;;;; trigger-conditions.lisp - Models and schemas for crystallization triggers
;;;;
;;;; Defines configurable trigger conditions for automated crystallization,
;;;; including performance thresholds and scheduled intervals.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; Trigger Condition Models
;;; ===================================================================

(defstruct trigger-condition
  "Base structure for crystallization trigger conditions."
  (id (make-uuid) :type string :read-only t)
  (enabled t :type boolean)
  (name "" :type string)
  (description "" :type string)
  (last-triggered nil :type (or null integer)))

(defstruct (performance-threshold-trigger (:include trigger-condition))
  "Trigger based on agent performance metrics."
  (metric-type :heuristic-confidence :type keyword)  ; :heuristic-confidence, :success-rate, :profile-time
  (threshold 0.8 :type number)                         ; Threshold value to trigger on
  (comparison :above :type keyword)                    ; :above, :below, :equals
  (agent-id nil :type (or null string))                ; Specific agent, or nil for any
  (cooldown-seconds 3600 :type integer))               ; Minimum seconds between triggers

(defstruct (scheduled-interval-trigger (:include trigger-condition))
  "Trigger based on time intervals."
  (interval-seconds 86400 :type integer)               ; How often to trigger (default: daily)
  (next-trigger-time (get-universal-time) :type integer)) ; When to trigger next

;;; ===================================================================
;;; Trigger Registry
;;; ===================================================================

(defvar *trigger-registry* (make-hash-table :test 'equal)
  "Registry of active trigger conditions, keyed by trigger ID.")

(defvar *trigger-registry-lock* (bt:make-lock "trigger-registry")
  "Lock for thread-safe trigger registry access.")

(defun register-trigger (trigger)
  "Register a trigger condition in the global registry."
  (bt:with-lock-held (*trigger-registry-lock*)
    (setf (gethash (trigger-condition-id trigger) *trigger-registry*) trigger))
  trigger)

(defun unregister-trigger (trigger-id)
  "Remove a trigger condition from the registry."
  (bt:with-lock-held (*trigger-registry-lock*)
    (remhash trigger-id *trigger-registry*)))

(defun get-trigger (trigger-id)
  "Get a trigger condition by ID."
  (bt:with-lock-held (*trigger-registry-lock*)
    (gethash trigger-id *trigger-registry*)))

(defun list-triggers ()
  "Return a list of all registered triggers."
  (bt:with-lock-held (*trigger-registry-lock*)
    (loop for trigger being the hash-values of *trigger-registry*
          collect trigger)))

(defun clear-triggers ()
  "Remove all triggers from the registry."
  (bt:with-lock-held (*trigger-registry-lock*)
    (clrhash *trigger-registry*)))

;;; ===================================================================
;;; Performance Metric Evaluation
;;; ===================================================================

(defun get-agent-heuristic-confidence (agent-id)
  "Get the average heuristic confidence across all agents.
   Currently heuristics are global, not agent-specific."
  (declare (ignore agent-id)) ; Heuristics are currently global
  (let ((heuristics (autopoiesis.agent:list-heuristics)))
    (if heuristics
        (/ (reduce #'+ heuristics :key #'autopoiesis.agent:heuristic-confidence)
           (length heuristics))
        0.0)))

(defun get-agent-success-rate (agent-id)
  "Get the success rate for an agent based on recent experiences."
  (let* ((experiences (autopoiesis.agent:list-experiences :agent-id agent-id))
         (recent-exps (subseq experiences 0 (min 100 (length experiences)))))
    (if recent-exps
        (let ((success-count (count :success recent-exps :key #'autopoiesis.agent:experience-outcome)))
          (/ success-count (length recent-exps)))
        0.0)))

(defun get-agent-profile-time (agent-id operation-name)
  "Get average profile time for a specific operation on an agent."
  (declare (ignore agent-id)) ; For now, get global metrics
  (let ((metric (autopoiesis.core:get-profile-metric operation-name)))
    (when metric
      (autopoiesis.core:ns-to-ms
       (/ (autopoiesis.core:profile-metric-total-time-ns metric)
          (autopoiesis.core:profile-metric-call-count metric))))))

;;; ===================================================================
;;; Trigger Evaluation
;;; ===================================================================

(defgeneric evaluate-trigger (trigger)
  (:documentation "Evaluate if a trigger condition is met. Returns T if crystallization should occur."))

(defmethod evaluate-trigger ((trigger performance-threshold-trigger))
  "Check if performance threshold is met."
  (let* ((metric-type (performance-threshold-trigger-metric-type trigger))
         (threshold (performance-threshold-trigger-threshold trigger))
         (comparison (performance-threshold-trigger-comparison trigger))
         (agent-id (performance-threshold-trigger-agent-id trigger))
         (cooldown (performance-threshold-trigger-cooldown-seconds trigger))
         (last-triggered (trigger-condition-last-triggered trigger))
         (current-time (get-universal-time)))

    ;; Check cooldown
    (when (and last-triggered (< (- current-time last-triggered) cooldown))
      (return-from evaluate-trigger nil))

    ;; Get current metric value
    (let ((current-value
           (case metric-type
             (:heuristic-confidence (get-agent-heuristic-confidence agent-id))
             (:success-rate (get-agent-success-rate agent-id))
             (:profile-time (get-agent-profile-time agent-id "cognitive-cycle"))
             (otherwise 0.0))))

      ;; Compare against threshold
      (when current-value
        (let ((triggered
               (case comparison
                 (:above (> current-value threshold))
                 (:below (< current-value threshold))
                 (:equals (= current-value threshold))
                 (otherwise nil))))
          (when triggered
            ;; Update last triggered time
            (setf (trigger-condition-last-triggered trigger) current-time))
          triggered)))))

(defmethod evaluate-trigger ((trigger scheduled-interval-trigger))
  "Check if scheduled interval has elapsed."
  (let ((next-time (scheduled-interval-trigger-next-trigger-time trigger))
        (current-time (get-universal-time)))
    (when (>= current-time next-time)
      ;; Schedule next trigger
      (setf (scheduled-interval-trigger-next-trigger-time trigger)
            (+ current-time (scheduled-interval-trigger-interval-seconds trigger)))
      ;; Update last triggered
      (setf (trigger-condition-last-triggered trigger) current-time)
      t)))

;;; ===================================================================
;;; Trigger Management
;;; ===================================================================

(defun check-all-triggers (&key agent)
  "Check all enabled triggers and return list of triggered conditions.
   Returns a list of trigger IDs that should trigger crystallization."
  (let (triggered-triggers)
    (bt:with-lock-held (*trigger-registry-lock*)
      (loop for trigger being the hash-values of *trigger-registry*
            when (and (trigger-condition-enabled trigger)
                      (evaluate-trigger trigger))
            do (push trigger triggered-triggers)))
    triggered-triggers))

(defun create-performance-trigger (name description metric-type threshold
                                  &key (comparison :above) agent-id (cooldown-seconds 3600))
  "Create and register a new performance threshold trigger."
  (let ((trigger (make-performance-threshold-trigger
                  :name name
                  :description description
                  :metric-type metric-type
                  :threshold threshold
                  :comparison comparison
                  :agent-id agent-id
                  :cooldown-seconds cooldown-seconds)))
    (register-trigger trigger)))

(defun create-scheduled-trigger (name description interval-seconds)
  "Create and register a new scheduled interval trigger."
  (let ((trigger (make-scheduled-interval-trigger
                  :name name
                  :description description
                  :interval-seconds interval-seconds)))
    (register-trigger trigger)))

;;; ===================================================================
;;; Serialization/Storage
;;; ===================================================================

(defgeneric trigger-to-plist (trigger)
  (:documentation "Convert trigger to property list for storage."))

(defmethod trigger-to-plist ((trigger trigger-condition))
  `(:id ,(trigger-condition-id trigger)
    :enabled ,(trigger-condition-enabled trigger)
    :name ,(trigger-condition-name trigger)
    :description ,(trigger-condition-description trigger)
    :last-triggered ,(trigger-condition-last-triggered trigger)
    :type ,(type-of trigger)))

(defmethod trigger-to-plist ((trigger performance-threshold-trigger))
  (append (call-next-method)
          `(:metric-type ,(performance-threshold-trigger-metric-type trigger)
            :threshold ,(performance-threshold-trigger-threshold trigger)
            :comparison ,(performance-threshold-trigger-comparison trigger)
            :agent-id ,(performance-threshold-trigger-agent-id trigger)
            :cooldown-seconds ,(performance-threshold-trigger-cooldown-seconds trigger))))

(defmethod trigger-to-plist ((trigger scheduled-interval-trigger))
  (append (call-next-method)
          `(:interval-seconds ,(scheduled-interval-trigger-interval-seconds trigger)
            :next-trigger-time ,(scheduled-interval-trigger-next-trigger-time trigger))))

(defgeneric plist-to-trigger (plist)
  (:documentation "Reconstruct trigger from property list."))

(defmethod plist-to-trigger (plist)
  (let ((type (getf plist :type)))
    (case type
      (performance-threshold-trigger
       (make-performance-threshold-trigger
        :id (getf plist :id)
        :enabled (getf plist :enabled)
        :name (getf plist :name)
        :description (getf plist :description)
        :last-triggered (getf plist :last-triggered)
        :metric-type (getf plist :metric-type)
        :threshold (getf plist :threshold)
        :comparison (getf plist :comparison)
        :agent-id (getf plist :agent-id)
        :cooldown-seconds (getf plist :cooldown-seconds)))
      (scheduled-interval-trigger
       (make-scheduled-interval-trigger
        :id (getf plist :id)
        :enabled (getf plist :enabled)
        :name (getf plist :name)
        :description (getf plist :description)
        :last-triggered (getf plist :last-triggered)
        :interval-seconds (getf plist :interval-seconds)
        :next-trigger-time (getf plist :next-trigger-time)))
      (otherwise nil))))

(defun save-triggers-to-store ()
  "Save all triggers to the substrate store."
  (when autopoiesis.substrate:*store*
    (let ((trigger-plists (mapcar #'trigger-to-plist (list-triggers))))
      (autopoiesis.substrate:transact!
       (list (list :db/add :global :crystallize-triggers trigger-plists))))))

(defun load-triggers-from-store ()
  "Load triggers from the substrate store."
  (when autopoiesis.substrate:*store*
    (let ((stored-plists (autopoiesis.substrate:entity-attr :global :crystallize-triggers)))
      (when stored-plists
        (clear-triggers)
        (dolist (plist stored-plists)
          (let ((trigger (plist-to-trigger plist)))
            (when trigger
              (register-trigger trigger))))))))

;;; ===================================================================
;;; Integration with Crystallization
;;; ===================================================================

(defun auto-crystallize-if-triggered (agent)
  "Check triggers and perform crystallization if any are met.
   Returns the snapshot if crystallization occurred, NIL otherwise."
  (let ((triggered-triggers (check-all-triggers :agent agent)))
    (when triggered-triggers
      (format t "~&Crystallization triggered by: ~{~A~^, ~}~%"
              (mapcar #'trigger-condition-name triggered-triggers))
      (crystallize-all agent :label "auto-triggered"))))