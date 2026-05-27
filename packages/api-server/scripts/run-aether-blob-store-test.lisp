;;;; run-aether-blob-store-test.lisp - Driver for the standalone test.
;;;;
;;;; Loads :autopoiesis/api, then loads the test file, then runs the tests.
;;;; Exits with non-zero status on failure.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/api-server/scripts/run-aether-blob-store-test.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/"
               "./packages/substrate/"
               "./packages/api-server/"
               "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis :silent t)
(ql:quickload :autopoiesis/api :silent t)

(load (truename "./packages/api-server/test/aether-blob-store-test.lisp"))

(handler-case
    (let ((runner (find-symbol "RUN-AETHER-BLOB-STORE-TESTS"
                               (find-package "AUTOPOIESIS.API"))))
      (unless runner
        (error "run-aether-blob-store-tests not defined in :autopoiesis.api"))
      (funcall runner)
      (sb-ext:exit :code 0))
  (error (e)
    (format *error-output* "~&aether-blob-store TEST FAILED: ~A~%" e)
    (sb-ext:exit :code 1)))
