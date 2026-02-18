;;;; prompt-registry.lisp - First-class versioned prompts
;;;;
;;;; Makes prompts runtime artifacts: versioned in the substrate,
;;;; queryable via a registry, composable via templating, and forkable
;;;; by agents. Enables the self-extension story: agents can read,
;;;; fork, and evolve their own prompts.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; CLOS Class
;;; ===================================================================

(defclass prompt-template ()
  ((name :initarg :name
         :accessor prompt-name
         :documentation "Unique prompt name (string)")
   (category :initarg :category
             :accessor prompt-category
             :initform :custom
             :documentation "Category keyword for grouping")
   (body :initarg :body
         :accessor prompt-body
         :documentation "Template body text with {{variable}} placeholders")
   (version :initarg :version
            :accessor prompt-version
            :initform 1
            :documentation "Version number, auto-incremented on re-registration")
   (content-hash :initarg :content-hash
                 :accessor prompt-content-hash
                 :initform nil
                 :documentation "SHA256 hash of the body for content-addressing")
   (parent :initarg :parent
           :accessor prompt-parent
           :initform nil
           :documentation "Content-hash of the parent prompt (for forking lineage)")
   (author :initarg :author
           :accessor prompt-author
           :initform "system"
           :documentation "Who created this version")
   (variables :initarg :variables
              :accessor prompt-variables
              :initform nil
              :documentation "List of variable name strings expected in the body")
   (includes :initarg :includes
             :accessor prompt-includes
             :initform nil
             :documentation "List of prompt names referenced via {{include:name}}")
   (created-at :initarg :created-at
               :accessor prompt-created-at
               :initform (get-universal-time)
               :documentation "Universal time of creation"))
  (:documentation "A versioned, composable prompt template."))

(defmethod print-object ((p prompt-template) stream)
  (print-unreadable-object (p stream :type t)
    (format stream "~a v~d (~a)"
            (prompt-name p) (prompt-version p) (prompt-category p))))

;;; ===================================================================
;;; Registry Globals
;;; ===================================================================

(defvar *prompt-registry* (make-hash-table :test 'equal)
  "Name -> current prompt-template mapping.")

(defvar *prompt-history* (make-hash-table :test 'equal)
  "Name -> list of all prompt-template versions (newest first).")

;;; ===================================================================
;;; Constructor
;;; ===================================================================

(defun make-prompt-template (&key name category body variables includes author parent)
  "Create a new prompt-template, auto-computing content-hash."
  (unless (and name (stringp name) (> (length name) 0))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Prompt name must be a non-empty string"))
  (unless (and body (stringp body))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Prompt body must be a string"))
  (make-instance 'prompt-template
                 :name name
                 :category (or category :custom)
                 :body body
                 :variables (or variables nil)
                 :includes (or includes nil)
                 :author (or author "system")
                 :parent parent
                 :content-hash (autopoiesis.core:sexpr-hash body)))

;;; ===================================================================
;;; Registry API
;;; ===================================================================

(defun register-prompt (prompt)
  "Register or update a prompt in the registry.
   If a prompt with the same name exists, auto-increment version and link parent."
  (let* ((name (prompt-name prompt))
         (existing (gethash name *prompt-registry*)))
    (when existing
      ;; Auto-version: bump version, link parent
      (setf (prompt-version prompt) (1+ (prompt-version existing)))
      (setf (prompt-parent prompt) (prompt-content-hash existing)))
    ;; Store as current
    (setf (gethash name *prompt-registry*) prompt)
    ;; Prepend to history
    (push prompt (gethash name *prompt-history*))
    prompt))

(defun find-prompt (name &key version)
  "Look up a prompt by name. If VERSION is given, return that specific version.
   Returns NIL if not found."
  (if version
      ;; Search history for specific version
      (find version (gethash name *prompt-history*)
            :key #'prompt-version)
      ;; Return current
      (gethash name *prompt-registry*)))

(defun list-prompts (&key category)
  "List all registered prompts. If CATEGORY given, filter by it."
  (let ((all nil))
    (maphash (lambda (name prompt)
               (declare (ignore name))
               (when (or (null category)
                         (eq category (prompt-category prompt)))
                 (push prompt all)))
             *prompt-registry*)
    (sort all #'string< :key #'prompt-name)))

(defun unregister-prompt (name)
  "Remove a prompt from the registry. Returns T if removed, NIL if not found."
  (let ((existed (gethash name *prompt-registry*)))
    (when existed
      (remhash name *prompt-registry*)
      (remhash name *prompt-history*)
      t)))

(defun fork-prompt (name &key new-name new-body author)
  "Create a derived prompt from an existing one.
   NEW-NAME defaults to NAME (creating a new version).
   NEW-BODY defaults to the parent's body."
  (let ((parent (find-prompt name)))
    (unless parent
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Cannot fork: prompt ~a not found" name)))
    (let ((forked (make-prompt-template
                   :name (or new-name name)
                   :category (prompt-category parent)
                   :body (or new-body (prompt-body parent))
                   :variables (prompt-variables parent)
                   :includes (prompt-includes parent)
                   :author (or author "agent")
                   :parent (prompt-content-hash parent))))
      (register-prompt forked))))

(defun prompt-history (name)
  "Return the version history for NAME, newest first."
  (gethash name *prompt-history*))

;;; ===================================================================
;;; Templating
;;; ===================================================================

(defun substitute-variables (text bindings)
  "Replace {{variable}} patterns with values from BINDINGS alist.
   Unbound variables are left as-is."
  (cl-ppcre:regex-replace-all
   "\\{\\{([a-zA-Z][a-zA-Z0-9_-]*)\\}\\}"
   text
   (lambda (target-string start end match-start match-end reg-starts reg-ends)
     (declare (ignore start end match-start match-end))
     (let* ((var-name (subseq target-string (aref reg-starts 0) (aref reg-ends 0)))
            (pair (assoc var-name bindings :test #'string=)))
       (if pair
           (format nil "~a" (cdr pair))
           ;; Leave unbound variables as-is
           (format nil "{{~a}}" var-name))))))

(defun resolve-includes (text &optional (registry *prompt-registry*) (seen nil))
  "Replace {{include:prompt-name}} patterns with referenced prompt bodies.
   SEEN tracks visited names for cycle detection."
  (cl-ppcre:regex-replace-all
   "\\{\\{include:([a-zA-Z][a-zA-Z0-9_-]*)\\}\\}"
   text
   (lambda (target-string start end match-start match-end reg-starts reg-ends)
     (declare (ignore start end match-start match-end))
     (let ((prompt-name (subseq target-string (aref reg-starts 0) (aref reg-ends 0))))
       (when (member prompt-name seen :test #'string=)
         (error 'autopoiesis.core:autopoiesis-error
                :message (format nil "Circular include detected: ~a -> ~{~a~^ -> ~}"
                                 prompt-name (reverse seen))))
       (let ((included (gethash prompt-name registry)))
         (if included
             ;; Recursively resolve includes in the included body
             (resolve-includes (prompt-body included) registry
                               (cons prompt-name seen))
             ;; Leave unresolved includes as-is
             (format nil "{{include:~a}}" prompt-name)))))))

(defun render-prompt (prompt bindings &key (registry *prompt-registry*))
  "Resolve includes, then substitute variables. Returns string."
  (let* ((body (prompt-body prompt))
         (with-includes (resolve-includes body registry))
         (with-vars (substitute-variables with-includes bindings)))
    with-vars))

;;; ===================================================================
;;; Substrate Persistence
;;; ===================================================================

(defun persist-prompt (prompt)
  "Write prompt to substrate as datoms. Returns entity ID.
   Requires active *store*."
  (unless autopoiesis.substrate:*store*
    (error 'autopoiesis.core:autopoiesis-error
           :message "Cannot persist prompt: no active substrate store"))
  (let ((eid (autopoiesis.substrate:intern-id
              (format nil "prompt-~a-v~d" (prompt-name prompt) (prompt-version prompt)))))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom eid :entity/type :prompt)
           (autopoiesis.substrate:make-datom eid :prompt/name (prompt-name prompt))
           (autopoiesis.substrate:make-datom eid :prompt/category (prompt-category prompt))
           (autopoiesis.substrate:make-datom eid :prompt/body (prompt-body prompt))
           (autopoiesis.substrate:make-datom eid :prompt/version (prompt-version prompt))
           (autopoiesis.substrate:make-datom eid :prompt/content-hash (prompt-content-hash prompt))
           (autopoiesis.substrate:make-datom eid :prompt/parent (prompt-parent prompt))
           (autopoiesis.substrate:make-datom eid :prompt/author (prompt-author prompt))
           (autopoiesis.substrate:make-datom eid :prompt/created-at (prompt-created-at prompt))
           (autopoiesis.substrate:make-datom eid :prompt/variables (prompt-variables prompt))
           (autopoiesis.substrate:make-datom eid :prompt/includes (prompt-includes prompt))))
    eid))

(defun load-prompts-from-substrate ()
  "Load all prompt entities from substrate into the in-memory registry.
   Requires active *store*. Returns count of prompts loaded."
  (unless autopoiesis.substrate:*store*
    (return-from load-prompts-from-substrate 0))
  (let ((prompt-eids (autopoiesis.substrate:find-entities :entity/type :prompt))
        (count 0))
    (dolist (eid prompt-eids)
      (handler-case
          (let* ((name (autopoiesis.substrate:entity-attr eid :prompt/name))
                 (category (autopoiesis.substrate:entity-attr eid :prompt/category))
                 (body (autopoiesis.substrate:entity-attr eid :prompt/body))
                 (version (autopoiesis.substrate:entity-attr eid :prompt/version))
                 (content-hash (autopoiesis.substrate:entity-attr eid :prompt/content-hash))
                 (parent (autopoiesis.substrate:entity-attr eid :prompt/parent))
                 (author (autopoiesis.substrate:entity-attr eid :prompt/author))
                 (created-at (autopoiesis.substrate:entity-attr eid :prompt/created-at))
                 (variables (autopoiesis.substrate:entity-attr eid :prompt/variables))
                 (includes (autopoiesis.substrate:entity-attr eid :prompt/includes)))
            (when (and name body)
              (let ((prompt (make-instance 'prompt-template
                                           :name name
                                           :category (or category :custom)
                                           :body body
                                           :version (or version 1)
                                           :content-hash content-hash
                                           :parent parent
                                           :author (or author "system")
                                           :created-at (or created-at 0)
                                           :variables variables
                                           :includes includes)))
                ;; Register without auto-versioning (direct slot set)
                (setf (gethash name *prompt-registry*) prompt)
                (push prompt (gethash name *prompt-history*))
                (incf count))))
        (error () nil)))
    count))

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defun prompt-to-sexpr (prompt)
  "Convert a prompt-template to a serializable S-expression (plist)."
  `(:prompt-template
    :name ,(prompt-name prompt)
    :category ,(prompt-category prompt)
    :body ,(prompt-body prompt)
    :version ,(prompt-version prompt)
    :content-hash ,(prompt-content-hash prompt)
    :parent ,(prompt-parent prompt)
    :author ,(prompt-author prompt)
    :created-at ,(prompt-created-at prompt)
    :variables ,(prompt-variables prompt)
    :includes ,(prompt-includes prompt)))

(defun sexpr-to-prompt (sexpr)
  "Restore a prompt-template from an S-expression."
  (unless (and (consp sexpr) (eq (first sexpr) :prompt-template))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Invalid prompt S-expression"))
  (let ((plist (rest sexpr)))
    (make-instance 'prompt-template
                   :name (getf plist :name)
                   :category (or (getf plist :category) :custom)
                   :body (getf plist :body)
                   :version (or (getf plist :version) 1)
                   :content-hash (getf plist :content-hash)
                   :parent (getf plist :parent)
                   :author (or (getf plist :author) "system")
                   :created-at (or (getf plist :created-at) 0)
                   :variables (getf plist :variables)
                   :includes (getf plist :includes))))

;;; ===================================================================
;;; defprompt Macro
;;; ===================================================================

(defmacro defprompt (name (&key category variables includes) &body body-strings)
  "Define and register a prompt at load time.
   Body strings are concatenated with newlines."
  (let ((name-str (etypecase name
                    (string name)
                    (symbol (string-downcase (symbol-name name))))))
    `(register-prompt
      (make-prompt-template
       :name ,name-str
       :category ,(or category :custom)
       :body ,(format nil "~{~a~^~%~}" body-strings)
       :variables ',variables
       :includes ',includes))))

;;; ===================================================================
;;; Built-in Prompts
;;; ===================================================================

(defun seed-builtin-prompts ()
  "Register the built-in prompt templates. Idempotent."
  ;; Clear existing builtins to allow re-seeding
  (register-prompt
   (make-prompt-template
    :name "agent-guidelines"
    :category :cognitive-base
    :body "Guidelines:
- Be concise and focused in your responses
- Explain your reasoning before taking actions
- If uncertain about a decision with significant consequences, request human input
- Use tools when they help accomplish the task more effectively"
    :author "system"))

  (register-prompt
   (make-prompt-template
    :name "cognitive-base"
    :category :cognitive-base
    :body "You are an AI agent named {{agent-name}} operating within the Autopoiesis platform.

Your capabilities include: {{capabilities}}

You operate as part of a larger agent system where:
- All your thoughts and actions are recorded in an immutable event log
- Humans can review, branch, and navigate your cognitive history
- You may be paused for human input at critical decision points

{{include:agent-guidelines}}"
    :variables '("agent-name" "capabilities")
    :includes '("agent-guidelines")
    :author "system"))

  (register-prompt
   (make-prompt-template
    :name "self-extension"
    :category :self-extension
    :body "You have the ability to extend your own capabilities by writing new ones.

When writing a new capability:
1. Define clear input/output types
2. Include comprehensive documentation
3. Test the capability before promoting it
4. Consider security implications

Use define-capability-tool to create, test-capability-tool to verify,
and promote-capability-tool to make it permanent."
    :author "system"))

  (register-prompt
   (make-prompt-template
    :name "provider-bridge"
    :category :provider-bridge
    :body "You are running as a provider-backed agent in the Autopoiesis platform.
Your responses are recorded as thoughts in the agent's cognitive stream.
The orchestration layer may schedule follow-up tasks based on your output."
    :author "system"))

  (register-prompt
   (make-prompt-template
    :name "orchestration"
    :category :orchestration
    :body "You are a conductor-managed agent. The conductor schedules your tasks
and monitors your progress. Report completion via the standard result format.
If you encounter errors, report them clearly so the conductor can retry or escalate."
    :author "system")))

;; Seed at load time
(seed-builtin-prompts)
