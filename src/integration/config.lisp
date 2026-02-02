;;;; config.lisp - Integration configuration
;;;;
;;;; Configuration for external integrations.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defvar *integration-config* (make-hash-table :test 'equal)
  "Global integration configuration.")

(defun get-config (key &key (config *integration-config*) default)
  "Get a configuration value."
  (gethash key config default))

(defun set-config (key value &key (config *integration-config*))
  "Set a configuration value."
  (setf (gethash key config) value))

(defun load-config-from-env ()
  "Load configuration from environment variables."
  (let ((api-key (uiop:getenv "ANTHROPIC_API_KEY"))
        (model (uiop:getenv "AUTOPOIESIS_MODEL"))
        (mcp-config (uiop:getenv "MCP_CONFIG_PATH")))
    (when api-key
      (set-config :anthropic-api-key api-key))
    (when model
      (set-config :default-model model))
    (when mcp-config
      (set-config :mcp-config-path mcp-config))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defun initialize-integrations ()
  "Initialize all integration subsystems."
  (load-config-from-env)
  ;; Could load MCP servers from config here
  t)
