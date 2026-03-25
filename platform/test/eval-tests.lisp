;;;; eval-tests.lisp - Tests for the eval module
;;;;
;;;; Tests scenario CRUD, harness protocol, verifiers, metrics,
;;;; eval run execution, and comparison.

(defpackage #:autopoiesis.eval.test
  (:use #:cl #:fiveam)
  (:export #:run-eval-tests))

(in-package #:autopoiesis.eval.test)

(def-suite eval-tests
  :description "Tests for the agent evaluation platform")

(in-suite eval-tests)

(defun run-eval-tests ()
  "Run all eval tests."
  (run! 'eval-tests))

;;; ===================================================================
;;; Mock Harness for Testing
;;; ===================================================================

(defclass mock-harness (autopoiesis.eval:eval-harness)
  ((mock-output :initarg :mock-output :accessor mock-output :initform "Hello, World!")
   (mock-cost :initarg :mock-cost :accessor mock-cost :initform 0.01)
   (mock-turns :initarg :mock-turns :accessor mock-turns :initform 3)
   (mock-duration :initarg :mock-duration :accessor mock-duration :initform 1.5)
   (mock-exit-code :initarg :mock-exit-code :accessor mock-exit-code :initform 0)
   (invoke-count :initarg :invoke-count :accessor mock-invoke-count :initform 0))
  (:documentation "Mock harness for testing that returns configurable results."))

(defmethod autopoiesis.eval:harness-run-scenario
    ((harness mock-harness) scenario-plist &key timeout)
  (declare (ignore timeout))
  (incf (mock-invoke-count harness))
  (let* ((verifier (getf scenario-plist :eval-scenario/verifier))
         (expected (getf scenario-plist :eval-scenario/expected))
         (output (mock-output harness))
         (passed (if verifier
                     (autopoiesis.eval:run-verifier verifier output
                                                     :expected expected
                                                     :exit-code (mock-exit-code harness))
                     nil)))
    (list :output output
          :tool-calls nil
          :duration (mock-duration harness)
          :cost (mock-cost harness)
          :turns (mock-turns harness)
          :exit-code (mock-exit-code harness)
          :passed passed
          :metadata nil)))

;;; ===================================================================
;;; Scenario Tests
;;; ===================================================================

(test scenario-create
  "Creating a scenario stores it in the substrate."
  (autopoiesis.substrate:with-store ()
    (let ((sid (autopoiesis.eval:create-scenario
                :name "Test Scenario"
                :description "A test scenario"
                :prompt "Write hello world"
                :domain :coding
                :tags '(:basic :test))))
      (is (not (null sid)))
      (is (equal "Test Scenario"
                 (autopoiesis.substrate:entity-attr sid :eval-scenario/name)))
      (is (equal "Write hello world"
                 (autopoiesis.substrate:entity-attr sid :eval-scenario/prompt)))
      (is (eq :coding
              (autopoiesis.substrate:entity-attr sid :eval-scenario/domain)))
      (is (equal '(:basic :test)
                 (autopoiesis.substrate:entity-attr sid :eval-scenario/tags))))))

(test scenario-create-with-verifier
  "Creating a scenario with verifier and rubric."
  (autopoiesis.substrate:with-store ()
    (let ((sid (autopoiesis.eval:create-scenario
                :name "Verified"
                :description "Has verifier"
                :prompt "Do something"
                :verifier '(:type :contains :value "expected")
                :rubric "Evaluate for correctness")))
      (is (equal '(:type :contains :value "expected")
                 (autopoiesis.substrate:entity-attr sid :eval-scenario/verifier)))
      (is (equal "Evaluate for correctness"
                 (autopoiesis.substrate:entity-attr sid :eval-scenario/rubric))))))

(test scenario-create-requires-fields
  "Creating a scenario without required fields signals an error."
  (autopoiesis.substrate:with-store ()
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.eval:create-scenario :name "incomplete"))))

(test scenario-get
  "Getting a scenario returns its full state."
  (autopoiesis.substrate:with-store ()
    (let* ((sid (autopoiesis.eval:create-scenario
                 :name "Get Test"
                 :description "Get test"
                 :prompt "Hello"))
           (state (autopoiesis.eval:get-scenario sid)))
      (is (not (null state)))
      (is (equal "Get Test" (getf state :eval-scenario/name))))))

(test scenario-list
  "Listing scenarios returns all scenarios."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:create-scenario
     :name "S1" :description "D1" :prompt "P1" :domain :coding)
    (autopoiesis.eval:create-scenario
     :name "S2" :description "D2" :prompt "P2" :domain :research)
    (autopoiesis.eval:create-scenario
     :name "S3" :description "D3" :prompt "P3" :domain :coding)
    (let ((all (autopoiesis.eval:list-scenarios)))
      (is (= 3 (length all))))
    (let ((coding (autopoiesis.eval:list-scenarios :domain :coding)))
      (is (= 2 (length coding))))
    (let ((research (autopoiesis.eval:list-scenarios :domain :research)))
      (is (= 1 (length research))))))

(test scenario-to-alist
  "Scenario serialization produces correct alist."
  (autopoiesis.substrate:with-store ()
    (let* ((sid (autopoiesis.eval:create-scenario
                 :name "Alist Test"
                 :description "Desc"
                 :prompt "Prompt"
                 :domain :coding
                 :verifier :exit-zero))
           (alist (autopoiesis.eval:scenario-to-alist sid)))
      (is (equal "Alist Test" (cdr (assoc :name alist))))
      (is (equal "coding" (cdr (assoc :domain alist))))
      (is (eq t (cdr (assoc :has-verifier alist)))))))

(test scenario-delete
  "Deleting a scenario removes it from listings."
  (autopoiesis.substrate:with-store ()
    (let ((sid (autopoiesis.eval:create-scenario
                :name "Delete Me" :description "D" :prompt "P")))
      (is (= 1 (length (autopoiesis.eval:list-scenarios))))
      (autopoiesis.eval:delete-scenario sid)
      (is (= 0 (length (autopoiesis.eval:list-scenarios)))))))

;;; ===================================================================
;;; Harness Registry Tests
;;; ===================================================================

(test harness-registry
  "Harness registration and lookup."
  (autopoiesis.eval:clear-harness-registry)
  (let ((h (make-instance 'mock-harness :name "test-harness")))
    (autopoiesis.eval:register-harness h)
    (is (eq h (autopoiesis.eval:find-harness "test-harness")))
    (is (null (autopoiesis.eval:find-harness "nonexistent")))
    (is (= 1 (length (autopoiesis.eval:list-harnesses))))
    (autopoiesis.eval:clear-harness-registry)))

(test harness-run-mock
  "Mock harness executes and returns correct result."
  (let ((h (make-instance 'mock-harness
                          :name "mock"
                          :mock-output "result text"
                          :mock-cost 0.05
                          :mock-turns 5)))
    (let ((result (autopoiesis.eval:harness-run-scenario
                   h
                   (list :eval-scenario/prompt "test prompt"))))
      (is (equal "result text" (getf result :output)))
      (is (= 0.05 (getf result :cost)))
      (is (= 5 (getf result :turns)))
      (is (= 1 (mock-invoke-count h))))))

;;; ===================================================================
;;; Verifier Tests
;;; ===================================================================

(test verifier-exit-zero
  "Exit-zero verifier checks exit code."
  (is (eq :pass (autopoiesis.eval:run-verifier :exit-zero "output" :exit-code 0)))
  (is (eq :fail (autopoiesis.eval:run-verifier :exit-zero "output" :exit-code 1))))

(test verifier-contains
  "Contains verifier checks for substring."
  (is (eq :pass (autopoiesis.eval:run-verifier :contains "hello world" :expected "world")))
  (is (eq :fail (autopoiesis.eval:run-verifier :contains "hello world" :expected "xyz")))
  (is (eq :fail (autopoiesis.eval:run-verifier :contains nil :expected "x"))))

(test verifier-regex
  "Regex verifier checks for pattern match."
  (is (eq :pass (autopoiesis.eval:run-verifier :regex "hello 42 world" :expected "\\d+")))
  (is (eq :fail (autopoiesis.eval:run-verifier :regex "hello world" :expected "\\d+"))))

(test verifier-plist-form
  "Plist verifier form dispatches correctly."
  (is (eq :pass (autopoiesis.eval:run-verifier
                 '(:type :contains :value "hello")
                 "hello world")))
  (is (eq :fail (autopoiesis.eval:run-verifier
                 '(:type :contains :value "xyz")
                 "hello world"))))

(test verifier-non-empty
  "Non-empty verifier checks for content."
  (is (eq :pass (autopoiesis.eval:run-verifier :non-empty "text")))
  (is (eq :fail (autopoiesis.eval:run-verifier :non-empty "")))
  (is (eq :fail (autopoiesis.eval:run-verifier :non-empty nil))))

(test verifier-exact-match
  "Exact-match verifier checks string equality."
  (is (eq :pass (autopoiesis.eval:run-verifier :exact-match "abc" :expected "abc")))
  (is (eq :fail (autopoiesis.eval:run-verifier :exact-match "abc" :expected "abd"))))

(test verifier-unknown-keyword
  "Unknown verifier keyword returns :error."
  (is (eq :error (autopoiesis.eval:run-verifier :nonexistent "output"))))

;;; ===================================================================
;;; Metrics Tests
;;; ===================================================================

(test hard-metrics-basic
  "Hard metrics computation from trial plists."
  (let* ((trials (list
                  (list :eval-trial/passed :pass :eval-trial/duration 1.0
                        :eval-trial/cost 0.01 :eval-trial/turns 3)
                  (list :eval-trial/passed :pass :eval-trial/duration 2.0
                        :eval-trial/cost 0.02 :eval-trial/turns 5)
                  (list :eval-trial/passed :fail :eval-trial/duration 1.5
                        :eval-trial/cost 0.015 :eval-trial/turns 4)))
         (metrics (autopoiesis.eval:compute-hard-metrics trials)))
    (is (= 3 (getf metrics :total-trials)))
    (is (= 2 (getf metrics :passed)))
    (is (= 1 (getf metrics :failed)))
    (is (< 0.66 (getf metrics :pass-rate) 0.67))
    (is (= 1.5 (getf metrics :p50-duration)))
    (is (< 0.044 (getf metrics :total-cost) 0.046))))

(test hard-metrics-empty
  "Hard metrics with empty trial list."
  (let ((metrics (autopoiesis.eval:compute-hard-metrics nil)))
    (is (= 0 (getf metrics :total-trials)))
    (is (= 0.0 (getf metrics :pass-rate)))))

(test squishy-metrics-basic
  "Squishy metrics computation from judge scores."
  (let* ((trials (list
                  (list :eval-trial/judge-scores
                        '(("score" . 8) ("correctness" . 9) ("style" . 7)))
                  (list :eval-trial/judge-scores
                        '(("score" . 6) ("correctness" . 7) ("style" . 5)))))
         (metrics (autopoiesis.eval:compute-squishy-metrics trials)))
    (is (= 2 (getf metrics :trials-judged)))
    (is (= 7.0 (getf metrics :avg-overall-score)))
    (is (not (null (getf metrics :dimension-averages))))))

;;; ===================================================================
;;; Eval Run Tests
;;; ===================================================================

(test eval-run-creation
  "Creating an eval run creates the correct number of trials."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (let* ((s1 (autopoiesis.eval:create-scenario
                :name "S1" :description "D" :prompt "P"))
           (s2 (autopoiesis.eval:create-scenario
                :name "S2" :description "D" :prompt "P"))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Test Run"
                    :scenarios (list s1 s2)
                    :harnesses '("h1" "h2")
                    :trials 3)))
      ;; 2 scenarios * 2 harnesses * 3 trials = 12 trials
      (is (= 12 (length (autopoiesis.eval:list-trials run-id))))
      (is (eq :pending (autopoiesis.substrate:entity-attr run-id :eval-run/status)))
      ;; Check trial distribution
      (is (= 6 (length (autopoiesis.eval:list-trials run-id :harness "h1"))))
      (is (= 6 (length (autopoiesis.eval:list-trials run-id :harness "h2"))))
      (is (= 6 (length (autopoiesis.eval:list-trials run-id :scenario s1))))
      (is (= 6 (length (autopoiesis.eval:list-trials run-id :scenario s2)))))))

(test eval-run-execution
  "Executing an eval run processes all trials through harnesses."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (let* ((mock-h1 (make-instance 'mock-harness
                                    :name "mock-pass"
                                    :mock-output "pass output"
                                    :mock-exit-code 0))
           (mock-h2 (make-instance 'mock-harness
                                    :name "mock-fail"
                                    :mock-output "fail output"
                                    :mock-exit-code 1)))
      (autopoiesis.eval:register-harness mock-h1)
      (autopoiesis.eval:register-harness mock-h2)
      (let* ((s1 (autopoiesis.eval:create-scenario
                  :name "S1" :description "D" :prompt "P"
                  :verifier :exit-zero))
             (run-id (autopoiesis.eval:create-eval-run
                      :name "Exec Test"
                      :scenarios (list s1)
                      :harnesses '("mock-pass" "mock-fail")
                      :trials 2)))
        (autopoiesis.eval:execute-eval-run run-id)
        ;; Run should be complete
        (is (eq :complete (autopoiesis.substrate:entity-attr run-id :eval-run/status)))
        ;; All trials should be complete
        (let ((trials (autopoiesis.eval:list-trials run-id)))
          (is (= 4 (length trials)))
          (dolist (eid trials)
            (is (eq :complete (autopoiesis.substrate:entity-attr eid :eval-trial/status)))))
        ;; mock-pass trials should pass, mock-fail should fail
        (let ((pass-trials (autopoiesis.eval:list-trials run-id :harness "mock-pass")))
          (dolist (eid pass-trials)
            (is (eq :pass (autopoiesis.substrate:entity-attr eid :eval-trial/passed)))))
        (let ((fail-trials (autopoiesis.eval:list-trials run-id :harness "mock-fail")))
          (dolist (eid fail-trials)
            (is (eq :fail (autopoiesis.substrate:entity-attr eid :eval-trial/passed)))))
        ;; Mock harnesses should have been invoked
        (is (= 2 (mock-invoke-count mock-h1)))
        (is (= 2 (mock-invoke-count mock-h2)))))))

(test eval-run-get
  "Getting an eval run includes trial summary."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "m"))
    (let* ((s (autopoiesis.eval:create-scenario
               :name "S" :description "D" :prompt "P"))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Get Test"
                    :scenarios (list s)
                    :harnesses '("m")
                    :trials 2))
           (run-data (autopoiesis.eval:get-eval-run run-id)))
      (is (equal "Get Test" (getf run-data :eval-run/name)))
      (let ((summary (getf run-data :trial-summary)))
        (is (= 2 (getf summary :total)))
        (is (= 2 (getf summary :pending)))))))

(test eval-run-list
  "Listing eval runs with status filter."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "m"))
    (let ((s (autopoiesis.eval:create-scenario
              :name "S" :description "D" :prompt "P")))
      (autopoiesis.eval:create-eval-run
       :name "R1" :scenarios (list s) :harnesses '("m") :trials 1)
      (let ((r2 (autopoiesis.eval:create-eval-run
                 :name "R2" :scenarios (list s) :harnesses '("m") :trials 1)))
        (autopoiesis.eval:execute-eval-run r2)
        (is (= 2 (length (autopoiesis.eval:list-eval-runs))))
        (is (= 1 (length (autopoiesis.eval:list-eval-runs :status :pending))))
        (is (= 1 (length (autopoiesis.eval:list-eval-runs :status :complete))))))))

;;; ===================================================================
;;; Comparison Tests
;;; ===================================================================

(test compare-harnesses-basic
  "Comparing harnesses within a run produces correct structure."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "fast"
                    :mock-duration 0.5 :mock-cost 0.01 :mock-exit-code 0))
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "slow"
                    :mock-duration 5.0 :mock-cost 0.10 :mock-exit-code 0))
    (let* ((s (autopoiesis.eval:create-scenario
               :name "S" :description "D" :prompt "P" :verifier :exit-zero))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Compare Test"
                    :scenarios (list s)
                    :harnesses '("fast" "slow")
                    :trials 2)))
      (autopoiesis.eval:execute-eval-run run-id)
      (let ((comparison (autopoiesis.eval:compare-harnesses run-id)))
        ;; Should have comparison structure
        (is (not (null comparison)))
        (is (equal "Compare Test" (getf comparison :run-name)))
        ;; Should have scenarios section
        (is (= 1 (length (getf comparison :scenarios))))
        ;; Should have aggregate section with both harnesses
        (let ((agg (getf comparison :aggregate)))
          (is (= 2 (length agg)))
          ;; Both should have 100% pass rate
          (dolist (h agg)
            (is (= 1.0 (getf h :overall-pass-rate)))))))))

(test compare-harnesses-mixed-results
  "Comparison with mixed pass/fail results."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "good" :mock-exit-code 0))
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "bad" :mock-exit-code 1))
    (let* ((s (autopoiesis.eval:create-scenario
               :name "S" :description "D" :prompt "P" :verifier :exit-zero))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Mixed"
                    :scenarios (list s)
                    :harnesses '("good" "bad")
                    :trials 3)))
      (autopoiesis.eval:execute-eval-run run-id)
      (let* ((comparison (autopoiesis.eval:compare-harnesses run-id))
             (agg (getf comparison :aggregate))
             (good-stats (find "good" agg :key (lambda (h) (getf h :harness)) :test #'string=))
             (bad-stats (find "bad" agg :key (lambda (h) (getf h :harness)) :test #'string=)))
        (is (= 1.0 (getf good-stats :overall-pass-rate)))
        (is (= 0.0 (getf bad-stats :overall-pass-rate)))))))

(test trial-to-alist-format
  "Trial serialization produces correct alist format."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "m" :mock-cost 0.05 :mock-turns 4))
    (let* ((s (autopoiesis.eval:create-scenario
               :name "S" :description "D" :prompt "P" :verifier :exit-zero))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Alist Test"
                    :scenarios (list s)
                    :harnesses '("m")
                    :trials 1)))
      (autopoiesis.eval:execute-eval-run run-id)
      (let* ((trial-eid (first (autopoiesis.eval:list-trials run-id)))
             (alist (autopoiesis.eval:trial-to-alist trial-eid)))
        (is (not (null alist)))
        (is (equal "m" (cdr (assoc :harness alist))))
        (is (equal "complete" (cdr (assoc :status alist))))
        (is (= 0.05 (cdr (assoc :cost alist))))
        (is (= 4 (cdr (assoc :turns alist))))
        (is (equal "pass" (cdr (assoc :passed alist))))))))

;;; ===================================================================
;;; Judge Response Parsing Tests
;;; ===================================================================

(test judge-parse-valid-json
  "Parsing valid judge JSON response."
  (let ((result (autopoiesis.eval::parse-judge-response
                 "{\"score\": 8, \"dimensions\": {\"correctness\": 9, \"style\": 7}, \"reasoning\": \"Good work\"}")))
    (is (not (null result)))
    (is (= 8 (getf result :score)))
    (is (equal "Good work" (getf result :reasoning)))
    (is (= 2 (length (getf result :dimensions))))))

(test judge-parse-with-markdown-fences
  "Parsing judge response wrapped in markdown code fences."
  (let ((result (autopoiesis.eval::parse-judge-response
                 "```json
{\"score\": 7, \"dimensions\": {}, \"reasoning\": \"OK\"}
```")))
    (is (not (null result)))
    (is (= 7 (getf result :score)))))

(test judge-parse-invalid-json
  "Parsing invalid JSON returns nil."
  (is (null (autopoiesis.eval::parse-judge-response "not json at all")))
  (is (null (autopoiesis.eval::parse-judge-response ""))))

;;; ===================================================================
;;; Shell Harness Tests
;;; ===================================================================

(test shell-harness-basic
  "Shell harness executes a command and captures output."
  (autopoiesis.substrate:with-store ()
    (let ((h (autopoiesis.eval:make-shell-harness
              "echo-test" "echo 'hello from shell'")))
      (let ((result (autopoiesis.eval:harness-run-scenario
                     h (list :eval-scenario/prompt "test"))))
        (is (not (null (getf result :output))))
        (is (search "hello from shell" (getf result :output)))
        (is (eql 0 (getf result :exit-code)))
        (is (numberp (getf result :duration)))))))

(test shell-harness-with-prompt
  "Shell harness interpolates {{prompt}} in command."
  (autopoiesis.substrate:with-store ()
    (let ((h (autopoiesis.eval:make-shell-harness
              "echo-prompt" "echo {{prompt}}")))
      (let ((result (autopoiesis.eval:harness-run-scenario
                     h (list :eval-scenario/prompt "interpolated text"))))
        (is (search "interpolated text" (getf result :output)))))))

(test shell-harness-with-verifier
  "Shell harness runs verifier against output."
  (autopoiesis.substrate:with-store ()
    (let ((h (autopoiesis.eval:make-shell-harness
              "verify-test" "echo 'expected output here'")))
      (let ((result (autopoiesis.eval:harness-run-scenario
                     h (list :eval-scenario/prompt "test"
                             :eval-scenario/verifier '(:type :contains :value "expected output")))))
        (is (eq :pass (getf result :passed)))))))

(test shell-harness-failure
  "Shell harness captures non-zero exit codes."
  (autopoiesis.substrate:with-store ()
    (let ((h (autopoiesis.eval:make-shell-harness
              "fail-test" "exit 1")))
      (let ((result (autopoiesis.eval:harness-run-scenario
                     h (list :eval-scenario/prompt "test"
                             :eval-scenario/verifier :exit-zero))))
        (is (eql 1 (getf result :exit-code)))
        (is (eq :fail (getf result :passed)))))))

(test shell-harness-in-eval-run
  "Shell harness works within a full eval run."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (autopoiesis.eval:make-shell-harness "echo-h" "echo 'hello world'"))
    (let* ((s (autopoiesis.eval:create-scenario
               :name "Shell Scenario"
               :description "Test shell harness in run"
               :prompt "test"
               :verifier '(:type :contains :value "hello")))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Shell Run"
                    :scenarios (list s)
                    :harnesses '("echo-h")
                    :trials 2)))
      (autopoiesis.eval:execute-eval-run run-id)
      (is (eq :complete (autopoiesis.substrate:entity-attr run-id :eval-run/status)))
      (let ((trials (autopoiesis.eval:list-trials run-id)))
        (is (= 2 (length trials)))
        (dolist (eid trials)
          (is (eq :pass (autopoiesis.substrate:entity-attr eid :eval-trial/passed))))))))

;;; ===================================================================
;;; Template Interpolation Tests
;;; ===================================================================

(test template-interpolation
  "Template interpolation handles special characters."
  (is (string= "echo 'hello'" (autopoiesis.eval::interpolate-template "echo {{prompt}}" "hello")))
  ;; Should shell-escape quotes
  (let ((result (autopoiesis.eval::interpolate-template "echo {{prompt}}" "it's a test")))
    (is (search "it" result))))

;;; ===================================================================
;;; Ralph Harness Tests (structural only - no actual ralph execution)
;;; ===================================================================

(test ralph-harness-creation
  "Ralph harness can be created with configuration."
  (let ((h (autopoiesis.eval:make-ralph-harness
            "ralph-test"
            :backend "claude"
            :mode "build"
            :max-iterations 3)))
    (is (equal "ralph-test" (autopoiesis.eval:harness-name h)))
    (is (equal "claude" (autopoiesis.eval::rh-backend h)))
    (is (equal "build" (autopoiesis.eval::rh-mode h)))
    (is (= 3 (autopoiesis.eval::rh-max-iterations h)))))

(test ralph-harness-config-plist
  "Ralph harness serializes to config plist."
  (let* ((h (autopoiesis.eval:make-ralph-harness
             "ralph-opus" :backend "claude" :max-iterations 10))
         (config (autopoiesis.eval:harness-to-config-plist h)))
    (is (equal "ralph" (getf config :type)))
    (is (equal "ralph-opus" (getf config :name)))
    (is (equal "claude" (getf config :backend)))
    (is (= 10 (getf config :max-iterations)))))

;;; ===================================================================
;;; Team Harness Tests (structural only - team layer may not be loaded)
;;; ===================================================================

(test team-harness-creation
  "Team harness can be created with configuration."
  (let ((h (autopoiesis.eval:make-team-harness
            "debate-3"
            :strategy :debate
            :team-size 3
            :provider-name "claude-code")))
    (is (equal "debate-3" (autopoiesis.eval:harness-name h)))
    (is (eq :debate (autopoiesis.eval::th-strategy h)))
    (is (= 3 (autopoiesis.eval::th-team-size h)))
    (is (equal "claude-code" (autopoiesis.eval::th-provider-name h)))))

(test team-harness-config-plist
  "Team harness serializes to config plist."
  (let* ((h (autopoiesis.eval:make-team-harness
             "parallel-5" :strategy :parallel :team-size 5))
         (config (autopoiesis.eval:harness-to-config-plist h)))
    (is (equal "team" (getf config :type)))
    (is (eq :parallel (getf config :strategy)))
    (is (= 5 (getf config :team-size)))))

;;; ===================================================================
;;; Builtin Scenarios Tests
;;; ===================================================================

(test builtin-scenarios-load
  "Builtin scenarios load without error."
  (autopoiesis.substrate:with-store ()
    (setf autopoiesis.eval::*builtin-scenarios-loaded* nil)
    (let ((count (autopoiesis.eval:load-builtin-scenarios)))
      (is (> count 10))
      (is (>= (length (autopoiesis.eval:list-scenarios)) 10)))))

(test builtin-scenarios-domains
  "Builtin scenarios cover multiple domains."
  (autopoiesis.substrate:with-store ()
    (setf autopoiesis.eval::*builtin-scenarios-loaded* nil)
    (autopoiesis.eval:load-builtin-scenarios)
    (let ((coding (autopoiesis.eval:list-scenarios :domain :coding))
          (refactoring (autopoiesis.eval:list-scenarios :domain :refactoring))
          (research (autopoiesis.eval:list-scenarios :domain :research))
          (tool-use (autopoiesis.eval:list-scenarios :domain :tool-use))
          (reasoning (autopoiesis.eval:list-scenarios :domain :reasoning)))
      (is (>= (length coding) 4))
      (is (>= (length refactoring) 1))
      (is (>= (length research) 1))
      (is (>= (length tool-use) 1))
      (is (>= (length reasoning) 1)))))

(test builtin-scenarios-have-verifiers
  "Builtin scenarios include verifiers."
  (autopoiesis.substrate:with-store ()
    (setf autopoiesis.eval::*builtin-scenarios-loaded* nil)
    (autopoiesis.eval:load-builtin-scenarios)
    (let* ((all (autopoiesis.eval:list-scenarios))
           (with-verifier (remove-if-not
                           (lambda (eid)
                             (autopoiesis.substrate:entity-attr eid :eval-scenario/verifier))
                           all)))
      (is (>= (length with-verifier) 10)))))

(test builtin-scenarios-have-rubrics
  "Builtin scenarios include rubrics for LLM judge."
  (autopoiesis.substrate:with-store ()
    (setf autopoiesis.eval::*builtin-scenarios-loaded* nil)
    (autopoiesis.eval:load-builtin-scenarios)
    (let* ((all (autopoiesis.eval:list-scenarios))
           (with-rubric (remove-if-not
                         (lambda (eid)
                           (autopoiesis.substrate:entity-attr eid :eval-scenario/rubric))
                         all)))
      (is (>= (length with-rubric) 10)))))

(test builtin-scenarios-idempotent
  "Loading builtin scenarios twice doesn't duplicate."
  (autopoiesis.substrate:with-store ()
    (setf autopoiesis.eval::*builtin-scenarios-loaded* nil)
    (let ((count1 (autopoiesis.eval:load-builtin-scenarios))
          (count2 (autopoiesis.eval:load-builtin-scenarios)))
      (declare (ignore count2))
      (is (= count1 (length (autopoiesis.eval:list-scenarios)))))))

;;; ===================================================================
;;; History / Summary Tests
;;; ===================================================================

(test eval-summary-basic
  "Eval summary returns correct structure."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "m" :mock-exit-code 0))
    (let* ((s (autopoiesis.eval:create-scenario
               :name "S" :description "D" :prompt "P" :verifier :exit-zero))
           (run-id (autopoiesis.eval:create-eval-run
                    :name "Summary Run"
                    :scenarios (list s) :harnesses '("m") :trials 2)))
      (autopoiesis.eval:execute-eval-run run-id)
      (let ((summary (autopoiesis.eval:eval-summary)))
        (is (= 1 (getf summary :total-scenarios)))
        (is (= 1 (getf summary :total-runs)))
        (is (= 1 (getf summary :completed-runs)))
        (is (= 2 (getf summary :total-trials)))
        (is (= 1 (getf summary :active-harnesses)))))))

(test harness-performance-history-basic
  "Harness history returns run-by-run data."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.eval:clear-harness-registry)
    (autopoiesis.eval:register-harness
     (make-instance 'mock-harness :name "h1" :mock-exit-code 0))
    (let ((s (autopoiesis.eval:create-scenario
              :name "S" :description "D" :prompt "P" :verifier :exit-zero)))
      ;; Run two evaluations
      (let ((r1 (autopoiesis.eval:create-eval-run
                 :name "Run 1" :scenarios (list s) :harnesses '("h1") :trials 1)))
        (autopoiesis.eval:execute-eval-run r1))
      (let ((r2 (autopoiesis.eval:create-eval-run
                 :name "Run 2" :scenarios (list s) :harnesses '("h1") :trials 1)))
        (autopoiesis.eval:execute-eval-run r2))
      (let ((history (autopoiesis.eval:harness-performance-history "h1")))
        (is (= 2 (length history)))
        (dolist (entry history)
          (is (= 1.0 (getf entry :pass-rate))))))))
