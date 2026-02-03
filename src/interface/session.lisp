;;;; session.lisp - CLI-based human interaction sessions
;;;;
;;;; Manages human-agent interaction sessions with CLI interface.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass session ()
  ((id :initarg :id
       :accessor session-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique session ID")
   (user :initarg :user
         :accessor session-user
         :documentation "Human user identifier")
   (agent :initarg :agent
          :accessor session-agent
          :documentation "Associated agent")
   (started :initarg :started
            :accessor session-started
            :initform (autopoiesis.core:get-precise-time)
            :documentation "When session started")
   (ended :initarg :ended
          :accessor session-ended
          :initform nil
          :documentation "When session ended")
   (navigator :initarg :navigator
              :accessor session-navigator
              :initform nil
              :documentation "Session's navigator")
   (viewport :initarg :viewport
             :accessor session-viewport
             :initform nil
             :documentation "Session's viewport")
   (command-history :initarg :command-history
                    :accessor session-command-history
                    :initform nil
                    :documentation "History of commands entered")
   (input-stream :initarg :input-stream
                 :accessor session-input-stream
                 :initform *standard-input*
                 :documentation "Input stream for human commands")
   (output-stream :initarg :output-stream
                  :accessor session-output-stream
                  :initform *standard-output*
                  :documentation "Output stream for display"))
  (:documentation "An interactive CLI session between human and agent"))

(defun make-session (user agent &key input-stream output-stream)
  "Create a new session."
  (make-instance 'session
                 :user user
                 :agent agent
                 :navigator (make-navigator)
                 :viewport (make-viewport)
                 :input-stream (or input-stream *standard-input*)
                 :output-stream (or output-stream *standard-output*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Lifecycle
;;; ═══════════════════════════════════════════════════════════════════

(defvar *active-sessions* (make-hash-table :test 'equal)
  "Currently active sessions.")

(defvar *current-session* nil
  "The current interactive session.")

(defun start-session (user agent &key input-stream output-stream)
  "Start a new interactive session."
  (let ((session (make-session user agent
                               :input-stream input-stream
                               :output-stream output-stream)))
    (setf (gethash (session-id session) *active-sessions*) session)
    (setf *current-session* session)
    session))

(defun end-session (session)
  "End a session."
  (setf (session-ended session) (autopoiesis.core:get-precise-time))
  (remhash (session-id session) *active-sessions*)
  (when (eq *current-session* session)
    (setf *current-session* nil))
  session)

(defun find-session (id)
  "Find a session by ID."
  (gethash id *active-sessions*))

(defun list-sessions ()
  "List all active sessions."
  (loop for session being the hash-values of *active-sessions*
        collect session))

;;; ═══════════════════════════════════════════════════════════════════
;;; CLI Display
;;; ═══════════════════════════════════════════════════════════════════

(defun cli-display-header (session)
  "Display the CLI header."
  (let ((out (session-output-stream session))
        (agent (session-agent session)))
    (format out "~&~%")
    (format out "========================================================================~%")
    (format out "  AUTOPOIESIS CLI - Agent: ~a (~a)~%"
            (autopoiesis.agent:agent-name agent)
            (subseq (autopoiesis.agent:agent-id agent) 0 8))
    (format out "  Status: ~a | Session: ~a~%"
            (autopoiesis.agent:agent-state agent)
            (subseq (session-id session) 0 8))
    (format out "========================================================================~%")
    (force-output out)))

(defun cli-display-state (session)
  "Display current agent state."
  (let* ((out (session-output-stream session))
         (agent (session-agent session))
         (viewport (session-viewport session))
         (ts (autopoiesis.agent:agent-thought-stream agent))
         (thoughts (autopoiesis.core:stream-thoughts ts))
         (recent-thoughts (if (> (length thoughts) 5)
                              (subseq thoughts (- (length thoughts) 5))
                              thoughts)))
    (format out "~%--- Agent State ---~%")
    (format out "Capabilities: ~{~a~^, ~}~%"
            (or (autopoiesis.agent:agent-capabilities agent) '("(none)")))
    (format out "~%--- Recent Thoughts (~a total) ---~%"
            (length thoughts))
    (if recent-thoughts
        (dolist (thought recent-thoughts)
          (format out "  [~8a] ~a~%"
                  (autopoiesis.core:thought-type thought)
                  (truncate-for-display
                   (format nil "~s" (autopoiesis.core:thought-content thought))
                   60)))
        (format out "  (no thoughts yet)~%"))
    (format out "~%--- Viewport (detail: ~a) ---~%"
            (viewport-detail-level viewport))
    (force-output out)))

(defun cli-display-help (session)
  "Display CLI help."
  (let ((out (session-output-stream session)))
    (format out "~&~%")
    (format out "Commands:~%")
    (format out "  help, h, ?     - Show this help~%")
    (format out "  status, s      - Show agent status~%")
    (format out "  start          - Start the agent~%")
    (format out "  stop           - Stop the agent~%")
    (format out "  pause          - Pause the agent~%")
    (format out "  resume         - Resume the agent~%")
    (format out "  step           - Execute one cognitive cycle~%")
    (format out "  thoughts       - Show all thoughts~%")
    (format out "  inject <text>  - Inject observation into agent~%")
    (format out "  detail +/-     - Increase/decrease detail level~%")
    (format out "  back, b        - Navigate back in history~%")
    (format out "  pending        - Show pending input requests~%")
    (format out "  respond <id> <value> - Respond to pending request~%")
    (format out "  quit, q        - End session~%")
    (format out "~%")
    (force-output out)))

(defun cli-display-prompt (session)
  "Display the CLI prompt."
  (let ((out (session-output-stream session)))
    (format out "~&> ")
    (force-output out)))

;;; ═══════════════════════════════════════════════════════════════════
;;; CLI Command Parsing
;;; ═══════════════════════════════════════════════════════════════════

(defclass cli-command ()
  ((name :initarg :name
         :accessor command-name
         :documentation "Command name keyword")
   (args :initarg :args
         :accessor command-args
         :initform nil
         :documentation "Command arguments")
   (raw :initarg :raw
        :accessor command-raw
        :documentation "Raw input string"))
  (:documentation "A parsed CLI command"))

(defun parse-cli-command (input)
  "Parse INPUT string into a cli-command."
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline) input))
         (parts (split-string trimmed #\Space))
         (name-str (first parts))
         (args (rest parts)))
    (when (and name-str (plusp (length name-str)))
      (make-instance 'cli-command
                     :name (intern (string-upcase name-str) :keyword)
                     :args args
                     :raw trimmed))))

(defun split-string (string delimiter)
  "Split STRING by DELIMITER."
  (let ((result nil)
        (start 0))
    (loop for i from 0 below (length string)
          when (char= (char string i) delimiter)
            do (when (> i start)
                 (push (subseq string start i) result))
               (setf start (1+ i)))
    (when (< start (length string))
      (push (subseq string start) result))
    (nreverse result)))

(defun truncate-for-display (string max-length)
  "Truncate STRING to MAX-LENGTH characters."
  (if (<= (length string) max-length)
      string
      (concatenate 'string (subseq string 0 (- max-length 3)) "...")))

;;; ═══════════════════════════════════════════════════════════════════
;;; CLI Command Execution
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric execute-cli-command (session command)
  (:documentation "Execute a CLI command in the session.")

  (:method ((session session) (command cli-command))
    "Execute a parsed CLI command."
    (let ((out (session-output-stream session))
          (agent (session-agent session)))
      ;; Record in history
      (push (command-raw command) (session-command-history session))

      ;; Dispatch based on command name
      (case (command-name command)
        ((:help :h :?)
         (cli-display-help session)
         :continue)

        ((:status :s)
         (cli-display-state session)
         :continue)

        ((:start)
         (autopoiesis.agent:start-agent agent)
         (format out "Agent started.~%")
         :continue)

        ((:stop)
         (autopoiesis.agent:stop-agent agent)
         (format out "Agent stopped.~%")
         :continue)

        ((:pause)
         (autopoiesis.agent:pause-agent agent)
         (format out "Agent paused.~%")
         :continue)

        ((:resume)
         (autopoiesis.agent:resume-agent agent)
         (format out "Agent resumed.~%")
         :continue)

        ((:step)
         (if (autopoiesis.agent:agent-running-p agent)
             (progn
               (autopoiesis.agent:cognitive-cycle agent nil)
               (format out "Executed one cognitive cycle.~%"))
             (format out "Agent is not running. Use 'start' first.~%"))
         :continue)

        ((:thoughts)
         (let* ((ts (autopoiesis.agent:agent-thought-stream agent))
                (thoughts (autopoiesis.core:stream-thoughts ts)))
           (format out "~%All Thoughts (~a):~%" (length thoughts))
           (dolist (thought thoughts)
             (format out "  [~a] ~a: ~s~%"
                     (autopoiesis.core:thought-id thought)
                     (autopoiesis.core:thought-type thought)
                     (autopoiesis.core:thought-content thought)))
           (when (null thoughts)
             (format out "  (no thoughts)~%")))
         :continue)

        ((:inject)
         (let ((text (format nil "~{~a~^ ~}" (command-args command))))
           (if (plusp (length text))
               (progn
                 (autopoiesis.core:stream-append
                  (autopoiesis.agent:agent-thought-stream agent)
                  (autopoiesis.core:make-observation
                   text
                   :source :human-cli
                   :interpreted `(:human-input ,text)))
                 (format out "Injected observation: ~a~%" text))
               (format out "Usage: inject <text>~%")))
         :continue)

        ((:detail)
         (let ((arg (first (command-args command))))
           (cond
             ((or (string= arg "+") (string= arg "more"))
              (expand-detail (session-viewport session))
              (format out "Detail level: ~a~%"
                      (viewport-detail-level (session-viewport session))))
             ((or (string= arg "-") (string= arg "less"))
              (collapse-detail (session-viewport session))
              (format out "Detail level: ~a~%"
                      (viewport-detail-level (session-viewport session))))
             (t
              (format out "Usage: detail +/-~%"))))
         :continue)

        ((:back :b)
         (navigate-back (session-navigator session))
         (format out "Navigated back.~%")
         :continue)

        ((:pending)
         (show-pending-requests out)
         :continue)

        ((:respond)
         (let ((args (command-args command)))
           (if (>= (length args) 2)
               (let* ((id-prefix (first args))
                      (value-str (format nil "~{~a~^ ~}" (rest args)))
                      ;; Find request by prefix match
                      (requests (list-pending-blocking-requests))
                      (matching (find-if (lambda (req)
                                          (search id-prefix (blocking-request-id req)))
                                        requests)))
                 (if matching
                     (progn
                       (provide-response matching value-str)
                       (format out "Response provided to request ~a~%"
                               (subseq (blocking-request-id matching) 0 8)))
                     (format out "No pending request matching '~a'~%" id-prefix)))
               (format out "Usage: respond <request-id-prefix> <response>~%")))
         :continue)

        ((:quit :q)
         (format out "Ending session...~%")
         :quit)

        (otherwise
         (format out "Unknown command: ~a~%" (command-name command))
         (format out "Type 'help' for available commands.~%")
         :continue)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Main CLI Loop
;;; ═══════════════════════════════════════════════════════════════════

(defun run-cli-session (session)
  "Run the interactive CLI loop for SESSION."
  (let ((in (session-input-stream session))
        (out (session-output-stream session)))
    (cli-display-header session)
    (cli-display-help session)
    (cli-display-state session)

    ;; Main loop
    (loop
      (cli-display-prompt session)
      (let ((line (read-line in nil :eof)))
        (cond
          ((eq line :eof)
           (format out "~%End of input.~%")
           (return :eof))

          ((zerop (length (string-trim '(#\Space #\Tab) line)))
           ;; Empty line, just continue
           )

          (t
           (let* ((command (parse-cli-command line))
                  (result (when command
                            (execute-cli-command session command))))
             (when (eq result :quit)
               (return :quit)))))))

    ;; End session
    (end-session session)))

(defun cli-interact (agent &key (user "default"))
  "Start an interactive CLI session with AGENT."
  (let ((session (start-session user agent)))
    (unwind-protect
         (run-cli-session session)
      (when (find-session (session-id session))
        (end-session session)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun session-to-sexpr (session)
  "Convert SESSION to an S-expression for persistence."
  `(:session
    :id ,(session-id session)
    :user ,(session-user session)
    :agent-id ,(autopoiesis.agent:agent-id (session-agent session))
    :started ,(session-started session)
    :ended ,(session-ended session)
    :command-history ,(session-command-history session)))

(defun session-summary (session)
  "Return a summary of the session."
  `(:id ,(session-id session)
    :user ,(session-user session)
    :agent ,(autopoiesis.agent:agent-name (session-agent session))
    :started ,(session-started session)
    :ended ,(session-ended session)
    :commands-executed ,(length (session-command-history session))
    :duration ,(when (session-ended session)
                 (- (session-ended session) (session-started session)))))
