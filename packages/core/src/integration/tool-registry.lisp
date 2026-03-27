;;;; tool-registry.lisp - External tool registry
;;;;
;;;; Registry of external tools available to agents.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; External Tool Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass external-tool ()
  ((name :initarg :name
         :accessor tool-name
         :documentation "Tool name")
   (description :initarg :description
                :accessor tool-description
                :initform ""
                :documentation "Tool description")
   (parameters :initarg :parameters
               :accessor tool-parameters
               :initform nil
               :documentation "JSON Schema for parameters")
   (handler :initarg :handler
            :accessor tool-handler
            :documentation "Function to invoke")
   (source :initarg :source
           :accessor tool-source
           :initform :local
           :documentation ":local or MCP server name"))
  (:documentation "An external tool"))

(defun make-external-tool (name handler &key description parameters source)
  "Create an external tool."
  (make-instance 'external-tool
                 :name name
                 :handler handler
                 :description (or description "")
                 :parameters parameters
                 :source (or source :local)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tool Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *external-tool-registry* (make-hash-table :test 'equal)
  "Registry of external tools.")

(defun register-external-tool (tool &key (registry *external-tool-registry*))
  "Register an external tool."
  (setf (gethash (tool-name tool) registry) tool))

(defun unregister-external-tool (name &key (registry *external-tool-registry*))
  "Unregister an external tool."
  (remhash name registry))

(defun find-external-tool (name &key (registry *external-tool-registry*))
  "Find an external tool by name."
  (gethash name registry))

(defun list-external-tools (&key (registry *external-tool-registry*))
  "List all external tools."
  (loop for tool being the hash-values of registry
        collect tool))

(defun invoke-external-tool (name args &key (registry *external-tool-registry*))
  "Invoke an external tool."
  (let ((tool (find-external-tool name :registry registry)))
    (unless tool
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Unknown external tool: ~a" name)))
    (apply (tool-handler tool) args)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tool Schema Generation
;;; ═══════════════════════════════════════════════════════════════════

(defun tool-to-claude-schema (tool)
  "Convert an external tool to Claude's tool schema format."
  `(("name" . ,(tool-name tool))
    ("description" . ,(tool-description tool))
    ("input_schema" . ,(or (tool-parameters tool)
                           '(("type" . "object")
                             ("properties" . ()))))))

(defun tools-to-claude-schemas (tools)
  "Convert a list of tools to Claude's format."
  (mapcar #'tool-to-claude-schema tools))
