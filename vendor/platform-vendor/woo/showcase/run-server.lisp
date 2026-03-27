;; Use local woo, not quicklisp version (local has WebSocket exports)
(push #P"/Users/reuben/gauntlet/woo/" asdf:*central-registry*)
(push #P"/Users/reuben/gauntlet/woo/showcase/" asdf:*central-registry*)

(ql:quickload :woo-showcase :silent t)

(format t "~%Starting Woo Showcase server...~%")
(woo-showcase:start :port 5000 :worker-num 1)
