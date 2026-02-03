;;;; permissions.lisp - Permission system for Autopoiesis
;;;;
;;;; Implements a resource × action permission matrix for agent security.
;;;; Phase 10.2: Security Hardening

(in-package #:autopoiesis.security)

;;; ═══════════════════════════════════════════════════════════════════
;;; Action Constants
;;; ═══════════════════════════════════════════════════════════════════

(defconstant +action-read+ :read
  "Permission to read/view a resource.")

(defconstant +action-write+ :write
  "Permission to modify an existing resource.")

(defconstant +action-execute+ :execute
  "Permission to execute/invoke a resource.")

(defconstant +action-delete+ :delete
  "Permission to delete/remove a resource.")

(defconstant +action-create+ :create
  "Permission to create new instances of a resource type.")

(defconstant +action-admin+ :admin
  "Administrative permission - implies all other actions.")

(defun all-actions ()
  "Return list of all defined actions."
  (list +action-read+ +action-write+ +action-execute+ 
        +action-delete+ +action-create+ +action-admin+))

;;; ═══════════════════════════════════════════════════════════════════
;;; Resource Type Constants
;;; ═══════════════════════════════════════════════════════════════════

(defconstant +resource-snapshot+ :snapshot
  "Snapshot resources - agent state captures.")

(defconstant +resource-agent+ :agent
  "Agent resources - other agents in the system.")

(defconstant +resource-capability+ :capability
  "Capability resources - agent capabilities.")

(defconstant +resource-extension+ :extension
  "Extension resources - agent-written code.")

(defconstant +resource-file+ :file
  "File system resources.")

(defconstant +resource-network+ :network
  "Network resources - external connections.")

(defconstant +resource-system+ :system
  "System resources - internal platform operations.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Resource Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass resource ()
  ((type :initarg :type
         :accessor resource-type
         :type keyword
         :documentation "The type of resource (e.g., :snapshot, :agent)")
   (id :initarg :id
       :accessor resource-id
       :initform nil
       :documentation "Optional specific resource identifier")
   (owner :initarg :owner
          :accessor resource-owner
          :initform nil
          :documentation "Agent ID that owns this resource"))
  (:documentation "Represents a resource that can be protected by permissions."))

(defun make-resource (type &key id owner)
  "Create a new resource instance.
   
   Arguments:
     type  - Resource type keyword (e.g., :snapshot, :agent)
     id    - Optional specific resource ID
     owner - Optional owner agent ID
   
   Returns: resource instance"
  (make-instance 'resource
                 :type type
                 :id id
                 :owner owner))

(defmethod print-object ((resource resource) stream)
  (print-unreadable-object (resource stream :type t)
    (format stream "~a~@[:~a~]" 
            (resource-type resource)
            (resource-id resource))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass permission ()
  ((name :initarg :name
         :accessor permission-name
         :type string
         :documentation "Human-readable permission name")
   (resource :initarg :resource
             :accessor permission-resource
             :documentation "Resource type or specific resource this permission applies to")
   (actions :initarg :actions
            :accessor permission-actions
            :type list
            :documentation "List of allowed actions: :read :write :execute :delete :create :admin"))
  (:documentation "Represents a permission granting specific actions on a resource."))

(defun make-permission (name resource-type actions &key resource-id)
  "Create a new permission instance.
   
   Arguments:
     name          - Human-readable name for this permission
     resource-type - Type of resource (keyword)
     actions       - List of allowed actions
     resource-id   - Optional specific resource ID (nil = all of type)
   
   Returns: permission instance"
  (make-instance 'permission
                 :name name
                 :resource (make-resource resource-type :id resource-id)
                 :actions (ensure-list actions)))

(defmethod print-object ((perm permission) stream)
  (print-unreadable-object (perm stream :type t)
    (format stream "~a: ~a -> ~{~a~^,~}" 
            (permission-name perm)
            (resource-type (permission-resource perm))
            (permission-actions perm))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Templates
;;; ═══════════════════════════════════════════════════════════════════

(defun make-read-only-permission (name resource-type &key resource-id)
  "Create a read-only permission for a resource type."
  (make-permission name resource-type (list +action-read+)
                   :resource-id resource-id))

(defun make-full-access-permission (name resource-type &key resource-id)
  "Create a full access permission (all actions) for a resource type."
  (make-permission name resource-type (all-actions)
                   :resource-id resource-id))

(defun make-execute-only-permission (name resource-type &key resource-id)
  "Create an execute-only permission for a resource type."
  (make-permission name resource-type (list +action-execute+)
                   :resource-id resource-id))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Denied Condition
;;; ═══════════════════════════════════════════════════════════════════

(define-condition permission-denied (error)
  ((agent :initarg :agent
          :reader permission-denied-agent
          :documentation "The agent that was denied")
   (resource :initarg :resource
             :reader permission-denied-resource
             :documentation "The resource that was protected")
   (action :initarg :action
           :reader permission-denied-action
           :documentation "The action that was attempted"))
  (:documentation "Signaled when an agent attempts an unauthorized action.")
  (:report (lambda (condition stream)
             (format stream "Permission denied: agent ~a cannot ~a on ~a"
                     (permission-denied-agent condition)
                     (permission-denied-action condition)
                     (permission-denied-resource condition)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Permissions Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *agent-permissions* (make-hash-table :test 'equal)
  "Map of agent-id -> list of permissions.")

(defun get-agent-permissions (agent-id)
  "Get the list of permissions for an agent."
  (gethash agent-id *agent-permissions*))

(defun set-agent-permissions (agent-id permissions)
  "Set the permissions for an agent."
  (setf (gethash agent-id *agent-permissions*) permissions))

(defun clear-agent-permissions (&optional agent-id)
  "Clear permissions for a specific agent or all agents."
  (if agent-id
      (remhash agent-id *agent-permissions*)
      (clrhash *agent-permissions*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Checking
;;; ═══════════════════════════════════════════════════════════════════

(defun permission-matches-p (permission resource-type &optional resource-id)
  "Check if a permission matches a resource type and optional ID."
  (let ((perm-resource (permission-resource permission)))
    (and (eq (resource-type perm-resource) resource-type)
         (or (null (resource-id perm-resource))  ; Wildcard permission
             (null resource-id)                   ; No specific ID required
             (equal (resource-id perm-resource) resource-id)))))

(defun check-permission (agent-id resource-type action &key resource-id)
  "Check if an agent has permission for an action on a resource.
   
   Arguments:
     agent-id      - The agent's identifier
     resource-type - Type of resource (keyword)
     action        - The action being attempted (keyword)
     resource-id   - Optional specific resource ID
   
   Returns: T if permitted, NIL otherwise"
  (let ((perms (get-agent-permissions agent-id)))
    (some (lambda (perm)
            (and (permission-matches-p perm resource-type resource-id)
                 (or (member +action-admin+ (permission-actions perm))
                     (member action (permission-actions perm)))))
          perms)))

(defun has-permission-p (agent-id resource-type action &key resource-id)
  "Predicate version of check-permission."
  (check-permission agent-id resource-type action :resource-id resource-id))

(defun grant-permission (agent-id permission)
  "Grant a permission to an agent.
   
   Arguments:
     agent-id   - The agent's identifier
     permission - The permission to grant
   
   Returns: The updated permission list"
  (let ((current (get-agent-permissions agent-id)))
    (unless (member permission current :test #'equalp)
      (push permission current)
      (set-agent-permissions agent-id current))
    current))

(defun revoke-permission (agent-id permission-name)
  "Revoke a permission from an agent by name.
   
   Arguments:
     agent-id        - The agent's identifier
     permission-name - Name of the permission to revoke
   
   Returns: The updated permission list"
  (let ((current (get-agent-permissions agent-id)))
    (setf current (remove-if (lambda (p) 
                               (string= (permission-name p) permission-name))
                             current))
    (set-agent-permissions agent-id current)
    current))

(defun list-permissions (agent-id)
  "List all permissions for an agent."
  (get-agent-permissions agent-id))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Check Macro
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-permission-check ((agent resource-type action &key resource-id) &body body)
  "Execute body only if agent has permission, otherwise signal permission-denied.
   
   Usage:
     (with-permission-check (agent :snapshot :read)
       (load-snapshot id))
   
   Arguments:
     agent         - Agent object or agent-id
     resource-type - Type of resource (keyword)
     action        - The action being attempted (keyword)
     resource-id   - Optional specific resource ID"
  (let ((agent-var (gensym "AGENT"))
        (agent-id-var (gensym "AGENT-ID")))
    `(let* ((,agent-var ,agent)
            (,agent-id-var (if (stringp ,agent-var)
                               ,agent-var
                               (autopoiesis.agent:agent-id ,agent-var))))
       (if (check-permission ,agent-id-var ,resource-type ,action 
                             :resource-id ,resource-id)
           (progn ,@body)
           (error 'permission-denied
                  :agent ,agent-id-var
                  :resource (make-resource ,resource-type :id ,resource-id)
                  :action ,action)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Matrix
;;; ═══════════════════════════════════════════════════════════════════

(defclass permission-matrix ()
  ((matrix :initform (make-hash-table :test 'equal)
           :accessor matrix-data
           :documentation "Hash table mapping (resource-type . action) -> allowed-p"))
  (:documentation "A resource × action permission matrix for efficient lookups."))

(defun make-permission-matrix (&optional permissions)
  "Create a permission matrix from a list of permissions."
  (let ((matrix (make-instance 'permission-matrix)))
    (dolist (perm permissions)
      (let ((resource-type (resource-type (permission-resource perm))))
        (dolist (action (permission-actions perm))
          (setf (gethash (cons resource-type action) (matrix-data matrix)) t))))
    matrix))

(defun matrix-check (matrix resource-type action)
  "Check if an action is allowed on a resource type in the matrix."
  (or (gethash (cons resource-type action) (matrix-data matrix))
      (gethash (cons resource-type +action-admin+) (matrix-data matrix))))

(defun matrix-grant (matrix resource-type action)
  "Grant an action on a resource type in the matrix."
  (setf (gethash (cons resource-type action) (matrix-data matrix)) t))

(defun matrix-revoke (matrix resource-type action)
  "Revoke an action on a resource type from the matrix."
  (remhash (cons resource-type action) (matrix-data matrix)))

(defun matrix-to-list (matrix)
  "Convert a permission matrix to a list of (resource-type action) pairs."
  (let ((result nil))
    (maphash (lambda (key value)
               (when value
                 (push (list (car key) (cdr key)) result)))
             (matrix-data matrix))
    (nreverse result)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Default Permission Sets
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *default-agent-permissions*
  (list
   ;; Agents can read their own snapshots
   (make-permission "read-snapshots" +resource-snapshot+ 
                    (list +action-read+))
   ;; Agents can execute capabilities
   (make-permission "execute-capabilities" +resource-capability+ 
                    (list +action-execute+))
   ;; Agents can read other agents (limited)
   (make-permission "read-agents" +resource-agent+ 
                    (list +action-read+)))
  "Default permissions granted to all agents.")

(defparameter *admin-permissions*
  (list
   ;; Full access to all resource types
   (make-full-access-permission "admin-snapshots" +resource-snapshot+)
   (make-full-access-permission "admin-agents" +resource-agent+)
   (make-full-access-permission "admin-capabilities" +resource-capability+)
   (make-full-access-permission "admin-extensions" +resource-extension+)
   (make-full-access-permission "admin-files" +resource-file+)
   (make-full-access-permission "admin-network" +resource-network+)
   (make-full-access-permission "admin-system" +resource-system+))
  "Full administrative permissions for system administrators.")

(defparameter *sandbox-permissions*
  (list
   ;; Sandboxed agents can only read snapshots and execute limited capabilities
   (make-read-only-permission "sandbox-read-snapshots" +resource-snapshot+)
   (make-execute-only-permission "sandbox-execute-caps" +resource-capability+))
  "Restricted permissions for sandboxed/untrusted agents.")
