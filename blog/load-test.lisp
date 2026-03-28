;;;; Quick test to see if autopoiesis loads
(require :asdf)
(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))

(dolist (dir '("packages/core/" "packages/substrate/" "packages/api-server/"
              "packages/eval/" "packages/shen/" "packages/swarm/"
              "packages/team/" "packages/supervisor/" "packages/crystallize/"
              "packages/jarvis/" "packages/paperclip/"
              "packages/sandbox/" "packages/research/"
              "vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(format t "~%Loading autopoiesis...~%")
(handler-case
    (progn
      (handler-bind ((warning #'muffle-warning))
        (ql:quickload :autopoiesis :silent t))
      (format t "~%LOADED OK~%"))
  (error (e)
    (format t "~%LOAD ERROR: ~A~%" e)))

(sb-ext:exit)
