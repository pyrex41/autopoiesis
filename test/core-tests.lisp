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
