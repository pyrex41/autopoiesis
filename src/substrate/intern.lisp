;;;; intern.lisp - Monotonic-counter interning for compact integer IDs
;;;;
;;;; Maps arbitrary objects to compact monotonic integers.
;;;; Entity IDs use u64 counter, attribute IDs use u32 counter.
;;;; Pattern from Bubble CL's intern-term: monotonic counter
;;;; avoids birthday-paradox collisions that hash truncation would cause.

(in-package #:autopoiesis.substrate)

(defvar *next-entity-id* 1
  "Monotonic counter for entity IDs (u64 space)")

(defvar *next-attribute-id* 1
  "Monotonic counter for attribute IDs (u32 space)")

(defvar *intern-table* (make-hash-table :test 'equal)
  "Forward map: object -> interned integer ID")

(defvar *resolve-table* (make-hash-table :test 'eql)
  "Reverse map: integer ID -> original object")

(defun intern-id (term &key (width :entity))
  "Intern TERM to a compact integer. Idempotent.
   WIDTH is :entity (u64, default) or :attribute (u32).
   Uses monotonic counter, NOT hash truncation."
  (or (gethash term *intern-table*)
      (let ((id (ecase width
                  (:entity (prog1 *next-entity-id*
                             (incf *next-entity-id*)))
                  (:attribute (prog1 *next-attribute-id*
                                (incf *next-attribute-id*))))))
        (setf (gethash term *intern-table*) id)
        (setf (gethash id *resolve-table*) term)
        id)))

(defun resolve-id (id)
  "Resolve interned ID back to original term."
  (gethash id *resolve-table*))

(defun reset-intern-tables ()
  "Reset all intern state. For testing only."
  (clrhash *intern-table*)
  (clrhash *resolve-table*)
  (setf *next-entity-id* 1)
  (setf *next-attribute-id* 1))
