;;;; aether-dev-server.lisp — boot the AETHER dev backend.
;;;;
;;;; Loads core + substrate + api-server, seeds a demo snapshot store, and
;;;; starts both the REST control API (:8081) and the WebSocket server
;;;; (:8095, which the Vite dev proxy points at). Run from the repo root:
;;;;
;;;;   sbcl --noinform --non-interactive --load packages/api-server/scripts/aether-dev-server.lisp
;;;;
;;;; Lives in the repo (not /tmp) so it survives temp-dir cleanup.

(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis :silent t)
(ql:quickload :autopoiesis/api :silent t)
(load "packages/core/scripts/aether-seed.lisp")

;; Populate (idempotent) + initialize the snapshot store the API serves from.
(aether-seed:populate :path #P"/tmp/aether-seed/" :n 60 :seed 42)
(autopoiesis.snapshot:initialize-store
 (uiop:ensure-directory-pathname #P"/tmp/aether-seed/"))

;; *api-require-auth* defaults to NIL, so unauthenticated curl/browser works.
(autopoiesis.api:start-rest-server :port 8081)
(autopoiesis.api:start-api-server :port 8095)
(format t "~&AETHER server ready: REST on 8081, WS on 8095.~%")
(format t "~&Agent workspace root: ~A~%"
        (merge-pathnames "aether-workspace/" (user-homedir-pathname)))

;; Block forever.
(loop (sleep 60))
