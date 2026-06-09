;;;; run-product-loop-demo.lisp - Slice 3a: the product loop on the substrate
;;;;
;;;; Ties the substrate-first primitives into the actual product: a team-owned
;;;; builder works a board, consults the team at a deliberation gate, teammates
;;;; fork-to-propose alternatives, and every decision is queryable provenance.
;;;;
;;;; What it proves (all on the live substrate, reusing Slices 0-2):
;;;;   1. BOARD / lanes: builder atomically claims a ticket via take! (Linda).
;;;;   2. DELIBERATION GATE: builder posts a question; teammates give inputs;
;;;;      the lead resolves (lead-decides); dissent is RETAINED as datoms.
;;;;   3. FORK-TO-PROPOSE (hybrid): teammates fork the builder's state and
;;;;      propose alternatives; independent proposals union, a same-attr
;;;;      divergence is FLAGGED for the lead (= the Slice-0/1 fact-merge).
;;;;   4. PROVENANCE: datalog q + entity-as-of answer "why did we decide X,
;;;;      who dissented, what alternative did we reject, what was the board
;;;;      before the builder claimed it".
;;;;
;;;; Design: deliberation facts (question/input/resolution) are transacted to the
;;;; shared base (immediately datalog-queryable -- the queryable decision history
;;;; IS the product). The builder's code-work lives on speculative branches that
;;;; merge in. Attributes are KEYWORDS (datalog convention).
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/substrate/scripts/run-product-loop-demo.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-product-demo
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)))
(in-package #:sb-product-demo)

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defvar *clock* 1000)
(defun tick () (incf *clock*))          ; deterministic monotonic timestamps

;;; ---- deliberation gate (facts on the shared base) ----
(defun make-decision (name question ticket-eid)
  (let ((d (s:intern-id name)))
    (s:transact! (list (s:make-datom d :decision/question question)
                       (s:make-datom d :decision/ticket ticket-eid)
                       (s:make-datom d :decision/status :open)
                       (s:make-datom d :decision/at (tick))))
    d))

(defun add-input (name decision user text)
  "A teammate weighs in on a decision. Retained forever as provenance."
  (let ((i (s:intern-id name)))
    (s:transact! (list (s:make-datom i :input/decision decision)
                       (s:make-datom i :input/user user)
                       (s:make-datom i :input/text text)
                       (s:make-datom i :input/at (tick))))
    i))

(defun resolve-decision (decision lead chosen-text)
  "Lead-decides: record the resolution; dissenting inputs are NOT deleted."
  (s:transact! (list (s:make-datom decision :decision/resolution chosen-text)
                     (s:make-datom decision :decision/resolved-by lead)
                     (s:make-datom decision :decision/status :resolved)
                     (s:make-datom decision :decision/resolved-at (tick)))))

;;; ---- provenance queries ----
(defun decision-inputs (decision)
  "List of (user . text) for a decision, via datalog."
  (mapcar (lambda (tup) (cons (first tup) (second tup)))
          (s:q '(:find ?u ?t :in ?d
                 :where (?i :input/decision ?d) (?i :input/user ?u) (?i :input/text ?t))
               decision)))

(defun dissenters (decision)
  "Users whose input differs from the resolution (the logged dissent)."
  (let ((res (s:entity-attr decision :decision/resolution)))
    (loop for (u . tx) in (decision-inputs decision)
          unless (equal tx res) collect u)))

(defun attr-as-of (entity attribute tx-id)
  "Value of (ENTITY, ATTRIBUTE) as of TX-ID: newest EAVT entry with tx<=TX-ID,
   via entity-history (forward term->id). A single-attribute alternative to
   entity-as-of (both now correct after the resolve-id width-aware fix)."
  (loop for e in (s:entity-history entity attribute :last-n 100000)
        when (<= (getf e :tx) tx-id) return (getf e :value)))

;;; ===================================================================
(defun run-demo ()
  (setf *fails* nil)
  (s:with-store ()
    ;; cardinalities for the fork-to-propose layer
    (s:declare-cardinality :module/impl :one)
    (s:declare-cardinality :module/doc  :one)

    ;; ---------- 1. BOARD: ticket in the AI-ready lane ----------
    (let ((ticket (s:intern-id "ticket-1")))
      (s:transact! (list (s:make-datom ticket :ticket/title "Add storage backend")
                         (s:make-datom ticket :ticket/status :ai-ready)))
      (let ((tx-before-claim (s::store-tx-counter s:*store*)))

        ;; builder atomically claims it (Linda take!)
        (let ((claimed (s:take! :ticket/status :ai-ready :new-value :in-progress)))
          (check "builder atomically claimed the AI-ready ticket"
                 (eql claimed ticket) claimed))
        (check "second claim finds nothing (atomic lane-claim)"
               (null (s:take! :ticket/status :ai-ready :new-value :in-progress)))

        ;; ---------- 2. DELIBERATION GATE (lead-decides, dissent logged) ----------
        (let ((dec (make-decision "decision-1"
                                  "Which storage backend: sqlite, lmdb, or postgres?"
                                  ticket)))
          (add-input "in-alice" dec "alice" "lmdb")
          (add-input "in-bob"   dec "bob"   "postgres")
          (add-input "in-carol" dec "carol" "lmdb")
          ;; the lead weighs the team and decides
          (resolve-decision dec "lead" "lmdb")

          (check "decision resolved to the lead's pick"
                 (equal (s:entity-attr dec :decision/resolution) "lmdb"))
          (check "all 3 team inputs retained as provenance"
                 (= 3 (length (decision-inputs dec))) (decision-inputs dec))
          (check "dissent is logged + identifiable (bob preferred postgres)"
                 (equal (dissenters dec) '("bob")) (dissenters dec))

          ;; ---------- builder does the work on a branch, per the resolution ----------
          (let ((bw (s:branch-fork :name "builder")))
            (s:branch-stage bw "module" :module/impl
                            (format nil "storage=~A" (s:entity-attr dec :decision/resolution)))
            (s:branch-merge bw))
          (check "builder's work merged to base (impl reflects the decision)"
                 (equal (s:entity-attr "module" :module/impl) "storage=lmdb"))

          ;; ---------- 3. FORK-TO-PROPOSE (hybrid, lead-gated) ----------
          ;; dave proposes an INDEPENDENT addition (docs) -> unions clean.
          (let ((dave (s:branch-fork :name "dave")))
            (s:branch-stage dave "module" :module/doc "added README")
            (multiple-value-bind (applied conflicts) (s:branch-merge dave)
              (check "independent proposal (docs) accepted, no conflict"
                     (and (plusp applied) (null conflicts)))))

          ;; bob and carol BOTH fork from impl=storage=lmdb and propose rival impls.
          (let ((bob   (s:branch-fork :name "bob-impl"))
                (carol (s:branch-fork :name "carol-impl")))
            (s:branch-stage bob   "module" :module/impl "storage=lmdb;cache=lru")
            (s:branch-stage carol "module" :module/impl "storage=lmdb;cache=arc")
            ;; lead merges bob first -> clean
            (multiple-value-bind (a c) (s:branch-merge bob)
              (check "first rival impl merges clean" (and (plusp a) (null c))))
            ;; carol now diverges from the moved base -> FLAGGED for the lead
            (multiple-value-bind (a c) (s:branch-merge carol)
              (declare (ignore a))
              (check "rival impl on the same attr is FLAGGED for the lead"
                     (and (= 1 (length c))
                          (eq (s:merge-conflict-attribute (first c)) :module/impl)))
              ;; lead-decides on the proposal too: keep bob's, record why
              (when c
                (s:transact!
                 (list (s:make-datom (s:intern-id "decision-2")
                                     :decision/question "Accept carol's cache=arc impl?")
                       (s:make-datom (s:intern-id "decision-2") :decision/resolution "no: keep cache=lru")
                       (s:make-datom (s:intern-id "decision-2") :decision/resolved-by "lead")
                       (s:make-datom (s:intern-id "decision-2") :decision/status :resolved))))))

          (check "rejected rival did NOT overwrite base (lead kept bob's impl)"
                 (equal (s:entity-attr "module" :module/impl) "storage=lmdb;cache=lru")
                 (s:entity-attr "module" :module/impl))
          (check "independent doc proposal is present"
                 (equal (s:entity-attr "module" :module/doc) "added README"))

          ;; ---------- move ticket to done ----------
          (s:take! :ticket/status :in-progress :new-value :done)

          ;; ---------- 4. PROVENANCE QUERIES ----------
          ;; "why did we decide X?" -- datalog over the decision facts
          (let ((why (s:q '(:find ?q ?r ?by
                            :where (?d :decision/question ?q)
                                   (?d :decision/resolution ?r)
                                   (?d :decision/resolved-by ?by)))))
            (check "datalog 'why' query returns both resolved decisions"
                   (= 2 (length why)) why)
            (check "decision-1 provenance is queryable (question+resolution+lead)"
                   (find-if (lambda (tup)
                              (and (search "storage backend" (first tup))
                                   (equal (second tup) "lmdb")
                                   (equal (third tup) "lead")))
                            why)))

          ;; time-travel: the board BEFORE the builder claimed the ticket.
          ;; entity-as-of now works in mixed workloads (resolve-id is width-aware).
          (check "time-travel: entity-as-of shows ticket :ai-ready before the claim"
                 (eq (getf (s:entity-as-of ticket tx-before-claim) :ticket/status) :ai-ready)
                 (getf (s:entity-as-of ticket tx-before-claim) :ticket/status))
          (check "time-travel: attr-as-of agrees (entity-history path)"
                 (eq (attr-as-of ticket :ticket/status tx-before-claim) :ai-ready))
          (check "current ticket status is :done"
                 (eq (s:entity-attr ticket :ticket/status) :done))))))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-demo))
