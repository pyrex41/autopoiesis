(require :asdf)
;; Only use platform path - the root .asd files reference non-existent src/ paths
(push #p"/Users/reuben/projects/ap/platform/" asdf:*central-registry*)
(handler-case
    (progn
      (asdf:load-system :autopoiesis)
      (asdf:load-system :autopoiesis/test)
      (funcall (intern "RUN-ALL-TESTS" "AUTOPOIESIS.TEST")))
  (error (e)
    (format t "~%ERROR: ~a~%" e)
    (sb-ext:exit :code 1)))
