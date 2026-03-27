;;;; config.lisp - Configuration for skeleton LLM functions
;;;; Handles LLM configuration (model, tokens, temperature, etc.)

(in-package #:autopoiesis.skel)

;;; ============================================================================
;;; Retry Policy Class
;;; ============================================================================

(defclass retry-policy ()
  ((max-attempts
    :initarg :max-attempts
    :initform 3
    :accessor retry-max-attempts
    :type integer
    :documentation "Maximum number of retry attempts (not including initial attempt)")
   (base-delay
    :initarg :base-delay
    :initform 1.0
    :accessor retry-base-delay
    :type number
    :documentation "Base delay in seconds before first retry")
   (max-delay
    :initarg :max-delay
    :initform 60.0
    :accessor retry-max-delay
    :type number
    :documentation "Maximum delay in seconds between retries")
   (multiplier
    :initarg :multiplier
    :initform 2.0
    :accessor retry-multiplier
    :type number
    :documentation "Multiplier for exponential backoff")
   (jitter
    :initarg :jitter
    :initform 0.1
    :accessor retry-jitter
    :type number
    :documentation "Random jitter factor (0.0-1.0) to add to delays")
   (retry-on
    :initarg :retry-on
    :initform '(:rate-limit :server-error :connection-error :parse-error)
    :accessor retry-on-errors
    :type list
    :documentation "List of error types to retry on.")
   (respect-retry-after
    :initarg :respect-retry-after
    :initform t
    :accessor retry-respect-retry-after
    :type boolean
    :documentation "If T, use retry-after header from rate limit responses"))
  (:documentation "Configures retry behavior for LLM calls."))

(defun make-retry-policy (&key (max-attempts 3) (base-delay 1.0) (max-delay 60.0)
                               (multiplier 2.0) (jitter 0.1)
                               (retry-on '(:rate-limit :server-error :connection-error :parse-error))
                               (respect-retry-after t))
  "Create a new retry policy instance."
  (make-instance 'retry-policy
    :max-attempts max-attempts
    :base-delay base-delay
    :max-delay max-delay
    :multiplier multiplier
    :jitter jitter
    :retry-on retry-on
    :respect-retry-after respect-retry-after))

(defun calculate-backoff-delay (policy attempt)
  "Calculate the delay for ATTEMPT using exponential backoff."
  (let* ((base (retry-base-delay policy))
         (mult (retry-multiplier policy))
         (max-d (retry-max-delay policy))
         (jitter-factor (retry-jitter policy))
         (raw-delay (* base (expt mult attempt)))
         (capped-delay (min raw-delay max-d))
         (jitter-amount (* capped-delay jitter-factor (- (random 2.0) 1.0))))
    (max 0.1 (+ capped-delay jitter-amount))))

(defun should-retry-error-p (policy error)
  "Check if ERROR should trigger a retry based on POLICY configuration."
  (let ((retry-on (retry-on-errors policy)))
    (or (member :all retry-on)
        (typecase error
          (skel-llm-rate-limit-error
           (member :rate-limit retry-on))
          (skel-llm-server-error
           (member :server-error retry-on))
          (skel-llm-connection-error
           (member :connection-error retry-on))
          (skel-parse-error
           (member :parse-error retry-on))
          (sap-error
           (member :parse-error retry-on))
          (t nil)))))

(defun get-retry-delay (policy error attempt)
  "Get the delay before retrying after ERROR on ATTEMPT."
  (if (and (retry-respect-retry-after policy)
           (typep error 'skel-llm-rate-limit-error))
      (let ((retry-after (skel-llm-retry-after error)))
        (if retry-after
            (max retry-after (calculate-backoff-delay policy attempt))
            (calculate-backoff-delay policy attempt)))
      (calculate-backoff-delay policy attempt)))

;;; ============================================================================
;;; Default Retry Policy
;;; ============================================================================

(defvar *default-retry-policy* (make-retry-policy)
  "Default retry policy for SKEL function calls.")

(defvar *no-retry-policy* (make-retry-policy :max-attempts 0)
  "A retry policy that disables retries.")

;;; ============================================================================
;;; Configuration Class
;;; ============================================================================

(defclass skel-config ()
  ((model
    :initarg :model
    :initform nil
    :accessor config-model
    :type (or null string)
    :documentation "LLM model to use (nil = use client default)")
   (max-tokens
    :initarg :max-tokens
    :initform nil
    :accessor config-max-tokens
    :type (or null integer)
    :documentation "Maximum tokens for response (nil = use client default)")
   (temperature
    :initarg :temperature
    :initform nil
    :accessor config-temperature
    :type (or null number)
    :documentation "Sampling temperature 0.0-1.0 (nil = use client default)")
   (timeout
    :initarg :timeout
    :initform nil
    :accessor config-timeout
    :type (or null integer)
    :documentation "Request timeout in seconds (nil = use client default)")
   (system-prompt
    :initarg :system-prompt
    :initform nil
    :accessor config-system-prompt
    :type (or null string)
    :documentation "System prompt to prepend to function prompt")
   (retry-count
    :initarg :retry-count
    :initform 0
    :accessor config-retry-count
    :type integer
    :documentation "Number of retries on parse failure (DEPRECATED: use retry-policy)")
   (retry-delay
    :initarg :retry-delay
    :initform 1.0
    :accessor config-retry-delay
    :type number
    :documentation "Delay between retries in seconds (DEPRECATED: use retry-policy)")
   (retry-policy
    :initarg :retry-policy
    :initform nil
    :accessor config-retry-policy
    :type (or null retry-policy)
    :documentation "Retry policy for handling LLM call failures"))
  (:documentation "Configuration for a skeleton function invocation."))

(defun make-skel-config (&key model max-tokens temperature timeout
                              system-prompt (retry-count 0) (retry-delay 1.0)
                              retry-policy)
  "Create a new skel-config instance."
  (make-instance 'skel-config
    :model model
    :max-tokens max-tokens
    :temperature temperature
    :timeout timeout
    :system-prompt system-prompt
    :retry-count retry-count
    :retry-delay retry-delay
    :retry-policy retry-policy))

;;; ============================================================================
;;; Default Configuration
;;; ============================================================================

(defvar *default-skel-config* (make-skel-config)
  "Default configuration used when none is specified.")

;;; ============================================================================
;;; Config Merging
;;; ============================================================================

(defun merge-configs (base override)
  "Merge two configurations, with OVERRIDE values taking precedence."
  (make-skel-config
   :model (or (config-model override) (config-model base))
   :max-tokens (or (config-max-tokens override) (config-max-tokens base))
   :temperature (or (config-temperature override) (config-temperature base))
   :timeout (or (config-timeout override) (config-timeout base))
   :system-prompt (cond
                    ((and (config-system-prompt base)
                          (config-system-prompt override))
                     (format nil "~A~%~%~A"
                             (config-system-prompt base)
                             (config-system-prompt override)))
                    ((config-system-prompt override)
                     (config-system-prompt override))
                    (t (config-system-prompt base)))
   :retry-count (if (zerop (config-retry-count override))
                    (config-retry-count base)
                    (config-retry-count override))
   :retry-delay (config-retry-delay override)
   :retry-policy (or (config-retry-policy override)
                     (config-retry-policy base))))

(defun config-effective-retry-policy (config)
  "Get the effective retry policy from CONFIG."
  (or (config-retry-policy config)
      (if (> (config-retry-count config) 0)
          (make-retry-policy
           :max-attempts (config-retry-count config)
           :base-delay (config-retry-delay config)
           :multiplier 1.0
           :jitter 0.0
           :retry-on '(:parse-error))
          *no-retry-policy*)))

;;; ============================================================================
;;; Config to Client Mapping
;;; ============================================================================

(defun apply-config-to-client (client config)
  "Apply a skel-config to an LLM client, returning a modified client.
Fallback clients are returned unchanged — config applies to their inner clients."
  (if (typep client 'fallback-skel-client)
      client
      (make-skel-llm-client
       :api-key (skel-client-api-key client)
       :model (or (config-model config) (skel-client-model client))
       :max-tokens (or (config-max-tokens config) (skel-client-max-tokens client))
       :temperature (or (config-temperature config) (skel-client-temperature client))
       :timeout (or (config-timeout config) (skel-client-timeout client)))))
