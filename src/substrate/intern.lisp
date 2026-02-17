;;;; intern.lisp - Monotonic-counter interning for compact integer IDs
;;;;
;;;; Maps arbitrary objects to compact monotonic integers.
;;;; Entity IDs use u64 counter, attribute IDs use u32 counter.
;;;; Pattern from Bubble CL's intern-term: monotonic counter
;;;; avoids birthday-paradox collisions that hash truncation would cause.
;;;;
;;;; All state is stored in the *substrate* context object.
;;;; The old special variables are kept as backward-compat accessors.

(in-package #:autopoiesis.substrate)

;;; Backward-compat accessors — these symbol-macros expand to context slots
;;; so existing code that reads/writes them continues to work.
(defvar *next-entity-id* 1
  "DEPRECATED: Use (substrate-context-next-entity-id *substrate*).
   Kept for backward compatibility in code not yet migrated.")

(defvar *next-attribute-id* 1
  "DEPRECATED: Use (substrate-context-next-attribute-id *substrate*).
   Kept for backward compatibility in code not yet migrated.")

(defvar *intern-table* (make-hash-table :test 'equal)
  "DEPRECATED: Use (substrate-context-intern-table *substrate*).
   Forward map: object -> interned integer ID")

(defvar *resolve-table* (make-hash-table :test 'eql)
  "DEPRECATED: Use (substrate-context-resolve-table *substrate*).
   Reverse map: integer ID -> original object")

(defun intern-id (term &key (width :entity))
  "Intern TERM to a compact integer. Idempotent.
   WIDTH is :entity (u64, default) or :attribute (u32).
   Uses monotonic counter, NOT hash truncation."
  (let* ((ctx *substrate*)
         (intern-tbl (if ctx (substrate-context-intern-table ctx) *intern-table*))
         (resolve-tbl (if ctx (substrate-context-resolve-table ctx) *resolve-table*)))
    (or (gethash term intern-tbl)
        (let ((id (ecase width
                    (:entity
                     (if ctx
                         (prog1 (substrate-context-next-entity-id ctx)
                           (incf (substrate-context-next-entity-id ctx)))
                         (prog1 *next-entity-id*
                           (incf *next-entity-id*))))
                    (:attribute
                     (if ctx
                         (prog1 (substrate-context-next-attribute-id ctx)
                           (incf (substrate-context-next-attribute-id ctx)))
                         (prog1 *next-attribute-id*
                           (incf *next-attribute-id*)))))))
          (setf (gethash term intern-tbl) id)
          (setf (gethash id resolve-tbl) term)
          id))))

(defun resolve-id (id)
  "Resolve interned ID back to original term."
  (let* ((ctx *substrate*)
         (resolve-tbl (if ctx (substrate-context-resolve-table ctx) *resolve-table*)))
    (gethash id resolve-tbl)))

(defun reset-intern-tables ()
  "Reset all intern state. For testing only."
  (let ((ctx *substrate*))
    (if ctx
        (progn
          (clrhash (substrate-context-intern-table ctx))
          (clrhash (substrate-context-resolve-table ctx))
          (setf (substrate-context-next-entity-id ctx) 1)
          (setf (substrate-context-next-attribute-id ctx) 1))
        (progn
          (clrhash *intern-table*)
          (clrhash *resolve-table*)
          (setf *next-entity-id* 1)
          (setf *next-attribute-id* 1)))))
