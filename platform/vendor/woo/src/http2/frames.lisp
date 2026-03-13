(in-package :cl-user)
(defpackage woo.http2.frames
  (:use :cl :woo.http2.constants)
  (:export :frame
           :make-frame
           :frame-type
           :frame-flags
           :frame-stream-id
           :frame-payload
           :frame-length
           :parse-frame-header
           :parse-frame
           :serialize-frame
           :make-settings-frame
           :make-settings-ack-frame
           :make-headers-frame
           :make-data-frame
           :make-window-update-frame
           :make-ping-frame
           :make-ping-ack-frame
           :make-goaway-frame
           :make-rst-stream-frame
           :make-push-promise-frame
           :parse-settings-payload
           :parse-window-update-payload
           :parse-goaway-payload
           :parse-rst-stream-payload))
(in-package :woo.http2.frames)

(defstruct frame
  "HTTP/2 frame structure."
  (type 0 :type (unsigned-byte 8))
  (flags 0 :type (unsigned-byte 8))
  (stream-id 0 :type (unsigned-byte 32))
  (payload #() :type (simple-array (unsigned-byte 8) (*))))

(defun frame-length (frame)
  "Get the payload length of a frame."
  (length (frame-payload frame)))

(defun parse-frame-header (data &key (start 0))
  "Parse 9-byte frame header.
   Returns (values length type flags stream-id) or NIL if insufficient data."
  (when (< (- (length data) start) 9)
    (return-from parse-frame-header nil))
  (let ((length (+ (ash (aref data start) 16)
                   (ash (aref data (+ start 1)) 8)
                   (aref data (+ start 2))))
        (type (aref data (+ start 3)))
        (flags (aref data (+ start 4)))
        (stream-id (logand #x7FFFFFFF  ; Clear reserved bit
                           (+ (ash (aref data (+ start 5)) 24)
                              (ash (aref data (+ start 6)) 16)
                              (ash (aref data (+ start 7)) 8)
                              (aref data (+ start 8))))))
    (values length type flags stream-id)))

(defun parse-frame (data &key (start 0))
  "Parse complete frame from data.
   Returns (values frame bytes-consumed) or NIL if insufficient data."
  (multiple-value-bind (length type flags stream-id)
      (parse-frame-header data :start start)
    (unless length
      (return-from parse-frame nil))
    (let ((total-len (+ 9 length)))
      (when (< (- (length data) start) total-len)
        (return-from parse-frame nil))
      (let ((payload (make-array length :element-type '(unsigned-byte 8))))
        (replace payload data :start2 (+ start 9) :end2 (+ start total-len))
        (values (make-frame :type type
                            :flags flags
                            :stream-id stream-id
                            :payload payload)
                total-len)))))

(defun serialize-frame (frame)
  "Serialize frame to byte vector."
  (let* ((payload (frame-payload frame))
         (length (length payload))
         (result (make-array (+ 9 length) :element-type '(unsigned-byte 8))))
    ;; Length (24 bits, network byte order)
    (setf (aref result 0) (ldb (byte 8 16) length)
          (aref result 1) (ldb (byte 8 8) length)
          (aref result 2) (ldb (byte 8 0) length))
    ;; Type
    (setf (aref result 3) (frame-type frame))
    ;; Flags
    (setf (aref result 4) (frame-flags frame))
    ;; Stream ID (31 bits, MSB reserved)
    (let ((sid (frame-stream-id frame)))
      (setf (aref result 5) (ldb (byte 8 24) sid)
            (aref result 6) (ldb (byte 8 16) sid)
            (aref result 7) (ldb (byte 8 8) sid)
            (aref result 8) (ldb (byte 8 0) sid)))
    ;; Payload
    (when (> length 0)
      (replace result payload :start1 9))
    result))

;;; Frame constructors

(defun make-settings-frame (settings &key (ack nil) (stream-id 0))
  "Create SETTINGS frame.
   SETTINGS is an alist of (identifier . value) pairs.
   If ACK is true, creates an empty SETTINGS ACK frame."
  (declare (ignore stream-id))  ; SETTINGS must be on stream 0
  (if ack
      (make-frame :type +frame-settings+
                  :flags +flag-ack+
                  :stream-id 0
                  :payload (make-array 0 :element-type '(unsigned-byte 8)))
      (let* ((payload-len (* 6 (length settings)))
             (payload (make-array payload-len :element-type '(unsigned-byte 8)))
             (idx 0))
        (dolist (setting settings)
          (let ((id (car setting))
                (value (cdr setting)))
            ;; Identifier (16 bits)
            (setf (aref payload idx) (ldb (byte 8 8) id)
                  (aref payload (+ idx 1)) (ldb (byte 8 0) id))
            ;; Value (32 bits)
            (setf (aref payload (+ idx 2)) (ldb (byte 8 24) value)
                  (aref payload (+ idx 3)) (ldb (byte 8 16) value)
                  (aref payload (+ idx 4)) (ldb (byte 8 8) value)
                  (aref payload (+ idx 5)) (ldb (byte 8 0) value))
            (incf idx 6)))
        (make-frame :type +frame-settings+
                    :flags 0
                    :stream-id 0
                    :payload payload))))

(defun make-settings-ack-frame ()
  "Create SETTINGS ACK frame."
  (make-settings-frame nil :ack t))

(defun make-headers-frame (stream-id header-block &key (end-stream nil) (end-headers t)
                                                       (priority nil) (exclusive nil)
                                                       (stream-dependency 0) (weight 16))
  "Create HEADERS frame with encoded header block.
   HEADER-BLOCK should be HPACK-encoded bytes."
  (declare (ignore priority exclusive stream-dependency weight))
  ;; TODO: Handle PRIORITY flag and fields
  (let ((flags (logior (if end-stream +flag-end-stream+ 0)
                       (if end-headers +flag-end-headers+ 0))))
    (make-frame :type +frame-headers+
                :flags flags
                :stream-id stream-id
                :payload header-block)))

(defun make-data-frame (stream-id data &key (end-stream nil) (padded nil) (pad-length 0))
  "Create DATA frame."
  (declare (ignore padded pad-length))
  ;; TODO: Handle padding
  (let ((payload (if (typep data '(simple-array (unsigned-byte 8) (*)))
                     data
                     (coerce data '(simple-array (unsigned-byte 8) (*))))))
    (make-frame :type +frame-data+
                :flags (if end-stream +flag-end-stream+ 0)
                :stream-id stream-id
                :payload payload)))

(defun make-window-update-frame (stream-id increment)
  "Create WINDOW_UPDATE frame.
   INCREMENT must be between 1 and 2^31-1."
  (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
    ;; Window Size Increment (31 bits, MSB reserved)
    (setf (aref payload 0) (ldb (byte 8 24) increment)
          (aref payload 1) (ldb (byte 8 16) increment)
          (aref payload 2) (ldb (byte 8 8) increment)
          (aref payload 3) (ldb (byte 8 0) increment))
    (make-frame :type +frame-window-update+
                :flags 0
                :stream-id stream-id
                :payload payload)))

(defun make-ping-frame (opaque-data &key (ack nil))
  "Create PING frame.
   OPAQUE-DATA must be exactly 8 bytes."
  (assert (= (length opaque-data) 8) nil
          "PING frame opaque data must be exactly 8 bytes")
  (let ((payload (make-array 8 :element-type '(unsigned-byte 8))))
    (replace payload opaque-data)
    (make-frame :type +frame-ping+
                :flags (if ack +flag-ack+ 0)
                :stream-id 0
                :payload payload)))

(defun make-ping-ack-frame (opaque-data)
  "Create PING ACK frame with the same opaque data."
  (make-ping-frame opaque-data :ack t))

(defun make-goaway-frame (last-stream-id error-code &optional debug-data)
  "Create GOAWAY frame."
  (let* ((debug-len (if debug-data (length debug-data) 0))
         (payload (make-array (+ 8 debug-len) :element-type '(unsigned-byte 8))))
    ;; Last-Stream-ID (31 bits)
    (setf (aref payload 0) (ldb (byte 8 24) last-stream-id)
          (aref payload 1) (ldb (byte 8 16) last-stream-id)
          (aref payload 2) (ldb (byte 8 8) last-stream-id)
          (aref payload 3) (ldb (byte 8 0) last-stream-id))
    ;; Error Code (32 bits)
    (setf (aref payload 4) (ldb (byte 8 24) error-code)
          (aref payload 5) (ldb (byte 8 16) error-code)
          (aref payload 6) (ldb (byte 8 8) error-code)
          (aref payload 7) (ldb (byte 8 0) error-code))
    ;; Optional debug data
    (when debug-data
      (replace payload debug-data :start1 8))
    (make-frame :type +frame-goaway+
                :flags 0
                :stream-id 0
                :payload payload)))

(defun make-rst-stream-frame (stream-id error-code)
  "Create RST_STREAM frame."
  (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
    (setf (aref payload 0) (ldb (byte 8 24) error-code)
          (aref payload 1) (ldb (byte 8 16) error-code)
          (aref payload 2) (ldb (byte 8 8) error-code)
          (aref payload 3) (ldb (byte 8 0) error-code))
    (make-frame :type +frame-rst-stream+
                :flags 0
                :stream-id stream-id
                :payload payload)))

(defun make-push-promise-frame (stream-id promised-stream-id header-block &key (end-headers t))
  "Create PUSH_PROMISE frame."
  (let* ((header-len (length header-block))
         (payload (make-array (+ 4 header-len) :element-type '(unsigned-byte 8))))
    ;; Promised Stream ID (31 bits)
    (setf (aref payload 0) (ldb (byte 8 24) promised-stream-id)
          (aref payload 1) (ldb (byte 8 16) promised-stream-id)
          (aref payload 2) (ldb (byte 8 8) promised-stream-id)
          (aref payload 3) (ldb (byte 8 0) promised-stream-id))
    ;; Header block fragment
    (replace payload header-block :start1 4)
    (make-frame :type +frame-push-promise+
                :flags (if end-headers +flag-end-headers+ 0)
                :stream-id stream-id
                :payload payload)))

;;; Payload parsers

(defun parse-settings-payload (payload)
  "Parse SETTINGS frame payload into alist of (identifier . value)."
  (let ((settings nil)
        (len (length payload)))
    (loop for i from 0 below len by 6
          when (<= (+ i 6) len)
          do (let ((id (+ (ash (aref payload i) 8)
                          (aref payload (+ i 1))))
                   (value (+ (ash (aref payload (+ i 2)) 24)
                             (ash (aref payload (+ i 3)) 16)
                             (ash (aref payload (+ i 4)) 8)
                             (aref payload (+ i 5)))))
               (push (cons id value) settings)))
    (nreverse settings)))

(defun parse-window-update-payload (payload)
  "Parse WINDOW_UPDATE frame payload. Returns window size increment."
  (logand #x7FFFFFFF  ; Clear reserved bit
          (+ (ash (aref payload 0) 24)
             (ash (aref payload 1) 16)
             (ash (aref payload 2) 8)
             (aref payload 3))))

(defun parse-goaway-payload (payload)
  "Parse GOAWAY frame payload.
   Returns (values last-stream-id error-code debug-data)."
  (let ((last-stream-id (logand #x7FFFFFFF
                                (+ (ash (aref payload 0) 24)
                                   (ash (aref payload 1) 16)
                                   (ash (aref payload 2) 8)
                                   (aref payload 3))))
        (error-code (+ (ash (aref payload 4) 24)
                       (ash (aref payload 5) 16)
                       (ash (aref payload 6) 8)
                       (aref payload 7)))
        (debug-data (when (> (length payload) 8)
                      (subseq payload 8))))
    (values last-stream-id error-code debug-data)))

(defun parse-rst-stream-payload (payload)
  "Parse RST_STREAM frame payload. Returns error code."
  (+ (ash (aref payload 0) 24)
     (ash (aref payload 1) 16)
     (ash (aref payload 2) 8)
     (aref payload 3)))
