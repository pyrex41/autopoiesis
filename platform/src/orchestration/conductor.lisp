;;;; conductor.lisp - Central scheduler with tick loop and timer heap
;;;;
;;;; The conductor runs a background thread with a 100ms tick loop.
;;;; Events and workers are stored as datoms in the substrate, NOT
;;;; as class slots. The conductor's timer heap is the only in-memory
;;;; scheduling structure.

(in-package #:autopoiesis.orchestration)

;;; ===================================================================
;;; Conductor class
;;; ===================================================================

(defvar *conductor* nil "The active conductor instance.")

(defclass conductor ()
  ((timer-heap :initform nil :accessor conductor-timer-heap
                :documentation "List of (fire-time . action-plist) sorted by time")
    (tick-thread :initform nil :accessor conductor-tick-thread)
    (running :initform nil :accessor conductor-running-p)
    (metrics :initform (make-hash-table :test 'eq) :accessor conductor-metrics)
    (failure-counts :initform (make-hash-table :test 'equal)
                    :accessor conductor-failure-counts)
    (lock :initform (bt:make-lock "conductor") :accessor conductor-lock)
    (tick-counter :initform 0 :accessor conductor-tick-counter
                  :documentation "Counter for periodic trigger checks")
    ;; Captured substrate bindings for the tick thread
    (substrate-bindings :initform nil :accessor conductor-substrate-bindings
                        :documentation "Plist of substrate special variable bindings"))
  (:documentation "Central scheduler -- tick loop with timer heap.
   Events and worker status are stored as datoms in the substrate."))

;;; ===================================================================
;;; Metrics
;;; ===================================================================

(defun increment-metric (conductor name &optional (delta 1))
  "Increment a metric counter by DELTA."
  (bt:with-lock-held ((conductor-lock conductor))
    (incf (gethash name (conductor-metrics conductor) 0) delta)))

(defun get-metric (conductor name)
  "Get the current value of a metric."
  (gethash name (conductor-metrics conductor) 0))

;;; ===================================================================
;;; Timer heap (sorted list, fire-time ascending)
;;; ===================================================================

(defun schedule-action (conductor delay-seconds action-plist)
  "Schedule an action to fire after DELAY-SECONDS.
   ACTION-PLIST must include :action-type. Returns the fire-time."
  (let ((fire-time (+ (get-universal-time) delay-seconds)))
    (bt:with-lock-held ((conductor-lock conductor))
      (setf (conductor-timer-heap conductor)
            (merge 'list
                   (list (cons fire-time action-plist))
                   (conductor-timer-heap conductor)
                   #'< :key #'car)))
    fire-time))

(defun cancel-action (conductor action-type)
  "Cancel all pending actions with the given :action-type."
  (bt:with-lock-held ((conductor-lock conductor))
    (setf (conductor-timer-heap conductor)
          (remove action-type (conductor-timer-heap conductor)
                  :key (lambda (entry) (getf (cdr entry) :action-type))))))

(defun process-due-timers (conductor)
  "Fire all timers whose fire-time <= now."
  (let ((now (get-universal-time)))
    (loop
      (bt:with-lock-held ((conductor-lock conductor))
        (let ((next (first (conductor-timer-heap conductor))))
          (unless (and next (<= (car next) now))
            (return))
          (pop (conductor-timer-heap conductor))
          ;; Execute outside the lock by releasing and re-acquiring
          (handler-case
              (execute-timer-action conductor (cdr next))
            (error (e)
              (format *error-output* "~&Timer action error: ~A~%" e)
              (increment-metric conductor :timer-errors))))))))

(defun execute-timer-action (conductor action-plist)
  "Dispatch on :action-type in ACTION-PLIST."
  (let ((action-type (getf action-plist :action-type)))
    (case action-type
      (:tick nil)
      (:claude
       ;; Spawn Claude CLI worker if not already running
       (let ((id (getf action-plist :id)))
         (unless (and id (worker-running-p conductor (princ-to-string id)))
           (let ((task-id (format nil "claude-~A" (make-uuid))))
             (register-worker conductor task-id (bt:current-thread))
             (run-claude-cli
              (list :prompt (getf action-plist :prompt)
                    :mcp-config (getf action-plist :mcp-config)
                    :allowed-tools (getf action-plist :allowed-tools)
                    :max-turns (getf action-plist :max-turns 50)
                    :claude-path (getf action-plist :claude-path))
              :timeout (or (getf action-plist :timeout) 300)
              :on-complete (lambda (result)
                             (handle-task-result conductor task-id :success result))
              :on-error (lambda (reason)
                          (handle-task-result conductor task-id :failure
                                             (format nil "~A" reason))))))))
      (:agent-wakeup
       ;; Send a scheduled message to an agent's mailbox
       (let ((agent-id (getf action-plist :agent-id))
             (message (getf action-plist :message))
             (recurring-p (getf action-plist :recurring))
             (interval (getf action-plist :interval)))
         (when agent-id
           (ignore-errors
             (let ((agent-pkg (find-package :autopoiesis.agent)))
               (when agent-pkg
                 (let ((send-fn (find-symbol "SEND-MESSAGE" agent-pkg))
                       (typed-fn (find-symbol "MAKE-TYPED-MESSAGE" agent-pkg)))
                   (when (and send-fn typed-fn (fboundp send-fn) (fboundp typed-fn))
                     (funcall send-fn "conductor" agent-id
                              (funcall typed-fn :scheduled message)))))))
           ;; Re-schedule if recurring
           (when (and recurring-p interval (> interval 0))
             (schedule-action conductor interval action-plist)))))
      (otherwise
       ;; Default: queue as event for processing
       (queue-event action-type action-plist)))))

;;; ===================================================================
;;; Event queue (substrate-backed)
;;; ===================================================================

(defun make-uuid ()
  "Generate a simple unique identifier."
  (format nil "~8,'0X-~4,'0X"
          (random (expt 16 8))
          (random (expt 16 4))))

(defun queue-event (event-type data &key (store *store*))
  "Queue an event as datoms. Hooks fire, conductor processes on next tick."
  (declare (ignore store))
  (let ((event-id (intern-id (format nil "event-~A-~A" event-type (make-uuid)))))
    (transact!
     (list (make-datom event-id :event/type event-type)
           (make-datom event-id :event/data data)
           (make-datom event-id :event/status :pending)
           (make-datom event-id :event/created-at (get-universal-time))))
    event-id))

(defun process-events (conductor)
  "Process pending events by claiming them via take!."
  (loop for event-eid = (take! :event/status :pending :new-value :processing)
        while event-eid
        do (let ((event-type (entity-attr event-eid :event/type))
                 (event-data (entity-attr event-eid :event/data)))
             (handler-case
                 (progn
                   (dispatch-event conductor event-type event-data)
                   (transact! (list (make-datom event-eid :event/status :complete)))
                   (increment-metric conductor :events-processed))
               (error (e)
                 (transact! (list (make-datom event-eid :event/status :failed)
                                  (make-datom event-eid :event/error (format nil "~A" e))))
                 (increment-metric conductor :events-failed))))))

(defun dispatch-event (conductor event-type event-data)
  "Dispatch an event based on its type. Extensible via methods later."
  (case event-type
    (:task-result
     ;; Handle task completion -- update worker datoms
     (let ((task-id (getf event-data :task-id))
           (result (getf event-data :result))
           (status (getf event-data :status)))
       (when task-id
         (handle-task-result conductor task-id status result))))
    ;; Team coordination events — increment metrics
    ((:team-created :team-started :team-completed :team-failed)
     (increment-metric conductor :team-events))
    (:team-task-completed
     (increment-metric conductor :team-tasks-completed))
    ((:team-member-joined :team-member-left :team-task-assigned)
     (increment-metric conductor :team-events))
    ;; Swarm orchestration events
    ((:swarm-evolution-started :swarm-evolution-completed :swarm-evolution-failed)
     (increment-metric conductor :swarm-events))
    (:swarm-generation-completed
     (increment-metric conductor :swarm-generations))
    ((:swarm-agent-evolved :swarm-team-optimized)
     (increment-metric conductor :swarm-events))
    (otherwise nil)))

;;; ===================================================================
;;; Workers (substrate-backed)
;;; ===================================================================

(defun register-worker (conductor task-id thread)
  "Register a running worker as datoms."
  (declare (ignore conductor))
  (let ((worker-eid (intern-id task-id)))
    (transact!
     (list (make-datom worker-eid :worker/task-id task-id)
           (make-datom worker-eid :worker/status :running)
           (make-datom worker-eid :worker/thread thread)
           (make-datom worker-eid :worker/started-at (get-universal-time))))
    worker-eid))

(defun unregister-worker (conductor task-id &key (status :complete) result error-msg)
  "Mark a worker as finished in the substrate."
  (declare (ignore conductor))
  (let ((worker-eid (intern-id task-id)))
    (transact!
     (append
      (list (make-datom worker-eid :worker/status status))
      (when result
        (list (make-datom worker-eid :worker/result result)))
      (when error-msg
        (list (make-datom worker-eid :worker/error error-msg)))))))

(defun worker-running-p (conductor task-id)
  "Check if a worker is currently running."
  (declare (ignore conductor))
  (let ((worker-eid (intern-id task-id)))
    (eq (entity-attr worker-eid :worker/status) :running)))

(defun conductor-active-workers (&key (store *store*))
  "Return list of task-ids for all running workers."
  (declare (ignore store))
  (let ((eids (find-entities :worker/status :running)))
    (mapcar (lambda (eid) (entity-attr eid :worker/task-id)) eids)))

;;; ===================================================================
;;; Task result handling with failure backoff
;;; ===================================================================

(defun handle-task-result (conductor task-id status result)
  "Handle a completed task. Track failures for backoff."
  (case status
    (:success
     ;; Clear failure count on success
     (bt:with-lock-held ((conductor-lock conductor))
       (remhash task-id (conductor-failure-counts conductor)))
     (unregister-worker conductor task-id :status :complete :result result))
    (:failure
     ;; Increment failure count, apply backoff
     (let ((count (bt:with-lock-held ((conductor-lock conductor))
                    (incf (gethash task-id (conductor-failure-counts conductor) 0)))))
       (unregister-worker conductor task-id
                          :status :failed
                          :error-msg (or result "unknown error"))
       ;; Exponential backoff: 2^count seconds, max 300
       (let ((backoff (min 300 (expt 2 count))))
         (increment-metric conductor :task-retries)
         (format *error-output* "~&Task ~A failed (~D times), retry in ~Ds~%"
                 task-id count backoff))))))

(defun failure-count (conductor task-id)
  "Get the failure count for a task."
  (bt:with-lock-held ((conductor-lock conductor))
    (gethash task-id (conductor-failure-counts conductor) 0)))

;;; ===================================================================
;;; Crystallization trigger checking
;;; ===================================================================

(defparameter *trigger-check-interval* 100
  "Number of ticks between trigger checks (100 ticks = 10 seconds).")

(defun check-crystallization-triggers (conductor)
  "Check crystallization triggers periodically. Called every tick."
  (when (>= (incf (conductor-tick-counter conductor)) *trigger-check-interval*)
    (setf (conductor-tick-counter conductor) 0)
    (when (not (find-package :autopoiesis.crystallize))
      (return-from check-crystallization-triggers nil))
    (handler-case
        (let* ((list-agents-fn (find-symbol "LIST-AGENTS" :autopoiesis.agent))
               (agent-running-p-fn (find-symbol "AGENT-RUNNING-P" :autopoiesis.agent))
               (auto-crystallize-fn (find-symbol "AUTO-CRYSTALLIZE-IF-TRIGGERED" :autopoiesis.crystallize))
               (agents (funcall list-agents-fn))
               (triggers-checked 0)
               (crystallizations-performed 0))
          (dolist (agent agents)
            (when (funcall agent-running-p-fn agent)
              (let ((snapshot (funcall auto-crystallize-fn agent)))
                (incf triggers-checked)
                (when snapshot
                  (incf crystallizations-performed)))))
          ;; Update metrics
          (when (> triggers-checked 0)
            (increment-metric conductor :triggers-checked triggers-checked))
          (when (> crystallizations-performed 0)
            (increment-metric conductor :crystallizations-performed crystallizations-performed)))
      (error (e)
        (format *error-output* "~&Crystallization trigger check error: ~A~%" e)
        (increment-metric conductor :trigger-check-errors)))))

;;; ===================================================================
;;; Tick loop
;;; ===================================================================

(defun check-periodic-consistency (conductor)
  "Run periodic consistency checks if snapshot layer is loaded.
   Uses the same dynamic resolution pattern as check-crystallization-triggers."
  (declare (ignore conductor))
  (when (find-package :autopoiesis.snapshot)
    (let ((fn (find-symbol "MAYBE-RUN-CONSISTENCY-CHECK" :autopoiesis.snapshot)))
      (when (and fn (fboundp fn))
        (handler-case
            (funcall fn)
          (error (e)
            (format *error-output* "~&Consistency check error in conductor: ~A~%" e)))))))

(defun conductor-tick-loop (conductor)
  "Main tick loop. Runs every 100ms while conductor is running."
  (loop while (conductor-running-p conductor)
        do (handler-case
                (progn
                  (process-due-timers conductor)
                  (process-events conductor)
                  (check-crystallization-triggers conductor)
                  (check-periodic-consistency conductor)
                  (increment-metric conductor :tick-count))
              (error (e)
                (format *error-output* "~&Conductor tick error: ~A~%" e)
                (increment-metric conductor :tick-errors)))
            (sleep 0.1)))

;;; ===================================================================
;;; Conductor lifecycle
;;; ===================================================================

(defun start-conductor (&key (store *store*))
  "Start the conductor. Returns the conductor instance.
    Captures current *substrate* context so the tick thread sees the same store."
  (when (and *conductor* (conductor-running-p *conductor*))
    (error "Conductor already running"))
  ;; Load crystallization triggers from store if crystallize is available
  (when (find-package :autopoiesis.crystallize)
    (funcall (find-symbol "LOAD-TRIGGERS-FROM-STORE" :autopoiesis.crystallize)))
  (let ((conductor (make-instance 'conductor))
        ;; Single context capture replaces 7 individual variable captures.
        (captured-substrate autopoiesis.substrate:*substrate*)
        (captured-store store))
    (setf (conductor-running-p conductor) t)
    (setf (conductor-tick-thread conductor)
          (bt:make-thread
           (lambda ()
             (let ((autopoiesis.substrate:*substrate* captured-substrate)
                   (*store* captured-store))
               (conductor-tick-loop conductor)))
           :name "conductor-tick"))
    (setf *conductor* conductor)
    conductor))

(defun stop-conductor (&key (conductor *conductor*))
  "Stop the conductor and wait for the tick thread to exit."
  (when conductor
    (setf (conductor-running-p conductor) nil)
    (when (conductor-tick-thread conductor)
      (handler-case
          (bt:join-thread (conductor-tick-thread conductor))
        (error () nil))
      (setf (conductor-tick-thread conductor) nil))
    (when (eq *conductor* conductor)
      (setf *conductor* nil))
    t))

;;; ===================================================================
;;; Status
;;; ===================================================================

(defun conductor-status (&key (conductor *conductor*))
  "Return conductor status as a plist."
  (if conductor
      (let ((base-status (list :running (conductor-running-p conductor)
                               :tick-count (get-metric conductor :tick-count)
                               :events-processed (get-metric conductor :events-processed)
                               :events-failed (get-metric conductor :events-failed)
                               :timer-errors (get-metric conductor :timer-errors)
                               :tick-errors (get-metric conductor :tick-errors)
                               :task-retries (get-metric conductor :task-retries)
                               :pending-timers (length (conductor-timer-heap conductor))
                               :active-workers (length (conductor-active-workers)))))
        ;; Add crystallization metrics if available
        (when (find-package :autopoiesis.crystallize)
          (append base-status
                  (list :triggers-checked (get-metric conductor :triggers-checked)
                        :crystallizations-performed (get-metric conductor :crystallizations-performed)
                        :trigger-check-errors (get-metric conductor :trigger-check-errors))))
        base-status)
      (list :running nil)))
