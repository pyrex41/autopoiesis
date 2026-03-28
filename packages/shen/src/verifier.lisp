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
   Queries the rule with context from the harness result."
  (unless (shen-available-p)
    ;; Fallback: if Shen not loaded, try CL-based verification
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
                                          (or after-tree '())
                                          (or output "")
                                          (or (getf result :exit-code) -1))))
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
;;; CL Fallback Verification (when Shen not loaded)
;;; ===================================================================

(defun cl-fallback-verify (rule-name output result)
  "Attempt verification using CL helpers when Shen is not available.
   Returns :pass, :fail, or :error."
  (declare (ignore output))
  (let* ((metadata (getf result :metadata))
         (after-tree (getf metadata :after-tree)))
    ;; Can only do tree-based checks without Shen
    (if after-tree :error :error)))

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
