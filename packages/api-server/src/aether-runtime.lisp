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

(defstruct aether-session
  id                          ; "ses-XXXXXXXX"
  prompt
  model
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
  delta-last-flush)           ; internal-real-time of last flush

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
  "Map a rho event-type to a spectral mood."
  (cond
    ((string= event-type "session")     "explorer")  ; birth event
    ((string= event-type "text_delta")  "linear")    ; ongoing thought
    ((string= event-type "tool_use")    "explorer")  ; reaching out
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
         (metadata (list :lineage lineage
                         :mood (event-mood event-type (and text (> (length text) 0)))
                         :event-type event-type
                         :session (aether-session-id session)
                         :ticks depth
                         :depth depth
                         :text (truncate-text text 240)))
         (state (list :aether-event
                      :event-type event-type
                      :text text
                      :session (aether-session-id session)
                      :tick depth))
         (parent (aether-session-current-snapshot-id session))
         (snap (autopoiesis.snapshot:make-snapshot state
                                                    :parent parent
                                                    :metadata metadata)))
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
       (let ((payload (cond
                        (text text)
                        ((string= event-type "tool_use")
                         (format nil "tool: ~A" (gethash "name" event)))
                        ((string= event-type "tool_result")
                         (truncate-text (princ-to-string (gethash "result" event)) 200))
                        ((string= event-type "complete")
                         (if (gethash "success" event) "completed" "failed"))
                        (t (princ-to-string event)))))
         (aether-snapshot session event-type payload))))))

(defun run-rho-thread (session)
  "Body of the subprocess thread. Reads stream-json line by line."
  (let* ((exe (find-rho-executable))
         ;; rho-cli uses positional or -p; positional is safer with embedded args
         (args (list "-p" (aether-session-prompt session)
                     "--output-format" "stream-json"
                     "--model" (aether-session-model session)))
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

(defun spawn-aether-session (&key prompt parent model)
  "Spawn a new live agent session. Returns (values session initial-snapshot).
   PROMPT is required. PARENT is an optional parent snapshot id. MODEL
   defaults to claude-haiku."
  (unless (and prompt (> (length prompt) 0))
    (error "spawn-aether-session: prompt is required"))
  (let* ((session-id (new-aether-session-id))
         (lineage (lineage-name-from-session session-id))
         (session (make-aether-session
                   :id session-id
                   :prompt prompt
                   :model (or model "claude-haiku")
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
              (model (cdr (assoc :model body))))
         (cond
           ((or (null prompt) (string= prompt ""))
            (json-error "prompt is required" :status 400 :error-type "Bad Request"))
           (t
            (handler-case
                (multiple-value-bind (session initial)
                    (spawn-aether-session :prompt prompt
                                          :parent parent
                                          :model model)
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
      ;; Unknown
      (t
       (json-not-found "AETHER route" uri)))))
