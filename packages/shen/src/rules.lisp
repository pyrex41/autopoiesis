;;;; rules.lisp - Rule storage, compilation, and querying
;;;;
;;;; Rules are S-expressions that map to Shen Prolog predicates.
;;;; They're stored as data (surviving serialization, forking, and
;;;; time-travel) and compiled into Shen on demand.
;;;;
;;;; Rule format (AP S-expression):
;;;;   (:name :file-valid
;;;;    :clauses ((file-valid Tree)
;;;;              <-- (has-file Tree "src/main.py")
;;;;                  (has-file Tree "README.md")))
;;;;
;;;; This compiles to Shen:
;;;;   (defprolog file-valid
;;;;     Tree <-- (has-file Tree "src/main.py")
;;;;              (has-file Tree "README.md");)

(in-package #:autopoiesis.shen)

;;; ===================================================================
;;; Rule Store
;;; ===================================================================

(defvar *rule-store* (make-hash-table :test 'eq)
  "Global registry of Prolog rules. Keyword name → list of clause S-expressions.
   NOTE: This is process-global. When multiple agents use Shen reasoning,
   load-agent-knowledge clears and reloads per agent under *shen-lock*.")

(defvar *compiled-rules* (make-hash-table :test 'eq)
  "Tracks which rules have been compiled into the current Shen session.")

;;; ===================================================================
;;; Rule Definition
;;; ===================================================================

(defun define-rule (name clauses)
  "Define a Prolog rule by name. Stores as data and compiles into Shen if available.
   NAME is a keyword. CLAUSES is a list of clause S-expressions.
   Idempotent — redefining replaces the previous definition.

   Example:
     (define-rule :member
       '((mem X [X | _] <--)
         (mem X [_ | Y] <-- (mem X Y))))"
  (check-type name keyword)
  (check-type clauses list)
  (setf (gethash name *rule-store*) clauses)
  ;; Compile into Shen if loaded
  (when (shen-available-p)
    (compile-rule-into-shen name clauses))
  name)

(defun remove-rule (name)
  "Remove a rule from the store."
  (remhash name *rule-store*)
  (remhash name *compiled-rules*)
  name)

(defun list-rules ()
  "Return a list of all defined rule names."
  (let ((names nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             *rule-store*)
    (nreverse names)))

(defun clear-rules ()
  "Remove all rules from the store."
  (clrhash *rule-store*)
  (clrhash *compiled-rules*))

;;; ===================================================================
;;; Rule Compilation (AP S-expr → Shen defprolog)
;;; ===================================================================

(defun compile-rule-into-shen (name clauses)
  "Compile a rule's clauses into Shen Prolog via shen.s-prolog.
   Converts AP clause S-expressions to the format expected by
   Shen's internal prolog compiler. Marks as compiled on success."
  (handler-case
      (let ((s-prolog-fn (find-symbol "shen.s-prolog" :shen)))
        (unless (and s-prolog-fn (fboundp s-prolog-fn))
          (error "shen.s-prolog not available"))
        (let ((shen-clauses (clauses-to-shen-internal name clauses)))
          (funcall s-prolog-fn shen-clauses)
          (setf (gethash name *compiled-rules*) t)))
    (error (e)
      (warn "Failed to compile rule ~A into Shen: ~A" name e))))

(defun clauses-to-shen-internal (name clauses)
  "Convert AP rule clauses to the internal format for shen.s-prolog.
   Each AP clause: ((pred args...) <-- body-goal1 body-goal2 ...)
   Becomes:        ((shen-pred args...) - (body-goals...))

   The result is a list of (HEAD - BODY) triples for shen.s-prolog."
  (let* ((pred-sym (intern (string-downcase (symbol-name name)) :shen))
         ;; Normalize: if <-- appears as a direct element, it's a single clause
         ;; Use string= for <-- comparison since it may be in different packages
         (normalized (if (find '<-- clauses :test #'arrow-symbol-p)
                         (list clauses)
                         clauses)))
    (mapcar (lambda (clause)
              (split-clause-for-shen pred-sym clause))
            normalized)))

(defun arrow-symbol-p (a b)
  "Check if two symbols both represent <-- (may be in different packages)."
  (and (symbolp a) (symbolp b)
       (string= (symbol-name a) (symbol-name b))))

(defun split-clause-for-shen (pred-sym clause)
  "Split a single AP clause at <-- and convert to (HEAD - BODY) for shen.s-prolog."
  (let ((head-terms nil)
        (body-terms nil)
        (seen-arrow nil))
    ;; Walk the clause, splitting at <-- (use string= for cross-package compat)
    (dolist (item clause)
      (cond
        ((and (symbolp item) (string= (symbol-name item) "<--"))
         (setf seen-arrow t))
        (seen-arrow (push item body-terms))
        (t (push item head-terms))))
    (setf head-terms (nreverse head-terms))
    (setf body-terms (nreverse body-terms))
    ;; Build head: if single compound form like ((pred X Y)), extract args
    (let* ((head-form (if (and (= 1 (length head-terms))
                               (listp (first head-terms)))
                          (first head-terms)
                          head-terms))
           (shen-head (cons pred-sym
                            (mapcar #'intern-shen-term (rest head-form))))
           (shen-body (mapcar (lambda (goal)
                                (if (listp goal)
                                    (mapcar #'intern-shen-term goal)
                                    (list (intern-shen-term goal))))
                              body-terms)))
      (list shen-head '- shen-body))))

(defun intern-shen-term (term)
  "Intern a term for Shen Prolog. Symbols go to :SHEN package,
   strings and numbers stay as-is. Uppercase symbols are Prolog variables."
  (cond
    ((null term) nil)
    ((stringp term) term)
    ((numberp term) term)
    ((keywordp term) (intern (string-downcase (symbol-name term)) :shen))
    ((symbolp term)
     (let ((name (symbol-name term)))
       (cond
         ((string= name "_") (intern "_"))
         ;; All-uppercase = Prolog variable (stays in CL-USER)
         ((and (> (length name) 0)
               (every #'upper-case-p (remove-if-not #'alpha-char-p name)))
          (intern name))
         ;; Everything else → SHEN package
         (t (intern (string-downcase name) :shen)))))
    ((listp term) (mapcar #'intern-shen-term term))
    (t term)))

(defun ensure-rule-compiled (name)
  "Ensure a rule is compiled into the current Shen session."
  (unless (gethash name *compiled-rules*)
    (let ((clauses (gethash name *rule-store*)))
      (when clauses
        (compile-rule-into-shen name clauses)))))

(defun format-defprolog-string (name clauses)
  "Format AP rule clauses as a Shen defprolog source string.
   Shen Prolog syntax: (defprolog name Head <-- Body1 Body2 ;)
   Each clause ends with ; and the whole form is wrapped in parens.

   NAME is a keyword. CLAUSES is the AP S-expression clause list.
   Clauses can be flat lists like: ((fact 42) <--)
   or with body goals: ((head X Y) <-- (goal1 X) (goal2 Y))"
  (let ((shen-name (string-downcase (symbol-name name))))
    (with-output-to-string (s)
      (format s "(defprolog ~A" shen-name)
      (dolist (clause clauses)
        (format s "~%  ")
        (if (listp clause)
            ;; Clause is a list of terms
            (dolist (term clause)
              (format s "~A " (format-shen-term term)))
            ;; Clause is an atom (e.g., <--)
            (format s "~A " (format-shen-term clause))))
      (format s ";)"))))

(defun format-shen-term (term)
  "Format a single term for Shen Prolog source.
   Strings stay quoted, uppercase symbols are Prolog variables,
   other symbols are lowercased predicates."
  (cond
    ((null term) "[]")
    ((eq term '<--) "<--")
    ((stringp term) (format nil "~S" term))
    ((keywordp term) (string-downcase (symbol-name term)))
    ((symbolp term)
     (let ((name (symbol-name term)))
       (cond
         ;; Single uppercase letter or all-uppercase = Prolog variable
         ((and (> (length name) 0)
               (every #'upper-case-p (remove-if-not #'alpha-char-p name))
               (not (string= name "<--")))
          name)
         ;; Special operators
         ((member name '("_" "<--") :test #'string=) name)
         ;; Everything else lowercased
         (t (string-downcase name)))))
    ((listp term)
     (format nil "(~{~A~^ ~})" (mapcar #'format-shen-term term)))
    (t (format nil "~A" term))))

(defun clauses-to-defprolog (name clauses)
  "Convert AP rule clauses to a Shen defprolog S-expression.
   NAME is a keyword (converted to a Shen symbol).
   CLAUSES is the list of clause forms.
   NOTE: This produces an S-expression form. For actual Shen evaluation,
   use format-defprolog-string + shen-eval-string instead."
  (let ((shen-name (rule-name-to-shen name)))
    `(defprolog ,shen-name ,@clauses)))

(defun rule-name-to-shen (name)
  "Convert a keyword rule name to a Shen-compatible symbol.
   :file-valid → file-valid (interned in :SHEN if available)"
  (let ((str (string-downcase (symbol-name name))))
    (if (find-package :shen)
        (intern str :shen)
        (intern str))))

;;; ===================================================================
;;; Rule Querying
;;; ===================================================================

(defun query-rules (name &key tree output exit-code context)
  "Query a named rule with the given context.
   Returns the query result or NIL if the query fails.
   Use :context for raw argument lists, or :tree/:output/:exit-code
   for structured eval context.

   Example:
     (query-rules :member :context '(1 (1 2 3))) → T"
  (unless (shen-available-p)
    (error "Shen is not loaded. Call (ensure-shen-loaded) first."))
  (ensure-rule-compiled name)
  (let* ((shen-name (rule-name-to-shen name))
         (raw-args (or context
                       (remove nil (list tree output exit-code))))
         ;; Intern args for Shen Prolog
         (shen-args (mapcar #'intern-shen-term raw-args)))
    (shen-query `((,shen-name ,@shen-args)))))

;;; ===================================================================
;;; Serialization (for substrate datoms / persistent agent metadata)
;;; ===================================================================

(defun rules-to-sexpr ()
  "Serialize the entire rule store to an S-expression.
   Returns a list of (name . clauses) pairs."
  (let ((result nil))
    (maphash (lambda (name clauses)
               (push (cons name clauses) result))
             *rule-store*)
    (nreverse result)))

(defun sexpr-to-rules (sexpr)
  "Load rules from a serialized S-expression (list of (name . clauses) pairs).
   Merges with existing rules (overwrites on name collision)."
  (dolist (entry sexpr)
    (define-rule (car entry) (cdr entry))))

(defun load-rules-from-pmap (pmap)
  "Load rules stored in a persistent agent metadata pmap under :shen-rules."
  (let* ((pkg (find-package :autopoiesis.core))
         (get-fn (when pkg (find-symbol "PMAP-GET" pkg)))
         (rules-data (when (and get-fn (fboundp get-fn))
                       (funcall get-fn pmap :shen-rules))))
    (when rules-data
      (sexpr-to-rules rules-data))))
