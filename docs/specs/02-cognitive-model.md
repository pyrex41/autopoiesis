# Autopoiesis: Cognitive Model

## Specification Document 02: Cognitive Model

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

The Cognitive Model defines how Autopoiesis agents think, make decisions, and modify themselves. At its core, an agent is a Lisp image with a structured thought process, a set of capabilities, and the unique ability to inspect and modify its own cognitive patterns.

---

## Agent Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AGENT                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       COGNITIVE CORE                                 │   │
│  │                                                                      │   │
│  │   ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐   │   │
│  │   │  Thought    │   │  Decision   │   │     Self-Modification   │   │   │
│  │   │  Stream     │──▶│  Engine     │──▶│     Engine              │   │   │
│  │   └─────────────┘   └─────────────┘   └─────────────────────────┘   │   │
│  │          ▲                │                       │                 │   │
│  │          │                ▼                       ▼                 │   │
│  │   ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐   │   │
│  │   │  Context    │   │   Action    │   │     Reflection          │   │   │
│  │   │  Window     │◀──│   Executor  │──▶│     Module              │   │   │
│  │   └─────────────┘   └─────────────┘   └─────────────────────────┘   │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      CAPABILITY LAYER                                │   │
│  │                                                                      │   │
│  │   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │   │ Builtin  │ │ Acquired │ │ Generated│ │   MCP    │ │ External │  │   │
│  │   │  Caps    │ │  Caps    │ │   Caps   │ │  Tools   │ │  Tools   │  │   │
│  │   └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        STATE LAYER                                   │   │
│  │                                                                      │   │
│  │   ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │   │
│  │   │   Bindings   │  │   Memory     │  │   Personality/Config     │  │   │
│  │   │  (dynamic    │  │  (long-term  │  │   (stable traits)        │  │   │
│  │   │   variables) │  │   storage)   │  │                          │  │   │
│  │   └──────────────┘  └──────────────┘  └──────────────────────────┘  │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Agent Definition

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; agent.lisp - Base agent definition
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Agent class
;;; ─────────────────────────────────────────────────────────────────

(defclass agent ()
  (;; Identity
   (id :initarg :id
       :accessor agent-id
       :initform (make-uuid)
       :documentation "Unique identifier")
   (name :initarg :name
         :accessor agent-name
         :initform "unnamed-agent"
         :documentation "Human-readable name")
   (parent :initarg :parent
           :accessor agent-parent
           :initform nil
           :documentation "Parent agent (if spawned by another)")

   ;; Cognitive core
   (thought-stream :initarg :thought-stream
                   :accessor agent-thought-stream
                   :initform (make-instance 'thought-stream)
                   :documentation "Ordered sequence of all thoughts")
   (context-window :initarg :context-window
                   :accessor agent-context-window
                   :initform (make-context-window)
                   :documentation "Current working context")
   (decision-engine :initarg :decision-engine
                    :accessor agent-decision-engine
                    :initform (make-default-decision-engine)
                    :documentation "Decision-making strategy")

   ;; Capabilities
   (capabilities :initarg :capabilities
                 :accessor agent-capabilities
                 :initform (make-hash-table :test 'eq)
                 :documentation "Available capabilities (name -> capability)")
   (capability-permissions :initarg :capability-permissions
                           :accessor agent-capability-permissions
                           :initform :standard
                           :documentation "Permission level for new capabilities")

   ;; State
   (bindings :initarg :bindings
             :accessor agent-bindings
             :initform (make-hash-table :test 'eq)
             :documentation "Dynamic variable bindings")
   (memory :initarg :memory
           :accessor agent-memory
           :initform (make-agent-memory)
           :documentation "Persistent memory store")
   (personality :initarg :personality
                :accessor agent-personality
                :initform (make-default-personality)
                :documentation "Stable behavioral traits")

   ;; Execution state
   (status :initarg :status
           :accessor agent-status
           :initform :idle
           :documentation ":idle :running :paused :terminated")
   (current-task :initarg :current-task
                 :accessor agent-current-task
                 :initform nil)
   (pending-actions :initarg :pending-actions
                    :accessor agent-pending-actions
                    :initform nil)

   ;; Meta
   (created-at :initarg :created-at
               :accessor agent-created-at
               :initform (get-universal-time))
   (extensions :initarg :extensions
               :accessor agent-extensions
               :initform nil
               :documentation "Self-written extensions"))

  (:documentation "A Autopoiesis cognitive agent"))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Protocol (generic functions)
;;; ─────────────────────────────────────────────────────────────────

(defgeneric agent-think (agent input)
  (:documentation "Process INPUT and produce thoughts"))

(defgeneric agent-decide (agent options)
  (:documentation "Choose between OPTIONS"))

(defgeneric agent-act (agent action)
  (:documentation "Execute ACTION using capabilities"))

(defgeneric agent-reflect (agent &optional target)
  (:documentation "Metacognitive self-reflection"))

(defgeneric agent-modify-self (agent modification)
  (:documentation "Apply self-modification"))

(defgeneric agent-to-sexpr (agent)
  (:documentation "Serialize agent to S-expression"))

(defgeneric sexpr-to-agent (sexpr)
  (:documentation "Reconstruct agent from S-expression"))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Metaobject Protocol (AMOP)
;;; ─────────────────────────────────────────────────────────────────

(defclass agent-metaclass (standard-class)
  ((cognitive-hooks :initarg :cognitive-hooks
                    :accessor metaclass-cognitive-hooks
                    :initform nil
                    :documentation "Hooks called during cognition"))
  (:documentation "Metaclass for agents, enabling cognitive customization"))

(defmethod validate-superclass ((class agent-metaclass) (superclass standard-class))
  t)

;; Allow agents to define how they process input
(defgeneric compute-cognitive-method (agent phase input)
  (:documentation "Compute the cognitive method for PHASE given INPUT.
   PHASE is one of :perceive :reason :decide :act :reflect"))

(defmethod compute-cognitive-method ((agent agent) phase input)
  "Default: use standard cognitive pipeline."
  (ecase phase
    (:perceive #'default-perceive)
    (:reason #'default-reason)
    (:decide #'default-decide)
    (:act #'default-act)
    (:reflect #'default-reflect)))

;;; ─────────────────────────────────────────────────────────────────
;;; Specialized Agent Types
;;; ─────────────────────────────────────────────────────────────────

(defclass specialist-agent (agent)
  ((domain :initarg :domain
           :accessor specialist-domain
           :documentation "Domain of specialization")
   (expertise-level :initarg :expertise-level
                    :accessor specialist-expertise
                    :initform 1.0))
  (:metaclass agent-metaclass)
  (:documentation "An agent specialized in a particular domain"))

(defclass coordinator-agent (agent)
  ((subordinates :initarg :subordinates
                 :accessor coordinator-subordinates
                 :initform nil
                 :documentation "Agents being coordinated")
   (strategy :initarg :strategy
             :accessor coordinator-strategy
             :initform :parallel))
  (:metaclass agent-metaclass)
  (:documentation "An agent that coordinates other agents"))

(defclass learner-agent (agent)
  ((learning-rate :initarg :learning-rate
                  :accessor learner-learning-rate
                  :initform 0.1)
   (experience :initarg :experience
               :accessor learner-experience
               :initform nil))
  (:metaclass agent-metaclass)
  (:documentation "An agent that improves through experience"))
```

---

## Capability System

Capabilities are first-class objects that agents can discover, acquire, create, and share.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; capability.lisp - The capability system
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Capability Definition
;;; ─────────────────────────────────────────────────────────────────

(defclass capability ()
  ((name :initarg :name
         :accessor capability-name
         :documentation "Unique capability name")
   (documentation :initarg :documentation
                  :accessor capability-documentation
                  :initform "")
   (parameters :initarg :parameters
               :accessor capability-parameters
               :initform nil
               :documentation "List of (name type &key required default doc)")
   (returns :initarg :returns
            :accessor capability-returns
            :initform t
            :documentation "Return type specification")
   (implementation :initarg :implementation
                   :accessor capability-implementation
                   :documentation "The actual function")

   ;; Metadata
   (cost :initarg :cost
         :accessor capability-cost
         :initform 0.0
         :documentation "Resource cost to invoke")
   (latency :initarg :latency
            :accessor capability-latency
            :initform :instant
            :documentation ":instant :fast :medium :slow")
   (side-effects :initarg :side-effects
                 :accessor capability-side-effects
                 :initform nil
                 :documentation "List of side effect types")
   (idempotent :initarg :idempotent
               :accessor capability-idempotent-p
               :initform nil
               :documentation "Safe to retry?")

   ;; Composition
   (requires :initarg :requires
             :accessor capability-requires
             :initform nil
             :documentation "Other capabilities required")
   (composes-with :initarg :composes-with
                  :accessor capability-composes-with
                  :initform nil
                  :documentation "Capabilities that work well together")
   (conflicts-with :initarg :conflicts-with
                   :accessor capability-conflicts-with
                   :initform nil
                   :documentation "Capabilities that shouldn't be used together")

   ;; Origin
   (source :initarg :source
           :accessor capability-source
           :initform :builtin
           :documentation ":builtin :acquired :generated :mcp :external")
   (author :initarg :author
           :accessor capability-author
           :initform nil))

  (:documentation "A capability that an agent can use"))

;;; ─────────────────────────────────────────────────────────────────
;;; Capability Definition Macro
;;; ─────────────────────────────────────────────────────────────────

(defmacro defcapability (name lambda-list &body body-and-options)
  "Define a new capability.

   Example:
   (defcapability web-search (query &key (max-results 10) verify-sources)
     \"Search the web for QUERY\"
     :cost 0.02
     :latency :medium
     :side-effects nil
     :composes-with (summarize extract-entities)
     :body
     (perform-web-search query :limit max-results :verify verify-sources))"
  (multiple-value-bind (doc options body)
      (parse-defcapability-body body-and-options)
    (let ((params (parse-capability-params lambda-list)))
      `(register-capability
        (make-instance 'capability
          :name ',name
          :documentation ,doc
          :parameters ',params
          :implementation (lambda ,lambda-list ,@body)
          ,@(loop for (key val) on options by #'cddr
                  unless (eq key :body)
                  append `(,key ,val)))))))

(defun parse-defcapability-body (body)
  "Parse the body of defcapability into (doc options body)."
  (let ((doc (if (stringp (first body)) (pop body) ""))
        (options nil)
        (actual-body nil))
    (loop while body
          for item = (pop body)
          do (if (keywordp item)
                 (if (eq item :body)
                     (setf actual-body body
                           body nil)
                     (push item options)
                     (push (pop body) options))
                 (progn
                   (push item actual-body)
                   (setf actual-body (nconc (nreverse actual-body) body)
                         body nil))))
    (values doc (nreverse options) actual-body)))

(defun parse-capability-params (lambda-list)
  "Parse lambda-list into capability parameter specifications."
  (let ((params nil)
        (mode :required))
    (dolist (item lambda-list (nreverse params))
      (cond
        ((member item '(&optional &key &rest))
         (setf mode item))
        ((eq mode :required)
         (push `(,item t :required t) params))
        ((eq mode '&optional)
         (if (consp item)
             (push `(,(first item) t :default ,(second item)) params)
             (push `(,item t) params)))
        ((eq mode '&key)
         (if (consp item)
             (push `(,(first item) t :default ,(second item)) params)
             (push `(,item t) params)))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Capability Registry
;;; ─────────────────────────────────────────────────────────────────

(defvar *capability-registry* (make-hash-table :test 'eq)
  "Global registry of all known capabilities.")

(defun register-capability (capability)
  "Register CAPABILITY in the global registry."
  (setf (gethash (capability-name capability) *capability-registry*)
        capability)
  capability)

(defun find-capability (name)
  "Find capability by NAME."
  (gethash name *capability-registry*))

(defun list-capabilities (&key source)
  "List all capabilities, optionally filtered by SOURCE."
  (let ((caps nil))
    (maphash (lambda (name cap)
               (declare (ignore name))
               (when (or (null source)
                         (eq (capability-source cap) source))
                 (push cap caps)))
             *capability-registry*)
    caps))

(defun discover-capabilities (criteria)
  "Discover capabilities matching CRITERIA.
   CRITERIA is a plist with :type :cost :latency etc."
  (let ((matches nil))
    (maphash (lambda (name cap)
               (declare (ignore name))
               (when (capability-matches-p cap criteria)
                 (push cap matches)))
             *capability-registry*)
    (sort matches #'< :key #'capability-cost)))

(defun capability-matches-p (cap criteria)
  "Check if CAP matches CRITERIA."
  (loop for (key val) on criteria by #'cddr
        always (case key
                 (:cost (<= (capability-cost cap) val))
                 (:latency (latency<= (capability-latency cap) val))
                 (:side-effects (subsetp (capability-side-effects cap) val))
                 (:source (eq (capability-source cap) val))
                 (t t))))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Capability Management
;;; ─────────────────────────────────────────────────────────────────

(defun grant-capability (agent capability-name)
  "Grant CAPABILITY-NAME to AGENT."
  (let ((cap (find-capability capability-name)))
    (unless cap
      (error 'capability-not-found :name capability-name :agent agent))
    ;; Check requirements
    (dolist (req (capability-requires cap))
      (unless (has-capability-p agent req)
        (error 'autopoiesis-error
               :message (format nil "Capability ~a requires ~a"
                                capability-name req))))
    ;; Grant
    (setf (gethash capability-name (agent-capabilities agent)) cap)
    cap))

(defun revoke-capability (agent capability-name)
  "Revoke CAPABILITY-NAME from AGENT."
  (remhash capability-name (agent-capabilities agent)))

(defun has-capability-p (agent capability-name)
  "Check if AGENT has CAPABILITY-NAME."
  (gethash capability-name (agent-capabilities agent)))

(defun invoke-capability (agent capability-name &rest args)
  "Invoke CAPABILITY-NAME on AGENT with ARGS."
  (let ((cap (gethash capability-name (agent-capabilities agent))))
    (unless cap
      (error 'capability-not-found :name capability-name :agent agent))
    ;; Record the action
    (stream-append (agent-thought-stream agent)
                   (apply #'make-action capability-name args))
    ;; Execute
    (apply (capability-implementation cap) args)))

;;; ─────────────────────────────────────────────────────────────────
;;; Built-in Capabilities
;;; ─────────────────────────────────────────────────────────────────

(defcapability introspect (what)
  "Inspect own internal state"
  :cost 0.0
  :latency :instant
  :side-effects nil
  :source :builtin
  :body
  (ecase what
    (:capabilities (hash-table-keys (agent-capabilities *current-agent*)))
    (:thoughts (stream-to-sexpr (agent-thought-stream *current-agent*)))
    (:bindings (hash-table-alist (agent-bindings *current-agent*)))
    (:status (agent-status *current-agent*))))

(defcapability spawn (agent-spec)
  "Create a new agent"
  :cost 0.1
  :latency :fast
  :side-effects (:creates-agent)
  :source :builtin
  :body
  (spawn-agent agent-spec :parent *current-agent*))

(defcapability communicate (target message)
  "Send a message to another agent"
  :cost 0.01
  :latency :fast
  :side-effects (:sends-message)
  :source :builtin
  :body
  (send-message target message :from *current-agent*))

(defcapability request-human-input (prompt &key context options)
  "Request input from the human operator"
  :cost 0.0
  :latency :slow
  :side-effects (:requests-human)
  :source :builtin
  :body
  (request-human-intervention *current-agent*
                              :prompt prompt
                              :context context
                              :options options))
```

---

## Cognitive Pipeline

The standard flow of agent cognition.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; cognition.lisp - The cognitive pipeline
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Context Window
;;; ─────────────────────────────────────────────────────────────────

(defclass context-window ()
  ((content :initarg :content
            :accessor context-content
            :initform nil
            :documentation "Current context as S-expression")
   (max-size :initarg :max-size
             :accessor context-max-size
             :initform 100000
             :documentation "Maximum context size in tokens/chars")
   (priority-queue :initarg :priority-queue
                   :accessor context-priority-queue
                   :initform (make-priority-queue)
                   :documentation "Items ranked by relevance"))
  (:documentation "The agent's working memory / context window"))

(defun make-context-window (&key (max-size 100000))
  (make-instance 'context-window :max-size max-size))

(defun context-add (context item &key (priority 1.0))
  "Add ITEM to CONTEXT with PRIORITY."
  (pqueue-push (context-priority-queue context) item priority)
  (recompute-context-content context))

(defun context-remove (context item)
  "Remove ITEM from CONTEXT."
  (pqueue-remove (context-priority-queue context) item)
  (recompute-context-content context))

(defun context-focus (context pattern)
  "Boost priority of items matching PATTERN."
  (pqueue-map (context-priority-queue context)
              (lambda (item priority)
                (if (pattern-matches-p pattern item)
                    (* priority 2.0)
                    priority)))
  (recompute-context-content context))

(defun recompute-context-content (context)
  "Rebuild context content from priority queue, respecting max-size."
  (let ((items nil)
        (size 0))
    (pqueue-do (context-priority-queue context)
      (lambda (item priority)
        (declare (ignore priority))
        (let ((item-size (sexpr-size item)))
          (when (< (+ size item-size) (context-max-size context))
            (push item items)
            (incf size item-size)))))
    (setf (context-content context) (nreverse items))))

;;; ─────────────────────────────────────────────────────────────────
;;; The Cognitive Loop
;;; ─────────────────────────────────────────────────────────────────

(defvar *current-agent* nil
  "The currently executing agent (dynamically bound)")

(defvar *cognitive-hooks* (make-hash-table :test 'eq)
  "Hooks called at various points in cognition")

(defun run-agent (agent task)
  "Run AGENT on TASK until completion or pause."
  (let ((*current-agent* agent))
    (setf (agent-status agent) :running
          (agent-current-task agent) task)

    (unwind-protect
         (catch 'agent-pause
           (catch 'agent-terminate
             (cognitive-loop agent task)))

      ;; Cleanup
      (unless (eq (agent-status agent) :terminated)
        (setf (agent-status agent) :idle)))))

(defun cognitive-loop (agent task)
  "Main cognitive loop."
  (loop
    ;; Check for interrupts
    (check-agent-interrupts agent)

    ;; 1. PERCEIVE - Add task/input to context
    (let ((perception (run-cognitive-phase agent :perceive task)))
      (context-add (agent-context-window agent) perception :priority 2.0)

      ;; Create snapshot after perception
      (maybe-create-snapshot agent :after-perceive))

    ;; 2. REASON - Generate thoughts about the situation
    (let ((thoughts (run-cognitive-phase agent :reason
                                         (context-content
                                          (agent-context-window agent)))))
      (dolist (thought thoughts)
        (stream-append (agent-thought-stream agent) thought)))

    ;; 3. DECIDE - Choose what to do
    (let ((decision (run-cognitive-phase agent :decide
                                         (stream-thoughts
                                          (agent-thought-stream agent)))))
      (stream-append (agent-thought-stream agent) decision)

      ;; Create snapshot at decision point
      (maybe-create-snapshot agent :decision))

    ;; 4. ACT - Execute the decision
    (let ((action (decision-chosen (find-latest-decision agent))))
      (when action
        (let ((result (run-cognitive-phase agent :act action)))
          ;; Update action with result
          (setf (action-result (find-action agent action)) result)
          ;; Add result to context
          (context-add (agent-context-window agent)
                       `(action-result ,action ,result)))))

    ;; 5. REFLECT - Metacognition
    (when (should-reflect-p agent)
      (let ((reflection (run-cognitive-phase agent :reflect nil)))
        (when reflection
          (stream-append (agent-thought-stream agent) reflection)
          ;; Apply any self-modifications
          (when (reflection-modification reflection)
            (agent-modify-self agent (reflection-modification reflection))))))

    ;; Check if task is complete
    (when (task-complete-p agent task)
      (return (finalize-task agent task)))))

(defun run-cognitive-phase (agent phase input)
  "Run a single cognitive phase."
  ;; Run pre-hooks
  (run-hooks phase :before agent input)

  ;; Get the cognitive method for this phase
  (let* ((method (compute-cognitive-method agent phase input))
         (result (funcall method agent input)))

    ;; Run post-hooks
    (run-hooks phase :after agent result)

    result))

;;; ─────────────────────────────────────────────────────────────────
;;; Default Cognitive Methods
;;; ─────────────────────────────────────────────────────────────────

(defun default-perceive (agent input)
  "Default perception: wrap input as observation."
  (make-observation input :source :task))

(defun default-reason (agent context)
  "Default reasoning: analyze context, generate thoughts."
  (let ((thoughts nil))
    ;; Decompose task if needed
    (when-let (task (find :task context :key #'car))
      (push (make-thought `(task-analysis ,task)
                          :type :reasoning)
            thoughts))

    ;; Identify relevant capabilities
    (let ((relevant-caps (find-relevant-capabilities context)))
      (when relevant-caps
        (push (make-thought `(relevant-capabilities ,@relevant-caps)
                            :type :planning)
              thoughts)))

    (nreverse thoughts)))

(defun default-decide (agent thoughts)
  "Default decision: evaluate options, choose best."
  (let* ((options (generate-options agent thoughts))
         (scored (score-options agent options))
         (best (first (sort scored #'> :key #'cdr))))
    (make-decision scored (car best)
                   :rationale (generate-rationale agent best scored))))

(defun default-act (agent action)
  "Default action: invoke capability."
  (destructuring-bind (capability &rest args) action
    (apply #'invoke-capability agent capability args)))

(defun default-reflect (agent _)
  "Default reflection: assess recent performance."
  (let* ((recent (recent-thoughts agent 10))
         (pattern (detect-pattern recent))
         (improvement (suggest-improvement pattern)))
    (when improvement
      (make-reflection pattern improvement
                       :modification (improvement-to-modification improvement)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Cognitive Hooks
;;; ─────────────────────────────────────────────────────────────────

(defun add-cognitive-hook (phase timing hook-fn)
  "Add HOOK-FN to be called at TIMING of PHASE.
   PHASE: :perceive :reason :decide :act :reflect
   TIMING: :before :after"
  (let ((key (cons phase timing)))
    (push hook-fn (gethash key *cognitive-hooks*))))

(defun run-hooks (phase timing agent data)
  "Run all hooks for PHASE at TIMING."
  (let ((hooks (gethash (cons phase timing) *cognitive-hooks*)))
    (dolist (hook hooks)
      (funcall hook agent data))))

;; Example hooks

(add-cognitive-hook :decide :before
  (lambda (agent input)
    (when (> (length (agent-pending-actions agent)) 10)
      (warn "Agent ~a has many pending actions" (agent-name agent)))))

(add-cognitive-hook :act :after
  (lambda (agent result)
    (when (typep result 'error)
      (log:error "Action failed for ~a: ~a" (agent-name agent) result))))
```

---

## Self-Modification Engine

The mechanism by which agents extend and modify themselves.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; self-modification.lisp - Agent self-extension
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Modification Types
;;; ─────────────────────────────────────────────────────────────────

(defclass modification ()
  ((type :initarg :type
         :accessor modification-type
         :documentation "Type of modification")
   (target :initarg :target
           :accessor modification-target
           :documentation "What is being modified")
   (change :initarg :change
           :accessor modification-change
           :documentation "The actual change")
   (rationale :initarg :rationale
              :accessor modification-rationale
              :documentation "Why this modification")
   (reversible :initarg :reversible
               :accessor modification-reversible-p
               :initform t)
   (previous-state :initarg :previous-state
                   :accessor modification-previous-state
                   :initform nil
                   :documentation "For rollback"))
  (:documentation "A self-modification to be applied"))

(defun make-modification (type target change &key rationale)
  (make-instance 'modification
                 :type type
                 :target target
                 :change change
                 :rationale rationale))

;;; ─────────────────────────────────────────────────────────────────
;;; Applying Modifications
;;; ─────────────────────────────────────────────────────────────────

(defmethod agent-modify-self ((agent agent) (mod modification))
  "Apply modification MOD to AGENT."
  ;; Validate
  (validate-modification agent mod)

  ;; Save previous state for rollback
  (setf (modification-previous-state mod)
        (capture-modification-target agent mod))

  ;; Apply based on type
  (ecase (modification-type mod)
    (:add-capability
     (apply-add-capability agent mod))
    (:modify-capability
     (apply-modify-capability agent mod))
    (:remove-capability
     (apply-remove-capability agent mod))
    (:add-heuristic
     (apply-add-heuristic agent mod))
    (:modify-decision-engine
     (apply-modify-decision-engine agent mod))
    (:add-cognitive-hook
     (apply-add-cognitive-hook agent mod))
    (:modify-personality
     (apply-modify-personality agent mod))
    (:install-extension
     (apply-install-extension agent mod)))

  ;; Record modification
  (push mod (agent-extensions agent))

  ;; Create snapshot
  (maybe-create-snapshot agent :self-modification)

  mod)

(defun validate-modification (agent mod)
  "Ensure MOD is safe to apply to AGENT."
  (ecase (modification-type mod)
    (:add-capability
     ;; Check if capability source is trusted
     (let ((source (getf (modification-change mod) :source)))
       (when (and (eq source :generated)
                  (eq (agent-capability-permissions agent) :restricted))
         (error 'autopoiesis-error
                :message "Agent cannot add generated capabilities"))))
    (:install-extension
     ;; Validate extension code
     (let ((source (getf (modification-change mod) :source)))
       (multiple-value-bind (valid errors)
           (validate-extension-source source)
         (unless valid
           (error 'autopoiesis-error
                  :message (format nil "Extension validation failed: ~a"
                                   errors))))))
    (t t)))

;;; ─────────────────────────────────────────────────────────────────
;;; Specific Modification Appliers
;;; ─────────────────────────────────────────────────────────────────

(defun apply-add-capability (agent mod)
  "Add a new capability to agent."
  (let* ((change (modification-change mod))
         (cap (if (typep change 'capability)
                  change
                  (apply #'make-instance 'capability change))))
    (setf (capability-source cap) :generated
          (capability-author cap) (agent-id agent))
    (setf (gethash (capability-name cap) (agent-capabilities agent)) cap)))

(defun apply-modify-capability (agent mod)
  "Modify an existing capability."
  (let* ((target (modification-target mod))
         (cap (gethash target (agent-capabilities agent)))
         (changes (modification-change mod)))
    (loop for (slot value) on changes by #'cddr
          do (setf (slot-value cap (intern (string slot) :autopoiesis.agent))
                   value))))

(defun apply-remove-capability (agent mod)
  "Remove a capability from agent."
  (remhash (modification-target mod) (agent-capabilities agent)))

(defun apply-add-heuristic (agent mod)
  "Add a heuristic to the decision engine."
  (let ((heuristic (modification-change mod)))
    (push heuristic
          (decision-engine-heuristics (agent-decision-engine agent)))))

(defun apply-install-extension (agent mod)
  "Install an agent-written extension."
  (let* ((change (modification-change mod))
         (name (getf change :name))
         (source (getf change :source))
         (extension (compile-extension name source
                                       :author (agent-id agent)
                                       :sandbox-level :strict)))
    (install-extension extension)
    ;; Grant any capabilities the extension provides
    (dolist (cap (extension-provides extension))
      (grant-capability agent (first cap)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Rollback
;;; ─────────────────────────────────────────────────────────────────

(defun rollback-modification (agent mod)
  "Undo modification MOD on AGENT."
  (unless (modification-reversible-p mod)
    (error 'autopoiesis-error :message "Modification is not reversible"))

  (let ((previous (modification-previous-state mod)))
    (ecase (modification-type mod)
      (:add-capability
       (remhash (modification-target mod) (agent-capabilities agent)))
      (:modify-capability
       (setf (gethash (modification-target mod) (agent-capabilities agent))
             previous))
      (:remove-capability
       (setf (gethash (modification-target mod) (agent-capabilities agent))
             previous))
      (:install-extension
       (uninstall-extension (getf (modification-change mod) :name)))))

  ;; Remove from extensions list
  (setf (agent-extensions agent)
        (remove mod (agent-extensions agent))))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Macro Definition
;;; ─────────────────────────────────────────────────────────────────

(defun agent-define-macro (agent name lambda-list body)
  "Have AGENT define a new macro for its own use."
  (let* ((macro-fn (compile nil `(lambda ,lambda-list ,@body)))
         (mod (make-modification
               :install-extension
               (agent-id agent)
               `(:name ,(format nil "~a-macro-~a" (agent-name agent) name)
                 :source (defagent-macro ,name ,lambda-list ,@body)
                 :provides ((,name :type :macro)))
               :rationale (format nil "Agent-defined macro: ~a" name))))
    (agent-modify-self agent mod)))

;;; ─────────────────────────────────────────────────────────────────
;;; Learning and Heuristic Generation
;;; ─────────────────────────────────────────────────────────────────

(defun extract-successful-pattern (agent)
  "Analyze recent successful actions to extract a pattern."
  (let* ((recent (recent-actions agent 20))
         (successful (remove-if-not #'action-succeeded-p recent))
         (pattern (find-common-pattern successful)))
    pattern))

(defun pattern-to-heuristic (pattern)
  "Convert a successful pattern into a heuristic."
  (lambda (agent situation)
    (when (pattern-applies-p pattern situation)
      (list (pattern-suggested-action pattern)
            :confidence (pattern-confidence pattern)
            :source :learned))))

(defun install-learned-heuristic (agent pattern)
  "Install a learned heuristic based on PATTERN."
  (let ((heuristic (pattern-to-heuristic pattern))
        (mod (make-modification
              :add-heuristic
              (agent-decision-engine agent)
              heuristic
              :rationale (format nil "Learned from pattern: ~a" pattern))))
    (agent-modify-self agent mod)))
```

---

## Agent Spawning

Dynamic creation of new agents.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; spawner.lisp - Agent creation and lifecycle
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Specifications
;;; ─────────────────────────────────────────────────────────────────

(defclass agent-spec ()
  ((class :initarg :class
          :accessor spec-class
          :initform 'agent)
   (name :initarg :name
         :accessor spec-name
         :initform nil)
   (capabilities :initarg :capabilities
                 :accessor spec-capabilities
                 :initform nil)
   (personality :initarg :personality
                :accessor spec-personality
                :initform nil)
   (initial-context :initarg :initial-context
                    :accessor spec-initial-context
                    :initform nil)
   (task :initarg :task
         :accessor spec-task
         :initform nil))
  (:documentation "Specification for spawning a new agent"))

(defun make-agent-spec (&rest args)
  (apply #'make-instance 'agent-spec args))

;;; ─────────────────────────────────────────────────────────────────
;;; Spawning
;;; ─────────────────────────────────────────────────────────────────

(defvar *agent-registry* (make-hash-table :test 'equal)
  "Registry of all living agents.")

(defun spawn-agent (spec &key parent)
  "Spawn a new agent according to SPEC."
  (let* ((spec (if (typep spec 'agent-spec) spec (parse-agent-spec spec)))
         (agent (make-instance (spec-class spec)
                               :name (or (spec-name spec)
                                         (generate-agent-name))
                               :parent parent)))

    ;; Grant capabilities
    (dolist (cap (spec-capabilities spec))
      (grant-capability agent cap))

    ;; Set personality
    (when (spec-personality spec)
      (setf (agent-personality agent)
            (apply #'make-personality (spec-personality spec))))

    ;; Add initial context
    (when (spec-initial-context spec)
      (dolist (item (spec-initial-context spec))
        (context-add (agent-context-window agent) item)))

    ;; Register
    (setf (gethash (agent-id agent) *agent-registry*) agent)

    ;; Create genesis snapshot
    (create-snapshot agent :type :genesis)

    ;; Start task if provided
    (when (spec-task spec)
      (run-agent agent (spec-task spec)))

    agent))

(defun parse-agent-spec (spec)
  "Parse SPEC (symbol, list, or plist) into agent-spec."
  (etypecase spec
    (agent-spec spec)
    (symbol (make-agent-spec :class spec))
    (list
     (if (keywordp (first spec))
         ;; Plist style: (:class foo :capabilities (a b) :task "do thing")
         (apply #'make-agent-spec spec)
         ;; List style: (specialist-agent (code-review security-audit) "review auth.py")
         (make-agent-spec :class (first spec)
                          :capabilities (second spec)
                          :task (third spec))))))

(defun generate-agent-name ()
  "Generate a unique agent name."
  (format nil "agent-~a" (subseq (make-uuid) 0 8)))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Lifecycle
;;; ─────────────────────────────────────────────────────────────────

(defun terminate-agent (agent &key reason)
  "Terminate AGENT."
  (setf (agent-status agent) :terminated)
  ;; Create final snapshot
  (create-snapshot agent :type :termination :reason reason)
  ;; Remove from registry
  (remhash (agent-id agent) *agent-registry*)
  ;; Notify parent
  (when (agent-parent agent)
    (send-message (agent-parent agent)
                  `(child-terminated ,(agent-id agent) :reason ,reason))))

(defun fork-agent (agent &key modifications)
  "Create a copy of AGENT, optionally with MODIFICATIONS."
  (let* ((sexpr (agent-to-sexpr agent))
         (new-agent (sexpr-to-agent sexpr)))
    ;; Give new identity
    (setf (agent-id new-agent) (make-uuid)
          (agent-name new-agent) (format nil "~a-fork" (agent-name agent))
          (agent-parent new-agent) agent)
    ;; Apply modifications
    (dolist (mod modifications)
      (agent-modify-self new-agent mod))
    ;; Register
    (setf (gethash (agent-id new-agent) *agent-registry*) new-agent)
    ;; Snapshot
    (create-snapshot new-agent :type :fork :source (agent-id agent))
    new-agent))

(defun merge-agents (agent-a agent-b &key conflict-resolution)
  "Merge learning/state from AGENT-B into AGENT-A."
  (let ((conflicts nil))
    ;; Merge capabilities
    (maphash (lambda (name cap)
               (if (has-capability-p agent-a name)
                   (push `(:capability ,name) conflicts)
                   (setf (gethash name (agent-capabilities agent-a)) cap)))
             (agent-capabilities agent-b))

    ;; Merge extensions
    (dolist (ext (agent-extensions agent-b))
      (push ext (agent-extensions agent-a)))

    ;; Merge memory
    (merge-memories (agent-memory agent-a)
                    (agent-memory agent-b)
                    conflict-resolution)

    (values agent-a conflicts)))

;;; ─────────────────────────────────────────────────────────────────
;;; Finding Agents
;;; ─────────────────────────────────────────────────────────────────

(defun find-agent (id)
  "Find agent by ID."
  (gethash id *agent-registry*))

(defun list-agents (&key status parent)
  "List all agents, optionally filtered."
  (let ((agents nil))
    (maphash (lambda (id agent)
               (declare (ignore id))
               (when (and (or (null status) (eq (agent-status agent) status))
                          (or (null parent) (eq (agent-parent agent) parent)))
                 (push agent agents)))
             *agent-registry*)
    agents))

(defun stop-all-agents ()
  "Terminate all running agents."
  (maphash (lambda (id agent)
             (declare (ignore id))
             (when (eq (agent-status agent) :running)
               (terminate-agent agent :reason :shutdown)))
           *agent-registry*))
```

---

## Agent Serialization

Converting agents to and from S-expressions for persistence and transfer.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; serialization.lisp - Agent serialization
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

(defmethod agent-to-sexpr ((agent agent))
  "Serialize AGENT to S-expression."
  `(agent
    :id ,(agent-id agent)
    :name ,(agent-name agent)
    :class ,(class-name (class-of agent))
    :created-at ,(agent-created-at agent)

    :thought-stream ,(stream-to-sexpr (agent-thought-stream agent))
    :context ,(context-to-sexpr (agent-context-window agent))

    :capabilities ,(loop for name being the hash-keys of (agent-capabilities agent)
                         collect name)
    :bindings ,(hash-table-alist (agent-bindings agent))
    :personality ,(personality-to-sexpr (agent-personality agent))

    :extensions ,(mapcar #'extension-to-sexpr (agent-extensions agent))

    :status ,(agent-status agent)))

(defmethod sexpr-to-agent (sexpr)
  "Reconstruct agent from SEXPR."
  (destructuring-bind (&key id name class created-at
                            thought-stream context
                            capabilities bindings personality
                            extensions status)
      (rest sexpr)
    (let ((agent (make-instance class
                                :id id
                                :name name
                                :created-at created-at
                                :status status)))
      ;; Restore thought stream
      (setf (agent-thought-stream agent)
            (sexpr-to-stream thought-stream))

      ;; Restore context
      (setf (agent-context-window agent)
            (sexpr-to-context context))

      ;; Restore capabilities
      (dolist (cap capabilities)
        (when (find-capability cap)
          (grant-capability agent cap)))

      ;; Restore bindings
      (dolist (binding bindings)
        (setf (gethash (car binding) (agent-bindings agent))
              (cdr binding)))

      ;; Restore personality
      (setf (agent-personality agent)
            (sexpr-to-personality personality))

      ;; Restore extensions
      (dolist (ext-sexpr extensions)
        (let ((ext (sexpr-to-extension ext-sexpr)))
          (push ext (agent-extensions agent))))

      agent)))

(defun save-agent (agent path)
  "Save AGENT to PATH."
  (with-open-file (out path :direction :output :if-exists :supersede)
    (let ((*print-readably* t)
          (*print-circle* t))
      (print (agent-to-sexpr agent) out))))

(defun load-agent (path)
  "Load agent from PATH."
  (with-open-file (in path)
    (sexpr-to-agent (read in))))
```

---

## Next Document

Continue to [03-snapshot-system.md](./03-snapshot-system.md) for the snapshot, branching, and time-travel system.
