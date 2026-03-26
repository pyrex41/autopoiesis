;; Use local woo, not quicklisp version (local has WebSocket exports)
(push #P"/Users/reuben/gauntlet/woo/" asdf:*central-registry*)
(push #P"/Users/reuben/gauntlet/woo/showcase/" asdf:*central-registry*)
(handler-case
  (progn
    (ql:quickload :woo-showcase :silent t)
    (format t "~%SUCCESS: woo-showcase loaded successfully!~%")
    (sb-ext:exit :code 0))
  (error (e)
    (format t "~%ERROR: ~A~%" e)
    (sb-ext:exit :code 1)))
