;; Simple benchmark server for Woo
;; Returns "Hello, World!" for all requests

(ql:quickload '(:woo) :silent t)

(defun benchmark-app (env)
  (declare (ignore env))
  '(200
    (:content-type "text/plain"
     :content-length 13)
    ("Hello, World!")))

(format t "~%Starting Woo benchmark server on port 3000...~%")
(format t "Press Ctrl+C to stop.~%~%")

(woo:run #'benchmark-app
         :port 3000
         :address "127.0.0.1"
         :worker-num 8
         :debug nil)
