;;;; eval-sandbox-tests.lisp - Tests for sandbox-eval integration
;;;;
;;;; Tests the sandbox harness, filesystem-aware verifiers,
;;;; sandbox metrics, and judge diff-context integration.
;;;;
;;;; Requires both autopoiesis/eval and autopoiesis/sandbox-backends loaded.

(defpackage #:autopoiesis.eval-sandbox.test
  (:use #:cl #:fiveam)
  (:export #:run-eval-sandbox-tests))

(in-package #:autopoiesis.eval-sandbox.test)

(def-suite eval-sandbox-tests
  :description "Sandbox-eval integration tests")

(in-suite eval-sandbox-tests)

(defun run-eval-sandbox-tests ()
  "Run all sandbox-eval integration tests."
  (run! 'eval-sandbox-tests))

;;; ===================================================================
;;; Sandbox Harness Basic Tests
;;; ===================================================================

(test sandbox-harness-creation
  "Sandbox harness can be created and configured."
  (let ((h (autopoiesis.eval:make-sandbox-harness "test-sandbox"
             :backend-type :local
             :base-dir "/tmp/ap-eval-test/"
             :command-template "echo {{prompt}}"
             :capture-diff t)))
    (is (typep h 'autopoiesis.eval:sandbox-harness))
    (is (string= "test-sandbox" (autopoiesis.eval:harness-name h)))
    (is (eq :local (autopoiesis.eval::sbh-backend-type h)))
    (is (autopoiesis.eval::sbh-capture-diff h))))

(test sandbox-harness-serialization
  "Sandbox harness serializes to config plist."
  (let* ((h (autopoiesis.eval:make-sandbox-harness "ser-test"))
         (config (autopoiesis.eval:harness-to-config-plist h)))
    (is (string= "sandbox" (getf config :type)))
    (is (string= "ser-test" (getf config :name)))
    (is (listp (getf config :config)))))

;;; ===================================================================
;;; Sandbox Harness Execution Tests
;;; ===================================================================

(test sandbox-harness-basic-execution
  "Sandbox harness runs a simple echo command and returns correct result shape."
  (autopoiesis.substrate:with-store ()
    (let* ((h (autopoiesis.eval:make-sandbox-harness "exec-test"
               :base-dir "/tmp/ap-eval-test-exec/"
               :command-template "echo {{prompt}}"))
           (scenario (list :eval-scenario/prompt "hello sandbox"
                           :eval-scenario/verifier :non-empty))
           (result (autopoiesis.eval:harness-run-scenario h scenario)))
      ;; Check result shape
      (is (stringp (getf result :output)))
      (is (search "hello sandbox" (getf result :output)))
      (is (numberp (getf result :duration)))
      (is (eql 0 (getf result :exit-code)))
      (is (eq :pass (getf result :passed)))
      ;; Check metadata
      (let ((meta (getf result :metadata)))
        (is (listp meta))
        (is (stringp (getf meta :sandbox-id)))))))

(test sandbox-harness-diff-capture
  "Sandbox harness captures before/after filesystem diff."
  (autopoiesis.substrate:with-store ()
    (let* ((h (autopoiesis.eval:make-sandbox-harness "diff-test"
               :base-dir "/tmp/ap-eval-test-diff/"
               :capture-diff t
               :command-template "mkdir -p src && echo 'print(1)' > src/main.py"))
           (scenario (list :eval-scenario/prompt "unused"))
           (result (autopoiesis.eval:harness-run-scenario h scenario)))
      (is (eql 0 (getf result :exit-code)))
      (let ((meta (getf result :metadata)))
        ;; Should have captured file additions
        (is (plusp (getf meta :file-count-after)))
        (is (plusp (getf meta :file-count-delta)))
        (is (plusp (getf meta :files-added)))
        ;; Tree hashes should be different
        (is (stringp (getf meta :tree-hash-after)))
        ;; Diff summary should be non-nil
        (is (stringp (getf meta :diff-summary)))
        ;; After-tree should be present
        (is (listp (getf meta :after-tree)))))))

(test sandbox-harness-no-diff
  "Sandbox harness works without diff capture."
  (autopoiesis.substrate:with-store ()
    (let* ((h (autopoiesis.eval:make-sandbox-harness "nodiff-test"
               :base-dir "/tmp/ap-eval-test-nodiff/"
               :capture-diff nil
               :command-template "echo {{prompt}}"))
           (scenario (list :eval-scenario/prompt "hi"))
           (result (autopoiesis.eval:harness-run-scenario h scenario)))
      (is (eql 0 (getf result :exit-code)))
      (let ((meta (getf result :metadata)))
        ;; No diff data when capture-diff is nil
        (is (null (getf meta :diff-summary)))
        (is (null (getf meta :after-tree)))))))

(test sandbox-harness-baseline-setup
  "Sandbox harness writes baseline files before execution."
  (autopoiesis.substrate:with-store ()
    (let* ((h (autopoiesis.eval:make-sandbox-harness "baseline-test"
               :base-dir "/tmp/ap-eval-test-baseline/"
               :baseline-setup (list (cons "config.txt" "key=value"))
               :capture-diff t
               :command-template "cat config.txt && echo ' modified' >> config.txt"))
           (scenario (list :eval-scenario/prompt "unused"
                           :eval-scenario/verifier :contains
                           :eval-scenario/expected "key=value"))
           (result (autopoiesis.eval:harness-run-scenario h scenario)))
      (is (eq :pass (getf result :passed)))
      (is (search "key=value" (getf result :output))))))

(test sandbox-harness-error-handling
  "Sandbox harness handles execution errors gracefully."
  (autopoiesis.substrate:with-store ()
    (let* ((h (autopoiesis.eval:make-sandbox-harness "error-test"
               :base-dir "/tmp/ap-eval-test-error/"
               :command-template "exit 42"))
           (scenario (list :eval-scenario/prompt "unused"
                           :eval-scenario/verifier :exit-zero))
           (result (autopoiesis.eval:harness-run-scenario h scenario)))
      (is (eql 42 (getf result :exit-code)))
      (is (eq :fail (getf result :passed))))))

;;; ===================================================================
;;; Filesystem Verifier Tests
;;; ===================================================================

(test verifier-file-exists
  "The :file-exists verifier checks after-tree."
  (let* ((tree (list (list :file "src/main.py" :hash "abc" :mode 33188 :size 10 :mtime 0)))
         (result (list :output "" :metadata (list :after-tree tree))))
    ;; File that exists
    (is (eq :pass (autopoiesis.eval:run-verifier :file-exists ""
                                                  :expected "src/main.py"
                                                  :result result)))
    ;; File that doesn't exist
    (is (eq :fail (autopoiesis.eval:run-verifier :file-exists ""
                                                  :expected "missing.py"
                                                  :result result)))))

(test verifier-file-count-delta
  "The :file-count-delta verifier checks metadata."
  (let ((result (list :output "" :metadata (list :file-count-delta 3))))
    (is (eq :pass (autopoiesis.eval:run-verifier :file-count-delta ""
                                                  :expected 3
                                                  :result result)))
    (is (eq :fail (autopoiesis.eval:run-verifier :file-count-delta ""
                                                  :expected 5
                                                  :result result)))))

(test verifier-tree-matches
  "The :tree-matches verifier checks multiple paths."
  (let* ((tree (list (list :file "a.py" :hash "h1" :mode 33188 :size 10 :mtime 0)
                     (list :file "b.py" :hash "h2" :mode 33188 :size 20 :mtime 0)))
         (result (list :output "" :metadata (list :after-tree tree))))
    ;; All paths exist
    (is (eq :pass (autopoiesis.eval:run-verifier :tree-matches ""
                                                  :expected '("a.py" "b.py")
                                                  :result result)))
    ;; One path missing
    (is (eq :fail (autopoiesis.eval:run-verifier :tree-matches ""
                                                  :expected '("a.py" "c.py")
                                                  :result result)))))

;;; ===================================================================
;;; Sandbox Metrics Tests
;;; ===================================================================

(test sandbox-metrics-aggregation
  "compute-sandbox-metrics aggregates trial metadata correctly."
  (let ((trials (list (list :eval-trial/metadata
                            (list :file-count-delta 3 :files-added 3
                                  :files-removed 0 :files-modified 0
                                  :bytes-written-total 1024
                                  :tree-hash-after "hash-a"))
                      (list :eval-trial/metadata
                            (list :file-count-delta 2 :files-added 2
                                  :files-removed 0 :files-modified 1
                                  :bytes-written-total 2048
                                  :tree-hash-after "hash-b"))
                      ;; Trial without sandbox metadata
                      (list :eval-trial/output "no sandbox"))))
    (let ((m (autopoiesis.eval:compute-sandbox-metrics trials)))
      (is (= 2 (getf m :trials-with-sandbox-data)))
      (is (= 5 (getf m :total-files-added)))
      (is (= 1 (getf m :total-files-modified)))
      (is (= 3072 (getf m :total-bytes-written)))
      (is (= 2 (getf m :unique-tree-hashes))))))

;;; ===================================================================
;;; Judge Diff-Context Tests
;;; ===================================================================

(test judge-prompt-includes-diff
  "build-judge-prompt includes diff context when provided."
  (let ((prompt (autopoiesis.eval::build-judge-prompt
                 "Test task" "Test rubric" "Test output" nil
                 "2 changes: +1 added, -1 removed")))
    (is (search "Filesystem Changes" prompt))
    (is (search "2 changes" prompt))))

(test judge-prompt-no-diff
  "build-judge-prompt omits diff section when nil."
  (let ((prompt (autopoiesis.eval::build-judge-prompt
                 "Test task" "Test rubric" "Test output" nil nil)))
    (is (not (search "Filesystem Changes" prompt)))))

;;; ===================================================================
;;; Fork Support Tests
;;; ===================================================================

(test sandbox-fork-prepare-and-run
  "Fork-based trial execution works."
  (autopoiesis.substrate:with-store ()
    (let* ((h (autopoiesis.eval:make-sandbox-harness "fork-test"
               :base-dir "/tmp/ap-eval-test-fork/"
               :baseline-setup (list (cons "base.txt" "baseline content"))
               :capture-diff t
               :command-template "echo 'modified' >> base.txt && echo done"))
           (scenario (list :eval-scenario/prompt "unused"
                           :eval-scenario/verifier :non-empty))
           (baseline-id (autopoiesis.eval:sandbox-prepare-baseline h scenario)))
      (unwind-protect
           (let ((result (autopoiesis.eval:sandbox-run-in-fork
                          h baseline-id scenario)))
             (is (eql 0 (getf result :exit-code)))
             (is (search "done" (getf result :output)))
             (let ((meta (getf result :metadata)))
               (is (string= baseline-id (getf meta :forked-from)))))
        (autopoiesis.eval:sandbox-destroy-baseline h baseline-id)))))
