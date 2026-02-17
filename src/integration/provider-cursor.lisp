;;;; provider-cursor.lisp - Cursor Agent CLI provider
;;;;
;;;; Wraps the `cursor-agent` CLI tool as an inference provider.
;;;; Uses a shorter default timeout due to hang risk.

(in-package #:autopoiesis.integration)

(define-cli-provider :cursor
  (:command "cursor-agent")
  (:modes (:one-shot))
  (:default-timeout 120)
  (:documentation "Provider for the Cursor Agent CLI tool.

Invokes `cursor-agent` with --output-format json. Uses a shorter
default timeout (120s) due to potential hang risk.")
  (:extra-slots
    (cursor-mode :initarg :cursor-mode
                 :accessor cursor-mode
                 :initform nil
                 :documentation "Cursor mode: nil, \"plan\", or \"ask\"")
    (force :initarg :force
           :accessor cursor-force
           :initform t
           :documentation "Whether to force non-interactive execution"))
  (:build-command (provider prompt)
    "Build cursor-agent CLI command."
    (let ((args (list "-p" prompt "--output-format" "json")))
      (when (cursor-force provider)
        (push "--force" args))
      (when (cursor-mode provider)
        (setf args (append args (list "--mode" (cursor-mode provider)))))
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :json-object
    (:text "result")))
