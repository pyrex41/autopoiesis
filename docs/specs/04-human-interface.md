# Autopoiesis: Human Interface

## Specification Document 04: Human-in-the-Loop Protocol

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

The Human Interface layer enables seamless human oversight and intervention in agent cognition. Humans can observe, interrupt, guide, fork, explore, and merge agent cognitive processes at any point, with the same fluidity that a developer has when working with a REPL.

---

## Design Principles

1. **Zero-friction entry**: Humans can jump in at any moment with no ceremony
2. **Full context**: At any entry point, the human sees complete relevant context
3. **Non-destructive exploration**: Exploring alternatives never loses existing work
4. **Graceful handoff**: Moving between human and agent control is seamless
5. **Complete history**: Every human intervention is recorded in the snapshot DAG

---

## Entry Points

Humans can enter the agent's cognitive loop through several mechanisms:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HUMAN ENTRY POINTS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │   Pause     │  │  Breakpoint │  │   Agent     │  │     Error/          ││
│  │  (Ctrl-C)   │  │  (pre-set)  │  │  Request    │  │   Uncertainty       ││
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘│
│         │                │                │                     │          │
│         ▼                ▼                ▼                     ▼          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      ENTER HUMAN LOOP                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         VIEWPORT                                     │   │
│  │  (what the human sees: context, state, options, history)            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      HUMAN ACTIONS                                   │   │
│  │  navigate | modify | fork | inject | redirect | continue | abort    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Entry Point Types

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; entry-points.lisp - Human entry mechanisms
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.interface)

;;; ─────────────────────────────────────────────────────────────────
;;; Entry Point Definitions
;;; ─────────────────────────────────────────────────────────────────

(deftype entry-type ()
  '(member
    :interrupt           ; Human pressed pause/Ctrl-C
    :breakpoint          ; Pre-configured stop point
    :agent-request       ; Agent explicitly asked for human input
    :decision-fork       ; Agent presenting options for human to choose
    :uncertainty         ; Agent unsure, seeking guidance
    :error               ; Error occurred, human intervention needed
    :milestone           ; Significant progress checkpoint
    :scheduled           ; Time-based or interval-based pause
    :watch-trigger))     ; Watched condition became true

(defclass entry-point ()
  ((type :initarg :type
         :accessor entry-type
         :type entry-type)
   (snapshot :initarg :snapshot
             :accessor entry-snapshot
             :documentation "Snapshot at moment of entry")
   (context :initarg :context
            :accessor entry-context
            :documentation "Additional context for this entry")
   (agent :initarg :agent
          :accessor entry-agent)
   (timestamp :initarg :timestamp
              :accessor entry-timestamp
              :initform (get-precise-time))
   (prompt :initarg :prompt
           :accessor entry-prompt
           :initform nil
           :documentation "Message to show human")
   (suggested-actions :initarg :suggested-actions
                      :accessor entry-suggested-actions
                      :initform nil))
  (:documentation "A point where human can enter agent cognition"))

;;; ─────────────────────────────────────────────────────────────────
;;; Interrupt Handling
;;; ─────────────────────────────────────────────────────────────────

(defvar *interrupt-handlers* nil
  "Stack of interrupt handlers.")

(defun install-interrupt-handler ()
  "Install system interrupt handler for human pause."
  #+sbcl
  (push (lambda (signal info context)
          (declare (ignore signal info context))
          (handle-human-interrupt))
        sb-sys:*interrupt-handlers*)
  #+ccl
  (ccl:set-interrupt-handler
   (lambda (signal)
     (declare (ignore signal))
     (handle-human-interrupt))))

(defun handle-human-interrupt ()
  "Handle Ctrl-C or equivalent interrupt."
  (when *current-agent*
    (let ((snapshot (create-snapshot *current-agent*
                                     :type :human
                                     :trigger :interrupt)))
      (enter-human-loop
       (make-instance 'entry-point
                      :type :interrupt
                      :snapshot snapshot
                      :agent *current-agent*
                      :prompt "Execution paused by user.")))))

;;; ─────────────────────────────────────────────────────────────────
;;; Breakpoints
;;; ─────────────────────────────────────────────────────────────────

(defclass breakpoint ()
  ((id :initarg :id
       :accessor breakpoint-id
       :initform (make-uuid))
   (condition :initarg :condition
              :accessor breakpoint-condition
              :documentation "S-expression condition to evaluate")
   (location :initarg :location
             :accessor breakpoint-location
             :documentation "Where to check: :every-thought :every-action etc")
   (enabled :initarg :enabled
            :accessor breakpoint-enabled-p
            :initform t)
   (hit-count :initarg :hit-count
              :accessor breakpoint-hit-count
              :initform 0)
   (skip-count :initarg :skip-count
               :accessor breakpoint-skip-count
               :initform 0
               :documentation "Skip this many hits before stopping")
   (temporary :initarg :temporary
              :accessor breakpoint-temporary-p
              :initform nil
              :documentation "Delete after first hit"))
  (:documentation "A conditional stopping point"))

(defvar *breakpoints* nil
  "List of active breakpoints.")

(defun set-breakpoint (condition &key (location :every-action) temporary)
  "Set a breakpoint with CONDITION."
  (let ((bp (make-instance 'breakpoint
                           :condition condition
                           :location location
                           :temporary temporary)))
    (push bp *breakpoints*)
    bp))

(defun clear-breakpoint (id)
  "Remove breakpoint with ID."
  (setf *breakpoints*
        (remove id *breakpoints* :key #'breakpoint-id :test #'equal)))

(defun check-breakpoints (agent location)
  "Check if any breakpoint should trigger at LOCATION."
  (dolist (bp *breakpoints*)
    (when (and (breakpoint-enabled-p bp)
               (eq (breakpoint-location bp) location)
               (eval-breakpoint-condition bp agent))
      (incf (breakpoint-hit-count bp))
      (when (>= (breakpoint-hit-count bp) (breakpoint-skip-count bp))
        ;; Hit!
        (when (breakpoint-temporary-p bp)
          (clear-breakpoint (breakpoint-id bp)))
        (return bp)))))

(defun eval-breakpoint-condition (bp agent)
  "Evaluate breakpoint condition in agent context."
  (let ((*current-agent* agent))
    (eval (breakpoint-condition bp))))

;; Convenience macros for setting breakpoints

(defmacro break-when (condition)
  "Break when CONDITION is true."
  `(set-breakpoint ',condition))

(defmacro break-at-decision ()
  "Break at next decision point."
  `(set-breakpoint 't :location :decision :temporary t))

(defmacro break-on-capability (capability-name)
  "Break when CAPABILITY-NAME is about to be invoked."
  `(set-breakpoint '(pending-capability-p ',capability-name)
                   :location :every-action))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent-Initiated Entry
;;; ─────────────────────────────────────────────────────────────────

(defun request-human-input (prompt &key context options default timeout)
  "Agent requests human input. Blocks until human responds."
  (let* ((snapshot (create-snapshot *current-agent*
                                    :type :human
                                    :trigger :agent-request))
         (entry (make-instance 'entry-point
                               :type :agent-request
                               :snapshot snapshot
                               :agent *current-agent*
                               :prompt prompt
                               :context context
                               :suggested-actions options)))
    (let ((response (enter-human-loop entry :timeout timeout)))
      (or response default))))

(defun present-decision (options &key prompt context)
  "Agent presents OPTIONS for human to choose. Returns chosen option."
  (let* ((snapshot (create-snapshot *current-agent*
                                    :type :decision
                                    :trigger :human-decision
                                    :alternatives options))
         (entry (make-instance 'entry-point
                               :type :decision-fork
                               :snapshot snapshot
                               :agent *current-agent*
                               :prompt (or prompt "Please choose an option:")
                               :context context
                               :suggested-actions options)))
    (enter-human-loop entry)))

(defun signal-uncertainty (issue &key confidence context suggestions)
  "Agent signals uncertainty about ISSUE."
  (when (< confidence 0.5)  ; Only bother human if really unsure
    (let* ((snapshot (create-snapshot *current-agent*
                                      :type :human
                                      :trigger :uncertainty))
           (entry (make-instance 'entry-point
                                 :type :uncertainty
                                 :snapshot snapshot
                                 :agent *current-agent*
                                 :prompt (format nil "Uncertain about: ~a (confidence: ~a)"
                                                 issue confidence)
                                 :context context
                                 :suggested-actions suggestions)))
      (enter-human-loop entry))))
```

---

## The Viewport

What the human sees when entering the loop.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; viewport.lisp - Human's view into agent state
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.interface)

;;; ─────────────────────────────────────────────────────────────────
;;; Viewport Class
;;; ─────────────────────────────────────────────────────────────────

(defclass viewport ()
  ((entry-point :initarg :entry-point
                :accessor viewport-entry
                :documentation "How we got here")
   (snapshot :initarg :snapshot
             :accessor viewport-snapshot)
   (agent :initarg :agent
          :accessor viewport-agent)

   ;; What to show
   (context-view :initarg :context-view
                 :accessor viewport-context
                 :documentation "Rendered context window")
   (thought-view :initarg :thought-view
                 :accessor viewport-thoughts
                 :documentation "Recent thoughts")
   (state-view :initarg :state-view
               :accessor viewport-state
               :documentation "Key state variables")
   (decision-view :initarg :decision-view
                  :accessor viewport-decision
                  :documentation "Current decision/alternatives")
   (history-view :initarg :history-view
                 :accessor viewport-history
                 :documentation "Position in snapshot DAG")

   ;; Interaction state
   (detail-level :initarg :detail-level
                 :accessor viewport-detail
                 :initform :standard
                 :documentation ":minimal :standard :detailed :full")
   (focus :initarg :focus
          :accessor viewport-focus
          :initform :overview
          :documentation "What section is focused"))
  (:documentation "The human's window into agent cognition"))

;;; ─────────────────────────────────────────────────────────────────
;;; Creating Viewports
;;; ─────────────────────────────────────────────────────────────────

(defun create-viewport (entry-point)
  "Create a viewport for ENTRY-POINT."
  (let* ((snapshot (entry-snapshot entry-point))
         (agent (entry-agent entry-point)))
    (make-instance 'viewport
      :entry-point entry-point
      :snapshot snapshot
      :agent agent
      :context-view (render-context-view snapshot)
      :thought-view (render-thought-view snapshot)
      :state-view (render-state-view snapshot)
      :decision-view (render-decision-view entry-point)
      :history-view (render-history-view snapshot))))

;;; ─────────────────────────────────────────────────────────────────
;;; Rendering Views
;;; ─────────────────────────────────────────────────────────────────

(defun render-context-view (snapshot &key (max-items 20))
  "Render the context window for display."
  (let ((context (snapshot-context snapshot)))
    (mapcar (lambda (item)
              `(:item ,(truncate-sexpr item 100)
                :type ,(classify-context-item item)
                :age ,(context-item-age item snapshot)))
            (take max-items context))))

(defun render-thought-view (snapshot &key (max-thoughts 10))
  "Render recent thoughts for display."
  (let ((thoughts (parse-thought-stream (snapshot-thought-stream snapshot))))
    (mapcar (lambda (thought)
              `(:id ,(thought-id thought)
                :type ,(thought-type thought)
                :content ,(truncate-sexpr (thought-content thought) 80)
                :confidence ,(thought-confidence thought)
                :timestamp ,(thought-timestamp thought)))
            (take max-thoughts (reverse thoughts)))))

(defun render-state-view (snapshot)
  "Render key state variables."
  (let ((state (snapshot-agent-state snapshot)))
    `(:status ,(getf state :status)
      :current-task ,(truncate-sexpr (getf state :current-task) 60)
      :capabilities ,(length (getf state :capabilities))
      :bindings ,(summarize-bindings (getf state :bindings))
      :confidence ,(calculate-current-confidence state))))

(defun render-decision-view (entry-point)
  "Render decision information if applicable."
  (let ((snapshot (entry-snapshot entry-point)))
    (when (snapshot-decision snapshot)
      (let ((decision (snapshot-decision snapshot)))
        `(:chosen ,(decision-chosen decision)
          :alternatives ,(mapcar (lambda (alt)
                                   `(:option ,(car alt)
                                     :score ,(cdr alt)))
                                 (decision-alternatives decision))
          :rationale ,(decision-rationale decision))))))

(defun render-history-view (snapshot)
  "Render position in snapshot history."
  (let ((branch (snapshot-branch snapshot))
        (depth (count-ancestors snapshot))
        (children (length (snapshot-children-ids snapshot))))
    `(:branch ,branch
      :depth ,depth
      :has-children ,(> children 0)
      :num-children ,children
      :is-decision ,(eq (snapshot-type snapshot) :decision)
      :is-fork ,(eq (snapshot-type snapshot) :fork))))

;;; ─────────────────────────────────────────────────────────────────
;;; Viewport Display
;;; ─────────────────────────────────────────────────────────────────

(defgeneric display-viewport (viewport destination)
  (:documentation "Display VIEWPORT to DESTINATION"))

(defmethod display-viewport (viewport (destination (eql :terminal)))
  "Display viewport to terminal."
  (format t "~&~%")
  (format t "╔══════════════════════════════════════════════════════════════════════════════╗~%")
  (format t "║                           AUTOPOIESIS HUMAN INTERFACE                             ║~%")
  (format t "╠══════════════════════════════════════════════════════════════════════════════╣~%")

  ;; Entry info
  (let ((entry (viewport-entry viewport)))
    (format t "║ Entry: ~12a │ Branch: ~15a │ ~a~%"
            (entry-type entry)
            (snapshot-branch (viewport-snapshot viewport))
            (if (entry-prompt entry)
                (truncate-string (entry-prompt entry) 35)
                "")))

  (format t "╠══════════════════════════════════════════════════════════════════════════════╣~%")

  ;; Context section
  (format t "║ CONTEXT                                                                      ║~%")
  (format t "╟──────────────────────────────────────────────────────────────────────────────╢~%")
  (dolist (item (take 5 (viewport-context viewport)))
    (format t "║  ~a~%" (truncate-string (format nil "~a" (getf item :item)) 75)))

  (format t "╠══════════════════════════════════════════════════════════════════════════════╣~%")

  ;; Recent thoughts
  (format t "║ RECENT THOUGHTS                                                              ║~%")
  (format t "╟──────────────────────────────────────────────────────────────────────────────╢~%")
  (dolist (thought (take 5 (viewport-thoughts viewport)))
    (format t "║  [~8a] ~a~%"
            (getf thought :type)
            (truncate-string (format nil "~a" (getf thought :content)) 60)))

  (format t "╠══════════════════════════════════════════════════════════════════════════════╣~%")

  ;; State summary
  (let ((state (viewport-state viewport)))
    (format t "║ STATE: ~a │ Task: ~a │ Caps: ~a │ Conf: ~,2f~%"
            (getf state :status)
            (truncate-string (format nil "~a" (getf state :current-task)) 25)
            (getf state :capabilities)
            (or (getf state :confidence) 0.0)))

  ;; Decision if present
  (when (viewport-decision viewport)
    (format t "╠══════════════════════════════════════════════════════════════════════════════╣~%")
    (format t "║ DECISION                                                                     ║~%")
    (format t "╟──────────────────────────────────────────────────────────────────────────────╢~%")
    (let ((decision (viewport-decision viewport)))
      (format t "║  Chosen: ~a~%" (truncate-string (format nil "~a" (getf decision :chosen)) 65))
      (format t "║  Alternatives:~%")
      (dolist (alt (take 3 (getf decision :alternatives)))
        (format t "║    - ~a (~,2f)~%"
                (truncate-string (format nil "~a" (getf alt :option)) 55)
                (getf alt :score)))))

  (format t "╠══════════════════════════════════════════════════════════════════════════════╣~%")

  ;; Actions
  (format t "║ ACTIONS: [c]ontinue [j]ump [b]ack [f]ork [i]nject [d]iff [e]xplore [?]help   ║~%")
  (format t "╚══════════════════════════════════════════════════════════════════════════════╝~%"))
```

---

## Human Actions

What the human can do when in the loop.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; actions.lisp - Human action handling
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.interface)

;;; ─────────────────────────────────────────────────────────────────
;;; Action Definitions
;;; ─────────────────────────────────────────────────────────────────

(deftype human-action-type ()
  '(member
    ;; Navigation
    :continue              ; Resume agent execution
    :step                  ; Execute one step, then pause
    :jump                  ; Jump to specific snapshot
    :back                  ; Go to previous snapshot
    :forward               ; Go to next snapshot
    :goto-decision         ; Jump to nearest decision
    :goto-genesis          ; Jump to beginning
    :goto-head             ; Jump to current head

    ;; Modification
    :inject-context        ; Add to agent's context
    :modify-binding        ; Change a variable
    :grant-capability      ; Give agent new capability
    :revoke-capability     ; Remove capability
    :set-task              ; Change current task

    ;; Branching
    :fork                  ; Create new branch here
    :explore-alternative   ; Fork to explore unchosen path
    :merge                 ; Merge branches

    ;; Control
    :redirect              ; Give agent new direction
    :override-decision     ; Change the decision
    :abort                 ; Stop agent entirely
    :spawn-helper          ; Create a helper agent

    ;; Observation
    :inspect               ; Deep inspect something
    :diff                  ; Compare snapshots
    :search                ; Search through history

    ;; Annotation
    :tag                   ; Add tags to snapshot
    :annotate              ; Add notes
    :bookmark))            ; Bookmark this snapshot

(defclass human-action ()
  ((type :initarg :type
         :accessor action-type
         :type human-action-type)
   (payload :initarg :payload
            :accessor action-payload
            :initform nil)
   (timestamp :initarg :timestamp
              :accessor action-timestamp
              :initform (get-precise-time)))
  (:documentation "An action taken by the human"))

;;; ─────────────────────────────────────────────────────────────────
;;; The Human Loop
;;; ─────────────────────────────────────────────────────────────────

(defvar *human-loop-active* nil
  "Whether we're currently in a human loop.")

(defun enter-human-loop (entry-point &key timeout)
  "Enter the human interaction loop. Returns when human chooses to exit."
  (let ((*human-loop-active* t)
        (viewport (create-viewport entry-point))
        (navigator (make-instance 'navigator
                                  :current (entry-snapshot entry-point)
                                  :agent (entry-agent entry-point))))

    ;; Record entry in snapshot
    (create-snapshot (entry-agent entry-point)
                     :type :human
                     :trigger `(:entered-human-loop ,(entry-type entry-point)))

    ;; Display initial viewport
    (display-viewport viewport :terminal)

    ;; Main loop
    (loop
      (let ((action (read-human-action viewport timeout)))
        (when (null action)
          ;; Timeout
          (return-from enter-human-loop nil))

        (let ((result (execute-human-action action viewport navigator)))
          ;; Check if action exits the loop
          (case (action-type action)
            (:continue
             (return-from enter-human-loop :continue))
            (:abort
             (return-from enter-human-loop :abort))
            (:redirect
             (return-from enter-human-loop (action-payload action)))
            (:override-decision
             (return-from enter-human-loop (action-payload action)))
            (t
             ;; Update viewport and continue loop
             (when result
               (setf viewport (update-viewport viewport result))
               (display-viewport viewport :terminal)))))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Reading Human Input
;;; ─────────────────────────────────────────────────────────────────

(defun read-human-action (viewport timeout)
  "Read an action from the human. Returns NIL on timeout."
  (format t "~&> ")
  (force-output)

  (let ((input (if timeout
                   (read-line-with-timeout timeout)
                   (read-line))))
    (when input
      (parse-human-input input viewport))))

(defun parse-human-input (input viewport)
  "Parse human INPUT into a human-action."
  (let ((trimmed (string-trim '(#\Space #\Tab) input)))
    (cond
      ;; Single character commands
      ((string= trimmed "c") (make-instance 'human-action :type :continue))
      ((string= trimmed "b") (make-instance 'human-action :type :back))
      ((string= trimmed "f") (make-instance 'human-action :type :fork))
      ((string= trimmed "?") (make-instance 'human-action :type :help))
      ((string= trimmed "q") (make-instance 'human-action :type :abort))

      ;; Multi-character commands
      ((starts-with trimmed "jump ")
       (make-instance 'human-action
                      :type :jump
                      :payload (subseq trimmed 5)))
      ((starts-with trimmed "inject ")
       (make-instance 'human-action
                      :type :inject-context
                      :payload (read-from-string (subseq trimmed 7))))
      ((starts-with trimmed "tag ")
       (make-instance 'human-action
                      :type :tag
                      :payload (split-string (subseq trimmed 4) #\Space)))
      ((starts-with trimmed "diff ")
       (make-instance 'human-action
                      :type :diff
                      :payload (subseq trimmed 5)))
      ((starts-with trimmed "explore ")
       (make-instance 'human-action
                      :type :explore-alternative
                      :payload (parse-integer (subseq trimmed 8))))
      ((starts-with trimmed "redirect ")
       (make-instance 'human-action
                      :type :redirect
                      :payload (read-from-string (subseq trimmed 9))))

      ;; S-expression input (for complex actions)
      ((char= (char trimmed 0) #\()
       (let ((sexpr (read-from-string trimmed)))
         (sexpr-to-action sexpr)))

      ;; Default: treat as context injection
      (t
       (make-instance 'human-action
                      :type :inject-context
                      :payload `(human-says ,trimmed))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Executing Actions
;;; ─────────────────────────────────────────────────────────────────

(defgeneric execute-human-action (action viewport navigator)
  (:documentation "Execute HUMAN-ACTION, return result for viewport update"))

(defmethod execute-human-action ((action human-action) viewport navigator)
  "Default action execution."
  (let ((agent (viewport-agent viewport))
        (snapshot (viewport-snapshot viewport)))

    (ecase (action-type action)
      ;; Navigation
      (:back
       (step-backward 1 navigator)
       (nav-current navigator))

      (:forward
       (step-forward 1 navigator)
       (nav-current navigator))

      (:jump
       (jump-to (action-payload action) navigator)
       (nav-current navigator))

      (:goto-decision
       (jump-to-decision :previous navigator)
       (nav-current navigator))

      (:step
       ;; Run one cognitive step then pause
       (run-one-step agent)
       (create-snapshot agent :type :human :trigger :step))

      ;; Modification
      (:inject-context
       (context-add (agent-context-window agent)
                    (action-payload action)
                    :priority 2.0)
       (create-snapshot agent :type :human :trigger :inject))

      (:modify-binding
       (destructuring-bind (var value) (action-payload action)
         (setf (gethash var (agent-bindings agent)) value))
       (create-snapshot agent :type :human :trigger :modify))

      (:grant-capability
       (grant-capability agent (action-payload action))
       (create-snapshot agent :type :human :trigger :grant-cap))

      (:revoke-capability
       (revoke-capability agent (action-payload action))
       (create-snapshot agent :type :human :trigger :revoke-cap))

      ;; Branching
      (:fork
       (let* ((name (or (action-payload action)
                        (generate-branch-name snapshot)))
              (branch (fork-from-snapshot (snapshot-id snapshot)
                                          :name name)))
         (switch-branch (branch-name branch))
         branch))

      (:explore-alternative
       (let ((alt-index (action-payload action)))
         (fork-from-snapshot (snapshot-id snapshot)
                             :explore-alternative alt-index)))

      ;; Observation
      (:diff
       (let ((target-id (action-payload action)))
         (diff-snapshots snapshot (load-snapshot target-id))))

      (:inspect
       (inspect-object (action-payload action) agent snapshot))

      (:search
       (search-snapshots (action-payload action)))

      ;; Annotation
      (:tag
       (setf (snapshot-tags snapshot)
             (union (snapshot-tags snapshot)
                    (action-payload action)
                    :test #'equal))
       (save-snapshot snapshot)
       snapshot)

      (:annotate
       (setf (snapshot-notes snapshot)
             (concatenate 'string
                          (or (snapshot-notes snapshot) "")
                          (format nil "~%~a" (action-payload action))))
       (save-snapshot snapshot)
       snapshot)

      (:bookmark
       (bookmark-current (action-payload action) navigator)
       snapshot)

      ;; Help
      (:help
       (display-help)
       nil))))

;;; ─────────────────────────────────────────────────────────────────
;;; Help Display
;;; ─────────────────────────────────────────────────────────────────

(defun display-help ()
  "Display help for human actions."
  (format t "~&
╔══════════════════════════════════════════════════════════════════════════════╗
║                              AUTOPOIESIS HELP                                     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ NAVIGATION                                                                   ║
║   c          Continue execution                                              ║
║   b          Step backward one snapshot                                      ║
║   f          Fork here (create new branch)                                   ║
║   jump <id>  Jump to snapshot ID                                             ║
║   explore N  Fork to explore alternative N                                   ║
║                                                                              ║
║ MODIFICATION                                                                 ║
║   inject <sexpr>      Add to agent context                                   ║
║   redirect <sexpr>    Give agent new direction                               ║
║   (set-binding 'var value)  Modify variable                                  ║
║                                                                              ║
║ OBSERVATION                                                                  ║
║   diff <id>   Compare current with snapshot ID                               ║
║   (inspect 'x)  Deep inspect object                                          ║
║                                                                              ║
║ ANNOTATION                                                                   ║
║   tag t1 t2   Add tags to current snapshot                                   ║
║   note <text> Add note to current snapshot                                   ║
║                                                                              ║
║ CONTROL                                                                      ║
║   q           Abort agent                                                    ║
║   ?           Show this help                                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝
"))
```

---

## Watch System

Automatic triggers for human attention.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; watch.lisp - Automatic attention triggers
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.interface)

;;; ─────────────────────────────────────────────────────────────────
;;; Watch Definitions
;;; ─────────────────────────────────────────────────────────────────

(defclass watch ()
  ((id :initarg :id
       :accessor watch-id
       :initform (make-uuid))
   (name :initarg :name
         :accessor watch-name)
   (condition :initarg :condition
              :accessor watch-condition
              :documentation "S-expression condition to evaluate")
   (action :initarg :action
           :accessor watch-action
           :initform :pause
           :documentation ":pause :notify :log")
   (enabled :initarg :enabled
            :accessor watch-enabled-p
            :initform t)
   (cooldown :initarg :cooldown
             :accessor watch-cooldown
             :initform 0
             :documentation "Minimum seconds between triggers")
   (last-triggered :initarg :last-triggered
                   :accessor watch-last-triggered
                   :initform 0))
  (:documentation "A watched condition that can trigger human attention"))

(defvar *watches* nil
  "List of active watches.")

;;; ─────────────────────────────────────────────────────────────────
;;; Watch Management
;;; ─────────────────────────────────────────────────────────────────

(defun add-watch (name condition &key (action :pause) (cooldown 0))
  "Add a watch for CONDITION."
  (let ((watch (make-instance 'watch
                              :name name
                              :condition condition
                              :action action
                              :cooldown cooldown)))
    (push watch *watches*)
    watch))

(defun remove-watch (name)
  "Remove watch by NAME."
  (setf *watches*
        (remove name *watches* :key #'watch-name :test #'equal)))

(defun check-watches (agent)
  "Check all watches, trigger any that match."
  (let ((now (get-universal-time)))
    (dolist (watch *watches*)
      (when (and (watch-enabled-p watch)
                 (> (- now (watch-last-triggered watch))
                    (watch-cooldown watch))
                 (eval-watch-condition watch agent))
        ;; Triggered!
        (setf (watch-last-triggered watch) now)
        (handle-watch-trigger watch agent)))))

(defun eval-watch-condition (watch agent)
  "Evaluate watch condition in agent context."
  (let ((*current-agent* agent))
    (handler-case
        (eval (watch-condition watch))
      (error () nil))))

(defun handle-watch-trigger (watch agent)
  "Handle a triggered watch."
  (ecase (watch-action watch)
    (:pause
     ;; Enter human loop
     (let ((snapshot (create-snapshot agent
                                      :type :human
                                      :trigger `(:watch ,(watch-name watch)))))
       (enter-human-loop
        (make-instance 'entry-point
                       :type :watch-trigger
                       :snapshot snapshot
                       :agent agent
                       :prompt (format nil "Watch triggered: ~a"
                                       (watch-name watch))))))
    (:notify
     ;; Just notify, don't pause
     (notify-human (format nil "Watch '~a' triggered" (watch-name watch))
                   :agent agent))
    (:log
     ;; Just log
     (log:info "Watch ~a triggered for agent ~a"
               (watch-name watch) (agent-id agent)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Common Watch Patterns
;;; ─────────────────────────────────────────────────────────────────

(defun watch-for-error ()
  "Set up watch for any error condition."
  (add-watch "error-watch"
             '(agent-has-error-p *current-agent*)
             :action :pause))

(defun watch-for-low-confidence (threshold)
  "Watch for agent confidence dropping below THRESHOLD."
  (add-watch "confidence-watch"
             `(< (agent-confidence *current-agent*) ,threshold)
             :action :pause))

(defun watch-for-loop ()
  "Watch for agent getting stuck in a loop."
  (add-watch "loop-watch"
             '(detecting-cognitive-loop-p *current-agent*)
             :action :pause))

(defun watch-for-capability (capability-name)
  "Watch for specific capability being used."
  (add-watch (format nil "cap-watch-~a" capability-name)
             `(capability-invoked-p *current-agent* ',capability-name)
             :action :notify))

(defun watch-for-cost (threshold)
  "Watch for cumulative cost exceeding THRESHOLD."
  (add-watch "cost-watch"
             `(> (agent-cumulative-cost *current-agent*) ,threshold)
             :action :pause))
```

---

## Notification System

Async notifications to humans.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; notifications.lisp - Async human notifications
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.interface)

;;; ─────────────────────────────────────────────────────────────────
;;; Notification Types
;;; ─────────────────────────────────────────────────────────────────

(defclass notification ()
  ((id :initarg :id
       :accessor notification-id
       :initform (make-uuid))
   (type :initarg :type
         :accessor notification-type
         :documentation ":info :warning :error :decision :milestone")
   (message :initarg :message
            :accessor notification-message)
   (agent-id :initarg :agent-id
             :accessor notification-agent)
   (snapshot-id :initarg :snapshot-id
                :accessor notification-snapshot)
   (timestamp :initarg :timestamp
              :accessor notification-timestamp
              :initform (get-universal-time))
   (read :initarg :read
         :accessor notification-read-p
         :initform nil)
   (action-required :initarg :action-required
                    :accessor notification-action-required-p
                    :initform nil))
  (:documentation "A notification for the human"))

(defvar *notification-queue* nil
  "Queue of pending notifications.")

(defvar *notification-handlers* nil
  "List of notification handler functions.")

;;; ─────────────────────────────────────────────────────────────────
;;; Sending Notifications
;;; ─────────────────────────────────────────────────────────────────

(defun notify-human (message &key (type :info) agent snapshot action-required)
  "Send a notification to the human."
  (let ((notification (make-instance 'notification
                                     :type type
                                     :message message
                                     :agent-id (when agent (agent-id agent))
                                     :snapshot-id (when snapshot (snapshot-id snapshot))
                                     :action-required action-required)))
    ;; Add to queue
    (push notification *notification-queue*)

    ;; Call handlers
    (dolist (handler *notification-handlers*)
      (funcall handler notification))

    notification))

(defun add-notification-handler (handler)
  "Add a handler function for notifications."
  (push handler *notification-handlers*))

;; Default handlers

(defun terminal-notification-handler (notification)
  "Display notification in terminal."
  (let ((prefix (ecase (notification-type notification)
                  (:info "ℹ")
                  (:warning "⚠")
                  (:error "✖")
                  (:decision "❓")
                  (:milestone "✓"))))
    (format t "~&~a [~a] ~a~%"
            prefix
            (format-time (notification-timestamp notification))
            (notification-message notification))))

;; Install default handler
(add-notification-handler #'terminal-notification-handler)

;;; ─────────────────────────────────────────────────────────────────
;;; Notification Management
;;; ─────────────────────────────────────────────────────────────────

(defun list-notifications (&key unread-only type)
  "List notifications, optionally filtered."
  (let ((notifs *notification-queue*))
    (when unread-only
      (setf notifs (remove-if #'notification-read-p notifs)))
    (when type
      (setf notifs (remove-if-not (lambda (n)
                                    (eq (notification-type n) type))
                                  notifs)))
    notifs))

(defun mark-notification-read (id)
  "Mark notification as read."
  (let ((notif (find id *notification-queue*
                     :key #'notification-id :test #'equal)))
    (when notif
      (setf (notification-read-p notif) t))))

(defun clear-notifications (&key read-only)
  "Clear notifications."
  (if read-only
      (setf *notification-queue*
            (remove-if #'notification-read-p *notification-queue*))
      (setf *notification-queue* nil)))
```

---

## Session Management

Managing human interaction sessions.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; session.lisp - Human interaction sessions
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.interface)

;;; ─────────────────────────────────────────────────────────────────
;;; Session Class
;;; ─────────────────────────────────────────────────────────────────

(defclass human-session ()
  ((id :initarg :id
       :accessor session-id
       :initform (make-uuid))
   (started-at :initarg :started-at
               :accessor session-started
               :initform (get-universal-time))
   (ended-at :initarg :ended-at
             :accessor session-ended
             :initform nil)
   (agents :initarg :agents
           :accessor session-agents
           :initform nil
           :documentation "Agents interacted with")
   (entry-points :initarg :entry-points
                 :accessor session-entries
                 :initform nil
                 :documentation "All entry points during session")
   (actions :initarg :actions
            :accessor session-actions
            :initform nil
            :documentation "All actions taken")
   (branches-created :initarg :branches-created
                     :accessor session-branches
                     :initform nil)
   (snapshots-visited :initarg :snapshots-visited
                      :accessor session-snapshots
                      :initform nil))
  (:documentation "A human interaction session"))

(defvar *current-session* nil
  "The current human session.")

;;; ─────────────────────────────────────────────────────────────────
;;; Session Lifecycle
;;; ─────────────────────────────────────────────────────────────────

(defun start-session ()
  "Start a new human session."
  (setf *current-session* (make-instance 'human-session))
  (log:info "Human session started: ~a" (session-id *current-session*))
  *current-session*)

(defun end-session ()
  "End the current session."
  (when *current-session*
    (setf (session-ended *current-session*) (get-universal-time))
    (save-session *current-session*)
    (log:info "Human session ended: ~a" (session-id *current-session*))
    (let ((session *current-session*))
      (setf *current-session* nil)
      session)))

(defun save-session (session)
  "Save session for later review."
  (let ((path (session-file-path (session-id session))))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output :if-exists :supersede)
      (print (session-to-sexpr session) out))))

(defun load-session (id)
  "Load a saved session."
  (let ((path (session-file-path id)))
    (when (probe-file path)
      (with-open-file (in path)
        (sexpr-to-session (read in))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Session Recording
;;; ─────────────────────────────────────────────────────────────────

(defun record-entry (entry-point)
  "Record an entry point in the session."
  (when *current-session*
    (push entry-point (session-entries *current-session*))
    (pushnew (entry-agent entry-point) (session-agents *current-session*))))

(defun record-action (action viewport)
  "Record a human action in the session."
  (when *current-session*
    (push (cons action (snapshot-id (viewport-snapshot viewport)))
          (session-actions *current-session*))))

(defun record-visit (snapshot)
  "Record a snapshot visit in the session."
  (when *current-session*
    (pushnew (snapshot-id snapshot) (session-snapshots *current-session*)
             :test #'equal)))

(defun record-branch (branch)
  "Record a branch creation in the session."
  (when *current-session*
    (push (branch-name branch) (session-branches *current-session*))))

;;; ─────────────────────────────────────────────────────────────────
;;; Session Summary
;;; ─────────────────────────────────────────────────────────────────

(defun session-summary (session)
  "Generate a summary of the session."
  `(:id ,(session-id session)
    :duration ,(when (session-ended session)
                 (- (session-ended session) (session-started session)))
    :agents-count ,(length (session-agents session))
    :entries-count ,(length (session-entries session))
    :actions-count ,(length (session-actions session))
    :snapshots-visited ,(length (session-snapshots session))
    :branches-created ,(length (session-branches session))
    :entry-types ,(mapcar #'entry-type (session-entries session))
    :action-types ,(mapcar (lambda (a) (action-type (car a)))
                           (session-actions session))))

(defun print-session-summary (session &optional (stream *standard-output*))
  "Print a human-readable session summary."
  (let ((summary (session-summary session)))
    (format stream "~&Session Summary: ~a~%" (getf summary :id))
    (format stream "Duration: ~a seconds~%" (or (getf summary :duration) "ongoing"))
    (format stream "Agents: ~a~%" (getf summary :agents-count))
    (format stream "Entry points: ~a~%" (getf summary :entries-count))
    (format stream "Actions taken: ~a~%" (getf summary :actions-count))
    (format stream "Snapshots visited: ~a~%" (getf summary :snapshots-visited))
    (format stream "Branches created: ~a~%" (getf summary :branches-created))))
```

---

## Next Document

Continue to [05-visualization.md](./05-visualization.md) for the 3D ECS visualization system specification.
