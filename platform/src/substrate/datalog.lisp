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
         (e-raw (resolve-pattern e-pat binding intern-tbl))
         (a-raw (resolve-pattern a-pat binding intern-tbl))
         (v-resolved (resolve-pattern v-pat binding intern-tbl))
         ;; For entity/attribute positions, ensure integer IDs
         (e-resolved (if (integerp e-raw) e-raw (%resolve-as-eid e-raw intern-tbl)))
         (a-resolved (if (integerp a-raw) a-raw (%resolve-as-eid a-raw intern-tbl)))
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

(defun %resolve-as-eid (resolved intern-tbl)
  "Ensure RESOLVED is an integer entity/attribute ID.
   If RESOLVED is a symbol (e.g. from :in param), try interning it."
  (cond
    ((integerp resolved) resolved)
    ((symbolp resolved) (gethash resolved intern-tbl))
    (t nil)))

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

;;; ===================================================================
;;; Pull API (Datomic-style entity reads)
;;; ===================================================================

(defun pull (entity-id pattern)
  "Pull specific attributes from an entity, returning a plist.
   ENTITY-ID is a name or integer EID.
   PATTERN is a list of attribute keywords, or '(*) for all.

   Examples:
     (pull :agent-1 '(:agent/status :agent/name))
     => (:agent/status :running :agent/name \"scout\")

     (pull :agent-1 '(*))
     => (:agent/status :running :agent/name \"scout\" :entity/type :agent)"
  (if (and pattern (eq (car pattern) '*))
      ;; Wildcard: delegate to entity-state
      (entity-state entity-id)
      ;; Specific attributes: O(N) direct lookups
      (let* ((cache (get-entity-cache))
             (intern-tbl (get-intern-table))
             (eid (if (integerp entity-id) entity-id
                      (gethash entity-id intern-tbl)))
             (result nil))
        (when eid
          (dolist (attr (reverse pattern))
            (let ((aid (if (integerp attr) attr
                           (gethash attr intern-tbl))))
              (when aid
                (multiple-value-bind (value found-p)
                    (gethash (cons eid aid) cache)
                  (when found-p
                    (push value result)
                    (push attr result)))))))
        result)))

(defun pull-many (entity-ids pattern)
  "Pull the same PATTERN from multiple entities.
   Returns a list of plists (one per entity).

   Example:
     (pull-many '(:a1 :a2) '(:agent/status :agent/name))
     => ((:agent/status :running :agent/name \"scout\")
         (:agent/status :paused :agent/name \"analyst\"))"
  (mapcar (lambda (eid) (pull eid pattern)) entity-ids))

;;; ===================================================================
;;; Datomic-style q function
;;; ===================================================================

(defun %parse-query (form)
  "Parse a Datomic-style query form into components.
   Returns (values find-spec in-vars where-clauses rules-var).

   Form: (:find <spec> [:in <vars>] :where <clauses>)"
  (let ((find-spec nil)
        (in-vars nil)
        (where-clauses nil)
        (rules-var nil)
        (section nil))
    (dolist (elem form)
      (cond
        ((eq elem :find) (setf section :find))
        ((eq elem :in) (setf section :in))
        ((eq elem :where) (setf section :where))
        (t (ecase section
             (:find (push elem find-spec))
             (:in (if (eq elem '%)
                      (setf rules-var t)
                      (push elem in-vars)))
             (:where (push elem where-clauses))))))
    (values (nreverse find-spec)
            (nreverse in-vars)
            (nreverse where-clauses)
            rules-var)))

(defun %dot-p (sym)
  "Check if SYM is the dot marker (symbol named \".\")."
  (and (symbolp sym) (string= (symbol-name sym) ".")))

(defun %ellipsis-p (sym)
  "Check if SYM is the ellipsis marker (symbol named \"...\")."
  (and (symbolp sym) (string= (symbol-name sym) "...")))

(defun %project-bindings (bindings find-spec)
  "Project raw binding alists according to a :find spec.
   Four modes (following Datomic):
   - Relation (default): (:find ?a ?b) => ((v1 v2) (v3 v4) ...)
   - Scalar:             (:find ?a .) => v1
   - Tuple:              (:find ?a ?b .) => (v1 v2)  -- first result only
   - Collection:         (:find [?a ...]) => (v1 v2 v3 ...)"
  (cond
    ;; Scalar: (:find ?var .)
    ((and (= (length find-spec) 2)
          (%dot-p (second find-spec)))
     (let ((var-key (variable-key (first find-spec))))
       (when bindings
         (cdr (assoc var-key (first bindings))))))
    ;; Collection: (:find (?var ...))
    ((and (= (length find-spec) 1)
          (listp (first find-spec))
          (>= (length (first find-spec)) 2)
          (%ellipsis-p (second (first find-spec))))
     (let ((var-key (variable-key (first (first find-spec)))))
       (mapcar (lambda (b) (cdr (assoc var-key b))) bindings)))
    ;; Tuple: last element is .
    ((and (>= (length find-spec) 2)
          (%dot-p (car (last find-spec))))
     (let ((vars (butlast find-spec)))
       (when bindings
         (let ((b (first bindings)))
           (mapcar (lambda (v) (cdr (assoc (variable-key v) b))) vars)))))
    ;; Relation (default)
    (t
     (mapcar (lambda (b)
               (mapcar (lambda (v) (cdr (assoc (variable-key v) b)))
                       find-spec))
             bindings))))

(defun %bind-in-params (in-vars args)
  "Create initial bindings from :in variables and their argument values.
   Returns a list containing one binding alist."
  (when in-vars
    (list (mapcar (lambda (var val)
                    (cons (variable-key var) val))
                  in-vars args))))

(defun q (query-form &rest args)
  "Datomic-style query with :find, :in, and :where clauses.

   Examples:
     ;; Relation (list of tuples)
     (q '(:find ?name ?status
          :where (?e :agent/status ?status)
                 (?e :agent/name ?name)))
     => ((\"scout\" :running) (\"analyst\" :paused))

     ;; Scalar (single value)
     (q '(:find ?name |.|
          :where (?e :agent/status :running)
                 (?e :agent/name ?name)))
     => \"scout\"

     ;; Collection (flat list)
     (q '(:find (?name ...)
          :where (?e :entity/type :agent)
                 (?e :agent/name ?name)))
     => (\"scout\" \"analyst\")

     ;; Parameterized
     (q '(:find ?name
          :in ?status
          :where (?e :agent/status ?status)
                 (?e :agent/name ?name))
        :running)
     => ((\"scout\") (\"analyst\"))

     ;; With rules
     (q '(:find ?ancestor
          :in % ?start
          :where (ancestor ?start ?ancestor))
        '(((ancestor ?t ?a) (?t :turn/parent ?a))
          ((ancestor ?t ?a) (?t :turn/parent ?mid) (ancestor ?mid ?a)))
        start-eid)
     => ((...) ...)"
  (multiple-value-bind (find-spec in-vars where-clauses rules-var)
      (%parse-query query-form)
    (let* ((rule-args (when rules-var args))
           (param-args (if rules-var (cdr args) args))
           (rules (when rules-var (first rule-args)))
           (initial-bindings (%bind-in-params in-vars param-args))
           (bindings (if initial-bindings initial-bindings nil)))
      ;; Execute where clauses
      (dolist (clause where-clauses)
        (cond
          ;; Negation
          ((and (listp clause) (eq (car clause) 'not))
           (setf bindings (execute-negation (cadr clause) bindings)))
          ;; Rule invocation: (rule-name ?arg1 ?arg2)
          ((and rules (listp clause) (symbolp (car clause))
                (not (variable-p (car clause)))
                (%find-rules (car clause) rules))
           (setf bindings (%execute-rule-clause clause bindings rules)))
          ;; Normal clause
          (t
           (setf bindings (execute-clause clause bindings)))))
      ;; Project
      (%project-bindings bindings find-spec))))

;;; ===================================================================
;;; Rules + recursive queries
;;; ===================================================================

(defun %find-rules (name rules)
  "Find all rule definitions matching NAME.
   Rules are: ((name ?a ?b) clause1 clause2 ...)"
  (remove-if-not (lambda (rule)
                   (eq (car (car rule)) name))
                 rules))

(defun %execute-rule-clause (clause bindings rules)
  "Execute a rule invocation against current bindings.
   CLAUSE is (rule-name ?arg1 ?arg2 ...).
   Returns extended bindings."
  (let ((rule-name (car clause))
        (call-args (cdr clause))
        (memo-table (make-hash-table :test 'equal))
        (results nil))
    (if (null bindings)
        ;; No prior bindings — generate from rule with empty binding
        (setf results (%evaluate-rule rule-name call-args nil rules
                                       memo-table (make-hash-table :test 'equal)))
        ;; Extend each existing binding through the rule
        (dolist (binding bindings)
          (let ((extended (%evaluate-rule rule-name call-args binding rules
                                          memo-table (make-hash-table :test 'equal))))
            (setf results (nconc results extended)))))
    results))

(defun %evaluate-rule (rule-name call-args binding rules memo-table visited)
  "Evaluate a rule, returning list of extended bindings.
   Uses MEMO-TABLE for memoization and VISITED for cycle detection."
  (let* ((matching-rules (%find-rules rule-name rules))
         (all-results nil))
    (dolist (rule matching-rules)
      (let* ((head (car rule))
             (head-args (cdr head))
             (body-clauses (cdr rule))
             ;; Bind call args to head args
             (rule-binding (copy-alist binding)))
        ;; Unify call-args with head-args
        (let ((unified t))
          (loop for call-arg in call-args
                for head-arg in head-args
                while unified
                do (cond
                     ;; Both variables — bind call-arg's value to head-arg
                     ((and (variable-p call-arg) (variable-p head-arg))
                      (let ((val (cdr (assoc (variable-key call-arg) rule-binding))))
                        (if val
                            (let ((existing (cdr (assoc (variable-key head-arg) rule-binding))))
                              (if existing
                                  (unless (equal val existing) (setf unified nil))
                                  (push (cons (variable-key head-arg) val) rule-binding)))
                            ;; call-arg unbound — just alias
                            (let ((existing (cdr (assoc (variable-key head-arg) rule-binding))))
                              (when existing
                                (push (cons (variable-key call-arg) existing) rule-binding))))))
                     ;; Call arg is variable, head is concrete
                     ((variable-p call-arg)
                      (let ((val (cdr (assoc (variable-key call-arg) rule-binding))))
                        (if val
                            (unless (equal val head-arg) (setf unified nil))
                            (push (cons (variable-key call-arg) head-arg) rule-binding))))
                     ;; Call arg is concrete, head is variable
                     ((variable-p head-arg)
                      (push (cons (variable-key head-arg) call-arg) rule-binding))
                     ;; Both concrete — must match
                     (t (unless (equal call-arg head-arg) (setf unified nil)))))
          (when unified
            ;; Check for cycles using a key based on rule + resolved args
            (let ((visit-key (list rule-name
                                   (mapcar (lambda (a)
                                             (if (variable-p a)
                                                 (cdr (assoc (variable-key a) rule-binding))
                                                 a))
                                           call-args))))
              (unless (gethash visit-key visited)
                (setf (gethash visit-key visited) t)
                ;; Execute body clauses
                (let ((body-bindings (list rule-binding)))
                  (dolist (bc body-clauses)
                    (when body-bindings
                      (cond
                        ;; Recursive rule call
                        ((and (listp bc) (symbolp (car bc))
                              (not (variable-p (car bc)))
                              (%find-rules (car bc) rules))
                         (let ((extended nil))
                           (dolist (bb body-bindings)
                             (setf extended
                                   (nconc extended
                                          (%evaluate-rule (car bc) (cdr bc) bb rules
                                                          memo-table visited))))
                           (setf body-bindings extended)))
                        ;; Negation in rule body
                        ((and (listp bc) (eq (car bc) 'not))
                         (setf body-bindings
                               (execute-negation (cadr bc) body-bindings)))
                        ;; Normal datom clause — use [] syntax: [?e :attr ?v]
                        ((and (listp bc) (>= (length bc) 3))
                         (setf body-bindings
                               (execute-clause bc body-bindings)))
                        (t (setf body-bindings nil)))))
                  ;; Map head-arg bindings back to call-arg bindings
                  (dolist (rb body-bindings)
                    (let ((result-binding (copy-alist binding)))
                      (loop for call-arg in call-args
                            for head-arg in head-args
                            do (when (variable-p call-arg)
                                 (let ((val (cdr (assoc (variable-key head-arg) rb))))
                                   (when val
                                     (unless (assoc (variable-key call-arg) result-binding)
                                       (push (cons (variable-key call-arg) val)
                                             result-binding))))))
                      (push result-binding all-results))))))))))
    all-results))
