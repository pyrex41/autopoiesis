(in-package :cl-user)
(defpackage woo.http2.stream
  (:use :cl :woo.http2.constants)
  (:export :http2-stream
           :make-http2-stream
           :http2-stream-id
           :http2-stream-state
           :http2-stream-headers
           :http2-stream-body-buffer
           :http2-stream-window-size
           :http2-stream-content-length
           :http2-stream-bytes-received
           :http2-stream-header-buffer
           :http2-stream-awaiting-continuation
           :stream-transition
           :stream-open-p
           :stream-half-closed-remote-p
           :stream-closed-p
           :+state-idle+
           :+state-reserved-local+
           :+state-reserved-remote+
           :+state-open+
           :+state-half-closed-local+
           :+state-half-closed-remote+
           :+state-closed+))
(in-package :woo.http2.stream)

;; Stream states (RFC 9113 Section 5.1)
(defconstant +state-idle+ 0)
(defconstant +state-reserved-local+ 1)
(defconstant +state-reserved-remote+ 2)
(defconstant +state-open+ 3)
(defconstant +state-half-closed-local+ 4)
(defconstant +state-half-closed-remote+ 5)
(defconstant +state-closed+ 6)

(defstruct http2-stream
  "HTTP/2 stream state."
  (id 0 :type (unsigned-byte 32))
  (state +state-idle+ :type (unsigned-byte 8))
  (headers nil :type list)
  (body-buffer (make-array 0 :element-type '(unsigned-byte 8)
                           :adjustable t :fill-pointer 0))
  (window-size +default-initial-window-size+ :type integer)
  (content-length nil :type (or null integer))
  (bytes-received 0 :type integer)
  ;; For tracking header continuation
  (header-buffer nil)
  (awaiting-continuation nil :type boolean))

(defun stream-open-p (stream)
  "Check if stream is in open state."
  (= (http2-stream-state stream) +state-open+))

(defun stream-half-closed-remote-p (stream)
  "Check if stream is half-closed (remote)."
  (= (http2-stream-state stream) +state-half-closed-remote+))

(defun stream-closed-p (stream)
  "Check if stream is closed."
  (= (http2-stream-state stream) +state-closed+))

(defun stream-transition (stream event)
  "Transition stream state based on event.
   Returns the new state, or signals an error for invalid transitions.

   Events:
   - :send-headers - Sending HEADERS frame
   - :recv-headers - Receiving HEADERS frame
   - :send-end-stream - Sending END_STREAM flag
   - :recv-end-stream - Receiving END_STREAM flag
   - :send-push-promise - Sending PUSH_PROMISE
   - :recv-push-promise - Receiving PUSH_PROMISE
   - :send-rst - Sending RST_STREAM
   - :recv-rst - Receiving RST_STREAM"
  (let* ((old-state (http2-stream-state stream))
         (new-state
           (case event
             (:send-headers
              (case old-state
                (#.+state-idle+ +state-open+)
                (#.+state-reserved-local+ +state-half-closed-remote+)
                (t (error "Cannot send HEADERS in state ~A" old-state))))

             (:recv-headers
              (case old-state
                (#.+state-idle+ +state-open+)
                (#.+state-reserved-remote+ +state-half-closed-local+)
                (#.+state-half-closed-local+ old-state)  ; Trailing headers
                (t (error "Cannot receive HEADERS in state ~A" old-state))))

             (:send-end-stream
              (case old-state
                (#.+state-open+ +state-half-closed-local+)
                (#.+state-half-closed-remote+ +state-closed+)
                (t (error "Cannot send END_STREAM in state ~A" old-state))))

             (:recv-end-stream
              (case old-state
                (#.+state-open+ +state-half-closed-remote+)
                (#.+state-half-closed-local+ +state-closed+)
                (t (error "Cannot receive END_STREAM in state ~A" old-state))))

             (:send-push-promise
              (case old-state
                (#.+state-idle+ +state-reserved-local+)
                (t (error "Cannot send PUSH_PROMISE in state ~A" old-state))))

             (:recv-push-promise
              (case old-state
                (#.+state-idle+ +state-reserved-remote+)
                (t (error "Cannot receive PUSH_PROMISE in state ~A" old-state))))

             (:send-rst
              +state-closed+)

             (:recv-rst
              +state-closed+)

             (t (error "Unknown stream event: ~A" event)))))
    (setf (http2-stream-state stream) new-state)
    new-state))

(defun state-name (state)
  "Return human-readable name for stream state."
  (case state
    (#.+state-idle+ "idle")
    (#.+state-reserved-local+ "reserved (local)")
    (#.+state-reserved-remote+ "reserved (remote)")
    (#.+state-open+ "open")
    (#.+state-half-closed-local+ "half-closed (local)")
    (#.+state-half-closed-remote+ "half-closed (remote)")
    (#.+state-closed+ "closed")
    (t "unknown")))
