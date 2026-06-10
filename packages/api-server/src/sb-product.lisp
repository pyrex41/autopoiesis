;;;; sb-product.lisp - Slice 3b backend: the product loop as a REST API
;;;;
;;;; Promotes the Slice-3a product-loop logic (board/lanes, deliberation gate,
;;;; decision provenance) from the demo script into a real module backing
;;;; /api/sb/* endpoints. All state is substrate datoms; reads use datalog +
;;;; entity-attr; lane-claims use take!. Mirrors rest-handle-aether.
;;;;
;;;; Scope: the PERSISTENT, queryable product surface (board + deliberation +
;;;; provenance). Fork-to-propose (Slice 3a) needs cross-request branch
;;;; lifecycle and is deferred -- it stays a substrate capability for now.
;;;;
;;;; Entity schema (KEYWORD attrs, datalog convention):
;;;;   ticket   :entity/type :sb-ticket   :ticket/title :ticket/status(:one)
;;;;   decision :entity/type :sb-decision :decision/question :decision/status
;;;;            :decision/resolution :decision/resolved-by :decision/ticket
;;;;   input    :entity/type :sb-input    :input/decision(eid) :input/user
;;;;            :input/text :input/at

(in-package #:autopoiesis.api)

;;; ── schema ───────────────────────────────────────────────────────
(autopoiesis.substrate:declare-cardinality :ticket/status :one)
(autopoiesis.substrate:declare-cardinality :ticket/title  :one)

(defparameter *sb-lanes* '(:backlog :ai-ready :in-progress :review :done))

;;; ── helpers ──────────────────────────────────────────────────────
(defun sb-tx (datoms) (autopoiesis.substrate:transact! datoms))
(defun sb-datom (e a v) (autopoiesis.substrate:make-datom e a v))
(defun sb-attr (e a) (autopoiesis.substrate:entity-attr e a))
(defun sb-name (eid) (autopoiesis.substrate:resolve-id eid :entity))

(defun sb-keyword (s)
  "Coerce a JSON string/keyword into a lane/status keyword."
  (cond ((keywordp s) s)
        ((stringp s) (intern (string-upcase s) :keyword))
        (t s)))

;;; ── board ────────────────────────────────────────────────────────
(defun ticket-alist (eid)
  `((:id . ,(sb-name eid))
    (:title . ,(sb-attr eid :ticket/title))
    (:status . ,(string-downcase (princ-to-string (sb-attr eid :ticket/status))))))

(defun board-alist ()
  "The board as lanes -> tickets. List values are VECTORS so cl-json encodes
   them as JSON arrays (a list cdr in a single-key alist gets flattened)."
  (let ((tickets (autopoiesis.substrate:find-entities :entity/type :sb-ticket)))
    `((:lanes
       . ,(map 'vector
               (lambda (lane)
                 `((:lane . ,(string-downcase (princ-to-string lane)))
                   (:tickets
                    . ,(map 'vector #'ticket-alist
                            (remove-if-not
                             (lambda (eid) (eq (sb-attr eid :ticket/status) lane))
                             tickets)))))
               *sb-lanes*)))))

(defun move-ticket (name to-lane)
  "Move a specific ticket to TO-LANE (direct set)."
  (let ((eid (autopoiesis.substrate:intern-id name)))
    (sb-tx (list (sb-datom eid :ticket/status to-lane)))
    eid))

(defun claim-next (from-lane to-lane)
  "Atomically claim the next ticket in FROM-LANE (Linda take!). Returns name or nil."
  (let ((eid (autopoiesis.substrate:take! :ticket/status from-lane :new-value to-lane)))
    (when eid (sb-name eid))))

;;; ── deliberation gate ────────────────────────────────────────────
(defun decision-inputs (dec-eid)
  "(user . text) for a decision, via datalog."
  (mapcar (lambda (tup) (cons (first tup) (second tup)))
          (autopoiesis.substrate:q
           '(:find ?u ?t :in ?d
             :where (?i :input/decision ?d) (?i :input/user ?u) (?i :input/text ?t))
           dec-eid)))

(defun decision-alist (eid)
  (let* ((res (sb-attr eid :decision/resolution))
         (inputs (decision-inputs eid)))
    `((:id . ,(sb-name eid))
      (:question . ,(sb-attr eid :decision/question))
      (:status . ,(string-downcase (princ-to-string (or (sb-attr eid :decision/status) :open))))
      (:resolution . ,res)
      (:resolved_by . ,(sb-attr eid :decision/resolved-by))
      (:ticket . ,(let ((tk (sb-attr eid :decision/ticket))) (and tk (sb-name tk))))
      (:inputs . ,(map 'vector
                       (lambda (ut)
                         `((:user . ,(car ut)) (:text . ,(cdr ut))
                           (:dissent . ,(if (and res (not (equal (cdr ut) res))) t nil))))
                       inputs))
      (:dissenters . ,(coerce (loop for (u . tx) in inputs
                                    when (and res (not (equal tx res))) collect u)
                              'vector)))))

(defun all-decisions ()
  (mapcar #'decision-alist
          (autopoiesis.substrate:find-entities :entity/type :sb-decision)))

(defun create-decision (name question &optional ticket-name)
  (let ((d (autopoiesis.substrate:intern-id name)))
    (sb-tx (list (sb-datom d :entity/type :sb-decision)
                 (sb-datom d :decision/question question)
                 (sb-datom d :decision/status :open)
                 (when ticket-name
                   (sb-datom d :decision/ticket (autopoiesis.substrate:intern-id ticket-name)))))
    d))

(defun add-decision-input (dec-eid user text)
  (let ((i (autopoiesis.substrate:intern-id
            (format nil "input-~A-~A" (sb-name dec-eid) user))))
    (sb-tx (list (sb-datom i :entity/type :sb-input)
                 (sb-datom i :input/decision dec-eid)
                 (sb-datom i :input/user user)
                 (sb-datom i :input/text text)
                 (sb-datom i :input/at (get-universal-time))))
    i))

(defun resolve-decision* (dec-eid lead resolution)
  "Lead-decides; dissenting inputs are retained (never deleted)."
  (sb-tx (list (sb-datom dec-eid :decision/resolution resolution)
               (sb-datom dec-eid :decision/resolved-by lead)
               (sb-datom dec-eid :decision/status :resolved))))

;;; ── provenance ("why") ───────────────────────────────────────────
(defun why-report ()
  "All resolved decisions with question/resolution/lead, via datalog."
  (mapcar (lambda (tup)
            `((:question . ,(first tup)) (:resolution . ,(second tup))
              (:resolved_by . ,(third tup))))
          (autopoiesis.substrate:q
           '(:find ?q ?r ?by
             :where (?d :decision/question ?q)
                    (?d :decision/resolution ?r)
                    (?d :decision/resolved-by ?by)))))

;;; ── seed (dev convenience) ───────────────────────────────────────
(defun seed-sb-demo ()
  "Populate a sample board + a resolved decision so the console has data."
  (sb-tx (list (sb-datom "sb-t1" :entity/type :sb-ticket)
               (sb-datom "sb-t1" :ticket/title "Add storage backend")
               (sb-datom "sb-t1" :ticket/status :ai-ready)
               (sb-datom "sb-t2" :entity/type :sb-ticket)
               (sb-datom "sb-t2" :ticket/title "Wire the deliberation gate")
               (sb-datom "sb-t2" :ticket/status :backlog)
               (sb-datom "sb-t3" :entity/type :sb-ticket)
               (sb-datom "sb-t3" :ticket/title "Provenance queries")
               (sb-datom "sb-t3" :ticket/status :done)))
  (let ((d (create-decision "sb-d1" "Which storage backend: sqlite, lmdb, or postgres?" "sb-t1")))
    (add-decision-input d "alice" "lmdb")
    (add-decision-input d "bob" "postgres")
    (add-decision-input d "carol" "lmdb")
    (resolve-decision* d "lead" "lmdb"))
  :seeded)

;;; ── REST dispatch: /api/sb/* ─────────────────────────────────────
(defun rest-handle-sb (request)
  "Dispatch /api/sb/* requests (board, decisions, why, seed)."
  (let ((method (hunchentoot:request-method request))
        (uri (hunchentoot:request-uri request)))
    (let ((qpos (position #\? uri))) (when qpos (setf uri (subseq uri 0 qpos))))
    (cond
      ;; GET /api/sb/board
      ((and (eq method :get) (string= uri "/api/sb/board"))
       (require-permission :read)
       (json-ok (board-alist)))

      ;; POST /api/sb/board/claim   {from, to}
      ((and (eq method :post) (string= uri "/api/sb/board/claim"))
       (require-permission :write)
       (let* ((body (parse-json-body))
              (from (sb-keyword (or (cdr (assoc :from body)) "ai-ready")))
              (to (sb-keyword (or (cdr (assoc :to body)) "in-progress")))
              (claimed (claim-next from to)))
         (when claimed (sse-broadcast "sb_board_changed" (board-alist)))
         (json-ok `((:claimed . ,claimed)))))

      ;; POST /api/sb/board/:ticket/move   {to}
      ((and (eq method :post)
            (> (length uri) 14) (string= "/api/sb/board/" (subseq uri 0 14))
            (let ((rest (subseq uri 14))) (search "/move" rest)))
       (require-permission :write)
       (let* ((rest (subseq uri 14))
              (ticket (subseq rest 0 (search "/move" rest)))
              (body (parse-json-body))
              (to (sb-keyword (cdr (assoc :to body)))))
         (if (and ticket to)
             (progn (move-ticket ticket to)
                    (sse-broadcast "sb_board_changed" (board-alist))
                    (json-ok `((:id . ,ticket) (:status . ,(string-downcase (princ-to-string to))))))
             (json-error "ticket and 'to' required"))))

      ;; GET /api/sb/decisions
      ((and (eq method :get) (string= uri "/api/sb/decisions"))
       (require-permission :read)
       (json-ok (or (all-decisions) #())))

      ;; POST /api/sb/decisions   {name, question, ticket?}
      ((and (eq method :post) (string= uri "/api/sb/decisions"))
       (require-permission :write)
       (let* ((body (parse-json-body))
              (name (cdr (assoc :name body)))
              (question (cdr (assoc :question body)))
              (ticket (cdr (assoc :ticket body))))
         (if (and name question)
             (let ((d (create-decision name question ticket)))
               (sse-broadcast "sb_decision_changed" (decision-alist d))
               (json-ok (decision-alist d) :status 201))
             (json-error "name and question required"))))

      ;; GET /api/sb/decisions/:id
      ((and (eq method :get)
            (> (length uri) 18) (string= "/api/sb/decisions/" (subseq uri 0 18))
            (not (search "/" (subseq uri 18))))
       (require-permission :read)
       (json-ok (decision-alist (autopoiesis.substrate:intern-id (subseq uri 18)))))

      ;; POST /api/sb/decisions/:id/input   {user, text}
      ((and (eq method :post)
            (> (length uri) 18) (string= "/api/sb/decisions/" (subseq uri 0 18))
            (let ((rest (subseq uri 18))) (search "/input" rest)))
       (require-permission :write)
       (let* ((rest (subseq uri 18))
              (id (subseq rest 0 (search "/input" rest)))
              (body (parse-json-body))
              (user (cdr (assoc :user body)))
              (text (cdr (assoc :text body)))
              (d (autopoiesis.substrate:intern-id id)))
         (if (and user text)
             (progn (add-decision-input d user text)
                    (sse-broadcast "sb_decision_changed" (decision-alist d))
                    (json-ok (decision-alist d)))
             (json-error "user and text required"))))

      ;; POST /api/sb/decisions/:id/resolve   {lead, resolution}
      ((and (eq method :post)
            (> (length uri) 18) (string= "/api/sb/decisions/" (subseq uri 0 18))
            (let ((rest (subseq uri 18))) (search "/resolve" rest)))
       (require-permission :write)
       (let* ((rest (subseq uri 18))
              (id (subseq rest 0 (search "/resolve" rest)))
              (body (parse-json-body))
              (lead (or (cdr (assoc :lead body)) "lead"))
              (resolution (cdr (assoc :resolution body)))
              (d (autopoiesis.substrate:intern-id id)))
         (if resolution
             (progn (resolve-decision* d lead resolution)
                    (sse-broadcast "sb_decision_changed" (decision-alist d))
                    (json-ok (decision-alist d)))
             (json-error "resolution required"))))

      ;; GET /api/sb/why
      ((and (eq method :get) (string= uri "/api/sb/why"))
       (require-permission :read)
       (json-ok (or (why-report) #())))

      ;; POST /api/sb/seed
      ((and (eq method :post) (string= uri "/api/sb/seed"))
       (require-permission :write)
       (seed-sb-demo)
       (sse-broadcast "sb_board_changed" (board-alist))
       (json-ok `((:seeded . t))))

      (t (json-not-found "SB route" uri)))))
