;;;; run-sb-server.lisp - long-running REST server with a seeded SB board,
;;;; for live eyeballing of the Board view (vite dev proxies /api -> :8097).
(in-package #:cl-user)
(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis/api :silent t)

(autopoiesis.substrate:open-store)
(autopoiesis.api::seed-sb-demo)
(autopoiesis.api::start-rest-server :port 8097)
(format t "~%>>> SB REST server up on http://localhost:8097 (seeded)~%")
(finish-output)
(loop (sleep 60))
