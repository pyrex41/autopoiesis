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
;;; Provider Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defun load-provider-config-from-env ()
  "Load provider configuration from environment variables.

   Reads:
   - CLAUDE_CODE_PATH - Path to claude CLI binary
   - CODEX_PATH - Path to codex CLI binary
   - OPENCODE_PATH - Path to opencode CLI binary
   - CURSOR_AGENT_PATH - Path to cursor-agent CLI binary"
  (let ((claude-path (uiop:getenv "CLAUDE_CODE_PATH"))
        (codex-path (uiop:getenv "CODEX_PATH"))
        (opencode-path (uiop:getenv "OPENCODE_PATH"))
        (cursor-path (uiop:getenv "CURSOR_AGENT_PATH")))
    (when claude-path
      (set-config :claude-code-path claude-path))
    (when codex-path
      (set-config :codex-path codex-path))
    (when opencode-path
      (set-config :opencode-path opencode-path))
    (when cursor-path
      (set-config :cursor-agent-path cursor-path))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defun initialize-integrations ()
  "Initialize all integration subsystems."
  (load-config-from-env)
  (load-provider-config-from-env)
  t)
