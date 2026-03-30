;;;; rules.lisp - Named Datalog rule store for the substrate
;;;;
;;;; Provides a persistent registry of named Datalog rules that
;;;; can be used with the `q` query function. Rules are stored as
;;;; S-expression data and can be serialized for persistence.
;;;;
;;;; Also provides conversion from the Shen Prolog rule format
;;;; (used by packages/shen/) to the substrate Datalog format.
;;;;
;;;; Usage:
;;;;   (define-datalog-rule :ancestor
;;;;     '(((ancestor ?x ?y) (?x :parent ?y))
;;;;       ((ancestor ?x ?y) (?x :parent ?mid) (ancestor ?mid ?y))))
;;;;
;;;;   (with-store ()
;;;;     (q '(:find ?anc :in % :where (ancestor 10 ?anc))
;;;;        (all-rules-for-query)))

(in-package #:autopoiesis.substrate)

;;; ===================================================================
;;; Rule Store
;;; ===================================================================

(defvar *datalog-rules* (make-hash-table :test 'eq)
  "Registry of named Datalog rules. Keyword name → list of rule clauses.
   Each clause is: ((head ?a ?b) (body-clause1) (body-clause2) ...)")

(defun define-datalog-rule (name clauses)
  "Define a named Datalog rule. NAME is a keyword. CLAUSES is a list
   of rule clauses in substrate Datalog format:
     (((pred ?a ?b) (?a :attr ?b) ...)   ; clause with datom body
      ((pred ?a ?b) (other-rule ?a ?b)))  ; clause invoking another rule

   Idempotent — redefining replaces the previous definition."
  (check-type name keyword)
  (check-type clauses list)
  (setf (gethash name *datalog-rules*) clauses)
  name)

(defun remove-datalog-rule (name)
  "Remove a named Datalog rule."
  (remhash name *datalog-rules*)
  name)

(defun list-datalog-rules ()
  "Return a list of all defined rule names."
  (let ((names nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             *datalog-rules*)
    (nreverse names)))

(defun clear-datalog-rules ()
  "Remove all rules."
  (clrhash *datalog-rules*))

(defun all-rules-for-query ()
  "Collect all registered rules into the flat list format that `q` expects.
   Returns: (((name ?a ?b) clause1 ...) ((name2 ?x) clause2 ...) ...)"
  (let ((rules nil))
    (maphash (lambda (name clauses)
               (declare (ignore name))
               (dolist (c clauses) (push c rules)))
             *datalog-rules*)
    (nreverse rules)))

;;; ===================================================================
;;; Query with registered rules
;;; ===================================================================

(defun q-rules (query-form &rest args)
  "Like `q` but automatically includes all registered Datalog rules.
   If the query already specifies :in %, the registered rules are
   prepended. Otherwise, :in % is injected.

   Usage:
     (define-datalog-rule :ancestor ...)
     (q-rules '(:find ?anc :where (ancestor 10 ?anc)))"
  (let ((rules (all-rules-for-query)))
    (if (null rules)
        ;; No rules registered — just run as normal query
        (apply #'q query-form args)
        ;; Inject rules
        (apply #'q query-form rules args))))

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defun datalog-rules-to-sexpr ()
  "Serialize the rule store to an S-expression for persistence.
   Returns: ((:name . (clause1 clause2 ...)) ...)"
  (let ((result nil))
    (maphash (lambda (name clauses)
               (push (cons name clauses) result))
             *datalog-rules*)
    (nreverse result)))

(defun sexpr-to-datalog-rules (sexpr)
  "Load rules from a serialized S-expression.
   Merges with existing rules (overwrites on name collision)."
  (dolist (entry sexpr)
    (define-datalog-rule (car entry) (cdr entry))))

;;; ===================================================================
;;; Shen Format Conversion
;;; ===================================================================

(defun convert-shen-rules-to-datalog (shen-clauses)
  "Convert rules from Shen Prolog format to substrate Datalog format.

   Shen format:  ((pred X Y) <-- (goal1 X) (goal2 Y))
   Datalog format: ((pred ?x ?y) (goal1 ?x) (goal2 ?y))

   Handles both single clauses (flat list with <--) and
   multiple clauses (list of lists each containing <--)."
  (let ((normalized (if (find-if (lambda (x)
                                   (and (symbolp x)
                                        (string= (symbol-name x) "<--")))
                                 shen-clauses)
                        (list shen-clauses)  ; single clause → wrap
                        shen-clauses)))      ; already list of clauses
    (mapcar #'convert-one-shen-clause normalized)))

(defun convert-one-shen-clause (clause)
  "Convert one Shen-format clause to Datalog format.
   ((pred X Y) <-- (goal1 X) (goal2 Y))
   → ((pred ?x ?y) (goal1 ?x) (goal2 ?y))"
  (let ((head-terms nil)
        (body-terms nil)
        (seen-arrow nil))
    ;; Split at <--
    (dolist (item clause)
      (cond
        ((and (symbolp item) (string= (symbol-name item) "<--"))
         (setf seen-arrow t))
        (seen-arrow (push item body-terms))
        (t (push item head-terms))))
    (setf head-terms (nreverse head-terms))
    (setf body-terms (nreverse body-terms))
    ;; Build Datalog clause: (head goal1 goal2 ...)
    (let* ((head-form (if (and (= 1 (length head-terms))
                               (listp (first head-terms)))
                          (first head-terms)     ; ((pred X Y)) → (pred X Y)
                          head-terms))           ; already flat
           (dl-head (convert-term-list head-form))
           (dl-body (mapcar (lambda (goal)
                              (if (listp goal)
                                  (convert-term-list goal)
                                  (list (shen-term-to-datalog goal))))
                            body-terms)))
      (cons dl-head dl-body))))

(defun convert-term-list (terms)
  "Convert a list of terms where the first is a predicate name and the rest are args.
   (ANCESTOR X Y) → (ancestor ?x ?y)"
  (if (null terms)
      nil
      (cons (let ((pred (first terms)))
              ;; First element is always a predicate name, not a variable
              (if (symbolp pred)
                  (intern (string-downcase (symbol-name pred)))
                  pred))
            (mapcar #'shen-term-to-datalog (rest terms)))))

(defun shen-term-to-datalog (term)
  "Convert a Shen Prolog term to Datalog convention.
   Uppercase symbols (X, Y, TREE) → ?x, ?y, ?tree (Datalog variables)
   Wildcard _ → fresh gensym ?-variable
   Keywords and strings pass through unchanged."
  (cond
    ((not (symbolp term)) term)
    ((keywordp term) term)
    ((string= (symbol-name term) "_")
     (intern (format nil "?~A" (gensym "WILD")) :keyword))
    ((and (> (length (symbol-name term)) 0)
          (every #'upper-case-p
                 (remove-if-not #'alpha-char-p (symbol-name term))))
     (intern (format nil "?~A" (string-downcase (symbol-name term)))))
    (t term)))

;;; ===================================================================
;;; Built-in Rules
;;; ===================================================================

(defun register-builtin-rules ()
  "Register useful default Datalog rules for common graph traversals.
   Call this after system initialization."

  ;; Snapshot ancestry (replaces snapshot-ancestors, walk-ancestors-paginated)
  (define-datalog-rule :snapshot-ancestor
    '(((snapshot-ancestor ?x ?y) (?x :snapshot/parent ?y))
      ((snapshot-ancestor ?x ?y) (?x :snapshot/parent ?mid)
                                  (snapshot-ancestor ?mid ?y))))

  ;; Snapshot descendant
  (define-datalog-rule :snapshot-descendant
    '(((snapshot-descendant ?parent ?child) (?child :snapshot/parent ?parent))
      ((snapshot-descendant ?parent ?child) (?mid :snapshot/parent ?parent)
                                             (snapshot-descendant ?mid ?child))))

  ;; Agent lineage
  (define-datalog-rule :agent-descendant
    '(((agent-descendant ?parent ?child) (?child :agent/parent ?parent))
      ((agent-descendant ?parent ?child) (?mid :agent/parent ?parent)
                                          (agent-descendant ?mid ?child)))))
