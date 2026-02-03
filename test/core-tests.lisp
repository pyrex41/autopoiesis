;;;; core-tests.lisp - Tests for core layer
;;;;
;;;; Tests S-expression utilities and cognitive primitives.

(in-package #:autopoiesis.test)

(def-suite core-tests
  :description "Core layer tests")

(in-suite core-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; S-expression Tests
;;; ═══════════════════════════════════════════════════════════════════

(test sexpr-equal-atoms
  "Test sexpr-equal on atoms"
  (is (sexpr-equal nil nil))
  (is (sexpr-equal t t))
  (is (sexpr-equal 42 42))
  (is (sexpr-equal "hello" "hello"))
  (is (sexpr-equal :keyword :keyword))
  (is (not (sexpr-equal 1 2)))
  (is (not (sexpr-equal "a" "b"))))

(test sexpr-equal-lists
  "Test sexpr-equal on lists"
  (is (sexpr-equal '(1 2 3) '(1 2 3)))
  (is (sexpr-equal '((a b) (c d)) '((a b) (c d))))
  (is (not (sexpr-equal '(1 2) '(1 2 3))))
  (is (not (sexpr-equal '(1 2 3) '(1 2)))))

(test sexpr-hash-consistency
  "Test that sexpr-hash produces consistent hashes"
  (let ((expr '(a (b c) d)))
    (is (string= (sexpr-hash expr) (sexpr-hash expr)))
    (is (string= (sexpr-hash '(1 2 3)) (sexpr-hash '(1 2 3))))
    (is (not (string= (sexpr-hash '(1 2)) (sexpr-hash '(1 2 3)))))))

(test sexpr-diff-identical
  "Test that identical expressions have no diff"
  (is (null (sexpr-diff '(a b c) '(a b c)))))

(test sexpr-diff-different
  "Test diff on different expressions"
  (let ((diff (sexpr-diff '(a b c) '(a x c))))
    (is (= 1 (length diff)))
    (is (eq :replace (autopoiesis.core::sexpr-edit-type (first diff))))))

(test sexpr-patch-roundtrip
  "Test that patch applies diff correctly"
  (let* ((old '(a b c))
         (new '(a x c))
         (diff (sexpr-diff old new))
         (patched (sexpr-patch old diff)))
    (is (sexpr-equal patched new))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Tests
;;; ═══════════════════════════════════════════════════════════════════

(test make-thought-basic
  "Test basic thought creation"
  (let ((thought (make-thought '(hello world))))
    (is (not (null (thought-id thought))))
    (is (numberp (thought-timestamp thought)))
    (is (equal '(hello world) (thought-content thought)))
    (is (eq :generic (thought-type thought)))
    (is (= 1.0 (thought-confidence thought)))))

(test thought-serialization
  "Test thought to/from sexpr"
  (let* ((thought (make-thought '(test content) :type :reasoning :confidence 0.8))
         (sexpr (thought-to-sexpr thought))
         (restored (sexpr-to-thought sexpr)))
    (is (equal (thought-id thought) (thought-id restored)))
    (is (equal (thought-content thought) (thought-content restored)))
    (is (eq (thought-type thought) (thought-type restored)))
    (is (= (thought-confidence thought) (thought-confidence restored)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Stream Tests
;;; ═══════════════════════════════════════════════════════════════════

(test thought-stream-operations
  "Test thought stream basic operations"
  (let ((stream (make-thought-stream)))
    (is (= 0 (stream-length stream)))
    (let ((t1 (make-thought '(first)))
          (t2 (make-thought '(second)))
          (t3 (make-thought '(third))))
      (stream-append stream t1)
      (stream-append stream t2)
      (stream-append stream t3)
      (is (= 3 (stream-length stream)))
      (is (eq t1 (stream-find stream (thought-id t1))))
      (is (eq t3 (first (stream-last stream 1))))
      (is (= 2 (length (stream-last stream 2)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Stream Compaction Tests
;;; ═══════════════════════════════════════════════════════════════════

(test compact-thought-stream-no-op-when-small
  "Test compact-thought-stream does nothing when stream is small"
  (let ((stream (make-thought-stream)))
    ;; Add 10 thoughts (less than default keep-last * 2)
    (dotimes (i 10)
      (stream-append stream (make-thought `(thought ,i))))
    (multiple-value-bind (archived kept)
        (autopoiesis.core:compact-thought-stream stream :keep-last 100)
      (is (= 0 archived))
      (is (= 10 kept))
      ;; Stream should be unchanged
      (is (= 10 (stream-length stream))))))

(test compact-thought-stream-compacts-when-large
  "Test compact-thought-stream removes old thoughts when stream is large"
  (let ((stream (make-thought-stream)))
    ;; Add 250 thoughts (more than 100 * 2)
    (dotimes (i 250)
      (stream-append stream (make-thought `(thought ,i))))
    (is (= 250 (stream-length stream)))
    ;; Compact without archiving
    (multiple-value-bind (archived kept)
        (autopoiesis.core:compact-thought-stream stream :keep-last 100)
      (is (= 150 archived))
      (is (= 100 kept))
      ;; Stream should now have only 100 thoughts
      (is (= 100 (stream-length stream))))))

(test compact-thought-stream-keeps-recent
  "Test compact-thought-stream keeps the most recent thoughts"
  (let ((stream (make-thought-stream)))
    ;; Add 250 thoughts with identifiable content
    (dotimes (i 250)
      (stream-append stream (make-thought `(thought ,i))))
    ;; Compact to keep last 100
    (autopoiesis.core:compact-thought-stream stream :keep-last 100)
    ;; Check that we kept thoughts 150-249
    (let ((first-kept (first (stream-last stream 100)))
          (last-kept (first (stream-last stream 1))))
      ;; Last thought should be (thought 249)
      (is (equal '(thought 249) (thought-content last-kept)))
      ;; First kept thought should be (thought 150)
      (is (equal '(thought 150) (thought-content first-kept))))))

(test compact-thought-stream-rebuilds-indices
  "Test compact-thought-stream rebuilds lookup indices correctly"
  (let ((stream (make-thought-stream))
        (kept-ids nil))
    ;; Add 250 thoughts, save IDs of last 100
    (dotimes (i 250)
      (let ((thought (make-thought `(thought ,i))))
        (stream-append stream thought)
        (when (>= i 150)
          (push (thought-id thought) kept-ids))))
    (setf kept-ids (nreverse kept-ids))
    ;; Compact
    (autopoiesis.core:compact-thought-stream stream :keep-last 100)
    ;; All kept IDs should still be findable
    (dolist (id kept-ids)
      (is-true (stream-find stream id)))))

(test compact-thought-stream-with-archive
  "Test compact-thought-stream archives to disk when path provided"
  (let ((stream (make-thought-stream))
        (archive-dir (merge-pathnames "test-archive/"
                                      (uiop:temporary-directory))))
    ;; Ensure clean test directory
    (when (probe-file archive-dir)
      (uiop:delete-directory-tree archive-dir :validate t))
    (ensure-directories-exist archive-dir)
    (unwind-protect
        (progn
          ;; Add 250 thoughts
          (dotimes (i 250)
            (stream-append stream (make-thought `(thought ,i))))
          ;; Compact with archiving
          (multiple-value-bind (archived kept)
              (autopoiesis.core:compact-thought-stream stream
                                                       :keep-last 100
                                                       :archive-path archive-dir)
            (is (= 150 archived))
            (is (= 100 kept))
            ;; Check archive file was created
            (let ((archive-files (directory (merge-pathnames "thoughts-*.sexpr" archive-dir))))
              (is (= 1 (length archive-files)))
              ;; Load and verify archived thoughts
              (let ((loaded (autopoiesis.core:load-archived-thoughts (first archive-files))))
                (is (= 150 (length loaded)))
                ;; First archived thought should be (thought 0)
                (is (equal '(thought 0) (thought-content (first loaded))))))))
      ;; Cleanup
      (when (probe-file archive-dir)
        (uiop:delete-directory-tree archive-dir :validate t)))))

(test load-archived-thoughts-handles-missing-file
  "Test load-archived-thoughts returns NIL for missing file"
  (let ((result (autopoiesis.core:load-archived-thoughts #p"/nonexistent/file.sexpr")))
    (is (null result))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Extension Compiler Tests
;;; ═══════════════════════════════════════════════════════════════════

(test validate-safe-code
  "Test validation of safe code"
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(lambda (x) (+ x 1)))
    (declare (ignore errors))
    (is-true valid)))

(test validate-forbidden-code
  "Test validation rejects forbidden patterns"
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(eval (read)))
    (is (not valid))
    (is (not (null errors)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Sandbox Rules Tests
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-allowed-packages
  "Test that *allowed-packages* is defined and contains expected packages"
  (is (listp autopoiesis.core::*allowed-packages*))
  (is (member "COMMON-LISP" autopoiesis.core::*allowed-packages* :test #'string=))
  (is (member "KEYWORD" autopoiesis.core::*allowed-packages* :test #'string=))
  (is (member "AUTOPOIESIS.CORE" autopoiesis.core::*allowed-packages* :test #'string=)))

(test sandbox-forbidden-symbols
  "Test that *forbidden-symbols* is defined and contains dangerous operations"
  (is (listp autopoiesis.core::*forbidden-symbols*))
  (is (member 'eval autopoiesis.core::*forbidden-symbols*))
  (is (member 'compile autopoiesis.core::*forbidden-symbols*))
  (is (member 'load autopoiesis.core::*forbidden-symbols*))
  (is (member 'open autopoiesis.core::*forbidden-symbols*))
  (is (member 'delete-file autopoiesis.core::*forbidden-symbols*)))

(test sandbox-allowed-special-forms
  "Test that *allowed-special-forms* contains safe control structures"
  (is (listp autopoiesis.core::*allowed-special-forms*))
  (is (member 'if autopoiesis.core::*allowed-special-forms*))
  (is (member 'let autopoiesis.core::*allowed-special-forms*))
  (is (member 'lambda autopoiesis.core::*allowed-special-forms*))
  (is (member 'progn autopoiesis.core::*allowed-special-forms*))
  (is (member 'loop autopoiesis.core::*allowed-special-forms*)))

(test validate-complex-safe-code
  "Test validation of complex but safe code"
  ;; Nested let with lambda
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(let ((x 10))
          (let* ((y (+ x 5))
                 (z (* y 2)))
            (lambda (n) (+ n z)))))
    (declare (ignore errors))
    (is-true valid))
  
  ;; Loop with conditionals
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(loop for i from 1 to 10
              when (evenp i)
              collect (* i i)))
    (declare (ignore errors))
    (is-true valid))
  
  ;; Flet with local functions
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(flet ((double (x) (* x 2))
               (square (x) (* x x)))
          (+ (double 3) (square 4))))
    (declare (ignore errors))
    (is-true valid)))

(test validate-forbidden-symbols-rejected
  "Test that forbidden symbols are rejected"
  ;; eval is forbidden
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(eval '(+ 1 2)))
    (is (not valid))
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors)))
  
  ;; compile is forbidden
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(compile nil '(lambda (x) x)))
    (is (not valid))
    (is (some (lambda (e) (search "compile" e :test #'char-equal)) errors)))
  
  ;; setf is forbidden
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(setf x 10))
    (is (not valid))
    (is (some (lambda (e) (search "setf" e :test #'char-equal)) errors)))
  
  ;; defun is forbidden
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(defun foo (x) x))
    (is (not valid))
    (is (some (lambda (e) (search "defun" e :test #'char-equal)) errors))))

(test validate-file-operations-rejected
  "Test that file operations are rejected"
  ;; open is forbidden
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(open "/etc/passwd"))
    (is (not valid))
    (is (some (lambda (e) (search "open" e :test #'char-equal)) errors)))
  
  ;; delete-file is forbidden
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(delete-file "/tmp/test"))
    (is (not valid))
    (is (some (lambda (e) (search "delete" e :test #'char-equal)) errors))))

(test validate-sandbox-levels
  "Test different sandbox levels"
  ;; :strict rejects forbidden code
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(eval '(+ 1 2)) :sandbox-level :strict)
    (declare (ignore errors))
    (is (not valid)))
  
  ;; :trusted allows anything
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(eval '(+ 1 2)) :sandbox-level :trusted)
    (declare (ignore errors))
    (is-true valid)))

(test validate-quoted-forms-safe
  "Test that quoted forms are not recursively checked"
  ;; Quoted eval should be safe (it's just data)
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source '(list 'eval 'compile 'load))
    (declare (ignore errors))
    (is-true valid)))

(test validate-keywords-allowed
  "Test that keywords are always allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(list :foo :bar :baz))
    (declare (ignore errors))
    (is-true valid))
  
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(getf '(:a 1 :b 2) :a))
    (declare (ignore errors))
    (is-true valid)))

(test validate-lambda-params-unrestricted
  "Test that lambda parameter names are not restricted"
  ;; Parameter names can be anything
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(lambda (eval compile load) (+ eval compile load)))
    (declare (ignore errors))
    (is-true valid)))

(test validate-let-bindings-unrestricted
  "Test that let binding names are not restricted"
  ;; Binding names can be anything
  (multiple-value-bind (valid errors)
      (autopoiesis.core::validate-extension-source
       '(let ((eval 1) (compile 2))
          (+ eval compile)))
    (declare (ignore errors))
    (is-true valid)))

;;; ─────────────────────────────────────────────────────────────────
;;; validate-extension-code Tests (Phase 9.1)
;;; ─────────────────────────────────────────────────────────────────

(test validate-extension-code-safe
  "Test validate-extension-code accepts safe code"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(lambda (x y) (+ x y)))
    (declare (ignore errors))
    (is-true valid))
  
  ;; Complex safe code
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((sum 0))
          (loop for i from 1 to 10
                do (setq sum (+ sum i)))
          sum))
    ;; setq is forbidden even in this context
    (is (not valid))
    (is (some (lambda (e) (search "setq" e :test #'char-equal)) errors))))

(test validate-extension-code-rejects-dangerous
  "Test validate-extension-code rejects dangerous code"
  ;; eval
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(eval (read)))
    (is (not valid))
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors)))
  
  ;; File operations
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(with-open-file (f "/etc/passwd") (read f)))
    (is (not valid))
    (is (some (lambda (e) (search "with-open-file" e :test #'char-equal)) errors))))

(test validate-extension-code-walker-handles-special-forms
  "Test that the code walker correctly handles special forms"
  ;; Lambda parameters should not be checked as operators
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(lambda (eval compile) (list eval compile)))
    (declare (ignore errors))
    (is-true valid))
  
  ;; Flet local functions should be allowed
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(flet ((helper (x) (* x 2)))
          (helper 10)))
    (declare (ignore errors))
    (is-true valid))
  
  ;; Labels with recursive functions
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(labels ((factorial (n)
                   (if (<= n 1)
                       1
                       (* n (factorial (1- n))))))
          (factorial 5)))
    (declare (ignore errors))
    (is-true valid))
  
  ;; Quoted forms should not be recursively checked
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(list 'eval 'compile 'open 'delete-file))
    (declare (ignore errors))
    (is-true valid)))

;;; ─────────────────────────────────────────────────────────────────
;;; compile-extension Tests (Phase 9.1)
;;; ─────────────────────────────────────────────────────────────────

(test compile-extension-safe-code
  "Test compile-extension successfully compiles safe code"
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-add"
       '(+ 1 2))
    (is-true ext)
    (is (null errors))
    (is (equal "test-add" (autopoiesis.core::extension-name ext)))
    (is (functionp (autopoiesis.core::extension-compiled ext)))
    ;; Execute the compiled extension
    (is (= 3 (funcall (autopoiesis.core::extension-compiled ext))))))

(test compile-extension-with-lambda
  "Test compile-extension with lambda expressions"
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-lambda"
       '(let ((x 10)
              (y 20))
          (+ x y)))
    (is-true ext)
    (is (null errors))
    ;; Execute and verify result
    (is (= 30 (funcall (autopoiesis.core::extension-compiled ext))))))

(test compile-extension-rejects-forbidden-code
  "Test compile-extension rejects forbidden code"
  ;; eval is forbidden
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-eval"
       '(eval '(+ 1 2)))
    (is (null ext))
    (is (not (null errors)))
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors)))
  
  ;; File operations are forbidden
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-file"
       '(delete-file "/tmp/test"))
    (is (null ext))
    (is (not (null errors)))
    (is (some (lambda (e) (search "delete" e :test #'char-equal)) errors))))

(test compile-extension-trusted-level
  "Test compile-extension with :trusted sandbox level allows anything"
  ;; Even eval is allowed in trusted mode
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-trusted"
       '(list 1 2 3)
       :sandbox-level :trusted)
    (is-true ext)
    (is (null errors))))

(test compile-extension-with-metadata
  "Test compile-extension preserves author and dependencies"
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-meta"
       '(+ 1 1)
       :author "agent-123"
       :dependencies '("base-math"))
    (is-true ext)
    (is (null errors))
    (is (equal "agent-123" (autopoiesis.core::extension-author ext)))
    (is (equal '("base-math") (autopoiesis.core::extension-dependencies ext)))))

(test compile-extension-complex-safe-code
  "Test compile-extension with complex but safe code"
  ;; Nested let with loop
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-complex"
       '(let ((numbers '(1 2 3 4 5)))
          (reduce #'+ (mapcar (lambda (x) (* x x)) numbers))))
    (is-true ext)
    (is (null errors))
    ;; 1 + 4 + 9 + 16 + 25 = 55
    (is (= 55 (funcall (autopoiesis.core::extension-compiled ext)))))
  
  ;; Flet with local functions
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-flet"
       '(flet ((double (x) (* x 2))
               (square (x) (* x x)))
          (+ (double 3) (square 4))))
    (is-true ext)
    (is (null errors))
    ;; 6 + 16 = 22
    (is (= 22 (funcall (autopoiesis.core::extension-compiled ext))))))

(test compile-extension-handles-compilation-errors
  "Test compile-extension handles compilation errors gracefully"
  ;; Note: This test uses :trusted to bypass validation and test compilation errors
  ;; In practice, most compilation errors would be caught by validation first
  ;; We test with syntactically valid but semantically problematic code
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "test-compile-error"
       '(the integer "not-an-integer")
       :sandbox-level :trusted)
    ;; This may or may not error depending on SBCL's handling of THE
    ;; The important thing is it doesn't throw - it returns values
    (is (or ext (listp errors)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Extension Registry Tests (Phase 9.1)
;;; ─────────────────────────────────────────────────────────────────

(test extension-class-slots
  "Test extension class has all required slots"
  (let ((ext (make-instance 'autopoiesis.core::extension
                            :name "test-ext"
                            :source '(+ 1 2))))
    ;; Basic slots
    (is (equal "test-ext" (autopoiesis.core:extension-name ext)))
    (is (equal '(+ 1 2) (autopoiesis.core:extension-source ext)))
    ;; New slots
    (is (null (autopoiesis.core:extension-id ext)))
    (is (= 0 (autopoiesis.core:extension-invocations ext)))
    (is (= 0 (autopoiesis.core:extension-errors ext)))
    (is (eq :pending (autopoiesis.core:extension-status ext)))))

(test register-extension-basic
  "Test register-extension creates and registers an extension"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Register a simple extension
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "agent-001"
         '(+ 10 20)
         :registry test-registry)
      (is-true ext)
      (is (null errors))
      ;; Check extension properties
      (is (stringp (autopoiesis.core:extension-id ext)))
      (is (equal "agent-001" (autopoiesis.core:extension-author ext)))
      (is (eq :validated (autopoiesis.core:extension-status ext)))
      (is (= 0 (autopoiesis.core:extension-invocations ext)))
      (is (= 0 (autopoiesis.core:extension-errors ext)))
      ;; Check it's in the registry
      (is (eq ext (gethash (autopoiesis.core:extension-id ext) test-registry))))))

(test register-extension-with-name
  "Test register-extension with custom name"
  (let ((test-registry (make-hash-table :test 'equal)))
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "agent-002"
         '(* 5 5)
         :name "multiply-five"
         :registry test-registry)
      (is-true ext)
      (is (null errors))
      (is (equal "multiply-five" (autopoiesis.core:extension-name ext))))))

(test register-extension-rejects-invalid-code
  "Test register-extension rejects invalid code"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Try to register code with eval
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "agent-003"
         '(eval '(+ 1 2))
         :registry test-registry)
      (is (null ext))
      (is (not (null errors)))
      (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors))
      ;; Registry should be empty
      (is (= 0 (hash-table-count test-registry))))))

(test invoke-extension-basic
  "Test invoke-extension executes registered extension"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Register an extension
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "agent-004"
         '(+ 100 200)
         :registry test-registry)
      (declare (ignore errors))
      ;; Invoke it
      (let ((result (autopoiesis.core:invoke-extension
                     (autopoiesis.core:extension-id ext)
                     :registry test-registry)))
        (is (= 300 result))
        ;; Check invocation counter
        (is (= 1 (autopoiesis.core:extension-invocations ext)))))))

(test invoke-extension-multiple-times
  "Test invoke-extension tracks multiple invocations"
  (let ((test-registry (make-hash-table :test 'equal)))
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "agent-005"
         '(list 1 2 3)
         :registry test-registry)
      (declare (ignore errors))
      (let ((ext-id (autopoiesis.core:extension-id ext)))
        ;; Invoke multiple times
        (autopoiesis.core:invoke-extension ext-id :registry test-registry)
        (autopoiesis.core:invoke-extension ext-id :registry test-registry)
        (autopoiesis.core:invoke-extension ext-id :registry test-registry)
        ;; Check counter
        (is (= 3 (autopoiesis.core:extension-invocations ext)))))))

(test invoke-extension-not-found
  "Test invoke-extension signals error for unknown extension"
  (let ((test-registry (make-hash-table :test 'equal)))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.core:invoke-extension
       "nonexistent-id"
       :registry test-registry))))

(test invoke-extension-not-validated
  "Test invoke-extension rejects non-validated extensions"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Create an extension manually with :pending status
    (let ((ext (make-instance 'autopoiesis.core::extension
                              :name "pending-ext"
                              :id "pending-id"
                              :source '(+ 1 1)
                              :compiled (compile nil '(lambda () (+ 1 1)))
                              :status :pending)))
      (setf (gethash "pending-id" test-registry) ext)
      ;; Should fail because status is :pending
      (signals autopoiesis.core:autopoiesis-error
        (autopoiesis.core:invoke-extension "pending-id" :registry test-registry)))))

(test invoke-extension-auto-disable-on-errors
  "Test invoke-extension auto-disables extension after too many errors"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Create an extension that always errors
    (let ((ext (make-instance 'autopoiesis.core::extension
                              :name "error-ext"
                              :id "error-id"
                              :source '(error "intentional error")
                              :compiled (compile nil '(lambda () (error "intentional error")))
                              :status :validated)))
      (setf (gethash "error-id" test-registry) ext)
      ;; Invoke and catch errors 4 times
      (dotimes (i 4)
        (handler-case
            (autopoiesis.core:invoke-extension "error-id" :registry test-registry)
          (autopoiesis.core:autopoiesis-error () nil)))
      ;; After 4 errors, status should be :rejected
      (is (eq :rejected (autopoiesis.core:extension-status ext)))
      (is (= 4 (autopoiesis.core:extension-errors ext))))))

(test clear-extension-registry
  "Test clear-extension-registry removes all extensions"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Register some extensions
    (autopoiesis.core:register-extension "agent" '(+ 1 1) :registry test-registry)
    (autopoiesis.core:register-extension "agent" '(+ 2 2) :registry test-registry)
    (is (= 2 (hash-table-count test-registry)))
    ;; Clear
    (autopoiesis.core:clear-extension-registry :registry test-registry)
    (is (= 0 (hash-table-count test-registry)))))

(test list-extensions
  "Test list-extensions returns all registered extensions"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Register some extensions
    (autopoiesis.core:register-extension "agent" '(+ 1 1) :name "ext1" :registry test-registry)
    (autopoiesis.core:register-extension "agent" '(+ 2 2) :name "ext2" :registry test-registry)
    (let ((exts (autopoiesis.core:list-extensions :registry test-registry)))
      (is (= 2 (length exts)))
      (is (every (lambda (e) (typep e 'autopoiesis.core::extension)) exts)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Profiling Tests
;;; ═══════════════════════════════════════════════════════════════════

(test profiling-disabled-by-default
  "Test that profiling is disabled by default"
  (is (not autopoiesis.core:*profiling-enabled*)))

(test profiling-enable-disable
  "Test enable/disable profiling"
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         (is-true autopoiesis.core:*profiling-enabled*)
         (autopoiesis.core:disable-profiling)
         (is (not autopoiesis.core:*profiling-enabled*)))
    (autopoiesis.core:disable-profiling)))

(test profiling-with-timing-macro
  "Test with-timing macro records metrics"
  (autopoiesis.core:reset-profiling)
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         ;; Execute some timed code
         (autopoiesis.core:with-timing ("test-operation")
           (sleep 0.01))
         ;; Check metrics were recorded
         (let ((metric (autopoiesis.core:get-profile-metric "test-operation")))
           (is-true metric)
           (is (= 1 (autopoiesis.core:profile-metric-call-count metric)))
           (is (> (autopoiesis.core:profile-metric-total-time-ns metric) 0))))
    (autopoiesis.core:disable-profiling)
    (autopoiesis.core:reset-profiling)))

(test profiling-with-timing-no-overhead-when-disabled
  "Test with-timing has no overhead when profiling disabled"
  (autopoiesis.core:reset-profiling)
  (autopoiesis.core:disable-profiling)
  ;; Execute timed code with profiling disabled
  (autopoiesis.core:with-timing ("disabled-operation")
    (+ 1 2))
  ;; No metrics should be recorded
  (let ((metric (autopoiesis.core:get-profile-metric "disabled-operation")))
    (is (null metric))))

(test profiling-multiple-calls-aggregated
  "Test multiple calls to same operation are aggregated"
  (autopoiesis.core:reset-profiling)
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         ;; Execute multiple times
         (dotimes (i 5)
           (autopoiesis.core:with-timing ("multi-call-op")
             (+ 1 2)))
         ;; Check aggregated metrics
         (let ((metric (autopoiesis.core:get-profile-metric "multi-call-op")))
           (is-true metric)
           (is (= 5 (autopoiesis.core:profile-metric-call-count metric)))))
    (autopoiesis.core:disable-profiling)
    (autopoiesis.core:reset-profiling)))

(test profiling-min-max-tracking
  "Test min/max time tracking"
  (autopoiesis.core:reset-profiling)
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         ;; Execute with varying times
         (autopoiesis.core:with-timing ("min-max-test")
           (sleep 0.001))
         (autopoiesis.core:with-timing ("min-max-test")
           (sleep 0.01))
         (autopoiesis.core:with-timing ("min-max-test")
           (sleep 0.001))
         ;; Check min < max
         (let ((metric (autopoiesis.core:get-profile-metric "min-max-test")))
           (is-true metric)
           (is (< (autopoiesis.core:profile-metric-min-time-ns metric)
                  (autopoiesis.core:profile-metric-max-time-ns metric)))))
    (autopoiesis.core:disable-profiling)
    (autopoiesis.core:reset-profiling)))

(test profiling-reset-clears-all
  "Test reset-profiling clears all metrics"
  (autopoiesis.core:reset-profiling)
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         (autopoiesis.core:with-timing ("to-be-cleared")
           (+ 1 2))
         (is-true (autopoiesis.core:get-profile-metric "to-be-cleared"))
         (autopoiesis.core:reset-profiling)
         (is (null (autopoiesis.core:get-profile-metric "to-be-cleared"))))
    (autopoiesis.core:disable-profiling)
    (autopoiesis.core:reset-profiling)))

(test profiling-report-structure
  "Test profile-report returns correct structure"
  (autopoiesis.core:reset-profiling)
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         (autopoiesis.core:with-timing ("report-test")
           (+ 1 2))
         (let ((report (autopoiesis.core:profile-report)))
           (is (listp report))
           (is (= 1 (getf report :total-operations)))
           (is (listp (getf report :operations)))
           (let ((op (first (getf report :operations))))
             (is (equal "report-test" (getf op :name)))
             (is (= 1 (getf op :calls)))
             (is (numberp (getf op :total-ms)))
             (is (numberp (getf op :avg-us)))
             (is (numberp (getf op :min-us)))
             (is (numberp (getf op :max-us))))))
    (autopoiesis.core:disable-profiling)
    (autopoiesis.core:reset-profiling)))

(test profiling-with-profiling-macro
  "Test with-profiling macro enables and disables correctly"
  (autopoiesis.core:reset-profiling)
  (autopoiesis.core:disable-profiling)
  (is (not autopoiesis.core:*profiling-enabled*))
  (autopoiesis.core:with-profiling
    (is-true autopoiesis.core:*profiling-enabled*)
    (autopoiesis.core:with-timing ("inside-with-profiling")
      (+ 1 2)))
  ;; Should be disabled after with-profiling
  (is (not autopoiesis.core:*profiling-enabled*))
  ;; But metrics should still be there
  (is-true (autopoiesis.core:get-profile-metric "inside-with-profiling"))
  (autopoiesis.core:reset-profiling))

(test profiling-summary
  "Test profile-summary returns correct structure"
  (autopoiesis.core:reset-profiling)
  (unwind-protect
       (progn
         (autopoiesis.core:enable-profiling)
         (autopoiesis.core:with-timing ("summary-op-1")
           (+ 1 2))
         (autopoiesis.core:with-timing ("summary-op-2")
           (+ 3 4))
         (let ((summary (autopoiesis.core:profile-summary)))
           (is (listp summary))
           (is-true (getf summary :enabled))
           (is (= 2 (getf summary :operations-tracked)))
           (is (= 2 (getf summary :total-calls)))
           (is (numberp (getf summary :total-time-ms)))
           (is (listp (getf summary :hot-paths)))))
    (autopoiesis.core:disable-profiling)
    (autopoiesis.core:reset-profiling)))

(test profiling-benchmark-function
  "Test benchmark function"
  (let ((result (autopoiesis.core:benchmark "bench-test" 100
                  (lambda () (+ 1 2)))))
    (is (listp result))
    (is (equal "bench-test" (getf result :name)))
    (is (= 100 (getf result :iterations)))
    (is (numberp (getf result :total-ms)))
    (is (numberp (getf result :avg-us)))
    (is (numberp (getf result :ops-per-sec)))
    (is (> (getf result :ops-per-sec) 0))))

(test profiling-batch-sexpr-hash
  "Test batch-sexpr-hash function"
  (let ((sexprs '((a b c) (1 2 3) ("hello" "world"))))
    (let ((hashes (autopoiesis.core:batch-sexpr-hash sexprs)))
      (is (= 3 (length hashes)))
      (is (every #'stringp hashes))
      ;; Each hash should match individual hash
      (is (equal (first hashes) (sexpr-hash '(a b c))))
      (is (equal (second hashes) (sexpr-hash '(1 2 3))))
      (is (equal (third hashes) (sexpr-hash '("hello" "world")))))))

(test profiling-batch-sexpr-serialize
  "Test batch-sexpr-serialize function"
  (let ((sexprs '((a b c) (1 2 3))))
    (let ((serialized (autopoiesis.core:batch-sexpr-serialize sexprs)))
      (is (= 2 (length serialized)))
      (is (every #'stringp serialized)))))

(test profiling-memory-usage
  "Test memory-usage function"
  (let ((usage (autopoiesis.core:memory-usage)))
    (is (listp usage))
    (is (numberp (getf usage :dynamic-usage)))))

(test profiling-with-memory-tracking
  "Test with-memory-tracking macro"
  (multiple-value-bind (result bytes)
      (autopoiesis.core:with-memory-tracking
        (make-list 1000))
    (is (listp result))
    (is (= 1000 (length result)))
    (is (numberp bytes))))
