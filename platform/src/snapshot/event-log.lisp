;;;; event-log.lisp - Append-only event log
;;;;
;;;; Events are the primary persistence mechanism.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass event ()
  ((id :initarg :id
       :accessor event-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique event ID")
   (type :initarg :type
         :accessor event-type
         :documentation "Event type keyword")
   (timestamp :initarg :timestamp
              :accessor event-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When event occurred")
   (data :initarg :data
         :accessor event-data
         :initform nil
         :documentation "Event payload"))
  (:documentation "An event in the append-only log"))

(defun make-event (type data)
  "Create a new event."
  (make-instance 'event :type type :data data))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Log
;;; ═══════════════════════════════════════════════════════════════════

(defvar *event-log* (make-array 0 :adjustable t :fill-pointer 0)
  "The append-only event log.")

(defun append-event (event &key (log *event-log*))
  "Append EVENT to the log."
  (vector-push-extend event log)
  event)

(defun replay-events (handler &key (log *event-log*) from-index)
  "Replay events through HANDLER function.
   HANDLER receives each event."
  (loop for i from (or from-index 0) below (length log)
        do (funcall handler (aref log i))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Checkpoint Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass checkpoint ()
  ((id :initarg :id
       :accessor checkpoint-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique checkpoint ID")
   (timestamp :initarg :timestamp
              :accessor checkpoint-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When checkpoint was created")
   (state :initarg :state
          :accessor checkpoint-state
          :documentation "The full state at checkpoint time")
   (event-count :initarg :event-count
                :accessor checkpoint-event-count
                :initform 0
                :documentation "Number of events compacted into this checkpoint"))
  (:documentation "A checkpoint representing compacted state"))

(defun make-checkpoint (state &key event-count)
  "Create a new checkpoint with given STATE."
  (make-instance 'checkpoint
                 :state state
                 :event-count (or event-count 0)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Compaction
;;; ═══════════════════════════════════════════════════════════════════

(defun compact-events (log checkpoint-fn &key keep-recent)
  "Compact LOG by creating a checkpoint.
   CHECKPOINT-FN is called with no arguments and should return the current state.
   Returns the checkpoint created.
   If KEEP-RECENT is provided, that many recent events are preserved."
  (when (zerop (length log))
    (return-from compact-events nil))
  (let* ((current-state (funcall checkpoint-fn))
         (total-events (length log))
         (events-to-compact (if keep-recent
                                (max 0 (- total-events keep-recent))
                                total-events))
         (checkpoint (make-checkpoint current-state
                                       :event-count events-to-compact)))
    ;; If keeping some recent events, shift them to front of log
    (when (and keep-recent (> keep-recent 0) (< keep-recent total-events))
      (let ((keep-start (- total-events keep-recent)))
        ;; Move recent events to the beginning
        (loop for i from 0 below keep-recent
              do (setf (aref log i) (aref log (+ keep-start i))))
        ;; Adjust fill pointer
        (setf (fill-pointer log) keep-recent)))
    ;; If not keeping any events, clear the log
    (when (or (null keep-recent) (zerop keep-recent) (>= keep-recent total-events))
      (unless (and keep-recent (>= keep-recent total-events))
        (setf (fill-pointer log) 0)))
    checkpoint))

(defun event-log-count (&key (log *event-log*))
  "Return the number of events in LOG."
  (length log))

(defun clear-event-log (&key (log *event-log*))
  "Clear all events from LOG."
  (setf (fill-pointer log) 0))
