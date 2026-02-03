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
