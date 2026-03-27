;;;; integrate-primitives.lisp - Meta-dispatcher for coding providers
;;;;
;;;; Provides a unified capability that routes coding tasks to the best
;;;; available provider backend based on task characteristics.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; Backend Selection Heuristic
;;; ===================================================================

(defun select-coding-backend (prompt)
  "Select the best coding backend based on task characteristics.

   Returns a keyword: :claude-code, :pi, or :opencode.

   Heuristic:
   - :pi for heavy file editing / refactoring tasks (fast Rust engine)
   - :opencode for GitHub-workflow tasks (PR, issue, review)
   - :claude-code as default (most mature, general purpose)"
  (let ((lower (string-downcase prompt)))
    (cond
      ;; Pi excels at bulk file operations and refactoring
      ((or (search "refactor" lower)
           (search "rename all" lower)
           (search "rewrite" lower)
           (search "migrate" lower)
           (search "convert all" lower)
           (search "bulk edit" lower))
       :pi)
      ;; OpenCode for GitHub workflow tasks
      ((or (search "create a pr" lower)
           (search "pull request" lower)
           (search "open an issue" lower)
           (search "review the pr" lower)
           (search "github" lower))
       :opencode)
      ;; Default: Claude Code
      (t :claude-code))))

;;; ===================================================================
;;; Provider Construction
;;; ===================================================================

(defun ensure-coding-provider (backend &key model project-path)
  "Look up or construct a coding provider for BACKEND.

   First checks the provider registry, then constructs a new instance
   using environment configuration."
  (let ((name (string-downcase (symbol-name backend))))
    (or (find-provider name)
        (let ((provider
                (ecase backend
                  (:claude-code
                   (make-claude-code-provider
                    :working-directory project-path
                    :default-model model))
                  (:pi
                   (make-pi-provider
                    :working-directory project-path
                    :default-model model
                    :command (or (get-config :pi-path) "pi")))
                  (:opencode
                   (make-opencode-provider
                    :working-directory project-path
                    :default-model model
                    :command (or (get-config :opencode-path) "opencode"))))))
          (register-provider provider)
          provider))))

;;; ===================================================================
;;; Coding Primitive Capability
;;; ===================================================================

(autopoiesis.agent:defcapability coding-primitive
    (&key prompt project-path backend model)
  "Dispatch coding tasks to the best available provider.

   Selects a backend automatically based on task characteristics,
   or uses the explicitly specified BACKEND keyword."
  :permissions (:provider-invoke)
  (let* ((effective-backend (or backend (select-coding-backend prompt)))
         (provider (ensure-coding-provider effective-backend
                                            :model model
                                            :project-path project-path)))
    (provider-invoke provider prompt)))
