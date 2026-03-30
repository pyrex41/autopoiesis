;;;; verifier.lisp - Prolog-based eval verifiers
;;;;
;;;; Registers :prolog-query and :prolog-check verifiers with the eval
;;;; system. Uses dynamic resolution (find-symbol) so the eval package
;;;; is not a compile-time dependency.
;;;;
;;;; :prolog-query — expected is a rule name (keyword) from *rule-store*
;;;; :prolog-check — expected is an inline Prolog expression (S-expression)

(in-package #:autopoiesis.shen)

;;; ===================================================================
;;; CL Helper Functions for Verification Predicates
;;; ===================================================================

(defun cl-tree-has-file (tree path)
  "Check if PATH exists in a filesystem tree entry list.
   Tree entries are S-expressions: (:file \"path\" :hash ... :mode ...)"
  (let ((find-fn (let* ((pkg (find-package :autopoiesis.snapshot))
                         (fn (when pkg (find-symbol "TREE-FIND-ENTRY" pkg))))
                   (when (and fn (fboundp fn)) fn))))
    (if find-fn
        (not (null (funcall find-fn tree path)))
        ;; Fallback: manual search
        (some (lambda (entry)
                (and (listp entry)
                     (stringp (second entry))
                     (string= (second entry) path)))
              tree))))

(defun cl-file-count-above (tree n)
  "Check if a tree has more than N file entries."
  (let ((count (count-if (lambda (entry)
                           (and (listp entry) (eq (first entry) :file)))
                         tree)))
    (> count n)))

(defun cl-output-contains (output substr)
  "Check if OUTPUT string contains SUBSTR."
  (and (stringp output) (stringp substr)
       (not (null (search substr output)))))

;;; ===================================================================
;;; Verifier Registration
;;; ===================================================================

(defun register-shen-verifiers ()
  "Register :prolog-query and :prolog-check verifiers with the eval system.
   Call this after loading both autopoiesis-shen and autopoiesis/eval.
   Safe to call if eval is not loaded (no-op)."
  (let* ((pkg (find-package :autopoiesis.eval))
         (register-fn (when pkg (find-symbol "REGISTER-VERIFIER" pkg))))
    (unless (and register-fn (fboundp register-fn))
      (return-from register-shen-verifiers nil))
    ;; :prolog-query — expected is a rule name keyword
    (funcall register-fn :prolog-query
             (lambda (output &key expected result &allow-other-keys)
               (prolog-query-verifier output expected result)))
    ;; :prolog-check — expected is an inline check spec
    (funcall register-fn :prolog-check
             (lambda (output &key expected result &allow-other-keys)
               (prolog-check-verifier output expected result)))
    t))

;;; ===================================================================
;;; Verifier Implementations
;;; ===================================================================

(defun prolog-query-verifier (output expected result)
  "Verify using a named rule from *rule-store*.
   EXPECTED is a keyword naming the rule.
   Tries three paths in order:
   1. Shen Prolog (if loaded)
   2. Substrate Datalog (if available and rule has datom patterns)
   3. CL fallback (pattern matching on clause structure)"
  (unless (shen-available-p)
    ;; Try substrate Datalog before CL fallback
    (let ((datalog-result (datalog-fallback-verify expected output result)))
      (when datalog-result
        (return-from prolog-query-verifier datalog-result)))
    ;; Fall back to CL pattern matching
    (return-from prolog-query-verifier
      (cl-fallback-verify expected output result)))
  (unless (keywordp expected)
    (return-from prolog-query-verifier :error))
  (let ((clauses (gethash expected *rule-store*)))
    (unless clauses
      (return-from prolog-query-verifier :error))
    (handler-case
        (let* ((metadata (getf result :metadata))
               (after-tree (getf metadata :after-tree))
               (query-result (query-rules expected
                                          :tree (or after-tree '())
                                          :output (or output "")
                                          :exit-code (or (getf result :exit-code) -1))))
          (if query-result :pass :fail))
      (error () :error))))

(defun prolog-check-verifier (output expected result)
  "Verify using an inline check specification.
   EXPECTED is a plist describing the check:
     (:files-exist (\"path1\" \"path2\" ...))
     (:output-contains \"substring\")
     (:file-count-above N)
     (:all <check1> <check2> ...)"
  (handler-case
      (if (and (listp expected) (keywordp (first expected)))
          (cl-check-verify expected output result)
          :error)
    (error () :error)))

;;; ===================================================================
;;; Substrate Datalog Verification
;;; ===================================================================

(defun datalog-fallback-verify (rule-name output result)
  "Try to verify using the substrate Datalog engine.
   Converts the Shen-format rule to Datalog, runs it via `q`.
   Returns :pass, :fail, or NIL (if Datalog is not applicable)."
  (let ((substrate-pkg (find-package :autopoiesis.substrate)))
    (unless substrate-pkg (return-from datalog-fallback-verify nil))
    (let ((q-fn (find-symbol "Q" substrate-pkg))
          (convert-fn (find-symbol "CONVERT-SHEN-RULES-TO-DATALOG" substrate-pkg)))
      (unless (and q-fn (fboundp q-fn) convert-fn (fboundp convert-fn))
        (return-from datalog-fallback-verify nil))
      ;; Get the rule clauses from our store
      (let ((clauses (gethash rule-name *rule-store*)))
        (unless clauses (return-from datalog-fallback-verify nil))
        ;; Convert Shen format → Datalog format
        (handler-case
            (let* ((dl-clauses (funcall convert-fn clauses))
                   ;; Build a query: does the rule succeed with the given context?
                   (metadata (getf result :metadata))
                   (after-tree (getf metadata :after-tree))
                   ;; For now, only handle rules that query datom patterns
                   ;; (rules with has-file, output-contains etc. stay on CL fallback)
                   (has-datom-patterns (some (lambda (clause)
                                               (some (lambda (term)
                                                       (and (listp term)
                                                            (= 3 (length term))
                                                            (variable-p-shen (first term))))
                                                     (rest clause)))
                                             dl-clauses)))
              (if has-datom-patterns
                  ;; This rule queries the substrate — run via Datalog
                  (let ((query-result
                          (funcall q-fn
                                   `(:find ?result
                                     :in %
                                     :where (,(car (car (first dl-clauses)))
                                             ,@(mapcar (lambda (x) (declare (ignore x)) '?_x)
                                                       (rest (car (first dl-clauses))))))
                                   dl-clauses)))
                    (if query-result :pass :fail))
                  ;; Not datom-based — let CL fallback handle it
                  nil))
          (error () nil))))))

(defun variable-p-shen (x)
  "Check if X looks like a Datalog variable (?x style)."
  (and (symbolp x)
       (> (length (symbol-name x)) 1)
       (char= #\? (char (symbol-name x) 0))))

;;; ===================================================================
;;; CL Fallback Verification (when Shen not loaded)
;;; ===================================================================

(defun cl-fallback-verify (rule-name output result)
  "Attempt verification using CL helpers when Shen is not available.
   Inspects the rule's clauses for recognizable CL-checkable patterns.
   Returns :pass, :fail, or :error."
  (let ((clauses (gethash rule-name *rule-store*)))
    (unless clauses
      (return-from cl-fallback-verify :error))
    (let ((spec (clauses-to-cl-check clauses)))
      (if spec
          (cl-check-verify spec output result)
          :error))))

(defun clauses-to-cl-check (clauses)
  "Try to convert Prolog clauses to a CL check spec.
   Returns a check spec or NIL if the clauses aren't CL-checkable.
   Recognizes patterns like (has-file Tree \"path\") -> (:files-exist ...)."
  (let ((file-paths nil)
        (output-substrings nil))
    (dolist (clause clauses)
      (when (listp clause)
        (let ((body (rest (member '<-- clause))))
          (dolist (term body)
            (when (listp term)
              (cond
                ((and (eq (first term) 'has-file)
                      (stringp (third term)))
                 (push (third term) file-paths))
                ((and (eq (first term) 'output-contains)
                      (stringp (second term)))
                 (push (second term) output-substrings))))))))
    (cond
      ((and file-paths output-substrings)
       `(:all (:files-exist ,(nreverse file-paths))
              ,@(mapcar (lambda (s) `(:output-contains ,s))
                        (nreverse output-substrings))))
      (file-paths
       `(:files-exist ,(nreverse file-paths)))
      (output-substrings
       (if (= 1 (length output-substrings))
           `(:output-contains ,(first output-substrings))
           `(:all ,@(mapcar (lambda (s) `(:output-contains ,s))
                            (nreverse output-substrings)))))
      (t nil))))

(defun cl-check-verify (spec output result)
  "Run a CL-based check specification.
   Returns :pass or :fail."
  (let* ((check-type (first spec))
         (metadata (getf result :metadata))
         (after-tree (getf metadata :after-tree)))
    (ecase check-type
      (:files-exist
       (let ((paths (second spec)))
         (if (and after-tree
                  (every (lambda (p) (cl-tree-has-file after-tree p)) paths))
             :pass :fail)))
      (:output-contains
       (let ((substr (second spec)))
         (if (cl-output-contains output substr) :pass :fail)))
      (:file-count-above
       (let ((n (second spec)))
         (if (and after-tree (cl-file-count-above after-tree n))
             :pass :fail)))
      (:all
       (let ((checks (rest spec)))
         (if (every (lambda (check)
                      (eq :pass (cl-check-verify check output result)))
                    checks)
             :pass :fail))))))
