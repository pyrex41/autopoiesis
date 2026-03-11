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
           #:list-branches))

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

(defun list-snapshots (&optional (limit 20))
  "Return up to LIMIT snapshot ID strings."
  (let ((ids (call-if-available :autopoiesis.snapshot "LIST-SNAPSHOTS")))
    (if (> (length ids) limit)
        (subseq ids 0 limit)
        ids)))

(defun list-branches ()
  "Return list of (name head-id) for all branches."
  (let ((branches (call-if-available :autopoiesis.snapshot "LIST-BRANCHES")))
    (mapcar (lambda (b)
              (list (safe-slot b "BRANCH-NAME" :autopoiesis.snapshot)
                    (safe-slot b "BRANCH-HEAD" :autopoiesis.snapshot)))
            branches)))

(provide :slynk-autopoiesis)
