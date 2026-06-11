;;;; test-ingress.lisp - GO/NO-GO test for the pluggable ingress layer.
;;;;
;;;; Run from repo root:
;;;;   sbcl --noinform --non-interactive --load scripts/test-ingress.lisp
;;;;
;;;; Proves, fully offline (no real Slack / LLM calls):
;;;;   1. A webhook JSON payload over REAL HTTP (dexador) opens a room
;;;;      and queues a :room-work event.
;;;;   2. A synthetic Slack app_mention payload opens a room.
;;;;   3. Agentic context-fetch: a pointer-only trigger fetches (mock)
;;;;      context and builds a prompt.
;;;;   4. Decision routing: raising a :decision/question posts to the
;;;;      MOCK Slack client; a mock reply becomes a :decision/input datom
;;;;      (queryable via datalog q).

(require :asdf)

;;; --- Prelude: load Quicklisp, register systems, load autopoiesis ---
(let ((ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file ql) (load ql)))

(push (truename "./packages/core/") asdf:*central-registry*)
(push (truename "./packages/substrate/") asdf:*central-registry*)
(push (truename "./packages/api-server/") asdf:*central-registry*)
(push (truename "./vendor/platform-vendor/woo/") asdf:*central-registry*)

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))

(handler-case
    (progn
      (funcall (find-symbol "QUICKLOAD" :ql) :woo)
      (funcall (find-symbol "QUICKLOAD" :ql) :autopoiesis)
      (asdf:load-asd (truename "./packages/api-server/api-server.asd"))
      (funcall (find-symbol "QUICKLOAD" :ql) :autopoiesis/api)
      (funcall (find-symbol "QUICKLOAD" :ql) :dexador))
  (error (e)
    (format t "~%PRELUDE-FAIL: ~A~%" e)
    (uiop:quit 1)))

;;; Global store so Hunchentoot handler threads see it.
(autopoiesis.substrate:open-store)

(defpackage #:ingress-test (:use #:cl))
(in-package #:ingress-test)

(defvar *pass* 0)
(defvar *fail* 0)

(defun chk (name ok &optional detail)
  (if ok
      (progn (incf *pass*) (format t "  PASS  ~A~%" name))
      (progn (incf *fail*) (format t "  FAIL  ~A~@[  -- ~A~]~%" name detail))))

;;; A free local port for the REST server.
(defparameter *port* 18733)

;;; ===================================================================
;;; Setup: a stub fetcher + a mock Slack client (no network)
;;; ===================================================================

;; Register a stub fetcher for the :stub scheme AND as the default fetcher,
;; so pointer-only triggers resolve to canned context offline.
(autopoiesis.api:register-fetcher
 :http
 (lambda (pointer)
   (format nil "FETCHED-CONTENT for ~A: the build is failing on step 3." pointer)))
(setf autopoiesis.api:*default-fetcher*
      (lambda (pointer)
        (format nil "DEFAULT-FETCHED for ~A" pointer)))

(defmacro with-rest-server (&body body)
  `(let ((acceptor nil))
     (unwind-protect
          (progn
            (setf (symbol-value (find-symbol "*REST-PORT*" :autopoiesis.api)) *port*)
            (setf acceptor (autopoiesis.api:start-rest-server :port *port* :host "127.0.0.1"))
            (sleep 0.4)
            ,@body)
       (ignore-errors (autopoiesis.api:stop-rest-server)))))

(defun post-json (path alist)
  "POST ALIST as JSON to PATH; return (values body-string status)."
  (multiple-value-bind (body status)
      (dexador:post (format nil "http://127.0.0.1:~D~A" *port* path)
                    :headers '(("content-type" . "application/json"))
                    :content (cl-json:encode-json-to-string alist))
    (values body status)))

;;; ===================================================================
;;; Test 1: webhook over real HTTP opens a room + queues :room-work
;;; ===================================================================

(defun test-webhook ()
  (format t "~%[1] Webhook ingress over real HTTP (dexador)~%")
  (let ((rooms-before (length (autopoiesis.api:list-rooms)))
        (events-before
          (length (autopoiesis.substrate:find-entities :event/type :room-work))))
    (with-rest-server
      (multiple-value-bind (body status)
          (post-json "/api/ingress/webhook"
                     '((:problem . "WH-1")
                       (:title . "Webhook room")
                       (:prompt . "Investigate the flaky deploy.")
                       (:backend . ((:kind . "rho") (:model . "grok-4.3")))))
        (chk "HTTP 200" (= status 200) (format nil "status=~A body=~A" status body))
        (let ((parsed (ignore-errors (cl-json:decode-json-from-string body))))
          (chk "response opened=t" (eq (cdr (assoc :opened parsed)) t)))))
    ;; Assert room datoms exist.
    (let* ((rooms (autopoiesis.substrate:find-entities :room/problem "WH-1"))
           (room (first rooms)))
      (chk "room entity created" (and room t))
      (when room
        (chk "room/title datom"
             (string= (autopoiesis.substrate:entity-attr room :room/title) "Webhook room"))
        (chk "room/source = :webhook"
             (eq (autopoiesis.substrate:entity-attr room :room/source) :webhook))
        (chk "room/backend spec carried"
             (equal (autopoiesis.substrate:entity-attr room :room/backend)
                    '(:kind :rho :model "grok-4.3")))))
    (chk "rooms count increased"
         (> (length (autopoiesis.api:list-rooms)) rooms-before))
    ;; Assert a :room-work event was queued.
    (let ((events (autopoiesis.substrate:find-entities :event/type :room-work)))
      (chk ":event/type :room-work queued"
           (> (length events) events-before)
           (format nil "~A events" (length events)))
      ;; The event carries the backend spec in its data plist.
      (let* ((ev (first events))
             (data (autopoiesis.substrate:entity-attr ev :event/data)))
        (chk "event data carries :backend"
             (and (getf data :backend) t))))))

;;; ===================================================================
;;; Test 2: synthetic Slack app_mention opens a room
;;; ===================================================================

(defun test-slack-mention ()
  (format t "~%[2] Slack app_mention ingress (synthetic payload)~%")
  ;; A realistic Slack Events API envelope.
  (let ((payload
          '((:type . "event_callback")
            (:event . ((:type . "app_mention")
                       (:text . "<@U0BOT> the staging API returns 500 on /login")
                       (:channel . "C123")
                       (:ts . "1700000000.000100")
                       (:user . "U999"))))))
    (with-rest-server
      (multiple-value-bind (body status) (post-json "/api/ingress/slack" payload)
        (chk "HTTP 200" (= status 200) (format nil "status=~A body=~A" status body)))))
  (let* ((rooms (autopoiesis.substrate:find-entities :room/problem
                                                      "slack-C123-1700000000.000100"))
         (room (first rooms)))
    (chk "slack room created" (and room t))
    (when room
      (chk "room/source = :slack"
           (eq (autopoiesis.substrate:entity-attr room :room/source) :slack))
      ;; mention token stripped, prompt is the cleaned text
      (let ((prompt (autopoiesis.substrate:entity-attr room :room/prompt)))
        (chk "mention prefix stripped from prompt"
             (and prompt (null (search "<@U0BOT>" prompt))
                  (search "staging API" prompt)))))))

;;; ===================================================================
;;; Test 3: agentic context-fetch from a pointer-only trigger
;;; ===================================================================

(defun test-context-fetch ()
  (format t "~%[3] Agentic context-fetch (pointer-only trigger)~%")
  ;; No :prompt, only a :pointer (URL). ingest must fetch + build prompt.
  (let ((room (autopoiesis.api:ingest
               :webhook
               '((:problem . "PTR-1")
                 (:title . "Pointer room")
                 (:pointer . "http://issues.local/123")))))
    (chk "room opened from pointer" (and room t))
    (let ((prompt (autopoiesis.substrate:entity-attr room :room/prompt))
          (meta (autopoiesis.substrate:entity-attr room :room/metadata)))
      (chk "prompt was built from fetched context"
           (and prompt (search "FETCHED-CONTENT" prompt)))
      (chk "prompt references the pointer"
           (and prompt (search "http://issues.local/123" prompt)))
      (chk "metadata marks fetched=t" (eq (getf meta :fetched) t)))))

;;; ===================================================================
;;; Test 4: decision routing to MOCK Slack + reply -> :decision/input
;;; ===================================================================

(defun test-decision-routing ()
  (format t "~%[4] Decision routing via MOCK Slack client~%")
  (multiple-value-bind (client backend) (autopoiesis.api:make-mock-slack-client)
    ;; Open a room, then raise a deliberation gate.
    (let* ((room (autopoiesis.api:open-room "DEC-1" "Decision room"
                                            "Should we roll back?"))
           (decision (autopoiesis.api:raise-decision
                      room "Roll back the deploy or hotfix forward?")))
      (chk "decision raised"
           (eq (autopoiesis.substrate:entity-attr decision :decision/status) :open))
      ;; Route it to a Slack channel via the mock.
      (let ((thread-ts (autopoiesis.api:route-decision-to-slack client decision "C-deci")))
        (chk "posted to mock Slack"
             (let ((posted (autopoiesis.api:mock-slack-posted backend)))
               (and posted
                    (search "Roll back" (getf (first posted) :text)))))
        (chk "decision records slack thread ts"
             (string= (autopoiesis.substrate:entity-attr decision :decision/slack-ts)
                      thread-ts))
        ;; Inject two fake replies into the thread, then ingest them.
        (autopoiesis.api:mock-slack-inject-reply backend thread-ts "alice" "Hotfix forward.")
        (autopoiesis.api:mock-slack-inject-reply backend thread-ts "bot-agent" "Risk is low; agree.")
        (let ((created (autopoiesis.api:ingest-decision-replies client decision)))
          (chk "two replies ingested as inputs" (= (length created) 2)))
        ;; Verify via datalog q that inputs are attached to the decision.
        (let ((inputs (autopoiesis.api:decision-input-ids decision)))
          (chk "decision-input-ids (datalog q) returns 2" (= (length inputs) 2))
          (let ((texts (mapcar (lambda (i)
                                 (autopoiesis.substrate:entity-attr i :input/text))
                               inputs)))
            (chk "input text 'Hotfix forward.' present"
                 (member "Hotfix forward." texts :test #'string=))
            (chk "input source = :slack"
                 (every (lambda (i)
                          (eq (autopoiesis.substrate:entity-attr i :input/source) :slack))
                        inputs))))))))

;;; (Conductor execution of :room-work is covered offline-free by
;;; run-room-orchestration-demo.lisp, which spawns real agent workers. This
;;; ingress test stays offline and only proves rooms open + work is QUEUED +
;;; decisions route to Slack.)

;;; ===================================================================
;;; Driver
;;; ===================================================================

(format t "~%=== Pluggable Ingress + Slack Decision Routing :: GO/NO-GO ===~%")

(handler-case
    (progn
      (test-webhook)
      (test-slack-mention)
      (test-context-fetch)
      (test-decision-routing))
  (error (e)
    (format t "~%UNEXPECTED ERROR: ~A~%" e)
    (incf *fail*)))

;; Free the port / clean up.
(ignore-errors (autopoiesis.api:stop-rest-server))
(ignore-errors (autopoiesis.orchestration:stop-conductor))

(format t "~%--------------------------------------------------~%")
(format t "Results: ~D passed, ~D failed~%" *pass* *fail*)
(if (zerop *fail*)
    (progn (format t "GO~%") (uiop:quit 0))
    (progn (format t "NO-GO~%") (uiop:quit 1)))
