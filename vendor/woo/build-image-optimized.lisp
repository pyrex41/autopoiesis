;; Build a highly optimized SBCL image with pre-computed responses
;; This version caches the Date header and pre-formats responses

(require :asdf)
(push (pathname "/Users/reuben/gauntlet/woo/") asdf:*central-registry*)

;; Maximum optimizations
(declaim (optimize (speed 3) (safety 0) (debug 0) (space 0)))

(format t "~%Loading Woo...~%")
(ql:quickload '(:woo :trivial-utf-8) :silent t)

;;; Monkey-patch the response generation for maximum performance

;; Cache the Date header - update every second
(defvar *cached-date* nil)
(defvar *cached-date-time* 0)

(defun woo.response::current-rfc-1123-timestamp ()
  "Cached version - only updates once per second"
  (declare (optimize (speed 3) (safety 0)))
  (let ((now (get-universal-time)))
    (when (or (null *cached-date*)
              (/= now *cached-date-time*))
      (setf *cached-date-time* now)
      (setf *cached-date* 
            (multiple-value-bind (sec minute hour day month year weekday)
                (decode-universal-time now 0)
              (format nil "~A, ~2,'0D ~A ~D ~2,'0D:~2,'0D:~2,'0D GMT"
                      (svref #("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun") weekday)
                      day
                      (svref #("" "Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec") month)
                      year hour minute sec))))
    *cached-date*))

(compile 'woo.response::current-rfc-1123-timestamp)

;; Pre-allocate response
(defvar *response-body* "Hello, World!")
(defvar *response-headers* '(:content-type "text/plain" :content-length 13))
(defvar *response* (list 200 *response-headers* (list *response-body*)))

(declaim (inline benchmark-app))
(defun benchmark-app (env)
  (declare (ignore env)
           (optimize (speed 3) (safety 0)))
  *response*)

(compile 'benchmark-app)

(defun start-benchmark-server (&optional (workers 10) (port 3000))
  (format t "~%=== Woo Optimized Benchmark Server ===~%")
  (format t "Port: ~A~%" port)
  (format t "Workers: ~A~%" workers)
  (format t "Optimizations: Date caching, pre-compiled~%")
  (format t "~%Starting server...~%~%")
  (woo:run #'benchmark-app
           :port port
           :address "127.0.0.1"
           :worker-num workers
           :debug nil
           :backlog 4096))

(compile 'start-benchmark-server)

#+sbcl (sb-ext:gc :full t)

(format t "~%Saving optimized image...~%")

#+sbcl
(sb-ext:save-lisp-and-die "woo-benchmark-opt.core"
                          :toplevel (lambda ()
                                      (start-benchmark-server 
                                       (or (ignore-errors 
                                             (parse-integer (uiop:getenv "WORKERS")))
                                           10)
                                       (or (ignore-errors 
                                             (parse-integer (uiop:getenv "PORT")))
                                           3000)))
                          :executable t
                          :compression t
                          :purify t)
