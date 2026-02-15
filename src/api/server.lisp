;;;; server.lisp - Clack/Lack/Woo WebSocket API server
;;;;
;;;; The main entry point for the API layer. Sets up:
;;;; - Woo as the async server backend (good for WebSocket)
;;;; - Lack middleware stack (static files, CORS, logging)
;;;; - WebSocket upgrade handling via websocket-driver
;;;; - HTTP fallback routes for health checks and static assets
;;;;
;;;; Usage:
;;;;   (autopoiesis.api:start-api-server)          ; Start on default port 8080
;;;;   (autopoiesis.api:start-api-server :port 9000) ; Custom port
;;;;   (autopoiesis.api:stop-api-server)            ; Shutdown

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defvar *api-port* 8080
  "Default port for the API server.")

(defvar *api-host* "0.0.0.0"
  "Default host for the API server.")

(defvar *api-server* nil
  "The running Clack server handle (used to stop it).")

(defvar *api-static-path* nil
  "Path to serve static files from (e.g., frontend build output).
If NIL, no static files are served.")

;;; ═══════════════════════════════════════════════════════════════════
;;; CORS Middleware
;;; ═══════════════════════════════════════════════════════════════════

(defun make-cors-middleware (app)
  "Wrap APP with CORS headers for cross-origin frontend access."
  (lambda (env)
    (if (eq (getf env :request-method) :options)
        ;; Preflight response
        '(204
          (:access-control-allow-origin "*"
           :access-control-allow-methods "GET, POST, OPTIONS"
           :access-control-allow-headers "Content-Type, Authorization"
           :access-control-max-age "86400")
          (""))
        ;; Normal response with CORS headers
        (let ((response (funcall app env)))
          (when response
            (let ((headers (second response)))
              (setf (second response)
                    (append headers
                            (list :access-control-allow-origin "*"
                                  :access-control-allow-methods "GET, POST, OPTIONS"
                                  :access-control-allow-headers "Content-Type, Authorization")))))
          response))))

;;; ═══════════════════════════════════════════════════════════════════
;;; WebSocket Handler
;;; ═══════════════════════════════════════════════════════════════════

(defun make-websocket-handler (env)
  "Create a WebSocket connection handler for the given request ENV."
  (let* ((ws (websocket-driver:make-server env))
         (connection (make-instance 'api-connection :ws ws)))

    ;; On open: register connection, send welcome
    (websocket-driver:on :open ws
      (lambda ()
        (register-connection connection)
        (let ((welcome (encode-message
                        (ok-response "connected"
                                     "connectionId" (connection-id connection)
                                     "version" (autopoiesis:version)))))
          (websocket-driver:send ws welcome))))

    ;; On message: dispatch to handler
    (websocket-driver:on :message ws
      (lambda (json-string)
        (let ((response (handle-message connection json-string)))
          (when response
            (websocket-driver:send ws response)))))

    ;; On close: unregister connection
    (websocket-driver:on :close ws
      (lambda (&key code reason)
        (declare (ignore code reason))
        (unregister-connection connection)))

    ;; Return the WebSocket upgrade response
    (lambda (responder)
      (declare (ignore responder))
      (websocket-driver:start-connection ws))))

;;; ═══════════════════════════════════════════════════════════════════
;;; HTTP Routes
;;; ═══════════════════════════════════════════════════════════════════

(defun http-handler (env)
  "Handle HTTP requests (non-WebSocket)."
  (let ((path (getf env :path-info))
        (method (getf env :request-method)))
    (cond
      ;; Health check
      ((and (eq method :get) (equal path "/health"))
       (let* ((health (autopoiesis:health-check))
              (status (if (eq (getf health :status) :healthy) 200 503)))
         (list status
               '(:content-type "application/json")
               (list (encode-message
                      (let ((h (make-hash-table :test 'equal)))
                        (setf (gethash "status" h) (string-downcase
                                                    (symbol-name (getf health :status)))
                              (gethash "version" h) (autopoiesis:version)
                              (gethash "connections" h) (connection-count))
                        h))))))

      ;; API info
      ((and (eq method :get) (equal path "/api"))
       (list 200
             '(:content-type "application/json")
             (list (encode-message
                    (let ((h (make-hash-table :test 'equal)))
                      (setf (gethash "name" h) "autopoiesis"
                            (gethash "version" h) (autopoiesis:version)
                            (gethash "websocket" h) "/ws"
                            (gethash "protocol" h) "See docs for WebSocket message protocol")
                      h)))))

      ;; Root redirect to /api
      ((and (eq method :get) (equal path "/"))
       '(302 (:location "/api") ("")))

      ;; 404
      (t
       (list 404
             '(:content-type "application/json")
             (list (encode-message
                    (let ((h (make-hash-table :test 'equal)))
                      (setf (gethash "error" h) "not_found"
                            (gethash "message" h) (format nil "No route for ~a ~a" method path))
                      h))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Application Builder
;;; ═══════════════════════════════════════════════════════════════════

(defun make-app ()
  "Build the Clack application with middleware stack."
  (let ((base-app (lambda (env)
                    (let ((path (getf env :path-info))
                          (upgrade (gethash "upgrade"
                                            (getf env :headers)
                                            nil)))
                      ;; Check for WebSocket upgrade on /ws
                      (if (and (equal path "/ws")
                               upgrade
                               (string-equal upgrade "websocket"))
                          (make-websocket-handler env)
                          (http-handler env))))))
    ;; Build middleware stack
    (let ((app (make-cors-middleware base-app)))
      ;; Add static file serving if configured
      (when *api-static-path*
        (setf app
              (let ((inner app)
                    (static-path *api-static-path*))
                (lambda (env)
                  (let ((path (getf env :path-info)))
                    ;; Serve static files for /static/ prefix
                    (if (and (>= (length path) 8)
                             (string= "/static/" (subseq path 0 8)))
                        (let* ((file-path (subseq path 8))
                               (full-path (merge-pathnames file-path static-path)))
                          (if (probe-file full-path)
                              (list 200
                                    (list :content-type
                                          (guess-content-type file-path))
                                    full-path)
                              (funcall inner env)))
                        (funcall inner env)))))))
      app)))

(defun guess-content-type (filename)
  "Guess MIME type from file extension."
  (let ((ext (pathname-type filename)))
    (cond
      ((equal ext "html") "text/html")
      ((equal ext "js") "application/javascript")
      ((equal ext "css") "text/css")
      ((equal ext "json") "application/json")
      ((equal ext "png") "image/png")
      ((equal ext "jpg") "image/jpeg")
      ((equal ext "svg") "image/svg+xml")
      ((equal ext "woff2") "font/woff2")
      ((equal ext "wasm") "application/wasm")
      (t "application/octet-stream"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Server Lifecycle
;;; ═══════════════════════════════════════════════════════════════════

(defun start-api-server (&key (port *api-port*) (host *api-host*) static-path)
  "Start the API server.

   PORT: TCP port to listen on (default 8080)
   HOST: Interface to bind to (default 0.0.0.0)
   STATIC-PATH: Optional path to serve static files from

   Returns the server handle."
  (when *api-server*
    (log:warn "API server already running, stopping first")
    (stop-api-server))

  (when static-path
    (setf *api-static-path* (pathname static-path)))

  ;; Start event bridge and blocking notifier
  (start-event-bridge)
  (start-blocking-notifier)

  ;; Start the Clack server with Woo backend
  (setf *api-server*
        (clack:clackup (make-app)
                       :server :woo
                       :port port
                       :address host
                       :use-default-middlewares nil
                       :silent t))

  (log:info "API server started on ~a:~d" host port)
  (format t "~&Autopoiesis API server running at http://~a:~d~%" host port)
  (format t "  WebSocket: ws://~a:~d/ws~%" host port)
  (format t "  Health:    http://~a:~d/health~%" host port)
  *api-server*)

(defun stop-api-server ()
  "Stop the API server and clean up."
  (stop-event-bridge)
  (stop-blocking-notifier)

  (when *api-server*
    (handler-case
        (clack:stop *api-server*)
      (error (e)
        (log:warn "Error stopping API server: ~a" e)))
    (setf *api-server* nil))

  ;; Close all connections
  (dolist (conn (list-connections))
    (unregister-connection conn))

  (log:info "API server stopped")
  t)

(defun api-server-running-p ()
  "Return T if the API server is running."
  (not (null *api-server*)))
