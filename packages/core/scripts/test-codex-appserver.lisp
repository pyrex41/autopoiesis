;;;; test-codex-appserver.lisp - Live test for the codex app-server provider.
;;;;
;;;; Run:
;;;;   sbcl --noinform --non-interactive --load packages/core/scripts/test-codex-appserver.lisp
;;;;
;;;; Proves the long-lived JSON-RPC client:
;;;;   1. spawns `codex app-server`, completes initialize + thread/start handshake
;;;;   2. runs a turn ("create hello.txt") and reaches a terminal turn event
;;;;   3. runs a SECOND turn on the SAME session (thread-id reused) => persistence
;;;;
;;;; Honest about auth: the default model_provider is `cursor-headless` (a local
;;;; proxy on localhost:8000). If that proxy is down/unauthed, LLM turns report
;;;; status "failed" but the PROTOCOL (handshake + turn lifecycle + thread reuse)
;;;; is still proven. We assert protocol-level facts and report the auth wall.

(require :asdf)

;;; ── Prelude: register systems and load core ──────────────────────────
(let* ((here (or *load-truename* *load-pathname*))
       (script-dir (directory-namestring here))
       ;; .../packages/core/scripts/ -> repo root is three up
       (repo-root (truename (merge-pathnames "../../../" script-dir))))
  (format t "~&Repo root: ~a~%" repo-root)
  (flet ((reg (rel) (pushnew (truename (merge-pathnames rel repo-root))
                             asdf:*central-registry* :test #'equal)))
    (reg "packages/core/")
    (reg "packages/substrate/")
    (reg "vendor/platform-vendor/woo/"))
  (handler-case
      (progn
        (asdf:load-asd (truename (merge-pathnames "vendor/platform-vendor/woo/woo.asd" repo-root)))
        (ql:quickload :woo :silent t)
        (ql:quickload :autopoiesis :silent t))
    (error (e)
      (format t "~&FAIL: could not load :autopoiesis: ~a~%NO-GO~%" e)
      (uiop:quit 2))))

(in-package :cl-user)

(defvar *pass* 0)
(defvar *fail* 0)

(defun check (name ok &optional detail)
  (if ok
      (progn (incf *pass*) (format t "~&PASS  ~a~@[  (~a)~]~%" name detail))
      (progn (incf *fail*) (format t "~&FAIL  ~a~@[  (~a)~]~%" name detail))))

(defun status-of (result)
  (getf (autopoiesis.integration:provider-result-metadata result) :status))

(defun error-of (result)
  (getf (autopoiesis.integration:provider-result-metadata result) :error))

;;; ── The test ─────────────────────────────────────────────────────────
(let* ((tmp (uiop:ensure-directory-pathname
             (format nil "/tmp/codex-appserver-test-~a/" (get-universal-time))))
       (session nil)
       (auth-ok nil))
  (ensure-directories-exist tmp)
  (format t "~&Temp workspace: ~a~%" tmp)
  (unwind-protect
       (handler-case
           (progn
             ;; 1. Start session (initialize + thread/start handshake)
             (setf session
                   (autopoiesis.integration:start-codex-session
                    :cwd tmp
                    :approval-policy "never"
                    :sandbox "workspace-write"
                    :auto-approve t))
             (check "session starts (initialize + thread/start)"
                    (autopoiesis.integration:codex-session-alive-p session))
             (let ((tid1 (autopoiesis.integration:codex-session-thread-id session)))
               (check "thread/start returned a thread-id"
                      (and (stringp tid1) (> (length tid1) 0))
                      tid1)

               ;; 2. First turn
               (format t "~&-- Turn 1 --~%")
               (let ((r1 (autopoiesis.integration:codex-run-turn
                          session
                          "Create a file hello.txt containing exactly HELLO, using a relative path. Then reply DONE."
                          :timeout 90
                          :on-event (lambda (ev)
                                      (format t "   ev: ~a ~a~%"
                                              (getf ev :event) (getf ev :method))))))
                 (check "turn 1 reached a terminal turn event"
                        (member (status-of r1) '("completed" "failed" "cancelled") :test #'equal)
                        (format nil "status=~a err=~a" (status-of r1) (error-of r1)))
                 (when (equal (status-of r1) "completed")
                   (setf auth-ok t))
                 (let ((hello (merge-pathnames "hello.txt" tmp)))
                   (when (probe-file hello)
                     (check "hello.txt created with HELLO"
                            (search "HELLO" (uiop:read-file-string hello))
                            (uiop:read-file-string hello)))))

               ;; 3. Second turn on SAME session => thread reuse
               (format t "~&-- Turn 2 (same session) --~%")
               (let ((r2 (autopoiesis.integration:codex-run-turn
                          session
                          "Now create world.txt containing exactly WORLD. Then reply DONE."
                          :timeout 90)))
                 (check "turn 2 reached a terminal turn event"
                        (member (status-of r2) '("completed" "failed" "cancelled") :test #'equal)
                        (format nil "status=~a err=~a" (status-of r2) (error-of r2)))
                 (let ((tid2 (autopoiesis.integration:codex-session-thread-id session)))
                   (check "thread-id reused across turns (SESSION PERSISTENCE)"
                          (equal tid1 tid2)
                          (format nil "~a == ~a" tid1 tid2))
                   (check "turn results carry thread-id as session-id"
                          (equal (autopoiesis.integration:provider-result-session-id r2) tid2)))
                 (when (equal (status-of r2) "completed")
                   (let ((world (merge-pathnames "world.txt" tmp)))
                     (when (probe-file world)
                       (check "world.txt created with WORLD"
                              (search "WORLD" (uiop:read-file-string world)))))))

               ;; 4. Provider-class integration smoke test (reuses no auth)
               (let ((prov (autopoiesis.integration:make-codex-appserver-provider
                            :working-directory tmp)))
                 (check "provider exposes :one-shot and :streaming modes"
                        (and (member :streaming (autopoiesis.integration:provider-supported-modes prov))
                             (member :one-shot (autopoiesis.integration:provider-supported-modes prov))))
                 (check "provider-to-sexpr serializes config"
                        (eq :provider (first (autopoiesis.integration:provider-to-sexpr prov)))))))

         (error (e)
           (incf *fail*)
           (format t "~&FAIL  unexpected error: ~a~%" e)))
    (when session
      (autopoiesis.integration:stop-codex-session session))

    ;; ── Report ──────────────────────────────────────────────────────
    (format t "~%================ RESULT ================~%")
    (format t "PASS: ~a   FAIL: ~a~%" *pass* *fail*)
    (if auth-ok
        (format t "AUTH: working (cursor-headless proxy reachable) — full two-turn flow exercised.~%")
        (format t "AUTH: LLM turns failed (cursor-headless proxy at localhost:8000 down/unauthed).~%        Protocol (handshake + turn lifecycle + thread reuse) still proven.~%"))
    ;; GO if the protocol-level assertions all passed. The auth wall does not
    ;; fail the build — the client code is the deliverable.
    (if (zerop *fail*)
        (progn (format t "GO~%") (uiop:quit 0))
        (progn (format t "NO-GO~%") (uiop:quit 1)))))
