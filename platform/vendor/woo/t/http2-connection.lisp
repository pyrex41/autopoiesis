(in-package :cl-user)
(defpackage woo-test.http2-connection
  (:use :cl :rove)
  (:import-from :woo.http2.connection
                :make-http2-connection
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
                :connection-get-stream)
  (:import-from :woo.http2.constants
                :+connection-preface+
                :+connection-preface-length+
                :+default-initial-window-size+
                :+default-max-frame-size+
                :+default-header-table-size+
                :+max-frame-size-limit+
                :+settings-header-table-size+
                :+settings-max-concurrent-streams+
                :+settings-initial-window-size+
                :+settings-max-frame-size+)
  (:import-from :woo.http2.stream
                :http2-stream-id
                :http2-stream-state
                :http2-stream-window-size
                :+state-idle+)
  (:import-from :woo.http2.hpack
                :hpack-context-max-dynamic-table-size))
(in-package :woo-test.http2-connection)

(deftest connection-preface-constant
  (testing "Connection preface is exactly 24 bytes"
    (ok (= +connection-preface-length+ 24)))

  (testing "Connection preface has correct value (PRI * HTTP/2.0\\r\\n\\r\\nSM\\r\\n\\r\\n)"
    (ok (equalp +connection-preface+
                (make-array 24 :element-type '(unsigned-byte 8)
                            :initial-contents '(#x50 #x52 #x49 #x20 #x2a #x20 #x48 #x54
                                                #x54 #x50 #x2f #x32 #x2e #x30 #x0d #x0a
                                                #x0d #x0a #x53 #x4d #x0d #x0a #x0d #x0a))))
    ;; Verify it's "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" by checking key bytes
    (ok (= #x50 (aref +connection-preface+ 0)) "First byte is 'P'")
    (ok (= #x52 (aref +connection-preface+ 1)) "Second byte is 'R'")
    (ok (= #x49 (aref +connection-preface+ 2)) "Third byte is 'I'")
    (ok (= #x0d (aref +connection-preface+ 14)) "Contains CR")
    (ok (= #x0a (aref +connection-preface+ 15)) "Contains LF")))

(deftest connection-creation
  (testing "make-http2-connection creates connection with initial state"
    (let ((conn (make-http2-connection)))
      (ok conn "Connection object created")

      ;; Test exported accessors
      (ok (not (http2-connection-goaway-sent conn))
          "GOAWAY not sent initially")

      ;; Test stream management
      (ok (http2-connection-streams conn)
          "Streams hash table exists")
      (ok (hash-table-p (http2-connection-streams conn))
          "Streams is a hash table")
      (ok (= 0 (hash-table-count (http2-connection-streams conn)))
          "No streams initially")

      ;; Test stream ID tracking
      (ok (= 0 (http2-connection-last-stream-id conn))
          "Last stream ID starts at 0"))))

(deftest connection-flow-control
  (testing "Connection has correct initial flow control window sizes"
    (let ((conn (make-http2-connection)))
      (ok (= +default-initial-window-size+
             (http2-connection-window-size conn))
          "Local window size is default (65535)"))))

(deftest connection-local-settings
  (testing "Connection has correct local settings"
    (let ((conn (make-http2-connection)))
      (let ((settings (http2-connection-local-settings conn)))
        (ok settings "Local settings exist")
        (ok (listp settings) "Settings is a list")

        ;; Check for required settings
        (let ((max-concurrent (cdr (assoc +settings-max-concurrent-streams+ settings)))
              (initial-window (cdr (assoc +settings-initial-window-size+ settings)))
              (max-frame-size (cdr (assoc +settings-max-frame-size+ settings)))
              (header-table-size (cdr (assoc +settings-header-table-size+ settings))))

          (ok (= 100 max-concurrent)
              "Max concurrent streams is 100")
          (ok (= +default-initial-window-size+ initial-window)
              "Initial window size matches default")
          (ok (= +default-max-frame-size+ max-frame-size)
              "Max frame size matches default")
          (ok (= +default-header-table-size+ header-table-size)
              "Header table size matches default"))))))

(deftest connection-remote-settings
  (testing "Connection starts with nil remote settings"
    (let ((conn (make-http2-connection)))
      (ok (null (http2-connection-remote-settings conn))
          "Remote settings initially nil (not received yet)"))))

(deftest connection-hpack-contexts
  (testing "Connection initializes HPACK encoder and decoder contexts"
    (let ((conn (make-http2-connection)))
      ;; Test encoder context
      (ok (http2-connection-encoder-context conn)
          "Encoder context exists")
      (ok (woo.http2.hpack::hpack-context-p
           (http2-connection-encoder-context conn))
          "Encoder is an HPACK context")
      (ok (= +default-header-table-size+
             (hpack-context-max-dynamic-table-size
              (http2-connection-encoder-context conn)))
          "Encoder has correct max table size")

      ;; Test decoder context
      (ok (http2-connection-decoder-context conn)
          "Decoder context exists")
      (ok (woo.http2.hpack::hpack-context-p
           (http2-connection-decoder-context conn))
          "Decoder is an HPACK context")
      (ok (= +default-header-table-size+
             (hpack-context-max-dynamic-table-size
              (http2-connection-decoder-context conn)))
          "Decoder has correct max table size")

      ;; Verify they are separate instances
      (ok (not (eq (http2-connection-encoder-context conn)
                   (http2-connection-decoder-context conn)))
          "Encoder and decoder are separate contexts"))))

(deftest stream-management-get-without-create
  (testing "connection-get-stream without :create returns nil for non-existent stream"
    (let ((conn (make-http2-connection)))
      (ok (null (connection-get-stream conn 1))
          "Non-existent stream returns nil")
      (ok (null (connection-get-stream conn 3))
          "Another non-existent stream returns nil")
      (ok (= 0 (hash-table-count (http2-connection-streams conn)))
          "No streams were created"))))

(deftest stream-management-get-with-create
  (testing "connection-get-stream with :create creates new stream"
    (let ((conn (make-http2-connection)))
      (let ((stream (connection-get-stream conn 1 :create t)))
        (ok stream "Stream was created")
        (ok (woo.http2.stream::http2-stream-p stream) "Result is an http2-stream")
        (ok (= 1 (http2-stream-id stream)) "Stream has correct ID")
        (ok (= +state-idle+ (http2-stream-state stream))
            "New stream is in idle state")
        (ok (= +default-initial-window-size+
               (http2-stream-window-size stream))
            "Stream has default window size")
        (ok (= 1 (hash-table-count (http2-connection-streams conn)))
            "Stream was added to connection"))))

  (testing "connection-get-stream returns existing stream on second call"
    (let ((conn (make-http2-connection)))
      (let ((stream1 (connection-get-stream conn 3 :create t))
            (stream2 (connection-get-stream conn 3)))
        (ok (eq stream1 stream2)
            "Same stream object returned")
        (ok (= 1 (hash-table-count (http2-connection-streams conn)))
            "No duplicate streams created"))))

  (testing "connection-get-stream creates multiple streams with different IDs"
    (let ((conn (make-http2-connection)))
      (let ((stream1 (connection-get-stream conn 1 :create t))
            (stream3 (connection-get-stream conn 3 :create t))
            (stream5 (connection-get-stream conn 5 :create t)))
        (ok (not (eq stream1 stream3))
            "Different stream objects")
        (ok (not (eq stream1 stream5))
            "Different stream objects")
        (ok (not (eq stream3 stream5))
            "Different stream objects")
        (ok (= 1 (http2-stream-id stream1)) "Stream 1 has ID 1")
        (ok (= 3 (http2-stream-id stream3)) "Stream 3 has ID 3")
        (ok (= 5 (http2-stream-id stream5)) "Stream 5 has ID 5")
        (ok (= 3 (hash-table-count (http2-connection-streams conn)))
            "Three streams in connection")))))

(deftest stream-management-with-callback
  (testing "connection-get-stream calls on-stream callback when creating"
    (let ((conn (make-http2-connection))
          (callback-called nil)
          (callback-stream nil))
      ;; Set the callback (internal accessor)
      (setf (woo.http2.connection::http2-connection-on-stream conn)
            (lambda (stream)
              (setf callback-called t
                    callback-stream stream)))

      ;; Create a stream
      (let ((stream (connection-get-stream conn 7 :create t)))
        (ok callback-called "Callback was invoked")
        (ok (eq stream callback-stream)
            "Callback received the correct stream"))))

  (testing "connection-get-stream doesn't call callback for existing stream"
    (let ((conn (make-http2-connection))
          (callback-count 0))
      ;; Set the callback (internal accessor)
      (setf (woo.http2.connection::http2-connection-on-stream conn)
            (lambda (stream)
              (declare (ignore stream))
              (incf callback-count)))

      ;; Create stream first time
      (connection-get-stream conn 9 :create t)
      (ok (= 1 callback-count) "Callback called once on creation")

      ;; Get existing stream
      (connection-get-stream conn 9)
      (ok (= 1 callback-count) "Callback not called for existing stream")

      ;; Try to get with :create again
      (connection-get-stream conn 9 :create t)
      (ok (= 1 callback-count) "Callback still only called once"))))

(deftest stream-window-size-inheritance
  (testing "New streams inherit window size from connection"
    (let ((conn (make-http2-connection)))
      ;; Create a new stream - it should get default window size
      (let ((stream (connection-get-stream conn 1 :create t)))
        (ok (= +default-initial-window-size+ (http2-stream-window-size stream))
            "Stream gets default window size")))))

(deftest connection-callbacks
  (testing "Connection callback slots can be set"
    (let ((conn (make-http2-connection))
          (on-stream-fn (lambda (s) (declare (ignore s)) nil)))

      (setf (woo.http2.connection::http2-connection-on-stream conn) on-stream-fn)

      (ok (eq on-stream-fn (woo.http2.connection::http2-connection-on-stream conn))
          "on-stream callback set"))))

(deftest connection-socket
  (testing "Connection socket can be set and retrieved"
    (let ((conn (make-http2-connection))
          (mock-socket "mock-socket-object"))
      (setf (http2-connection-socket conn) mock-socket)
      (ok (equal mock-socket (http2-connection-socket conn))
          "Socket value preserved"))))

(deftest constants-verification
  (testing "HTTP/2 constants have correct values"
    ;; Verify settings constants match expected values
    (ok (= 1 +settings-header-table-size+)
        "SETTINGS_HEADER_TABLE_SIZE = 0x1")
    (ok (= 3 +settings-max-concurrent-streams+)
        "SETTINGS_MAX_CONCURRENT_STREAMS = 0x3")
    (ok (= 4 +settings-initial-window-size+)
        "SETTINGS_INITIAL_WINDOW_SIZE = 0x4")
    (ok (= 5 +settings-max-frame-size+)
        "SETTINGS_MAX_FRAME_SIZE = 0x5")

    ;; Verify default values
    (ok (= 4096 +default-header-table-size+)
        "Default header table size is 4096")
    (ok (= 65535 +default-initial-window-size+)
        "Default window size is 65535")
    (ok (= 16384 +default-max-frame-size+)
        "Default frame size is 16384")
    (ok (= 16777215 +max-frame-size-limit+)
        "Max frame size limit is 2^24 - 1")))

(deftest connection-state-flags
  (testing "Connection state flags are independently settable"
    (let ((conn (make-http2-connection)))
      ;; Test goaway-sent flag (which is exported)
      (ok (not (http2-connection-goaway-sent conn))
          "GOAWAY sent initially false")

      ;; Set goaway-sent (using internal setter)
      (setf (woo.http2.connection::http2-connection-goaway-sent conn) t)
      (ok (http2-connection-goaway-sent conn)
          "GOAWAY sent flag can be set"))))
