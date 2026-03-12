;;;; connections.lisp - WebSocket connection management
;;;;
;;;; Tracks connected clients, their subscriptions, and provides
;;;; broadcast/targeted message delivery.
;;;;
;;;; Supports hybrid wire format: text frames (JSON) for control
;;;; messages, binary frames (MessagePack) for data streams.

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
   (preferred-stream-format :initarg :preferred-stream-format
                            :accessor connection-stream-format
                            :initform :msgpack
                            :type wire-format
                            :documentation "Wire format for data streams.
:msgpack (default, compact binary) or :json (for debugging).")
   (created-at :initarg :created-at
               :accessor connection-created-at
               :initform (autopoiesis.core:get-precise-time)
               :documentation "When connection was established")
   (metadata :initarg :metadata
             :accessor connection-metadata
             :initform (make-hash-table :test 'equal)
             :documentation "Arbitrary metadata about this connection")
   (send-lock :initarg :send-lock
              :accessor connection-send-lock
              :initform (bordeaux-threads:make-lock "ws-send-lock")
              :documentation "Lock serializing WebSocket frame writes"))
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
  "Send a JSON text frame to a specific connection (thread-safe)."
  (handler-case
      (bordeaux-threads:with-lock-held ((connection-send-lock connection))
        (ws-send-text (connection-ws connection) message-string))
    (error (e)
      (log:warn "Failed to send to connection ~a: ~a"
                (connection-id connection) e)
      (unregister-connection connection))))

(defun send-stream-to-connection (connection data)
  "Send a data stream message to a connection using its preferred format (thread-safe).
DATA is a hash-table or plist to be encoded."
  (handler-case
      (bordeaux-threads:with-lock-held ((connection-send-lock connection))
        (ecase (connection-stream-format connection)
          (:msgpack (ws-send-binary (connection-ws connection)
                                    (encode-stream data)))
          (:json (ws-send-text (connection-ws connection)
                               (encode-control data)))))
    (error (e)
      (log:warn "Failed to send stream to connection ~a: ~a"
                (connection-id connection) e)
      (unregister-connection connection))))

(defun broadcast-message (message-string &key subscription-type)
  "Send a JSON text frame to all connections, optionally filtered by subscription."
  ;; Snapshot connections under lock, then send outside lock to avoid blocking
  (let ((targets (bordeaux-threads:with-lock-held (*connections-lock*)
                   (loop for conn being the hash-values of *connections*
                         when (or (null subscription-type)
                                  (connection-subscribed-p conn subscription-type))
                           collect conn)))
        (dead nil))
    (dolist (conn targets)
      (handler-case
          (bordeaux-threads:with-lock-held ((connection-send-lock conn))
            (ws-send-text (connection-ws conn) message-string))
        (error (e)
          (log:warn "Broadcast send failed for ~a: ~a"
                    (connection-id conn) e)
          (push conn dead))))
    ;; Clean up dead connections
    (dolist (conn dead)
      (unregister-connection conn))))

(defun broadcast-stream-data (data &key subscription-type)
  "Send a data stream to all subscribed connections using each one's preferred format.
DATA is a hash-table or plist to be encoded per-connection."
  ;; Snapshot connections under lock, then encode and send outside lock
  (let ((targets (bordeaux-threads:with-lock-held (*connections-lock*)
                   (loop for conn being the hash-values of *connections*
                         when (or (null subscription-type)
                                  (connection-subscribed-p conn subscription-type))
                           collect conn)))
        (dead nil))
    (when targets
      ;; Pre-encode both formats lazily so we don't re-encode per connection
      (let ((msgpack-bytes nil)
            (json-string nil))
        (dolist (conn targets)
          (handler-case
              (bordeaux-threads:with-lock-held ((connection-send-lock conn))
                (ecase (connection-stream-format conn)
                  (:msgpack
                   (unless msgpack-bytes
                     (setf msgpack-bytes (encode-stream data)))
                   (ws-send-binary (connection-ws conn) msgpack-bytes))
                  (:json
                   (unless json-string
                     (setf json-string (encode-control data)))
                   (ws-send-text (connection-ws conn) json-string))))
            (error (e)
              (log:warn "Stream broadcast failed for ~a: ~a"
                        (connection-id conn) e)
              (push conn dead))))))
    ;; Clean up dead connections
    (dolist (conn dead)
      (unregister-connection conn))))

(defun broadcast-to-agent-subscribers (agent-id data)
  "Send a data stream to all connections subscribed to a specific agent's updates."
  (let ((sub-type (format nil "thoughts:~a" agent-id)))
    (broadcast-stream-data data :subscription-type sub-type)))
