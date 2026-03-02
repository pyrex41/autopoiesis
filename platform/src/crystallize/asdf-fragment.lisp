;;;; asdf-fragment.lisp - Generate ASDF defsystem fragments
;;;;
;;;; Creates loadable ASDF system definitions for crystallized capabilities.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; ASDF Fragment Generation
;;; ===================================================================

(defun emit-asdf-fragment (crystallized-forms output-path &key (system-name "crystallized"))
  "Generate an ASDF defsystem fragment that loads crystallized files.
   This is used when exporting to filesystem for standalone loading."
  (let* ((cap-files (loop for (name . form) in (or (getf crystallized-forms :capabilities-named) nil)
                          collect (format nil "capabilities/~(~a~)" name)))
         (fragment `(asdf:defsystem ,(intern (string-upcase system-name) :keyword)
                      :description "Auto-generated crystallized capabilities"
                      :serial t
                      :components ,(mapcar (lambda (f) `(:file ,f)) cap-files))))
    (emit-to-file (list fragment) output-path :header "ASDF system fragment for crystallized code")
    output-path))
