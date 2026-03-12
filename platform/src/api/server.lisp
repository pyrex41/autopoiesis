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
          (when (and response (listp response))
            (let ((headers (second response)))
              (setf (second response)
                    (append headers
                            (list :access-control-allow-origin "*"
                                  :access-control-allow-methods "GET, POST, OPTIONS"
                                  :access-control-allow-headers "Content-Type, Authorization")))))
          response))))

;;; ═══════════════════════════════════════════════════════════════════
;;; WebSocket Handler
;;; ═══════════════════════════════════════════════════════════════════ b374f5a (Add MCP server, Go client SDK, and PicoClaw Skill integration)

(defun make-websocket-handler (env)
  "Create a WebSocket connection handler using Woo's native WebSocket support."
  (let* ((socket (getf env :clack.io))
         (headers (getf env :headers))
         (ws-key (gethash "sec-websocket-key" headers))
         (accept-key (woo.websocket:compute-accept-key ws-key))
         (connection (make-instance 'api-connection :ws socket)))

    ;; Use delayed response: Woo calls our lambda with a responder.
    ;; We write the 101 upgrade ourselves, set up WebSocket, then
    ;; call responder with a streaming writer (which we won't use)
    ;; so Woo keeps the socket in its event loop.
    (lambda (responder)
      ;; Write 101 Switching Protocols AND the welcome message in a single
      ;; async write batch. This ensures the 101 response is flushed before
      ;; any WebSocket frames — mixing with-async-writing (for 101) and
      ;; ws-send-text (direct fd write) would race.
      (let ((welcome-payload (trivial-utf-8:string-to-utf-8-bytes
                              (encode-message
                               (ok-response "connected"
                                            "connectionId" (connection-id connection)
                                            "version" (autopoiesis:version)))))
            (welcome-frame nil))
        (setf welcome-frame
              (woo.websocket::make-frame woo.websocket:+opcode-text+ welcome-payload))
        (woo.ev.socket:with-async-writing (socket)
          (woo.response:write-socket-string socket "HTTP/1.1 101 Switching Protocols")
          (woo.response:write-socket-crlf socket)
          (woo.response:write-socket-string socket "Upgrade: websocket")
          (woo.response:write-socket-crlf socket)
          (woo.response:write-socket-string socket "Connection: Upgrade")
          (woo.response:write-socket-crlf socket)
          (woo.response:write-socket-string socket "Sec-WebSocket-Accept: ")
          (woo.response:write-socket-string socket accept-key)
          (woo.response:write-socket-crlf socket)
          (woo.response:write-socket-crlf socket)
          ;; Welcome frame in same write batch — after 101
          (woo.ev.socket:write-socket-data socket welcome-frame)))

      ;; Set up WebSocket frame handling on this socket
      (woo.websocket:setup-websocket socket
        :on-message (lambda (opcode payload)
                      (declare (ignore opcode))
                      (handler-case
                          (let* ((json-string (trivial-utf-8:utf-8-bytes-to-string payload))
                                 (response (handle-message connection json-string)))
                            (when response
                              (ws-send-text socket response)))
                        (error (e)
                          (log:warn "WebSocket message error for ~a: ~a"
                                    (connection-id connection) e))))
        :on-close (lambda (code reason)
                    (declare (ignore code reason))
                    (cleanup-chat-sessions-for-connection connection)
                    (unregister-connection connection))
        :on-error (lambda (error)
                    (log:warn "WebSocket error for ~a: ~a" (connection-id connection) error)
                    (cleanup-chat-sessions-for-connection connection)
                    (unregister-connection connection)))

      ;; Register connection (after setup, so handlers are ready)
      (register-connection connection)

      ;; Don't call responder - we've already written the upgrade response
      ;; and set up the WebSocket frame parser on the socket
      nil)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Dashboard Serving
;;; ═══════════════════════════════════════════════════════════════════

(defun serve-dashboard ()
  "Serve the agent swarm dashboard HTML page."
  (let ((dashboard-path (merge-pathnames "dashboard.html" *api-static-path*)))
    (if (and *api-static-path* (probe-file dashboard-path))
        (list 200
              '(:content-type "text/html")
              (list (uiop:read-file-string dashboard-path)))
        (list 404
              '(:content-type "text/html")
              (list "<html><body><h1>Dashboard not found</h1><p>Static path not configured or dashboard.html missing.</p></body></html>")))))

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

      ;; Dashboard
      ((and (eq method :get) (equal path "/dashboard"))
       (serve-dashboard))

      ;; Root redirect to /dashboard
      ((and (eq method :get) (equal path "/"))
       '(302 (:location "/dashboard") ("")))

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
                    (let* ((path (getf env :path-info))
                           (headers (getf env :headers))
                           (upgrade (typecase headers
                                      (hash-table (gethash "upgrade" headers))
                                      (list (getf headers :upgrade))
                                      (t nil))))
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
                    (static-path (truename *api-static-path*)))
                (lambda (env)
                  (let ((path (getf env :path-info)))
                    ;; Serve static files for /static/ prefix
                    (if (and (>= (length path) 8)
                             (string= "/static/" (subseq path 0 8)))
                        (let* ((file-path (subseq path 8))
                               (full-path (merge-pathnames file-path static-path))
                               (resolved (ignore-errors (truename full-path))))
                          ;; Validate resolved path is under static-path (prevent traversal)
                          (if (and resolved
                                   (uiop:subpathp resolved static-path))
                              (list 200
                                    (list :content-type
                                          (guess-content-type file-path))
                                    resolved)
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

  ;; Set static path - default to platform/static if not specified
  (when static-path
    (setf *api-static-path* (pathname static-path)))
  (unless *api-static-path*
    ;; Default to platform/static relative to the autopoiesis.asd file
    (let ((asd-path (asdf:system-source-directory :autopoiesis)))
      (when asd-path
        (setf *api-static-path* (merge-pathnames "static/" asd-path)))))

  ;; Start event bridge, blocking notifier, activity tracker, and holodeck bridge
  (start-event-bridge)
  (start-blocking-notifier)
  (start-activity-tracker)
  (start-holodeck-bridge)

  ;; Initialize web console
  (init-web-console)

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
  (stop-holodeck-bridge)
  (stop-event-bridge)
  (stop-blocking-notifier)
  (stop-activity-tracker)

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
