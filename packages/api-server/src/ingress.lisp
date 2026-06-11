;;;; ingress.lisp - Pluggable ingress layer + Slack decision routing
;;;;
;;;; The "shared room" product needs per-problem rooms that can be
;;;; triggered flexibly: a tag in Slack, a watched Jira ticket, a
;;;; webhook, a feed -- "you ping it with a URL and it goes and fetches
;;;; what it needs." This file provides:
;;;;
;;;;   1. A pluggable SOURCE-ADAPTER protocol + registry. A source
;;;;      normalizes an incoming trigger into a room-open request and
;;;;      opens a room.
;;;;   2. OPEN-ROOM: creates the room entity (datoms) and queues a
;;;;      :room-work event carrying a serializable :backend agent spec.
;;;;   3. A pluggable context FETCHER: when a trigger carries a pointer
;;;;      (URL / ticket id) instead of a full prompt, the room bootstraps
;;;;      by fetching context from the pointer and building the prompt.
;;;;   4. A Slack client interface (struct-of-fns) with a MOCK
;;;;      implementation, plus decision routing: a raised
;;;;      :decision/question is POSTed to Slack and replies are captured
;;;;      back as :decision/input datoms.
;;;;
;;;; Everything is transport/provider-agnostic so real Slack/Jira creds
;;;; slot in later. The room work RUNNER is itself pluggable
;;;; (*room-runner*) so this layer is fully offline-testable.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Substrate schema (reused / defined here)
;;; ===================================================================
;;;
;;; Room:
;;;   :room/title      string
;;;   :room/problem    string (problem-id)
;;;   :room/source     keyword (which adapter opened it)
;;;   :room/prompt     string (the bootstrapped prompt)
;;;   :room/backend    plist  (serializable agent spec, e.g. (:kind :rho ...))
;;;   :room/metadata   plist
;;;   :room/status     keyword (:open ...)
;;;   :room/created-at universal-time
;;;
;;; Decision (mirrors the SB-product decision schema):
;;;   :decision/question   string
;;;   :decision/status     keyword (:open :resolved ...)
;;;   :decision/resolution string
;;;   :decision/room       entity-id (which room raised it)
;;;   :decision/slack-channel string
;;;   :decision/slack-ts      string  (thread root timestamp)
;;; Decision input (a reply / weigh-in):
;;;   :input/decision      entity-id (the decision)
;;;   :input/user          string
;;;   :input/text          string
;;;   :input/source        keyword (:slack :agent :human ...)
;;;   :input/created-at    universal-time

(defvar *default-room-backend* '(:kind :rho :model "grok-4.3")
  "Default serializable agent-backend spec attached to :room-work events.")

;;; ===================================================================
;;; Source adapter protocol + registry
;;; ===================================================================

(defclass source-adapter ()
  ((name :initarg :name :reader source-adapter-name
         :documentation "Keyword naming this source, e.g. :webhook :slack :jira.")
   (normalizer :initarg :normalizer :reader source-adapter-normalizer
               :documentation "Function (raw-payload) -> room-open plist.
   The returned plist must contain at least :problem, and should contain
   :title and either :prompt or :pointer. May also carry :metadata."))
  (:documentation "A pluggable ingress source. Normalizes an incoming
   trigger payload into a uniform room-open request."))

(defvar *source-adapters* (make-hash-table :test 'eq)
  "Registry of source adapters keyed by name.")

(defun register-source-adapter (name normalizer)
  "Register (or replace) a source adapter NAME with NORMALIZER fn.
   NORMALIZER takes the raw trigger payload and returns a room-open
   plist (:problem :title :prompt|:pointer :metadata). Returns the adapter."
  (let ((adapter (make-instance 'source-adapter :name name :normalizer normalizer)))
    (setf (gethash name *source-adapters*) adapter)
    adapter))

(defun find-source-adapter (name)
  "Return the registered adapter named NAME, or NIL."
  (gethash name *source-adapters*))

(defun list-source-adapters ()
  "Return a list of registered adapter names."
  (loop for k being the hash-keys of *source-adapters* collect k))

(defgeneric adapter-normalize (adapter raw-payload)
  (:documentation "Normalize RAW-PAYLOAD into a room-open plist.")
  (:method ((adapter source-adapter) raw-payload)
    (funcall (source-adapter-normalizer adapter) raw-payload)))

;;; ===================================================================
;;; Pluggable context fetcher
;;; ===================================================================
;;;
;;; A fetcher resolves a pointer (URL / ticket id / scheme keyword) into
;;; context text. Registered by a SCHEME keyword. fetch-context picks the
;;; fetcher by the pointer's scheme (or *default-fetcher*).

(defvar *fetchers* (make-hash-table :test 'eq)
  "Registry of context fetchers keyed by scheme keyword (e.g. :http :jira :stub).")

(defvar *default-fetcher* nil
  "Fallback fetcher fn (pointer) -> string, used when no scheme matches.")

(defun register-fetcher (scheme fn)
  "Register a fetcher FN for a pointer SCHEME keyword. FN takes the
   pointer string and returns context text (a string)."
  (setf (gethash scheme *fetchers*) fn))

(defun find-fetcher (scheme)
  "Return the fetcher fn for SCHEME, or NIL."
  (gethash scheme *fetchers*))

(defun pointer-scheme (pointer)
  "Infer a scheme keyword from POINTER. URLs -> :http/:https; bare
   tokens like \"JIRA-123\" -> :jira; otherwise NIL."
  (cond
    ((and (stringp pointer) (>= (length pointer) 7)
          (string-equal "http://" (subseq pointer 0 7)))
     :http)
    ((and (stringp pointer) (>= (length pointer) 8)
          (string-equal "https://" (subseq pointer 0 8)))
     :https)
    ((and (stringp pointer) (find #\- pointer)
          (every (lambda (c) (or (alpha-char-p c) (digit-char-p c) (char= c #\-))) pointer)
          (alpha-char-p (char pointer 0)))
     :jira)
    (t nil)))

(defun fetch-context (pointer)
  "Resolve POINTER to context text using a registered fetcher.
   Selection order: exact scheme fetcher, then *default-fetcher*.
   Signals an error if no fetcher can handle the pointer."
  (let* ((scheme (pointer-scheme pointer))
         (fn (or (and scheme (find-fetcher scheme)) *default-fetcher*)))
    (unless fn
      (error "No fetcher registered for pointer ~S (scheme ~S)" pointer scheme))
    (funcall fn pointer)))

;;; Room-work EXECUTION is not defined here: open-room queues a :room-work
;;; event, which the conductor's existing :room-work dispatch case runs via
;;; autopoiesis.integration:run-room-work (spawns a worker that runs the agent
;;; turn through the :backend spec and stages a branch; the orchestrator fans
;;; in). This ingress layer's job is only to OPEN rooms + queue work + route
;;; decisions -- it stays free of agent/LLM calls.

;;; ===================================================================
;;; open-room
;;; ===================================================================

(defun open-room (problem-id title prompt
                  &key (source :manual) (backend *default-room-backend*) metadata)
  "Create a room entity and queue work for it.
   - PROBLEM-ID : stable id for the problem (string).
   - TITLE      : human title.
   - PROMPT     : the (already built) prompt for the room's first turn.
   - :SOURCE    : keyword naming which adapter opened it.
   - :BACKEND   : serializable agent-backend spec for the :room-work event.
   - :METADATA  : extra plist stored on the room.
   Returns the room entity-id."
  (let ((room-eid (autopoiesis.substrate:intern-id
                   (format nil "room-~A-~A" problem-id
                           (autopoiesis.orchestration::make-uuid)))))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom room-eid :room/problem problem-id)
           (autopoiesis.substrate:make-datom room-eid :room/title title)
           (autopoiesis.substrate:make-datom room-eid :room/prompt prompt)
           (autopoiesis.substrate:make-datom room-eid :room/source source)
           (autopoiesis.substrate:make-datom room-eid :room/backend backend)
           (autopoiesis.substrate:make-datom room-eid :room/metadata metadata)
           (autopoiesis.substrate:make-datom room-eid :room/status :open)
           (autopoiesis.substrate:make-datom room-eid :room/created-at
                                              (get-universal-time))))
    ;; Queue the work. The conductor's :room-work dispatch runs it.
    (autopoiesis.orchestration:queue-event
     :room-work
     (list :problem problem-id
           :prompt prompt
           :backend backend
           :room room-eid
           :worker (format nil "room-~A" problem-id)))
    room-eid))

(defun ingress-room-state (room-eid)
  "Return an ingress room's attributes as a plist. (Named ingress-room-state to
   avoid clashing with room-mcp.lisp's room-state, which backs the room_state
   MCP tool.)"
  (autopoiesis.substrate:entity-state room-eid))

(defun list-rooms ()
  "Return entity-ids of all rooms."
  (autopoiesis.substrate:find-entities :room/status :open))

;;; ===================================================================
;;; ingest -- the generic entry point through an adapter
;;; ===================================================================

(defun ingest (adapter-name raw-payload &key (backend *default-room-backend*))
  "Normalize RAW-PAYLOAD through the adapter named ADAPTER-NAME and open
   a room. If the normalized request carries a :pointer (and no :prompt),
   the context is fetched and a prompt is built. Returns the room eid."
  (let ((adapter (find-source-adapter adapter-name)))
    (unless adapter
      (error "No source adapter registered: ~S" adapter-name))
    (let* ((req (adapter-normalize adapter raw-payload))
           (problem (getf req :problem))
           (title (or (getf req :title) problem "Untitled room"))
           (prompt (getf req :prompt))
           (pointer (getf req :pointer))
           (metadata (getf req :metadata)))
      (unless problem
        (error "Adapter ~S produced no :problem" adapter-name))
      ;; Agentic context-fetch: pointer-only trigger -> fetch + build prompt.
      (when (and (not prompt) pointer)
        (let ((context (fetch-context pointer)))
          (setf prompt
                (format nil "Problem: ~A~%~%Context fetched from ~A:~%~A~%~%~
                             Please analyze and propose next steps."
                        problem pointer context))
          (setf metadata (append (list :pointer pointer :fetched t) metadata))))
      (unless prompt
        (error "Adapter ~S produced neither :prompt nor :pointer" adapter-name))
      (open-room problem title prompt
                 :source adapter-name :backend backend :metadata metadata))))

;;; ===================================================================
;;; Built-in adapters: webhook, slack
;;; ===================================================================

(defun assoc-val (key alist)
  "Read KEY from a cl-json-decoded ALIST (keys are keywords)."
  (cdr (assoc key alist)))

(defun normalize-webhook (payload)
  "Webhook normalizer. PAYLOAD is a decoded JSON alist:
   {problem, title, prompt?, source?, pointer?, metadata?}."
  (list :problem (assoc-val :problem payload)
        :title (assoc-val :title payload)
        :prompt (assoc-val :prompt payload)
        :pointer (or (assoc-val :pointer payload) (assoc-val :url payload))
        :metadata (let ((m (assoc-val :metadata payload)))
                    (when m (list :raw m)))))

(defun normalize-slack-mention (payload)
  "Slack app_mention normalizer. PAYLOAD is a decoded Slack Events API
   envelope alist: {event: {type:\"app_mention\", text, channel, ts, user}}.
   The bot mention prefix (<@Uxxxx>) is stripped; the remaining text
   becomes the prompt; the channel+ts identify the problem/thread."
  (let* ((event (assoc-val :event payload))
         (text (or (assoc-val :text event) ""))
         (channel (assoc-val :channel event))
         (ts (assoc-val :ts event))
         (user (assoc-val :user event))
         ;; Strip a leading mention token like "<@U123> "
         (clean (string-left-trim
                 " "
                 (cl-ppcre:regex-replace "^<@[^>]+>" text ""))))
    (list :problem (format nil "slack-~A-~A" (or channel "dm") (or ts "0"))
          :title (if (> (length clean) 60) (subseq clean 0 60) clean)
          :prompt clean
          :metadata (list :slack-channel channel :slack-ts ts :slack-user user))))

(defun register-builtin-ingress-adapters ()
  "Register the webhook and slack adapters. Idempotent."
  (register-source-adapter :webhook #'normalize-webhook)
  (register-source-adapter :slack #'normalize-slack-mention)
  t)

;; Register at load time.
(register-builtin-ingress-adapters)

;;; ===================================================================
;;; Slack client interface (mockable) + decision routing
;;; ===================================================================
;;;
;;; A slack-client is a struct of functions so the transport is fully
;;; abstracted. Real wiring provides functions that call chat.postMessage
;;; / conversations.replies; the mock records posts and serves injected
;;; replies.

(defstruct slack-client
  ;; (post-fn channel text &key thread-ts) -> message-ts (string)
  (post-fn nil :type (or null function))
  ;; (replies-fn channel thread-ts) -> list of (:user u :text t) plists
  (replies-fn nil :type (or null function)))

(defun slack-post-message (client channel text &key thread-ts)
  "Post TEXT to CHANNEL (optionally in THREAD-TS). Returns the message ts."
  (funcall (slack-client-post-fn client) channel text :thread-ts thread-ts))

(defun slack-fetch-replies (client channel thread-ts)
  "Fetch replies in CHANNEL/THREAD-TS as a list of (:user :text) plists."
  (funcall (slack-client-replies-fn client) channel thread-ts))

;;; --- Real Slack wiring (documentation; slots in here) ---
;;;
;;; To go live, construct a real slack-client whose post-fn / replies-fn
;;; call the Slack Web API with a bot token, and accept inbound events
;;; through /api/ingress/slack. Concretely:
;;;
;;;   Slack app config (api.slack.com/apps):
;;;     - Bot token scopes (OAuth & Permissions):
;;;         chat:write          (post decision messages)
;;;         channels:history     (read public-channel thread replies)
;;;         groups:history       (read private-channel thread replies)
;;;         app_mentions:read    (receive @mentions that open rooms)
;;;         channels:read        (resolve channel ids, optional)
;;;     - Event Subscriptions: enable, subscribe bot to "app_mention".
;;;       Request URL -> https://<host>/api/ingress/slack
;;;       (the handler answers the url_verification challenge already).
;;;       Socket Mode is the alternative if you cannot expose a public URL.
;;;     - Install the app; store the Bot User OAuth Token (xoxb-...) and
;;;       the Signing Secret (verify X-Slack-Signature on inbound posts).
;;;
;;;   Real client (pseudo):
;;;     (make-slack-client
;;;       :post-fn (lambda (channel text &key thread-ts)
;;;                  ;; POST https://slack.com/api/chat.postMessage
;;;                  ;;   Authorization: Bearer xoxb-...
;;;                  ;;   {channel, text, thread_ts}
;;;                  ;; -> return the "ts" from the JSON response
;;;                  ...)
;;;       :replies-fn (lambda (channel thread-ts)
;;;                     ;; GET https://slack.com/api/conversations.replies
;;;                     ;;   ?channel=..&ts=thread-ts
;;;                     ;; -> map each message to (:user .. :text ..)
;;;                     ...))
;;;
;;;   Inbound replies can also be pushed: a "message" event in a thread
;;;   whose thread_ts matches a decision's :decision/slack-ts can be
;;;   turned into a :decision/input datom directly (same shape as
;;;   ingest-decision-replies), avoiding polling.
;;;
;;; Nothing above changes the decision-routing code: only the two fns
;;; in the slack-client struct differ between mock and live.

;;; --- Mock implementation ---

(defstruct mock-slack-backend
  (posted nil)        ; list of (:channel :text :thread-ts :ts) plists, newest last
  (replies (make-hash-table :test 'equal)) ; thread-ts -> list of (:user :text)
  (counter 0))

(defun make-mock-slack-client ()
  "Construct a mock slack-client backed by an in-memory store.
   Returns two values: the slack-client and its mock-slack-backend."
  (let ((backend (make-mock-slack-backend)))
    (values
     (make-slack-client
      :post-fn (lambda (channel text &key thread-ts)
                 (let ((ts (format nil "~D.~6,'0D"
                                   (get-universal-time)
                                   (incf (mock-slack-backend-counter backend)))))
                   (setf (mock-slack-backend-posted backend)
                         (append (mock-slack-backend-posted backend)
                                 (list (list :channel channel :text text
                                             :thread-ts (or thread-ts ts) :ts ts))))
                   ts))
      :replies-fn (lambda (channel thread-ts)
                    (declare (ignore channel))
                    (gethash thread-ts (mock-slack-backend-replies backend))))
     backend)))

(defun mock-slack-posted (backend)
  "Return the list of messages posted to the mock backend."
  (mock-slack-backend-posted backend))

(defun mock-slack-inject-reply (backend thread-ts user text)
  "Inject a fake reply into the mock backend's THREAD-TS."
  (setf (gethash thread-ts (mock-slack-backend-replies backend))
        (append (gethash thread-ts (mock-slack-backend-replies backend))
                (list (list :user user :text text)))))

;;; --- Decision schema operations ---

(defun raise-decision (room-eid question)
  "Raise a deliberation gate: create a :decision entity bound to ROOM-EID.
   Returns the decision entity-id."
  (let ((dec-eid (autopoiesis.substrate:intern-id
                  (format nil "decision-~A" (autopoiesis.orchestration::make-uuid)))))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom dec-eid :decision/question question)
           (autopoiesis.substrate:make-datom dec-eid :decision/status :open)
           (autopoiesis.substrate:make-datom dec-eid :decision/room room-eid)
           (autopoiesis.substrate:make-datom dec-eid :decision/created-at
                                              (get-universal-time))))
    dec-eid))

(defun route-decision-to-slack (client decision-eid channel)
  "POST the decision's question to a Slack CHANNEL, opening a thread.
   Records the channel + thread ts on the decision so replies can be
   collected later. Returns the thread ts."
  (let* ((question (autopoiesis.substrate:entity-attr decision-eid :decision/question))
         (ts (slack-post-message client channel
                                 (format nil "Decision needed: ~A" question))))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom decision-eid :decision/slack-channel channel)
           (autopoiesis.substrate:make-datom decision-eid :decision/slack-ts ts)))
    ts))

(defun ingest-decision-replies (client decision-eid)
  "Fetch Slack thread replies for DECISION-EID and record each as a
   :decision/input datom. Returns the list of created input entity-ids."
  (let* ((channel (autopoiesis.substrate:entity-attr decision-eid :decision/slack-channel))
         (ts (autopoiesis.substrate:entity-attr decision-eid :decision/slack-ts))
         (replies (slack-fetch-replies client channel ts))
         (created nil))
    (dolist (r replies)
      (let ((in-eid (autopoiesis.substrate:intern-id
                     (format nil "input-~A" (autopoiesis.orchestration::make-uuid)))))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom in-eid :input/decision decision-eid)
               (autopoiesis.substrate:make-datom in-eid :input/user (getf r :user))
               (autopoiesis.substrate:make-datom in-eid :input/text (getf r :text))
               (autopoiesis.substrate:make-datom in-eid :input/source :slack)
               (autopoiesis.substrate:make-datom in-eid :input/created-at
                                                  (get-universal-time))))
        (push in-eid created)))
    (nreverse created)))

(defun decision-state (decision-eid)
  "Return the decision's attributes as a plist."
  (autopoiesis.substrate:entity-state decision-eid))

(defun decision-input-ids (decision-eid)
  "Return all input entity-ids attached to DECISION-EID via datalog.
   (Named -ids to avoid clashing with sb-product.lisp's decision-inputs,
   which returns (user . text) pairs.)"
  (mapcar #'first
          (autopoiesis.substrate:q
           '(:find ?in
             :in ?dec
             :where (?in :input/decision ?dec))
           decision-eid)))

(defun room-to-json-alist (room-eid)
  "Serialize a room entity to a JSON-encodable alist."
  (let ((s (autopoiesis.substrate:entity-state room-eid)))
    `((:id . ,room-eid)
      (:problem . ,(getf s :room/problem))
      (:title . ,(getf s :room/title))
      (:source . ,(string-downcase (string (or (getf s :room/source) :unknown))))
      (:status . ,(string-downcase (string (or (getf s :room/status) :unknown))))
      (:backend . ,(prin1-to-string (getf s :room/backend)))
      (:created--at . ,(getf s :room/created-at)))))
