;;;; provider-result.lisp - Provider invocation results
;;;;
;;;; Captures the output of a provider invocation and provides
;;;; utilities for recording the exchange in the agent's thought stream.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Result Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass provider-result ()
  ((provider-name :initarg :provider-name
                  :accessor provider-result-provider-name
                  :initform nil
                  :documentation "Name of the provider that produced this result")
   (text :initarg :text
         :accessor provider-result-text
         :initform nil
         :documentation "The text response from the provider")
   (tool-calls :initarg :tool-calls
               :accessor provider-result-tool-calls
               :initform nil
               :documentation "List of tool calls made by the provider (plists)")
   (turns :initarg :turns
          :accessor provider-result-turns
          :initform nil
          :documentation "Number of agentic turns taken")
   (cost :initarg :cost
         :accessor provider-result-cost
         :initform nil
         :documentation "Cost in USD, if reported")
   (duration :initarg :duration
             :accessor provider-result-duration
             :initform nil
             :documentation "Wall-clock duration in seconds")
   (raw-output :initarg :raw-output
               :accessor provider-result-raw-output
               :initform nil
               :documentation "Complete raw output from subprocess")
   (exit-code :initarg :exit-code
              :accessor provider-result-exit-code
              :initform nil
              :documentation "Process exit code")
   (error-output :initarg :error-output
                 :accessor provider-result-error-output
                 :initform nil
                 :documentation "Stderr output from subprocess")
   (session-id :initarg :session-id
               :accessor provider-result-session-id
               :initform nil
               :documentation "Session ID if provider tracks sessions")
   (metadata :initarg :metadata
             :accessor provider-result-metadata
             :initform nil
             :documentation "Additional provider-specific metadata as plist"))
  (:documentation "Result of a provider invocation.

Captures the text response, any tool calls made, performance metrics,
and raw output for debugging."))

(defmethod print-object ((result provider-result) stream)
  (print-unreadable-object (result stream :type t)
    (format stream "~a exit:~a ~@[~a turns~] ~@[$~,4f~]"
            (provider-result-provider-name result)
            (provider-result-exit-code result)
            (provider-result-turns result)
            (provider-result-cost result))))

(defun make-provider-result (&key provider-name text tool-calls turns cost
                               duration raw-output exit-code error-output
                               session-id metadata)
  "Create a new provider result."
  (make-instance 'provider-result
                 :provider-name provider-name
                 :text text
                 :tool-calls tool-calls
                 :turns turns
                 :cost cost
                 :duration duration
                 :raw-output raw-output
                 :exit-code exit-code
                 :error-output error-output
                 :session-id session-id
                 :metadata metadata))

(defun result-success-p (result)
  "Return T if the provider invocation was successful (exit code 0)."
  (eql (provider-result-exit-code result) 0))

;;; ═══════════════════════════════════════════════════════════════════
;;; S-Expression Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun provider-result-to-sexpr (result)
  "Serialize a provider result to an S-expression."
  `(:provider-result
    :provider-name ,(provider-result-provider-name result)
    :text ,(provider-result-text result)
    :tool-calls ,(provider-result-tool-calls result)
    :turns ,(provider-result-turns result)
    :cost ,(provider-result-cost result)
    :duration ,(provider-result-duration result)
    :exit-code ,(provider-result-exit-code result)
    :session-id ,(provider-result-session-id result)
    :metadata ,(provider-result-metadata result)))

(defun sexpr-to-provider-result (sexpr)
  "Deserialize a provider result from an S-expression."
  (unless (and (listp sexpr) (eq (first sexpr) :provider-result))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Invalid provider-result S-expression"))
  (let ((plist (rest sexpr)))
    (make-provider-result
     :provider-name (getf plist :provider-name)
     :text (getf plist :text)
     :tool-calls (getf plist :tool-calls)
     :turns (getf plist :turns)
     :cost (getf plist :cost)
     :duration (getf plist :duration)
     :exit-code (getf plist :exit-code)
     :session-id (getf plist :session-id)
     :metadata (getf plist :metadata))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Stream Recording
;;; ═══════════════════════════════════════════════════════════════════

(defun record-provider-exchange (thought-stream provider-name prompt result)
  "Record a provider exchange as thoughts in THOUGHT-STREAM.

   Records 4 types of thoughts:
   1. Observation — the prompt sent to the provider
   2. Action(s) — one per tool call made by the provider
   3. Observation — the final result text
   4. Reflection — summary with turns/cost/duration

   THOUGHT-STREAM - The agent's thought stream
   PROVIDER-NAME - Name of the provider
   PROMPT - The prompt that was sent
   RESULT - The provider-result object"
  (let ((source (intern (string-upcase provider-name) :keyword)))
    ;; 1. Record the prompt as an observation
    (autopoiesis.core:stream-append
     thought-stream
     (autopoiesis.core:make-observation
      (truncate-string (format nil "~a" prompt) 500)
      :source source
      :interpreted (format nil "Sent prompt to ~a provider" provider-name)))

    ;; 2. Record each tool call as an action
    (dolist (tc (provider-result-tool-calls result))
      (let ((name (or (getf tc :name) "unknown-tool"))
            (input (getf tc :input)))
        (autopoiesis.core:stream-append
         thought-stream
         (autopoiesis.core:make-action
          (intern (string-upcase (substitute #\- #\_ name)) :keyword)
          input))))

    ;; 3. Record the result text as an observation
    (when (provider-result-text result)
      (autopoiesis.core:stream-append
       thought-stream
       (autopoiesis.core:make-observation
        (truncate-string (or (provider-result-text result) "") 1000)
        :source source
        :interpreted (if (result-success-p result)
                         "Provider completed successfully"
                         (format nil "Provider failed (exit ~a)"
                                 (provider-result-exit-code result))))))

    ;; 4. Record a reflection summarizing the exchange
    (autopoiesis.core:stream-append
     thought-stream
     (autopoiesis.core:make-reflection
      source
      (format nil "Provider ~a: ~:[failed~;succeeded~]~@[, ~a turns~]~@[, $~,4f~]~@[, ~,1fs~]"
              provider-name
              (result-success-p result)
              (provider-result-turns result)
              (provider-result-cost result)
              (provider-result-duration result))))))
