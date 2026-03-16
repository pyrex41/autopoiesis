;;;; paperclip-adapter-tests.lisp - Tests for Paperclip AI BYOA adapter
;;;;
;;;; Tests agent registry, heartbeat handling, budget enforcement,
;;;; SKILLS.md generation, and event integration.

(defpackage #:autopoiesis.paperclip.test
  (:use #:cl #:fiveam)
  (:export #:run-paperclip-tests))

(in-package #:autopoiesis.paperclip.test)

(def-suite paperclip-tests
  :description "Paperclip AI BYOA adapter tests")

(in-suite paperclip-tests)

;;; ===================================================================
;;; Test Helpers
;;; ===================================================================

(defun reset-paperclip-state ()
  "Clear all Paperclip adapter state for a clean test."
  ;; Clear agents (retire all first)
  (dolist (pair (autopoiesis.paperclip:paperclip-list-agents))
    (autopoiesis.paperclip:paperclip-retire-agent (car pair)))
  ;; Clear budgets
  (bt:with-lock-held (autopoiesis.paperclip::*paperclip-budgets-lock*)
    (clrhash autopoiesis.paperclip:*paperclip-budgets*))
  ;; Clear event history for clean assertions
  (autopoiesis.integration:clear-event-history))

;;; ===================================================================
;;; Agent Registry Tests
;;; ===================================================================

(test agent-registry-create-new
  "paperclip-get-or-create-agent creates an agent for a new role"
  (reset-paperclip-state)
  (let ((agent (autopoiesis.paperclip:paperclip-get-or-create-agent "analyst")))
    (is (not (null agent)))
    (is (search "paperclip:analyst" (autopoiesis.agent:agent-name agent)))))

(test agent-registry-reuse-existing
  "paperclip-get-or-create-agent reuses agent for existing role"
  (reset-paperclip-state)
  (let ((a1 (autopoiesis.paperclip:paperclip-get-or-create-agent "worker"))
        (a2 (autopoiesis.paperclip:paperclip-get-or-create-agent "worker")))
    (is (string= (autopoiesis.agent:agent-id a1)
                  (autopoiesis.agent:agent-id a2)))))

(test agent-registry-retire
  "paperclip-retire-agent removes the agent from registry"
  (reset-paperclip-state)
  (autopoiesis.paperclip:paperclip-get-or-create-agent "temp-role")
  (is (= 1 (length (autopoiesis.paperclip:paperclip-list-agents))))
  (is (eq t (autopoiesis.paperclip:paperclip-retire-agent "temp-role")))
  (is (= 0 (length (autopoiesis.paperclip:paperclip-list-agents)))))

(test agent-registry-retire-nonexistent
  "paperclip-retire-agent returns NIL for unknown role"
  (reset-paperclip-state)
  (is (null (autopoiesis.paperclip:paperclip-retire-agent "ghost"))))

(test agent-registry-list
  "paperclip-list-agents returns all managed agents"
  (reset-paperclip-state)
  (autopoiesis.paperclip:paperclip-get-or-create-agent "role-a")
  (autopoiesis.paperclip:paperclip-get-or-create-agent "role-b")
  (let ((agents (autopoiesis.paperclip:paperclip-list-agents)))
    (is (= 2 (length agents)))
    (is (assoc "role-a" agents :test #'string=))
    (is (assoc "role-b" agents :test #'string=))))

(test agent-registry-different-roles-different-agents
  "Different roles get different agents"
  (reset-paperclip-state)
  (let ((a1 (autopoiesis.paperclip:paperclip-get-or-create-agent "alpha"))
        (a2 (autopoiesis.paperclip:paperclip-get-or-create-agent "beta")))
    (is (not (string= (autopoiesis.agent:agent-id a1)
                       (autopoiesis.agent:agent-id a2))))))

;;; ===================================================================
;;; Heartbeat Handling Tests
;;; ===================================================================

(test heartbeat-new-role-creates-agent
  "Heartbeat with new role creates agent and returns correct structure"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "researcher")
                     (:heartbeat--id . "hb-001")))))
    (is (string= "hb-001" (cdr (assoc :heartbeat--id response))))
    (is (stringp (cdr (assoc :agent--id response))))
    (is (string= "researcher" (cdr (assoc :role response))))))

(test heartbeat-existing-role-reuses-agent
  "Heartbeat with existing role reuses the same agent"
  (reset-paperclip-state)
  (let* ((r1 (autopoiesis.paperclip:handle-paperclip-heartbeat
              '((:agent--role . "coder"))))
         (r2 (autopoiesis.paperclip:handle-paperclip-heartbeat
              '((:agent--role . "coder")))))
    (is (string= (cdr (assoc :agent--id r1))
                  (cdr (assoc :agent--id r2))))))

(test heartbeat-with-task
  "Heartbeat with task returns completed status"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "tasker")
                     (:task . "analyze data")))))
    (is (string= "completed" (cdr (assoc :status response))))))

(test heartbeat-without-task
  "Heartbeat without task returns idle status"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "idler")))))
    (is (string= "idle" (cdr (assoc :status response))))))

(test heartbeat-includes-cost-report
  "Heartbeat response includes cost_report"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "spender")
                     (:task . "do work")
                     (:estimated--cost . 0.05)))))
    (is (not (null (cdr (assoc :cost--report response)))))))

(test heartbeat-includes-capabilities
  "Heartbeat response includes capabilities list"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "capable")))))
    (is (listp (cdr (assoc :capabilities response))))))

(test heartbeat-auto-generates-id
  "Heartbeat without heartbeat_id auto-generates one"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "auto-id")))))
    (is (not (null (cdr (assoc :heartbeat--id response)))))
    (is (stringp (cdr (assoc :heartbeat--id response))))))

(test heartbeat-default-role
  "Heartbeat without role uses 'default'"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat '())))
    (is (string= "default" (cdr (assoc :role response))))))

;;; ===================================================================
;;; Paperclip-Native Payload Tests
;;; ===================================================================

(test paperclip-native-heartbeat-basic
  "Paperclip-native payload maps agentId→role and runId→heartbeat-id"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent-id . "pc-agent-001")
                     (:run-id . "run-42")))))
    (is (string= "run-42" (cdr (assoc :heartbeat--id response))))
    (is (string= "pc-agent-001" (cdr (assoc :role response))))
    (is (string= "idle" (cdr (assoc :status response))))))

(test paperclip-native-heartbeat-with-task-key
  "Paperclip-native context.taskKey triggers cognitive cycle"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent-id . "pc-tasker")
                     (:run-id . "run-99")
                     (:context . ((:task-key . "analyze data")))))))
    (is (string= "completed" (cdr (assoc :status response))))))

(test paperclip-native-heartbeat-creates-agent
  "Paperclip-native agentId is used as registry key"
  (reset-paperclip-state)
  (autopoiesis.paperclip:handle-paperclip-heartbeat
   '((:agent-id . "pc-reg-test")
     (:run-id . "run-1")))
  (let ((agents (autopoiesis.paperclip:paperclip-list-agents)))
    (is (assoc "pc-reg-test" agents :test #'string=))))

(test paperclip-native-heartbeat-reuses-agent
  "Same agentId returns same agent across heartbeats"
  (reset-paperclip-state)
  (let* ((r1 (autopoiesis.paperclip:handle-paperclip-heartbeat
              '((:agent-id . "pc-reuse"))))
         (r2 (autopoiesis.paperclip:handle-paperclip-heartbeat
              '((:agent-id . "pc-reuse")))))
    (is (string= (cdr (assoc :agent--id r1))
                  (cdr (assoc :agent--id r2))))))

(test paperclip-native-auto-generates-heartbeat-id
  "Missing runId auto-generates a string heartbeat ID"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent-id . "pc-no-run")))))
    (is (not (null (cdr (assoc :heartbeat--id response)))))
    (is (stringp (cdr (assoc :heartbeat--id response))))))

(test paperclip-native-context-task-fallback
  "context.task is used when no taskKey present"
  (reset-paperclip-state)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent-id . "pc-fallback")
                     (:run-id . "run-fb")
                     (:context . ((:task . "fallback task")))))))
    (is (string= "completed" (cdr (assoc :status response))))))

;;; ===================================================================
;;; Budget Enforcement Tests
;;; ===================================================================

(test budget-no-limit-returns-ok
  "check-paperclip-budget returns :OK when no limit set"
  (reset-paperclip-state)
  (is (eq :ok (autopoiesis.paperclip:check-paperclip-budget "unlim" 100))))

(test budget-under-limit-returns-ok
  "check-paperclip-budget returns :OK when under limit"
  (reset-paperclip-state)
  (autopoiesis.paperclip:update-paperclip-budget "budgeted" :limit 10.0)
  (is (eq :ok (autopoiesis.paperclip:check-paperclip-budget "budgeted" 1.0))))

(test budget-at-80-percent-returns-warning
  "check-paperclip-budget returns :WARNING at 80%"
  (reset-paperclip-state)
  (autopoiesis.paperclip:update-paperclip-budget "warn-test" :limit 10.0)
  ;; Accumulate some spend first
  (autopoiesis.paperclip::record-paperclip-cost "warn-test" 7.5)
  ;; 7.5 + 0.5 = 8.0 = exactly 80%
  (is (eq :warning (autopoiesis.paperclip:check-paperclip-budget "warn-test" 0.5))))

(test budget-over-limit-returns-exceeded
  "check-paperclip-budget returns :EXCEEDED when over limit"
  (reset-paperclip-state)
  (autopoiesis.paperclip:update-paperclip-budget "over-test" :limit 5.0)
  (autopoiesis.paperclip::record-paperclip-cost "over-test" 4.5)
  (is (eq :exceeded (autopoiesis.paperclip:check-paperclip-budget "over-test" 1.0))))

(test budget-accumulation
  "Budget accumulates across multiple cost recordings"
  (reset-paperclip-state)
  (autopoiesis.paperclip:update-paperclip-budget "accum" :limit 10.0)
  (autopoiesis.paperclip::record-paperclip-cost "accum" 2.0)
  (autopoiesis.paperclip::record-paperclip-cost "accum" 3.0)
  ;; 2 + 3 = 5 spent; 5 + 4 = 9 projected = 90% → warning
  (is (eq :warning (autopoiesis.paperclip:check-paperclip-budget "accum" 4.0)))
  ;; 5 + 6 = 11 projected = 110% → exceeded
  (is (eq :exceeded (autopoiesis.paperclip:check-paperclip-budget "accum" 6.0))))

(test budget-heartbeat-rejected-when-exceeded
  "Heartbeat is rejected when budget is exceeded"
  (reset-paperclip-state)
  (autopoiesis.paperclip:update-paperclip-budget "broke" :limit 1.0)
  (autopoiesis.paperclip::record-paperclip-cost "broke" 1.0)
  (let ((response (autopoiesis.paperclip:handle-paperclip-heartbeat
                   '((:agent--role . "broke")
                     (:task . "expensive task")
                     (:estimated--cost . 0.5)))))
    (is (string= "budget_exceeded" (cdr (assoc :status response))))))

(test budget-update-sets-limit
  "update-paperclip-budget sets the limit correctly"
  (reset-paperclip-state)
  (let ((budget (autopoiesis.paperclip:update-paperclip-budget "setter"
                                                                :limit 50.0
                                                                :currency "EUR")))
    (is (= 50.0 (getf budget :limit)))
    (is (string= "EUR" (getf budget :currency)))))

;;; ===================================================================
;;; SKILLS.md Generation Tests
;;; ===================================================================

(test skills-md-is-string
  "generate-skills-md returns a string"
  (reset-paperclip-state)
  (is (stringp (autopoiesis.paperclip:generate-skills-md))))

(test skills-md-contains-standard-section
  "generate-skills-md includes Standard Capabilities section"
  (let ((md (autopoiesis.paperclip:generate-skills-md)))
    (is (search "Standard Capabilities" md))))

(test skills-md-contains-unique-section
  "generate-skills-md includes Unique Capabilities section"
  (let ((md (autopoiesis.paperclip:generate-skills-md)))
    (is (search "Unique Capabilities" md))))

(test skills-md-mentions-fork
  "generate-skills-md mentions fork capability"
  (let ((md (autopoiesis.paperclip:generate-skills-md)))
    (is (search "fork" md))))

(test skills-md-mentions-snapshot
  "generate-skills-md mentions snapshot capability"
  (let ((md (autopoiesis.paperclip:generate-skills-md)))
    (is (search "snapshot" md))))

(test skills-md-mentions-time-travel
  "generate-skills-md mentions time-travel capability"
  (let ((md (autopoiesis.paperclip:generate-skills-md)))
    (is (search "time-travel" md))))

;;; ===================================================================
;;; Event Integration Tests
;;; ===================================================================

(test heartbeat-emits-received-event
  "Heartbeat emits :paperclip-heartbeat-received event"
  (reset-paperclip-state)
  (autopoiesis.paperclip:handle-paperclip-heartbeat
   '((:agent--role . "eventer")
     (:heartbeat--id . "ev-001")))
  (let ((events (autopoiesis.integration:get-event-history
                 :type :paperclip-heartbeat-received)))
    (is (>= (length events) 1))))

(test heartbeat-emits-responded-event
  "Heartbeat emits :paperclip-heartbeat-responded event"
  (reset-paperclip-state)
  (autopoiesis.paperclip:handle-paperclip-heartbeat
   '((:agent--role . "eventer2")
     (:heartbeat--id . "ev-002")))
  (let ((events (autopoiesis.integration:get-event-history
                 :type :paperclip-heartbeat-responded)))
    (is (>= (length events) 1))))

;;; ===================================================================
;;; Adapter Loaded Flag Test
;;; ===================================================================

(test adapter-loaded-flag
  "Adapter loaded flag is T after loading"
  (is (eq t autopoiesis.paperclip:*paperclip-adapter-loaded*)))

;;; ===================================================================
;;; Test Runner
;;; ===================================================================

(defun run-paperclip-tests ()
  "Run all Paperclip adapter tests."
  (let ((results (run 'paperclip-tests)))
    (explain! results)
    results))
