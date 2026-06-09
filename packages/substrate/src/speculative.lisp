;;;; speculative.lisp - Speculative datom branches + cardinality-aware merge
;;;;
;;;; A speculative branch is a private overlay of staged writes on top of a
;;;; shared base store (Datomic `d/with` style). Reads consult overlay-then-base.
;;;;
;;;; Writes are staged BY NAME and are intern-free until merge: branch-stage
;;;; only READS the base (entity-attr) and the cardinality registry; it never
;;;; interns or transacts. This is what lets many branches be built concurrently
;;;; (read-only on shared state, no interning race) and folded back sequentially
;;;; at fan-in, where the single store lock and interning are exercised safely.
;;;;
;;;; Merge is cardinality-aware:
;;;;   :many -> set-union (append a datom); NEVER conflicts.
;;;;   :one  -> conflict ONLY when the base changed since fork to a value
;;;;            different from what the branch wants (two branches diverging on
;;;;            the same (E,A)). Conflicts are returned, never silently dropped.
;;;;
;;;; Validated by packages/substrate/scripts/run-merge-spike.lisp (Slice 0).

(in-package #:autopoiesis.substrate)

;;; ===================================================================
;;; Per-attribute cardinality (the schema that makes merge decidable)
;;; ===================================================================

(defvar *attribute-cardinality* (make-hash-table :test 'equal)
  "Maps attribute name -> :one (replace) or :many (accumulate).
   In a fuller build this becomes a declaration on define-entity-type.")

(defun declare-cardinality (attribute cardinality)
  "Declare ATTRIBUTE as :one (replace) or :many (accumulate)."
  (check-type cardinality (member :one :many))
  (setf (gethash attribute *attribute-cardinality*) cardinality))

(defun attribute-cardinality (attribute)
  "Cardinality of ATTRIBUTE. Errors if undeclared (merge must be decidable)."
  (or (gethash attribute *attribute-cardinality*)
      (error "attribute ~S has no declared cardinality" attribute)))

;;; ===================================================================
;;; Branch
;;; ===================================================================

(defstruct branch-write
  "One staged overlay write. BASE-AT-FORK is the base value observed when the
   write was staged (= the fork-time value, since staging precedes any merge)."
  entity attribute value cardinality base-at-fork)

(defstruct datom-branch
  name
  fork-tx
  (writes nil))                         ; newest-first

(defun branch-fork (&key name (store *store*))
  "Fork a speculative branch off the current base STORE (O(1))."
  (make-datom-branch :name name :fork-tx (store-tx-counter store)))

(defun branch-stage (branch entity attribute value)
  "Stage a write into BRANCH's overlay. Intern-free: records the base value
   observed now. Does not touch the base store."
  (push (make-branch-write :entity entity :attribute attribute :value value
                           :cardinality (attribute-cardinality attribute)
                           :base-at-fork (entity-attr entity attribute))
        (datom-branch-writes branch))
  value)

(defun branch-read (branch entity attribute)
  "Branch read: overlay-then-base (newest overlay write wins)."
  (let ((w (find-if (lambda (x) (and (equal (branch-write-entity x) entity)
                                     (equal (branch-write-attribute x) attribute)))
                    (datom-branch-writes branch))))
    (if w (branch-write-value w) (entity-attr entity attribute))))

(defun branch-changeset (branch)
  "BRANCH's staged overlay as a changeset, oldest-first."
  (reverse (datom-branch-writes branch)))

;;; ===================================================================
;;; Cardinality-aware merge (fan-in)
;;; ===================================================================

(defstruct merge-conflict
  entity attribute forked base-now wanted)

(defun branch-merge (branch &key (store *store*))
  "Fold BRANCH's overlay into the base STORE. Sequential (call from the
   orchestrator at fan-in). Returns (values applied-count conflicts), where
   CONFLICTS is a list of MERGE-CONFLICT for cardinality-one divergences --
   never silently dropped."
  (let ((conflicts nil)
        (applied 0)
        (seen-one (make-hash-table :test 'equal))) ; only newest :one write per (E,A)
    (dolist (w (datom-branch-writes branch))        ; newest-first
      (ecase (branch-write-cardinality w)
        (:many
         (transact! (list (make-datom (branch-write-entity w)
                                      (branch-write-attribute w)
                                      (branch-write-value w)))
                    :store store)
         (incf applied))
        (:one
         (let ((key (cons (branch-write-entity w) (branch-write-attribute w))))
           (unless (gethash key seen-one)
             (setf (gethash key seen-one) t)
             (let ((base-now (entity-attr (branch-write-entity w)
                                          (branch-write-attribute w)))
                   (forked (branch-write-base-at-fork w))
                   (want (branch-write-value w)))
               (cond
                 ((equal base-now want) nil)         ; already agrees
                 ((equal base-now forked)            ; base untouched since fork
                  (transact! (list (make-datom (branch-write-entity w)
                                               (branch-write-attribute w)
                                               want))
                             :store store)
                  (incf applied))
                 (t                                   ; divergent one-attr
                  (push (make-merge-conflict
                         :entity (branch-write-entity w)
                         :attribute (branch-write-attribute w)
                         :forked forked :base-now base-now :wanted want)
                        conflicts)))))))))
    (values applied (nreverse conflicts))))
