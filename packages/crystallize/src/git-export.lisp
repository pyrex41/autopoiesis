;;;; git-export.lisp - Export crystallized snapshots to filesystem
;;;;
;;;; One-way DAG to Git export. Writes crystallized forms as .lisp files
;;;; to a directory structure suitable for version control.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; Git Export
;;; ===================================================================

(defun export-to-git (snapshot &key output-dir commit-message)
  "Export a crystallized snapshot to filesystem and optionally git commit.
   1. Read :crystallized forms from snapshot metadata
   2. Emit each form to output-dir via emit-to-file
   3. Return list of written file paths

   Does NOT actually call git - that's left to the git tools in builtin-tools.
   This just writes files to the filesystem."
  (declare (ignore commit-message))
  (let* ((metadata (autopoiesis.snapshot:snapshot-metadata snapshot))
         (crystallized (getf metadata :crystallized))
         (dir (or output-dir (merge-pathnames "crystallized/" (uiop:getcwd))))
         (written-files nil))
    (unless crystallized
      (return-from export-to-git nil))
    ;; Write capabilities
    (let ((caps (getf crystallized :capabilities)))
      (when caps
        (dolist (form caps)
          (let ((path (merge-pathnames
                       (format nil "capabilities/~(~a~).lisp"
                               (or (and (listp form) (third form)) "unknown"))
                       dir)))
            (emit-to-file (list form) path
                          :header (format nil "Crystallized capability"))
            (push path written-files)))))
    ;; Write heuristics
    (let ((heurs (getf crystallized :heuristics)))
      (when heurs
        (let ((path (merge-pathnames "heuristics/all.lisp" dir)))
          (emit-to-file heurs path
                        :header "Crystallized heuristics")
          (push path written-files))))
    (nreverse written-files)))
