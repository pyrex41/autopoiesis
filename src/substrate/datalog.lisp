;;;; datalog.lisp - Datalog query language for the substrate
;;;;
;;;; Provides interpreted `query` and compiled `compile-query` for
;;;; pattern matching over datoms. Supports variable binding, joins,
;;;; and negation.
;;;;
;;;; Usage:
;;;;   (query '((?e :agent/status :running) (?e :agent/name ?name)))
;;;;   => ((:?e 42 :?name "researcher") ...)
;;;;
;;;;   (compile-query running-agents
;;;;     ((?e :agent/status :running) (?e :agent/name ?name)))
;;;;   => defines function RUNNING-AGENTS

(in-package #:autopoiesis.substrate)

;;; ===================================================================
;;; Variable handling
;;; ===================================================================

(defun variable-p (x)
  "A query variable starts with ?."
  (and (symbolp x)
       (char= #\? (char (symbol-name x) 0))))

(defun variable-key (var)
  "Convert a variable symbol to a keyword for binding maps.
   ?e -> :?E, ?name -> :?NAME"
  (intern (symbol-name var) :keyword))

;;; ===================================================================
;;; Clause execution
;;; ===================================================================

(defun execute-clause (clause bindings)
  "Execute a single pattern clause against the store.
   CLAUSE is (?entity attribute value) where any element can be a variable.
   BINDINGS is a list of binding alists from previous clauses.
   Returns a new list of extended binding alists."
  (destructuring-bind (e-pat a-pat v-pat) clause
    (if (null bindings)
        ;; First clause: generate initial bindings
        (generate-initial-bindings e-pat a-pat v-pat)
        ;; Join clause: extend existing bindings
        (loop for binding in bindings
              nconc (extend-binding binding e-pat a-pat v-pat)))))

(defun generate-initial-bindings (e-pat a-pat v-pat)
  "Generate bindings for the first clause by scanning the entity cache."
  (let ((cache (get-entity-cache))
        (intern-tbl (get-intern-table))
        (results nil))
    ;; Determine if we can use value index for fast lookup
    (cond
      ;; Both attribute and value are concrete -> use find-entities
      ((and (not (variable-p a-pat)) (not (variable-p v-pat)))
       (let* ((aid (if (integerp a-pat) a-pat (gethash a-pat intern-tbl)))
              (eids (when aid (find-entities a-pat v-pat))))
         (dolist (eid eids)
           (let ((binding nil))
             (when (variable-p e-pat)
               (push (cons (variable-key e-pat) eid) binding))
             (push binding results)))))
      ;; Attribute is concrete, value is variable -> scan entity cache
      ((and (not (variable-p a-pat)) (variable-p v-pat))
       (let ((aid (if (integerp a-pat) a-pat (gethash a-pat intern-tbl))))
         (when aid
           (maphash (lambda (key value)
                      (when (= (cdr key) aid)
                        (let ((eid (car key))
                              (binding nil)
                              (match t))
                          ;; Check entity pattern
                          (cond
                            ((variable-p e-pat)
                             (push (cons (variable-key e-pat) eid) binding))
                            ((not (eql eid (if (integerp e-pat) e-pat
                                               (gethash e-pat intern-tbl))))
                             (setf match nil)))
                          (when match
                            (push (cons (variable-key v-pat) value) binding)
                            (push binding results)))))
                    cache))))
      ;; Full scan: all patterns have variables
      (t
       (maphash (lambda (key value)
                  (let ((eid (car key))
                        (aid (cdr key))
                        (binding nil)
                        (match t))
                    ;; Check entity
                    (cond
                      ((variable-p e-pat)
                       (push (cons (variable-key e-pat) eid) binding))
                      (t (let ((expected (if (integerp e-pat) e-pat
                                             (gethash e-pat intern-tbl))))
                           (unless (eql eid expected) (setf match nil)))))
                    ;; Check attribute
                    (when match
                      (cond
                        ((variable-p a-pat)
                         (push (cons (variable-key a-pat) aid) binding))
                        (t (let ((expected (if (integerp a-pat) a-pat
                                               (gethash a-pat intern-tbl))))
                             (unless (eql aid expected) (setf match nil))))))
                    ;; Check value
                    (when match
                      (cond
                        ((variable-p v-pat)
                         (push (cons (variable-key v-pat) value) binding))
                        (t (unless (equal value v-pat) (setf match nil)))))
                    (when match
                      (push binding results))))
                cache)))
    results))

(defun extend-binding (binding e-pat a-pat v-pat)
  "Try to extend BINDING with a new clause. Returns list of extended bindings."
  (let* ((cache (get-entity-cache))
         (intern-tbl (get-intern-table))
         ;; Resolve patterns against existing binding
         (e-resolved (resolve-pattern e-pat binding intern-tbl))
         (a-resolved (resolve-pattern a-pat binding intern-tbl))
         (v-resolved (resolve-pattern v-pat binding intern-tbl))
         (results nil))
    (cond
      ;; Both entity and attribute resolved -> direct lookup
      ((and (integerp e-resolved) (integerp a-resolved))
       (multiple-value-bind (value found-p)
           (gethash (cons e-resolved a-resolved) cache)
         (when found-p
           (cond
             ;; Value is a variable -> bind it
             ((and (variable-p v-pat) (not (assoc (variable-key v-pat) binding)))
              (push (list* (cons (variable-key v-pat) value) binding) results))
             ;; Value already bound -> check match
             ((integerp v-resolved)
              (when (equal value v-resolved) (push binding results)))
             ((and v-resolved (not (variable-p v-pat)))
              (when (equal value v-resolved) (push binding results)))
             ;; Value is concrete literal
             ((not (variable-p v-pat))
              (when (equal value v-pat) (push binding results)))
             ;; Variable already bound in binding -> check match
             (t
              (let ((existing (cdr (assoc (variable-key v-pat) binding))))
                (if existing
                    (when (equal value existing) (push binding results))
                    (push (list* (cons (variable-key v-pat) value) binding) results))))))))
      ;; Need to scan
      (t
       (maphash (lambda (key value)
                  (let ((eid (car key))
                        (aid (cdr key))
                        (new-binding (copy-alist binding))
                        (match t))
                    ;; Check entity
                    (cond
                      ((integerp e-resolved)
                       (unless (= eid e-resolved) (setf match nil)))
                      ((variable-p e-pat)
                       (let ((existing (cdr (assoc (variable-key e-pat) new-binding))))
                         (if existing
                             (unless (eql eid existing) (setf match nil))
                             (push (cons (variable-key e-pat) eid) new-binding)))))
                    ;; Check attribute
                    (when match
                      (cond
                        ((integerp a-resolved)
                         (unless (= aid a-resolved) (setf match nil)))
                        ((variable-p a-pat)
                         (let ((existing (cdr (assoc (variable-key a-pat) new-binding))))
                           (if existing
                               (unless (eql aid existing) (setf match nil))
                               (push (cons (variable-key a-pat) aid) new-binding))))))
                    ;; Check value
                    (when match
                      (cond
                        ((variable-p v-pat)
                         (let ((existing (cdr (assoc (variable-key v-pat) new-binding))))
                           (if existing
                               (unless (equal value existing) (setf match nil))
                               (push (cons (variable-key v-pat) value) new-binding))))
                        (v-resolved
                         (unless (equal value v-resolved) (setf match nil)))
                        (t
                         (unless (equal value v-pat) (setf match nil)))))
                    (when match
                      (push new-binding results))))
                cache)))
    results))

(defun resolve-pattern (pat binding intern-tbl)
  "Resolve a pattern element: if it's a bound variable, return its value.
   If it's a concrete term, intern it. If unbound variable, return it as-is."
  (cond
    ((variable-p pat)
     (let ((val (cdr (assoc (variable-key pat) binding))))
       (or val pat)))
    ((integerp pat) pat)
    (t (gethash pat intern-tbl))))

;;; ===================================================================
;;; Negation
;;; ===================================================================

(defun execute-negation (clause bindings)
  "Filter bindings by removing those that match the negated clause.
   (not (?e :attr :val)) removes bindings where the pattern matches."
  (remove-if (lambda (binding)
               (let ((results (extend-binding binding
                                              (first clause)
                                              (second clause)
                                              (third clause))))
                 (not (null results))))
             bindings))

;;; ===================================================================
;;; Interpreted query
;;; ===================================================================

(defun query (clauses)
  "Execute a Datalog query. Returns list of binding alists.
   CLAUSES is a list of (?entity attribute value) patterns.
   Variables (symbols starting with ?) are bound across clauses.
   Negation via (not (?e :attr :val)).

   Example:
     (query '((?e :agent/status :running) (?e :agent/name ?name)))
     => ((:?E . 42) (:?NAME . \"researcher\")) ...)"
  (let ((bindings nil))
    (dolist (clause clauses)
      (cond
        ;; Negation clause
        ((and (listp clause) (eq (car clause) 'not))
         (setf bindings (execute-negation (cadr clause) bindings)))
        ;; Normal clause
        (t
         (setf bindings (execute-clause clause bindings)))))
    bindings))

;;; ===================================================================
;;; Compiled query
;;; ===================================================================

(defmacro compile-query (name clauses)
  "Compile a Datalog query into a named function.
   The function takes no arguments and returns binding alists.

   Example:
     (compile-query running-agents
       ((?e :agent/status :running) (?e :agent/name ?name)))
     ;; Defines function RUNNING-AGENTS"
  `(defun ,name ()
     ,(format nil "Compiled Datalog query: ~S" clauses)
     (query ',clauses)))
