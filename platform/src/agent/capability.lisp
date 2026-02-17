;;;; capability.lisp - Capability system
;;;;
;;;; Capabilities are named functions that agents can invoke.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass capability ()
  ((name :initarg :name
         :accessor capability-name
         :documentation "Unique name for this capability")
   (function :initarg :function
             :accessor capability-function
             :documentation "Function to invoke")
   (parameters :initarg :parameters
               :accessor capability-parameters
               :initform nil
               :documentation "Parameter specifications for tool mapping")
   (permissions :initarg :permissions
                :accessor capability-permissions
                :initform nil
                :documentation "Required permissions")
   (description :initarg :description
                :accessor capability-description
                :initform ""
                :documentation "Human-readable description"))
  (:documentation "A capability that an agent can invoke"))

(defun make-capability (name function &key parameters permissions description)
  "Create a new capability."
  (make-instance 'capability
                 :name name
                 :function function
                 :parameters parameters
                 :permissions permissions
                 :description (or description "")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Global Capability Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *capability-registry* (make-hash-table :test 'equal)
  "Global registry of available capabilities.")

(defun register-capability (capability &key (registry *capability-registry*))
  "Register a capability in the registry."
  (setf (gethash (capability-name capability) registry) capability))

(defun unregister-capability (name &key (registry *capability-registry*))
  "Remove a capability from the registry."
  (remhash name registry))

(defun find-capability (name &key (registry *capability-registry*))
  "Find a capability by name."
  (gethash name registry))

(defun list-capabilities (&key (registry *capability-registry*))
  "List all registered capabilities."
  (loop for cap being the hash-values of registry
        collect cap))

(defun invoke-capability (name &rest args)
  "Invoke a capability by name with arguments."
  (let ((cap (find-capability name)))
    (unless cap
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Unknown capability: ~a" name)))
    (apply (capability-function cap) args)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Definition Macro
;;; ═══════════════════════════════════════════════════════════════════

(defun parse-defcapability-body (body)
  "Parse the body of defcapability into (values doc options actual-body).

   The body can contain:
   - An optional docstring as the first element
   - Keyword options (e.g., :cost 0.1 :latency :fast)
   - A :body keyword followed by the implementation forms

   Returns three values: docstring, options plist, and body forms."
  (let ((doc (if (stringp (first body)) (pop body) ""))
        (options nil)
        (actual-body nil))
    (loop while body
          for item = (pop body)
          do (cond
               ;; :body keyword signals start of implementation
               ((eq item :body)
                (setf actual-body body
                      body nil))
               ;; Other keywords are options
               ((keywordp item)
                (push item options)
                (push (pop body) options))
               ;; Non-keyword means we hit the body without :body marker
               (t
                (push item actual-body)
                (setf actual-body (nconc (nreverse actual-body) body)
                      body nil))))
    (values doc (nreverse options) actual-body)))

(defun parse-capability-params (lambda-list)
  "Parse a lambda list into capability parameter specifications.

   Each parameter becomes a list of (name type &key required default).
   - Required parameters: (name t :required t)
   - Optional parameters: (name t) or (name t :default value)
   - Keyword parameters: (name t) or (name t :default value)"
  (let ((params nil)
        (mode :required))
    (dolist (item lambda-list (nreverse params))
      (cond
        ;; Lambda list keywords change the mode
        ((member item '(&optional &key &rest &aux))
         (setf mode item))
        ;; In required mode
        ((eq mode :required)
         (push `(,item t :required t) params))
        ;; In &optional mode
        ((eq mode '&optional)
         (if (consp item)
             (push `(,(first item) t :default ,(second item)) params)
             (push `(,item t) params)))
        ;; In &key mode
        ((eq mode '&key)
         (if (consp item)
             (push `(,(first item) t :default ,(second item)) params)
             (push `(,item t) params)))
        ;; &rest just captures the name
        ((eq mode '&rest)
         (push `(,item t :rest t) params))))))

(defmacro defcapability (name lambda-list &body body-and-options)
  "Define and register a new capability.

   NAME is the symbol naming this capability.
   LAMBDA-LIST is the parameter list for the capability function.
   BODY-AND-OPTIONS contains an optional docstring, keyword options,
   and the implementation body (either after :body or as remaining forms).

   Options:
     :permissions - List of permissions required to use this capability
     :description - Human-readable description (overrides docstring)

   Example:
     (defcapability web-search (query &key (max-results 10))
       \"Search the web for QUERY\"
       :permissions (:network)
       :body
       (perform-web-search query :limit max-results))

   Or without :body marker:
     (defcapability add-numbers (a b)
       \"Add two numbers\"
       (+ a b))"
  (multiple-value-bind (doc options body)
      (parse-defcapability-body body-and-options)
    (let ((permissions (getf options :permissions))
          (description (getf options :description))
          (params (parse-capability-params lambda-list)))
      `(register-capability
        (make-capability ',name
                         (lambda ,lambda-list ,@body)
                         :parameters ',params
                         :permissions ',permissions
                         :description ,(or description doc))))))
