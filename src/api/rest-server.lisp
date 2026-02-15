;;;; rest-server.lisp - Hunchentoot REST API server
;;;;
;;;; Manages the Hunchentoot HTTP server for the REST control API.
;;;; Runs alongside the WebSocket API server (server.lisp) on a
;;;; separate port.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Configuration
;;; ===================================================================

(defvar *rest-port* 8081
  "Port for the REST control API server. Default 8081.")

(defvar *rest-server* nil
  "The running Hunchentoot acceptor for the REST control API.")

(defvar *rest-dispatch-table* nil
  "Saved dispatch table for REST API endpoints.")

(defvar *rest-previous-dispatch-table* nil
  "Previous dispatch table to restore on stop.")

;;; ===================================================================
;;; Server Management
;;; ===================================================================

(defun create-rest-dispatcher ()
  "Create the URL dispatcher for REST API endpoints.
   Includes both the REST /api/ routes and the MCP /mcp endpoint."
  (list
   (hunchentoot:create-prefix-dispatcher "/mcp" #'handle-mcp-endpoint)
   (hunchentoot:create-regex-dispatcher "^/api/" #'api-dispatch-handler)))

(defun start-rest-server (&key (port *rest-port*) (host *api-host*))
  "Start the REST control API HTTP server.

   Arguments:
     port - Port to listen on (default *rest-port*, 8081)
     host - Host to bind to (default *api-host*, 0.0.0.0)

   Returns: The Hunchentoot acceptor"
  (when *rest-server*
    (warn "REST API server already running. Stopping existing server.")
    (stop-rest-server))

  (let ((acceptor (make-instance 'hunchentoot:easy-acceptor
                                 :port port
                                 :address host
                                 :name "autopoiesis-rest-api")))
    ;; Suppress default Hunchentoot access logging
    (setf (hunchentoot:acceptor-access-log-destination acceptor) nil)

    ;; Save current dispatch table and set up REST API dispatchers
    (setf *rest-previous-dispatch-table* hunchentoot:*dispatch-table*)
    (setf *rest-dispatch-table* (create-rest-dispatcher))
    (setf hunchentoot:*dispatch-table*
          (append *rest-dispatch-table* *rest-previous-dispatch-table*))

    ;; Start SSE bridge to forward internal events
    (start-sse-bridge)

    ;; Start the server
    (hunchentoot:start acceptor)
    (setf *rest-server* acceptor)

    (format t "~&Autopoiesis REST API started on ~a:~d~%" host port)
    (format t "  REST endpoints at /api/...~%")
    (format t "  MCP endpoint at /mcp~%")
    (format t "  Auth: (register-api-key \"key\" :identity \"name\")~%")

    acceptor))

(defun stop-rest-server ()
  "Stop the REST control API HTTP server."
  (stop-sse-bridge)
  (when *rest-server*
    (hunchentoot:stop *rest-server*)
    (setf *rest-server* nil)
    ;; Restore previous dispatch table
    (when *rest-previous-dispatch-table*
      (setf hunchentoot:*dispatch-table* *rest-previous-dispatch-table*)
      (setf *rest-previous-dispatch-table* nil))
    (setf *rest-dispatch-table* nil)
    (format t "~&Autopoiesis REST API stopped.~%")
    t))

(defun rest-server-running-p ()
  "Check if the REST API server is running."
  (and *rest-server*
       (hunchentoot:started-p *rest-server*)))
