;;;; provider-grok.lisp - grok coding-agent CLI provider (xAI / grok.com)
;;;;
;;;; Wraps `grok -p <prompt> --output-format plain [--cwd dir] [--always-approve]`
;;;; for a single-turn headless run. Uses the grok.com account's default model
;;;; (OAuth). For the xAI *API* grok models (grok-4.3 etc.), use the :rho or
;;;; :opencode backend with the model id instead. No :parse-output clause -> the
;;;; base provider-parse-output (text = raw stdout) is inherited.

(in-package #:autopoiesis.integration)

(define-cli-provider :grok
  (:command "grok")
  (:modes (:one-shot))
  (:default-timeout 600)
  (:documentation "Provider for the grok coding-agent CLI (grok.com OAuth).")
  (:extra-slots
    (always-approve :initarg :always-approve
                    :accessor grok-always-approve
                    :initform t
                    :documentation "Pass --always-approve to auto-approve tool use."))
  (:build-command (provider prompt &key tools)
    "Build grok CLI command for a single-turn (-p) run."
    (declare (ignore tools))
    (let ((args (list "-p" prompt "--output-format" "plain")))
      (when (provider-default-model provider)
        (setf args (append args (list "--model" (provider-default-model provider)))))
      (when (provider-working-directory provider)
        (setf args (append args (list "--cwd"
                                      (namestring (provider-working-directory provider))))))
      (when (grok-always-approve provider)
        (setf args (append args (list "--always-approve"))))
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args))))
