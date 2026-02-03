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

;;; ═══════════════════════════════════════════════════════════════════
;;; Memory Compaction
;;; ═══════════════════════════════════════════════════════════════════

(defvar *thought-archive-path* nil
  "Base path for archiving thoughts. If NIL, archiving is disabled.")

(defun compact-thought-stream (stream &key (keep-last 100) (archive-path *thought-archive-path*))
  "Compact old thoughts to reduce memory usage.

   Arguments:
     stream      - The thought stream to compact
     keep-last   - Number of recent thoughts to keep in memory (default 100)
     archive-path - Path to archive old thoughts (if NIL, old thoughts are discarded)

   Returns: (values archived-count kept-count)
     archived-count - Number of thoughts archived (or discarded if no archive-path)
     kept-count     - Number of thoughts kept in memory

   When the stream has more than (* keep-last 2) thoughts, this function:
   1. Archives thoughts older than keep-last to disk (if archive-path provided)
   2. Removes archived thoughts from memory
   3. Rebuilds the stream index

   Example:
     (compact-thought-stream my-stream :keep-last 50 :archive-path #p\"/tmp/thoughts/\")"
  (let* ((thoughts (stream-thoughts stream))
         (total-count (length thoughts)))
    ;; Only compact if we have significantly more than keep-last
    (when (> total-count (* keep-last 2))
      (let* ((archive-count (- total-count keep-last))
             (to-archive (subseq thoughts 0 archive-count))
             (to-keep (subseq thoughts archive-count)))
        ;; Archive to disk if path provided
        (when archive-path
          (archive-thoughts to-archive archive-path))
        ;; Update stream with only recent thoughts
        (let ((new-thoughts (make-array (length to-keep)
                                        :adjustable t
                                        :fill-pointer (length to-keep))))
          (loop for i from 0 below (length to-keep)
                do (setf (aref new-thoughts i) (aref to-keep i)))
          (setf (stream-thoughts stream) new-thoughts))
        ;; Rebuild indices
        (rebuild-stream-indices stream)
        (return-from compact-thought-stream
          (values archive-count (length to-keep)))))
    ;; No compaction needed
    (values 0 total-count)))

(defun archive-thoughts (thoughts archive-path)
  "Archive THOUGHTS vector to ARCHIVE-PATH.

   Creates a timestamped archive file containing the serialized thoughts.
   File format: thoughts-TIMESTAMP.sexpr

   Arguments:
     thoughts     - Vector of thought objects to archive
     archive-path - Directory path for archive files"
  (let* ((timestamp (get-precise-time))
         (filename (format nil "thoughts-~,6f.sexpr" timestamp))
         (full-path (merge-pathnames filename archive-path)))
    ;; Ensure directory exists
    (ensure-directories-exist full-path)
    ;; Write thoughts to file
    (with-open-file (out full-path
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create
                         :external-format :utf-8)
      (let ((*print-readably* t)
            (*print-circle* t)
            (*print-array* t)
            (*print-length* nil)
            (*print-level* nil))
        (prin1 `(:thought-archive
                 :version 1
                 :timestamp ,timestamp
                 :count ,(length thoughts)
                 :thoughts ,(map 'list #'thought-to-sexpr thoughts))
               out)))
    full-path))

(defun rebuild-stream-indices (stream)
  "Rebuild the ID -> position index for STREAM after compaction."
  (let ((indices (make-hash-table :test 'equal))
        (thoughts (stream-thoughts stream)))
    (loop for i from 0 below (length thoughts)
          for thought = (aref thoughts i)
          do (setf (gethash (thought-id thought) indices) i))
    (setf (stream-indices stream) indices)))

(defun load-archived-thoughts (archive-file)
  "Load thoughts from an archive file.

   Arguments:
     archive-file - Path to the archive file

   Returns: List of thought objects, or NIL if file doesn't exist or is invalid"
  (when (probe-file archive-file)
    (handler-case
        (with-open-file (in archive-file
                            :direction :input
                            :external-format :utf-8)
          (let* ((sexpr (read in))
                 (plist (rest sexpr))
                 (thought-sexprs (getf plist :thoughts)))
            (mapcar #'sexpr-to-thought thought-sexprs)))
      (error (e)
        (warn "Failed to load archived thoughts from ~a: ~a" archive-file e)
        nil))))
