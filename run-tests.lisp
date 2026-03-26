(require :asdf)
;; Register all package directories for ASDF discovery
(dolist (dir (directory #p"packages/*/"))
  (push dir asdf:*central-registry*))
(push #p"vendor/" asdf:*central-registry*)
(handler-case
    (progn
      (asdf:load-system :autopoiesis)
      (asdf:load-system :autopoiesis/test)
      (funcall (intern "RUN-ALL-TESTS" "AUTOPOIESIS.TEST")))
  (error (e)
    (format t "~%ERROR: ~a~%" e)
    (sb-ext:exit :code 1)))
