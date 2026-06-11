;;;; run-room-orchestration-demo.lisp - #1: wire it together (GO/NO-GO)
;;;;
;;;; The full loop, live: the CONDUCTOR dispatches :room-work events; each spawns
;;;; a WORKER that runs a real agent turn (grok-4.3 via the rho provider) through
;;;; the provider abstraction, POSTS the agent's output onto its own speculative
;;;; branch, and MERGES it into the shared ROOM. Two workers on one problem ->
;;;; their independent notes union; their divergent :one proposals -> the second
;;;; is FLAGGED (lead/human resolves), never silently lost.
;;;;
;;;; provider-codex-appserver plugs into the exact same loop (it's a provider);
;;;; we demo with grok because its endpoint is live today.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/core/scripts/run-room-orchestration-demo.lisp

(in-package #:cl-user)
(dolist (dir '("./packages/core/" "./packages/substrate/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-room-orch
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)
                    (#:o #:autopoiesis.orchestration)
                    (#:i #:autopoiesis.integration)))
(in-package #:sb-room-orch)

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defun many-values (e a)
  (remove-duplicates (mapcar (lambda (x) (getf x :value))
                             (s:entity-history e a :last-n 1000))
                     :test #'equal))

(defun worker-status (task-id)
  (s:entity-attr (s:intern-id task-id) :worker/status))

(defun wait-for-workers (task-ids &key (timeout 120))
  "Poll until every task-id is :complete/:failed, or timeout."
  (loop with start = (get-universal-time)
        for done = (every (lambda (tid) (member (worker-status tid) '(:complete :failed)))
                          task-ids)
        until (or done (> (- (get-universal-time) start) timeout))
        do (sleep 1.5)
        finally (return done)))

(defun run-demo ()
  (setf *fails* nil)
  (s:open-store)                          ; GLOBAL store (conductor + worker threads see it)
  (s:declare-cardinality :room/proposal :one)   ; contested -> divergence flags
  (s:declare-cardinality :room/note     :many)  ; independent -> unions
  (let ((problem "feature-storage"))
    (s:transact! (list (s:make-datom problem :room/title "Pick the storage backend")))
    (o:start-conductor)
    (sleep 0.3)
    ;; two workers, each its own grok provider, prompts that force divergent answers
    (let ((p-alice (i::make-rho-provider :name "alice-grok" :default-model "grok-4.3" :skip-tools t))
          (p-bob   (i::make-rho-provider :name "bob-grok"   :default-model "grok-4.3" :skip-tools t))
          (alice-id "room-worker-feature-storage-alice")
          (bob-id   "room-worker-feature-storage-bob"))
      ;; queue two :room-work events -> conductor tick -> dispatch -> spawn workers
      (o:queue-event :room-work
                     (list :problem problem :worker "alice" :provider p-alice
                           :prompt "Output only the single lowercase word and nothing else: postgres"))
      (o:queue-event :room-work
                     (list :problem problem :worker "bob" :provider p-bob
                           :prompt "Output only the single lowercase word and nothing else: sqlite"))
      (format t "~&== queued 2 :room-work events; waiting for workers ==~%")
      (let ((finished (wait-for-workers (list alice-id bob-id) :timeout 150)))
        (check "both workers ran to completion (conductor->worker->turn->merge)"
               finished
               (list :alice (worker-status alice-id) :bob (worker-status bob-id)))
        (check "alice worker completed" (eq (worker-status alice-id) :complete)
               (s:entity-attr (s:intern-id alice-id) :worker/result))
        (check "bob worker completed" (eq (worker-status bob-id) :complete)
               (s:entity-attr (s:intern-id bob-id) :worker/result))

        ;; orchestrator/lead fan-in: merge the staged branches (sequential)
        (multiple-value-bind (applied conflicts) (i::fan-in-room problem)
          (format t "  == fan-in: ~D writes applied, ~D conflict(s) ==~%"
                  applied (length conflicts)))

        ;; the room state after fan-in
        (let ((proposal (s:entity-attr problem :room/proposal))
              (notes (many-values problem :room/note))
              (conflict (s:entity-attr problem :room/conflict)))
          (format t "  room/proposal = ~S~%  room/note = ~S~%  room/conflict = ~S~%"
                  proposal notes conflict)
          (check "a proposal landed in the room (a worker's turn produced real output)"
                 (and proposal (plusp (length (string proposal)))))
          (check ":many notes UNION across both workers (independent work merged)"
                 (= 2 (length notes)) notes)
          (check "divergent :one proposal FLAGGED as a conflict (not silently lost)"
                 (and conflict (plusp (length (string conflict)))) conflict)))
      (o:stop-conductor)))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-demo))
