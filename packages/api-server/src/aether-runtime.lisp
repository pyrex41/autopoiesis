;;;; aether-runtime.lisp - Run a live agent from the AETHER spatial canvas.
;;;;
;;;; Spawns `rho --output-format stream-json -p <prompt>` as a subprocess,
;;;; parses its stream-json events, writes each into the snapshot store as
;;;; a new child snapshot, and broadcasts each new snapshot to subscribers
;;;; of the WebSocket channel "aether:snapshots".
;;;;
;;;; The minimum "this is a real tool" round-trip:
;;;;   POST /api/aether/spawn  → returns {session_id, initial_snapshot_id}
;;;;   WS subscribe "aether:snapshots" → receives aether_snapshot frames
;;;;
;;;; Text-delta events from rho are buffered and flushed as one snapshot
;;;; per ~800ms (or per ~80 chars, or on any non-delta event) so we don't
;;;; create one snapshot per token.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Session table
;;; ===================================================================

(defvar *aether-sessions* (make-hash-table :test 'equal)
  "session-id (string) → aether-session struct")

(defvar *aether-sessions-lock* (bordeaux-threads:make-lock "aether-sessions"))

;;; ===================================================================
;;; Filesystem capture
;;; ===================================================================

(defvar *aether-content-store* nil
  "Single shared content-store for AETHER snapshot filesystem blobs.
   Currently in-process only — blobs do NOT survive SBCL restart.
   On-disk persistence (LMDB) is a follow-up.")

(defun ensure-aether-content-store ()
  (or *aether-content-store*
      (setf *aether-content-store*
            (autopoiesis.snapshot:make-content-store))))

(defparameter *fs-scan-exclude*
  '(".git" "node_modules" "__pycache__" ".venv" "venv" "dist" "build"
    "target" ".next" ".cache" ".DS_Store")
  "Directory prefixes excluded from working-dir scans. Skip the things
   nobody actually wants to checkpoint.")

(defun should-capture-fs-p (event-type)
  "Re-scan only on events that could plausibly have changed disk state.
   Everything else inherits the previous scan's entries on this session
   — same Merkle root, blob-store unchanged."
  (or (string= event-type "prompt")
      (string= event-type "tool_result")
      (string= event-type "complete")
      (string= event-type "error")))

(defun capture-tree-entries (session event-type)
  "Either re-scan the session's cwd (returning fresh entries) or hand back
   the entries from the previous capture. nil if no cwd is configured."
  (let ((cwd (aether-session-cwd session)))
    (cond
      ((or (null cwd) (zerop (length cwd))) nil)
      ((not (should-capture-fs-p event-type))
       (aether-session-last-tree-entries session))
      ((not (probe-file (uiop:ensure-directory-pathname cwd)))
       (aether-session-last-tree-entries session))
      (t
       (handler-case
           (let ((entries (autopoiesis.snapshot:scan-directory-flat
                           (uiop:ensure-directory-pathname cwd)
                           (ensure-aether-content-store)
                           :exclude *fs-scan-exclude*)))
             (setf (aether-session-last-tree-entries session) entries)
             entries)
         (error (e)
           (log:warn "aether: FS scan failed for ~A: ~A" cwd e)
           (aether-session-last-tree-entries session)))))))

(defstruct aether-session
  id                          ; "ses-XXXXXXXX"
  prompt
  model
  cwd                         ; working directory for rho (-C); nil = inherit
  lineage-name                ; consistent across all snapshots of this session
  parent-snapshot-id          ; nil for fresh sessions, set for forks
  current-snapshot-id         ; latest snapshot in this session (next parent)
  event-count                 ; monotonic counter, drives `ticks` metadata
  thread                      ; the bt:thread running the subprocess
  started-at                  ; universal-time when spawned
  status                      ; :running | :complete | :error
  error-message               ; populated when status = :error
  ;; Text-delta buffer
  delta-buffer                ; string accumulator
  delta-last-flush            ; internal-real-time of last flush
  ;; Filesystem capture — sticky across events; only re-scanned when an
  ;; event could have changed disk state (prompt, tool_result, complete).
  last-tree-entries)          ; sorted list of tree entries from last scan

;;; ===================================================================
;;; Utilities
;;; ===================================================================

(defun find-rho-executable ()
  "Find the rho binary in PATH. Falls back to ~/.local/bin/rho then 'rho'."
  (or (handler-case
          (let ((p (uiop:run-program "which rho"
                                     :output '(:string :stripped t)
                                     :ignore-error-status t)))
            (when (and p (not (string= "" p))) p))
        (error () nil))
      (when (probe-file (merge-pathnames ".local/bin/rho" (user-homedir-pathname)))
        (namestring (merge-pathnames ".local/bin/rho" (user-homedir-pathname))))
      "rho"))

(defun new-aether-session-id ()
  (format nil "ses-~(~A~)"
          (subseq (autopoiesis.core:make-uuid) 0 8)))

(defun lineage-name-from-session (session-id)
  (format nil "live-~A" (subseq session-id 4)))

(defun truncate-text (text max-len)
  (if (and text (> (length text) max-len))
      (concatenate 'string (subseq text 0 max-len) "…")
      (or text "")))

(defun event-mood (event-type has-text-p)
  "Map a rho event-type to a spectral mood.
   rho emits: session / text_delta / tool_start / tool_result / complete / error."
  (cond
    ((string= event-type "session")     "explorer")  ; birth event
    ((string= event-type "text_delta")  "linear")    ; ongoing thought
    ((string= event-type "tool_start")  "explorer")  ; reaching out
    ((string= event-type "tool_result") "reflector") ; what came back
    ((string= event-type "complete")    "reflector") ; settled
    ((string= event-type "error")       "reflector")
    (has-text-p                          "linear")
    (t                                   "linear")))

;;; ===================================================================
;;; Snapshot creation + broadcast
;;; ===================================================================

(defun aether-snapshot (session event-type text)
  "Create + save + broadcast one snapshot for SESSION. Returns the snapshot."
  (let* ((depth (aether-session-event-count session))
         (lineage (aether-session-lineage-name session))
         (tree-entries (capture-tree-entries session event-type))
         (file-count (length (or tree-entries '())))
         (metadata (list :lineage lineage
                         :mood (event-mood event-type (and text (> (length text) 0)))
                         :event-type event-type
                         :session (aether-session-id session)
                         :ticks depth
                         :depth depth
                         :text (truncate-text text 240)
                         :cwd (or (aether-session-cwd session) "")
                         :files file-count))
         (state (list :aether-event
                      :event-type event-type
                      :text text
                      :session (aether-session-id session)
                      :tick depth))
         (parent (aether-session-current-snapshot-id session))
         (snap (autopoiesis.snapshot:make-snapshot
                state
                :parent parent
                :metadata metadata
                :tree-entries tree-entries)))
    (autopoiesis.snapshot:save-snapshot snap)
    (setf (aether-session-current-snapshot-id session)
          (autopoiesis.snapshot:snapshot-id snap))
    (incf (aether-session-event-count session))
    (broadcast-aether-snapshot snap)
    snap))

(defun broadcast-aether-snapshot (snap)
  "Push a new-snapshot frame to all WS subscribers of channel aether:snapshots.
   Uses cl-json (same encoder as REST responses) so the frontend sees an
   identical shape between GET /api/snapshots and a live WS push."
  (handler-case
      (let ((payload (cl-json:encode-json-to-string
                      `((:type . "aether_snapshot")
                        (:snapshot . ,(snapshot-summary-alist snap))))))
        (broadcast-message payload :subscription-type "aether:snapshots"))
    (error (e)
      (log:warn "aether: broadcast failed: ~A" e))))

;;; ===================================================================
;;; Text-delta buffer / flush
;;; ===================================================================

(defconstant +delta-flush-interval-internal+
  (* internal-time-units-per-second 8/10)
  "Flush the delta buffer after this many internal-time units.")

(defconstant +delta-flush-chars+ 80
  "Flush the delta buffer once it grows past this many characters.")

(defun flush-delta-buffer (session &key (force nil))
  "If the buffer has content, emit a text_delta snapshot and clear."
  (let ((buf (aether-session-delta-buffer session)))
    (when (and (or force (> (length buf) 0)) (> (length buf) 0))
      (aether-snapshot session "text_delta" buf)
      (setf (aether-session-delta-buffer session) "")
      (setf (aether-session-delta-last-flush session)
            (get-internal-real-time)))))

(defun maybe-flush-delta-buffer (session)
  (let* ((buf (aether-session-delta-buffer session))
         (since (- (get-internal-real-time)
                   (aether-session-delta-last-flush session))))
    (when (or (>= (length buf) +delta-flush-chars+)
              (>= since +delta-flush-interval-internal+))
      (flush-delta-buffer session))))

;;; ===================================================================
;;; rho subprocess + stream-json loop
;;; ===================================================================

(defun handle-rho-event (session event)
  "Dispatch one parsed rho event (a hash-table) into the snapshot stream."
  (let* ((event-type (gethash "type" event))
         (text (gethash "text" event)))
    (cond
      ;; Stream tokens — buffer
      ((string= event-type "text_delta")
       (when text
         (setf (aether-session-delta-buffer session)
               (concatenate 'string
                            (aether-session-delta-buffer session)
                            text)))
       (maybe-flush-delta-buffer session))
      ;; All other events flush any buffered text first, then snapshot.
      (t
       (flush-delta-buffer session :force t)
       (let ((payload
               (cond
                 (text text)
                 ;; rho session start: {session_id, type}
                 ((string= event-type "session")
                  (format nil "rho session ~A"
                          (or (gethash "session_id" event) "?")))
                 ;; rho tool invocation: {tool_name, input_summary, tool_id, type}
                 ((string= event-type "tool_start")
                  (format nil "~A(~A)"
                          (or (gethash "tool_name" event) "tool")
                          (truncate-text (or (gethash "input_summary" event) "") 120)))
                 ;; rho tool return: {tool_name, success, tool_id, type}
                 ((string= event-type "tool_result")
                  (format nil "~A → ~A"
                          (or (gethash "tool_name" event) "tool")
                          (if (gethash "success" event) "ok" "failed")))
                 ;; rho completion: {session_id, success, type}
                 ((string= event-type "complete")
                  (if (gethash "success" event) "completed" "failed"))
                 ;; Unknown event type — show the type at least.
                 (t (format nil "[~A]" event-type)))))
         (aether-snapshot session event-type payload))))))

(defun run-rho-thread (session)
  "Body of the subprocess thread. Reads stream-json line by line."
  (let* ((exe (find-rho-executable))
         ;; rho-cli uses positional or -p; positional is safer with embedded args
         (base-args (list "-p" (aether-session-prompt session)
                          "--output-format" "stream-json"
                          "--model" (aether-session-model session)))
         (args (let ((cwd (aether-session-cwd session)))
                 (if (and cwd (> (length cwd) 0))
                     (append (list "-C" cwd) base-args)
                     base-args)))
         (cmd (format nil "~A ~{~A~^ ~}"
                      exe
                      (mapcar (lambda (s) (format nil "'~A'"
                                                   (with-output-to-string (out)
                                                     (loop for c across s
                                                           do (if (char= c #\')
                                                                  (write-string "'\\''" out)
                                                                  (write-char c out))))))
                              args))))
    (handler-case
        (let ((process (sb-ext:run-program "/bin/sh"
                                           (list "-c" (format nil "~A </dev/null" cmd))
                                           :output :stream
                                           :error :output
                                           :wait nil)))
          (unwind-protect
              (let ((stdout (sb-ext:process-output process)))
                (loop for line = (read-line stdout nil :eof)
                      until (eq line :eof)
                      when (and line (> (length line) 0) (char= (char line 0) #\{))
                      do (handler-case
                             (let ((event (com.inuoe.jzon:parse line)))
                               (handle-rho-event session event))
                           (error (e)
                             (log:warn "aether: bad event line '~A': ~A" line e))))
                (flush-delta-buffer session :force t)
                (setf (aether-session-status session) :complete))
            (when process
              (sb-ext:process-wait process)
              (sb-ext:process-close process))))
      (error (e)
        (setf (aether-session-status session) :error)
        (setf (aether-session-error-message session) (format nil "~A" e))
        (flush-delta-buffer session :force t)
        (handler-case (aether-snapshot session "error" (format nil "~A" e))
          (error () nil))
        (log:warn "aether: rho thread error: ~A" e)))))

;;; ===================================================================
;;; Public entry — spawn
;;; ===================================================================

(defun spawn-aether-session (&key prompt parent model cwd)
  "Spawn a new live agent session. Returns (values session initial-snapshot).
   PROMPT is required. PARENT is an optional parent snapshot id. MODEL
   defaults to claude-haiku. CWD, when given, is passed to rho as -C
   (the agent's working directory) — important when running tasks that
   touch the filesystem so they don't write into the caller's tree."
  (unless (and prompt (> (length prompt) 0))
    (error "spawn-aether-session: prompt is required"))
  (let* ((session-id (new-aether-session-id))
         (lineage (lineage-name-from-session session-id))
         (session (make-aether-session
                   :id session-id
                   :prompt prompt
                   :model (or model "claude-haiku")
                   :cwd cwd
                   :lineage-name lineage
                   :parent-snapshot-id parent
                   :current-snapshot-id parent
                   :event-count 0
                   :started-at (get-universal-time)
                   :status :running
                   :delta-buffer ""
                   :delta-last-flush (get-internal-real-time))))
    ;; Record this session in the table immediately so callers / listings
    ;; can see it before the first snapshot writes.
    (bordeaux-threads:with-lock-held (*aether-sessions-lock*)
      (setf (gethash session-id *aether-sessions*) session))
    ;; Initial "prompt" snapshot — root of this session's lineage on the map.
    (let ((initial (aether-snapshot session "prompt" prompt)))
      ;; Spawn the rho thread; it writes subsequent snapshots as events arrive.
      (setf (aether-session-thread session)
            (bordeaux-threads:make-thread
             (lambda () (run-rho-thread session))
             :name (format nil "aether-rho-~A" session-id)))
      (values session initial))))

(defun list-aether-sessions ()
  "Return a snapshot of current sessions as a list of plists."
  (bordeaux-threads:with-lock-held (*aether-sessions-lock*)
    (loop for s being the hash-values of *aether-sessions*
          collect (list :id (aether-session-id s)
                        :prompt (truncate-text (aether-session-prompt s) 100)
                        :model (aether-session-model s)
                        :status (string-downcase (symbol-name (aether-session-status s)))
                        :started-at (aether-session-started-at s)
                        :event-count (aether-session-event-count s)
                        :current-snapshot-id (aether-session-current-snapshot-id s)))))

;;; ===================================================================
;;; REST route handler
;;; ===================================================================

(defun snapshot-cwd (snap)
  "Read the captured cwd from a snapshot's metadata, or nil."
  (let* ((md (autopoiesis.snapshot:snapshot-metadata snap))
         (cwd (getf md :cwd)))
    (when (and cwd (> (length cwd) 0)) cwd)))

(defun files-listing-for (snap)
  "Build a JSON-friendly summary of the FS tree captured at SNAP."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap)))
    `((:snapshot_id . ,(autopoiesis.snapshot:snapshot-id snap))
      (:tree_root . ,(or (autopoiesis.snapshot:snapshot-tree-root snap) ""))
      (:cwd . ,(or (snapshot-cwd snap) ""))
      (:count . ,(length (or entries '())))
      (:files . ,(loop for e in (or entries '())
                       when (eq (autopoiesis.snapshot:entry-type e) :file)
                       collect `((:path . ,(autopoiesis.snapshot:entry-path e))
                                 (:size . ,(or (autopoiesis.snapshot:entry-size e) 0))
                                 (:hash . ,(or (autopoiesis.snapshot:entry-hash e) ""))))))))

(defun checkout-snapshot-to (snap target-dir)
  "Materialize SNAP's tree-entries into TARGET-DIR. Returns the count of
   entries written. Destructive — clears TARGET-DIR contents first (but
   does NOT delete the directory itself; .git etc. are left alone).
   nil tree-entries is valid and means 'clear the directory'."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap))
        (target (uiop:ensure-directory-pathname target-dir))
        (store (ensure-aether-content-store)))
    (ensure-directories-exist target)
    ;; Clear existing files/dirs in target (mirrors local-backend approach).
    (dolist (f (uiop:directory-files target))
      (ignore-errors (delete-file f)))
    (dolist (d (uiop:subdirectories target))
      (let ((name (car (last (pathname-directory d)))))
        ;; Don't recurse into excluded dirs — leave .git etc. alone.
        (unless (member name *fs-scan-exclude* :test #'string=)
          (ignore-errors (uiop:delete-directory-tree d :validate t)))))
    (if entries
        (autopoiesis.snapshot:materialize-tree entries target store)
        0)))

(defun rest-handle-aether (request)
  "Dispatch /api/aether/* requests."
  (let ((method (hunchentoot:request-method request))
        (uri (hunchentoot:request-uri request)))
    ;; Strip query string
    (let ((qpos (position #\? uri)))
      (when qpos (setf uri (subseq uri 0 qpos))))
    (cond
      ;; POST /api/aether/spawn
      ((and (eq method :post) (string= uri "/api/aether/spawn"))
       (require-permission :write)
       (let* ((body (parse-json-body))
              (prompt (cdr (assoc :prompt body)))
              (parent (cdr (assoc :parent body)))
              (model (cdr (assoc :model body)))
              (cwd (cdr (assoc :cwd body))))
         (cond
           ((or (null prompt) (string= prompt ""))
            (json-error "prompt is required" :status 400 :error-type "Bad Request"))
           (t
            (handler-case
                (multiple-value-bind (session initial)
                    (spawn-aether-session :prompt prompt
                                          :parent parent
                                          :model model
                                          :cwd cwd)
                  (json-ok
                   (list (cons :session_id (aether-session-id session))
                         (cons :initial_snapshot_id
                               (autopoiesis.snapshot:snapshot-id initial))
                         (cons :lineage (aether-session-lineage-name session))
                         (cons :model (aether-session-model session)))))
              (error (e)
                (json-error (format nil "spawn failed: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; GET /api/aether/sessions
      ((and (eq method :get) (string= uri "/api/aether/sessions"))
       (require-permission :read)
       (json-ok (list-aether-sessions)))
      ;; GET /api/aether/snapshots/:id/files
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/snapshots/[^/]+/files$" uri))
       (require-permission :read)
       (let* ((id (cl-ppcre:register-groups-bind (sid)
                      ("^/api/aether/snapshots/([^/]+)/files$" uri)
                    sid))
              (snap (autopoiesis.snapshot:load-snapshot id)))
         (cond ((null snap) (json-not-found "Snapshot" id))
               (t (json-ok (files-listing-for snap))))))
      ;; POST /api/aether/snapshots/:id/checkout
      ;; Body (optional): {"target": "/abs/path"} — falls back to the cwd
      ;; the snapshot was captured at.
      ((and (eq method :post)
            (cl-ppcre:scan "^/api/aether/snapshots/[^/]+/checkout$" uri))
       (require-permission :write)
       (let* ((id (cl-ppcre:register-groups-bind (sid)
                      ("^/api/aether/snapshots/([^/]+)/checkout$" uri)
                    sid))
              (snap (autopoiesis.snapshot:load-snapshot id)))
         (cond
           ((null snap) (json-not-found "Snapshot" id))
           (t
            (let* ((body (parse-json-body))
                   (req-target (cdr (assoc :target body)))
                   (target (or req-target (snapshot-cwd snap))))
              (cond
                ((or (null target) (zerop (length target)))
                 (json-error
                  "Snapshot has no captured cwd; specify target in body."
                  :status 400 :error-type "Bad Request"))
                (t
                 (handler-case
                     (let ((count (checkout-snapshot-to snap target)))
                       (json-ok
                        (list (cons :snapshot_id id)
                              (cons :target target)
                              (cons :entries_written count))))
                   (error (e)
                     (json-error (format nil "checkout failed: ~A" e)
                                 :status 500 :error-type "Internal Error"))))))))))
      ;; Unknown
      (t
       (json-not-found "AETHER route" uri)))))
