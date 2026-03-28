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
  "Registry of Prolog rules. Keyword name → list of clause S-expressions.")

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
  "Compile a rule's clauses into a Shen defprolog form and evaluate it.
   Marks the rule as compiled."
  (handler-case
      (let ((shen-form (clauses-to-defprolog name clauses)))
        (shen-eval shen-form)
        (setf (gethash name *compiled-rules*) t))
    (error (e)
      (warn "Failed to compile rule ~A into Shen: ~A" name e))))

(defun ensure-rule-compiled (name)
  "Ensure a rule is compiled into the current Shen session."
  (unless (gethash name *compiled-rules*)
    (let ((clauses (gethash name *rule-store*)))
      (when clauses
        (compile-rule-into-shen name clauses)))))

(defun clauses-to-defprolog (name clauses)
  "Convert AP rule clauses to a Shen defprolog S-expression.
   NAME is a keyword (converted to a Shen symbol).
   CLAUSES is the list of clause forms."
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

(defun query-rules (name &rest args)
  "Query a named rule with the given arguments.
   Returns the query result or NIL if the query fails.

   Example:
     (query-rules :member 1 '(1 2 3)) → T"
  (unless (shen-available-p)
    (error "Shen is not loaded. Call (ensure-shen-loaded) first."))
  (ensure-rule-compiled name)
  (let ((shen-name (rule-name-to-shen name)))
    (shen-query `((,shen-name ,@args)))))

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
