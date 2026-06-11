;;;; provider-codex-appserver.lisp - Long-lived Codex app-server provider
;;;;
;;;; Ports Symphony's `codex app-server` JSON-RPC 2.0 client into Common Lisp.
;;;;
;;;; Unlike provider-codex (one-shot `codex exec`) and provider-rho (per-turn
;;;; `--resume`), this provider spawns `codex app-server` ONCE as a long-lived
;;;; subprocess and speaks JSON-RPC 2.0 over its stdio, pushing multiple turns
;;;; into the SAME thread (session) and streaming events back per turn.
;;;;
;;;; Protocol (confirmed against codex-cli 0.129.0 by observing live stdio):
;;;;   - Framing: line-delimited JSON (NOT Content-Length). One JSON object per
;;;;     line on both directions. Requests carry "jsonrpc":"2.0","id":N,"method".
;;;;     Responses echo "id" + "result" or "id" + "error" (no "jsonrpc" echoed).
;;;;     Server-initiated notifications carry "method"+"params", no "id".
;;;;   - Handshake: initialize (id) -> initialized (notification)
;;;;       -> thread/start (id) returns {"thread":{"id":...}}  <-- the thread_id
;;;;   - thread/started notification mirrors the thread object.
;;;;   - turn/start (id) {threadId, input:[{type:"text",text:...}]} returns the
;;;;       turn; lifecycle streamed as notifications:
;;;;         turn/started, item/started, item/completed, ... then
;;;;         turn/completed (params.turn.status = "completed" | "failed").
;;;;       (turn/failed / turn/cancelled also exist as terminal methods.)
;;;;   - sandbox is a STRING enum: "read-only" | "workspace-write" |
;;;;       "danger-full-access".  approvalPolicy: "never"|"on-request"|...
;;;;   - Server may send approval REQUESTS (objects with both "id" and "method",
;;;;     e.g. item/commandExecution/requestApproval, item/fileChange/requestApproval,
;;;;     execCommandApproval, applyPatchApproval). We reply {id, result:{decision}}
;;;;     under an auto-approve policy, mirroring Symphony.
;;;;
;;;; Auth note: the default `model_provider` here is `cursor-headless`, a local
;;;; proxy on localhost:8000. The PROTOCOL works regardless; LLM turns only
;;;; succeed when that proxy is up & authed. See the test script for details.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Session object
;;; ═══════════════════════════════════════════════════════════════════

(defclass codex-appserver-session ()
  ((process :initarg :process :accessor codex-session-process :initform nil
            :documentation "uiop launch-program process-info for `codex app-server`.")
   (input :initarg :input :accessor codex-session-input :initform nil
          :documentation "stdin stream into the subprocess (we write requests here).")
   (output :initarg :output :accessor codex-session-output :initform nil
           :documentation "stdout stream from the subprocess (we read messages here).")
   (thread-id :initarg :thread-id :accessor codex-session-thread-id :initform nil
              :documentation "JSON-RPC thread id; reused across turns (the session).")
   (cwd :initarg :cwd :accessor codex-session-cwd :initform nil
        :documentation "Working directory the agent operates in.")
   (model :initarg :model :accessor codex-session-model :initform nil
          :documentation "Model name reported by thread/start, or requested override.")
   (approval-policy :initarg :approval-policy :accessor codex-session-approval-policy
                    :initform "never")
   (sandbox :initarg :sandbox :accessor codex-session-sandbox
            :initform "workspace-write")
   (auto-approve :initarg :auto-approve :accessor codex-session-auto-approve :initform t
                 :documentation "When T, auto-approve approval requests with a session decision.")
   (next-id :initarg :next-id :accessor codex-session-next-id :initform 10
            :documentation "Monotonic counter for JSON-RPC request ids.")
   (lock :accessor codex-session-lock :initform (bt:make-recursive-lock "codex-appserver-session")))
  (:documentation "A live `codex app-server` JSON-RPC session. Holds the long-lived
subprocess and the reusable thread id."))

(defmethod print-object ((s codex-appserver-session) stream)
  (print-unreadable-object (s stream :type t)
    (format stream "thread=~a cwd=~a alive=~a"
            (codex-session-thread-id s)
            (codex-session-cwd s)
            (codex-session-alive-p s))))

(defun codex-session-alive-p (session)
  "Return T if the underlying app-server process is still running."
  (let ((p (codex-session-process session)))
    (and p (uiop:process-alive-p p))))

;;; ═══════════════════════════════════════════════════════════════════
;;; JSON-RPC framing (line-delimited)
;;; ═══════════════════════════════════════════════════════════════════

(defun %codex-next-id (session)
  (bt:with-recursive-lock-held ((codex-session-lock session))
    (incf (codex-session-next-id session))))

(defun %codex-send (session object)
  "Encode OBJECT as JSON and write it as one line to the subprocess stdin."
  (let ((line (cl-json:encode-json-to-string object))
        (in (codex-session-input session)))
    (write-string line in)
    (write-char #\Newline in)
    (force-output in))
  object)

(defun %codex-read-message (session &key (timeout 120))
  "Read & decode the next JSON message line from the subprocess stdout.
   Returns the decoded alist, or :EOF on stream close, or :TIMEOUT.
   Non-JSON lines (diagnostics) are skipped. TIMEOUT is in seconds."
  (let ((out (codex-session-output session))
        (deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (loop
      (when (> (get-internal-real-time) deadline)
        (return :timeout))
      ;; listen avoids blocking forever so the deadline can fire.
      (cond
        ((listen out)
         (let ((line (read-line out nil :eof)))
           (when (eq line :eof) (return :eof))
           (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
             (when (and (> (length trimmed) 0) (char= (char trimmed 0) #\{))
               (let ((msg (ignore-errors (cl-json:decode-json-from-string trimmed))))
                 (when msg (return msg)))))))
        (t
         ;; Nothing buffered yet. If the process died, surface EOF.
         (unless (codex-session-alive-p session)
           ;; Drain any final line that may have arrived between checks.
           (let ((line (read-line out nil :eof)))
             (if (eq line :eof)
                 (return :eof)
                 (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
                   (when (and (> (length trimmed) 0) (char= (char trimmed 0) #\{))
                     (let ((msg (ignore-errors (cl-json:decode-json-from-string trimmed))))
                       (when msg (return msg))))))))
         (sleep 0.01))))))

(defun %codex-await-response (session request-id &key (timeout 120))
  "Read messages until one with matching REQUEST-ID arrives.
   Returns (values RESULT-ALIST ERROR-ALIST). Notifications encountered while
   waiting are ignored (the handshake phase has no streamed events of interest).
   On timeout/EOF, signals an error."
  (loop
    (let ((msg (%codex-read-message session :timeout timeout)))
      (cond
        ((eq msg :timeout)
         (error 'autopoiesis.core:autopoiesis-error
                :message (format nil "codex app-server: timeout awaiting response id=~a" request-id)))
        ((eq msg :eof)
         (error 'autopoiesis.core:autopoiesis-error
                :message (format nil "codex app-server: process closed while awaiting id=~a" request-id)))
        (t
         (let ((id (cdr (assoc :id msg))))
           (when (eql id request-id)
             (let ((err (cdr (assoc :error msg))))
               (if err
                   (return (values nil err))
                   (return (values (cdr (assoc :result msg)) nil)))))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session lifecycle: start / run-turn / stop
;;; ═══════════════════════════════════════════════════════════════════

(defun start-codex-session (&key cwd model
                              (approval-policy "never")
                              (sandbox "workspace-write")
                              (auto-approve t)
                              (command "codex")
                              extra-args
                              (timeout 60))
  "Spawn `codex app-server` as a long-lived subprocess and perform the JSON-RPC
   handshake: initialize -> initialized -> thread/start. Returns a live
   CODEX-APPSERVER-SESSION whose thread-id is reused across turns.

   CWD              - working directory the agent operates in (defaults to current).
   MODEL            - optional model override (passed via -c model=...).
   APPROVAL-POLICY  - codex approval policy string (default \"never\" = autonomous).
   SANDBOX          - \"read-only\" | \"workspace-write\" | \"danger-full-access\".
   AUTO-APPROVE     - auto-approve approval requests during turns.
   COMMAND          - codex executable (default \"codex\").
   EXTRA-ARGS       - extra args appended after `app-server`.
   TIMEOUT          - seconds to wait for each handshake response."
  (let* ((cwd (or cwd (uiop:getcwd)))
         (cwd-str (namestring (truename cwd)))
         (args (append (list "app-server")
                       (when model (list "-c" (format nil "model=~s" model)))
                       extra-args))
         (process (uiop:launch-program
                   (cons command args)
                   :input :stream
                   :output :stream
                   :error-output :stream  ; keep stderr off our line stream
                   :directory cwd-str)))
    (let ((session (make-instance 'codex-appserver-session
                                  :process process
                                  :input (uiop:process-info-input process)
                                  :output (uiop:process-info-output process)
                                  :cwd cwd-str
                                  :model model
                                  :approval-policy approval-policy
                                  :sandbox sandbox
                                  :auto-approve auto-approve)))
      (handler-case
          (progn
            ;; 1. initialize
            ;; NOTE: capabilities must be a real object (per InitializeCapabilities
            ;; schema). cl-json renders an empty list/#() as null/[], which the
            ;; server rejects — so we send explicit fields.
            (%codex-send session
                         `(("jsonrpc" . "2.0")
                           ("id" . 1)
                           ("method" . "initialize")
                           ("params" . (("capabilities" . (("experimentalApi" . t)
                                                           ("optOutNotificationMethods" . nil)))
                                        ("clientInfo" . (("name" . "autopoiesis")
                                                         ("title" . "Autopoiesis Orchestrator")
                                                         ("version" . "0.1.0")))))))
            (multiple-value-bind (result err) (%codex-await-response session 1 :timeout timeout)
              (declare (ignore result))
              (when err
                (error 'autopoiesis.core:autopoiesis-error
                       :message (format nil "codex initialize failed: ~a" err))))
            ;; 2. initialized notification (no id, no response expected).
            ;; params is optional; omitted because cl-json can't emit a bare {}.
            (%codex-send session
                         `(("jsonrpc" . "2.0")
                           ("method" . "initialized")))
            ;; 3. thread/start
            (%codex-send session
                         `(("jsonrpc" . "2.0")
                           ("id" . 2)
                           ("method" . "thread/start")
                           ("params" . (("cwd" . ,cwd-str)
                                        ("approvalPolicy" . ,approval-policy)
                                        ("sandbox" . ,sandbox)))))
            (multiple-value-bind (result err) (%codex-await-response session 2 :timeout timeout)
              (when err
                (error 'autopoiesis.core:autopoiesis-error
                       :message (format nil "codex thread/start failed: ~a" err)))
              (let* ((thread (cdr (assoc :thread result)))
                     (thread-id (cdr (assoc :id thread)))
                     (rmodel (cdr (assoc :model result))))
                (unless thread-id
                  (error 'autopoiesis.core:autopoiesis-error
                         :message (format nil "codex thread/start: no thread id in ~a" result)))
                (setf (codex-session-thread-id session) thread-id)
                (when (and rmodel (not model))
                  (setf (codex-session-model session) rmodel))))
            session)
        (error (e)
          (ignore-errors (stop-codex-session session))
          (error e))))))

(defparameter *codex-approval-request-methods*
  '("item/commandExecution/requestApproval"
    "item/fileChange/requestApproval"
    "execCommandApproval"
    "applyPatchApproval")
  "Server->client request methods that expect an approval {decision} reply.")

(defun %codex-approval-decision-for (method)
  "Return the decision string codex expects for METHOD when auto-approving.
   Newer item/* requests use camelCase \"acceptForSession\"; legacy
   exec/applyPatch approvals use \"approved_for_session\"."
  (if (or (string= method "item/commandExecution/requestApproval")
          (string= method "item/fileChange/requestApproval"))
      "acceptForSession"
      "approved_for_session"))

(defun codex-run-turn (session prompt &key on-event (timeout 600))
  "Run ONE turn on SESSION's live thread (reusing the existing thread-id).
   Streams events to optional ON-EVENT (a function of one arg: a plist
   (:event KEYWORD :method STRING :params ALIST :raw ALIST)). Auto-approves
   approval requests when the session's auto-approve policy is on.

   Returns a PROVIDER-RESULT: text accumulated from agent message items,
   :turns 1, :session-id the thread-id, :metadata carrying :status, :usage,
   and :error (if the turn failed). Blocks until a terminal turn event.

   TIMEOUT - seconds to wait for the whole turn to complete."
  (unless (codex-session-thread-id session)
    (error 'autopoiesis.core:autopoiesis-error
           :message "codex-run-turn: session has no thread-id (not started?)"))
  (let* ((thread-id (codex-session-thread-id session))
         (turn-req-id (%codex-next-id session))
         (text-parts nil)
         (tool-calls nil)
         (usage nil)
         (status nil)
         (turn-error nil)
         (turn-id nil))
    (flet ((emit (event method params raw)
             (when on-event
               (ignore-errors
                 (funcall on-event (list :event event :method method
                                         :params params :raw raw))))))
      ;; Send turn/start. The response (matching turn-req-id) gives the turn id.
      ;; input is a JSON ARRAY of input items; each item is an object. We use a
      ;; vector for the array so cl-json can't mistake it for an alist, and
      ;; encode the single text item as {"type":"text","text":...}.
      (%codex-send session
                   `(("jsonrpc" . "2.0")
                     ("id" . ,turn-req-id)
                     ("method" . "turn/start")
                     ("params" . (("threadId" . ,thread-id)
                                  ("input" . ,(vector `(("type" . "text")
                                                        ("text" . ,prompt))))))))
      ;; Event loop: read messages until a terminal turn event.
      (loop
        (let ((msg (%codex-read-message session :timeout timeout)))
          (cond
            ((eq msg :timeout)
             (setf status "timeout"
                   turn-error "turn timed out waiting for completion")
             (return))
            ((eq msg :eof)
             (setf status "process-exit"
                   turn-error "app-server process closed mid-turn")
             (return))
            (t
             (let ((id (cdr (assoc :id msg)))
                   (method (cdr (assoc :method msg)))
                   (params (cdr (assoc :params msg)))
                   (err (cdr (assoc :error msg))))
               (cond
                 ;; Response to our turn/start request.
                 ((and (eql id turn-req-id) (not method))
                  (if err
                      (progn (setf status "failed"
                                   turn-error (format nil "turn/start error: ~a" err))
                             (return))
                      (let* ((result (cdr (assoc :result msg)))
                             (turn (cdr (assoc :turn result))))
                        (setf turn-id (cdr (assoc :id turn)))
                        (emit :turn-accepted method result msg))))

                 ;; Server-initiated REQUEST (has both id and method) =>
                 ;; approval or tool-call request needing a reply.
                 ((and id method)
                  (cond
                    ((member method *codex-approval-request-methods* :test #'string=)
                     (if (codex-session-auto-approve session)
                         (let ((decision (%codex-approval-decision-for method)))
                           (%codex-send session
                                        `(("id" . ,id)
                                          ("result" . (("decision" . ,decision)))))
                           (emit :approval-auto-approved method params msg))
                         (progn
                           (emit :approval-required method params msg)
                           ;; Cannot proceed without approval; deny politely.
                           (%codex-send session
                                        `(("id" . ,id)
                                          ("result" . (("decision" . "denied"))))))))
                    (t
                     ;; Unknown server request: reply with a benign empty result
                     ;; so the app-server is not left blocking on us.
                     (emit :server-request method params msg)
                     (%codex-send session
                                  `(("id" . ,id) ("result" . #()))))))

                 ;; Terminal turn events.
                 ((and method (string= method "turn/completed"))
                  (let* ((turn (cdr (assoc :turn params)))
                         (st (cdr (assoc :status turn)))
                         (terr (cdr (assoc :error turn)))
                         (u (or (cdr (assoc :usage turn)) (cdr (assoc :usage params)))))
                    (setf status (or st "completed"))
                    (when u (setf usage u))
                    (when terr
                      (setf turn-error (or (cdr (assoc :message terr)) (format nil "~a" terr))))
                    (emit :turn-completed method params msg)
                    (return)))
                 ((and method (string= method "turn/failed"))
                  (setf status "failed"
                        turn-error (or (cdr (assoc :message params)) (format nil "~a" params)))
                  (emit :turn-failed method params msg)
                  (return))
                 ((and method (string= method "turn/cancelled"))
                  (setf status "cancelled")
                  (emit :turn-cancelled method params msg)
                  (return))

                 ;; Streamed item lifecycle: accumulate agent text + tool calls.
                 ((and method (string= method "item/completed"))
                  (let* ((item (cdr (assoc :item params)))
                         (itype (cdr (assoc :type item))))
                    (cond
                      ((and itype (member itype '("agentMessage" "assistantMessage") :test #'string=))
                       (%codex-collect-item-text item #'(lambda (txt) (push txt text-parts))))
                      ((and itype (string= itype "toolCall"))
                       (push (list :name (cdr (assoc :name item))
                                   :id (cdr (assoc :id item))
                                   :input (cdr (assoc :arguments item)))
                             tool-calls)))
                    (emit :item-completed method params msg)))
                 ((and method (string= method "item/started"))
                  (emit :item-started method params msg))

                 ;; Any other notification: pass through.
                 (method
                  (let ((u (cdr (assoc :usage params))))
                    (when u (setf usage u)))
                  (emit :notification method params msg))

                 ;; Stray response with non-matching id: ignore.
                 (t nil)))))))
      (let ((result (make-provider-result
                     :provider-name "codex-app-server"
                     :text (format nil "~{~a~}" (nreverse text-parts))
                     :tool-calls (nreverse tool-calls)
                     :turns 1
                     :session-id thread-id
                     :exit-code (if (and status (string= status "completed")) 0 1)
                     :metadata (list :status status
                                     :turn-id turn-id
                                     :usage usage
                                     :error turn-error))))
        result))))

(defun %codex-collect-item-text (item collector)
  "Extract text fragments from a message ITEM's content list, calling COLLECTOR."
  (let ((content (cdr (assoc :content item))))
    (when (listp content)
      (dolist (part content)
        (let ((txt (cdr (assoc :text part))))
          (when txt (funcall collector txt)))))))

(defun stop-codex-session (session)
  "Cleanly shut down SESSION: close stdin (signals EOF to app-server), then
   terminate and reap the subprocess. Idempotent."
  (when session
    (let ((process (codex-session-process session)))
      (ignore-errors
        (when (codex-session-input session)
          (close (codex-session-input session))))
      (when process
        (ignore-errors (uiop:terminate-process process))
        (ignore-errors (uiop:wait-process process)))
      (setf (codex-session-process session) nil
            (codex-session-input session) nil
            (codex-session-output session) nil)))
  session)

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider integration (:codex-app-server long-lived streaming provider)
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Slots into the existing provider abstraction (see provider.lisp). It is a
;;; STREAMING provider: provider-start-session opens the app-server + thread,
;;; provider-send / provider-send-streaming push turns, provider-stop-session
;;; tears it down. provider-invoke (one-shot) transparently starts a session,
;;; runs one turn, and stops it.

(defclass codex-appserver-provider (provider)
  ((approval-policy :initarg :approval-policy :accessor codex-appserver-approval-policy
                    :initform "never"
                    :documentation "codex approval policy (default \"never\" = autonomous).")
   (sandbox :initarg :sandbox :accessor codex-appserver-sandbox
            :initform "workspace-write"
            :documentation "Sandbox mode: read-only|workspace-write|danger-full-access.")
   (auto-approve :initarg :auto-approve :accessor codex-appserver-auto-approve
                 :initform t
                 :documentation "Auto-approve approval requests during turns.")
   (session :initarg :session :accessor codex-appserver-provider-session :initform nil
            :documentation "The live CODEX-APPSERVER-SESSION, if started."))
  (:default-initargs :name "codex-app-server" :command "codex" :timeout 600)
  (:documentation "Long-lived `codex app-server` JSON-RPC provider. A single
subprocess + thread is reused across turns (true session persistence), unlike
the one-shot :codex provider."))

(defun make-codex-appserver-provider (&key (name "codex-app-server") (command "codex")
                                        working-directory default-model
                                        (max-turns 10) (timeout 600)
                                        env extra-args
                                        (approval-policy "never")
                                        (sandbox "workspace-write")
                                        (auto-approve t))
  "Create a codex-app-server provider instance."
  (make-instance 'codex-appserver-provider
                 :name name :command command
                 :working-directory working-directory
                 :default-model default-model
                 :max-turns max-turns :timeout timeout
                 :env env :extra-args extra-args
                 :approval-policy approval-policy
                 :sandbox sandbox
                 :auto-approve auto-approve))

(defmethod provider-supported-modes ((provider codex-appserver-provider))
  '(:one-shot :streaming))

(defmethod provider-alive-p ((provider codex-appserver-provider))
  (let ((s (codex-appserver-provider-session provider)))
    (and s (codex-session-alive-p s))))

(defmethod provider-start-session ((provider codex-appserver-provider))
  "Spawn `codex app-server` and start a thread. Stores the session on PROVIDER."
  (let ((session (start-codex-session
                  :cwd (provider-working-directory provider)
                  :model (provider-default-model provider)
                  :approval-policy (codex-appserver-approval-policy provider)
                  :sandbox (codex-appserver-sandbox provider)
                  :auto-approve (codex-appserver-auto-approve provider)
                  :command (provider-command provider)
                  :extra-args (provider-extra-args provider))))
    (setf (codex-appserver-provider-session provider) session
          (provider-session-id provider) (codex-session-thread-id session))
    provider))

(defmethod provider-send ((provider codex-appserver-provider) message)
  "Run one turn on the live thread. Starts a session lazily if needed."
  (unless (provider-alive-p provider)
    (provider-start-session provider))
  (codex-run-turn (codex-appserver-provider-session provider) message
                  :timeout (provider-timeout provider)))

(defmethod provider-send-streaming ((provider codex-appserver-provider) message on-text-delta)
  "Run one turn, invoking ON-TEXT-DELTA with each agent text fragment."
  (unless (provider-alive-p provider)
    (provider-start-session provider))
  (codex-run-turn
   (codex-appserver-provider-session provider) message
   :timeout (provider-timeout provider)
   :on-event
   (lambda (ev)
     (when (and on-text-delta (eq (getf ev :event) :item-completed))
       (let* ((params (getf ev :params))
              (item (cdr (assoc :item params)))
              (itype (cdr (assoc :type item))))
         (when (and itype (member itype '("agentMessage" "assistantMessage") :test #'string=))
           (%codex-collect-item-text item on-text-delta)))))))

(defmethod provider-stop-session ((provider codex-appserver-provider))
  "Shut down the app-server subprocess and clear session state."
  (when (codex-appserver-provider-session provider)
    (stop-codex-session (codex-appserver-provider-session provider))
    (setf (codex-appserver-provider-session provider) nil
          (provider-session-id provider) nil))
  provider)

(defmethod provider-invoke ((provider codex-appserver-provider) prompt
                            &key tools mode agent-id)
  "One-shot convenience: start a session, run one turn, stop. For multi-turn
   reuse, call provider-start-session + provider-send directly."
  (declare (ignore tools mode agent-id))
  (let ((own-session (not (provider-alive-p provider))))
    (when own-session (provider-start-session provider))
    (unwind-protect
         (codex-run-turn (codex-appserver-provider-session provider) prompt
                         :timeout (provider-timeout provider))
      (when own-session (provider-stop-session provider)))))

(defmethod provider-to-sexpr ((provider codex-appserver-provider))
  (append (call-next-method)
          (list :approval-policy (codex-appserver-approval-policy provider)
                :sandbox (codex-appserver-sandbox provider)
                :auto-approve (codex-appserver-auto-approve provider))))
