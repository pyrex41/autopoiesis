;;;; sse.lisp - Server-Sent Events for real-time event streaming
;;;;
;;;; Allows external agent systems to subscribe to a live stream
;;;; of cognitive events (decisions, actions, snapshots, etc.)

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; SSE Client Registry
;;; ===================================================================

(defvar *sse-clients* nil
  "List of active SSE client streams.")

(defvar *sse-clients-lock* (bordeaux-threads:make-lock "sse-clients-lock")
  "Lock for thread-safe SSE client list manipulation.")

(defun register-sse-client (stream)
  "Register a new SSE client stream."
  (bordeaux-threads:with-lock-held (*sse-clients-lock*)
    (push stream *sse-clients*)))

(defun unregister-sse-client (stream)
  "Remove an SSE client stream."
  (bordeaux-threads:with-lock-held (*sse-clients-lock*)
    (setf *sse-clients* (remove stream *sse-clients*))))

(defun sse-client-count ()
  "Return the number of connected SSE clients."
  (bordeaux-threads:with-lock-held (*sse-clients-lock*)
    (length *sse-clients*)))

;;; ===================================================================
;;; SSE Message Broadcasting
;;; ===================================================================

(defun format-sse-message (event-type data)
  "Format an SSE message string.
   EVENT-TYPE is the event name.
   DATA is a JSON-encodable alist."
  (with-output-to-string (out)
    (format out "event: ~a~%" event-type)
    (format out "data: ~a~%~%" (cl-json:encode-json-to-string data))))

(defun sse-broadcast (event-type data)
  "Broadcast an SSE event to all connected clients.
   Dead clients are automatically removed."
  (let ((message (format-sse-message event-type data))
        (dead-clients nil))
    (bordeaux-threads:with-lock-held (*sse-clients-lock*)
      (dolist (client *sse-clients*)
        (handler-case
            (progn
              (write-string message client)
              (force-output client))
          (error ()
            (push client dead-clients))))
      ;; Clean up dead clients
      (dolist (dead dead-clients)
        (setf *sse-clients* (remove dead *sse-clients*))))))

;;; ===================================================================
;;; SSE Event Bridge
;;; ===================================================================

(defvar *sse-event-handler* nil
  "The event handler function bridging the internal event bus to SSE.")

(defun start-sse-bridge ()
  "Wire the internal event bus to SSE broadcasting.
   All integration events will be forwarded to SSE clients."
  (when *sse-event-handler*
    (return-from start-sse-bridge nil))
  (setf *sse-event-handler*
        (lambda (event)
          (when (> (sse-client-count) 0)
            (sse-broadcast
             (string-downcase
              (string (autopoiesis.integration:integration-event-kind event)))
             (event-to-json-alist event)))))
  (autopoiesis.integration:subscribe-to-all-events *sse-event-handler*))

(defun stop-sse-bridge ()
  "Disconnect the SSE bridge from the event bus."
  (when *sse-event-handler*
    (autopoiesis.integration:unsubscribe-from-all-events *sse-event-handler*)
    (setf *sse-event-handler* nil)))

;;; ===================================================================
;;; SSE Stream Handler
;;; ===================================================================

(defun handle-sse-stream ()
  "Handle a GET /api/events request with Accept: text/event-stream.
   Keeps the connection open and streams events as they occur."
  (require-permission :read)
  ;; Set SSE headers
  (setf (hunchentoot:content-type*) "text/event-stream")
  (setf (hunchentoot:header-out :cache-control) "no-cache")
  (setf (hunchentoot:header-out :connection) "keep-alive")
  ;; Get the underlying stream
  (let ((stream (hunchentoot:send-headers)))
    ;; Send initial connection event
    (handler-case
        (progn
          (write-string (format-sse-message "connected"
                                            `((:message . "SSE connection established")
                                              (:server . "autopoiesis")))
                        stream)
          (force-output stream)
          ;; Register this client
          (register-sse-client stream)
          ;; Keep connection alive with periodic heartbeats
          (unwind-protect
               (loop
                 (sleep 30)
                 (handler-case
                     (progn
                       (write-string (format nil ": heartbeat ~a~%~%"
                                            (get-universal-time))
                                    stream)
                       (force-output stream))
                   (error ()
                     (return))))
            ;; Cleanup on disconnect
            (unregister-sse-client stream)
            (ignore-errors (close stream))))
      (error ()
        ;; Client disconnected during setup
        nil))))
