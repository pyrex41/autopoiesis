(require :asdf)
;; Use the current working directory so tests work from any checkout location
(push (uiop:getcwd) asdf:*central-registry*)
(handler-case
    (progn
      (asdf:load-system :autopoiesis)
      (asdf:load-system :autopoiesis/test)
      (funcall (intern "RUN-ALL-TESTS" "AUTOPOIESIS.TEST")))
  (error (e)
    (format t "~%ERROR: ~a~%" e)
    (sb-ext:exit :code 1)))
