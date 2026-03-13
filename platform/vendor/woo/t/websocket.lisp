(in-package :cl-user)
(defpackage woo-test.websocket
  (:use :cl :rove)
  (:import-from :woo.websocket
                :websocket-p
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
                :+opcode-pong+)
  (:import-from :trivial-utf-8
                :string-to-utf-8-bytes
                :utf-8-bytes-to-string))
(in-package :woo-test.websocket)

;;; Helper functions for testing

(defun bytes-to-list (byte-array)
  "Convert byte array to list for easier comparison."
  (coerce byte-array 'list))

(defun make-test-env (headers)
  "Create a mock environment plist for websocket-p testing."
  (let ((hash-table (make-hash-table :test 'equal)))
    (loop for (key value) on headers by #'cddr
          do (setf (gethash key hash-table) value))
    (list :request-method :GET
          :headers hash-table)))

;;; Test Suite 1: compute-accept-key - RFC 6455 Section 1.3
(deftest test-compute-accept-key
  (testing "RFC 6455 test vector"
    ;; The example from RFC 6455 Section 1.3
    (let ((client-key "dGhlIHNhbXBsZSBub25jZQ==")
          (expected "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="))
      (ok (string= (compute-accept-key client-key) expected)
          "Should produce correct accept key for RFC test vector")))

  (testing "Additional test vectors"
    ;; Additional known vectors for robustness
    (let ((key1 "x3JJHMbDL1EzLkh9GBhXDw==")
          (expected1 "HSmrc0sMlYUkAGmm5OPpG2HaGWk="))
      (ok (string= (compute-accept-key key1) expected1)
          "Should handle another valid WebSocket key")))

  (testing "Another test vector"
    (let* ((key2 "dGVzdA==")
           (result (compute-accept-key key2)))
      ;; Just verify it returns a valid base64 string
      (ok (> (length result) 0)
          "Should return non-empty result for any input")
      (ok (not (find #\Space result))
          "Result should not contain spaces")))

  (testing "Empty and edge cases"
    (let* ((empty-key "")
           (result (compute-accept-key empty-key)))
      (ok (stringp result)
          "Should handle empty string without error")
      (ok (> (length result) 0)
          "Empty key should still produce a hash"))))

;;; Test Suite 2: Opcode constants
(deftest test-opcode-constants
  (testing "Opcode values match RFC 6455 Section 5.2"
    (ok (= +opcode-continuation+ #x0)
        "Continuation opcode should be 0x0")
    (ok (= +opcode-text+ #x1)
        "Text opcode should be 0x1")
    (ok (= +opcode-binary+ #x2)
        "Binary opcode should be 0x2")
    (ok (= +opcode-close+ #x8)
        "Close opcode should be 0x8")
    (ok (= +opcode-ping+ #x9)
        "Ping opcode should be 0x9")
    (ok (= +opcode-pong+ #xA)
        "Pong opcode should be 0xA")))

;;; Test Suite 3: websocket-p detection
(deftest test-websocket-p
  (testing "Valid WebSocket upgrade request"
    (let ((env (make-test-env
                '("upgrade" "websocket"
                  "connection" "Upgrade"
                  "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ=="
                  "sec-websocket-version" "13"))))
      (ok (websocket-p env)
          "Should detect valid WebSocket upgrade request")))

  (testing "Valid with mixed-case connection header"
    (let ((env (make-test-env
                '("upgrade" "WebSocket"
                  "connection" "keep-alive, Upgrade"
                  "sec-websocket-key" "x3JJHMbDL1EzLkh9GBhXDw=="
                  "sec-websocket-version" "13"))))
      (ok (websocket-p env)
          "Should handle 'upgrade' in connection header with other values")))

  (testing "Invalid: missing upgrade header"
    (let ((env (make-test-env
                '("connection" "Upgrade"
                  "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ=="
                  "sec-websocket-version" "13"))))
      (ok (not (websocket-p env))
          "Should reject request without upgrade header")))

  (testing "Invalid: missing connection header"
    (let ((env (make-test-env
                '("upgrade" "websocket"
                  "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ=="
                  "sec-websocket-version" "13"))))
      (ok (not (websocket-p env))
          "Should reject request without connection header")))

  (testing "Invalid: missing sec-websocket-key"
    (let ((env (make-test-env
                '("upgrade" "websocket"
                  "connection" "Upgrade"
                  "sec-websocket-version" "13"))))
      (ok (not (websocket-p env))
          "Should reject request without WebSocket key")))

  (testing "Invalid: wrong WebSocket version"
    (let ((env (make-test-env
                '("upgrade" "websocket"
                  "connection" "Upgrade"
                  "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ=="
                  "sec-websocket-version" "12"))))
      (ok (not (websocket-p env))
          "Should reject request with wrong WebSocket version")))

  (testing "Invalid: wrong HTTP method"
    (let ((env (list :request-method :POST
                     :headers (make-hash-table :test 'equal))))
      (setf (gethash "upgrade" (getf env :headers)) "websocket"
            (gethash "connection" (getf env :headers)) "Upgrade"
            (gethash "sec-websocket-key" (getf env :headers)) "dGhlIHNhbXBsZSBub25jZQ=="
            (gethash "sec-websocket-version" (getf env :headers)) "13")
      (ok (not (websocket-p env))
          "Should reject non-GET requests")))

  (testing "Invalid: wrong upgrade value"
    (let ((env (make-test-env
                '("upgrade" "http/2.0"
                  "connection" "Upgrade"
                  "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ=="
                  "sec-websocket-version" "13"))))
      (ok (not (websocket-p env))
          "Should reject non-websocket upgrade"))))

;;; Test Suite 4: Frame construction via make-frame (internal symbol)
(deftest test-make-frame-small-payload
  (testing "Text frame with small payload (<126 bytes)"
    (let* ((payload (string-to-utf-8-bytes "Hello"))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (= (length frame) (+ 2 5))
          "Frame should have 2-byte header + 5-byte payload")
      ;; First byte: FIN=1, opcode=1
      (ok (= (aref frame 0) #x81)
          "First byte should be 0x81 (FIN=1, opcode=text)")
      ;; Second byte: MASK=0, length=5
      (ok (= (aref frame 1) 5)
          "Second byte should be 5 (unmasked, length=5)")
      ;; Payload
      (ok (equalp (subseq frame 2) payload)
          "Payload should match original data")))

  (testing "Binary frame with small payload"
    (let* ((payload (make-array 10 :element-type '(unsigned-byte 8)
                                :initial-contents '(1 2 3 4 5 6 7 8 9 10)))
           (frame (woo.websocket::make-frame +opcode-binary+ payload :fin t :mask nil)))
      (ok (= (length frame) 12)
          "Frame should be 2 + 10 bytes")
      (ok (= (aref frame 0) #x82)
          "First byte should be 0x82 (FIN=1, opcode=binary)")
      (ok (= (aref frame 1) 10)
          "Second byte should be 10")
      (ok (equalp (subseq frame 2) payload)
          "Binary payload should match")))

  (testing "Frame without FIN bit"
    (let* ((payload (string-to-utf-8-bytes "fragment"))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin nil :mask nil)))
      (ok (= (aref frame 0) #x01)
          "First byte should be 0x01 (FIN=0, opcode=text)")
      (ok (= (aref frame 1) 8)
          "Payload length should be 8"))))

(deftest test-make-frame-medium-payload
  (testing "Text frame with medium payload (126-65535 bytes)"
    (let* ((payload (make-array 200 :element-type '(unsigned-byte 8)
                                :initial-element (char-code #\A)))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (= (length frame) (+ 4 200))
          "Frame should have 4-byte header + 200-byte payload")
      (ok (= (aref frame 0) #x81)
          "First byte should be 0x81")
      (ok (= (aref frame 1) 126)
          "Second byte should be 126 (extended length indicator)")
      ;; Extended length in network byte order (big-endian)
      (ok (= (aref frame 2) 0)
          "Extended length high byte should be 0")
      (ok (= (aref frame 3) 200)
          "Extended length low byte should be 200")
      (ok (equalp (subseq frame 4) payload)
          "Payload should match")))

  (testing "Edge case: payload length exactly 126"
    (let* ((payload (make-array 126 :element-type '(unsigned-byte 8)
                                :initial-element 42))
           (frame (woo.websocket::make-frame +opcode-binary+ payload :fin t :mask nil)))
      (ok (= (aref frame 1) 126)
          "Should use extended length for exactly 126 bytes")
      (ok (= (length frame) (+ 4 126))
          "Total frame length should be 130")))

  (testing "Maximum medium frame: 65535 bytes"
    (let* ((payload (make-array 65535 :element-type '(unsigned-byte 8)
                                :initial-element 1))
           (frame (woo.websocket::make-frame +opcode-binary+ payload :fin t :mask nil)))
      (ok (= (aref frame 1) 126)
          "Should use 16-bit extended length")
      (ok (= (aref frame 2) 255)
          "High byte should be 255")
      (ok (= (aref frame 3) 255)
          "Low byte should be 255")
      (ok (= (length frame) (+ 4 65535))
          "Total frame length correct"))))

(deftest test-make-frame-large-payload
  (testing "Large frame (>65535 bytes) uses 64-bit length"
    (let* ((size 70000)
           (payload (make-array size :element-type '(unsigned-byte 8)
                                :initial-element 99))
           (frame (woo.websocket::make-frame +opcode-binary+ payload :fin t :mask nil)))
      (ok (= (aref frame 1) 127)
          "Second byte should be 127 (64-bit length indicator)")
      (ok (= (length frame) (+ 10 size))
          "Frame should have 10-byte header + payload")
      ;; Verify 64-bit length encoding (big-endian)
      (let ((decoded-len 0))
        (loop for i from 2 to 9
              for shift from 56 downto 0 by 8
              do (setf decoded-len (logior decoded-len
                                           (ash (aref frame i) shift))))
        (ok (= decoded-len size)
            "Decoded 64-bit length should match payload size")))))

(deftest test-make-frame-control-frames
  (testing "Ping frame"
    (let* ((payload (string-to-utf-8-bytes "ping"))
           (frame (woo.websocket::make-frame +opcode-ping+ payload :fin t :mask nil)))
      (ok (= (aref frame 0) #x89)
          "First byte should be 0x89 (FIN=1, opcode=ping)")
      (ok (= (aref frame 1) 4)
          "Payload length should be 4")))

  (testing "Pong frame"
    (let* ((payload (string-to-utf-8-bytes "pong"))
           (frame (woo.websocket::make-frame +opcode-pong+ payload :fin t :mask nil)))
      (ok (= (aref frame 0) #x8A)
          "First byte should be 0x8A (FIN=1, opcode=pong)")))

  (testing "Close frame with status code"
    (let* ((payload (make-array 2 :element-type '(unsigned-byte 8)
                                :initial-contents '(#x03 #xE8))) ; 1000 in big-endian
           (frame (woo.websocket::make-frame +opcode-close+ payload :fin t :mask nil)))
      (ok (= (aref frame 0) #x88)
          "First byte should be 0x88 (FIN=1, opcode=close)")
      (ok (= (aref frame 1) 2)
          "Payload length should be 2")
      (ok (= (aref frame 2) #x03)
          "Status code high byte")
      (ok (= (aref frame 3) #xE8)
          "Status code low byte")))

  (testing "Empty close frame"
    (let* ((payload (make-array 0 :element-type '(unsigned-byte 8)))
           (frame (woo.websocket::make-frame +opcode-close+ payload :fin t :mask nil)))
      (ok (= (length frame) 2)
          "Empty close frame should be 2 bytes")
      (ok (= (aref frame 0) #x88)
          "Should have close opcode")
      (ok (= (aref frame 1) 0)
          "Payload length should be 0"))))

(deftest test-make-frame-masking
  (testing "Client frame with masking"
    (let* ((payload (string-to-utf-8-bytes "test"))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask t)))
      (ok (= (length frame) (+ 2 4 4))
          "Masked frame should have header + mask key + payload")
      (ok (= (logand (aref frame 1) #x80) #x80)
          "MASK bit should be set in second byte")
      ;; Verify masking key exists (4 bytes)
      (ok (>= (length frame) 10)
          "Frame should contain masking key")
      ;; Payload is masked, so it won't match original
      (ok (not (equalp (subseq frame 6) payload))
          "Masked payload should differ from original"))))

;;; Test Suite 5: ws-state structure (internal)
(deftest test-ws-state-creation
  (testing "Create ws-state with defaults"
    (let ((state (woo.websocket::make-ws-state)))
      (ok (woo.websocket::ws-state-p state)
          "Should create valid ws-state")
      (ok (vectorp (woo.websocket::ws-state-buffer state))
          "Buffer should be a vector")
      (ok (= (length (woo.websocket::ws-state-buffer state)) 0)
          "Buffer should start empty")
      (ok (null (woo.websocket::ws-state-fragment-opcode state))
          "Fragment opcode should be nil")
      (ok (vectorp (woo.websocket::ws-state-fragment-buffer state))
          "Fragment buffer should be a vector")
      (ok (null (woo.websocket::ws-state-socket state))
          "Socket should be nil by default")))

  (testing "Create ws-state with callbacks"
    (let* ((msg-called nil)
           (ping-called nil)
           (state (woo.websocket::make-ws-state
                   :on-message (lambda (opcode payload)
                                 (declare (ignore opcode payload))
                                 (setf msg-called t))
                   :on-ping (lambda (payload)
                              (declare (ignore payload))
                              (setf ping-called t)))))
      (ok (functionp (woo.websocket::ws-state-on-message state))
          "on-message should be a function")
      (ok (functionp (woo.websocket::ws-state-on-ping state))
          "on-ping should be a function")
      ;; Test callback invocation
      (funcall (woo.websocket::ws-state-on-message state) +opcode-text+ #())
      (ok msg-called
          "Should be able to invoke on-message callback")
      (funcall (woo.websocket::ws-state-on-ping state) #())
      (ok ping-called
          "Should be able to invoke on-ping callback"))))

;;; Test Suite 6: Close frame payload construction
(deftest test-close-frame-construction
  (testing "Close frame with status code 1000 and reason"
    ;; This tests the helper logic that would be used in send-close
    (let* ((code 1000)
           (reason "Normal closure")
           (reason-bytes (string-to-utf-8-bytes reason))
           (payload (make-array (+ 2 (length reason-bytes))
                                :element-type '(unsigned-byte 8))))
      ;; Construct payload: 2 bytes for status code + UTF-8 reason
      (setf (aref payload 0) (ldb (byte 8 8) code)  ; High byte
            (aref payload 1) (ldb (byte 8 0) code)) ; Low byte
      (replace payload reason-bytes :start1 2)

      (ok (= (length payload) (+ 2 (length reason-bytes)))
          "Payload should be status code + reason")
      (ok (= (aref payload 0) 3)
          "High byte of 1000 should be 3")
      (ok (= (aref payload 1) 232)
          "Low byte of 1000 should be 232 (0xE8)")
      ;; Verify reason can be extracted
      (let ((extracted-reason (utf-8-bytes-to-string payload :start 2)))
        (ok (string= extracted-reason reason)
            "Should be able to extract reason from payload"))))

  (testing "Close frame with different status codes"
    (let ((test-codes '((1001 . "Going Away")
                        (1002 . "Protocol Error")
                        (1003 . "Unsupported Data")
                        (1006 . "Abnormal Closure")
                        (1008 . "Policy Violation")
                        (1011 . "Internal Error"))))
      (loop for (code . reason) in test-codes
            do (let* ((reason-bytes (string-to-utf-8-bytes reason))
                      (payload (make-array (+ 2 (length reason-bytes))
                                           :element-type '(unsigned-byte 8))))
                 (setf (aref payload 0) (ldb (byte 8 8) code)
                       (aref payload 1) (ldb (byte 8 0) code))
                 (replace payload reason-bytes :start1 2)
                 ;; Verify code can be reconstructed
                 (let ((reconstructed-code (+ (ash (aref payload 0) 8)
                                              (aref payload 1))))
                   (ok (= reconstructed-code code)
                       (format nil "Should correctly encode status code ~A" code)))))))

  (testing "Close frame with empty reason"
    (let* ((code 1000)
           (payload (make-array 2 :element-type '(unsigned-byte 8))))
      (setf (aref payload 0) (ldb (byte 8 8) code)
            (aref payload 1) (ldb (byte 8 0) code))
      (ok (= (length payload) 2)
          "Close frame with no reason should be 2 bytes")
      (ok (= (+ (ash (aref payload 0) 8) (aref payload 1)) code)
          "Should correctly encode status code"))))

;;; Test Suite 7: Edge cases and validation
(deftest test-frame-edge-cases
  (testing "Empty payload frame"
    (let* ((payload (make-array 0 :element-type '(unsigned-byte 8)))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (= (length frame) 2)
          "Empty frame should be 2 bytes (just header)")
      (ok (= (aref frame 0) #x81)
          "Should have text opcode with FIN")
      (ok (= (aref frame 1) 0)
          "Payload length should be 0")))

  (testing "Single byte payload"
    (let* ((payload (make-array 1 :element-type '(unsigned-byte 8)
                                :initial-element 65))
           (frame (woo.websocket::make-frame +opcode-binary+ payload :fin t :mask nil)))
      (ok (= (length frame) 3)
          "Single byte frame should be 3 bytes")
      (ok (= (aref frame 1) 1)
          "Payload length should be 1")
      (ok (= (aref frame 2) 65)
          "Payload byte should be preserved")))

  (testing "Payload at boundary: 125 bytes"
    (let* ((payload (make-array 125 :element-type '(unsigned-byte 8)
                                :initial-element 0))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (= (aref frame 1) 125)
          "125 bytes should use single-byte length")
      (ok (= (length frame) (+ 2 125))
          "Should not use extended length")))

  (testing "Payload at boundary: 65536 bytes"
    (let* ((payload (make-array 65536 :element-type '(unsigned-byte 8)
                                :initial-element 1))
           (frame (woo.websocket::make-frame +opcode-binary+ payload :fin t :mask nil)))
      (ok (= (aref frame 1) 127)
          "65536 bytes should use 64-bit length")
      (ok (= (length frame) (+ 10 65536))
          "Should use 64-bit extended length"))))

;;; Test Suite 8: UTF-8 handling
(deftest test-utf8-handling
  (testing "ASCII text in frames"
    (let* ((text "Hello, World!")
           (payload (string-to-utf-8-bytes text))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (string= (utf-8-bytes-to-string (subseq frame 2)) text)
          "ASCII text should round-trip correctly")))

  (testing "Unicode text in frames"
    (let* ((text "Hello, 世界! 🌍")
           (payload (string-to-utf-8-bytes text))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (> (length payload) (length text))
          "UTF-8 encoding should use multiple bytes for Unicode")
      (ok (string= (utf-8-bytes-to-string (subseq frame 2)) text)
          "Unicode text should round-trip correctly")))

  (testing "Empty string"
    (let* ((text "")
           (payload (string-to-utf-8-bytes text))
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (= (length payload) 0)
          "Empty string should produce empty payload")
      (ok (= (length frame) 2)
          "Empty text frame should be 2 bytes"))))

;;; Test Suite 9: Opcode validation
(deftest test-opcode-values
  (testing "All opcodes produce valid frames"
    (let ((opcodes (list +opcode-continuation+
                         +opcode-text+
                         +opcode-binary+
                         +opcode-close+
                         +opcode-ping+
                         +opcode-pong+))
          (payload (make-array 5 :element-type '(unsigned-byte 8)
                               :initial-element 42)))
      (loop for opcode in opcodes
            do (let ((frame (woo.websocket::make-frame opcode payload :fin t :mask nil)))
                 (ok (= (logand (aref frame 0) #x0F) opcode)
                     (format nil "Frame should have correct opcode ~X" opcode))))))

  (testing "Opcode in first byte low nibble"
    (let* ((payload #())
           (frame (woo.websocket::make-frame +opcode-text+ payload :fin t :mask nil)))
      (ok (= (logand (aref frame 0) #x0F) +opcode-text+)
          "Opcode should be in low 4 bits of first byte")
      (ok (= (logand (aref frame 0) #xF0) #x80)
          "FIN bit should be in high bit of first byte"))))
