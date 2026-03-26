;;;; harness-provider.lisp - Provider harness implementation
;;;;
;;;; Wraps any registered provider (Claude Code, Codex, OpenCode, etc.)
;;;; into the eval harness protocol for single-invocation evaluation.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Provider Harness Class
;;; ===================================================================

(defclass provider-harness (eval-harness)
  ((provider-name :initarg :provider-name
                  :accessor ph-provider-name
                  :type string
                  :documentation "Name of the registered provider to wrap")
   (model :initarg :model
          :accessor ph-model
          :initform nil
          :documentation "Optional model override")
   (tools :initarg :tools
          :accessor ph-tools
          :initform nil
          :documentation "Optional tool specifications")
   (working-directory :initarg :working-directory
                      :accessor ph-working-directory
                      :initform nil
                      :documentation "Working directory for provider execution"))
  (:documentation "Harness that wraps a registered provider for single-invocation eval."))

(defun make-provider-harness (provider-name &key model tools working-directory
                                              (description ""))
  "Create a provider harness wrapping an existing registered provider."
  (make-instance 'provider-harness
                 :name provider-name
                 :description (if (string= description "")
                                  (format nil "Provider harness wrapping ~a" provider-name)
                                  description)
                 :provider-name provider-name
                 :model model
                 :tools tools
                 :working-directory working-directory))

;;; ===================================================================
;;; Harness Protocol Implementation
;;; ===================================================================

(defmethod harness-run-scenario ((harness provider-harness) scenario-plist &key timeout)
  "Run scenario via provider-invoke. Times the invocation, applies verifier, returns result."
  (let* ((provider (autopoiesis.integration:find-provider (ph-provider-name harness)))
         (prompt (getf scenario-plist :eval-scenario/prompt))
         (verifier (getf scenario-plist :eval-scenario/verifier))
         (expected (getf scenario-plist :eval-scenario/expected))
         (scenario-timeout (or timeout
                               (getf scenario-plist :eval-scenario/timeout)
                               300)))
    (unless provider
      (return-from harness-run-scenario
        (list :output nil
              :duration 0
              :exit-code -1
              :passed :error
              :metadata (list :error (format nil "Provider not found: ~a"
                                             (ph-provider-name harness))))))
    ;; Execute with timing
    (let ((start-time (get-precise-time))
          result duration)
      (handler-case
          (progn
            ;; Set working directory if specified
            (when (ph-working-directory harness)
              (setf (autopoiesis.integration:provider-working-directory provider)
                    (ph-working-directory harness)))
            ;; Set timeout if provider supports it
            (when scenario-timeout
              (setf (autopoiesis.integration:provider-timeout provider) scenario-timeout))
            (setf result (autopoiesis.integration:provider-invoke
                          provider prompt
                          :tools (ph-tools harness)))
            (setf duration (/ (- (get-precise-time) start-time) 1000000.0)))
        (error (e)
          (setf duration (/ (- (get-precise-time) start-time) 1000000.0))
          (return-from harness-run-scenario
            (list :output (format nil "Error: ~a" e)
                  :duration duration
                  :cost nil
                  :turns nil
                  :exit-code -1
                  :passed :error
                  :metadata (list :error-type (type-of e)
                                  :error-message (format nil "~a" e))))))
      ;; Extract metrics from provider-result
      (let* ((output (autopoiesis.integration:provider-result-text result))
             (tool-calls (autopoiesis.integration:provider-result-tool-calls result))
             (cost (autopoiesis.integration:provider-result-cost result))
             (turns (autopoiesis.integration:provider-result-turns result))
             (exit-code (autopoiesis.integration:provider-result-exit-code result))
             ;; Use provider's duration if available, otherwise our measurement
             (actual-duration (or (autopoiesis.integration:provider-result-duration result)
                                  duration))
             ;; Run verifier if present
             (passed (if verifier
                         (run-verifier verifier output
                                       :expected expected
                                       :exit-code exit-code
                                       :result result)
                         nil)))
        (list :output output
              :tool-calls tool-calls
              :duration actual-duration
              :cost cost
              :turns turns
              :exit-code exit-code
              :passed passed
              :metadata (list :provider-name (ph-provider-name harness)
                              :session-id (autopoiesis.integration:provider-result-session-id result))
              :raw-provider-result
              (autopoiesis.integration:provider-result-to-sexpr result))))))

(defmethod harness-to-config-plist ((harness provider-harness))
  (list :type "provider"
        :name (harness-name harness)
        :provider-name (ph-provider-name harness)
        :model (ph-model harness)))
