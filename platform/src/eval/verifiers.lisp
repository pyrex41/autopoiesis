;;;; verifiers.lisp - Deterministic verifier functions for eval scenarios
;;;;
;;;; Verifiers check whether agent output meets a scenario's success criteria.
;;;; They return :pass, :fail, or :error.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Verifier Registry
;;; ===================================================================

(defvar *verifier-registry* (make-hash-table :test 'eq)
  "Registry of built-in verifier functions keyed by keyword.")

(defun register-verifier (name fn)
  "Register a built-in verifier function.
   FN should accept (output &key expected exit-code result) and return :pass/:fail/:error."
  (setf (gethash name *verifier-registry*) fn))

;;; ===================================================================
;;; Main Dispatcher
;;; ===================================================================

(defun run-verifier (verifier-designator output &key expected exit-code result)
  "Run a verifier against output. Returns :pass, :fail, or :error.

   VERIFIER-DESIGNATOR can be:
   - A keyword: looks up built-in verifier (e.g., :exit-zero, :contains)
   - A plist with :type key: dispatches to built-in with plist args
     e.g., (:type :contains :value \"expected string\")
   - A function: calls directly with (output :expected expected)
   - A symbol naming a function: resolves and calls"
  (handler-case
      (etypecase verifier-designator
        ;; Keyword: look up built-in
        (keyword
         (let ((fn (gethash verifier-designator *verifier-registry*)))
           (if fn
               (funcall fn output :expected expected :exit-code exit-code :result result)
               :error)))

        ;; Plist with :type — extract type and pass args
        (cons
         (if (getf verifier-designator :type)
             (let* ((vtype (getf verifier-designator :type))
                    (fn (gethash vtype *verifier-registry*))
                    (value (getf verifier-designator :value)))
               (if fn
                   (funcall fn output
                            :expected (or value expected)
                            :exit-code exit-code
                            :result result)
                   :error))
             ;; Might be a lambda form — try funcall
             (let ((fn (coerce verifier-designator 'function)))
               (if (funcall fn output expected)
                   :pass :fail))))

        ;; Function object
        (function
         (if (funcall verifier-designator output expected)
             :pass :fail))

        ;; Symbol naming a function
        (symbol
         (let ((fn (and (fboundp verifier-designator)
                        (symbol-function verifier-designator))))
           (if fn
               (if (funcall fn output expected) :pass :fail)
               :error))))
    (error (e)
      (declare (ignore e))
      :error)))

;;; ===================================================================
;;; Built-in Verifiers
;;; ===================================================================

(register-verifier :exit-zero
  (lambda (output &key exit-code &allow-other-keys)
    (declare (ignore output))
    (if (eql exit-code 0) :pass :fail)))

(register-verifier :contains
  (lambda (output &key expected &allow-other-keys)
    (if (and output expected (search expected output))
        :pass :fail)))

(register-verifier :not-contains
  (lambda (output &key expected &allow-other-keys)
    (if (and output expected (not (search expected output)))
        :pass :fail)))

(register-verifier :regex
  (lambda (output &key expected &allow-other-keys)
    (if (and output expected (cl-ppcre:scan expected output))
        :pass :fail)))

(register-verifier :exact-match
  (lambda (output &key expected &allow-other-keys)
    (if (and output expected (string= output expected))
        :pass :fail)))

(register-verifier :non-empty
  (lambda (output &key &allow-other-keys)
    (if (and output (> (length output) 0))
        :pass :fail)))

(register-verifier :always-pass
  (lambda (output &key &allow-other-keys)
    (declare (ignore output))
    :pass))
