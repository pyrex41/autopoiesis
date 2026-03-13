(defsystem "woo-test"
  :depends-on ("woo"
               "clack-test"
               "rove")
  :components
  ((:file "t/woo")
   (:file "t/ipv6")
   ;; HTTP/2 tests
   (:file "t/hpack")
   (:file "t/http2-frames")
   (:file "t/http2-stream")
   (:file "t/http2-connection")
   ;; WebSocket tests
   (:file "t/websocket")
   ;; SSL/ALPN tests
   (:file "t/alpn" :if-feature (:not :woo-no-ssl)))
  :perform (test-op (op c) (symbol-call '#:rove '#:run c)))
