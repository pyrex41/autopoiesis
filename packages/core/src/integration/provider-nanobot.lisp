;;;; provider-nanobot.lisp - NanoBot lightweight agent CLI provider
;;;;
;;;; Wraps the `nanobot` CLI tool as an inference provider.
;;;; Supports one-shot headless mode.

(in-package #:autopoiesis.integration)

(define-cli-provider :nanobot
  (:command "nanobot")
  (:modes (:one-shot))
  (:documentation "Provider for the NanoBot lightweight agent.

Invokes `nanobot agent` in headless mode with optional workspace.")
  (:extra-slots
    (workspace :initarg :workspace
               :accessor nanobot-workspace
               :initform nil
               :documentation "Workspace directory for NanoBot"))
  (:build-command (provider prompt)
    "Build nanobot CLI command."
    (let ((args (list "agent" "--no-markdown" "-m" prompt)))
      (when (nanobot-workspace provider)
        (setf args (append args (list "--workspace" (nanobot-workspace provider)))))
      (when (provider-default-model provider)
        (setf args (append args (list "--model" (provider-default-model provider)))))
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :json-object
    (:text "output")
    (:tool-calls "tool_calls")
    (:cost "cost")))
