;; Build a compiled SBCL image with Woo pre-loaded
;; Run with: sbcl --load build-image.lisp

(require :asdf)

;; Add our local Woo to the path
(push (pathname "/Users/reuben/gauntlet/woo/") asdf:*central-registry*)

;; Maximum optimizations
(declaim (optimize (speed 3) (safety 0) (debug 0) (space 0)))

;; Load Woo
(format t "~%Loading Woo...~%")
(ql:quickload '(:woo) :silent nil)

;; Pre-compile everything
(format t "~%Compiling all functions...~%")

;; Force compilation of hot paths
(compile 'woo:run)

;; Pre-allocate response for benchmark
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
  (format t "~%=== Woo Benchmark Server (Compiled Image) ===~%")
  (format t "Port: ~A~%" port)
  (format t "Workers: ~A~%" workers)
  (format t "~%Starting server...~%~%")
  (woo:run #'benchmark-app
           :port port
           :address "127.0.0.1"
           :worker-num workers
           :debug nil
           :backlog 4096))

(compile 'start-benchmark-server)

;; Purify memory before saving (moves stuff to static space)
#+sbcl (sb-ext:gc :full t)

(format t "~%Saving image to woo-benchmark.core...~%")

;; Save the image
#+sbcl
(sb-ext:save-lisp-and-die "woo-benchmark.core"
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
