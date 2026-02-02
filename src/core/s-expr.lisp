;;;; s-expr.lisp - S-expression utilities for Autopoiesis
;;;;
;;;; Provides the foundational S-expression operations:
;;;; - Structural equality and hashing
;;;; - Serialization and deserialization
;;;; - Diffing and patching

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun make-uuid ()
  "Generate a UUID v4 string."
  (format nil "~8,'0x-~4,'0x-~4,'0x-~4,'0x-~12,'0x"
          (random (expt 16 8))
          (random (expt 16 4))
          (logior #x4000 (random #x0fff))  ; Version 4
          (logior #x8000 (random #x3fff))  ; Variant
          (random (expt 16 12))))

(defun get-precise-time ()
  "Get current time with high precision as a universal time plus fraction."
  (multiple-value-bind (sec usec) (sb-ext:get-time-of-day)
    (+ sec (/ usec 1000000.0d0))))

(defun truncate-string (string max-length)
  "Truncate STRING to MAX-LENGTH, adding ellipsis if needed."
  (if (<= (length string) max-length)
      string
      (concatenate 'string (subseq string 0 (- max-length 3)) "...")))

(defun sexpr-size (sexpr)
  "Estimate the size of SEXPR in 'tokens' for context window management.
   This is a rough heuristic: atoms count as 1, conses add their car and cdr sizes."
  (typecase sexpr
    (null 1)
    (symbol 1)
    (number 1)
    (string (max 1 (ceiling (length sexpr) 4)))  ; ~4 chars per token
    (cons (+ 1 (sexpr-size (car sexpr)) (sexpr-size (cdr sexpr))))
    (array (+ 1 (loop for i below (array-total-size sexpr)
                      sum (sexpr-size (row-major-aref sexpr i)))))
    (hash-table (+ 1 (loop for k being the hash-keys of sexpr using (hash-value v)
                           sum (+ (sexpr-size k) (sexpr-size v)))))
    (t 1)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Structural Equality
;;; ═══════════════════════════════════════════════════════════════════

(defun sexpr-equal (a b)
  "Deep structural equality for S-expressions.
   Handles atoms, conses, arrays, and hash-tables."
  (typecase a
    (null (null b))
    (symbol (and (symbolp b) (eq a b)))
    (number (and (numberp b) (= a b)))
    (string (and (stringp b) (string= a b)))
    (cons (and (consp b)
               (sexpr-equal (car a) (car b))
               (sexpr-equal (cdr a) (cdr b))))
    (array (and (arrayp b)
                (equal (array-dimensions a) (array-dimensions b))
                (loop for i below (array-total-size a)
                      always (sexpr-equal (row-major-aref a i)
                                          (row-major-aref b i)))))
    (hash-table (and (hash-table-p b)
                     (= (hash-table-count a) (hash-table-count b))
                     (loop for k being the hash-keys of a using (hash-value v)
                           always (multiple-value-bind (bv found)
                                      (gethash k b)
                                    (and found (sexpr-equal v bv))))))
    (t (equal a b))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Content-Addressable Hashing
;;; ═══════════════════════════════════════════════════════════════════

(defun sexpr-hash (sexpr)
  "Content-addressable hash for S-expressions.
   Two structurally equal S-expressions produce the same hash.
   Returns a hex string."
  (let ((digester (ironclad:make-digest :sha256)))
    (sexpr-hash-into digester sexpr)
    (ironclad:byte-array-to-hex-string
     (ironclad:produce-digest digester))))

(defun sexpr-hash-into (digester sexpr)
  "Incrementally hash SEXPR into DIGESTER."
  (flet ((update-bytes (bytes)
           (ironclad:update-digest digester
                                   (if (stringp bytes)
                                       (babel:string-to-octets bytes :encoding :utf-8)
                                       bytes))))
    (typecase sexpr
      (null (update-bytes (make-array 1 :element-type '(unsigned-byte 8) :initial-element 0)))
      (symbol (update-bytes "S")
              (update-bytes (symbol-name sexpr)))
      (integer (update-bytes "I")
               (update-bytes (princ-to-string sexpr)))
      (float (update-bytes "F")
             (update-bytes (princ-to-string sexpr)))
      (string (update-bytes "\"")
              (update-bytes sexpr))
      (cons (update-bytes "(")
            (sexpr-hash-into digester (car sexpr))
            (update-bytes ".")
            (sexpr-hash-into digester (cdr sexpr))
            (update-bytes ")"))
      (t (update-bytes "?")
         (update-bytes (princ-to-string sexpr))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *sexpr-serialization-format* :readable
  "Format for serialization: :READABLE (print/read) or :JSON")

(defun sexpr-serialize (sexpr &optional stream)
  "Serialize SEXPR to a string or STREAM.
   Uses *SEXPR-SERIALIZATION-FORMAT* to determine output format."
  (ecase *sexpr-serialization-format*
    (:readable
     (let ((*print-readably* t)
           (*print-circle* t)
           (*print-array* t)
           (*print-length* nil)
           (*print-level* nil)
           (*package* (find-package :autopoiesis.core)))
       (if stream
           (prin1 sexpr stream)
           (prin1-to-string sexpr))))
    (:json
     (cl-json:encode-json-to-string sexpr))))

(defun sexpr-deserialize (input)
  "Deserialize INPUT (string or stream) to an S-expression."
  (handler-case
      (etypecase input
        (string (let ((*package* (find-package :autopoiesis.core)))
                  (read-from-string input)))
        (stream (let ((*package* (find-package :autopoiesis.core)))
                  (read input))))
    (error (e)
      (error 'deserialization-error
             :input input
             :message (format nil "~a" e)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Diffing and Patching
;;; ═══════════════════════════════════════════════════════════════════

(defstruct (sexpr-edit (:constructor make-edit (type path old new)))
  "An edit operation in an S-expression diff."
  (type nil :type (member :replace :insert :delete))
  (path nil :type list)    ; Path to the location (list of :car/:cdr)
  (old nil)                ; Previous value
  (new nil))               ; New value

(defun sexpr-diff (old new &optional (path nil))
  "Compute minimal diff between OLD and NEW S-expressions.
   Returns a list of SEXPR-EDIT operations."
  (cond
    ;; Identical - no diff
    ((sexpr-equal old new) nil)

    ;; Both conses - recurse
    ((and (consp old) (consp new))
     (append (sexpr-diff (car old) (car new) (append path '(:car)))
             (sexpr-diff (cdr old) (cdr new) (append path '(:cdr)))))

    ;; Different - replace
    (t (list (make-edit :replace path old new)))))

(defun sexpr-patch (sexpr edits)
  "Apply EDITS to SEXPR, returning new S-expression.
   Does not modify original."
  (let ((result (copy-tree sexpr)))
    (dolist (edit edits result)
      (setf result (apply-edit result edit)))))

(defun apply-edit (sexpr edit)
  "Apply a single SEXPR-EDIT to SEXPR."
  (if (null (sexpr-edit-path edit))
      ;; At target location
      (ecase (sexpr-edit-type edit)
        (:replace (sexpr-edit-new edit))
        (:delete nil)
        (:insert (sexpr-edit-new edit)))
      ;; Navigate deeper
      (let ((direction (first (sexpr-edit-path edit)))
            (rest-edit (make-edit (sexpr-edit-type edit)
                                  (rest (sexpr-edit-path edit))
                                  (sexpr-edit-old edit)
                                  (sexpr-edit-new edit))))
        (ecase direction
          (:car (cons (apply-edit (car sexpr) rest-edit) (cdr sexpr)))
          (:cdr (cons (car sexpr) (apply-edit (cdr sexpr) rest-edit)))))))
