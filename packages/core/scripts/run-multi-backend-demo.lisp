;;;; run-multi-backend-demo.lisp - general agent-backend layer (GO/NO-GO)
;;;;
;;;; Proves the "use your own tool" premise: the room worker is backend-agnostic.
;;;;  Part 1: the factory builds a provider for EVERY backend
;;;;          (codex / codex-appserver / claude-code / anthropic / rho / grok /
;;;;           pi / opencode) -- construction only, no auth/cost.
;;;;  Part 2: the SAME conductor->worker->room->fan-in loop runs real turns
;;;;          through DIFFERENT backends (rho@grok-4.3 and the grok.com CLI),
;;;;          selected purely by a serializable :backend spec on the event.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/core/scripts/run-multi-backend-demo.lisp

(in-package #:cl-user)
(dolist (dir '("./packages/core/" "./packages/substrate/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-multi-backend
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)
                    (#:o #:autopoiesis.orchestration)
                    (#:i #:autopoiesis.integration)))
(in-package #:sb-multi-backend)

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defun many-values (e a)
  (remove-duplicates (mapcar (lambda (x) (getf x :value)) (s:entity-history e a :last-n 1000))
                     :test #'equal))
(defun worker-status (tid) (s:entity-attr (s:intern-id tid) :worker/status))
(defun wait-for (task-ids &key (timeout 180))
  (loop with start = (get-universal-time)
        until (or (every (lambda (tid) (member (worker-status tid) '(:complete :failed))) task-ids)
                  (> (- (get-universal-time) start) timeout))
        do (sleep 1.5)
        finally (return (every (lambda (tid) (member (worker-status tid) '(:complete :failed))) task-ids))))

(defun run-demo ()
  (setf *fails* nil)
  (s:open-store)

  ;; ---------- Part 1: factory builds EVERY backend ----------
  (format t "~&== Part 1: agent-backend factory (construction) ==~%")
  (dolist (kind i::*agent-backends*)
    (check (format nil "factory builds ~A" kind)
           (handler-case (typep (i::make-agent-backend kind) 'i::provider)
             (error (e) (format t "      (~A: ~A)~%" kind e) nil))))

  ;; ---------- Part 2: same loop, two real backends ----------
  (format t "~&== Part 2: conductor -> workers on different backends -> room ==~%")
  (s:declare-cardinality :room/proposal :one)
  (s:declare-cardinality :room/note     :many)
  (let ((problem "backend-bakeoff"))
    (s:transact! (list (s:make-datom problem :room/title "Which backend?")))
    (o:start-conductor)
    (sleep 0.3)
    (let ((rho-id  "room-worker-backend-bakeoff-rho")
          (grok-id "room-worker-backend-bakeoff-grok"))
      ;; backend chosen purely by spec on the event -- worker builds the provider
      (o:queue-event :room-work
                     (list :problem problem :worker "rho"
                           :backend '(:kind :rho :model "grok-4.3")
                           :prompt "Output only the single lowercase word and nothing else: postgres"))
      (o:queue-event :room-work
                     (list :problem problem :worker "grok"
                           :backend '(:kind :grok)
                           :prompt "Output only the single lowercase word and nothing else: sqlite"))
      (format t "  queued 2 :room-work events (backends: rho@grok-4.3, grok.com CLI)~%")
      (let ((finished (wait-for (list rho-id grok-id) :timeout 200)))
        (check "both backends ran the same worker loop to completion"
               finished (list :rho (worker-status rho-id) :grok (worker-status grok-id)))
        (format t "  rho:  ~A~%  grok: ~A~%"
                (s:entity-attr (s:intern-id rho-id) :worker/result)
                (s:entity-attr (s:intern-id grok-id) :worker/result))
        (multiple-value-bind (applied conflicts) (i::fan-in-room problem)
          (format t "  == fan-in: ~D applied, ~D conflict(s) ==~%" applied (length conflicts)))
        (let ((notes (many-values problem :room/note)))
          (check "a proposal landed (a real turn produced output)"
                 (let ((p (s:entity-attr problem :room/proposal))) (and p (plusp (length (string p))))))
          (check "notes union across the two backends"
                 (= 2 (length notes)) notes))))
    (o:stop-conductor))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-demo))
