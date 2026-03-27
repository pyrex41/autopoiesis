(in-package :cl-user)
(defpackage woo-test.http2-frames
  (:use :cl :rove)
  (:import-from :woo.http2.frames
                :frame
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
                :parse-rst-stream-payload)
  (:import-from :woo.http2.constants
                :+frame-data+
                :+frame-headers+
                :+frame-priority+
                :+frame-rst-stream+
                :+frame-settings+
                :+frame-push-promise+
                :+frame-ping+
                :+frame-goaway+
                :+frame-window-update+
                :+frame-continuation+
                :+flag-end-stream+
                :+flag-end-headers+
                :+flag-padded+
                :+flag-priority+
                :+flag-ack+
                :+settings-header-table-size+
                :+settings-enable-push+
                :+settings-max-concurrent-streams+
                :+settings-initial-window-size+
                :+settings-max-frame-size+
                :+settings-max-header-list-size+
                :+no-error+
                :+protocol-error+
                :+internal-error+
                :+flow-control-error+
                :+settings-timeout+
                :+stream-closed+
                :+frame-size-error+
                :+refused-stream+
                :+cancel+
                :+compression-error+
                :+connect-error+
                :+enhance-your-calm+
                :+inadequate-security+
                :+http-1-1-required+
                :+default-header-table-size+
                :+default-initial-window-size+
                :+default-max-frame-size+
                :+max-frame-size-limit+
                :+connection-preface+
                :+connection-preface-length+))
(in-package :woo-test.http2-frames)

;;; Helper functions for testing

(defun make-test-frame-header (length type flags stream-id)
  "Create a 9-byte frame header for testing."
  (let ((header (make-array 9 :element-type '(unsigned-byte 8))))
    ;; Length (24 bits, network byte order)
    (setf (aref header 0) (ldb (byte 8 16) length)
          (aref header 1) (ldb (byte 8 8) length)
          (aref header 2) (ldb (byte 8 0) length))
    ;; Type
    (setf (aref header 3) type)
    ;; Flags
    (setf (aref header 4) flags)
    ;; Stream ID (31 bits, MSB reserved)
    (setf (aref header 5) (ldb (byte 8 24) stream-id)
          (aref header 6) (ldb (byte 8 16) stream-id)
          (aref header 7) (ldb (byte 8 8) stream-id)
          (aref header 8) (ldb (byte 8 0) stream-id))
    header))

(defun concatenate-byte-arrays (&rest arrays)
  "Concatenate multiple byte arrays."
  (let* ((total-length (reduce #'+ arrays :key #'length))
         (result (make-array total-length :element-type '(unsigned-byte 8)))
         (pos 0))
    (dolist (arr arrays result)
      (replace result arr :start1 pos)
      (incf pos (length arr)))))

;;; Frame header parsing tests

(deftest parse-frame-header-basic
  (testing "parse-frame-header with valid 9-byte header"
    (let ((data (make-test-frame-header 16 +frame-data+ #x01 1)))
      (multiple-value-bind (length type flags stream-id)
          (parse-frame-header data)
        (ok (= length 16))
        (ok (= type +frame-data+))
        (ok (= flags #x01))
        (ok (= stream-id 1))))))

(deftest parse-frame-header-insufficient-data
  (testing "parse-frame-header with insufficient data returns NIL"
    (let ((data (make-array 8 :element-type '(unsigned-byte 8))))
      (ok (null (parse-frame-header data))))))

(deftest parse-frame-header-with-offset
  (testing "parse-frame-header with offset"
    (let ((data (concatenate-byte-arrays
                 (make-array 5 :element-type '(unsigned-byte 8) :initial-element 0)
                 (make-test-frame-header 32 +frame-settings+ #x00 0))))
      (multiple-value-bind (length type flags stream-id)
          (parse-frame-header data :start 5)
        (ok (= length 32))
        (ok (= type +frame-settings+))
        (ok (= flags #x00))
        (ok (= stream-id 0))))))

(deftest parse-frame-header-reserved-bit
  (testing "parse-frame-header clears reserved bit in stream-id"
    (let ((data (make-array 9 :element-type '(unsigned-byte 8))))
      ;; Set all bits in stream-id including reserved bit
      (setf (aref data 0) 0  ; length
            (aref data 1) 0
            (aref data 2) 10
            (aref data 3) +frame-data+  ; type
            (aref data 4) 0  ; flags
            (aref data 5) #xFF  ; stream-id with reserved bit set
            (aref data 6) #xFF
            (aref data 7) #xFF
            (aref data 8) #xFF)
      (multiple-value-bind (length type flags stream-id)
          (parse-frame-header data)
        (ok (= stream-id #x7FFFFFFF) "Reserved bit should be cleared")))))

(deftest parse-frame-header-max-values
  (testing "parse-frame-header with maximum values"
    (let ((data (make-test-frame-header #xFFFFFF +frame-goaway+ #xFF #x7FFFFFFF)))
      (multiple-value-bind (length type flags stream-id)
          (parse-frame-header data)
        (ok (= length #xFFFFFF))
        (ok (= type +frame-goaway+))
        (ok (= flags #xFF))
        (ok (= stream-id #x7FFFFFFF))))))

;;; Complete frame parsing tests

(deftest parse-frame-basic
  (testing "parse-frame with DATA frame"
    (let* ((payload (make-array 16 :element-type '(unsigned-byte 8)
                                :initial-contents '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)))
           (header (make-test-frame-header 16 +frame-data+ +flag-end-stream+ 1))
           (data (concatenate-byte-arrays header payload)))
      (multiple-value-bind (frame bytes-consumed)
          (parse-frame data)
        (ok frame)
        (ok (= bytes-consumed 25))
        (ok (= (frame-type frame) +frame-data+))
        (ok (= (frame-flags frame) +flag-end-stream+))
        (ok (= (frame-stream-id frame) 1))
        (ok (= (length (frame-payload frame)) 16))
        (ok (equalp (frame-payload frame) payload))))))

(deftest parse-frame-empty-payload
  (testing "parse-frame with empty payload"
    (let* ((header (make-test-frame-header 0 +frame-settings+ +flag-ack+ 0))
           (data header))
      (multiple-value-bind (frame bytes-consumed)
          (parse-frame data)
        (ok frame)
        (ok (= bytes-consumed 9))
        (ok (= (frame-type frame) +frame-settings+))
        (ok (= (frame-flags frame) +flag-ack+))
        (ok (= (length (frame-payload frame)) 0))))))

(deftest parse-frame-insufficient-data
  (testing "parse-frame with insufficient data for payload"
    (let* ((header (make-test-frame-header 100 +frame-data+ 0 1))
           (payload (make-array 50 :element-type '(unsigned-byte 8)))
           (data (concatenate-byte-arrays header payload)))
      (ok (null (parse-frame data))))))

(deftest parse-frame-with-offset
  (testing "parse-frame with offset"
    (let* ((payload (make-array 4 :element-type '(unsigned-byte 8) :initial-element 42))
           (header (make-test-frame-header 4 +frame-ping+ 0 0))
           (data (concatenate-byte-arrays
                  (make-array 10 :element-type '(unsigned-byte 8))
                  header
                  payload)))
      (multiple-value-bind (frame bytes-consumed)
          (parse-frame data :start 10)
        (ok frame)
        (ok (= bytes-consumed 13))
        (ok (= (frame-type frame) +frame-ping+))))))

;;; Frame serialization and roundtrip tests

(deftest serialize-frame-basic
  (testing "serialize-frame produces correct byte sequence"
    (let* ((payload (make-array 8 :element-type '(unsigned-byte 8)
                                :initial-contents '(1 2 3 4 5 6 7 8)))
           (frame (make-frame :type +frame-data+
                              :flags +flag-end-stream+
                              :stream-id 3
                              :payload payload))
           (serialized (serialize-frame frame)))
      (ok (= (length serialized) 17))
      ;; Check header
      (ok (= (aref serialized 0) 0))  ; length high byte
      (ok (= (aref serialized 1) 0))  ; length mid byte
      (ok (= (aref serialized 2) 8))  ; length low byte
      (ok (= (aref serialized 3) +frame-data+))
      (ok (= (aref serialized 4) +flag-end-stream+))
      (ok (= (aref serialized 5) 0))  ; stream-id bytes
      (ok (= (aref serialized 6) 0))
      (ok (= (aref serialized 7) 0))
      (ok (= (aref serialized 8) 3))
      ;; Check payload
      (ok (equalp (subseq serialized 9) payload)))))

(deftest serialize-frame-empty-payload
  (testing "serialize-frame with empty payload"
    (let* ((frame (make-frame :type +frame-settings+
                              :flags +flag-ack+
                              :stream-id 0
                              :payload (make-array 0 :element-type '(unsigned-byte 8))))
           (serialized (serialize-frame frame)))
      (ok (= (length serialized) 9))
      (ok (= (aref serialized 0) 0))
      (ok (= (aref serialized 1) 0))
      (ok (= (aref serialized 2) 0)))))

(deftest serialize-parse-roundtrip
  (testing "serialize and parse roundtrip"
    (let* ((original-payload (make-array 64 :element-type '(unsigned-byte 8)))
           (original-frame (make-frame :type +frame-headers+
                                       :flags (logior +flag-end-stream+ +flag-end-headers+)
                                       :stream-id 5
                                       :payload original-payload)))
      ;; Initialize payload with test data
      (dotimes (i 64)
        (setf (aref original-payload i) (mod i 256)))

      (let* ((serialized (serialize-frame original-frame))
             (parsed-frame (parse-frame serialized)))
        (ok parsed-frame)
        (ok (= (frame-type parsed-frame) (frame-type original-frame)))
        (ok (= (frame-flags parsed-frame) (frame-flags original-frame)))
        (ok (= (frame-stream-id parsed-frame) (frame-stream-id original-frame)))
        (ok (equalp (frame-payload parsed-frame) (frame-payload original-frame)))))))

;;; SETTINGS frame tests

(deftest make-settings-frame-basic
  (testing "make-settings-frame with settings list"
    (let* ((settings (list (cons +settings-header-table-size+ 4096)
                           (cons +settings-max-concurrent-streams+ 100)
                           (cons +settings-initial-window-size+ 65535)))
           (frame (make-settings-frame settings)))
      (ok (= (frame-type frame) +frame-settings+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 0))
      (ok (= (length (frame-payload frame)) 18))  ; 3 settings * 6 bytes each

      ;; Verify first setting
      (let ((payload (frame-payload frame)))
        (ok (= (+ (ash (aref payload 0) 8) (aref payload 1))
               +settings-header-table-size+))
        (ok (= (+ (ash (aref payload 2) 24)
                  (ash (aref payload 3) 16)
                  (ash (aref payload 4) 8)
                  (aref payload 5))
               4096))))))

(deftest make-settings-frame-empty
  (testing "make-settings-frame with empty settings"
    (let ((frame (make-settings-frame nil)))
      (ok (= (frame-type frame) +frame-settings+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 0))
      (ok (= (length (frame-payload frame)) 0)))))

(deftest make-settings-ack-frame
  (testing "make-settings-ack-frame"
    (let ((frame (make-settings-ack-frame)))
      (ok (= (frame-type frame) +frame-settings+))
      (ok (= (frame-flags frame) +flag-ack+))
      (ok (= (frame-stream-id frame) 0))
      (ok (= (length (frame-payload frame)) 0)))))

(deftest make-settings-frame-with-ack
  (testing "make-settings-frame with :ack t"
    (let ((frame (make-settings-frame '((1 . 100)) :ack t)))
      (ok (= (frame-type frame) +frame-settings+))
      (ok (= (frame-flags frame) +flag-ack+))
      (ok (= (frame-stream-id frame) 0))
      (ok (= (length (frame-payload frame)) 0)))))

;;; HEADERS frame tests

(deftest make-headers-frame-basic
  (testing "make-headers-frame with basic options"
    (let* ((header-block (make-array 10 :element-type '(unsigned-byte 8) :initial-element 42))
           (frame (make-headers-frame 1 header-block)))
      (ok (= (frame-type frame) +frame-headers+))
      (ok (= (frame-flags frame) +flag-end-headers+))
      (ok (= (frame-stream-id frame) 1))
      (ok (equalp (frame-payload frame) header-block)))))

(deftest make-headers-frame-with-flags
  (testing "make-headers-frame with END_STREAM and END_HEADERS"
    (let* ((header-block (make-array 5 :element-type '(unsigned-byte 8)))
           (frame (make-headers-frame 3 header-block :end-stream t :end-headers t)))
      (ok (= (frame-flags frame) (logior +flag-end-stream+ +flag-end-headers+))))))

(deftest make-headers-frame-no-end-headers
  (testing "make-headers-frame without END_HEADERS"
    (let* ((header-block (make-array 5 :element-type '(unsigned-byte 8)))
           (frame (make-headers-frame 5 header-block :end-headers nil)))
      (ok (= (frame-flags frame) 0)))))

(deftest make-headers-frame-end-stream-only
  (testing "make-headers-frame with END_STREAM only"
    (let* ((header-block (make-array 5 :element-type '(unsigned-byte 8)))
           (frame (make-headers-frame 7 header-block :end-stream t :end-headers nil)))
      (ok (= (frame-flags frame) +flag-end-stream+)))))

;;; DATA frame tests

(deftest make-data-frame-basic
  (testing "make-data-frame with byte vector"
    (let* ((data (make-array 100 :element-type '(unsigned-byte 8) :initial-element 65))
           (frame (make-data-frame 1 data)))
      (ok (= (frame-type frame) +frame-data+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 1))
      (ok (= (length (frame-payload frame)) 100))
      (ok (equalp (frame-payload frame) data)))))

(deftest make-data-frame-with-end-stream
  (testing "make-data-frame with END_STREAM flag"
    (let* ((data (make-array 50 :element-type '(unsigned-byte 8)))
           (frame (make-data-frame 3 data :end-stream t)))
      (ok (= (frame-flags frame) +flag-end-stream+)))))

(deftest make-data-frame-empty
  (testing "make-data-frame with empty data"
    (let* ((data (make-array 0 :element-type '(unsigned-byte 8)))
           (frame (make-data-frame 5 data :end-stream t)))
      (ok (= (length (frame-payload frame)) 0))
      (ok (= (frame-flags frame) +flag-end-stream+)))))

(deftest make-data-frame-coercion
  (testing "make-data-frame with list (coercion)"
    (let* ((data '(72 101 108 108 111))  ; "Hello"
           (frame (make-data-frame 7 data)))
      (ok (= (length (frame-payload frame)) 5))
      (ok (typep (frame-payload frame) '(simple-array (unsigned-byte 8) (*)))))))

;;; WINDOW_UPDATE frame tests

(deftest make-window-update-frame-basic
  (testing "make-window-update-frame"
    (let ((frame (make-window-update-frame 1 1024)))
      (ok (= (frame-type frame) +frame-window-update+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 1))
      (ok (= (length (frame-payload frame)) 4))

      ;; Verify increment value
      (let ((payload (frame-payload frame)))
        (ok (= (+ (ash (aref payload 0) 24)
                  (ash (aref payload 1) 16)
                  (ash (aref payload 2) 8)
                  (aref payload 3))
               1024))))))

(deftest make-window-update-frame-connection
  (testing "make-window-update-frame for connection (stream 0)"
    (let ((frame (make-window-update-frame 0 65536)))
      (ok (= (frame-stream-id frame) 0)))))

(deftest make-window-update-frame-max-increment
  (testing "make-window-update-frame with maximum increment"
    (let ((frame (make-window-update-frame 1 #x7FFFFFFF)))
      (let ((payload (frame-payload frame)))
        (ok (= (+ (ash (aref payload 0) 24)
                  (ash (aref payload 1) 16)
                  (ash (aref payload 2) 8)
                  (aref payload 3))
               #x7FFFFFFF))))))

;;; PING frame tests

(deftest make-ping-frame-basic
  (testing "make-ping-frame"
    (let* ((opaque-data (make-array 8 :element-type '(unsigned-byte 8)
                                    :initial-contents '(1 2 3 4 5 6 7 8)))
           (frame (make-ping-frame opaque-data)))
      (ok (= (frame-type frame) +frame-ping+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 0))
      (ok (= (length (frame-payload frame)) 8))
      (ok (equalp (frame-payload frame) opaque-data)))))

(deftest make-ping-frame-with-ack
  (testing "make-ping-frame with ACK flag"
    (let* ((opaque-data (make-array 8 :element-type '(unsigned-byte 8)
                                    :initial-element 255))
           (frame (make-ping-frame opaque-data :ack t)))
      (ok (= (frame-flags frame) +flag-ack+)))))

(deftest make-ping-ack-frame
  (testing "make-ping-ack-frame"
    (let* ((opaque-data (make-array 8 :element-type '(unsigned-byte 8)
                                    :initial-contents '(9 8 7 6 5 4 3 2)))
           (frame (make-ping-ack-frame opaque-data)))
      (ok (= (frame-type frame) +frame-ping+))
      (ok (= (frame-flags frame) +flag-ack+))
      (ok (equalp (frame-payload frame) opaque-data)))))

(deftest make-ping-frame-invalid-length
  (testing "make-ping-frame with invalid opaque data length"
    (let ((invalid-data (make-array 7 :element-type '(unsigned-byte 8))))
      (ok (signals (make-ping-frame invalid-data) 'simple-error)))))

;;; GOAWAY frame tests

(deftest make-goaway-frame-basic
  (testing "make-goaway-frame without debug data"
    (let ((frame (make-goaway-frame 10 +no-error+)))
      (ok (= (frame-type frame) +frame-goaway+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 0))
      (ok (= (length (frame-payload frame)) 8))

      (let ((payload (frame-payload frame)))
        ;; Check last-stream-id
        (ok (= (+ (ash (aref payload 0) 24)
                  (ash (aref payload 1) 16)
                  (ash (aref payload 2) 8)
                  (aref payload 3))
               10))
        ;; Check error code
        (ok (= (+ (ash (aref payload 4) 24)
                  (ash (aref payload 5) 16)
                  (ash (aref payload 6) 8)
                  (aref payload 7))
               +no-error+))))))

(deftest make-goaway-frame-with-debug-data
  (testing "make-goaway-frame with debug data"
    (let* ((debug-data (make-array 10 :element-type '(unsigned-byte 8)
                                   :initial-element 42))
           (frame (make-goaway-frame 100 +protocol-error+ debug-data)))
      (ok (= (length (frame-payload frame)) 18))

      (let ((payload (frame-payload frame)))
        ;; Check error code
        (ok (= (+ (ash (aref payload 4) 24)
                  (ash (aref payload 5) 16)
                  (ash (aref payload 6) 8)
                  (aref payload 7))
               +protocol-error+))
        ;; Check debug data
        (ok (equalp (subseq payload 8) debug-data))))))

(deftest make-goaway-frame-various-errors
  (testing "make-goaway-frame with various error codes"
    (dolist (error-code (list +no-error+ +protocol-error+ +internal-error+
                              +flow-control-error+ +cancel+))
      (let ((frame (make-goaway-frame 0 error-code)))
        (ok (= (frame-type frame) +frame-goaway+))))))

;;; RST_STREAM frame tests

(deftest make-rst-stream-frame-basic
  (testing "make-rst-stream-frame"
    (let ((frame (make-rst-stream-frame 5 +cancel+)))
      (ok (= (frame-type frame) +frame-rst-stream+))
      (ok (= (frame-flags frame) 0))
      (ok (= (frame-stream-id frame) 5))
      (ok (= (length (frame-payload frame)) 4))

      (let ((payload (frame-payload frame)))
        (ok (= (+ (ash (aref payload 0) 24)
                  (ash (aref payload 1) 16)
                  (ash (aref payload 2) 8)
                  (aref payload 3))
               +cancel+))))))

(deftest make-rst-stream-frame-various-errors
  (testing "make-rst-stream-frame with various error codes"
    (dolist (error-code (list +protocol-error+ +internal-error+ +refused-stream+
                              +stream-closed+ +compression-error+))
      (let ((frame (make-rst-stream-frame 1 error-code)))
        (ok (= (frame-type frame) +frame-rst-stream+))
        (let ((payload (frame-payload frame)))
          (ok (= (+ (ash (aref payload 0) 24)
                    (ash (aref payload 1) 16)
                    (ash (aref payload 2) 8)
                    (aref payload 3))
                 error-code)))))))

;;; Payload parser tests

(deftest parse-settings-payload-basic
  (testing "parse-settings-payload with multiple settings"
    (let* ((payload (make-array 18 :element-type '(unsigned-byte 8)))
           (settings nil))
      ;; Setting 1: HEADER_TABLE_SIZE = 8192
      (setf (aref payload 0) (ldb (byte 8 8) +settings-header-table-size+)
            (aref payload 1) (ldb (byte 8 0) +settings-header-table-size+)
            (aref payload 2) 0
            (aref payload 3) 0
            (aref payload 4) (ldb (byte 8 8) 8192)
            (aref payload 5) (ldb (byte 8 0) 8192))
      ;; Setting 2: MAX_CONCURRENT_STREAMS = 128
      (setf (aref payload 6) (ldb (byte 8 8) +settings-max-concurrent-streams+)
            (aref payload 7) (ldb (byte 8 0) +settings-max-concurrent-streams+)
            (aref payload 8) 0
            (aref payload 9) 0
            (aref payload 10) 0
            (aref payload 11) 128)
      ;; Setting 3: INITIAL_WINDOW_SIZE = 65536
      (setf (aref payload 12) (ldb (byte 8 8) +settings-initial-window-size+)
            (aref payload 13) (ldb (byte 8 0) +settings-initial-window-size+)
            (aref payload 14) 0
            (aref payload 15) 1
            (aref payload 16) 0
            (aref payload 17) 0)

      (setf settings (parse-settings-payload payload))
      (ok (= (length settings) 3))
      (ok (= (cdr (assoc +settings-header-table-size+ settings)) 8192))
      (ok (= (cdr (assoc +settings-max-concurrent-streams+ settings)) 128))
      (ok (= (cdr (assoc +settings-initial-window-size+ settings)) 65536)))))

(deftest parse-settings-payload-empty
  (testing "parse-settings-payload with empty payload"
    (let ((payload (make-array 0 :element-type '(unsigned-byte 8))))
      (ok (null (parse-settings-payload payload))))))

(deftest parse-settings-payload-incomplete
  (testing "parse-settings-payload with incomplete setting"
    (let ((payload (make-array 8 :element-type '(unsigned-byte 8))))
      ;; Only 8 bytes, not enough for 2 complete settings
      (setf (aref payload 0) 0
            (aref payload 1) 1
            (aref payload 2) 0
            (aref payload 3) 0
            (aref payload 4) 0
            (aref payload 5) 100
            (aref payload 6) 0  ; Incomplete second setting
            (aref payload 7) 2)
      (let ((settings (parse-settings-payload payload)))
        (ok (= (length settings) 1))))))

(deftest parse-window-update-payload-basic
  (testing "parse-window-update-payload"
    (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
      (setf (aref payload 0) 0
            (aref payload 1) 0
            (aref payload 2) (ldb (byte 8 8) 1024)
            (aref payload 3) (ldb (byte 8 0) 1024))
      (ok (= (parse-window-update-payload payload) 1024)))))

(deftest parse-window-update-payload-reserved-bit
  (testing "parse-window-update-payload clears reserved bit"
    (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
      ;; Set all bits including reserved bit
      (setf (aref payload 0) #xFF
            (aref payload 1) #xFF
            (aref payload 2) #xFF
            (aref payload 3) #xFF)
      (ok (= (parse-window-update-payload payload) #x7FFFFFFF)))))

(deftest parse-window-update-payload-max-value
  (testing "parse-window-update-payload with maximum increment"
    (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
      (setf (aref payload 0) #x7F
            (aref payload 1) #xFF
            (aref payload 2) #xFF
            (aref payload 3) #xFF)
      (ok (= (parse-window-update-payload payload) #x7FFFFFFF)))))

(deftest parse-goaway-payload-basic
  (testing "parse-goaway-payload without debug data"
    (let ((payload (make-array 8 :element-type '(unsigned-byte 8))))
      ;; Last-Stream-ID = 42
      (setf (aref payload 0) 0
            (aref payload 1) 0
            (aref payload 2) 0
            (aref payload 3) 42)
      ;; Error Code = PROTOCOL_ERROR
      (setf (aref payload 4) 0
            (aref payload 5) 0
            (aref payload 6) 0
            (aref payload 7) +protocol-error+)

      (multiple-value-bind (last-stream-id error-code debug-data)
          (parse-goaway-payload payload)
        (ok (= last-stream-id 42))
        (ok (= error-code +protocol-error+))
        (ok (null debug-data))))))

(deftest parse-goaway-payload-with-debug-data
  (testing "parse-goaway-payload with debug data"
    (let ((payload (make-array 20 :element-type '(unsigned-byte 8))))
      ;; Last-Stream-ID = 100
      (setf (aref payload 0) 0
            (aref payload 1) 0
            (aref payload 2) 0
            (aref payload 3) 100)
      ;; Error Code = INTERNAL_ERROR
      (setf (aref payload 4) 0
            (aref payload 5) 0
            (aref payload 6) 0
            (aref payload 7) +internal-error+)
      ;; Debug data (12 bytes)
      (dotimes (i 12)
        (setf (aref payload (+ 8 i)) (+ 65 i)))  ; A-L

      (multiple-value-bind (last-stream-id error-code debug-data)
          (parse-goaway-payload payload)
        (ok (= last-stream-id 100))
        (ok (= error-code +internal-error+))
        (ok debug-data)
        (ok (= (length debug-data) 12))
        (ok (= (aref debug-data 0) 65))
        (ok (= (aref debug-data 11) 76))))))

(deftest parse-goaway-payload-reserved-bit
  (testing "parse-goaway-payload clears reserved bit in last-stream-id"
    (let ((payload (make-array 8 :element-type '(unsigned-byte 8))))
      ;; Set reserved bit in last-stream-id
      (setf (aref payload 0) #xFF
            (aref payload 1) #xFF
            (aref payload 2) #xFF
            (aref payload 3) #xFF
            (aref payload 4) 0
            (aref payload 5) 0
            (aref payload 6) 0
            (aref payload 7) 0)

      (multiple-value-bind (last-stream-id error-code debug-data)
          (parse-goaway-payload payload)
        (ok (= last-stream-id #x7FFFFFFF))))))

(deftest parse-rst-stream-payload-basic
  (testing "parse-rst-stream-payload"
    (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
      (setf (aref payload 0) 0
            (aref payload 1) 0
            (aref payload 2) 0
            (aref payload 3) +cancel+)
      (ok (= (parse-rst-stream-payload payload) +cancel+)))))

(deftest parse-rst-stream-payload-various-errors
  (testing "parse-rst-stream-payload with various error codes"
    (dolist (error-code (list +protocol-error+ +internal-error+ +flow-control-error+
                              +refused-stream+ +compression-error+))
      (let ((payload (make-array 4 :element-type '(unsigned-byte 8))))
        (setf (aref payload 0) (ldb (byte 8 24) error-code)
              (aref payload 1) (ldb (byte 8 16) error-code)
              (aref payload 2) (ldb (byte 8 8) error-code)
              (aref payload 3) (ldb (byte 8 0) error-code))
        (ok (= (parse-rst-stream-payload payload) error-code))))))

;;; Integration tests: create, serialize, parse, verify

(deftest integration-settings-roundtrip
  (testing "SETTINGS frame complete roundtrip"
    (let* ((settings (list (cons +settings-header-table-size+ 4096)
                           (cons +settings-max-concurrent-streams+ 100)))
           (frame (make-settings-frame settings))
           (serialized (serialize-frame frame))
           (parsed-frame (parse-frame serialized))
           (parsed-settings (parse-settings-payload (frame-payload parsed-frame))))
      (ok (= (length parsed-settings) 2))
      (ok (= (cdr (assoc +settings-header-table-size+ parsed-settings)) 4096))
      (ok (= (cdr (assoc +settings-max-concurrent-streams+ parsed-settings)) 100)))))

(deftest integration-window-update-roundtrip
  (testing "WINDOW_UPDATE frame complete roundtrip"
    (let* ((frame (make-window-update-frame 3 32768))
           (serialized (serialize-frame frame))
           (parsed-frame (parse-frame serialized))
           (increment (parse-window-update-payload (frame-payload parsed-frame))))
      (ok (= increment 32768))
      (ok (= (frame-stream-id parsed-frame) 3)))))

(deftest integration-goaway-roundtrip
  (testing "GOAWAY frame complete roundtrip with debug data"
    (let* ((debug-msg (make-array 5 :element-type '(unsigned-byte 8)
                                  :initial-contents '(72 101 108 108 111)))  ; "Hello"
           (frame (make-goaway-frame 42 +protocol-error+ debug-msg))
           (serialized (serialize-frame frame))
           (parsed-frame (parse-frame serialized)))
      (multiple-value-bind (last-stream-id error-code debug-data)
          (parse-goaway-payload (frame-payload parsed-frame))
        (ok (= last-stream-id 42))
        (ok (= error-code +protocol-error+))
        (ok (equalp debug-data debug-msg))))))

(deftest integration-rst-stream-roundtrip
  (testing "RST_STREAM frame complete roundtrip"
    (let* ((frame (make-rst-stream-frame 7 +cancel+))
           (serialized (serialize-frame frame))
           (parsed-frame (parse-frame serialized))
           (error-code (parse-rst-stream-payload (frame-payload parsed-frame))))
      (ok (= error-code +cancel+))
      (ok (= (frame-stream-id parsed-frame) 7)))))
