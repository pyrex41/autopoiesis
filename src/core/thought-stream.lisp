;;;; thought-stream.lisp - Ordered sequence of thoughts
;;;;
;;;; A thought stream maintains an ordered collection of thoughts
;;;; with fast lookup by ID and filtering capabilities.

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Stream Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass thought-stream ()
  ((thoughts :initarg :thoughts
             :accessor stream-thoughts
             :initform (make-array 0 :adjustable t :fill-pointer 0)
             :documentation "Vector of thoughts in order")
   (indices :initarg :indices
            :accessor stream-indices
            :initform (make-hash-table :test 'equal)
            :documentation "ID -> position index"))
  (:documentation "An ordered stream of thoughts with fast lookup"))

(defun make-thought-stream ()
  "Create a new empty thought stream."
  (make-instance 'thought-stream))

(defmethod print-object ((stream thought-stream) out)
  (print-unreadable-object (stream out :type t)
    (format out "~d thoughts" (length (stream-thoughts stream)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Stream Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun stream-append (stream thought)
  "Append THOUGHT to STREAM. Returns the thought."
  (let ((pos (vector-push-extend thought (stream-thoughts stream))))
    (setf (gethash (thought-id thought) (stream-indices stream)) pos)
    thought))

(defun stream-find (stream id)
  "Find thought by ID in STREAM. Returns NIL if not found."
  (let ((pos (gethash id (stream-indices stream))))
    (when pos
      (aref (stream-thoughts stream) pos))))

(defun stream-length (stream)
  "Return the number of thoughts in STREAM."
  (length (stream-thoughts stream)))

(defun stream-last (stream &optional (n 1))
  "Return the last N thoughts from STREAM."
  (let* ((thoughts (stream-thoughts stream))
         (len (length thoughts))
         (start (max 0 (- len n))))
    (coerce (subseq thoughts start) 'list)))

(defun stream-since (stream timestamp)
  "Get all thoughts since TIMESTAMP."
  (remove-if (lambda (thought)
               (< (thought-timestamp thought) timestamp))
             (coerce (stream-thoughts stream) 'list)))

(defun stream-by-type (stream type)
  "Get all thoughts of TYPE."
  (remove-if-not (lambda (thought)
                   (eq (thought-type thought) type))
                 (coerce (stream-thoughts stream) 'list)))

(defun stream-range (stream start-index &optional end-index)
  "Get thoughts from START-INDEX to END-INDEX (exclusive)."
  (let* ((thoughts (stream-thoughts stream))
         (end (or end-index (length thoughts))))
    (coerce (subseq thoughts start-index end) 'list)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun stream-to-sexpr (stream)
  "Convert entire stream to S-expression."
  (map 'list #'thought-to-sexpr (stream-thoughts stream)))

(defun sexpr-to-stream (sexpr)
  "Reconstruct a thought stream from S-expression."
  (let ((stream (make-thought-stream)))
    (dolist (thought-sexpr sexpr stream)
      (stream-append stream (sexpr-to-thought thought-sexpr)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Iteration Support
;;; ═══════════════════════════════════════════════════════════════════

(defmacro do-thoughts ((var stream &optional result) &body body)
  "Iterate over thoughts in STREAM, binding each to VAR."
  (let ((thoughts-var (gensym "THOUGHTS")))
    `(let ((,thoughts-var (stream-thoughts ,stream)))
       (loop for ,var across ,thoughts-var
             do (progn ,@body))
       ,result)))
