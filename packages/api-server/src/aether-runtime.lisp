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
   The in-memory hash-table is the fast path; aether-blob-store.lisp
   mirrors every captured blob out to an LMDB env at
   *aether-blob-store-path* so checkouts survive SBCL restart.")

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
           (let* ((store (ensure-aether-content-store))
                  (entries (autopoiesis.snapshot:scan-directory-flat
                            (uiop:ensure-directory-pathname cwd)
                            store
                            :exclude *fs-scan-exclude*)))
             (setf (aether-session-last-tree-entries session) entries)
             ;; Mirror any newly-stored blobs out to LMDB so they survive
             ;; SBCL restart. Cheap when nothing changed (already-persisted
             ;; hashes are skipped by persist-content-store-blobs).
             (ignore-errors (persist-content-store-blobs store))
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
   nil tree-entries is valid and means 'clear the directory'.

   Hydrates missing blobs from LMDB into the in-memory content-store first,
   so checkouts of pre-restart snapshots still find their file contents."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap))
        (target (uiop:ensure-directory-pathname target-dir))
        (store (ensure-aether-content-store)))
    (when entries
      (ignore-errors
        (hydrate-content-store-blobs store (tree-entry-hashes entries))))
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

;;; ===================================================================
;;; Per-line file blame (aether-blame)
;;; ===================================================================
;;;
;;; For any file at any snapshot, walk back through the same lineage and
;;; attribute each line to the EARLIEST ancestor whose tree contained that
;;; exact line. Think `git blame` over cognitive ancestry — clicking a
;;; line tells you which agent reasoning event (= which star) introduced it.

(defun blob-as-string (content-store hash)
  "Fetch BLOB at HASH from CONTENT-STORE and decode as UTF-8.
   Returns nil if the blob is missing. Returns the decoded string otherwise
   (or, on a decode error, an empty string — we never crash blame on binary)."
  (let ((bytes (autopoiesis.snapshot:store-get-blob content-store hash)))
    (when bytes
      (handler-case (babel:octets-to-string bytes :encoding :utf-8)
        (error () "")))))

(defun split-lines (text)
  "Split TEXT on #\\Newline, preserving order. The last element is empty
   when TEXT ends with a newline — that matches how we want to display
   line counts (one entry per actual line in the file)."
  (when text
    (let ((lines '())
          (start 0)
          (len (length text)))
      (loop for i from 0 below len
            when (char= (char text i) #\Newline)
              do (push (subseq text start i) lines)
                 (setf start (1+ i)))
      (push (subseq text start len) lines)
      (nreverse lines))))

(defun file-lines-from-snapshot (snap path)
  "Return the list of UTF-8-decoded lines for PATH at SNAP, or nil if PATH
   is not present in SNAP's tree (or SNAP has no tree-entries at all)."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap)))
    (when entries
      (let ((entry (find-if (lambda (e)
                              (and (eq (autopoiesis.snapshot:entry-type e) :file)
                                   (string= (autopoiesis.snapshot:entry-path e) path)))
                            entries)))
        (when entry
          (let ((text (blob-as-string (ensure-aether-content-store)
                                       (autopoiesis.snapshot:entry-hash entry))))
            (and text (split-lines text))))))))

(defun snapshot-lineage (snap)
  "Return the :lineage metadata value (string) for SNAP, or nil."
  (let ((md (autopoiesis.snapshot:snapshot-metadata snap)))
    (and md (getf md :lineage))))

(defun walk-lineage-ancestors (snap)
  "Walk from SNAP back along parent pointers, collecting snapshots that
   share SNAP's :lineage metadata. Returns the list ordered oldest → newest
   (so [0] is the lineage root and [last] is SNAP itself). Snapshots from
   other lineages are not included — blame stays meaningful by staying
   inside one lineage chain."
  (let ((target-lineage (snapshot-lineage snap))
        (chain '())
        (cur snap)
        (max-walk 10000))
    (loop for n from 0 below max-walk
          while cur
          do (let ((lin (snapshot-lineage cur)))
               (if (or (null target-lineage)
                       (and lin (string= lin target-lineage)))
                   (push cur chain)
                   ;; Different lineage — stop walking. The DAG can fork
                   ;; into a new live-XXX session and that's a hard boundary
                   ;; for attribution.
                   (return)))
             (let ((pid (autopoiesis.snapshot:snapshot-parent cur)))
               (setf cur (and pid (autopoiesis.snapshot:load-snapshot pid)))))
    chain))

(defun compute-blame (snap path)
  "For each line of PATH at SNAP, find the earliest ancestor whose copy of
   PATH already contained that exact line. Returns a list of plists, one
   per line, each with keys :line :text :origin-snapshot :origin-event-type
   :origin-timestamp :origin-lineage. Returns nil if PATH is not in SNAP.

   Algorithm: collect the lineage chain oldest→newest, hash each ancestor's
   line set, then for each current line find the first ancestor that
   already contained it. If no ancestor had it, the origin is SNAP itself."
  (let ((current-lines (file-lines-from-snapshot snap path)))
    (unless current-lines
      (return-from compute-blame nil))
    (let* ((chain (walk-lineage-ancestors snap))
           ;; Precompute (ancestor . line-set) pairs, skipping ancestors
           ;; that don't include PATH in their tree.
           (ancestor-line-sets
             (loop for a in chain
                   for lines = (file-lines-from-snapshot a path)
                   when lines
                   collect (let ((set (make-hash-table :test 'equal)))
                             (dolist (l lines) (setf (gethash l set) t))
                             (cons a set)))))
      (loop for line in current-lines
            for idx from 1
            for origin = (or (loop for (anc . line-set) in ancestor-line-sets
                                   when (gethash line line-set)
                                   return anc)
                             ;; Fallback: SNAP itself is the origin.
                             snap)
            collect (let ((md (autopoiesis.snapshot:snapshot-metadata origin)))
                      (list :line idx
                            :text line
                            :origin-snapshot (autopoiesis.snapshot:snapshot-id origin)
                            :origin-event-type (or (getf md :event-type) "")
                            :origin-timestamp (or (autopoiesis.snapshot:snapshot-timestamp origin) 0)
                            :origin-lineage (or (getf md :lineage) "")))))))

(defun blame-result-alist (snap path blames)
  "Build the JSON response body for /blame."
  `((:snapshot_id . ,(autopoiesis.snapshot:snapshot-id snap))
    (:path . ,path)
    (:line_count . ,(length blames))
    (:blames . ,(coerce
                 (loop for b in blames
                       collect `((:line . ,(getf b :line))
                                 (:text . ,(getf b :text))
                                 (:origin_snapshot . ,(getf b :origin-snapshot))
                                 (:origin_event_type . ,(getf b :origin-event-type))
                                 (:origin_timestamp . ,(getf b :origin-timestamp))
                                 (:origin_lineage . ,(getf b :origin-lineage))))
                 'vector))))

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
      ;; GET /api/aether/blame/:snapshot-id/:url-encoded-path
      ;; Per-line file ancestry. Walks the lineage chain from the snapshot
      ;; backward, attributing each line of the file to the earliest
      ;; ancestor whose tree already contained that exact line.
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/blame/[^/]+/.+$" uri))
       (require-permission :read)
       (cl-ppcre:register-groups-bind (sid encoded-path)
           ("^/api/aether/blame/([^/]+)/(.+)$" uri)
         (let* ((path (handler-case (hunchentoot:url-decode encoded-path)
                        (error () encoded-path)))
                (snap (autopoiesis.snapshot:load-snapshot sid)))
           (cond
             ((null snap) (json-not-found "Snapshot" sid))
             ((null (autopoiesis.snapshot:snapshot-tree-entries snap))
              (json-not-found "Snapshot has no tree" sid))
             (t
              (handler-case
                  (let ((blames (compute-blame snap path)))
                    (cond
                      ((null blames)
                       (json-not-found "File in snapshot" path))
                      (t (json-ok (blame-result-alist snap path blames)))))
                (error (e)
                  (json-error (format nil "blame failed: ~A" e)
                              :status 500 :error-type "Internal Error"))))))))
      ;; Unknown
      (t
       (json-not-found "AETHER route" uri)))))
