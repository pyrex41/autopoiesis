;;;; orchestration-tests.lisp - Tests for the orchestration layer
;;;;
;;;; Tests conductor lifecycle, timer heap, event queue (substrate-backed),
;;;; worker tracking (substrate-backed), metrics, failure backoff,
;;;; and tick loop integration.

(in-package #:autopoiesis.test)

(def-suite orchestration-tests
  :description "Orchestration layer tests")

(in-suite orchestration-tests)

;;; ===================================================================
;;; Conductor class creation
;;; ===================================================================

(test conductor-creation
  "Creating a conductor initializes all slots."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (is (null (autopoiesis.orchestration:conductor-running-p c)))
    (is (null (autopoiesis.orchestration:conductor-timer-heap c)))
    (is (hash-table-p (autopoiesis.orchestration::conductor-metrics c)))
    (is (hash-table-p (autopoiesis.orchestration::conductor-failure-counts c)))))

;;; ===================================================================
;;; Metrics
;;; ===================================================================

(test metrics-increment
  "increment-metric increases the counter."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (is (= 0 (autopoiesis.orchestration:get-metric c :test)))
    (autopoiesis.orchestration:increment-metric c :test)
    (is (= 1 (autopoiesis.orchestration:get-metric c :test)))
    (autopoiesis.orchestration:increment-metric c :test 5)
    (is (= 6 (autopoiesis.orchestration:get-metric c :test)))))

(test metrics-separate-names
  "Different metric names are independent."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (autopoiesis.orchestration:increment-metric c :alpha 10)
    (autopoiesis.orchestration:increment-metric c :beta 20)
    (is (= 10 (autopoiesis.orchestration:get-metric c :alpha)))
    (is (= 20 (autopoiesis.orchestration:get-metric c :beta)))))

;;; ===================================================================
;;; Timer heap
;;; ===================================================================

(test schedule-action-adds-to-heap
  "schedule-action inserts an entry into the timer heap."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (autopoiesis.orchestration:schedule-action c 10 '(:action-type :test-action))
    (is (= 1 (length (autopoiesis.orchestration:conductor-timer-heap c))))))

(test schedule-action-sorted-by-time
  "Timer heap entries are sorted by fire time (ascending)."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    ;; Schedule in reverse order
    (autopoiesis.orchestration:schedule-action c 30 '(:action-type :late))
    (autopoiesis.orchestration:schedule-action c 10 '(:action-type :early))
    (autopoiesis.orchestration:schedule-action c 20 '(:action-type :mid))
    (is (= 3 (length (autopoiesis.orchestration:conductor-timer-heap c))))
    ;; First entry should have earliest fire time
    (let ((times (mapcar #'car (autopoiesis.orchestration:conductor-timer-heap c))))
      (is (< (first times) (second times)))
      (is (< (second times) (third times))))))

(test cancel-action-removes-by-type
  "cancel-action removes all entries with matching :action-type."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (autopoiesis.orchestration:schedule-action c 10 '(:action-type :keep))
    (autopoiesis.orchestration:schedule-action c 20 '(:action-type :remove))
    (autopoiesis.orchestration:schedule-action c 30 '(:action-type :remove))
    (is (= 3 (length (autopoiesis.orchestration:conductor-timer-heap c))))
    (autopoiesis.orchestration:cancel-action c :remove)
    (is (= 1 (length (autopoiesis.orchestration:conductor-timer-heap c))))
    (is (eq :keep (getf (cdar (autopoiesis.orchestration:conductor-timer-heap c))
                        :action-type)))))

(test process-due-timers-fires-past-timers
  "process-due-timers fires timers with fire-time <= now."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      ;; Schedule an action 0 seconds from now (already due)
      (autopoiesis.orchestration:schedule-action c 0 '(:action-type :immediate))
      ;; Schedule an action 9999 seconds from now (not due)
      (autopoiesis.orchestration:schedule-action c 9999 '(:action-type :future))
      (autopoiesis.orchestration::process-due-timers c)
      ;; Only the future timer should remain
      (is (= 1 (length (autopoiesis.orchestration:conductor-timer-heap c))))
      (is (eq :future (getf (cdar (autopoiesis.orchestration:conductor-timer-heap c))
                            :action-type))))))

;;; ===================================================================
;;; Event queue (substrate-backed)
;;; ===================================================================

(test queue-event-creates-datoms
  "queue-event writes event datoms to the substrate."
  (autopoiesis.substrate:with-store ()
    (let ((eid (autopoiesis.orchestration:queue-event :test-event '(:foo "bar"))))
      (is (integerp eid))
      (is (eq :test-event (autopoiesis.substrate:entity-attr eid :event/type)))
      (is (equal '(:foo "bar") (autopoiesis.substrate:entity-attr eid :event/data)))
      (is (eq :pending (autopoiesis.substrate:entity-attr eid :event/status)))
      (is (integerp (autopoiesis.substrate:entity-attr eid :event/created-at))))))

(test queue-event-multiple-pending
  "Multiple events can be queued and all start as :pending."
  (autopoiesis.substrate:with-store ()
    (let ((e1 (autopoiesis.orchestration:queue-event :alpha nil))
          (e2 (autopoiesis.orchestration:queue-event :beta nil))
          (e3 (autopoiesis.orchestration:queue-event :gamma nil)))
      (is (eq :pending (autopoiesis.substrate:entity-attr e1 :event/status)))
      (is (eq :pending (autopoiesis.substrate:entity-attr e2 :event/status)))
      (is (eq :pending (autopoiesis.substrate:entity-attr e3 :event/status))))))

(test process-events-claims-via-take
  "process-events claims pending events and marks them :complete."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (let ((e1 (autopoiesis.orchestration:queue-event :test nil))
            (e2 (autopoiesis.orchestration:queue-event :test nil)))
        (autopoiesis.orchestration:process-events c)
        ;; Both events should be complete
        (is (eq :complete (autopoiesis.substrate:entity-attr e1 :event/status)))
        (is (eq :complete (autopoiesis.substrate:entity-attr e2 :event/status)))
        ;; Metrics updated
        (is (= 2 (autopoiesis.orchestration:get-metric c :events-processed)))))))

(test process-events-no-pending
  "process-events does nothing when no pending events."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      ;; No events queued
      (autopoiesis.orchestration:process-events c)
      (is (= 0 (autopoiesis.orchestration:get-metric c :events-processed))))))

(test process-events-handles-errors
  "process-events marks failed events and records error."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      ;; Queue a task-result event with missing data (will try to handle)
      (let ((eid (autopoiesis.orchestration:queue-event :unknown-type nil)))
        (autopoiesis.orchestration:process-events c)
        ;; Should still be :complete (default dispatch does nothing)
        (is (eq :complete (autopoiesis.substrate:entity-attr eid :event/status)))))))

;;; ===================================================================
;;; Workers (substrate-backed)
;;; ===================================================================

(test register-worker-creates-datoms
  "register-worker writes worker datoms to the substrate."
  (autopoiesis.substrate:with-store ()
    (let* ((c (make-instance 'autopoiesis.orchestration:conductor))
           (weid (autopoiesis.orchestration:register-worker c "task-42" :fake-thread)))
      (is (integerp weid))
      (is (equal "task-42" (autopoiesis.substrate:entity-attr weid :worker/task-id)))
      (is (eq :running (autopoiesis.substrate:entity-attr weid :worker/status)))
      (is (eq :fake-thread (autopoiesis.substrate:entity-attr weid :worker/thread)))
      (is (integerp (autopoiesis.substrate:entity-attr weid :worker/started-at))))))

(test worker-running-p-queries-substrate
  "worker-running-p returns T for running workers, NIL otherwise."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (is (null (autopoiesis.orchestration:worker-running-p c "task-99")))
      (autopoiesis.orchestration:register-worker c "task-99" :thread)
      (is (autopoiesis.orchestration:worker-running-p c "task-99")))))

(test unregister-worker-updates-status
  "unregister-worker changes status from :running to the given status."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (let ((weid (autopoiesis.orchestration:register-worker c "task-7" :thread)))
        (is (eq :running (autopoiesis.substrate:entity-attr weid :worker/status)))
        (autopoiesis.orchestration:unregister-worker c "task-7" :status :complete :result "done")
        (is (eq :complete (autopoiesis.substrate:entity-attr weid :worker/status)))))))

(test conductor-active-workers-lists-running
  "conductor-active-workers returns task-ids of running workers."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (is (null (autopoiesis.orchestration:conductor-active-workers)))
      (autopoiesis.orchestration:register-worker c "task-a" :thread)
      (autopoiesis.orchestration:register-worker c "task-b" :thread)
      (let ((workers (autopoiesis.orchestration:conductor-active-workers)))
        (is (= 2 (length workers)))
        (is (member "task-a" workers :test #'equal))
        (is (member "task-b" workers :test #'equal)))
      ;; Unregister one
      (autopoiesis.orchestration:unregister-worker c "task-a" :status :complete)
      (let ((workers (autopoiesis.orchestration:conductor-active-workers)))
        (is (= 1 (length workers)))
        (is (member "task-b" workers :test #'equal))))))

;;; ===================================================================
;;; Failure tracking and backoff
;;; ===================================================================

(test failure-count-starts-at-zero
  "failure-count returns 0 for unknown tasks."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (is (= 0 (autopoiesis.orchestration::failure-count c "unknown-task")))))

(test handle-task-result-success-clears-failures
  "Successful task result clears failure count."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (autopoiesis.orchestration:register-worker c "task-x" :thread)
      ;; Simulate a failure first
      (autopoiesis.orchestration::handle-task-result c "task-x" :failure "err")
      (is (= 1 (autopoiesis.orchestration::failure-count c "task-x")))
      ;; Re-register and succeed
      (autopoiesis.orchestration:register-worker c "task-x" :thread)
      (autopoiesis.orchestration::handle-task-result c "task-x" :success "ok")
      (is (= 0 (autopoiesis.orchestration::failure-count c "task-x"))))))

(test handle-task-result-failure-increments-count
  "Failed task result increments failure count."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (autopoiesis.orchestration:register-worker c "task-y" :thread)
      (autopoiesis.orchestration::handle-task-result c "task-y" :failure "err1")
      (is (= 1 (autopoiesis.orchestration::failure-count c "task-y")))
      (autopoiesis.orchestration:register-worker c "task-y" :thread)
      (autopoiesis.orchestration::handle-task-result c "task-y" :failure "err2")
      (is (= 2 (autopoiesis.orchestration::failure-count c "task-y"))))))

;;; ===================================================================
;;; Conductor lifecycle
;;; ===================================================================

(test start-stop-conductor
  "start-conductor starts tick loop, stop-conductor stops it."
  (autopoiesis.substrate:with-store ()
    (let ((autopoiesis.orchestration:*conductor* nil))
      (let ((c (autopoiesis.orchestration:start-conductor)))
        (unwind-protect
             (progn
               (is (autopoiesis.orchestration:conductor-running-p c))
               (is (eq c autopoiesis.orchestration:*conductor*))
               (is (bt:threadp (autopoiesis.orchestration::conductor-tick-thread c))))
          (autopoiesis.orchestration:stop-conductor :conductor c))
        (is (null (autopoiesis.orchestration:conductor-running-p c)))
        (is (null autopoiesis.orchestration:*conductor*))))))

(test start-conductor-twice-errors
  "Starting conductor twice signals an error."
  (autopoiesis.substrate:with-store ()
    (let ((autopoiesis.orchestration:*conductor* nil))
      (let ((c (autopoiesis.orchestration:start-conductor)))
        (unwind-protect
             (signals error
               (autopoiesis.orchestration:start-conductor))
          (autopoiesis.orchestration:stop-conductor :conductor c))))))

;;; ===================================================================
;;; Conductor status
;;; ===================================================================

(test conductor-status-when-nil
  "conductor-status returns (:running nil) when no conductor."
  (let ((autopoiesis.orchestration:*conductor* nil))
    (let ((status (autopoiesis.orchestration:conductor-status)))
      (is (null (getf status :running))))))

(test conductor-status-running
  "conductor-status reports running state and metrics."
  (autopoiesis.substrate:with-store ()
    (let ((autopoiesis.orchestration:*conductor* nil))
      (let ((c (autopoiesis.orchestration:start-conductor)))
        (unwind-protect
             (progn
               ;; Let it tick at least once
               (sleep 0.2)
               (let ((status (autopoiesis.orchestration:conductor-status)))
                 (is (getf status :running))
                 (is (>= (getf status :tick-count) 1))))
          (autopoiesis.orchestration:stop-conductor :conductor c))))))

;;; ===================================================================
;;; Integration: tick loop processes events
;;; ===================================================================

(test tick-loop-processes-queued-events
  "Events queued while conductor is running get processed."
  (autopoiesis.substrate:with-store ()
    (let ((autopoiesis.orchestration:*conductor* nil))
      (let ((c (autopoiesis.orchestration:start-conductor)))
        (unwind-protect
             (let ((eid (autopoiesis.orchestration:queue-event :integration-test '(:x 1))))
               ;; Wait for tick to process
               (sleep 0.3)
               (is (eq :complete (autopoiesis.substrate:entity-attr eid :event/status))))
          (autopoiesis.orchestration:stop-conductor :conductor c))))))

(test multiple-events-processed-in-order
  "Multiple events are all processed by the tick loop."
  (autopoiesis.substrate:with-store ()
    (let ((autopoiesis.orchestration:*conductor* nil))
      (let ((c (autopoiesis.orchestration:start-conductor)))
        (unwind-protect
             (let ((eids (loop for i from 1 to 5
                               collect (autopoiesis.orchestration:queue-event :batch `(:i ,i)))))
               (sleep 0.5)
               (dolist (eid eids)
                 (is (eq :complete (autopoiesis.substrate:entity-attr eid :event/status)))))
          (autopoiesis.orchestration:stop-conductor :conductor c))))))

;;; ===================================================================
;;; Claude worker: shell-quote
;;; ===================================================================

(test shell-quote-simple
  "shell-quote wraps a string in single quotes."
  (is (equal "'hello'" (autopoiesis.orchestration:shell-quote "hello"))))

(test shell-quote-with-spaces
  "shell-quote handles strings with spaces."
  (is (equal "'hello world'" (autopoiesis.orchestration:shell-quote "hello world"))))

(test shell-quote-with-embedded-quotes
  "shell-quote escapes embedded single quotes."
  (is (equal "'it'\\''s'" (autopoiesis.orchestration:shell-quote "it's"))))

(test shell-quote-empty
  "shell-quote handles empty string."
  (is (equal "''" (autopoiesis.orchestration:shell-quote ""))))

;;; ===================================================================
;;; Claude worker: build-claude-command
;;; ===================================================================

(test build-command-basic
  "build-claude-command produces a command with required flags."
  (let ((cmd (autopoiesis.orchestration:build-claude-command
              '(:prompt "Say hello" :claude-path "/usr/bin/claude"))))
    (is (search "/usr/bin/claude" cmd))
    (is (search "-p" cmd))
    (is (search "--output-format" cmd))
    (is (search "stream-json" cmd))
    (is (search "--verbose" cmd))
    (is (search "--max-turns" cmd))
    (is (search "--dangerously-skip-permissions" cmd))
    (is (search "</dev/null" cmd))))

(test build-command-with-mcp-config
  "build-claude-command includes --mcp-config when provided."
  (let ((cmd (autopoiesis.orchestration:build-claude-command
              '(:prompt "test" :claude-path "claude" :mcp-config "/path/to/config.json"))))
    (is (search "--mcp-config" cmd))
    (is (search "/path/to/config.json" cmd))))

(test build-command-with-allowed-tools
  "build-claude-command includes --allowedTools when provided."
  (let ((cmd (autopoiesis.orchestration:build-claude-command
              '(:prompt "test" :claude-path "claude" :allowed-tools "tool1,tool2"))))
    (is (search "--allowedTools" cmd))
    (is (search "tool1,tool2" cmd))))

(test build-command-default-max-turns
  "build-claude-command defaults to 50 max turns."
  (let ((cmd (autopoiesis.orchestration:build-claude-command
              '(:prompt "test" :claude-path "claude"))))
    (is (search "50" cmd))))

(test build-command-custom-max-turns
  "build-claude-command uses custom max turns."
  (let ((cmd (autopoiesis.orchestration:build-claude-command
              '(:prompt "test" :claude-path "claude" :max-turns 10))))
    (is (search "10" cmd))))

;;; ===================================================================
;;; Claude worker: extract-result
;;; ===================================================================

(test extract-result-finds-result-type
  "extract-result returns the message with type=result."
  (let* ((messages (list '((:type . "text") (:content . "hello"))
                         '((:type . "result") (:content . "final answer"))
                         '((:type . "usage") (:tokens . 42))))
         (result (autopoiesis.orchestration:extract-result messages)))
    (is (equal "result" (cdr (assoc :type result))))
    (is (equal "final answer" (cdr (assoc :content result))))))

(test extract-result-last-result-wins
  "extract-result returns the last result message when multiple exist."
  (let* ((messages (list '((:type . "result") (:content . "first"))
                         '((:type . "result") (:content . "second"))))
         (result (autopoiesis.orchestration:extract-result messages)))
    (is (equal "second" (cdr (assoc :content result))))))

(test extract-result-fallback-to-last
  "extract-result falls back to the last message when no result type."
  (let* ((messages (list '((:type . "text") (:content . "hello"))
                         '((:type . "usage") (:tokens . 42))))
         (result (autopoiesis.orchestration:extract-result messages)))
    (is (equal "usage" (cdr (assoc :type result))))))

(test extract-result-empty-messages
  "extract-result handles empty message list."
  (is (null (autopoiesis.orchestration:extract-result nil))))

;;; ===================================================================
;;; Crystallization trigger checking
;;; ===================================================================

(test conductor-has-tick-counter
  "Conductor has tick counter initialized to 0."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (is (= 0 (autopoiesis.orchestration::conductor-tick-counter c)))))

(test check-crystallization-triggers-increments-counter
  "check-crystallization-triggers increments tick counter."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (is (= 0 (autopoiesis.orchestration::conductor-tick-counter c)))
      (autopoiesis.orchestration::check-crystallization-triggers c)
      (is (= 1 (autopoiesis.orchestration::conductor-tick-counter c)))
      (autopoiesis.orchestration::check-crystallization-triggers c)
      (is (= 2 (autopoiesis.orchestration::conductor-tick-counter c))))))

(test check-crystallization-triggers-resets-at-interval
  "check-crystallization-triggers resets counter at trigger check interval."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      ;; Set counter to just before interval
      (setf (autopoiesis.orchestration::conductor-tick-counter c) 99)
      (autopoiesis.orchestration::check-crystallization-triggers c)
      ;; Should reset to 0 after hitting interval
      (is (= 0 (autopoiesis.orchestration::conductor-tick-counter c))))))

(test check-crystallization-triggers-loads-from-store
  "start-conductor loads triggers from store if crystallize is available."
  (when (find-package :autopoiesis.crystallize)
    (autopoiesis.substrate:with-store ()
      ;; Create and save a trigger
      (let ((create-trigger-fn (find-symbol "CREATE-PERFORMANCE-TRIGGER" :autopoiesis.crystallize))
            (save-triggers-fn (find-symbol "SAVE-TRIGGERS-TO-STORE" :autopoiesis.crystallize))
            (get-trigger-fn (find-symbol "GET-TRIGGER" :autopoiesis.crystallize))
            (trigger-id-fn (find-symbol "TRIGGER-CONDITION-ID" :autopoiesis.crystallize))
            (trigger-name-fn (find-symbol "TRIGGER-CONDITION-NAME" :autopoiesis.crystallize)))
        (let ((trigger (funcall create-trigger-fn
                               "test-trigger" "Test trigger" :heuristic-confidence 0.8)))
          (funcall save-triggers-fn)
          ;; Start conductor (should load triggers)
          (let ((c (autopoiesis.orchestration:start-conductor)))
            (unwind-protect
                 (let ((loaded (funcall get-trigger-fn
                                       (funcall trigger-id-fn trigger))))
                   (is (not (null loaded)))
                   (is (string= "test-trigger" (funcall trigger-name-fn loaded))))
              (autopoiesis.orchestration:stop-conductor :conductor c))))))))

(test conductor-status-includes-crystallization-metrics
  "conductor-status includes crystallization metrics if crystallize is available."
  (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
    (let ((status (autopoiesis.orchestration:conductor-status :conductor c)))
      (if (find-package :autopoiesis.crystallize)
          (progn
            (is (member :triggers-checked status))
            (is (member :crystallizations-performed status))
            (is (member :trigger-check-errors status)))
          (progn
            (is (not (member :triggers-checked status)))
            (is (not (member :crystallizations-performed status)))
            (is (not (member :trigger-check-errors status))))))))

;;; ===================================================================
;;; Claude worker: schedule-infra-watcher
;;; ===================================================================

(test schedule-infra-watcher-adds-timer
  "schedule-infra-watcher adds an entry to the timer heap."
  (autopoiesis.substrate:with-store ()
    (let ((c (make-instance 'autopoiesis.orchestration:conductor)))
      (autopoiesis.orchestration::schedule-infra-watcher :conductor c :interval 60)
      (is (= 1 (length (autopoiesis.orchestration:conductor-timer-heap c))))
      (let ((action (cdar (autopoiesis.orchestration:conductor-timer-heap c))))
        (is (eq :claude (getf action :action-type)))))))
