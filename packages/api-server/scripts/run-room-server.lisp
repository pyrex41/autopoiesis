;;;; run-room-server.lisp - Start a standalone shared-room MCP server.
;;;;
;;;; Boots the substrate (GLOBAL store), declares the room schema, seeds a base
;;;; task, and starts the Streamable-HTTP /mcp endpoint, then blocks forever so
;;;; a REAL coding agent (Claude Code / Codex) can connect over MCP and call the
;;;; room_* tools.
;;;;
;;;;   PORT=8240 sbcl --noinform --non-interactive --load \
;;;;     packages/api-server/scripts/run-room-server.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis/api :silent t)

(let ((port (or (ignore-errors (parse-integer (uiop:getenv "PORT"))) 8240)))
  (autopoiesis.substrate:open-store)
  (autopoiesis.api::room-ensure-schema)
  (autopoiesis.substrate:transact!
   (list (autopoiesis.substrate:make-datom "task-42" "room/decision" "use-postgres")
         (autopoiesis.substrate:make-datom "task-42" "room/note"     "kickoff")))
  (autopoiesis.api:start-rest-server :port port :host "127.0.0.1")
  (format t "~&ROOM-SERVER-READY port=~A url=http://127.0.0.1:~A/mcp~%" port port)
  (force-output)
  (loop (sleep 3600)))
