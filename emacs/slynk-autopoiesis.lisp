;;;; slynk-autopoiesis.lisp — CL-side Slynk contrib for Autopoiesis
;;;;
;;;; Loaded on demand by SLY via (slynk:require :slynk-autopoiesis).
;;;; Provides in-image RPC for agent inspection, chat, and system overview
;;;; with zero HTTP overhead — calls go directly through the Slynk wire protocol.

(defpackage #:slynk-autopoiesis
  (:use #:cl)
  (:export #:list-agents
           #:get-agent
           #:agent-thoughts
           #:start-chat
           #:chat-prompt
           #:stop-chat
           #:list-capabilities
           #:invoke-capability
           #:system-status
           #:list-snapshots
           #:list-branches
           #:get-snapshot-detail
           #:snapshot-diff-report
           #:create-branch-rpc
           #:checkout-branch-rpc
           ;; Event bridge
           #:start-emacs-event-bridge
           #:stop-emacs-event-bridge
           ;; Org topology
           #:org-topology))

(in-package #:slynk-autopoiesis)

;;; ═══════════════════════════════════════════════════════════════════
;;; Internal helpers
;;; ═══════════════════════════════════════════════════════════════════

(defvar *sly-chat-sessions* (make-hash-table :test 'equal)
  "Map from agent-id string to jarvis-session for SLY chat buffers.")

(defun resolve (pkg-name sym-name)
  "Find symbol SYM-NAME in package PKG-NAME, or NIL if not available."
  (let ((pkg (find-package pkg-name)))
    (when pkg (find-symbol (string sym-name) pkg))))

(defun call-if-available (pkg-name sym-name &rest args)
  "Call PKG-NAME:SYM-NAME with ARGS if the package is loaded, else signal error."
  (let ((fn (resolve pkg-name sym-name)))
    (unless (and fn (fboundp fn))
      (error "~a:~a is not available. Load the ~a system first."
             pkg-name sym-name pkg-name))
    (apply fn args)))

(defun safe-slot (obj accessor-name &optional (pkg :autopoiesis.agent))
  "Read a slot via an accessor, returning NIL if the accessor isn't bound."
  (let ((fn (resolve pkg accessor-name)))
    (when (and fn (fboundp fn))
      (funcall fn obj))))

(defun thought-to-alist (thought)
  "Convert a thought object to a simple alist for Emacs."
  (list (cons :id (or (safe-slot thought "THOUGHT-ID" :autopoiesis.core) ""))
        (cons :type (let ((ty (safe-slot thought "THOUGHT-TYPE" :autopoiesis.core)))
                      (if ty (string-downcase (symbol-name ty)) "unknown")))
        (cons :content (or (safe-slot thought "THOUGHT-CONTENT" :autopoiesis.core) ""))
        (cons :timestamp (let ((ts (safe-slot thought "THOUGHT-TIMESTAMP" :autopoiesis.core)))
                           (if ts (princ-to-string ts) "")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Inspection
;;; ═══════════════════════════════════════════════════════════════════

(defun list-agents ()
  "Return list of (id name state capability-count thought-count) for all agents."
  (let ((agents (call-if-available :autopoiesis.agent "LIST-AGENTS")))
    (mapcar (lambda (agent)
              (list (safe-slot agent "AGENT-ID")
                    (safe-slot agent "AGENT-NAME")
                    (let ((st (safe-slot agent "AGENT-STATE")))
                      (if st (string-downcase (symbol-name st)) "unknown"))
                    (length (or (safe-slot agent "AGENT-CAPABILITIES") nil))
                    (let ((stream (safe-slot agent "AGENT-THOUGHT-STREAM")))
                      (if stream
                          (call-if-available :autopoiesis.core "STREAM-LENGTH" stream)
                          0))))
            agents)))

(defun get-agent (id-string)
  "Return full agent plist for agent ID-STRING."
  (let ((agent (call-if-available :autopoiesis.agent "FIND-AGENT" id-string)))
    (unless agent
      (error "No agent found with id ~a" id-string))
    (list :id (safe-slot agent "AGENT-ID")
          :name (safe-slot agent "AGENT-NAME")
          :state (let ((st (safe-slot agent "AGENT-STATE")))
                   (if st (string-downcase (symbol-name st)) "unknown"))
          :capabilities (mapcar (lambda (c) (string-downcase (symbol-name c)))
                                (or (safe-slot agent "AGENT-CAPABILITIES") nil))
          :parent (safe-slot agent "AGENT-PARENT")
          :children (safe-slot agent "AGENT-CHILDREN")
          :thought-count (let ((stream (safe-slot agent "AGENT-THOUGHT-STREAM")))
                           (if stream
                               (call-if-available :autopoiesis.core "STREAM-LENGTH" stream)
                               0)))))

(defun agent-thoughts (id-string &optional (limit 20))
  "Return last LIMIT thoughts for agent ID-STRING as alists."
  (let ((agent (call-if-available :autopoiesis.agent "FIND-AGENT" id-string)))
    (unless agent
      (error "No agent found with id ~a" id-string))
    (let ((stream (safe-slot agent "AGENT-THOUGHT-STREAM")))
      (when stream
        (let ((thoughts (call-if-available :autopoiesis.core "STREAM-LAST" stream limit)))
          (mapcar #'thought-to-alist thoughts))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Chat (Jarvis bridge)
;;; ═══════════════════════════════════════════════════════════════════

(defun start-chat (agent-id-string &optional provider-config-plist)
  "Start a Jarvis chat session for AGENT-ID-STRING.
PROVIDER-CONFIG-PLIST is an optional plist with :type, :model, etc.
Returns the agent-id on success."
  (when (gethash agent-id-string *sly-chat-sessions*)
    (return-from start-chat agent-id-string))
  (let ((session (apply #'call-if-available :autopoiesis.jarvis "START-JARVIS"
                        (when provider-config-plist
                          (list :provider-config provider-config-plist)))))
    (setf (gethash agent-id-string *sly-chat-sessions*) session)
    agent-id-string))

(defun chat-prompt (agent-id-string text)
  "Send TEXT to the Jarvis session for AGENT-ID-STRING.
Returns the response text string."
  (let ((session (gethash agent-id-string *sly-chat-sessions*)))
    (unless session
      (error "No chat session for agent ~a. Call start-chat first." agent-id-string))
    (call-if-available :autopoiesis.jarvis "JARVIS-PROMPT" session text)))

(defun stop-chat (agent-id-string)
  "Stop the Jarvis chat session for AGENT-ID-STRING."
  (let ((session (gethash agent-id-string *sly-chat-sessions*)))
    (when session
      (ignore-errors
        (call-if-available :autopoiesis.jarvis "STOP-JARVIS" session))
      (remhash agent-id-string *sly-chat-sessions*)))
  t)

;;; ═══════════════════════════════════════════════════════════════════
;;; Capabilities
;;; ═══════════════════════════════════════════════════════════════════

(defun list-capabilities ()
  "Return list of registered capability names as strings."
  (let ((caps (call-if-available :autopoiesis.agent "LIST-CAPABILITIES")))
    (mapcar (lambda (c)
              (if (symbolp c) (string-downcase (symbol-name c)) (princ-to-string c)))
            caps)))

(defun invoke-capability (name-string &rest args)
  "Invoke capability NAME-STRING with ARGS. Returns result as string."
  (let* ((kw (intern (string-upcase name-string) :keyword))
         (cap (call-if-available :autopoiesis.agent "FIND-CAPABILITY" kw)))
    (unless cap
      (error "No capability named ~a" name-string))
    (princ-to-string (call-if-available :autopoiesis.agent "INVOKE-CAPABILITY" cap args))))

;;; ═══════════════════════════════════════════════════════════════════
;;; System Overview
;;; ═══════════════════════════════════════════════════════════════════

(defun system-status ()
  "Return system status as a plist."
  (let ((health (call-if-available :autopoiesis "HEALTH-CHECK"))
        (version (call-if-available :autopoiesis "VERSION"))
        (agents (ignore-errors (call-if-available :autopoiesis.agent "LIST-AGENTS"))))
    (list :version version
          :health-status (getf health :status)
          :agent-count (if agents (length agents) 0)
          :checks (getf health :checks))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Org Topology
;;; ═══════════════════════════════════════════════════════════════════

(defun org-topology ()
  "Return the complete agent/team topology as a structured plist.
Returns (:teams (...) :unaffiliated (...) :lineage (...))."
  (let* ((agents (handler-case
                     (call-if-available :autopoiesis.agent "LIST-AGENTS")
                   (error () nil)))
         (team-fn (resolve :autopoiesis.team "LIST-TEAMS"))
         (teams-raw (when (and team-fn (fboundp team-fn))
                      (handler-case (funcall team-fn)
                        (error () nil))))
         (member-ids (make-hash-table :test 'equal))
         (teams
           (mapcar
            (lambda (team)
              (let* ((tid (or (safe-slot team "TEAM-ID" :autopoiesis.team) ""))
                     (tname (or (safe-slot team "TEAM-NAME" :autopoiesis.team) ""))
                     (strategy (let ((s (safe-slot team "TEAM-STRATEGY" :autopoiesis.team)))
                                 (if s (string-downcase (symbol-name s)) "unknown")))
                     (status (let ((s (safe-slot team "TEAM-STATUS" :autopoiesis.team)))
                               (if s (string-downcase (symbol-name s)) "unknown")))
                     (leader (let ((l (safe-slot team "TEAM-LEADER" :autopoiesis.team)))
                               (if l (or (safe-slot l "AGENT-ID") "") "")))
                     (raw-members (or (safe-slot team "TEAM-MEMBERS" :autopoiesis.team) nil))
                     (members
                       (mapcar
                        (lambda (m)
                          (let ((mid (or (safe-slot m "AGENT-ID") "")))
                            (setf (gethash mid member-ids) t)
                            (list :id mid
                                  :name (or (safe-slot m "AGENT-NAME") "")
                                  :state (let ((st (safe-slot m "AGENT-STATE")))
                                           (if st (string-downcase (symbol-name st)) "unknown"))
                                  :role (if (equal mid leader) "leader" "worker"))))
                        raw-members)))
                (when (and leader (not (equal leader "")))
                  (setf (gethash leader member-ids) t))
                (list :id tid :name tname :strategy strategy :status status
                      :leader leader :members members)))
            teams-raw))
         (unaffiliated
           (loop for agent in agents
                 for aid = (or (safe-slot agent "AGENT-ID") "")
                 unless (gethash aid member-ids)
                   collect (list :id aid
                                 :name (or (safe-slot agent "AGENT-NAME") "")
                                 :state (let ((st (safe-slot agent "AGENT-STATE")))
                                          (if st (string-downcase (symbol-name st)) "unknown")))))
         (lineage
           (loop for agent in agents
                 for aid = (or (safe-slot agent "AGENT-ID") "")
                 for parent = (safe-slot agent "AGENT-PARENT")
                 for children = (safe-slot agent "AGENT-CHILDREN")
                 when parent
                   collect (list :parent (if (stringp parent) parent (princ-to-string parent))
                                 :children (mapcar (lambda (c)
                                                     (if (stringp c) c (princ-to-string c)))
                                                   (or children nil))))))
    (list :teams teams
          :unaffiliated unaffiliated
          :lineage lineage)))

(defun list-snapshots (&optional (limit 50))
  "Return list of snapshot alists with ID, timestamp, parent, hash."
  (let ((snapshots (call-if-available :autopoiesis.snapshot "LIST-SNAPSHOTS")))
    (let ((result (mapcar (lambda (snap)
                           (list (cons :id (safe-slot snap "SNAPSHOT-ID" :autopoiesis.snapshot))
                                 (cons :timestamp (let ((ts (safe-slot snap "SNAPSHOT-TIMESTAMP" :autopoiesis.snapshot)))
                                                    (if ts (princ-to-string ts) "")))
                                 (cons :parent (or (safe-slot snap "SNAPSHOT-PARENT" :autopoiesis.snapshot) ""))
                                 (cons :hash (or (safe-slot snap "SNAPSHOT-HASH" :autopoiesis.snapshot) ""))))
                         snapshots)))
      (if (> (length result) limit)
          (subseq result 0 limit)
          result))))

(defun list-branches ()
  "Return list of branch alists with name, head, created."
  (let ((branches (call-if-available :autopoiesis.snapshot "LIST-BRANCHES")))
    (mapcar (lambda (b)
              (list (cons :name (safe-slot b "BRANCH-NAME" :autopoiesis.snapshot))
                    (cons :head (or (safe-slot b "BRANCH-HEAD" :autopoiesis.snapshot) ""))
                    (cons :created (let ((ts (safe-slot b "BRANCH-CREATED" :autopoiesis.snapshot)))
                                    (if ts (princ-to-string ts) "")))))
            branches)))

(defun create-branch-rpc (name &optional from-snapshot)
  "Create a new branch named NAME, optionally from FROM-SNAPSHOT."
  (call-if-available :autopoiesis.snapshot "CREATE-BRANCH" name
                     :from-snapshot from-snapshot))

(defun checkout-branch-rpc (name)
  "Switch to branch NAME."
  (call-if-available :autopoiesis.snapshot "SWITCH-BRANCH" name))

(defun get-snapshot-detail (snapshot-id)
  "Return detailed snapshot info as a plist."
  (let* ((store-sym (resolve :autopoiesis.snapshot "*SNAPSHOT-STORE*"))
         (store (when (and store-sym (boundp store-sym)) (symbol-value store-sym)))
         (snap (when store
                (call-if-available :autopoiesis.snapshot "LOAD-SNAPSHOT" snapshot-id store))))
    (unless snap
      (error "Snapshot not found: ~a" snapshot-id))
    (list :id (safe-slot snap "SNAPSHOT-ID" :autopoiesis.snapshot)
          :timestamp (let ((ts (safe-slot snap "SNAPSHOT-TIMESTAMP" :autopoiesis.snapshot)))
                       (if ts (princ-to-string ts) ""))
          :parent (or (safe-slot snap "SNAPSHOT-PARENT" :autopoiesis.snapshot) "none")
          :hash (or (safe-slot snap "SNAPSHOT-HASH" :autopoiesis.snapshot) "")
          :metadata (let ((md (safe-slot snap "SNAPSHOT-METADATA" :autopoiesis.snapshot)))
                      (if md (princ-to-string md) ""))
          :agent-state (let ((st (safe-slot snap "SNAPSHOT-AGENT-STATE" :autopoiesis.snapshot)))
                         (if st (format nil "~S" st) "")))))

(defun snapshot-diff-report (snapshot-id-a snapshot-id-b)
  "Return a human-readable diff between two snapshots as a string."
  (let* ((store-sym (resolve :autopoiesis.snapshot "*SNAPSHOT-STORE*"))
         (store (when (and store-sym (boundp store-sym)) (symbol-value store-sym))))
    (unless store (error "No snapshot store available"))
    (let ((snap-a (call-if-available :autopoiesis.snapshot "LOAD-SNAPSHOT" snapshot-id-a store))
          (snap-b (call-if-available :autopoiesis.snapshot "LOAD-SNAPSHOT" snapshot-id-b store)))
      (unless snap-a (error "Snapshot not found: ~a" snapshot-id-a))
      (unless snap-b (error "Snapshot not found: ~a" snapshot-id-b))
      (let* ((state-a (safe-slot snap-a "SNAPSHOT-AGENT-STATE" :autopoiesis.snapshot))
             (state-b (safe-slot snap-b "SNAPSHOT-AGENT-STATE" :autopoiesis.snapshot))
             (diff (call-if-available :autopoiesis.core "SEXPR-DIFF" state-a state-b)))
        (format nil "~S" diff)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Bridge — Push events to Emacs in real time
;;; ═══════════════════════════════════════════════════════════════════

(defvar *emacs-event-bridge-handler* nil
  "The global event handler for pushing events to Emacs.")

(defvar *emacs-event-bridge-running* nil
  "Flag indicating whether the event bridge is active.")

(defun start-emacs-event-bridge ()
  "Install a global event handler that dispatches events to Emacs.
Events are forwarded via slynk:eval-in-emacs for zero-latency push."
  (when *emacs-event-bridge-handler*
    (stop-emacs-event-bridge))
  (setf *emacs-event-bridge-running* t)
  (setf *emacs-event-bridge-handler*
        (call-if-available :autopoiesis.integration "SUBSCRIBE-TO-ALL-EVENTS"
          (lambda (event)
            (when *emacs-event-bridge-running*
              (handler-case
                  (dispatch-event-to-emacs event)
                (error (e)
                  (ignore-errors
                    (format *error-output* "Event bridge error: ~a~%" e))))))))
  t)

(defun stop-emacs-event-bridge ()
  "Remove the global event handler."
  (setf *emacs-event-bridge-running* nil)
  (when *emacs-event-bridge-handler*
    (ignore-errors
      (call-if-available :autopoiesis.integration "UNSUBSCRIBE-FROM-ALL-EVENTS"
                         *emacs-event-bridge-handler*))
    (setf *emacs-event-bridge-handler* nil))
  t)

(defun dispatch-event-to-emacs (event)
  "Route an integration event to the appropriate Emacs handler."
  (let ((kind (safe-slot event "INTEGRATION-EVENT-KIND" :autopoiesis.integration))
        (agent-id (safe-slot event "INTEGRATION-EVENT-AGENT-ID" :autopoiesis.integration))
        (data (safe-slot event "INTEGRATION-EVENT-DATA" :autopoiesis.integration))
        (timestamp (safe-slot event "INTEGRATION-EVENT-TIMESTAMP" :autopoiesis.integration)))
    (case kind
      (:thought-recorded
       (let* ((thought-sexpr (getf data :thought))
              (thought-alist (when thought-sexpr
                              (list (cons :type (string-downcase
                                                  (symbol-name (or (getf thought-sexpr :type) :unknown))))
                                    (cons :content (or (getf thought-sexpr :content) ""))
                                    (cons :timestamp (princ-to-string (or timestamp "")))))))
         (when thought-alist
           (eval-in-emacs-safe
            `(sly-autopoiesis--handle-thought ,agent-id ',thought-alist)))))

      ((:tool-called :tool-result)
       (let ((tool-str (when (getf data :tool)
                         (princ-to-string (getf data :tool)))))
         (eval-in-emacs-safe
          `(sly-autopoiesis--handle-activity
            ,agent-id
            ,(string-downcase (symbol-name kind))
            ,tool-str
            ,(princ-to-string (or timestamp ""))))))

      (:provider-response
       (eval-in-emacs-safe
        `(sly-autopoiesis--handle-activity
          ,agent-id "provider-response" nil
          ,(princ-to-string (or timestamp "")))))

      ;; Agent state changes
      ((:team-created :team-started :team-completed :team-failed
        :team-member-joined :team-member-left)
       (eval-in-emacs-safe
        `(sly-autopoiesis--handle-team-event
          ,(string-downcase (symbol-name kind))
          ',data)))

      ;; Catch-all for other events (for event log buffer)
      (otherwise
       (eval-in-emacs-safe
        `(sly-autopoiesis--handle-generic-event
          ,(string-downcase (symbol-name kind))
          ,agent-id
          ,(princ-to-string (or timestamp ""))))))))

(defun eval-in-emacs-safe (form)
  "Call slynk:eval-in-emacs, ignoring errors if Emacs is not connected."
  (handler-case
      (let ((fn (find-symbol "EVAL-IN-EMACS" :slynk)))
        (when (and fn (fboundp fn))
          (funcall fn form t)))  ; t = nowait
    (error () nil)))

(provide :slynk-autopoiesis)
