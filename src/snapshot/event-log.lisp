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

(defun compact-events (log checkpoint-fn)
  "Compact LOG by creating a checkpoint.
   CHECKPOINT-FN is called with current state to create checkpoint."
  ;; Placeholder - compaction creates a checkpoint snapshot
  ;; and removes old events
  (declare (ignore log checkpoint-fn))
  (error 'autopoiesis.core:autopoiesis-error
         :message "Event compaction not yet implemented"))
