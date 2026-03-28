;;;; shen-tests.lisp - Tests for Shen Prolog integration
;;;;
;;;; Tests the bridge, rule system, verifiers, and reasoning mixin.
;;;; Tests that don't require Shen loaded are always run.
;;;; Tests requiring Shen are skipped gracefully when not available.

(defpackage #:autopoiesis.shen.test
  (:use #:cl #:fiveam)
  (:export #:run-shen-tests))

(in-package #:autopoiesis.shen.test)

(def-suite shen-tests
  :description "Shen Prolog integration tests")

(in-suite shen-tests)

(defun run-shen-tests ()
  "Run all Shen integration tests."
  (run! 'shen-tests))

;;; ===================================================================
;;; Bridge Tests (work without Shen loaded)
;;; ===================================================================

(test shen-availability-check
  "shen-available-p returns NIL when Shen is not loaded."
  ;; This test works regardless of whether Shen is installed
  (let ((result (autopoiesis.shen:shen-available-p)))
    ;; Just check it returns a boolean-ish value without erroring
    (is (or (null result) (eq result t)))))

(test shen-eval-without-load
  "shen-eval signals an error when Shen is not loaded."
  (unless (autopoiesis.shen:shen-available-p)
    (signals error (autopoiesis.shen:shen-eval '(+ 1 2)))))

(test shen-query-without-load
  "shen-query signals an error when Shen is not loaded."
  (unless (autopoiesis.shen:shen-available-p)
    (signals error (autopoiesis.shen:shen-query '((mem 1 [1 2 3]))))))

;;; ===================================================================
;;; Rule Store Tests (work without Shen loaded)
;;; ===================================================================

(test rule-define-and-list
  "Rules can be defined and listed without Shen loaded."
  (let ((autopoiesis.shen:*rule-store* (make-hash-table :test 'eq)))
    (autopoiesis.shen:define-rule :test-rule
      '((test-rule X) <-- (member X [1 2 3])))
    (is (member :test-rule (autopoiesis.shen:list-rules)))
    (autopoiesis.shen:remove-rule :test-rule)
    (is (not (member :test-rule (autopoiesis.shen:list-rules))))))

(test rule-clear
  "clear-rules empties the store."
  (let ((autopoiesis.shen:*rule-store* (make-hash-table :test 'eq)))
    (autopoiesis.shen:define-rule :a '((a X) <--))
    (autopoiesis.shen:define-rule :b '((b X) <--))
    (is (= 2 (length (autopoiesis.shen:list-rules))))
    (autopoiesis.shen:clear-rules)
    (is (= 0 (length (autopoiesis.shen:list-rules))))))

(test rule-idempotent-redefine
  "Redefining a rule replaces the previous definition."
  (let ((autopoiesis.shen:*rule-store* (make-hash-table :test 'eq)))
    (autopoiesis.shen:define-rule :x '((x 1) <--))
    (autopoiesis.shen:define-rule :x '((x 2) <--))
    (is (= 1 (length (autopoiesis.shen:list-rules))))
    ;; Check the stored clauses are the new ones
    (let ((clauses (gethash :x autopoiesis.shen:*rule-store*)))
      (is (equal '((x 2) <--) clauses)))))

;;; ===================================================================
;;; Serialization Tests (work without Shen loaded)
;;; ===================================================================

(test rules-serialization-roundtrip
  "Rules survive sexpr serialization roundtrip."
  (let ((autopoiesis.shen:*rule-store* (make-hash-table :test 'eq)))
    (autopoiesis.shen:define-rule :mem
      '((mem X [X | _] <--)
        (mem X [_ | Y] <-- (mem X Y))))
    (autopoiesis.shen:define-rule :valid
      '((valid Tree) <-- (has-file Tree "main.py")))
    (let ((serialized (autopoiesis.shen:rules-to-sexpr)))
      (is (= 2 (length serialized)))
      ;; Clear and reload
      (autopoiesis.shen:clear-rules)
      (is (= 0 (length (autopoiesis.shen:list-rules))))
      (autopoiesis.shen:sexpr-to-rules serialized)
      (is (= 2 (length (autopoiesis.shen:list-rules))))
      (is (member :mem (autopoiesis.shen:list-rules)))
      (is (member :valid (autopoiesis.shen:list-rules))))))

;;; ===================================================================
;;; Verifier Registration Tests (work without Shen loaded)
;;; ===================================================================

(test verifier-registration
  "register-shen-verifiers succeeds when eval package is loaded."
  (let ((result (autopoiesis.shen:register-shen-verifiers)))
    ;; Returns T if eval package is available, NIL otherwise
    (is (or (null result) (eq result t)))))

(test prolog-query-verifier-without-shen
  "Prolog verifier returns :error when Shen is not loaded."
  (unless (autopoiesis.shen:shen-available-p)
    ;; Register verifiers
    (autopoiesis.shen:register-shen-verifiers)
    ;; Try to use the verifier — should return :error gracefully
    (let* ((pkg (find-package :autopoiesis.eval))
           (run-fn (when pkg (find-symbol "RUN-VERIFIER" pkg))))
      (when (and run-fn (fboundp run-fn))
        (let ((result (funcall run-fn :prolog-query "test output"
                               :expected :some-rule
                               :result (list :metadata nil))))
          (is (eq :error result)))))))

(test cl-fallback-with-recognizable-rule
  "CL fallback can verify rules with has-file patterns."
  (unless (autopoiesis.shen:shen-available-p)
    (let ((autopoiesis.shen:*rule-store* (make-hash-table :test 'eq)))
      (autopoiesis.shen:define-rule :project-valid
        '((project-valid Tree)
          <-- (has-file Tree "src/main.py")
              (has-file Tree "README.md")))
      ;; Register verifiers
      (autopoiesis.shen:register-shen-verifiers)
      ;; Test with a tree that has the required files
      (let ((result (autopoiesis.shen::cl-fallback-verify
                     :project-valid "output"
                     (list :metadata
                           (list :after-tree
                                 '((:file "src/main.py" :hash "abc")
                                   (:file "README.md" :hash "def")
                                   (:file "test.py" :hash "ghi")))))))
        (is (eq :pass result)))
      ;; Test with a tree missing a file
      (let ((result (autopoiesis.shen::cl-fallback-verify
                     :project-valid "output"
                     (list :metadata
                           (list :after-tree
                                 '((:file "src/main.py" :hash "abc")))))))
        (is (eq :fail result)))
      ;; Test with unknown rule
      (let ((result (autopoiesis.shen::cl-fallback-verify
                     :nonexistent "output"
                     (list :metadata nil))))
        (is (eq :error result))))))

;;; ===================================================================
;;; Reasoning Mixin Tests (work without Shen loaded)
;;; ===================================================================

(test reasoning-mixin-creation
  "shen-reasoning-mixin can be used as a CLOS mixin."
  (let ((mixin (make-instance 'autopoiesis.shen:shen-reasoning-mixin)))
    (is (null (autopoiesis.shen:agent-knowledge-base mixin)))))

(test knowledge-base-management
  "Knowledge base add/remove/clear operations."
  (let ((mixin (make-instance 'autopoiesis.shen:shen-reasoning-mixin)))
    ;; Add
    (autopoiesis.shen:add-knowledge mixin :rule-a '((rule-a X) <--))
    (is (= 1 (length (autopoiesis.shen:agent-knowledge-base mixin))))
    ;; Add another
    (autopoiesis.shen:add-knowledge mixin :rule-b '((rule-b X) <--))
    (is (= 2 (length (autopoiesis.shen:agent-knowledge-base mixin))))
    ;; Redefine
    (autopoiesis.shen:add-knowledge mixin :rule-a '((rule-a Y) <--))
    (is (= 2 (length (autopoiesis.shen:agent-knowledge-base mixin))))
    ;; Remove
    (autopoiesis.shen:remove-knowledge mixin :rule-a)
    (is (= 1 (length (autopoiesis.shen:agent-knowledge-base mixin))))
    ;; Clear
    (autopoiesis.shen:clear-knowledge mixin)
    (is (= 0 (length (autopoiesis.shen:agent-knowledge-base mixin))))))

;;; ===================================================================
;;; Shen-Dependent Tests (skipped when Shen not available)
;;; ===================================================================

(test shen-eval-basic
  "Basic Shen evaluation (requires Shen loaded)."
  (when (autopoiesis.shen:shen-available-p)
    (let ((result (autopoiesis.shen:shen-eval '(+ 1 2))))
      (is (= 3 result)))))

(test shen-define-and-query-rule
  "Define a Prolog rule and query it (requires Shen loaded)."
  (when (autopoiesis.shen:shen-available-p)
    (let ((autopoiesis.shen:*rule-store* (make-hash-table :test 'eq)))
      (autopoiesis.shen:define-rule :test-mem
        '((test-mem X [X | _] <--)
          (test-mem X [_ | Y] <-- (test-mem X Y))))
      (is (autopoiesis.shen:query-rules :test-mem :context '(1 (1 2 3))))
      (is (not (autopoiesis.shen:query-rules :test-mem :context '(4 (1 2 3))))))))
