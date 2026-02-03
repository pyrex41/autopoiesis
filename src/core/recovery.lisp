;;;; recovery.lisp - Error recovery and restart system for Autopoiesis
;;;;
;;;; Provides comprehensive error recovery mechanisms including:
;;;; - Standard restarts for common operations
;;;; - Recovery strategies for different error types
;;;; - Graceful degradation helpers
;;;; - Operation retry with backoff

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Recovery Conditions
;;; ═══════════════════════════════════════════════════════════════════

(define-condition recoverable-error (autopoiesis-error)
  ((operation :initarg :operation
              :reader error-operation
              :initform nil
              :documentation "The operation that failed")
   (recoverable-p :initarg :recoverable-p
                  :reader error-recoverable-p
                  :initform t
                  :documentation "Whether the error can be recovered from")
   (recovery-hints :initarg :recovery-hints
                   :reader error-recovery-hints
                   :initform nil
                   :documentation "Hints for recovery strategies"))
  (:report (lambda (c s)
             (format s "Recoverable error in ~a: ~a~@[ (hints: ~{~a~^, ~})~]"
                     (error-operation c)
                     (condition-message c)
                     (error-recovery-hints c))))
  (:documentation "An error that can potentially be recovered from"))

(define-condition transient-error (recoverable-error)
  ((retry-count :initarg :retry-count
                :accessor error-retry-count
                :initform 0
                :documentation "Number of retry attempts made")
   (max-retries :initarg :max-retries
                :reader error-max-retries
                :initform 3
                :documentation "Maximum retry attempts allowed"))
  (:report (lambda (c s)
             (format s "Transient error in ~a (attempt ~d/~d): ~a"
                     (error-operation c)
                     (error-retry-count c)
                     (error-max-retries c)
                     (condition-message c))))
  (:documentation "A transient error that may succeed on retry"))

(define-condition resource-error (recoverable-error)
  ((resource :initarg :resource
             :reader error-resource
             :documentation "The resource that caused the error")
   (resource-type :initarg :resource-type
                  :reader error-resource-type
                  :initform :unknown
                  :documentation "Type of resource: :file, :network, :memory, etc."))
  (:report (lambda (c s)
             (format s "Resource error (~a ~a): ~a"
                     (error-resource-type c)
                     (error-resource c)
                     (condition-message c))))
  (:documentation "An error related to resource access"))

(define-condition state-inconsistency-error (recoverable-error)
  ((expected-state :initarg :expected-state
                   :reader error-expected-state
                   :documentation "The expected state")
   (actual-state :initarg :actual-state
                 :reader error-actual-state
                 :documentation "The actual state found"))
  (:report (lambda (c s)
             (format s "State inconsistency in ~a: expected ~a, got ~a"
                     (error-operation c)
                     (error-expected-state c)
                     (error-actual-state c))))
  (:documentation "An error due to inconsistent state"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Recovery Strategies
;;; ═══════════════════════════════════════════════════════════════════

(defclass recovery-strategy ()
  ((name :initarg :name
         :accessor strategy-name
         :documentation "Name of the recovery strategy")
   (description :initarg :description
                :accessor strategy-description
                :initform ""
                :documentation "Human-readable description")
   (applicable-p :initarg :applicable-p
                 :accessor strategy-applicable-p
                 :initform (constantly t)
                 :documentation "Predicate to check if strategy applies")
   (recover-fn :initarg :recover-fn
               :accessor strategy-recover-fn
               :documentation "Function to execute recovery")
   (priority :initarg :priority
             :accessor strategy-priority
             :initform 0
             :documentation "Higher priority strategies are tried first"))
  (:documentation "A strategy for recovering from errors"))

(defvar *recovery-strategies* (make-hash-table :test 'eq)
  "Registry of recovery strategies by error type.")

(defun register-recovery-strategy (error-type strategy)
  "Register a recovery strategy for ERROR-TYPE."
  (push strategy (gethash error-type *recovery-strategies*))
  ;; Keep sorted by priority
  (setf (gethash error-type *recovery-strategies*)
        (sort (gethash error-type *recovery-strategies*)
              #'> :key #'strategy-priority))
  strategy)

(defun find-recovery-strategies (condition)
  "Find applicable recovery strategies for CONDITION."
  (let ((strategies nil))
    (dolist (error-type (list (type-of condition) 'recoverable-error 'autopoiesis-error))
      (dolist (strategy (gethash error-type *recovery-strategies*))
        (when (funcall (strategy-applicable-p strategy) condition)
          (pushnew strategy strategies :key #'strategy-name))))
    (sort strategies #'> :key #'strategy-priority)))

(defmacro define-recovery-strategy (name error-type (&key (priority 0) description applicable-when) &body body)
  "Define a recovery strategy for ERROR-TYPE.
   
   NAME - Symbol naming the strategy
   ERROR-TYPE - Condition type this strategy handles
   PRIORITY - Higher priority strategies are tried first
   DESCRIPTION - Human-readable description
   APPLICABLE-WHEN - Form that returns T if strategy applies (condition bound to CONDITION)
   BODY - Recovery code (condition bound to CONDITION)"
  (let ((condition-var (gensym "CONDITION")))
    `(register-recovery-strategy
      ',error-type
      (make-instance 'recovery-strategy
                     :name ',name
                     :description ,description
                     :priority ,priority
                     :applicable-p (lambda (,condition-var)
                                     (declare (ignorable ,condition-var))
                                     ,(if applicable-when
                                          `(let ((condition ,condition-var))
                                             (declare (ignorable condition))
                                             ,applicable-when)
                                          t))
                     :recover-fn (lambda (,condition-var)
                                   (let ((condition ,condition-var))
                                     (declare (ignorable condition))
                                     ,@body))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Standard Restarts
;;; ═══════════════════════════════════════════════════════════════════

(defun establish-recovery-restarts (thunk &key operation default-value)
  "Run THUNK with comprehensive recovery restarts established.
   
   Available restarts:
   - CONTINUE-WITH-DEFAULT: Return DEFAULT-VALUE
   - RETRY-OPERATION: Retry the operation
   - RETRY-WITH-DELAY: Retry after a delay
   - USE-FALLBACK: Use a fallback value
   - SKIP-OPERATION: Skip and continue
   - ABORT-OPERATION: Abort with error"
  (restart-case (funcall thunk)
    (continue-with-default ()
      :report (lambda (s)
                (format s "Continue with default value~@[ (~a)~]" default-value))
      default-value)
    (retry-operation ()
      :report (lambda (s)
                (format s "Retry the operation~@[ (~a)~]" operation))
      (funcall thunk))
    (retry-with-delay (delay)
      :report (lambda (s)
                (format s "Retry after a delay~@[ (~a)~]" operation))
      :interactive (lambda ()
                     (format t "Enter delay in seconds: ")
                     (list (read)))
      (sleep delay)
      (funcall thunk))
    (use-fallback (value)
      :report "Use a fallback value"
      :interactive (lambda ()
                     (format t "Enter fallback value: ")
                     (list (eval (read))))
      value)
    (skip-operation ()
      :report (lambda (s)
                (format s "Skip this operation~@[ (~a)~]" operation))
      nil)
    (abort-operation ()
      :report "Abort the operation"
      (error 'autopoiesis-error
             :message (format nil "Operation aborted: ~a" operation)))))

(defmacro with-recovery ((&key operation default-value on-error) &body body)
  "Execute BODY with error recovery enabled.
   
   OPERATION - Name of the operation (for error messages)
   DEFAULT-VALUE - Value to return if CONTINUE-WITH-DEFAULT is invoked
   ON-ERROR - Form to evaluate on error (ERROR bound to the condition)
   
   Example:
     (with-recovery (:operation 'load-config :default-value *default-config*)
       (load-config-from-file path))"
  (let ((error-var (gensym "ERROR"))
        (block-name (gensym "WITH-RECOVERY-BLOCK")))
    `(block ,block-name
       (handler-bind
           ((recoverable-error
              (lambda (,error-var)
                (declare (ignorable ,error-var))
                ,@(when on-error
                    `((let ((error ,error-var))
                        (declare (ignorable error))
                        ,on-error)))))
            (autopoiesis-error
              (lambda (,error-var)
                (declare (ignorable ,error-var))
                ;; Try automatic recovery strategies
                (let ((strategies (find-recovery-strategies ,error-var)))
                  (dolist (strategy strategies)
                    (handler-case
                        (return-from ,block-name
                          (funcall (strategy-recover-fn strategy) ,error-var))
                      (error () nil)))))))
         (establish-recovery-restarts
          (lambda () ,@body)
          :operation ,operation
          :default-value ,default-value)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Retry with Backoff
;;; ═══════════════════════════════════════════════════════════════════

(defun exponential-backoff-delay (attempt &key (base-delay 0.1) (max-delay 30.0) (jitter 0.1))
  "Calculate delay for exponential backoff.
   
   ATTEMPT - Current attempt number (0-based)
   BASE-DELAY - Initial delay in seconds
   MAX-DELAY - Maximum delay cap
   JITTER - Random jitter factor (0.0-1.0)"
  (let* ((delay (* base-delay (expt 2 attempt)))
         (capped (min delay max-delay))
         (jitter-amount (* capped jitter (- (random 2.0) 1.0))))
    (max 0.0 (+ capped jitter-amount))))

(defun retry-with-backoff (thunk &key (max-retries 3) (base-delay 0.1) (max-delay 30.0)
                                   (retry-on '(transient-error)) (on-retry nil))
  "Execute THUNK with automatic retry and exponential backoff.
   
   MAX-RETRIES - Maximum number of retry attempts
   BASE-DELAY - Initial delay between retries
   MAX-DELAY - Maximum delay cap
   RETRY-ON - List of condition types to retry on
   ON-RETRY - Function called before each retry (attempt, condition, delay)
   
   Returns: (values result success-p attempts)"
  (let ((attempts 0))
    (loop
      (handler-case
          (return (values (funcall thunk) t attempts))
        (error (e)
          (incf attempts)
          (let ((should-retry (and (< attempts max-retries)
                                   (some (lambda (type) (typep e type)) retry-on))))
            (unless should-retry
              (return (values nil nil attempts)))
            (let ((delay (exponential-backoff-delay (1- attempts)
                                                    :base-delay base-delay
                                                    :max-delay max-delay)))
              (when on-retry
                (funcall on-retry attempts e delay))
              (sleep delay))))))))

(defmacro with-retry ((&key (max-retries 3) (base-delay 0.1) (retry-on ''(transient-error))) &body body)
  "Execute BODY with automatic retry on transient errors.
   
   Example:
     (with-retry (:max-retries 5 :base-delay 0.5)
       (fetch-remote-resource url))"
  `(retry-with-backoff (lambda () ,@body)
                       :max-retries ,max-retries
                       :base-delay ,base-delay
                       :retry-on ,retry-on))

;;; ═══════════════════════════════════════════════════════════════════
;;; Graceful Degradation
;;; ═══════════════════════════════════════════════════════════════════

(defclass degradation-level ()
  ((name :initarg :name
         :accessor degradation-name
         :documentation "Name of this degradation level")
   (description :initarg :description
                :accessor degradation-description
                :initform ""
                :documentation "Description of what's degraded")
   (capabilities :initarg :capabilities
                 :accessor degradation-capabilities
                 :initform nil
                 :documentation "List of capabilities available at this level")
   (restrictions :initarg :restrictions
                 :accessor degradation-restrictions
                 :initform nil
                 :documentation "List of restrictions at this level"))
  (:documentation "Represents a level of graceful degradation"))

(defvar *current-degradation-level* nil
  "Current system degradation level, or NIL for normal operation.")

(defvar *degradation-levels* (make-hash-table :test 'eq)
  "Registry of defined degradation levels.")

(defun define-degradation-level (name &key description capabilities restrictions)
  "Define a degradation level."
  (setf (gethash name *degradation-levels*)
        (make-instance 'degradation-level
                       :name name
                       :description description
                       :capabilities capabilities
                       :restrictions restrictions)))

(defun enter-degraded-mode (level &optional reason)
  "Enter a degraded operation mode.
   
   LEVEL - Degradation level name
   REASON - Optional reason for degradation"
  (let ((deg-level (gethash level *degradation-levels*)))
    (unless deg-level
      (error 'autopoiesis-error
             :message (format nil "Unknown degradation level: ~a" level)))
    (setf *current-degradation-level* deg-level)
    (warn 'autopoiesis-warning
          :message (format nil "Entering degraded mode: ~a~@[ (reason: ~a)~]"
                           (degradation-description deg-level)
                           reason))
    deg-level))

(defun exit-degraded-mode ()
  "Exit degraded mode and return to normal operation."
  (when *current-degradation-level*
    (let ((level *current-degradation-level*))
      (setf *current-degradation-level* nil)
      (warn 'autopoiesis-warning
            :message (format nil "Exiting degraded mode: ~a"
                             (degradation-name level)))
      level)))

(defun degraded-p ()
  "Check if system is in degraded mode."
  (not (null *current-degradation-level*)))

(defun capability-available-p (capability)
  "Check if CAPABILITY is available in current degradation level."
  (or (null *current-degradation-level*)
      (member capability (degradation-capabilities *current-degradation-level*))))

(defmacro with-graceful-degradation ((level &key on-degrade) &body body)
  "Execute BODY, degrading to LEVEL on error.
   
   LEVEL - Degradation level to enter on error
   ON-DEGRADE - Form to evaluate when degrading (ERROR bound to condition)
   
   Example:
     (with-graceful-degradation (:offline :on-degrade (log-degradation error))
       (sync-with-remote-server))"
  (let ((error-var (gensym "ERROR")))
    `(handler-case
         (progn ,@body)
       (error (,error-var)
         (enter-degraded-mode ,level (condition-message ,error-var))
         ,@(when on-degrade
             `((let ((error ,error-var))
                 (declare (ignorable error))
                 ,on-degrade)))
         nil))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Operation Wrappers
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-operation-recovery ((operation-name &key default on-error max-retries) &body body)
  "Comprehensive wrapper for recoverable operations.
   
   OPERATION-NAME - Name of the operation (for logging/errors)
   DEFAULT - Default value on unrecoverable error
   ON-ERROR - Form to evaluate on error
   MAX-RETRIES - Number of retries for transient errors
   
   Example:
     (with-operation-recovery ('save-snapshot :default nil :max-retries 3)
       (save-snapshot snapshot store))"
  (let ((retry-count (or max-retries 0)))
    (if (> retry-count 0)
        `(with-recovery (:operation ,operation-name :default-value ,default :on-error ,on-error)
           (with-retry (:max-retries ,retry-count)
             ,@body))
        `(with-recovery (:operation ,operation-name :default-value ,default :on-error ,on-error)
           ,@body))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Built-in Recovery Strategies
;;; ═══════════════════════════════════════════════════════════════════

;; Define standard degradation levels
(define-degradation-level :minimal
  :description "Minimal functionality - core operations only"
  :capabilities '(:read-snapshot :basic-navigation)
  :restrictions '(:no-persistence :no-network :no-extensions))

(define-degradation-level :offline
  :description "Offline mode - no network operations"
  :capabilities '(:read-snapshot :write-snapshot :navigation :local-extensions)
  :restrictions '(:no-network :no-remote-sync))

(define-degradation-level :read-only
  :description "Read-only mode - no modifications"
  :capabilities '(:read-snapshot :navigation :view-extensions)
  :restrictions '(:no-write :no-delete :no-new-extensions))

;; Define recovery strategies for common errors
(define-recovery-strategy retry-transient transient-error
    (:priority 100
     :description "Automatically retry transient errors"
     :applicable-when (< (error-retry-count condition) (error-max-retries condition)))
  (incf (error-retry-count condition))
  (sleep (exponential-backoff-delay (error-retry-count condition)))
  (invoke-restart 'retry-operation))

(define-recovery-strategy use-cached-value resource-error
    (:priority 50
     :description "Use cached value when resource unavailable"
     :applicable-when (eq (error-resource-type condition) :network))
  ;; Signal that we should try cache
  (invoke-restart 'continue-with-default))

(define-recovery-strategy enter-offline-mode resource-error
    (:priority 25
     :description "Enter offline mode on network errors"
     :applicable-when (and (eq (error-resource-type condition) :network)
                           (not (degraded-p))))
  (enter-degraded-mode :offline (condition-message condition))
  (invoke-restart 'skip-operation))

;;; ═══════════════════════════════════════════════════════════════════
;;; Component Health Tracking
;;; ═══════════════════════════════════════════════════════════════════

(defclass component-health ()
  ((name :initarg :name
         :accessor health-component-name
         :documentation "Name of the component")
   (status :initarg :status
           :accessor health-status
           :initform :healthy
           :documentation "Current status: :healthy, :degraded, :failed")
   (last-check :initarg :last-check
               :accessor health-last-check
               :initform nil
               :documentation "Timestamp of last health check")
   (failure-count :initarg :failure-count
                  :accessor health-failure-count
                  :initform 0
                  :documentation "Number of consecutive failures")
   (failure-threshold :initarg :failure-threshold
                      :accessor health-failure-threshold
                      :initform 3
                      :documentation "Failures before degradation")
   (last-error :initarg :last-error
               :accessor health-last-error
               :initform nil
               :documentation "Last error encountered")
   (degradation-level :initarg :degradation-level
                      :accessor health-degradation-level
                      :initform :minimal
                      :documentation "Level to degrade to on failure")
   (health-check-fn :initarg :health-check-fn
                    :accessor health-check-fn
                    :initform nil
                    :documentation "Function to check component health")
   (fallback-fn :initarg :fallback-fn
                :accessor health-fallback-fn
                :initform nil
                :documentation "Fallback function when degraded"))
  (:documentation "Tracks health status of a system component"))

(defvar *component-health-registry* (make-hash-table :test 'eq)
  "Registry of component health trackers.")

(defun register-component-health (name &key (failure-threshold 3)
                                            (degradation-level :minimal)
                                            health-check-fn
                                            fallback-fn)
  "Register a component for health tracking.
   
   NAME - Symbol identifying the component
   FAILURE-THRESHOLD - Consecutive failures before degradation
   DEGRADATION-LEVEL - Level to degrade to on failure
   HEALTH-CHECK-FN - Function to check health (returns T if healthy)
   FALLBACK-FN - Function to call when degraded"
  (setf (gethash name *component-health-registry*)
        (make-instance 'component-health
                       :name name
                       :failure-threshold failure-threshold
                       :degradation-level degradation-level
                       :health-check-fn health-check-fn
                       :fallback-fn fallback-fn)))

(defun get-component-health (name)
  "Get the health tracker for a component."
  (gethash name *component-health-registry*))

(defun record-component-success (name)
  "Record a successful operation for a component."
  (let ((health (get-component-health name)))
    (when health
      (setf (health-failure-count health) 0)
      (setf (health-status health) :healthy)
      (setf (health-last-check health) (get-precise-time)))))

(defun record-component-failure (name error)
  "Record a failure for a component, potentially triggering degradation."
  (let ((health (get-component-health name)))
    (when health
      (incf (health-failure-count health))
      (setf (health-last-error health) error)
      (setf (health-last-check health) (get-precise-time))
      ;; Check if we should degrade
      (when (>= (health-failure-count health) (health-failure-threshold health))
        (setf (health-status health) :failed)
        (enter-degraded-mode (health-degradation-level health)
                             (format nil "Component ~a failed: ~a" name error))))))

(defun check-component-health (name)
  "Run health check for a component.
   
   Returns: (values healthy-p status)"
  (let ((health (get-component-health name)))
    (if (null health)
        (values t :unknown)
        (let ((check-fn (health-check-fn health)))
          (if (null check-fn)
              (values (eq (health-status health) :healthy) (health-status health))
              (handler-case
                  (if (funcall check-fn)
                      (progn
                        (record-component-success name)
                        (values t :healthy))
                      (progn
                        (record-component-failure name "Health check returned false")
                        (values nil (health-status health))))
                (error (e)
                  (record-component-failure name e)
                  (values nil (health-status health)))))))))

(defun check-all-component-health ()
  "Run health checks for all registered components.
   
   Returns: Alist of (name . status)"
  (let ((results nil))
    (maphash (lambda (name health)
               (declare (ignore health))
               (multiple-value-bind (healthy-p status)
                   (check-component-health name)
                 (declare (ignore healthy-p))
                 (push (cons name status) results)))
             *component-health-registry*)
    (nreverse results)))

(defun component-healthy-p (name)
  "Check if a component is currently healthy."
  (let ((health (get-component-health name)))
    (or (null health)
        (eq (health-status health) :healthy))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Degraded Operation Execution
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-component-fallback ((component &key default on-fallback) &body body)
  "Execute BODY with automatic fallback on component failure.
   
   COMPONENT - Component name (symbol)
   DEFAULT - Value to return if fallback fails
   ON-FALLBACK - Form to evaluate when falling back
   
   If the component is degraded, uses the fallback function.
   If BODY fails, records the failure and may trigger degradation."
  (let ((result-var (gensym "RESULT"))
        (health-var (gensym "HEALTH")))
    `(let ((,health-var (get-component-health ',component)))
       (cond
         ;; Component is failed/degraded - use fallback
         ((and ,health-var
               (member (health-status ,health-var) '(:failed :degraded)))
          (let ((fallback-fn (health-fallback-fn ,health-var)))
            (if fallback-fn
                (progn
                  ,@(when on-fallback `(,on-fallback))
                  (funcall fallback-fn))
                ,default)))
         ;; Try normal operation
         (t
          (handler-case
              (let ((,result-var (progn ,@body)))
                (when ,health-var
                  (record-component-success ',component))
                ,result-var)
            (error (e)
              (when ,health-var
                (record-component-failure ',component e))
              ;; Try fallback if available
              (let ((fallback-fn (when ,health-var (health-fallback-fn ,health-var))))
                (if fallback-fn
                    (progn
                      ,@(when on-fallback `(,on-fallback))
                      (funcall fallback-fn))
                    ,default)))))))))

(defmacro with-degradation-check ((capability &key fallback-value) &body body)
  "Execute BODY only if CAPABILITY is available in current degradation level.
   
   If degraded and capability unavailable, returns FALLBACK-VALUE."
  `(if (capability-available-p ,capability)
       (progn ,@body)
       ,fallback-value))

;;; ═══════════════════════════════════════════════════════════════════
;;; Automatic Degradation Triggers
;;; ═══════════════════════════════════════════════════════════════════

(defvar *degradation-triggers* (make-hash-table :test 'eq)
  "Registry of automatic degradation triggers.")

(defclass degradation-trigger ()
  ((name :initarg :name
         :accessor trigger-name
         :documentation "Name of the trigger")
   (condition-type :initarg :condition-type
                   :accessor trigger-condition-type
                   :documentation "Condition type that triggers degradation")
   (target-level :initarg :target-level
                 :accessor trigger-target-level
                 :documentation "Degradation level to enter")
   (predicate :initarg :predicate
              :accessor trigger-predicate
              :initform (constantly t)
              :documentation "Additional predicate to check"))
  (:documentation "Defines when to automatically enter degraded mode"))

(defun register-degradation-trigger (name condition-type target-level &key predicate)
  "Register an automatic degradation trigger.
   
   NAME - Symbol identifying the trigger
   CONDITION-TYPE - Condition type that triggers degradation
   TARGET-LEVEL - Degradation level to enter
   PREDICATE - Optional additional predicate (receives condition)"
  (setf (gethash name *degradation-triggers*)
        (make-instance 'degradation-trigger
                       :name name
                       :condition-type condition-type
                       :target-level target-level
                       :predicate (or predicate (constantly t)))))

(defun find-applicable-trigger (condition)
  "Find a degradation trigger applicable to CONDITION."
  (maphash (lambda (name trigger)
             (declare (ignore name))
             (when (and (typep condition (trigger-condition-type trigger))
                        (funcall (trigger-predicate trigger) condition))
               (return-from find-applicable-trigger trigger)))
           *degradation-triggers*)
  nil)

(defmacro with-auto-degradation ((&key on-degrade) &body body)
  "Execute BODY with automatic degradation on registered trigger conditions.
   
   ON-DEGRADE - Form to evaluate when degradation occurs (ERROR bound to condition)"
  (let ((error-var (gensym "ERROR"))
        (trigger-var (gensym "TRIGGER")))
    `(handler-bind
         ((error (lambda (,error-var)
                   (let ((,trigger-var (find-applicable-trigger ,error-var)))
                     (when ,trigger-var
                       (enter-degraded-mode (trigger-target-level ,trigger-var)
                                            (format nil "~a" ,error-var))
                       ,@(when on-degrade
                           `((let ((error ,error-var))
                               (declare (ignorable error))
                               ,on-degrade))))))))
       ,@body)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Standard Degradation Triggers
;;; ═══════════════════════════════════════════════════════════════════

;; Network-related errors trigger offline mode
(register-degradation-trigger :network-failure
                              'resource-error
                              :offline
                              :predicate (lambda (e)
                                           (eq (error-resource-type e) :network)))

;; Storage errors trigger read-only mode
(register-degradation-trigger :storage-failure
                              'resource-error
                              :read-only
                              :predicate (lambda (e)
                                           (eq (error-resource-type e) :file)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Health Recovery
;;; ═══════════════════════════════════════════════════════════════════

(defun attempt-recovery (component)
  "Attempt to recover a failed component.
   
   Returns T if recovery successful."
  (let ((health (get-component-health component)))
    (when (and health (health-check-fn health))
      (handler-case
          (when (funcall (health-check-fn health))
            (setf (health-failure-count health) 0)
            (setf (health-status health) :healthy)
            (setf (health-last-check health) (get-precise-time))
            ;; Check if we can exit degraded mode
            (maybe-exit-degraded-mode)
            t)
        (error () nil)))))

(defun attempt-all-recovery ()
  "Attempt recovery for all failed components.
   
   Returns list of successfully recovered components."
  (let ((recovered nil))
    (maphash (lambda (name health)
               (when (member (health-status health) '(:failed :degraded))
                 (when (attempt-recovery name)
                   (push name recovered))))
             *component-health-registry*)
    recovered))

(defun maybe-exit-degraded-mode ()
  "Exit degraded mode if all components are healthy."
  (when (degraded-p)
    (let ((all-healthy t))
      (maphash (lambda (name health)
                 (declare (ignore name))
                 (unless (eq (health-status health) :healthy)
                   (setf all-healthy nil)))
               *component-health-registry*)
      (when all-healthy
        (exit-degraded-mode)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; System Health Summary
;;; ═══════════════════════════════════════════════════════════════════

(defun system-health-summary ()
  "Get a summary of system health.
   
   Returns plist with:
   - :degraded-p - Whether system is in degraded mode
   - :degradation-level - Current degradation level (or nil)
   - :components - List of (name status failure-count) tuples
   - :overall-status - :healthy, :degraded, or :critical"
  (let ((components nil)
        (failed-count 0)
        (degraded-count 0))
    (maphash (lambda (name health)
               (push (list name
                           (health-status health)
                           (health-failure-count health))
                     components)
               (case (health-status health)
                 (:failed (incf failed-count))
                 (:degraded (incf degraded-count))))
             *component-health-registry*)
    (list :degraded-p (degraded-p)
          :degradation-level (when *current-degradation-level*
                               (degradation-name *current-degradation-level*))
          :components (nreverse components)
          :overall-status (cond
                            ((> failed-count 0) :critical)
                            ((or (> degraded-count 0) (degraded-p)) :degraded)
                            (t :healthy)))))

(defun print-health-summary (&optional (stream *standard-output*))
  "Print a human-readable health summary."
  (let ((summary (system-health-summary)))
    (format stream "~&═══════════════════════════════════════════════════════════════~%")
    (format stream "SYSTEM HEALTH SUMMARY~%")
    (format stream "═══════════════════════════════════════════════════════════════~%")
    (format stream "Overall Status: ~a~%" (getf summary :overall-status))
    (format stream "Degraded Mode: ~a~@[ (~a)~]~%"
            (if (getf summary :degraded-p) "YES" "NO")
            (getf summary :degradation-level))
    (format stream "~%Components:~%")
    (dolist (comp (getf summary :components))
      (format stream "  ~20a ~10a (failures: ~d)~%"
              (first comp) (second comp) (third comp)))
    (format stream "═══════════════════════════════════════════════════════════════~%")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Recovery Logging
;;; ═══════════════════════════════════════════════════════════════════

(defvar *recovery-log* nil
  "Log of recovery actions taken.")

(defstruct recovery-event
  "Record of a recovery action."
  timestamp
  operation
  error-type
  error-message
  strategy-used
  outcome)

(defun log-recovery-event (operation error strategy outcome)
  "Log a recovery event."
  (let ((event (make-recovery-event
                :timestamp (get-precise-time)
                :operation operation
                :error-type (type-of error)
                :error-message (condition-message error)
                :strategy-used (when strategy (strategy-name strategy))
                :outcome outcome)))
    (push event *recovery-log*)
    ;; Keep log bounded
    (when (> (length *recovery-log*) 1000)
      (setf *recovery-log* (subseq *recovery-log* 0 500)))
    event))

(defun get-recovery-log (&key (limit 100) operation error-type)
  "Get recent recovery events, optionally filtered."
  (let ((log *recovery-log*))
    (when operation
      (setf log (remove-if-not (lambda (e) (eq (recovery-event-operation e) operation)) log)))
    (when error-type
      (setf log (remove-if-not (lambda (e) (eq (recovery-event-error-type e) error-type)) log)))
    (subseq log 0 (min limit (length log)))))

(defun clear-recovery-log ()
  "Clear the recovery log."
  (setf *recovery-log* nil))
