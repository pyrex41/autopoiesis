;;;; agent-backend.lisp - general agent-backend factory ("use your own tool").
;;;;
;;;; The product's premise is that anyone's agent -- their own or a shared one --
;;;; can do the work. So the room worker is backend-agnostic: it runs a turn
;;;; through the provider abstraction (provider-invoke), and this factory builds
;;;; the right provider for any supported backend by a serializable spec.
;;;;
;;;; Supported backends: codex (one-shot) / codex-appserver (long-lived) /
;;;; claude-code (anthropic) / rho (pyrex41/rho; multi-model incl. grok & claude)
;;;; / grok (grok.com CLI) / pi / opencode (multi-model). grok & anthropic are
;;;; also reachable as MODELS via rho/opencode (e.g. :rho :model "grok-4.3").

(in-package #:autopoiesis.integration)

(defparameter *agent-backends*
  '(:codex :codex-appserver :claude-code :anthropic :rho :grok :pi :opencode)
  "Agent backends the room layer can run a turn through, all behind provider-invoke.")

(defun make-agent-backend (kind &key model cwd name extra-args)
  "Build a provider for agent backend KIND. MODEL selects the model on
   multi-model backends (rho/opencode/codex/claude/grok-cli). CWD sets the
   agent's working directory. Every backend is driven uniformly via the
   define-cli-provider constructor keys (:name/:default-model/:working-directory/
   :extra-args), so callers stay backend-agnostic."
  (let ((nm (or name (string-downcase (symbol-name kind)))))
    (ecase kind
      (:codex
       (make-codex-provider :name nm :default-model model
                            :working-directory cwd :extra-args extra-args))
      (:codex-appserver
       (make-codex-appserver-provider :name nm :default-model model
                                      :working-directory cwd :extra-args extra-args))
      ((:claude-code :anthropic)
       (make-claude-code-provider :name nm :default-model (or model "claude-sonnet")
                                  :working-directory cwd :extra-args extra-args))
      (:rho
       (make-rho-provider :name nm :default-model (or model "grok-4.3") :skip-tools t
                          :working-directory cwd :extra-args extra-args))
      (:grok
       (make-grok-provider :name nm :default-model model
                           :working-directory cwd :extra-args extra-args))
      (:pi
       (make-pi-provider :name nm :default-model model
                         :working-directory cwd :extra-args extra-args))
      (:opencode
       (make-opencode-provider :name nm :default-model (or model "xai/grok-4.3")
                               :working-directory cwd :extra-args extra-args)))))

(defun make-agent-backend-from-spec (spec)
  "Build a backend from a serializable plist SPEC, e.g.
   (:kind :rho :model \"grok-4.3\" :cwd #p\"...\" :name \"alice\"). This is what
   rides inside a :room-work event so the worker can construct its own agent."
  (make-agent-backend (getf spec :kind)
                      :model (getf spec :model)
                      :cwd (getf spec :cwd)
                      :name (getf spec :name)
                      :extra-args (getf spec :extra-args)))
