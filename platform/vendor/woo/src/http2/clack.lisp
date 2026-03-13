(in-package :cl-user)
(defpackage woo.http2.clack
  (:use :cl
        :woo.http2.constants
        :woo.http2.frames
        :woo.http2.hpack
        :woo.http2.stream
        :woo.http2.connection)
  (:import-from :woo.ev.socket
                :socket
                :socket-remote-addr
                :socket-remote-port
                :socket-open-p)
  (:import-from :trivial-utf-8
                :string-to-utf-8-bytes)
  (:export :make-http2-app-handler
           :build-clack-env
           :send-http2-response))
(in-package :woo.http2.clack)

(defun pseudo-header-p (name)
  "Check if header name is a pseudo-header (starts with :)."
  (and (stringp name)
       (> (length name) 0)
       (char= (char name 0) #\:)))

(defun build-clack-env (socket stream headers)
  "Build Clack environment from HTTP/2 stream headers."
  (let ((env (list :clack.streaming t
                   :clack.nonblocking t
                   :clack.io socket
                   :http2.stream stream
                   :http2.connection nil  ; Will be set by caller
                   :server-protocol :HTTP/2
                   :script-name ""
                   :remote-addr (socket-remote-addr socket)
                   :remote-port (socket-remote-port socket)))
        (http-headers (make-hash-table :test 'equal)))

    (dolist (header headers)
      (let ((name (car header))
            (value (cdr header)))
        (cond
          ;; Pseudo-headers
          ((string= name ":method")
           (setf (getf env :request-method)
                 (intern (string-upcase value) :keyword)))
          ((string= name ":path")
           (let* ((path value)
                  (query-pos (position #\? path)))
             (if query-pos
                 (setf (getf env :path-info) (quri:url-decode (subseq path 0 query-pos) :lenient t)
                       (getf env :query-string) (subseq path (1+ query-pos))
                       (getf env :request-uri) path)
                 (setf (getf env :path-info) (quri:url-decode path :lenient t)
                       (getf env :request-uri) path))))
          ((string= name ":scheme")
           (setf (getf env :url-scheme) value))
          ((string= name ":authority")
           (let ((colon-pos (position #\: value :from-end t)))
             (if (and colon-pos (> colon-pos 0))
                 (setf (getf env :server-name) (subseq value 0 colon-pos)
                       (getf env :server-port) (parse-integer value :start (1+ colon-pos)))
                 (setf (getf env :server-name) value))))
          ;; Regular headers
          ((string= name "content-type")
           (setf (getf env :content-type) value))
          ((string= name "content-length")
           (setf (getf env :content-length) (parse-integer value)))
          ((string= name "host")
           ;; :authority takes precedence, but use host as fallback
           (unless (getf env :server-name)
             (let ((colon-pos (position #\: value :from-end t)))
               (if (and colon-pos (> colon-pos 0))
                   (setf (getf env :server-name) (subseq value 0 colon-pos)
                         (getf env :server-port) (parse-integer value :start (1+ colon-pos)))
                   (setf (getf env :server-name) value)))))
          ;; Skip other pseudo-headers, store regular headers
          ((not (pseudo-header-p name))
           (setf (gethash name http-headers) value)))))

    ;; Set defaults
    (unless (getf env :server-port)
      (setf (getf env :server-port)
            (if (string= (getf env :url-scheme) "https") 443 80)))
    (unless (getf env :path-info)
      (setf (getf env :path-info) "/"))
    (unless (getf env :request-uri)
      (setf (getf env :request-uri) (getf env :path-info)))

    (setf (getf env :headers) http-headers)
    env))

(defun send-http2-response (conn stream status headers body)
  "Send HTTP/2 response on stream.
   HEADERS should be a plist of header names to values.
   BODY can be nil, a byte vector, a string, or a list of strings/vectors."
  (let* ((status-str (write-to-string status))
         (response-headers (list (cons ":status" status-str))))

    ;; Convert headers plist to alist
    (loop for (name value) on headers by #'cddr
          when value
          do (let ((name-str (etypecase name
                               (string name)
                               (keyword (string-downcase (symbol-name name)))
                               (symbol (string-downcase (symbol-name name))))))
               (push (cons name-str (princ-to-string value)) response-headers)))

    (setf response-headers (nreverse response-headers))

    ;; Encode headers
    (let ((header-block (hpack-encode-headers
                         (http2-connection-encoder-context conn)
                         response-headers)))

      ;; Determine if we have a body
      (let ((has-body (and body
                           (etypecase body
                             ((vector (unsigned-byte 8)) (> (length body) 0))
                             (string (> (length body) 0))
                             (list (> (length body) 0))
                             (null nil)))))

        ;; Send HEADERS frame
        (connection-send-frame conn
          (make-headers-frame (http2-stream-id stream) header-block
                              :end-headers t
                              :end-stream (not has-body)))

        ;; Send DATA frames if body present
        (when has-body
          (etypecase body
            ((vector (unsigned-byte 8))
             (connection-send-frame conn
               (make-data-frame (http2-stream-id stream) body :end-stream t)))
            (string
             (let ((bytes (string-to-utf-8-bytes body)))
               (connection-send-frame conn
                 (make-data-frame (http2-stream-id stream) bytes :end-stream t))))
            (list
             (let ((remaining (copy-list body)))
               (loop while remaining
                     for chunk = (pop remaining)
                     for data = (etypecase chunk
                                  (string (string-to-utf-8-bytes chunk))
                                  ((vector (unsigned-byte 8)) chunk)
                                  (null nil))
                     when data
                     do (connection-send-frame conn
                          (make-data-frame (http2-stream-id stream) data
                                           :end-stream (null remaining))))))))))))

(defun make-http2-app-handler (app)
  "Create HTTP/2 connection handler that invokes Clack app for each request.
   Returns a function that takes a socket and sets up HTTP/2 handling."
  (lambda (socket)
    (let ((conn nil))
      (setf conn
            (setup-http2-parser
             socket
             :on-headers
             (lambda (stream headers end-stream)
               (let ((env (build-clack-env socket stream headers)))
                 ;; Store connection reference in env
                 (setf (getf env :http2.connection) conn)

                 ;; If end-stream, request is complete (no body)
                 (when end-stream
                   (setf (getf env :raw-body) nil)
                   (handler-case
                       (let ((response (funcall app env)))
                         (when (and (listp response) (socket-open-p socket))
                           (destructuring-bind (status resp-headers &optional body) response
                             (send-http2-response conn stream status resp-headers body))))
                     (error (e)
                       (vom:error "Error in HTTP/2 app handler: ~A" e)
                       (when (socket-open-p socket)
                         (send-http2-response conn stream 500
                                              '(:content-type "text/plain")
                                              "Internal Server Error")))))))

             :on-data
             (lambda (stream data end-stream)
               (declare (ignore data))
               (when end-stream
                 ;; Full request body received, invoke app
                 (let* ((env (build-clack-env socket stream (http2-stream-headers stream)))
                        (body (http2-stream-body-buffer stream)))
                   (setf (getf env :http2.connection) conn
                         (getf env :raw-body) (if (> (length body) 0) body nil))
                   (handler-case
                       (let ((response (funcall app env)))
                         (when (and (listp response) (socket-open-p socket))
                           (destructuring-bind (status resp-headers &optional resp-body) response
                             (send-http2-response conn stream status resp-headers resp-body))))
                     (error (e)
                       (vom:error "Error in HTTP/2 app handler: ~A" e)
                       (when (socket-open-p socket)
                         (send-http2-response conn stream 500
                                              '(:content-type "text/plain")
                                              "Internal Server Error")))))))

             :on-goaway
             (lambda (last-stream-id error-code debug-data)
               (declare (ignore last-stream-id debug-data))
               (vom:info "Received GOAWAY with error code ~A" error-code))

             :on-error
             (lambda (error-code debug-data)
               (vom:error "HTTP/2 protocol error ~A: ~A"
                          error-code
                          (when debug-data
                            (trivial-utf-8:utf-8-bytes-to-string debug-data)))))))))
