(in-package :woo-showcase)

(defvar *app* (make-instance 'ningle:app))
(defvar *server* nil)

;; Static file path
(defvar *static-root*
  (asdf:system-relative-pathname :woo-showcase "static/"))

;; Template directory
(defvar *template-root*
  (asdf:system-relative-pathname :woo-showcase "templates/"))

;; Initialize Djula templates
(djula:add-template-directory *template-root*)

(defun render-template (name &rest args)
  (let ((template (djula:compile-template* name)))
    (apply #'djula:render-template* template nil args)))

;; Landing page
(setf (ningle:route *app* "/")
      (lambda (params)
        (declare (ignore params))
        (render-template "index.html")))

;; Benchmarks page
(setf (ningle:route *app* "/benchmarks")
      (lambda (params)
        (declare (ignore params))
        (render-template "benchmarks.html")))

;; API endpoint for benchmark data (JSON)
(setf (ningle:route *app* "/api/benchmarks")
      (lambda (params)
        (declare (ignore params))
        (setf (getf (lack.response:response-headers ningle:*response*) :content-type)
              "application/json")
        (jonathan:to-json *benchmark-data*)))

;; WebSocket demo page
(setf (ningle:route *app* "/websocket")
      (lambda (params)
        (declare (ignore params))
        (render-template "websocket.html")))

;; WebSocket upgrade endpoint
(setf (ningle:route *app* "/ws/echo")
      (lambda (params)
        (declare (ignore params))
        (let* ((env ningle:*request*)
               (socket (getf env :clack.io)))
          (when (woo:websocket-p env)
            (let* ((headers (getf env :headers))
                   (key (gethash "sec-websocket-key" headers))
                   (accept (woo:compute-accept-key key)))
              ;; Send upgrade response
              (woo:write-websocket-upgrade-response socket accept)
              ;; Setup WebSocket handling
              (woo:setup-websocket socket
                :on-message (lambda (opcode payload)
                              (declare (ignore opcode))
                              ;; Echo back the message
                              (woo:send-text-frame socket
                                (trivial-utf-8:utf-8-bytes-to-string payload)))
                :on-close (lambda (code reason)
                            (declare (ignore code reason))
                            nil))
              ;; Return nil to prevent normal response
              nil)))))

;; HTTP/2 demo page
(setf (ningle:route *app* "/http2")
      (lambda (params)
        (declare (ignore params))
        (render-template "http2.html")))

;; Simulated slow resource (configurable delay)
(setf (ningle:route *app* "/api/resource/:id")
      (lambda (params)
        (let* ((id (cdr (assoc :id params)))
               (query-delay (cdr (assoc "delay" params :test #'string=)))
               (delay (if query-delay
                          (parse-integer query-delay :junk-allowed t)
                          100)))
          (sleep (/ (or delay 100) 1000.0))
          (setf (getf (lack.response:response-headers ningle:*response*) :content-type)
                "application/json")
          (jonathan:to-json
            (list :|id| id
                  :|timestamp| (get-universal-time)
                  :|delay| delay)))))

;; Build Lack app with middleware
(defvar *handler*
  (lack:builder
    :accesslog
    (:static :path "/static/" :root *static-root*)
    *app*))

(defun start (&key (port 5000) (worker-num 4))
  (setf *server*
        (woo:run *handler*
                 :port port
                 :worker-num worker-num
                 :debug nil))
  (format t "~%Woo Showcase running at http://127.0.0.1:~A~%" port)
  (format t "Press Ctrl+C to stop.~%"))

(defun stop ()
  (when *server*
    (woo:stop *server*)
    (setf *server* nil)
    (format t "Server stopped.~%")))
