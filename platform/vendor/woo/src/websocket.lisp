(in-package :cl-user)
(defpackage woo.websocket
  (:use :cl)
  (:import-from :woo.ev.socket
                :socket
                :socket-data
                :socket-read-cb
                :socket-fd
                :socket-open-p
                :write-socket-data
                :write-socket-byte
                :with-async-writing
                :close-socket)
  (:import-from :woo.response
                :write-socket-string
                :write-socket-crlf)
  (:import-from :trivial-utf-8
                :string-to-utf-8-bytes
                :utf-8-bytes-to-string)
  (:export :websocket-p
           :compute-accept-key
           :setup-websocket
           :send-text-frame
           :send-binary-frame
           :send-ping
           :send-pong
           :send-close
           :write-websocket-upgrade-response
           :+opcode-continuation+
           :+opcode-text+
           :+opcode-binary+
           :+opcode-close+
           :+opcode-ping+
           :+opcode-pong+))
(in-package :woo.websocket)

;; WebSocket opcodes (RFC 6455 Section 5.2)
(defconstant +opcode-continuation+ #x0)
(defconstant +opcode-text+ #x1)
(defconstant +opcode-binary+ #x2)
(defconstant +opcode-close+ #x8)
(defconstant +opcode-ping+ #x9)
(defconstant +opcode-pong+ #xA)

;; RFC 6455 magic GUID
(defvar *websocket-guid* "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")

(defun websocket-p (env)
  "Check if request is a WebSocket upgrade request."
  (and (eq (getf env :request-method) :GET)
       (let ((headers (getf env :headers)))
         (and (string-equal (gethash "upgrade" headers) "websocket")
              (search "upgrade" (string-downcase (or (gethash "connection" headers) "")))
              (gethash "sec-websocket-key" headers)
              (string= (gethash "sec-websocket-version" headers) "13")))))

(defun compute-accept-key (client-key)
  "Compute Sec-WebSocket-Accept from client's Sec-WebSocket-Key."
  (let* ((concat (concatenate 'string client-key *websocket-guid*))
         (sha1-bytes (ironclad:digest-sequence :sha1
                       (string-to-utf-8-bytes concat))))
    (cl-base64:usb8-array-to-base64-string sha1-bytes)))

(defstruct ws-state
  "WebSocket connection state."
  (buffer (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
  (fragment-opcode nil)
  (fragment-buffer (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
  socket
  on-message    ; (lambda (opcode payload))
  on-ping       ; (lambda (payload))
  on-pong       ; (lambda (payload))
  on-close      ; (lambda (code reason))
  on-error)     ; (lambda (error))

(defun make-frame (opcode payload &key (fin t) (mask nil))
  "Construct a WebSocket frame as byte vector.
   Servers MUST NOT mask frames sent to clients (RFC 6455 Section 5.1)."
  (let* ((payload-len (length payload))
         (extended-len (cond ((< payload-len 126) 0)
                             ((< payload-len 65536) 2)
                             (t 8)))
         (frame-len (+ 2 extended-len (if mask 4 0) payload-len))
         (frame (make-array frame-len :element-type '(unsigned-byte 8)))
         (idx 0))
    ;; First byte: FIN + opcode
    (setf (aref frame idx) (logior (if fin #x80 0) (logand opcode #x0F)))
    (incf idx)
    ;; Second byte: MASK + payload length
    (setf (aref frame idx)
          (logior (if mask #x80 0)
                  (cond ((< payload-len 126) payload-len)
                        ((< payload-len 65536) 126)
                        (t 127))))
    (incf idx)
    ;; Extended payload length (network byte order)
    (case extended-len
      (2 (setf (aref frame idx) (ldb (byte 8 8) payload-len)
               (aref frame (1+ idx)) (ldb (byte 8 0) payload-len))
         (incf idx 2))
      (8 (loop for i from 7 downto 0
               do (setf (aref frame idx) (ldb (byte 8 (* i 8)) payload-len))
                  (incf idx))))
    ;; Masking key (servers don't mask, but included for completeness)
    (when mask
      (let ((mask-key (make-array 4 :element-type '(unsigned-byte 8))))
        (dotimes (i 4)
          (setf (aref mask-key i) (random 256)
                (aref frame idx) (aref mask-key i))
          (incf idx))
        ;; Apply mask to payload
        (dotimes (i payload-len)
          (setf (aref frame idx) (logxor (aref payload i) (aref mask-key (mod i 4))))
          (incf idx))))
    ;; Unmasked payload
    (unless mask
      (replace frame payload :start1 idx))
    frame))

(defun parse-frame (state)
  "Parse WebSocket frame from state buffer.
   Returns T if a complete frame was processed, NIL if more data needed."
  (let* ((buf (ws-state-buffer state))
         (buf-len (length buf)))

    ;; Need at least 2 bytes for minimal frame header
    (when (< buf-len 2)
      (return-from parse-frame nil))

    (let* ((byte0 (aref buf 0))
           (byte1 (aref buf 1))
           (fin (logbitp 7 byte0))
           (opcode (logand byte0 #x0F))
           (masked (logbitp 7 byte1))
           (payload-len (logand byte1 #x7F))
           (header-len 2))

      ;; Extended payload length
      (cond
        ((= payload-len 126)
         (when (< buf-len 4)
           (return-from parse-frame nil))
         (setf payload-len (+ (ash (aref buf 2) 8) (aref buf 3))
               header-len 4))
        ((= payload-len 127)
         (when (< buf-len 10)
           (return-from parse-frame nil))
         (setf payload-len (loop for i from 2 to 9
                                 for shift from 56 downto 0 by 8
                                 sum (ash (aref buf i) shift))
               header-len 10)))

      ;; Masking key (clients MUST mask, servers expect it)
      (when masked
        (incf header-len 4))

      (let ((frame-len (+ header-len payload-len)))
        (when (< buf-len frame-len)
          (return-from parse-frame nil))

        ;; Extract and unmask payload
        (let ((payload (make-array payload-len :element-type '(unsigned-byte 8))))
          (if masked
              (let ((mask-start (- header-len 4)))
                (dotimes (i payload-len)
                  (setf (aref payload i)
                        (logxor (aref buf (+ header-len i))
                                (aref buf (+ mask-start (mod i 4)))))))
              (replace payload buf :start2 header-len))

          ;; Handle frame based on opcode
          (cond
            ;; Control frames (ping, pong, close)
            ((= opcode +opcode-ping+)
             (when (ws-state-on-ping state)
               (funcall (ws-state-on-ping state) payload)))
            ((= opcode +opcode-pong+)
             (when (ws-state-on-pong state)
               (funcall (ws-state-on-pong state) payload)))
            ((= opcode +opcode-close+)
             (let ((code (if (>= payload-len 2)
                             (+ (ash (aref payload 0) 8) (aref payload 1))
                             1000))
                   (reason (if (> payload-len 2)
                               (utf-8-bytes-to-string payload :start 2)
                               "")))
               (when (ws-state-on-close state)
                 (funcall (ws-state-on-close state) code reason))))
            ;; Data frames (continuation, text, binary)
            ((= opcode +opcode-continuation+)
             (let ((frag-buf (ws-state-fragment-buffer state))
                   (old-len (length (ws-state-fragment-buffer state))))
               (adjust-array frag-buf (+ old-len payload-len)
                             :fill-pointer (+ old-len payload-len))
               (replace frag-buf payload :start1 old-len))
             (when fin
               (when (ws-state-on-message state)
                 (funcall (ws-state-on-message state)
                          (ws-state-fragment-opcode state)
                          (ws-state-fragment-buffer state)))
               (setf (fill-pointer (ws-state-fragment-buffer state)) 0
                     (ws-state-fragment-opcode state) nil)))
            ((or (= opcode +opcode-text+) (= opcode +opcode-binary+))
             (if fin
                 ;; Complete message in single frame
                 (when (ws-state-on-message state)
                   (funcall (ws-state-on-message state) opcode payload))
                 ;; Start of fragmented message
                 (progn
                   (setf (ws-state-fragment-opcode state) opcode)
                   (let ((frag-buf (ws-state-fragment-buffer state)))
                     (adjust-array frag-buf payload-len :fill-pointer payload-len)
                     (replace frag-buf payload))))))

          ;; Remove processed frame from buffer
          (let ((remaining (- buf-len frame-len)))
            (if (zerop remaining)
                (setf (fill-pointer buf) 0)
                (progn
                  (replace buf buf :start2 frame-len)
                  (setf (fill-pointer buf) remaining))))

          t)))))

(defun send-frame (socket opcode payload)
  "Send a WebSocket frame over socket."
  (let ((frame (make-frame opcode payload)))
    (with-async-writing (socket)
      (write-socket-data socket frame))))

(defun send-text-frame (socket text)
  "Send a text frame."
  (send-frame socket +opcode-text+
              (string-to-utf-8-bytes text)))

(defun send-binary-frame (socket data)
  "Send a binary frame."
  (send-frame socket +opcode-binary+ data))

(defun send-ping (socket &optional (payload #()))
  "Send a ping frame."
  (send-frame socket +opcode-ping+ payload))

(defun send-pong (socket payload)
  "Send a pong frame."
  (send-frame socket +opcode-pong+ payload))

(defun send-close (socket &optional (code 1000) (reason ""))
  "Send a close frame."
  (let* ((reason-bytes (string-to-utf-8-bytes reason))
         (payload (make-array (+ 2 (length reason-bytes))
                              :element-type '(unsigned-byte 8))))
    (setf (aref payload 0) (ldb (byte 8 8) code)
          (aref payload 1) (ldb (byte 8 0) code))
    (replace payload reason-bytes :start1 2)
    (send-frame socket +opcode-close+ payload)))

(defun setup-websocket (socket &key on-message on-ping on-pong on-close on-error)
  "Set up WebSocket handling on an upgraded socket.
   Returns the ws-state object.

   Callbacks:
   - on-message: (lambda (opcode payload)) - called for text/binary messages
   - on-ping: (lambda (payload)) - called for ping frames (default: auto-pong)
   - on-pong: (lambda (payload)) - called for pong frames
   - on-close: (lambda (code reason)) - called for close frames (default: echo close)
   - on-error: (lambda (error)) - called on parse errors"
  (let ((state (make-ws-state
                :socket socket
                :on-message on-message
                :on-ping (or on-ping
                             (lambda (payload)
                               (send-pong socket payload)))
                :on-pong on-pong
                :on-close (or on-close
                              (lambda (code reason)
                                (declare (ignore reason))
                                (send-close socket code)
                                (close-socket socket)))
                :on-error on-error)))
    ;; Replace socket's data with our state and install frame parser
    (setf (socket-data socket)
          (lambda (data &key (start 0) (end (length data)))
            (handler-case
                (let ((buf (ws-state-buffer state))
                      (new-len (- end start)))
                  ;; Append new data to buffer
                  (let ((old-len (length buf)))
                    (adjust-array buf (+ old-len new-len)
                                  :fill-pointer (+ old-len new-len))
                    (replace buf data :start1 old-len :start2 start :end2 end))
                  ;; Parse as many complete frames as possible
                  (loop while (parse-frame state)))
              (error (e)
                (when (ws-state-on-error state)
                  (funcall (ws-state-on-error state) e))))))
    state))

(defun write-websocket-upgrade-response (socket accept-key &optional extra-headers)
  "Write a 101 Switching Protocols response for WebSocket upgrade.
   EXTRA-HEADERS is a plist of additional headers to include."
  (with-async-writing (socket)
    (write-socket-string socket "HTTP/1.1 101 Switching Protocols")
    (write-socket-crlf socket)
    (write-socket-string socket "Upgrade: websocket")
    (write-socket-crlf socket)
    (write-socket-string socket "Connection: Upgrade")
    (write-socket-crlf socket)
    (write-socket-string socket "Sec-WebSocket-Accept: ")
    (write-socket-string socket accept-key)
    (write-socket-crlf socket)
    ;; Extra headers (e.g., Sec-WebSocket-Protocol)
    (loop for (k v) on extra-headers by #'cddr
          when v
          do (write-socket-string socket (format nil "~:(~A~): ~A" k v))
             (write-socket-crlf socket))
    (write-socket-crlf socket)))
