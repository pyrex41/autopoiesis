#!/usr/bin/env sbcl --script

(require :asdf)

;; Load Quicklisp for dependency resolution
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
                                        (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; Add project root to ASDF search path
;; Script is at <project>/scripts/agent-worker.lisp
;; Project root is one level up
(let ((project-root (make-pathname
                      :directory (butlast
                                  (pathname-directory
                                    (or *load-truename*
                                        *default-pathname-defaults*))))))
  (push project-root asdf:*central-registry*))

(asdf:load-system :autopoiesis)

(defpackage :autopoiesis.worker
  (:use :cl :autopoiesis.core :autopoiesis.agent :autopoiesis.snapshot
        :autopoiesis.integration)
  (:export
   #:*agent*
   #:*start-time*))

(in-package :autopoiesis.worker)

;; Protocol message comments
;;
;; LFE->CL messages (Phase 1-3):
;;   :init              — Initialize agent
;;   :cognitive-cycle   — Run one cognitive cycle
;;   :snapshot           — Create snapshot
;;   :inject-observation — Inject observation into thought stream
;;   :shutdown           — Clean shutdown
;;
;; LFE->CL messages (Phase 4):
;;   :agentic-prompt    — Run multi-turn agentic loop with streaming
;;   :query-thoughts    — Query thought stream
;;   :list-capabilities — List registered capabilities
;;   :invoke-capability — Invoke a specific capability
;;   :checkout          — Restore agent from snapshot
;;   :diff              — Diff two snapshots
;;   :create-branch     — Create snapshot branch
;;   :list-branches     — List all branches
;;   :switch-branch     — Switch to branch and checkout head
;;   :blocking-response — Response to a blocking request
;;
;; CL->LFE messages (unsolicited):
;;   :heartbeat         — Periodic liveness signal
;;   :thought           — Streaming thought during agentic loop
;;   :blocking-request  — Human-in-the-loop request

(defvar *agent* nil
  "Current agent instance running in this worker.")

(defvar *start-time* (get-universal-time)
  "Time when this worker was started.")

(defvar *pending-responses* (make-hash-table :test 'equal)
  "Pending blocking-request responses keyed by request ID.")

(defvar *output-lock* (bt:make-lock "output-lock")
  "Lock for serializing output to stdout (heartbeat thread + main thread).")

(defun send-response (sexpr)
  "Write S-expression to stdout and flush. Thread-safe."
  (bt:with-lock-held (*output-lock*)
    (prin1 sexpr *standard-output*)
    (terpri *standard-output*)
    (finish-output *standard-output*)))

;;; ===================================================================
;;; Original handlers (Phase 1-3)
;;; ===================================================================

(defun handle-inject-observation (msg)
  "Inject an observation into the agent's thought stream."
  (let ((content (getf (cdr msg) :content)))
    (let ((obs (autopoiesis.core:make-observation content :source :external)))
      (autopoiesis.core:stream-append (agent-thought-stream *agent*) obs)
      (send-response `(:ok :type :observation-injected)))))

(defun handle-init (msg)
  "Initialize the worker by restoring an agent from snapshot or creating new.
   Message format: (:init :agent-id <id> :name <name>)
   If a snapshot exists for AGENT-ID, restores from it. Otherwise creates
   a new agent. Starts the agent and sets *agent*."
  (let ((args (cdr msg)))
    (let ((agent-id (getf args :agent-id))
          (name (getf args :name "unnamed")))
      (handler-case
          (let* ((restored (when agent-id
                             (restore-agent-from-snapshot agent-id)))
                 (agent (or restored
                            (make-agent :name name))))
            (start-agent agent)
            (setf *agent* agent)
            (setf *start-time* (get-universal-time))
            ;; Phase 4.1: Activate heartbeat after init
            (start-heartbeat-thread)
            (send-response `(:ok :type :init
                                 :agent-id ,(agent-id agent)
                                 :restored ,(not (null restored)))))
        (error (e)
          (send-response `(:error :type :init-failed
                                  :message ,(princ-to-string e))))))))

(defun handle-cognitive-cycle (msg)
  "Run one cognitive cycle on the current agent.
Counts thoughts added during the cycle and returns the result.
On error, sends a :cycle-failed response instead of crashing."
  (let ((environment (getf (cdr msg) :environment)))
    (handler-case
        (let* ((thoughts-before (stream-length (agent-thought-stream *agent*)))
               (result (cognitive-cycle *agent* environment))
               (thoughts-after (stream-length (agent-thought-stream *agent*))))
          (send-response `(:ok :type :cycle-complete
                               :result ,result
                               :thoughts-added ,(- thoughts-after thoughts-before))))
      (error (e)
        (send-response `(:error :type :cycle-failed
                                :message ,(princ-to-string e)))))))

(defun handle-snapshot (msg)
  "Create snapshot of current agent state."
  (declare (ignore msg))
  (handler-case
      (let ((snapshot (make-snapshot (agent-to-sexpr *agent*))))
        (save-snapshot snapshot)
        (send-response `(:ok :type :snapshot-complete
                              :snapshot-id ,(snapshot-id snapshot)
                              :hash ,(snapshot-hash snapshot))))
    (error (e)
      (send-response `(:error :type :snapshot-failed
                              :message ,(princ-to-string e))))))

(defun handle-shutdown (msg)
  "Clean shutdown."
  (declare (ignore msg))
  (when *agent*
    (stop-agent *agent*)
    ;; Create final snapshot
    (handler-case
        (let ((snapshot (make-snapshot (agent-to-sexpr *agent*)
                                       :metadata `(:shutdown-reason :command))))
          (save-snapshot snapshot))
      (error () nil)))
  (send-response `(:ok :type :shutdown))
  (sb-ext:exit :code 0))

;;; ===================================================================
;;; Heartbeat (Phase 4.1)
;;; ===================================================================

(defun send-heartbeat ()
  "Send periodic heartbeat to stdout."
  (when *agent*
    (handler-case
        (let ((thoughts (autopoiesis.core:stream-length (agent-thought-stream *agent*)))
              (uptime (- (get-universal-time) *start-time*)))
          (send-response `(:heartbeat :thoughts ,thoughts :uptime-seconds ,uptime)))
      (error () nil))))

(defun start-heartbeat-thread ()
  "Start a thread that sends heartbeat every 10 seconds."
  (bt:make-thread
   (lambda ()
     (loop
       (sleep 10)
       (send-heartbeat)))
   :name "heartbeat-thread"))

;;; ===================================================================
;;; Phase 4.2: New bridge protocol handlers
;;; ===================================================================

(defun resolve-capabilities (names)
  "Resolve capability name keywords to capability instances.
   If NAMES is nil, returns all registered capabilities."
  (if names
      (loop for name in names
            for cap = (find-capability name)
            when cap collect cap
            else do (warn "Capability not found: ~A" name))
      (list-capabilities)))

(defun thought-to-sexpr (thought)
  "Convert a thought to a portable S-expression."
  (list :type (autopoiesis.core:thought-type thought)
        :content (princ-to-string (autopoiesis.core:thought-content thought))
        :timestamp (autopoiesis.core:thought-timestamp thought)))

(defun handle-agentic-prompt (msg)
  "Run an agentic loop with streaming thoughts.
   Message: (:agentic-prompt :prompt \"...\" :capabilities (:tool1 :tool2) :max-turns 25)
   Streams: (:thought :type <type> :content <content> :turn <n>)
   Final:   (:ok :type :agentic-complete :result <text> :turns <n> :snapshot-id <id>)"
  (let* ((prompt (getf (cdr msg) :prompt))
         (cap-names (getf (cdr msg) :capabilities))
         (max-turns (or (getf (cdr msg) :max-turns) 25))
         (capabilities (resolve-capabilities cap-names))
         (messages (list (list (cons "role" "user") (cons "content" prompt))))
         (turn-count 0))
    (handler-case
        (let ((on-thought (lambda (type data)
                            (incf turn-count)
                            (send-response `(:thought :type ,type
                                                      :content ,(princ-to-string data)
                                                      :turn ,turn-count)))))
          (multiple-value-bind (response all-messages turns)
              (agentic-loop (agent-client *agent*) messages capabilities
                            :system (agent-system-prompt *agent*)
                            :max-turns max-turns
                            :on-thought on-thought)
            ;; Update agent conversation history
            (setf (agent-conversation-history *agent*) all-messages)
            ;; Drain and send orchestration requests queued by tools
            (dolist (req (drain-orchestration-requests))
              (send-response req))
            ;; Auto-snapshot after agentic loop
            (handler-case
                (let* ((snapshot (make-snapshot (agent-to-sexpr *agent*)))
                       (saved (save-snapshot snapshot)))
                  (declare (ignore saved))
                  (send-response `(:ok :type :agentic-complete
                                       :result ,(if (consp response)
                                                    (response-text response)
                                                    (princ-to-string response))
                                       :turns ,turns
                                       :snapshot-id ,(snapshot-id snapshot))))
              (error ()
                ;; Snapshot failed but loop succeeded — still report success
                (send-response `(:ok :type :agentic-complete
                                     :result ,(if (consp response)
                                                  (response-text response)
                                                  (princ-to-string response))
                                     :turns ,turns
                                     :snapshot-id nil))))))
      (error (e)
        (send-response `(:error :type :agentic-failed
                                :message ,(format nil "~A" e)))))))

(defun handle-query-thoughts (msg)
  "Query the agent's thought stream.
   Message: (:query-thoughts :last-n 10 :type :decision)
   Response: (:ok :type :thoughts :count <n> :thoughts (<thought-sexpr> ...))"
  (handler-case
      (let* ((last-n (or (getf (cdr msg) :last-n) 10))
             (type-filter (getf (cdr msg) :type))
             (stream (agent-thought-stream *agent*))
             (thoughts (if type-filter
                           (stream-by-type stream type-filter)
                           (stream-last stream last-n))))
        (send-response `(:ok :type :thoughts
                             :count ,(length thoughts)
                             :thoughts ,(mapcar #'thought-to-sexpr thoughts))))
    (error (e)
      (send-response `(:error :type :query-failed
                              :message ,(princ-to-string e))))))

(defun handle-list-capabilities (msg)
  "List available capabilities.
   Message: (:list-capabilities :filter \"search\")
   Response: (:ok :type :capabilities :count <n> :capabilities (...))"
  (handler-case
      (let* ((all-caps (list-capabilities))
             (filter (getf (cdr msg) :filter)))
        (let ((filtered (if filter
                            (remove-if-not
                             (lambda (cap)
                               (search filter (string (capability-name cap))
                                       :test #'char-equal))
                             all-caps)
                            all-caps)))
          (send-response
           `(:ok :type :capabilities
                 :count ,(length filtered)
                 :capabilities ,(mapcar (lambda (cap)
                                          (list :name (capability-name cap)
                                                :description (capability-description cap)))
                                        filtered)))))
    (error (e)
      (send-response `(:error :type :list-capabilities-failed
                              :message ,(princ-to-string e))))))

(defun handle-invoke-capability (msg)
  "Invoke a specific capability by name.
   Message: (:invoke-capability :name :some-cap :args (...))
   Response: (:ok :type :capability-result :name <name> :result <result>)"
  (handler-case
      (let* ((cap-name (getf (cdr msg) :name))
             (args (getf (cdr msg) :args))
             (cap (find-capability cap-name)))
        (if cap
            (let ((result (apply (capability-function cap) args)))
              (send-response `(:ok :type :capability-result
                                   :name ,cap-name
                                   :result ,(princ-to-string result))))
            (send-response `(:error :type :capability-not-found
                                    :name ,cap-name))))
    (error (e)
      (send-response `(:error :type :invoke-failed
                              :message ,(princ-to-string e))))))

(defun handle-checkout (msg)
  "Restore agent state from a snapshot.
   Message: (:checkout :snapshot-id \"abc123\")
   Response: (:ok :type :checked-out :snapshot-id <id>)"
  (handler-case
      (let* ((snapshot-id (getf (cdr msg) :snapshot-id))
             (snapshot (load-snapshot snapshot-id)))
        (if snapshot
            (let ((restored (sexpr-to-agent (snapshot-agent-state snapshot))))
              (setf *agent* restored)
              (start-agent *agent*)
              (send-response `(:ok :type :checked-out :snapshot-id ,snapshot-id)))
            (send-response `(:error :type :snapshot-not-found
                                    :snapshot-id ,snapshot-id))))
    (error (e)
      (send-response `(:error :type :checkout-failed
                              :message ,(princ-to-string e))))))

(defun handle-diff (msg)
  "Diff two snapshots.
   Message: (:diff :from \"id1\" :to \"id2\")
   Response: (:ok :type :diff :edits (...))"
  (handler-case
      (let* ((from-id (getf (cdr msg) :from))
             (to-id (getf (cdr msg) :to))
             (from-snap (load-snapshot from-id))
             (to-snap (load-snapshot to-id)))
        (if (and from-snap to-snap)
            (let ((edits (sexpr-diff (snapshot-agent-state from-snap)
                                     (snapshot-agent-state to-snap))))
              (send-response `(:ok :type :diff
                                   :from ,from-id :to ,to-id
                                   :edit-count ,(length edits)
                                   :edits ,(mapcar #'princ-to-string edits))))
            (send-response `(:error :type :snapshot-not-found
                                    :message "One or both snapshots not found"))))
    (error (e)
      (send-response `(:error :type :diff-failed
                              :message ,(princ-to-string e))))))

(defun handle-create-branch (msg)
  "Create a snapshot branch.
   Message: (:create-branch :name \"experiment\" :from \"snapshot-id\")
   Response: (:ok :type :branch-created :name <name>)"
  (handler-case
      (let* ((name (getf (cdr msg) :name))
             (from (getf (cdr msg) :from)))
        (create-branch name :from-snapshot from)
        (send-response `(:ok :type :branch-created :name ,name :from ,from)))
    (error (e)
      (send-response `(:error :type :branch-create-failed
                              :message ,(princ-to-string e))))))

(defun handle-list-branches (msg)
  "List all branches.
   Message: (:list-branches)
   Response: (:ok :type :branches :branches ((:name ... :head ...) ...))"
  (declare (ignore msg))
  (handler-case
      (let ((branches (list-branches)))
        (send-response
         `(:ok :type :branches
               :count ,(length branches)
               :branches ,(mapcar (lambda (b)
                                    (list :name (branch-name b)
                                          :head (branch-head b)))
                                  branches))))
    (error (e)
      (send-response `(:error :type :list-branches-failed
                              :message ,(princ-to-string e))))))

(defun handle-switch-branch (msg)
  "Switch to a branch and checkout its head.
   Message: (:switch-branch :name \"experiment\")
   Response: (:ok :type :branch-switched :name <name> :head <snapshot-id>)"
  (handler-case
      (let* ((name (getf (cdr msg) :name))
             (branch (switch-branch name)))
        (when (branch-head branch)
          (let ((snapshot (load-snapshot (branch-head branch))))
            (when snapshot
              (setf *agent* (sexpr-to-agent (snapshot-agent-state snapshot)))
              (start-agent *agent*))))
        (send-response `(:ok :type :branch-switched
                             :name ,name
                             :head ,(branch-head branch))))
    (error (e)
      (send-response `(:error :type :branch-switch-failed
                              :message ,(princ-to-string e))))))

;;; ===================================================================
;;; Phase 4.5: Blocking response handler
;;; ===================================================================

(defun handle-blocking-response (msg)
  "Receive response to a blocking request.
   Message: (:blocking-response :id <id> :response <response>)
   Stores response in *pending-responses* for the blocking handler."
  (let ((id (getf (cdr msg) :id))
        (response (getf (cdr msg) :response)))
    (setf (gethash id *pending-responses*) response)
    (send-response `(:ok :type :blocking-response-received :id ,id))))

;;; ===================================================================
;;; Phase 5: Meta-Agent orchestration handlers
;;; ===================================================================

(defun handle-spawn-sub-agent (msg)
  "Handle request to spawn a sub-agent via LFE.
   Message: (:spawn-sub-agent :agent-id <id> :name <name> :task <task>
             :capabilities (:cap1 :cap2) :max-turns 25)
   Sends spawn request upstream to LFE for supervised spawning."
  (handler-case
      (let* ((agent-id (getf (cdr msg) :agent-id))
             (name (getf (cdr msg) :name "sub-agent"))
             (task (getf (cdr msg) :task))
             (capabilities (getf (cdr msg) :capabilities))
             (max-turns (or (getf (cdr msg) :max-turns) 25)))
        (update-sub-agent agent-id
                          :status :spawning
                          :name name
                          :task task)
        (send-response `(:spawn-request
                         :agent-id ,agent-id
                         :name ,name
                         :task ,task
                         :capabilities ,capabilities
                         :max-turns ,max-turns))
        (send-response `(:ok :type :sub-agent-spawned :agent-id ,agent-id)))
    (error (e)
      (send-response `(:error :type :spawn-failed
                              :message ,(princ-to-string e))))))

(defun handle-sub-agent-result (msg)
  "Handle result from a completed sub-agent.
   Message: (:sub-agent-result :agent-id <id> :status <status> :result <text>)
   Updates the sub-agent registry so query-agent and await-agent can see it."
  (let ((agent-id (getf (cdr msg) :agent-id))
        (status (getf (cdr msg) :status))
        (result (getf (cdr msg) :result))
        (error-msg (getf (cdr msg) :error)))
    (update-sub-agent agent-id
                      :status status
                      :result result
                      :error error-msg
                      :completed (get-universal-time))
    (send-response `(:ok :type :sub-agent-result-received :agent-id ,agent-id))))

(defun handle-save-session (msg)
  "Save session state to a file.
   Message: (:save-session :name <name>)
   Response: (:ok :type :session-saved :session-id <id> :snapshot-id <id>)"
  (handler-case
      (let* ((name (or (getf (cdr msg) :name)
                       (format nil "session-~A" (autopoiesis.core:make-uuid))))
             (dir (ensure-session-directory))
             (snapshot (make-snapshot (agent-to-sexpr *agent*)
                                      :metadata `(:session-name ,name
                                                  :saved-at ,(get-universal-time))))
             (saved (save-snapshot snapshot))
             (session-data `(:session
                             :id ,name
                             :snapshot-id ,(snapshot-id snapshot)
                             :agent-id ,(agent-id *agent*)
                             :saved-at ,(get-universal-time)))
             (path (merge-pathnames (format nil "~A.session" name) dir)))
        (declare (ignore saved))
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
          (prin1 session-data out))
        (send-response `(:ok :type :session-saved
                             :session-id ,name
                             :snapshot-id ,(snapshot-id snapshot))))
    (error (e)
      (send-response `(:error :type :session-save-failed
                              :message ,(princ-to-string e))))))

(defun handle-resume-session (msg)
  "Resume a previously saved session.
   Message: (:resume-session :name <name>)
   Response: (:ok :type :session-resumed :session-id <id> :agent-id <id>)"
  (handler-case
      (let* ((name (getf (cdr msg) :name))
             (dir (ensure-session-directory))
             (path (merge-pathnames (format nil "~A.session" name) dir)))
        (if (not (probe-file path))
            (send-response `(:error :type :session-not-found :name ,name))
            (let* ((session-data (with-open-file (in path :direction :input)
                                   (read in)))
                   (snapshot-id (getf (cdr session-data) :snapshot-id))
                   (snapshot (load-snapshot snapshot-id)))
              (if (not snapshot)
                  (send-response `(:error :type :snapshot-not-found
                                          :snapshot-id ,snapshot-id))
                  (let ((restored (sexpr-to-agent (snapshot-agent-state snapshot))))
                    (start-agent restored)
                    (setf *agent* restored)
                    (send-response `(:ok :type :session-resumed
                                         :session-id ,name
                                         :agent-id ,(agent-id restored))))))))
    (error (e)
      (send-response `(:error :type :session-resume-failed
                              :message ,(princ-to-string e))))))

;;; ===================================================================
;;; Command dispatch
;;; ===================================================================

(defun handle-command (command)
  "Dispatch command to handler."
  (case (car command)
    ;; Original handlers
    (:init (handle-init command))
    (:cognitive-cycle (handle-cognitive-cycle command))
    (:snapshot (handle-snapshot command))
    (:inject-observation (handle-inject-observation command))
    (:shutdown (handle-shutdown command))
    ;; Phase 4 handlers
    (:agentic-prompt (handle-agentic-prompt command))
    (:query-thoughts (handle-query-thoughts command))
    (:list-capabilities (handle-list-capabilities command))
    (:invoke-capability (handle-invoke-capability command))
    (:checkout (handle-checkout command))
    (:diff (handle-diff command))
    (:create-branch (handle-create-branch command))
    (:list-branches (handle-list-branches command))
    (:switch-branch (handle-switch-branch command))
    (:blocking-response (handle-blocking-response command))
    ;; Phase 5 handlers
    (:spawn-sub-agent (handle-spawn-sub-agent command))
    (:sub-agent-result (handle-sub-agent-result command))
    (:save-session (handle-save-session command))
    (:resume-session (handle-resume-session command))
    (otherwise (send-response `(:error :type :unknown-command
                                       :command ,(car command))))))

;; Main message processing loop
(loop
  (handler-case
      (let ((command (read *standard-input* nil :eof)))
        (if (eq command :eof)
            (progn
              ;; EOF: clean shutdown
              (when *agent*
                (stop-agent *agent*)
                (handler-case
                    (let ((snapshot (make-snapshot (agent-to-sexpr *agent*)
                                                   :metadata `(:shutdown-reason :eof))))
                      (save-snapshot snapshot))
                  (error () nil)))
              (return))
            (handle-command command)))
    (error (e)
      (send-response `(:error :type :parse-error :message ,(princ-to-string e))))))
