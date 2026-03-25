;;;; packages.lisp - Package definition for the eval module
;;;;
;;;; Agent evaluation platform for comparing different agent systems
;;;; across standardized scenarios with hard metrics and LLM-as-judge scoring.

(defpackage #:autopoiesis.eval
  (:use #:cl)
  (:import-from #:autopoiesis.substrate
                #:transact! #:make-datom #:entity-attr #:entity-state
                #:find-entities #:find-entities-by-type #:intern-id
                #:define-entity-type #:take! #:with-batch-transaction
                #:entity-history)
  (:import-from #:autopoiesis.core
                #:make-uuid #:get-precise-time #:autopoiesis-error)
  (:export
   ;; Entity types (declared, not exported as symbols)

   ;; Scenarios
   #:create-scenario
   #:get-scenario
   #:list-scenarios
   #:delete-scenario
   #:scenario-to-alist

   ;; Harness protocol
   #:eval-harness
   #:harness-name
   #:harness-description
   #:harness-config
   #:harness-run-scenario
   #:harness-to-config-plist
   #:register-harness
   #:find-harness
   #:list-harnesses
   #:clear-harness-registry

   ;; Provider harness
   #:provider-harness
   #:make-provider-harness

   ;; Verifiers
   #:run-verifier
   #:register-verifier

   ;; Judge
   #:run-judge

   ;; Metrics
   #:compute-hard-metrics
   #:compute-squishy-metrics

   ;; Runs
   #:create-eval-run
   #:execute-eval-run
   #:get-eval-run
   #:list-eval-runs
   #:cancel-eval-run

   ;; Trials
   #:get-trial
   #:list-trials
   #:trial-to-alist

   ;; Comparison
   #:compare-harnesses
   #:compare-runs))

;; Test package defined in test/eval-tests.lisp (requires fiveam loaded first)
