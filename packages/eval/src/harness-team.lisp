;;;; harness-team.lisp - Team strategy harness
;;;;
;;;; Wraps the multi-agent team coordination layer as an eval harness.
;;;; Creates a team with a configurable strategy, assigns the scenario
;;;; as a team task, and collects results.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Team Harness Class
;;; ===================================================================

(defclass team-harness (eval-harness)
  ((strategy :initarg :strategy
             :accessor th-strategy
             :initform :parallel
             :type keyword
             :documentation "Team strategy: :parallel, :leader-worker, :pipeline, :debate, :consensus")
   (team-size :initarg :team-size
              :accessor th-team-size
              :initform 3
              :type integer
              :documentation "Number of agents in the team")
   (provider-name :initarg :provider-name
                  :accessor th-provider-name
                  :initform "claude-code"
                  :type string
                  :documentation "Provider to use for each agent in the team")
   (max-rounds :initarg :max-rounds
               :accessor th-max-rounds
               :initform 3
               :type integer
               :documentation "Max rounds for iterative strategies (debate, consensus)"))
  (:documentation "Harness that creates a multi-agent team to solve the scenario."))

(defun make-team-harness (name &key (strategy :parallel) (team-size 3)
                                  (provider-name "claude-code") (max-rounds 3)
                                  (description ""))
  "Create a team strategy harness."
  (make-instance 'team-harness
                 :name name
                 :description (if (string= description "")
                                  (format nil "Team ~a (~a x~a)"
                                          strategy provider-name team-size)
                                  description)
                 :strategy strategy
                 :team-size team-size
                 :provider-name provider-name
                 :max-rounds max-rounds))

;;; ===================================================================
;;; Team Layer Integration (Dynamic Resolution)
;;; ===================================================================

(defun team-pkg-available-p ()
  "Check if the team layer is loaded."
  (find-package :autopoiesis.team))

(defun %team-call (fn-name &rest args)
  "Call a function from autopoiesis.team dynamically."
  (let* ((pkg (find-package :autopoiesis.team))
         (fn (when pkg (find-symbol fn-name pkg))))
    (when (and fn (fboundp fn))
      (apply fn args))))

(defun %agent-call (fn-name &rest args)
  "Call a function from autopoiesis.agent dynamically."
  (let* ((pkg (find-package :autopoiesis.agent))
         (fn (when pkg (find-symbol fn-name pkg))))
    (when (and fn (fboundp fn))
      (apply fn args))))

;;; ===================================================================
;;; Harness Protocol
;;; ===================================================================

(defmethod harness-run-scenario ((harness team-harness) scenario-plist &key timeout)
  "Run scenario by creating a team of agents and coordinating via strategy."
  (let* ((prompt (getf scenario-plist :eval-scenario/prompt))
         (verifier (getf scenario-plist :eval-scenario/verifier))
         (expected (getf scenario-plist :eval-scenario/expected))
         (effective-timeout (or timeout
                                (getf scenario-plist :eval-scenario/timeout)
                                300))
         (start-time (get-precise-time)))
    ;; Check if team layer is available
    (unless (team-pkg-available-p)
      (return-from harness-run-scenario
        (list :output "Team layer not loaded (autopoiesis/team)"
              :duration 0 :exit-code -1 :passed :error
              :metadata (list :error "autopoiesis/team not loaded"))))
    (handler-case
        (let* (;; Create agents
               (agent-ids
                 (loop for i from 1 to (th-team-size harness)
                       collect (let ((agent (%agent-call "MAKE-AGENT"
                                                        :name (format nil "eval-team-~a" i)
                                                        :capabilities '(:llm-complete))))
                                 (when agent
                                   (%agent-call "AGENT-ID" agent)))))
               ;; Create team
               (team-id (%team-call "CREATE-TEAM"
                                    :name (format nil "eval-~a" (make-uuid))
                                    :strategy (th-strategy harness)
                                    :members agent-ids
                                    :task prompt))
               ;; Start team
               (_ (when team-id (%team-call "START-TEAM" team-id)))
               ;; Assign work
               (_ (when team-id
                    (%team-call "STRATEGY-ASSIGN-WORK"
                                (th-strategy harness) team-id prompt)))
               ;; Poll for completion with timeout
               (deadline (+ (get-internal-real-time)
                            (* effective-timeout internal-time-units-per-second)))
               (completed nil))
          (declare (ignore _))
          ;; Wait for completion
          (loop while (and team-id (not completed)
                          (< (get-internal-real-time) deadline))
                do (setf completed (%team-call "STRATEGY-COMPLETE-P"
                                               (th-strategy harness) team-id))
                   (unless completed (sleep 1)))
          ;; Collect results
          (let* ((results (when (and team-id completed)
                            (%team-call "STRATEGY-COLLECT-RESULTS"
                                        (th-strategy harness) team-id)))
                 (output (if results
                             (format nil "~{~a~^~%~%---~%~%~}" results)
                             (if completed "Team completed with no output"
                                 "Team timed out")))
                 (duration (/ (- (get-precise-time) start-time) 1000000.0))
                 ;; Run verifier
                 (passed (if verifier
                             (run-verifier verifier output
                                           :expected expected
                                           :exit-code (if completed 0 1))
                             nil)))
            ;; Cleanup: disband team
            (when team-id
              (handler-case (%team-call "DISBAND-TEAM" team-id)
                (error () nil)))
            (list :output output
                  :tool-calls nil
                  :duration duration
                  :cost nil ; team doesn't aggregate cost yet
                  :turns (th-team-size harness) ; each agent = one "turn" at minimum
                  :exit-code (if completed 0 1)
                  :passed passed
                  :metadata (list :strategy (th-strategy harness)
                                  :team-size (th-team-size harness)
                                  :provider (th-provider-name harness)
                                  :completed completed
                                  :team-id team-id))))
      (error (e)
        (let ((duration (/ (- (get-precise-time) start-time) 1000000.0)))
          (list :output (format nil "Team error: ~a" e)
                :duration duration
                :exit-code -1
                :passed :error
                :metadata (list :error (format nil "~a" e))))))))

(defmethod harness-to-config-plist ((harness team-harness))
  (list :type "team"
        :name (harness-name harness)
        :strategy (th-strategy harness)
        :team-size (th-team-size harness)
        :provider (th-provider-name harness)
        :max-rounds (th-max-rounds harness)))
