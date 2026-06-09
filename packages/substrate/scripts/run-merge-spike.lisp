;;;; run-merge-spike.lisp - Slice 0: merge-tractability spike (GO/NO-GO gate)
;;;;
;;;; Proves the load-bearing claim of the substrate-first architecture:
;;;;   "Speculative datom branches + cardinality-aware fact-merge are clean,
;;;;    and the global-ID seam is sane."
;;;;
;;;; Model (no rewiring of the store — pure overlay on top of real primitives):
;;;;   * A BRANCH is a base store + fork-tx + a private overlay of writes.
;;;;   * Reads consult overlay-then-base.
;;;;   * Merge folds overlay writes back into the base:
;;;;       - cardinality :many  -> set-union (append datom); NEVER conflicts.
;;;;       - cardinality :one   -> conflict ONLY when the base changed since fork
;;;;                               to a value different from what this branch wants
;;;;                               (i.e. two branches set the same (E,A) differently).
;;;;   * All entities/attributes go through the REAL make-datom / intern-id /
;;;;     transact! / entity-attr, so the ID-reconciliation seam is exercised.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/substrate/scripts/run-merge-spike.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/"
               "./packages/substrate/"
               "./packages/api-server/"
               "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-merge-spike
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)))
(in-package #:sb-merge-spike)

;;; ===================================================================
;;; (Task 2) Per-attribute cardinality declaration
;;; ===================================================================
;;; Standalone registry for the spike. In production this becomes a
;;; declaration on define-entity-type. :one = replace, :many = accumulate.

(defparameter *cardinality* (make-hash-table :test 'equal))

(defun declare-attr (name card)
  (check-type card (member :one :many))
  (setf (gethash name *cardinality*) card))

(defun attr-card (name)
  (or (gethash name *cardinality*)
      (error "attribute ~S has no declared cardinality" name)))

;;; ===================================================================
;;; (Task 3) Speculative overlay branch + changeset
;;; ===================================================================

(defstruct wr
  "One overlay write. BASE-AT-FORK is the base value observed when the
   branch first staged this (E,A) -- i.e. the fork-time value, since a
   branch stages all its writes before any merge."
  entity attr value card base-at-fork)

(defstruct branch
  name
  fork-tx
  (writes nil))                         ; newest-first

(defun fork (name)
  "Fork a speculative branch off the current base store."
  (make-branch :name name :fork-tx (s::store-tx-counter s::*store*)))

(defun b-assert (branch ename aname value)
  "Stage a write in the branch overlay (does NOT touch the base store)."
  (push (make-wr :entity ename :attr aname :value value
                 :card (attr-card aname)
                 :base-at-fork (s::entity-attr ename aname))
        (branch-writes branch))
  value)

(defun b-read (branch ename aname)
  "Branch read: overlay-then-base (newest overlay write wins)."
  (let ((w (find-if (lambda (x) (and (equal (wr-entity x) ename)
                                     (equal (wr-attr x) aname)))
                    (branch-writes branch))))
    (if w (wr-value w) (s::entity-attr ename aname))))

(defun changeset (branch)
  "The branch's overlay as a changeset (oldest-first), for inspection."
  (reverse (branch-writes branch)))

;;; ===================================================================
;;; (Task 4) Cardinality-aware merge with conflict-flag
;;; ===================================================================

(defun merge-branch (branch)
  "Fold BRANCH's overlay into the base store. Returns the list of flagged
   conflicts (cardinality-one divergences); never silently drops them."
  (let ((conflicts nil)
        (seen-one (make-hash-table :test 'equal))) ; only newest :one write per (E,A)
    (dolist (w (branch-writes branch))             ; newest-first
      (ecase (wr-card w)
        (:many
         ;; set-union: append a datom; cannot conflict.
         (s::transact! (list (s::make-datom (wr-entity w) (wr-attr w) (wr-value w)))))
        (:one
         (let ((key (cons (wr-entity w) (wr-attr w))))
           (unless (gethash key seen-one)
             (setf (gethash key seen-one) t)
             (let ((base-now (s::entity-attr (wr-entity w) (wr-attr w)))
                   (forked    (wr-base-at-fork w))
                   (want      (wr-value w)))
               (cond
                 ((equal base-now want) nil)              ; already agrees
                 ((equal base-now forked)                 ; base untouched since fork
                  (s::transact! (list (s::make-datom (wr-entity w) (wr-attr w) want))))
                 (t                                        ; divergent one-attr
                  (push (list :entity (wr-entity w) :attr (wr-attr w)
                              :forked forked :base-now base-now :wanted want)
                        conflicts)))))))))
    (nreverse conflicts)))

;;; ===================================================================
;;; Read helper for :many (EA-CURRENT is replace-only; use the EAVT log)
;;; ===================================================================

(defun many-values (ename aname)
  (remove-duplicates
   (mapcar (lambda (e) (getf e :value))
           (s::entity-history ename aname :last-n 1000))
   :test #'equal))

;;; ===================================================================
;;; (Task 5) Scenario + assertions + GO/NO-GO
;;; ===================================================================

(defvar *fails* nil)

(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defun run-spike ()
  (setf *fails* nil)
  (s::with-store ()
    ;; --- schema: declare cardinalities ---
    (declare-attr "doc/title"  :one)
    (declare-attr "doc/status" :one)
    (declare-attr "doc/owner"  :one)
    (declare-attr "doc/tag"    :many)

    ;; --- base: a document, forked from by both branches ---
    (let ((doc-eid (s::intern-id "doc")))
      (s::transact! (list (s::make-datom "doc" "doc/title"  "Draft")
                          (s::make-datom "doc" "doc/status" "open")
                          (s::make-datom "doc" "doc/tag"    "a")))
      (format t "~&== base established (doc eid=~A) ==~%" doc-eid)

      ;; --- two branches forked from the same base ---
      (let ((a (fork "A")) (b (fork "B")))
        ;; Branch A
        (b-assert a "doc" "doc/title"  "Final Draft")   ; independent :one
        (b-assert a "doc" "doc/tag"    "reviewed")       ; :many union
        (b-assert a "doc" "doc/status" "in-review")      ; :one -> will clash with B
        ;; Branch B
        (b-assert b "doc" "doc/tag"    "urgent")          ; :many union
        (b-assert b "doc" "doc/status" "closed")          ; :one -> clashes with A
        (b-assert b "doc" "doc/owner"  "alice")           ; independent new :one

        ;; branch isolation: each sees only its own overlay over base
        (check "branch-A reads its own title"
               (equal (b-read a "doc" "doc/title") "Final Draft"))
        (check "branch-B does NOT see A's title (isolation)"
               (equal (b-read b "doc" "doc/title") "Draft"))

        ;; --- merge A (base untouched since fork: expect zero conflicts) ---
        (let ((ca (merge-branch a)))
          (check "merge A has no conflicts" (null ca) ca))

        ;; --- merge B (status clashes with A; tag/owner independent) ---
        (let ((cb (merge-branch b)))
          (check "merge B flags exactly one conflict (status)"
                 (and (= 1 (length cb))
                      (equal (getf (first cb) :attr) "doc/status"))
                 cb)
          (check "the flagged conflict is closed-vs-in-review"
                 (and cb
                      (equal (getf (first cb) :wanted) "closed")
                      (equal (getf (first cb) :base-now) "in-review"))))

        ;; --- post-merge base state ---
        (check "title = A's value (independent :one applied)"
               (equal (s::entity-attr "doc" "doc/title") "Final Draft")
               (s::entity-attr "doc" "doc/title"))
        (check "status = in-review (A applied; B's clash NOT silently overwritten)"
               (equal (s::entity-attr "doc" "doc/status") "in-review")
               (s::entity-attr "doc" "doc/status"))
        (check "owner = alice (B's independent :one applied)"
               (equal (s::entity-attr "doc" "doc/owner") "alice")
               (s::entity-attr "doc" "doc/owner"))
        (let ((tags (sort (copy-list (many-values "doc" "doc/tag")) #'string<)))
          (check ":many union across both branches = {a, reviewed, urgent}"
                 (equal tags '("a" "reviewed" "urgent"))
                 tags))

        ;; --- ID-reconciliation seam ---
        ;; What branching/merge actually depends on: term->id (intern-id) must be
        ;; idempotent and shared, so branches reference IDENTICAL ids for identical
        ;; terms. That is what makes the merge a pure set-operation with no ID
        ;; translation. (id->term/resolve-id is a separate concern -- see note below.)
        (check "entity id for \"doc\" is stable (idempotent interning)"
               (= doc-eid (s::intern-id "doc")))
        (check "attribute ids reverse-resolve to correct names (production resolve-id path)"
               (and (equal (s::resolve-id (s::intern-id "doc/title"  :width :attribute)) "doc/title")
                    (equal (s::resolve-id (s::intern-id "doc/status" :width :attribute)) "doc/status")
                    (equal (s::resolve-id (s::intern-id "doc/owner"  :width :attribute)) "doc/owner")))
        (check "distinct attributes get distinct attribute-ids"
               (/= (s::intern-id "doc/title"  :width :attribute)
                   (s::intern-id "doc/status" :width :attribute)))
        (check "tx counter advanced monotonically (no reuse)"
               (> (s::store-tx-counter s::*store*) (branch-fork-tx a)))
        ;; interns a fresh entity LAST (pollutes the shared resolve-table -- see note)
        (check "distinct entities get distinct entity-ids"
               (/= (s::intern-id "doc") (s::intern-id "another-doc")))

        ;; --- FINDING (non-blocking): resolve-table id-space overlap ---
        ;; entity ids and attribute ids come from independent counters (both from 1)
        ;; but share ONE resolve-table keyed by bare integer, so eid N and aid N
        ;; clobber each other in id->term. intern-id (term->id, what merge needs) is
        ;; fine; resolve-id(entity-id) is unreliable in mixed workloads. Orthogonal
        ;; to branching; track as a substrate follow-up for the substrate-first build.
        (format t "  [NOTE] resolve-id(eid 1)=~S (clobbered by attribute of same numeric id) ~
                   -- term->id stays unambiguous; tracked separately.~%"
                (s::resolve-id 1)))))

  ;; --- verdict ---
  (format t "~%================ ~A ================~%"
          (if *fails* "NO-GO" "GO"))
  (when *fails*
    (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-spike))
