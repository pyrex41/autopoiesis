(in-package :cl-user)
(defpackage woo-test.http2-stream
  (:use :cl :rove)
  (:import-from :woo.http2.stream
                ;; Struct and accessors
                :http2-stream
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
                ;; Functions
                :stream-transition
                :stream-open-p
                :stream-half-closed-remote-p
                :stream-closed-p
                ;; State constants
                :+state-idle+
                :+state-reserved-local+
                :+state-reserved-remote+
                :+state-open+
                :+state-half-closed-local+
                :+state-half-closed-remote+
                :+state-closed+)
  (:import-from :woo.http2.constants
                :+default-initial-window-size+))
(in-package :woo-test.http2-stream)

;;; Stream Creation Tests

(deftest make-http2-stream-test
  (testing "Stream creation with default values"
    (let ((stream (make-http2-stream :id 1)))
      (ok (= (http2-stream-id stream) 1))
      (ok (= (http2-stream-state stream) +state-idle+))
      (ok (null (http2-stream-headers stream)))
      (ok (= (http2-stream-window-size stream) +default-initial-window-size+))
      (ok (null (http2-stream-content-length stream)))
      (ok (= (http2-stream-bytes-received stream) 0))
      (ok (null (http2-stream-header-buffer stream)))
      (ok (null (http2-stream-awaiting-continuation stream)))))

  (testing "Stream creation with custom window size"
    (let ((stream (make-http2-stream :id 3 :window-size 32768)))
      (ok (= (http2-stream-id stream) 3))
      (ok (= (http2-stream-window-size stream) 32768)))))

;;; State Predicate Tests

(deftest stream-state-predicates-test
  (testing "stream-open-p predicate"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (stream-open-p stream)))
    (let ((stream (make-http2-stream :id 1 :state +state-idle+)))
      (ok (not (stream-open-p stream)))))

  (testing "stream-half-closed-remote-p predicate"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-remote+)))
      (ok (stream-half-closed-remote-p stream)))
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (not (stream-half-closed-remote-p stream)))))

  (testing "stream-closed-p predicate"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (stream-closed-p stream)))
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (not (stream-closed-p stream))))))

;;; State Transition Tests - RFC 9113 Section 5.1

(deftest idle-to-open-transitions-test
  (testing "idle -> open via send-headers"
    (let ((stream (make-http2-stream :id 1)))
      (ok (= (http2-stream-state stream) +state-idle+))
      (stream-transition stream :send-headers)
      (ok (= (http2-stream-state stream) +state-open+))
      (ok (stream-open-p stream))))

  (testing "idle -> open via recv-headers"
    (let ((stream (make-http2-stream :id 2)))
      (ok (= (http2-stream-state stream) +state-idle+))
      (stream-transition stream :recv-headers)
      (ok (= (http2-stream-state stream) +state-open+))
      (ok (stream-open-p stream)))))

(deftest open-to-half-closed-transitions-test
  (testing "open -> half-closed-local via send-end-stream"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (stream-transition stream :send-end-stream)
      (ok (= (http2-stream-state stream) +state-half-closed-local+))))

  (testing "open -> half-closed-remote via recv-end-stream"
    (let ((stream (make-http2-stream :id 2 :state +state-open+)))
      (stream-transition stream :recv-end-stream)
      (ok (= (http2-stream-state stream) +state-half-closed-remote+))
      (ok (stream-half-closed-remote-p stream)))))

(deftest half-closed-to-closed-transitions-test
  (testing "half-closed-local -> closed via recv-end-stream"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-local+)))
      (stream-transition stream :recv-end-stream)
      (ok (= (http2-stream-state stream) +state-closed+))
      (ok (stream-closed-p stream))))

  (testing "half-closed-remote -> closed via send-end-stream"
    (let ((stream (make-http2-stream :id 2 :state +state-half-closed-remote+)))
      (stream-transition stream :send-end-stream)
      (ok (= (http2-stream-state stream) +state-closed+))
      (ok (stream-closed-p stream)))))

(deftest rst-stream-transitions-test
  (testing "idle -> closed via send-rst"
    (let ((stream (make-http2-stream :id 1 :state +state-idle+)))
      (stream-transition stream :send-rst)
      (ok (stream-closed-p stream))))

  (testing "open -> closed via send-rst"
    (let ((stream (make-http2-stream :id 2 :state +state-open+)))
      (stream-transition stream :send-rst)
      (ok (stream-closed-p stream))))

  (testing "half-closed-local -> closed via recv-rst"
    (let ((stream (make-http2-stream :id 3 :state +state-half-closed-local+)))
      (stream-transition stream :recv-rst)
      (ok (stream-closed-p stream))))

  (testing "half-closed-remote -> closed via send-rst"
    (let ((stream (make-http2-stream :id 4 :state +state-half-closed-remote+)))
      (stream-transition stream :send-rst)
      (ok (stream-closed-p stream)))))

(deftest push-promise-transitions-test
  (testing "idle -> reserved-local via send-push-promise"
    (let ((stream (make-http2-stream :id 2)))
      (ok (= (http2-stream-state stream) +state-idle+))
      (stream-transition stream :send-push-promise)
      (ok (= (http2-stream-state stream) +state-reserved-local+))))

  (testing "idle -> reserved-remote via recv-push-promise"
    (let ((stream (make-http2-stream :id 4)))
      (ok (= (http2-stream-state stream) +state-idle+))
      (stream-transition stream :recv-push-promise)
      (ok (= (http2-stream-state stream) +state-reserved-remote+)))))

(deftest reserved-to-half-closed-transitions-test
  (testing "reserved-local -> half-closed-remote via send-headers"
    (let ((stream (make-http2-stream :id 2 :state +state-reserved-local+)))
      (stream-transition stream :send-headers)
      (ok (= (http2-stream-state stream) +state-half-closed-remote+))
      (ok (stream-half-closed-remote-p stream))))

  (testing "reserved-remote -> half-closed-local via recv-headers"
    (let ((stream (make-http2-stream :id 4 :state +state-reserved-remote+)))
      (stream-transition stream :recv-headers)
      (ok (= (http2-stream-state stream) +state-half-closed-local+)))))

(deftest trailing-headers-test
  (testing "half-closed-local can receive trailing headers"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-local+)))
      (stream-transition stream :recv-headers)
      ;; State should remain half-closed-local
      (ok (= (http2-stream-state stream) +state-half-closed-local+)))))

;;; Invalid Transition Tests

(deftest invalid-send-headers-transitions-test
  (testing "Cannot send HEADERS from open state"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (signals (stream-transition stream :send-headers) 'error))))

  (testing "Cannot send HEADERS from half-closed-local state"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-local+)))
      (ok (signals (stream-transition stream :send-headers) 'error))))

  (testing "Cannot send HEADERS from half-closed-remote state"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-remote+)))
      (ok (signals (stream-transition stream :send-headers) 'error))))

  (testing "Cannot send HEADERS from closed state"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (signals (stream-transition stream :send-headers) 'error)))))

(deftest invalid-recv-headers-transitions-test
  (testing "Cannot receive HEADERS from open state"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (signals (stream-transition stream :recv-headers) 'error))))

  (testing "Cannot receive HEADERS from half-closed-remote state"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-remote+)))
      (ok (signals (stream-transition stream :recv-headers) 'error))))

  (testing "Cannot receive HEADERS from closed state"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (signals (stream-transition stream :recv-headers) 'error)))))

(deftest invalid-send-end-stream-transitions-test
  (testing "Cannot send END_STREAM from idle state"
    (let ((stream (make-http2-stream :id 1 :state +state-idle+)))
      (ok (signals (stream-transition stream :send-end-stream) 'error))))

  (testing "Cannot send END_STREAM from half-closed-local state"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-local+)))
      (ok (signals (stream-transition stream :send-end-stream) 'error))))

  (testing "Cannot send END_STREAM from closed state"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (signals (stream-transition stream :send-end-stream) 'error)))))

(deftest invalid-recv-end-stream-transitions-test
  (testing "Cannot receive END_STREAM from idle state"
    (let ((stream (make-http2-stream :id 1 :state +state-idle+)))
      (ok (signals (stream-transition stream :recv-end-stream) 'error))))

  (testing "Cannot receive END_STREAM from half-closed-remote state"
    (let ((stream (make-http2-stream :id 1 :state +state-half-closed-remote+)))
      (ok (signals (stream-transition stream :recv-end-stream) 'error))))

  (testing "Cannot receive END_STREAM from closed state"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (signals (stream-transition stream :recv-end-stream) 'error)))))

(deftest invalid-push-promise-transitions-test
  (testing "Cannot send PUSH_PROMISE from open state"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (signals (stream-transition stream :send-push-promise) 'error))))

  (testing "Cannot send PUSH_PROMISE from closed state"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (signals (stream-transition stream :send-push-promise) 'error))))

  (testing "Cannot receive PUSH_PROMISE from open state"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (ok (signals (stream-transition stream :recv-push-promise) 'error))))

  (testing "Cannot receive PUSH_PROMISE from closed state"
    (let ((stream (make-http2-stream :id 1 :state +state-closed+)))
      (ok (signals (stream-transition stream :recv-push-promise) 'error)))))

(deftest unknown-event-test
  (testing "Unknown event signals error"
    (let ((stream (make-http2-stream :id 1)))
      (ok (signals (stream-transition stream :invalid-event) 'error)))))

;;; Complete State Machine Flow Tests

(deftest complete-request-flow-test
  (testing "Complete client-initiated request: idle -> open -> half-closed-local -> closed"
    (let ((stream (make-http2-stream :id 1)))
      ;; Client sends HEADERS
      (stream-transition stream :send-headers)
      (ok (stream-open-p stream))
      ;; Client sends END_STREAM
      (stream-transition stream :send-end-stream)
      (ok (= (http2-stream-state stream) +state-half-closed-local+))
      ;; Server sends response with END_STREAM
      (stream-transition stream :recv-end-stream)
      (ok (stream-closed-p stream)))))

(deftest complete-server-response-flow-test
  (testing "Complete server response: idle -> open -> half-closed-remote -> closed"
    (let ((stream (make-http2-stream :id 1)))
      ;; Server receives HEADERS with END_STREAM
      (stream-transition stream :recv-headers)
      (ok (stream-open-p stream))
      (stream-transition stream :recv-end-stream)
      (ok (stream-half-closed-remote-p stream))
      ;; Server sends response with END_STREAM
      (stream-transition stream :send-end-stream)
      (ok (stream-closed-p stream)))))

(deftest server-push-flow-test
  (testing "Server push flow: idle -> reserved-local -> half-closed-remote -> closed"
    (let ((stream (make-http2-stream :id 2)))
      ;; Server sends PUSH_PROMISE
      (stream-transition stream :send-push-promise)
      (ok (= (http2-stream-state stream) +state-reserved-local+))
      ;; Server sends HEADERS
      (stream-transition stream :send-headers)
      (ok (stream-half-closed-remote-p stream))
      ;; Server sends END_STREAM
      (stream-transition stream :send-end-stream)
      (ok (stream-closed-p stream)))))

(deftest client-push-flow-test
  (testing "Client receiving push: idle -> reserved-remote -> half-closed-local -> closed"
    (let ((stream (make-http2-stream :id 2)))
      ;; Client receives PUSH_PROMISE
      (stream-transition stream :recv-push-promise)
      (ok (= (http2-stream-state stream) +state-reserved-remote+))
      ;; Client receives HEADERS
      (stream-transition stream :recv-headers)
      (ok (= (http2-stream-state stream) +state-half-closed-local+))
      ;; Client receives END_STREAM
      (stream-transition stream :recv-end-stream)
      (ok (stream-closed-p stream)))))

;;; Window Size Tests

(deftest window-size-tracking-test
  (testing "Initial window size is default"
    (let ((stream (make-http2-stream :id 1)))
      (ok (= (http2-stream-window-size stream) +default-initial-window-size+))))

  (testing "Window size can be updated"
    (let ((stream (make-http2-stream :id 1)))
      (setf (http2-stream-window-size stream) 32768)
      (ok (= (http2-stream-window-size stream) 32768))))

  (testing "Window size can be decreased"
    (let ((stream (make-http2-stream :id 1)))
      (setf (http2-stream-window-size stream)
            (- (http2-stream-window-size stream) 1024))
      (ok (= (http2-stream-window-size stream) (- +default-initial-window-size+ 1024)))))

  (testing "Window size can go negative (flow control violation)"
    (let ((stream (make-http2-stream :id 1)))
      (setf (http2-stream-window-size stream) -100)
      (ok (= (http2-stream-window-size stream) -100)))))

;;; Body Buffer Tests

(deftest body-buffer-operations-test
  (testing "Body buffer is initially empty"
    (let ((stream (make-http2-stream :id 1)))
      (ok (= (length (http2-stream-body-buffer stream)) 0))))

  (testing "Can append data to body buffer"
    (let ((stream (make-http2-stream :id 1))
          (data (make-array 10 :element-type '(unsigned-byte 8)
                           :initial-contents '(1 2 3 4 5 6 7 8 9 10))))
      (let ((buffer (http2-stream-body-buffer stream)))
        (loop for byte across data
              do (vector-push-extend byte buffer))
        (ok (= (length (http2-stream-body-buffer stream)) 10))
        (ok (equalp (http2-stream-body-buffer stream) data)))))

  (testing "Can append multiple chunks to body buffer"
    (let ((stream (make-http2-stream :id 1))
          (chunk1 (make-array 5 :element-type '(unsigned-byte 8)
                             :initial-contents '(1 2 3 4 5)))
          (chunk2 (make-array 3 :element-type '(unsigned-byte 8)
                             :initial-contents '(6 7 8))))
      (let ((buffer (http2-stream-body-buffer stream)))
        ;; Append first chunk
        (loop for byte across chunk1
              do (vector-push-extend byte buffer))
        ;; Append second chunk
        (loop for byte across chunk2
              do (vector-push-extend byte buffer))
        (ok (= (length (http2-stream-body-buffer stream)) 8))
        (ok (= (aref (http2-stream-body-buffer stream) 0) 1))
        (ok (= (aref (http2-stream-body-buffer stream) 4) 5))
        (ok (= (aref (http2-stream-body-buffer stream) 7) 8))))))

;;; Content Length and Bytes Received Tests

(deftest content-length-tracking-test
  (testing "Content length is initially nil"
    (let ((stream (make-http2-stream :id 1)))
      (ok (null (http2-stream-content-length stream)))))

  (testing "Can set content length"
    (let ((stream (make-http2-stream :id 1)))
      (setf (http2-stream-content-length stream) 1024)
      (ok (= (http2-stream-content-length stream) 1024)))))

(deftest bytes-received-tracking-test
  (testing "Bytes received is initially zero"
    (let ((stream (make-http2-stream :id 1)))
      (ok (= (http2-stream-bytes-received stream) 0))))

  (testing "Can increment bytes received"
    (let ((stream (make-http2-stream :id 1)))
      (incf (http2-stream-bytes-received stream) 512)
      (ok (= (http2-stream-bytes-received stream) 512))
      (incf (http2-stream-bytes-received stream) 256)
      (ok (= (http2-stream-bytes-received stream) 768)))))

;;; Header Continuation Tests

(deftest header-continuation-tracking-test
  (testing "Header buffer is initially nil"
    (let ((stream (make-http2-stream :id 1)))
      (ok (null (http2-stream-header-buffer stream)))))

  (testing "Awaiting continuation is initially nil"
    (let ((stream (make-http2-stream :id 1)))
      (ok (null (http2-stream-awaiting-continuation stream)))))

  (testing "Can set header continuation state"
    (let ((stream (make-http2-stream :id 1)))
      (setf (http2-stream-header-buffer stream) (list :header-fragments))
      (setf (http2-stream-awaiting-continuation stream) t)
      (ok (http2-stream-header-buffer stream))
      (ok (http2-stream-awaiting-continuation stream)))))

;;; Headers Storage Tests

(deftest headers-storage-test
  (testing "Headers list is initially empty"
    (let ((stream (make-http2-stream :id 1)))
      (ok (null (http2-stream-headers stream)))))

  (testing "Can store headers"
    (let ((stream (make-http2-stream :id 1)))
      (setf (http2-stream-headers stream)
            '((:method . "GET")
              (:path . "/index.html")
              (:scheme . "https")
              (:authority . "example.com")))
      (ok (= (length (http2-stream-headers stream)) 4))
      (ok (equal (assoc :method (http2-stream-headers stream)) '(:method . "GET")))
      (ok (equal (assoc :path (http2-stream-headers stream)) '(:path . "/index.html"))))))

;;; Edge Cases and Error Conditions

(deftest multiple-rst-stream-test
  (testing "Multiple RST_STREAM transitions keep stream closed"
    (let ((stream (make-http2-stream :id 1 :state +state-open+)))
      (stream-transition stream :send-rst)
      (ok (stream-closed-p stream))
      ;; Sending another RST should keep it closed
      (stream-transition stream :send-rst)
      (ok (stream-closed-p stream)))))

(deftest state-transitions-sequence-test
  (testing "Complex state transition sequence"
    (let ((stream (make-http2-stream :id 1)))
      ;; Start in idle
      (ok (= (http2-stream-state stream) +state-idle+))
      ;; Transition to open
      (stream-transition stream :recv-headers)
      (ok (stream-open-p stream))
      ;; Transition to half-closed-remote
      (stream-transition stream :recv-end-stream)
      (ok (stream-half-closed-remote-p stream))
      ;; Transition to closed
      (stream-transition stream :send-end-stream)
      (ok (stream-closed-p stream)))))

(deftest stream-id-values-test
  (testing "Stream ID can be any valid 32-bit unsigned integer"
    (let ((stream1 (make-http2-stream :id 1)))
      (ok (= (http2-stream-id stream1) 1)))
    (let ((stream2 (make-http2-stream :id 2147483647)))
      (ok (= (http2-stream-id stream2) 2147483647)))))
