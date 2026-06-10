;;;; run-sb-api-smoke.lisp - Slice 3b-i: HTTP smoke test for /api/sb/* endpoints
;;;;
;;;; Opens a GLOBAL substrate store (so Hunchentoot handler threads see it),
;;;; seeds a sample board, starts the REST server, and exercises the product-loop
;;;; endpoints over real HTTP via dexador. Asserts the served JSON.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/api-server/scripts/run-sb-api-smoke.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis/api :silent t)

(defpackage #:sb-api-smoke (:use #:cl))
(in-package #:sb-api-smoke)

(defvar *fails* nil)
(defvar *port* 9911)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defun base () (format nil "http://127.0.0.1:~A" *port*))
(defun jget (path)
  (cl-json:decode-json-from-string (dex:get (format nil "~A~A" (base) path))))
(defun jpost (path alist)
  (cl-json:decode-json-from-string
   (dex:post (format nil "~A~A" (base) path)
             :headers '(("content-type" . "application/json"))
             :content (cl-json:encode-json-to-string alist))))

(defun run ()
  (setf *fails* nil)
  ;; GLOBAL store (handler threads have no dynamic binding to inherit)
  (autopoiesis.substrate:open-store)
  (autopoiesis.api::seed-sb-demo)
  (autopoiesis.api::start-rest-server :port *port*)
  (sleep 1.0)
  (unwind-protect
       (progn
         ;; GET /api/sb/board
         (let* ((board (jget "/api/sb/board"))
                (lanes (cdr (assoc :lanes board))))
           (check "GET /board returns lanes" (>= (length lanes) 4))
           (let ((ai-ready (find "ai-ready" lanes
                                 :key (lambda (l) (cdr (assoc :lane l))) :test #'equal)))
             (check "ai-ready lane holds the seeded ticket"
                    (find "sb-t1" (cdr (assoc :tickets ai-ready))
                          :key (lambda (tk) (cdr (assoc :id tk))) :test #'equal))))

         ;; GET /api/sb/decisions/sb-d1  (provenance)
         (let ((d (jget "/api/sb/decisions/sb-d1")))
           (check "decision resolved to lmdb"
                  (equal (cdr (assoc :resolution d)) "lmdb"))
           (check "decision retains 3 inputs"
                  (= 3 (length (cdr (assoc :inputs d)))) (cdr (assoc :inputs d)))
           (check "dissenters = (bob)"
                  (equal (cdr (assoc :dissenters d)) '("bob"))
                  (cdr (assoc :dissenters d))))

         ;; GET /api/sb/why
         (let ((why (jget "/api/sb/why")))
           (check "why-report includes the storage-backend decision"
                  (find-if (lambda (row)
                             (and (search "storage backend" (cdr (assoc :question row)))
                                  (equal (cdr (assoc :resolution row)) "lmdb")))
                           why)))

         ;; POST /api/sb/board/claim  (atomic take!)
         (let ((res (jpost "/api/sb/board/claim" '((:from . "ai-ready") (:to . "in-progress")))))
           (check "POST /board/claim atomically claimed sb-t1"
                  (equal (cdr (assoc :claimed res)) "sb-t1") res))
         (let ((res2 (jpost "/api/sb/board/claim" '((:from . "ai-ready") (:to . "in-progress")))))
           (check "second claim finds nothing (atomic)"
                  (null (cdr (assoc :claimed res2)))))

         ;; POST a fresh decision + input + resolve over HTTP
         (jpost "/api/sb/decisions" '((:name . "sb-d2") (:question . "Tabs or spaces?")))
         (jpost "/api/sb/decisions/sb-d2/input" '((:user . "x") (:text . "spaces")))
         (jpost "/api/sb/decisions/sb-d2/input" '((:user . "y") (:text . "tabs")))
         (let ((d2 (jpost "/api/sb/decisions/sb-d2/resolve"
                          '((:lead . "lead") (:resolution . "spaces")))))
           (check "HTTP-created decision resolves with dissent (y: tabs)"
                  (and (equal (cdr (assoc :resolution d2)) "spaces")
                       (equal (cdr (assoc :dissenters d2)) '("y")))
                  (cdr (assoc :dissenters d2)))))
    (ignore-errors (autopoiesis.api::stop-rest-server)))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run))
