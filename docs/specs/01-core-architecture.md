# Autopoiesis: Core Architecture

## Specification Document 01: Core Architecture

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

The Core Layer provides the foundational primitives upon which all of Autopoiesis is built. It establishes the homoiconic representation that enables self-modification, introspection, and the seamless interplay between code and data.

---

## System Organization

```
src/
├── core/
│   ├── packages.lisp          ; Package definitions
│   ├── conditions.lisp        ; Error/condition hierarchy
│   ├── protocols.lisp         ; Generic function protocols
│   ├── s-expr.lisp            ; S-expression utilities
│   ├── cognitive-primitives.lisp
│   └── extension-compiler.lisp
├── agent/
│   ├── agent.lisp             ; Base agent class
│   ├── runtime.lisp           ; Agent execution
│   ├── spawner.lisp           ; Dynamic agent creation
│   └── capability.lisp        ; Capability system
├── snapshot/
│   ├── snapshot.lisp          ; Snapshot data structure
│   ├── store.lisp             ; Persistence
│   ├── branch.lisp            ; Branching logic
│   └── diff.lisp              ; State comparison
├── interface/
│   ├── navigator.lisp         ; Human navigation
│   ├── viewport.lisp          ; State viewing
│   └── annotator.lisp         ; Tagging/notes
├── viz/
│   ├── ecs/                   ; Entity-Component-System
│   ├── scene.lisp             ; 3D scene management
│   └── hologram.lisp          ; Visual effects
└── integration/
    ├── claude-bridge.lisp     ; Claude Code integration
    ├── mcp.lisp               ; MCP server support
    └── tools.lisp             ; External tool wrappers
```

---

## Package Structure

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; packages.lisp - Package definitions for Autopoiesis
;;;; ═══════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.core
  (:use #:cl)
  (:export
   ;; S-expression utilities
   #:sexpr-equal
   #:sexpr-hash
   #:sexpr-serialize
   #:sexpr-deserialize
   #:sexpr-diff
   #:sexpr-patch

   ;; Cognitive primitives
   #:thought
   #:decision
   #:action
   #:observation
   #:reflection

   ;; Extension compilation
   #:compile-extension
   #:install-extension
   #:uninstall-extension))

(defpackage #:autopoiesis.agent
  (:use #:cl #:autopoiesis.core)
  (:export
   ;; Agent protocol
   #:agent
   #:agent-id
   #:agent-name
   #:agent-capabilities
   #:agent-state
   #:agent-parent

   ;; Lifecycle
   #:spawn-agent
   #:terminate-agent
   #:fork-agent
   #:merge-agents

   ;; Execution
   #:run-agent
   #:pause-agent
   #:resume-agent
   #:step-agent

   ;; Capabilities
   #:defcapability
   #:capability
   #:find-capability
   #:grant-capability
   #:revoke-capability
   #:capability-registry))

(defpackage #:autopoiesis.snapshot
  (:use #:cl #:autopoiesis.core)
  (:export
   ;; Snapshot
   #:snapshot
   #:snapshot-id
   #:snapshot-parent
   #:snapshot-state
   #:snapshot-timestamp
   #:create-snapshot
   #:restore-snapshot

   ;; Branches
   #:branch
   #:create-branch
   #:switch-branch
   #:merge-branches
   #:list-branches

   ;; Navigation
   #:jump-to
   #:step-forward
   #:step-backward
   #:find-snapshots))

(defpackage #:autopoiesis.interface
  (:use #:cl #:autopoiesis.core #:autopoiesis.agent #:autopoiesis.snapshot)
  (:export
   #:enter-human-loop
   #:exit-human-loop
   #:viewport
   #:create-viewport
   #:navigator
   #:annotate
   #:tag-snapshot))

(defpackage #:autopoiesis.viz
  (:use #:cl #:autopoiesis.core #:autopoiesis.snapshot)
  (:export
   #:start-holodeck
   #:stop-holodeck
   #:update-visualization
   #:focus-on
   #:animate-to))

(defpackage #:autopoiesis
  (:use #:cl)
  (:use-reexport
   #:autopoiesis.core
   #:autopoiesis.agent
   #:autopoiesis.snapshot
   #:autopoiesis.interface
   #:autopoiesis.viz))
```

---

## S-Expression Foundation

The S-expression utilities provide the substrate for all data representation in Autopoiesis.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; s-expr.lisp - S-expression utilities
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.core)

;;; ─────────────────────────────────────────────────────────────────
;;; Structural equality and hashing
;;; ─────────────────────────────────────────────────────────────────

(defun sexpr-equal (a b)
  "Deep structural equality for S-expressions.
   Handles atoms, conses, arrays, and hash-tables."
  (typecase a
    (null (null b))
    (symbol (and (symbolp b) (eq a b)))
    (number (and (numberp b) (= a b)))
    (string (and (stringp b) (string= a b)))
    (cons (and (consp b)
               (sexpr-equal (car a) (car b))
               (sexpr-equal (cdr a) (cdr b))))
    (array (and (arrayp b)
                (equal (array-dimensions a) (array-dimensions b))
                (loop for i below (array-total-size a)
                      always (sexpr-equal (row-major-aref a i)
                                          (row-major-aref b i)))))
    (hash-table (and (hash-table-p b)
                     (= (hash-table-count a) (hash-table-count b))
                     (loop for k being the hash-keys of a using (hash-value v)
                           always (and (gethash k b)
                                       (sexpr-equal v (gethash k b))))))
    (t (equal a b))))

(defun sexpr-hash (sexpr)
  "Content-addressable hash for S-expressions.
   Two structurally equal S-expressions produce the same hash."
  (let ((state (make-hash-state)))
    (sexpr-hash-into state sexpr)
    (finalize-hash state)))

(defun sexpr-hash-into (state sexpr)
  "Incrementally hash an S-expression into STATE."
  (typecase sexpr
    (null (hash-update state #.(char-code #\N)))
    (symbol (hash-update state (symbol-name sexpr)))
    (number (hash-update state (princ-to-string sexpr)))
    (string (hash-update state sexpr))
    (cons
     (hash-update state #.(char-code #\())
     (sexpr-hash-into state (car sexpr))
     (hash-update state #.(char-code #\.))
     (sexpr-hash-into state (cdr sexpr))
     (hash-update state #.(char-code #\))))
    (t (hash-update state (princ-to-string sexpr)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Serialization
;;; ─────────────────────────────────────────────────────────────────

(defparameter *sexpr-serialization-format* :readable
  "Format for serialization: :READABLE (print/read) or :BINARY (compact)")

(defun sexpr-serialize (sexpr &optional (stream nil))
  "Serialize SEXPR to a string or STREAM.
   Uses *SEXPR-SERIALIZATION-FORMAT* to determine output format."
  (ecase *sexpr-serialization-format*
    (:readable
     (let ((*print-readably* t)
           (*print-circle* t)
           (*print-array* t)
           (*print-length* nil)
           (*print-level* nil))
       (if stream
           (prin1 sexpr stream)
           (prin1-to-string sexpr))))
    (:binary
     (sexpr-to-binary sexpr stream))))

(defun sexpr-deserialize (input)
  "Deserialize INPUT (string or stream) to an S-expression."
  (etypecase input
    (string (read-from-string input))
    (stream (read input))))

;;; ─────────────────────────────────────────────────────────────────
;;; Diffing and Patching
;;; ─────────────────────────────────────────────────────────────────

(defstruct (sexpr-edit (:constructor make-edit (type path old new)))
  "An edit operation in an S-expression diff."
  (type nil :type (member :replace :insert :delete))
  (path nil :type list)    ; Path to the location (list of car/cdr indices)
  (old nil)                ; Previous value
  (new nil))               ; New value

(defun sexpr-diff (old new &optional (path nil))
  "Compute minimal diff between OLD and NEW S-expressions.
   Returns a list of SEXPR-EDIT operations."
  (cond
    ;; Identical - no diff
    ((sexpr-equal old new) nil)

    ;; Both conses - recurse
    ((and (consp old) (consp new))
     (append (sexpr-diff (car old) (car new) (append path '(:car)))
             (sexpr-diff (cdr old) (cdr new) (append path '(:cdr)))))

    ;; One is cons, one is atom - replace
    ((or (consp old) (consp new))
     (list (make-edit :replace path old new)))

    ;; Both atoms but different
    (t (list (make-edit :replace path old new)))))

(defun sexpr-patch (sexpr edits)
  "Apply EDITS to SEXPR, returning new S-expression.
   Does not modify original."
  (let ((result (copy-tree sexpr)))
    (dolist (edit edits result)
      (setf result (apply-edit result edit)))))

(defun apply-edit (sexpr edit)
  "Apply a single SEXPR-EDIT to SEXPR."
  (if (null (sexpr-edit-path edit))
      ;; At target location
      (ecase (sexpr-edit-type edit)
        (:replace (sexpr-edit-new edit))
        (:delete nil)
        (:insert (sexpr-edit-new edit)))
      ;; Navigate deeper
      (let ((direction (first (sexpr-edit-path edit)))
            (rest-edit (make-edit (sexpr-edit-type edit)
                                  (rest (sexpr-edit-path edit))
                                  (sexpr-edit-old edit)
                                  (sexpr-edit-new edit))))
        (ecase direction
          (:car (cons (apply-edit (car sexpr) rest-edit) (cdr sexpr)))
          (:cdr (cons (car sexpr) (apply-edit (cdr sexpr) rest-edit)))))))

;;; ─────────────────────────────────────────────────────────────────
;;; S-expression as Code
;;; ─────────────────────────────────────────────────────────────────

(defun sexpr-to-code (sexpr &key (package *package*))
  "Interpret SEXPR as code and compile it.
   Returns a compiled function."
  (let ((*package* package))
    (compile nil (eval `(lambda () ,sexpr)))))

(defun code-to-sexpr (function)
  "Extract the S-expression form of FUNCTION if available.
   Returns NIL if source is not available."
  (function-lambda-expression function))

(defmacro with-sexpr-code ((var sexpr) &body body)
  "Execute BODY with VAR bound to a compiled form of SEXPR.
   The compiled code is cleaned up after."
  `(let ((,var (sexpr-to-code ,sexpr)))
     (unwind-protect
          (progn ,@body)
       ;; Allow GC to clean up compiled code
       (setf ,var nil))))
```

---

## Cognitive Primitives

These are the building blocks for representing agent thought.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; cognitive-primitives.lisp - Basic thought structures
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.core)

;;; ─────────────────────────────────────────────────────────────────
;;; Thought - A unit of agent cognition
;;; ─────────────────────────────────────────────────────────────────

(defclass thought ()
  ((id :initarg :id
       :accessor thought-id
       :initform (make-uuid)
       :documentation "Unique identifier for this thought")
   (timestamp :initarg :timestamp
              :accessor thought-timestamp
              :initform (get-universal-time)
              :documentation "When this thought occurred")
   (content :initarg :content
            :accessor thought-content
            :initform nil
            :documentation "The S-expression content of the thought")
   (type :initarg :type
         :accessor thought-type
         :initform :generic
         :documentation "Category: :reasoning :planning :executing :reflecting")
   (confidence :initarg :confidence
               :accessor thought-confidence
               :initform 1.0
               :documentation "Agent's confidence in this thought [0, 1]")
   (provenance :initarg :provenance
               :accessor thought-provenance
               :initform nil
               :documentation "What triggered this thought"))
  (:documentation "A single unit of agent cognition, represented as S-expression"))

(defmethod print-object ((thought thought) stream)
  (print-unreadable-object (thought stream :type t :identity t)
    (format stream "~a ~a"
            (thought-type thought)
            (truncate-string (prin1-to-string (thought-content thought)) 40))))

(defun make-thought (content &key (type :generic) (confidence 1.0) provenance)
  "Create a new thought with CONTENT."
  (make-instance 'thought
                 :content content
                 :type type
                 :confidence confidence
                 :provenance provenance))

(defun thought-to-sexpr (thought)
  "Convert THOUGHT to a pure S-expression representation."
  `(thought
    :id ,(thought-id thought)
    :timestamp ,(thought-timestamp thought)
    :type ,(thought-type thought)
    :confidence ,(thought-confidence thought)
    :content ,(thought-content thought)
    :provenance ,(thought-provenance thought)))

(defun sexpr-to-thought (sexpr)
  "Reconstruct a THOUGHT from its S-expression representation."
  (destructuring-bind (&key id timestamp type confidence content provenance)
      (rest sexpr)
    (make-instance 'thought
                   :id id
                   :timestamp timestamp
                   :type type
                   :confidence confidence
                   :content content
                   :provenance provenance)))

;;; ─────────────────────────────────────────────────────────────────
;;; Decision - A choice point with alternatives
;;; ─────────────────────────────────────────────────────────────────

(defclass decision (thought)
  ((alternatives :initarg :alternatives
                 :accessor decision-alternatives
                 :initform nil
                 :documentation "List of (option . score) pairs considered")
   (chosen :initarg :chosen
           :accessor decision-chosen
           :initform nil
           :documentation "The selected option")
   (rationale :initarg :rationale
              :accessor decision-rationale
              :initform nil
              :documentation "Why this option was chosen"))
  (:default-initargs :type :decision)
  (:documentation "A decision point where the agent chose between alternatives"))

(defun make-decision (alternatives chosen &key rationale confidence)
  "Create a decision recording the choice between ALTERNATIVES."
  (make-instance 'decision
                 :alternatives alternatives
                 :chosen chosen
                 :rationale rationale
                 :confidence (or confidence
                                 (cdr (assoc chosen alternatives)))))

(defun decision-unchosen (decision)
  "Return the alternatives that were NOT chosen."
  (remove (decision-chosen decision)
          (decision-alternatives decision)
          :key #'car))

;;; ─────────────────────────────────────────────────────────────────
;;; Action - An effect on the world
;;; ─────────────────────────────────────────────────────────────────

(defclass action (thought)
  ((capability :initarg :capability
               :accessor action-capability
               :initform nil
               :documentation "Which capability is being invoked")
   (arguments :initarg :arguments
              :accessor action-arguments
              :initform nil
              :documentation "Arguments to the capability")
   (result :initarg :result
           :accessor action-result
           :initform :pending
           :documentation "Result of the action, or :PENDING")
   (side-effects :initarg :side-effects
                 :accessor action-side-effects
                 :initform nil
                 :documentation "Observable side effects"))
  (:default-initargs :type :action)
  (:documentation "An action taken by the agent"))

(defun make-action (capability &rest arguments)
  "Create an action invoking CAPABILITY with ARGUMENTS."
  (make-instance 'action
                 :capability capability
                 :arguments arguments
                 :content `(,capability ,@arguments)))

;;; ─────────────────────────────────────────────────────────────────
;;; Observation - Input from the world
;;; ─────────────────────────────────────────────────────────────────

(defclass observation (thought)
  ((source :initarg :source
           :accessor observation-source
           :initform :external
           :documentation "Where this observation came from")
   (raw :initarg :raw
        :accessor observation-raw
        :initform nil
        :documentation "Raw unprocessed form")
   (interpreted :initarg :interpreted
                :accessor observation-interpreted
                :initform nil
                :documentation "Agent's interpretation"))
  (:default-initargs :type :observation)
  (:documentation "An observation of external state"))

(defun make-observation (raw &key source interpreted)
  "Create an observation of RAW data."
  (make-instance 'observation
                 :raw raw
                 :source source
                 :interpreted interpreted
                 :content (or interpreted raw)))

;;; ─────────────────────────────────────────────────────────────────
;;; Reflection - Metacognition
;;; ─────────────────────────────────────────────────────────────────

(defclass reflection (thought)
  ((target :initarg :target
           :accessor reflection-target
           :initform nil
           :documentation "What is being reflected upon (thought ID or pattern)")
   (insight :initarg :insight
            :accessor reflection-insight
            :initform nil
            :documentation "The metacognitive insight")
   (modification :initarg :modification
                 :accessor reflection-modification
                 :initform nil
                 :documentation "Self-modification triggered by this reflection"))
  (:default-initargs :type :reflection)
  (:documentation "Agent reflecting on its own cognition"))

(defun make-reflection (target insight &key modification)
  "Create a reflection on TARGET with INSIGHT."
  (make-instance 'reflection
                 :target target
                 :insight insight
                 :modification modification
                 :content `(reflect-on ,target :insight ,insight)))

;;; ─────────────────────────────────────────────────────────────────
;;; Thought Stream - Sequence of thoughts
;;; ─────────────────────────────────────────────────────────────────

(defclass thought-stream ()
  ((thoughts :initarg :thoughts
             :accessor stream-thoughts
             :initform (make-array 0 :adjustable t :fill-pointer 0)
             :documentation "Vector of thoughts in order")
   (indices :initarg :indices
            :accessor stream-indices
            :initform (make-hash-table :test 'equal)
            :documentation "ID -> position index"))
  (:documentation "An ordered stream of thoughts with fast lookup"))

(defun stream-append (stream thought)
  "Append THOUGHT to STREAM."
  (let ((pos (vector-push-extend thought (stream-thoughts stream))))
    (setf (gethash (thought-id thought) (stream-indices stream)) pos)
    thought))

(defun stream-find (stream id)
  "Find thought by ID in STREAM."
  (let ((pos (gethash id (stream-indices stream))))
    (when pos
      (aref (stream-thoughts stream) pos))))

(defun stream-since (stream timestamp)
  "Get all thoughts since TIMESTAMP."
  (remove-if (lambda (t) (< (thought-timestamp t) timestamp))
             (coerce (stream-thoughts stream) 'list)))

(defun stream-by-type (stream type)
  "Get all thoughts of TYPE."
  (remove-if-not (lambda (t) (eq (thought-type t) type))
                 (coerce (stream-thoughts stream) 'list)))

(defun stream-to-sexpr (stream)
  "Convert entire stream to S-expression."
  (map 'list #'thought-to-sexpr (stream-thoughts stream)))
```

---

## Condition Hierarchy

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; conditions.lisp - Error and condition hierarchy
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.core)

;;; ─────────────────────────────────────────────────────────────────
;;; Base conditions
;;; ─────────────────────────────────────────────────────────────────

(define-condition autopoiesis-condition ()
  ((message :initarg :message
            :reader condition-message
            :initform ""))
  (:documentation "Base condition for all Autopoiesis conditions"))

(define-condition autopoiesis-error (autopoiesis-condition error)
  ()
  (:report (lambda (c s)
             (format s "Autopoiesis error: ~a" (condition-message c))))
  (:documentation "Base error for all Autopoiesis errors"))

(define-condition autopoiesis-warning (autopoiesis-condition warning)
  ()
  (:report (lambda (c s)
             (format s "Autopoiesis warning: ~a" (condition-message c)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent conditions
;;; ─────────────────────────────────────────────────────────────────

(define-condition agent-error (autopoiesis-error)
  ((agent :initarg :agent :reader error-agent))
  (:report (lambda (c s)
             (format s "Agent ~a error: ~a"
                     (agent-id (error-agent c))
                     (condition-message c)))))

(define-condition capability-not-found (agent-error)
  ((capability-name :initarg :name :reader error-capability-name))
  (:report (lambda (c s)
             (format s "Capability ~a not found for agent ~a"
                     (error-capability-name c)
                     (agent-id (error-agent c))))))

(define-condition agent-paused (autopoiesis-condition)
  ((agent :initarg :agent :reader condition-agent)
   (reason :initarg :reason :reader pause-reason :initform :user-request))
  (:documentation "Signaled when an agent is paused"))

(define-condition human-intervention-requested (autopoiesis-condition)
  ((agent :initarg :agent :reader condition-agent)
   (context :initarg :context :reader intervention-context))
  (:documentation "Agent is requesting human intervention"))

;;; ─────────────────────────────────────────────────────────────────
;;; Snapshot conditions
;;; ─────────────────────────────────────────────────────────────────

(define-condition snapshot-error (autopoiesis-error)
  ((snapshot-id :initarg :snapshot-id :reader error-snapshot-id)))

(define-condition snapshot-not-found (snapshot-error)
  ()
  (:report (lambda (c s)
             (format s "Snapshot ~a not found" (error-snapshot-id c)))))

(define-condition branch-conflict (snapshot-error)
  ((branch-a :initarg :branch-a :reader conflict-branch-a)
   (branch-b :initarg :branch-b :reader conflict-branch-b)
   (conflicts :initarg :conflicts :reader merge-conflicts))
  (:report (lambda (c s)
             (format s "Merge conflict between ~a and ~a: ~a conflicts"
                     (conflict-branch-a c)
                     (conflict-branch-b c)
                     (length (merge-conflicts c))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Restart definitions
;;; ─────────────────────────────────────────────────────────────────

(defun establish-autopoiesis-restarts (thunk)
  "Run THUNK with standard Autopoiesis restarts established."
  (restart-case (funcall thunk)
    (continue-anyway ()
      :report "Continue execution despite the error"
      nil)
    (use-value (value)
      :report "Use a specific value"
      :interactive (lambda () (list (eval (read))))
      value)
    (retry-with-human ()
      :report "Pause and request human intervention"
      (signal 'human-intervention-requested))
    (abort-agent ()
      :report "Abort the current agent"
      (throw 'abort-agent nil))))
```

---

## Extension Compiler

This enables agents to write and install new code.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; extension-compiler.lisp - Agent-written code compilation
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.core)

;;; ─────────────────────────────────────────────────────────────────
;;; Extension representation
;;; ─────────────────────────────────────────────────────────────────

(defclass extension ()
  ((name :initarg :name
         :accessor extension-name
         :documentation "Unique name for this extension")
   (source :initarg :source
           :accessor extension-source
           :documentation "S-expression source code")
   (compiled :initarg :compiled
             :accessor extension-compiled
             :initform nil
             :documentation "Compiled form")
   (author :initarg :author
           :accessor extension-author
           :initform nil
           :documentation "Agent that created this extension")
   (created :initarg :created
            :accessor extension-created
            :initform (get-universal-time))
   (dependencies :initarg :dependencies
                 :accessor extension-dependencies
                 :initform nil
                 :documentation "Other extensions this depends on")
   (provides :initarg :provides
             :accessor extension-provides
             :initform nil
             :documentation "Capabilities this extension provides")
   (sandbox-level :initarg :sandbox-level
                  :accessor extension-sandbox-level
                  :initform :strict
                  :documentation ":strict, :moderate, or :trusted"))
  (:documentation "An agent-written extension"))

;;; ─────────────────────────────────────────────────────────────────
;;; Sandboxed compilation
;;; ─────────────────────────────────────────────────────────────────

(defparameter *sandbox-allowed-symbols*
  '(;; Core Lisp (safe subset)
    lambda let let* if cond case when unless
    progn prog1 prog2 block return-from
    and or not
    car cdr cons list list* append
    first second third rest
    length nth elt subseq
    map mapcar mapc reduce remove remove-if remove-if-not
    find find-if find-if-not position
    + - * / mod floor ceiling round
    = < > <= >= /= min max
    eq eql equal equalp
    null atom listp consp numberp stringp symbolp
    format princ prin1

    ;; Autopoiesis cognitive primitives
    make-thought make-decision make-action make-observation make-reflection
    thought-content thought-type thought-confidence

    ;; Safe autopoiesis operations
    autopoiesis.agent:find-capability
    autopoiesis.agent:capability-documentation
    autopoiesis.agent:capability-parameters)
  "Symbols allowed in sandboxed agent code.")

(defparameter *sandbox-forbidden-patterns*
  '((eval . "Direct eval is forbidden")
    (compile . "Direct compile is forbidden")
    (load . "Loading files is forbidden")
    (delete-file . "File deletion is forbidden")
    (run-program . "External programs are forbidden")
    (sb-ext: . "Implementation-specific extensions are forbidden")
    (ccl: . "Implementation-specific extensions are forbidden")
    (uiop:run-program . "External programs are forbidden"))
  "Patterns forbidden in agent code, with explanations.")

(defun validate-extension-source (source)
  "Validate that SOURCE is safe to compile.
   Returns (values valid-p errors)."
  (let ((errors nil))
    (labels ((check-form (form)
               (cond
                 ;; Atoms - check if allowed
                 ((symbolp form)
                  (unless (or (member form *sandbox-allowed-symbols*)
                              (keywordp form)
                              (null (symbol-package form)))
                    (push (format nil "Symbol ~a is not in allowed list" form)
                          errors)))
                 ;; Lists - check each element and special forms
                 ((consp form)
                  (let ((head (car form)))
                    ;; Check forbidden patterns
                    (dolist (forbidden *sandbox-forbidden-patterns*)
                      (when (eq head (car forbidden))
                        (push (cdr forbidden) errors)))
                    ;; Recurse
                    (mapc #'check-form form))))))
      (check-form source)
      (values (null errors) (nreverse errors)))))

(defun compile-extension (name source &key author dependencies sandbox-level)
  "Compile SOURCE into an extension.
   Validates safety before compilation."
  (let ((level (or sandbox-level :strict)))
    ;; Validate if sandboxed
    (when (member level '(:strict :moderate))
      (multiple-value-bind (valid errors)
          (validate-extension-source source)
        (unless valid
          (error 'autopoiesis-error
                 :message (format nil "Extension validation failed: ~{~a~^, ~}"
                                  errors)))))

    ;; Compile
    (let ((extension (make-instance 'extension
                                    :name name
                                    :source source
                                    :author author
                                    :dependencies dependencies
                                    :sandbox-level level)))
      (setf (extension-compiled extension)
            (compile nil `(lambda () ,source)))
      extension)))

;;; ─────────────────────────────────────────────────────────────────
;;; Extension registry and installation
;;; ─────────────────────────────────────────────────────────────────

(defvar *extension-registry* (make-hash-table :test 'equal)
  "Global registry of installed extensions.")

(defun install-extension (extension &key (registry *extension-registry*))
  "Install EXTENSION into REGISTRY, making it available."
  ;; Check dependencies
  (dolist (dep (extension-dependencies extension))
    (unless (gethash dep registry)
      (error 'autopoiesis-error
             :message (format nil "Missing dependency: ~a" dep))))

  ;; Install
  (setf (gethash (extension-name extension) registry) extension)

  ;; If it provides capabilities, register them
  (dolist (cap-spec (extension-provides extension))
    (apply #'register-provided-capability cap-spec))

  extension)

(defun uninstall-extension (name &key (registry *extension-registry*))
  "Remove extension NAME from REGISTRY."
  (let ((extension (gethash name registry)))
    (when extension
      ;; Remove provided capabilities
      (dolist (cap-spec (extension-provides extension))
        (unregister-provided-capability (first cap-spec)))
      ;; Remove from registry
      (remhash name registry)
      t)))

(defun find-extension (name &key (registry *extension-registry*))
  "Find extension by NAME."
  (gethash name registry))

(defun execute-extension (extension &rest args)
  "Execute a compiled extension with ARGS."
  (apply (extension-compiled extension) args))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent macro system
;;; ─────────────────────────────────────────────────────────────────

(defvar *agent-macros* (make-hash-table :test 'eq)
  "Macros defined by agents for use in their cognition.")

(defmacro defagent-macro (name lambda-list &body body)
  "Define a macro that agents can use in their cognitive code.
   These are expanded before sandboxing validation."
  `(setf (gethash ',name *agent-macros*)
         (lambda ,lambda-list ,@body)))

(defun expand-agent-macros (form)
  "Expand any agent macros in FORM."
  (cond
    ((atom form) form)
    ((gethash (car form) *agent-macros*)
     (expand-agent-macros
      (apply (gethash (car form) *agent-macros*) (cdr form))))
    (t (mapcar #'expand-agent-macros form))))

;; Example agent macros
(defagent-macro with-confidence (conf &body body)
  "Execute BODY, recording that agent has CONF confidence."
  `(let ((*current-confidence* ,conf))
     ,@body))

(defagent-macro carefully (&body body)
  "Execute BODY with additional verification."
  `(progn
     (verify-preconditions)
     (prog1 (progn ,@body)
       (verify-postconditions))))
```

---

## Configuration

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; config.lisp - System configuration
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.core)

(defvar *autopoiesis-config* nil
  "Current Autopoiesis configuration.")

(defclass autopoiesis-config ()
  ((snapshot-frequency :initarg :snapshot-frequency
                       :accessor config-snapshot-frequency
                       :initform :every-action
                       :documentation ":every-thought, :every-action, :on-decision")
   (snapshot-store-path :initarg :snapshot-store-path
                        :accessor config-snapshot-store-path
                        :initform #P"~/.autopoiesis/snapshots/")
   (max-snapshot-history :initarg :max-snapshot-history
                         :accessor config-max-snapshot-history
                         :initform 10000)
   (default-sandbox-level :initarg :default-sandbox-level
                          :accessor config-default-sandbox-level
                          :initform :strict)
   (enable-visualization :initarg :enable-visualization
                         :accessor config-enable-visualization
                         :initform t)
   (visualization-backend :initarg :visualization-backend
                          :accessor config-visualization-backend
                          :initform :trial  ; or :raylib, :mccl
                          :documentation "3D rendering backend")
   (claude-bridge-enabled :initarg :claude-bridge-enabled
                          :accessor config-claude-bridge-enabled
                          :initform t)
   (mcp-servers :initarg :mcp-servers
                :accessor config-mcp-servers
                :initform nil
                :documentation "List of MCP server configurations"))
  (:documentation "Global Autopoiesis configuration"))

(defun load-config (&optional (path #P"~/.autopoiesis/config.lisp"))
  "Load configuration from PATH."
  (if (probe-file path)
      (setf *autopoiesis-config* (eval (read-from-file path)))
      (setf *autopoiesis-config* (make-instance 'autopoiesis-config))))

(defun save-config (&optional (path #P"~/.autopoiesis/config.lisp"))
  "Save current configuration to PATH."
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output :if-exists :supersede)
    (let ((*print-readably* t))
      (print (config-to-sexpr *autopoiesis-config*) out))))

(defun config-to-sexpr (config)
  "Convert CONFIG to S-expression for serialization."
  `(make-instance 'autopoiesis-config
     :snapshot-frequency ,(config-snapshot-frequency config)
     :snapshot-store-path ,(config-snapshot-store-path config)
     :max-snapshot-history ,(config-max-snapshot-history config)
     :default-sandbox-level ,(config-default-sandbox-level config)
     :enable-visualization ,(config-enable-visualization config)
     :visualization-backend ,(config-visualization-backend config)
     :claude-bridge-enabled ,(config-claude-bridge-enabled config)
     :mcp-servers ',(config-mcp-servers config)))
```

---

## Initialization

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; init.lisp - System initialization
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis)

(defun initialize (&key (config-path #P"~/.autopoiesis/config.lisp")
                        (load-extensions t))
  "Initialize the Autopoiesis system."
  ;; Load configuration
  (autopoiesis.core:load-config config-path)

  ;; Initialize snapshot store
  (autopoiesis.snapshot:initialize-store
   (autopoiesis.core:config-snapshot-store-path autopoiesis.core:*autopoiesis-config*))

  ;; Initialize capability registry
  (autopoiesis.agent:initialize-capabilities)

  ;; Load saved extensions
  (when load-extensions
    (autopoiesis.core:load-extensions))

  ;; Initialize visualization if enabled
  (when (autopoiesis.core:config-enable-visualization autopoiesis.core:*autopoiesis-config*)
    (autopoiesis.viz:initialize-renderer
     (autopoiesis.core:config-visualization-backend autopoiesis.core:*autopoiesis-config*)))

  ;; Initialize Claude bridge if enabled
  (when (autopoiesis.core:config-claude-bridge-enabled autopoiesis.core:*autopoiesis-config*)
    (autopoiesis.integration:initialize-claude-bridge))

  ;; Initialize MCP servers
  (dolist (server-config (autopoiesis.core:config-mcp-servers autopoiesis.core:*autopoiesis-config*))
    (autopoiesis.integration:connect-mcp-server server-config))

  (format t "~&Autopoiesis initialized.~%")
  t)

(defun shutdown ()
  "Cleanly shut down the Autopoiesis system."
  ;; Stop all running agents
  (autopoiesis.agent:stop-all-agents)

  ;; Flush snapshot store
  (autopoiesis.snapshot:flush-store)

  ;; Shutdown visualization
  (when (autopoiesis.core:config-enable-visualization autopoiesis.core:*autopoiesis-config*)
    (autopoiesis.viz:shutdown-renderer))

  ;; Disconnect MCP servers
  (autopoiesis.integration:disconnect-all-mcp-servers)

  ;; Save config
  (autopoiesis.core:save-config)

  (format t "~&Autopoiesis shut down.~%")
  t)
```

---

## Next Document

Continue to [02-cognitive-model.md](./02-cognitive-model.md) for the agent cognition system, capability architecture, and self-modification mechanisms.
