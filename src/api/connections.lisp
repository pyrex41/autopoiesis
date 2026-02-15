;;;; connections.lisp - WebSocket connection management
;;;;
;;;; Tracks connected clients, their subscriptions, and provides
;;;; broadcast/targeted message delivery.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Connection Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass api-connection ()
  ((id :initarg :id
       :accessor connection-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique connection identifier")
   (ws :initarg :ws
       :accessor connection-ws
       :documentation "WebSocket driver instance")
   (subscriptions :initarg :subscriptions
                  :accessor connection-subscriptions
                  :initform (make-hash-table :test 'equal)
                  :documentation "What this connection is subscribed to.
Hash table mapping subscription-type -> parameters.")
   (created-at :initarg :created-at
               :accessor connection-created-at
               :initform (autopoiesis.core:get-precise-time)
               :documentation "When connection was established")
   (metadata :initarg :metadata
             :accessor connection-metadata
             :initform (make-hash-table :test 'equal)
             :documentation "Arbitrary metadata about this connection"))
  (:documentation "A connected frontend client with its WebSocket and subscriptions"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Connection Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *connections* (make-hash-table :test 'equal)
  "Registry of active WebSocket connections by ID.")

(defvar *connections-lock* (bordeaux-threads:make-lock "api-connections-lock")
  "Lock for thread-safe connection registry access.")

(defun register-connection (connection)
  "Register a new connection."
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (setf (gethash (connection-id connection) *connections*) connection))
  (log:info "API connection registered: ~a" (connection-id connection))
  connection)

(defun unregister-connection (connection)
  "Remove a connection from the registry."
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (remhash (connection-id connection) *connections*))
  (log:info "API connection unregistered: ~a" (connection-id connection))
  connection)

(defun find-connection (id)
  "Find a connection by ID."
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (gethash id *connections*)))

(defun list-connections ()
  "List all active connections."
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (loop for conn being the hash-values of *connections*
          collect conn)))

(defun connection-count ()
  "Return the number of active connections."
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (hash-table-count *connections*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Subscription Management
;;; ═══════════════════════════════════════════════════════════════════

(defun subscribe-connection (connection subscription-type &optional params)
  "Subscribe a connection to a type of real-time updates.

   SUBSCRIPTION-TYPE: string like \"events\", \"thoughts:AGENT-ID\", \"agents\"
   PARAMS: optional plist of subscription parameters"
  (setf (gethash subscription-type (connection-subscriptions connection))
        (or params t))
  (log:debug "Connection ~a subscribed to ~a"
             (connection-id connection) subscription-type))

(defun unsubscribe-connection (connection subscription-type)
  "Unsubscribe a connection from a type of updates."
  (remhash subscription-type (connection-subscriptions connection))
  (log:debug "Connection ~a unsubscribed from ~a"
             (connection-id connection) subscription-type))

(defun connection-subscribed-p (connection subscription-type)
  "Check if connection is subscribed to SUBSCRIPTION-TYPE."
  (nth-value 1 (gethash subscription-type (connection-subscriptions connection))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Delivery
;;; ═══════════════════════════════════════════════════════════════════

(defun send-to-connection (connection message-string)
  "Send a JSON string to a specific connection."
  (handler-case
      (websocket-driver:send (connection-ws connection) message-string)
    (error (e)
      (log:warn "Failed to send to connection ~a: ~a"
                (connection-id connection) e)
      ;; Connection is probably dead, clean it up
      (unregister-connection connection))))

(defun broadcast-message (message-string &key subscription-type)
  "Send a message to all connections, optionally filtered by subscription.

   MESSAGE-STRING: pre-encoded JSON string
   SUBSCRIPTION-TYPE: if provided, only send to connections subscribed to this"
  (bordeaux-threads:with-lock-held (*connections-lock*)
    (loop for conn being the hash-values of *connections*
          when (or (null subscription-type)
                   (connection-subscribed-p conn subscription-type))
            do (handler-case
                   (websocket-driver:send (connection-ws conn) message-string)
                 (error (e)
                   (log:warn "Broadcast send failed for ~a: ~a"
                             (connection-id conn) e))))))

(defun broadcast-to-agent-subscribers (agent-id message-string)
  "Send a message to all connections subscribed to a specific agent's updates."
  (let ((sub-type (format nil "thoughts:~a" agent-id)))
    (broadcast-message message-string :subscription-type sub-type)))
