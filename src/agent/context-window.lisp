;;;; context-window.lisp - Agent working memory / context window
;;;;
;;;; The context window represents the agent's current working memory,
;;;; managing what information is available for reasoning. Items are
;;;; stored with priorities and the window respects a maximum size.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Priority Queue Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defstruct (priority-queue (:constructor %make-priority-queue))
  "A simple priority queue using a sorted list.
   Items are stored as (priority . item) pairs, highest priority first."
  (items nil :type list))

(defun make-priority-queue ()
  "Create an empty priority queue."
  (%make-priority-queue))

(defun pqueue-push (pqueue item priority)
  "Add ITEM to PQUEUE with PRIORITY. Higher priority = earlier in queue."
  (let ((entry (cons priority item)))
    (setf (priority-queue-items pqueue)
          (merge 'list (list entry) (priority-queue-items pqueue)
                 #'> :key #'car)))
  pqueue)

(defun pqueue-pop (pqueue)
  "Remove and return the highest priority item from PQUEUE.
   Returns (values item priority) or (values nil nil) if empty."
  (if (priority-queue-items pqueue)
      (let ((entry (pop (priority-queue-items pqueue))))
        (values (cdr entry) (car entry)))
      (values nil nil)))

(defun pqueue-peek (pqueue)
  "Return the highest priority item without removing it.
   Returns (values item priority) or (values nil nil) if empty."
  (if (priority-queue-items pqueue)
      (let ((entry (first (priority-queue-items pqueue))))
        (values (cdr entry) (car entry)))
      (values nil nil)))

(defun pqueue-remove (pqueue item &key (test #'eql))
  "Remove ITEM from PQUEUE if present."
  (setf (priority-queue-items pqueue)
        (remove item (priority-queue-items pqueue)
                :key #'cdr :test test))
  pqueue)

(defun pqueue-empty-p (pqueue)
  "Return T if PQUEUE is empty."
  (null (priority-queue-items pqueue)))

(defun pqueue-size (pqueue)
  "Return the number of items in PQUEUE."
  (length (priority-queue-items pqueue)))

(defun pqueue-map (pqueue fn)
  "Apply FN to each (item priority) pair, updating priorities with returned value.
   FN receives (item priority) and should return a new priority."
  (setf (priority-queue-items pqueue)
        (sort (mapcar (lambda (entry)
                        (cons (funcall fn (cdr entry) (car entry))
                              (cdr entry)))
                      (priority-queue-items pqueue))
              #'> :key #'car))
  pqueue)

(defun pqueue-do (pqueue fn)
  "Call FN with (item priority) for each item in PQUEUE, highest priority first."
  (dolist (entry (priority-queue-items pqueue))
    (funcall fn (cdr entry) (car entry))))

(defun pqueue-items (pqueue)
  "Return list of items in PQUEUE in priority order (highest first)."
  (mapcar #'cdr (priority-queue-items pqueue)))

(defun pqueue-clear (pqueue)
  "Remove all items from PQUEUE."
  (setf (priority-queue-items pqueue) nil)
  pqueue)

;;; ═══════════════════════════════════════════════════════════════════
;;; Context Window Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass context-window ()
  ((content :initarg :content
            :accessor context-content
            :initform nil
            :documentation "Current context as list of items (computed from queue)")
   (max-size :initarg :max-size
             :accessor context-max-size
             :initform 100000
             :documentation "Maximum context size in tokens")
   (priority-queue :initarg :priority-queue
                   :accessor context-priority-queue
                   :initform (make-priority-queue)
                   :documentation "Items ranked by relevance/priority"))
  (:documentation "The agent's working memory / context window.
   Manages what information is currently available for reasoning,
   respecting size limits and item priorities."))

(defun make-context-window (&key (max-size 100000))
  "Create a new context window with MAX-SIZE token limit."
  (make-instance 'context-window :max-size max-size))

;;; ═══════════════════════════════════════════════════════════════════
;;; Context Window Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun context-add (context item &key (priority 1.0))
  "Add ITEM to CONTEXT with PRIORITY.
   Higher priority items are more likely to be retained when size limit is hit.
   Automatically recomputes the content based on the new queue state."
  (pqueue-push (context-priority-queue context) item priority)
  (recompute-context-content context)
  context)

(defun context-remove (context item &key (test #'eql))
  "Remove ITEM from CONTEXT.
   Uses TEST to compare items (default EQL)."
  (pqueue-remove (context-priority-queue context) item :test test)
  (recompute-context-content context)
  context)

(defun context-focus (context predicate &key (boost 2.0))
  "Boost priority of items matching PREDICATE by BOOST factor.
   PREDICATE receives each item and returns T if it should be boosted."
  (pqueue-map (context-priority-queue context)
              (lambda (item priority)
                (if (funcall predicate item)
                    (* priority boost)
                    priority)))
  (recompute-context-content context)
  context)

(defun context-defocus (context predicate &key (factor 0.5))
  "Reduce priority of items matching PREDICATE by FACTOR.
   PREDICATE receives each item and returns T if it should be de-prioritized."
  (pqueue-map (context-priority-queue context)
              (lambda (item priority)
                (if (funcall predicate item)
                    (* priority factor)
                    priority)))
  (recompute-context-content context)
  context)

(defun recompute-context-content (context)
  "Rebuild context content from priority queue, respecting max-size.
   Items are included in priority order until the size limit is reached."
  (let ((items nil)
        (size 0)
        (max-size (context-max-size context)))
    (pqueue-do (context-priority-queue context)
      (lambda (item priority)
        (declare (ignore priority))
        (let ((item-size (autopoiesis.core:sexpr-size item)))
          (when (< (+ size item-size) max-size)
            (push item items)
            (incf size item-size)))))
    (setf (context-content context) (nreverse items))))

(defun context-size (context)
  "Return the current estimated size of the context in tokens."
  (loop for item in (context-content context)
        sum (autopoiesis.core:sexpr-size item)))

(defun context-item-count (context)
  "Return the number of items currently in the context content."
  (length (context-content context)))

(defun context-total-items (context)
  "Return the total number of items in the priority queue."
  (pqueue-size (context-priority-queue context)))

(defun context-clear (context)
  "Remove all items from the context."
  (pqueue-clear (context-priority-queue context))
  (setf (context-content context) nil)
  context)

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun context-to-sexpr (context)
  "Serialize CONTEXT to an S-expression for persistence."
  `(:context-window
    :max-size ,(context-max-size context)
    :items ,(mapcar (lambda (entry)
                      `(:priority ,(car entry) :item ,(cdr entry)))
                    (priority-queue-items (context-priority-queue context)))))

(defun sexpr-to-context (sexpr)
  "Reconstruct a context window from SEXPR."
  (destructuring-bind (&key max-size items) (rest sexpr)
    (let ((context (make-context-window :max-size (or max-size 100000))))
      (dolist (entry (reverse items))  ; Reverse to maintain priority order
        (destructuring-bind (&key priority item) entry
          (context-add context item :priority priority)))
      context)))
