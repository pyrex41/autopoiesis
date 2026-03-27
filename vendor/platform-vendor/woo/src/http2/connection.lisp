(in-package :cl-user)
(defpackage woo.http2.connection
  (:use :cl
        :woo.http2.constants
        :woo.http2.frames
        :woo.http2.hpack
        :woo.http2.stream)
  (:import-from :trivial-utf-8
                :string-to-utf-8-bytes)
  (:import-from :woo.ev.socket
                :socket
                :socket-data
                :socket-open-p
                :write-socket-data
                :with-async-writing
                :close-socket)
  (:export :make-http2-connection
           :http2-connection
           :http2-connection-socket
           :http2-connection-streams
           :http2-connection-encoder-context
           :http2-connection-decoder-context
           :http2-connection-last-stream-id
           :http2-connection-goaway-sent
           :http2-connection-local-settings
           :http2-connection-remote-settings
           :http2-connection-window-size
           :connection-get-stream
           :connection-send-frame
           :connection-send-goaway
           :setup-http2-parser))
(in-package :woo.http2.connection)

(defstruct http2-connection
  "HTTP/2 connection state."
  socket
  (buffer (make-array 0 :element-type '(unsigned-byte 8)
                      :adjustable t :fill-pointer 0))
  (preface-received nil :type boolean)
  (settings-sent nil :type boolean)
  (settings-ack-received nil :type boolean)
  (encoder-context (make-hpack-context))
  (decoder-context (make-hpack-context))
  (streams (make-hash-table))
  (last-stream-id 0 :type (unsigned-byte 32))
  (next-push-stream-id 2 :type (unsigned-byte 32))  ; Server push uses even IDs
  (goaway-sent nil :type boolean)
  (goaway-received nil :type boolean)
  ;; Connection-level flow control
  (window-size +default-initial-window-size+ :type integer)
  (remote-window-size +default-initial-window-size+ :type integer)
  ;; Settings
  (local-settings `((,+settings-max-concurrent-streams+ . 100)
                    (,+settings-initial-window-size+ . ,+default-initial-window-size+)
                    (,+settings-max-frame-size+ . ,+default-max-frame-size+)
                    (,+settings-header-table-size+ . ,+default-header-table-size+)))
  (remote-settings nil)
  (remote-max-frame-size +default-max-frame-size+ :type integer)
  (remote-initial-window-size +default-initial-window-size+ :type integer)
  ;; Callbacks
  on-stream       ; (lambda (stream)) - called for new stream
  on-headers      ; (lambda (stream headers end-stream))
  on-data         ; (lambda (stream data end-stream))
  on-goaway       ; (lambda (last-stream-id error-code debug-data))
  on-error)       ; (lambda (error-code debug-data))

(defun connection-get-stream (conn stream-id &key (create nil))
  "Get stream by ID, optionally creating it if it doesn't exist."
  (let ((streams (http2-connection-streams conn)))
    (or (gethash stream-id streams)
        (when create
          (let ((stream (make-http2-stream
                         :id stream-id
                         :window-size (http2-connection-remote-initial-window-size conn))))
            (setf (gethash stream-id streams) stream)
            (when (http2-connection-on-stream conn)
              (funcall (http2-connection-on-stream conn) stream))
            stream)))))

(defun connection-send-frame (conn frame)
  "Send a frame on the connection."
  (let ((socket (http2-connection-socket conn)))
    (when (socket-open-p socket)
      (with-async-writing (socket)
        (write-socket-data socket (serialize-frame frame))))))

(defun connection-send-goaway (conn error-code &optional debug-data)
  "Send GOAWAY frame and mark connection for shutdown."
  (unless (http2-connection-goaway-sent conn)
    (setf (http2-connection-goaway-sent conn) t)
    (connection-send-frame conn
      (make-goaway-frame (http2-connection-last-stream-id conn)
                         error-code
                         debug-data))))

;;; Frame handlers

(defun handle-settings-frame (conn frame)
  "Handle received SETTINGS frame."
  (if (logbitp 0 (frame-flags frame))  ; ACK flag
      (setf (http2-connection-settings-ack-received conn) t)
      (let ((settings (parse-settings-payload (frame-payload frame))))
        ;; Store remote settings
        (dolist (setting settings)
          (let ((id (car setting))
                (value (cdr setting)))
            (push setting (http2-connection-remote-settings conn))
            ;; Handle specific settings
            (case id
              (#.+settings-header-table-size+
               (hpack-context-update-size
                (http2-connection-encoder-context conn) value))
              (#.+settings-max-frame-size+
               (setf (http2-connection-remote-max-frame-size conn) value))
              (#.+settings-initial-window-size+
               ;; Update window size for all existing streams
               (let ((delta (- value (http2-connection-remote-initial-window-size conn))))
                 (setf (http2-connection-remote-initial-window-size conn) value)
                 (maphash (lambda (id stream)
                            (declare (ignore id))
                            (incf (http2-stream-window-size stream) delta))
                          (http2-connection-streams conn)))))))
        ;; Send ACK
        (connection-send-frame conn (make-settings-ack-frame)))))

(defun handle-headers-frame (conn frame)
  "Handle received HEADERS frame."
  (let* ((stream-id (frame-stream-id frame))
         (stream (connection-get-stream conn stream-id :create t))
         (payload (frame-payload frame))
         (flags (frame-flags frame))
         (end-headers (logbitp 2 flags))  ; END_HEADERS
         (end-stream (logbitp 0 flags)))  ; END_STREAM

    ;; Handle padding if present
    (let ((header-start 0)
          (header-end (length payload)))
      (when (logbitp 3 flags)  ; PADDED
        (let ((pad-length (aref payload 0)))
          (setf header-start 1
                header-end (- header-end pad-length))))

      ;; Handle priority if present
      (when (logbitp 5 flags)  ; PRIORITY
        (incf header-start 5))

      ;; Extract header block fragment
      (let ((header-block (subseq payload header-start header-end)))
        (if end-headers
            ;; Complete header block
            (let ((headers (hpack-decode-headers
                            (http2-connection-decoder-context conn)
                            header-block)))
              (setf (http2-stream-headers stream) headers)
              (stream-transition stream :recv-headers)
              (when end-stream
                (stream-transition stream :recv-end-stream))

              ;; Update last stream ID
              (when (> stream-id (http2-connection-last-stream-id conn))
                (setf (http2-connection-last-stream-id conn) stream-id))

              ;; Extract content-length if present
              (let ((cl (cdr (assoc "content-length" headers :test #'string=))))
                (when cl
                  (setf (http2-stream-content-length stream)
                        (parse-integer cl))))

              ;; Invoke callback
              (when (http2-connection-on-headers conn)
                (funcall (http2-connection-on-headers conn)
                         stream headers end-stream)))

            ;; Incomplete - store for CONTINUATION
            (progn
              (setf (http2-stream-header-buffer stream) header-block
                    (http2-stream-awaiting-continuation stream) t)))))))

(defun handle-continuation-frame (conn frame)
  "Handle received CONTINUATION frame."
  (let* ((stream-id (frame-stream-id frame))
         (stream (gethash stream-id (http2-connection-streams conn))))
    (when (and stream (http2-stream-awaiting-continuation stream))
      (let* ((payload (frame-payload frame))
             (end-headers (logbitp 2 (frame-flags frame)))
             (old-buffer (http2-stream-header-buffer stream))
             (new-buffer (concatenate '(vector (unsigned-byte 8))
                                       old-buffer payload)))
        (if end-headers
            ;; Header block complete
            (let ((headers (hpack-decode-headers
                            (http2-connection-decoder-context conn)
                            new-buffer)))
              (setf (http2-stream-headers stream) headers
                    (http2-stream-header-buffer stream) nil
                    (http2-stream-awaiting-continuation stream) nil)
              (stream-transition stream :recv-headers)
              (when (http2-connection-on-headers conn)
                (funcall (http2-connection-on-headers conn)
                         stream headers nil)))
            ;; More continuation expected
            (setf (http2-stream-header-buffer stream) new-buffer))))))

(defun handle-data-frame (conn frame)
  "Handle received DATA frame."
  (let* ((stream-id (frame-stream-id frame))
         (stream (gethash stream-id (http2-connection-streams conn)))
         (payload (frame-payload frame))
         (flags (frame-flags frame))
         (end-stream (logbitp 0 flags)))

    (when stream
      ;; Handle padding if present
      (let ((data-start 0)
            (data-end (length payload)))
        (when (logbitp 3 flags)  ; PADDED
          (let ((pad-length (aref payload 0)))
            (setf data-start 1
                  data-end (- data-end pad-length))))

        (let ((data (subseq payload data-start data-end)))
          ;; Append to body buffer
          (let* ((buf (http2-stream-body-buffer stream))
                 (old-len (length buf))
                 (new-len (+ old-len (length data))))
            (adjust-array buf new-len :fill-pointer new-len)
            (replace buf data :start1 old-len))

          ;; Update bytes received
          (incf (http2-stream-bytes-received stream) (length data))

          (when end-stream
            (stream-transition stream :recv-end-stream))

          ;; Invoke callback
          (when (http2-connection-on-data conn)
            (funcall (http2-connection-on-data conn)
                     stream data end-stream))

          ;; Send WINDOW_UPDATE for stream and connection
          (let ((increment (length data)))
            (connection-send-frame conn
              (make-window-update-frame stream-id increment))
            (connection-send-frame conn
              (make-window-update-frame 0 increment))))))))

(defun handle-ping-frame (conn frame)
  "Handle received PING frame."
  (unless (logbitp 0 (frame-flags frame))  ; Not ACK
    (connection-send-frame conn
      (make-ping-ack-frame (frame-payload frame)))))

(defun handle-window-update-frame (conn frame)
  "Handle received WINDOW_UPDATE frame."
  (let ((increment (parse-window-update-payload (frame-payload frame))))
    (if (zerop (frame-stream-id frame))
        ;; Connection-level window update
        (incf (http2-connection-remote-window-size conn) increment)
        ;; Stream-level window update
        (let ((stream (gethash (frame-stream-id frame)
                               (http2-connection-streams conn))))
          (when stream
            (incf (http2-stream-window-size stream) increment))))))

(defun handle-rst-stream-frame (conn frame)
  "Handle received RST_STREAM frame."
  (let ((stream (gethash (frame-stream-id frame)
                         (http2-connection-streams conn))))
    (when stream
      (stream-transition stream :recv-rst))))

(defun handle-goaway-frame (conn frame)
  "Handle received GOAWAY frame."
  (setf (http2-connection-goaway-received conn) t)
  (multiple-value-bind (last-stream-id error-code debug-data)
      (parse-goaway-payload (frame-payload frame))
    (when (http2-connection-on-goaway conn)
      (funcall (http2-connection-on-goaway conn)
               last-stream-id error-code debug-data))))

(defun handle-priority-frame (conn frame)
  "Handle received PRIORITY frame (deprecated in RFC 9113, ignore)."
  (declare (ignore conn frame))
  nil)

(defun process-frame (conn frame)
  "Process a received frame by dispatching to the appropriate handler."
  (handler-case
      (case (frame-type frame)
        (#.+frame-data+ (handle-data-frame conn frame))
        (#.+frame-headers+ (handle-headers-frame conn frame))
        (#.+frame-priority+ (handle-priority-frame conn frame))
        (#.+frame-rst-stream+ (handle-rst-stream-frame conn frame))
        (#.+frame-settings+ (handle-settings-frame conn frame))
        (#.+frame-push-promise+ nil)  ; Clients don't receive PUSH_PROMISE from server
        (#.+frame-ping+ (handle-ping-frame conn frame))
        (#.+frame-goaway+ (handle-goaway-frame conn frame))
        (#.+frame-window-update+ (handle-window-update-frame conn frame))
        (#.+frame-continuation+ (handle-continuation-frame conn frame))
        (t (vom:warn "Unknown frame type: ~A" (frame-type frame))))
    (error (e)
      (vom:error "Error processing frame: ~A" e)
      (when (http2-connection-on-error conn)
        (funcall (http2-connection-on-error conn)
                 +internal-error+
                 (trivial-utf-8:string-to-utf-8-bytes (princ-to-string e)))))))

(defun parse-connection-data (conn data start end)
  "Parse incoming data on HTTP/2 connection."
  (let ((buf (http2-connection-buffer conn)))
    ;; Append new data to buffer
    (let ((old-len (length buf))
          (new-len (- end start)))
      (adjust-array buf (+ old-len new-len)
                    :fill-pointer (+ old-len new-len))
      (replace buf data :start1 old-len :start2 start :end2 end))

    ;; Check for connection preface if not yet received
    (unless (http2-connection-preface-received conn)
      (when (>= (length buf) +connection-preface-length+)
        (if (equalp (subseq buf 0 +connection-preface-length+) +connection-preface+)
            (progn
              (setf (http2-connection-preface-received conn) t)
              ;; Remove preface from buffer
              (let ((remaining (- (length buf) +connection-preface-length+)))
                (replace buf buf :start2 +connection-preface-length+)
                (setf (fill-pointer buf) remaining)))
            (progn
              ;; Invalid preface - send GOAWAY and close
              (connection-send-goaway conn +protocol-error+)
              (close-socket (http2-connection-socket conn))
              (return-from parse-connection-data)))))

    ;; Parse frames
    (loop
      (multiple-value-bind (frame consumed)
          (parse-frame buf)
        (unless frame
          (return))
        (process-frame conn frame)
        ;; Remove processed frame from buffer
        (let ((remaining (- (length buf) consumed)))
          (replace buf buf :start2 consumed)
          (setf (fill-pointer buf) remaining))))))

(defun setup-http2-parser (socket &key on-stream on-headers on-data on-goaway on-error)
  "Set up HTTP/2 handling on socket.
   Returns the connection object.

   Callbacks:
   - on-stream: (lambda (stream)) - called when new stream created
   - on-headers: (lambda (stream headers end-stream)) - called when headers received
   - on-data: (lambda (stream data end-stream)) - called when data received
   - on-goaway: (lambda (last-stream-id error-code debug-data)) - called on GOAWAY
   - on-error: (lambda (error-code debug-data)) - called on protocol errors"
  (let ((conn (make-http2-connection
               :socket socket
               :on-stream on-stream
               :on-headers on-headers
               :on-data on-data
               :on-goaway on-goaway
               :on-error on-error)))
    ;; Send server SETTINGS
    (connection-send-frame conn
      (make-settings-frame (http2-connection-local-settings conn)))
    (setf (http2-connection-settings-sent conn) t)

    ;; Install parser as socket read callback
    (setf (socket-data socket)
          (lambda (data &key (start 0) (end (length data)))
            (parse-connection-data conn data start end)))
    conn))
