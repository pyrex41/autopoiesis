;;;; events.lisp - Real-time event streaming over WebSocket
;;;;
;;;; Bridges the integration event bus to connected WebSocket clients.
;;;; When a frontend subscribes to "events" or "events:TYPE", it receives
;;;; real-time push notifications as MessagePack binary frames (compact).

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Bridge
;;; ═══════════════════════════════════════════════════════════════════

(defvar *event-bridge-handler* nil
  "The global event handler function bridging to WebSocket.
Stored so we can unsubscribe it on shutdown.")

(defun start-event-bridge ()
  "Install a global event handler that forwards events to subscribed WebSocket clients."
  (when *event-bridge-handler*
    (stop-event-bridge))
  (setf *event-bridge-handler*
        (subscribe-to-all-events
         (lambda (event)
           (forward-event-to-subscribers event))))
  (log:info "API event bridge started"))

(defun stop-event-bridge ()
  "Remove the global event handler."
  (when *event-bridge-handler*
    (unsubscribe-from-all-events *event-bridge-handler*)
    (setf *event-bridge-handler* nil)
    (log:info "API event bridge stopped")))

(defun forward-event-to-subscribers (event)
  "Forward an integration event to all subscribed WebSocket clients.
Uses binary (MessagePack) frames for compact delivery."
  (let* ((event-type (string-downcase
                      (symbol-name (integration-event-kind event))))
         (agent-id (integration-event-agent-id event))
         (data (ok-response "event"
                            "event" (event-to-json-plist event))))
    ;; Send as data stream (binary) to subscribed connections
    (broadcast-stream data :subscription-type "events")
    (broadcast-stream data
                      :subscription-type (format nil "events:~a" event-type))
    (when agent-id
      (broadcast-stream data
                        :subscription-type (format nil "agent:~a" agent-id)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Request Notifications
;;; ═══════════════════════════════════════════════════════════════════

(defvar *blocking-poll-thread* nil
  "Thread that periodically checks for new blocking requests and pushes them.")

(defvar *blocking-notifier-running* nil
  "Flag for cooperative shutdown of the blocking notifier thread.")

(defvar *known-blocking-ids* (make-hash-table :test 'equal)
  "Track which blocking request IDs we've already notified about.")

(defun start-blocking-notifier ()
  "Start a background thread that watches for new blocking requests
and pushes them to all connected clients."
  (when *blocking-poll-thread*
    (stop-blocking-notifier))
  (setf *blocking-notifier-running* t)
  (setf *blocking-poll-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while *blocking-notifier-running*
                 do (sleep 0.25)  ; Check 4 times per second
                    (handler-case
                        (check-new-blocking-requests)
                      (error (e)
                        (log:warn "Blocking notifier error: ~a" e)))))
         :name "api-blocking-notifier"))
  (log:info "Blocking request notifier started"))

(defun stop-blocking-notifier ()
  "Stop the blocking request notifier thread."
  (setf *blocking-notifier-running* nil)
  (when (and *blocking-poll-thread*
             (bordeaux-threads:thread-alive-p *blocking-poll-thread*))
    (ignore-errors (bordeaux-threads:join-thread *blocking-poll-thread*)))
  (setf *blocking-poll-thread* nil)
  (clrhash *known-blocking-ids*)
  (log:info "Blocking request notifier stopped"))

(defun check-new-blocking-requests ()
  "Check for blocking requests we haven't notified about yet."
  (let ((pending (list-pending-blocking-requests)))
    ;; Notify about new requests
    (dolist (req pending)
      (let ((id (blocking-request-id req)))
        (unless (gethash id *known-blocking-ids*)
          (setf (gethash id *known-blocking-ids*) t)
          ;; Push as binary stream to all clients
          (broadcast-stream
           (ok-response "blocking_request"
                        "request" (blocking-request-to-json-plist req))))))
    ;; Clean up known IDs for requests that are no longer pending
    ;; (collect first, then remove -- maphash+remhash is undefined behavior)
    (let ((pending-ids (mapcar #'blocking-request-id pending))
          (stale-ids nil))
      (maphash (lambda (id _)
                 (declare (ignore _))
                 (unless (member id pending-ids :test #'equal)
                   (push id stale-ids)))
               *known-blocking-ids*)
      (dolist (id stale-ids)
        (remhash id *known-blocking-ids*)))))
