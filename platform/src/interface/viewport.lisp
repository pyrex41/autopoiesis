;;;; viewport.lisp - Focused view of agent state
;;;;
;;;; Controls what part of agent state is visible.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Viewport Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass viewport ()
  ((focus :initarg :focus
          :accessor viewport-focus
          :initform nil
          :documentation "Path into the state tree")
   (filter :initarg :filter
           :accessor viewport-filter
           :initform nil
           :documentation "Filter predicate")
   (detail-level :initarg :detail-level
                 :accessor viewport-detail-level
                 :initform :summary
                 :documentation ":summary :normal :detailed")
   (has-focus :initarg :has-focus
              :accessor viewport-has-focus
              :initform nil
              :documentation "Whether this viewport currently has input focus"))
  (:documentation "A focused view into agent state"))

(defun make-viewport (&key focus filter detail-level has-focus)
  "Create a new viewport."
  (make-instance 'viewport
                 :focus focus
                 :filter filter
                 :detail-level (or detail-level :summary)
                 :has-focus has-focus))

;;; ═══════════════════════════════════════════════════════════════════
;;; Viewport Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun set-focus (viewport path)
  "Set the focus path into state."
  (setf (viewport-focus viewport) path))

(defun apply-filter (viewport predicate)
  "Apply a filter predicate."
  (setf (viewport-filter viewport) predicate))

(defun expand-detail (viewport)
  "Increase detail level."
  (setf (viewport-detail-level viewport)
        (case (viewport-detail-level viewport)
          (:summary :normal)
          (:normal :detailed)
          (:detailed :detailed))))

(defun collapse-detail (viewport)
  "Decrease detail level."
  (setf (viewport-detail-level viewport)
        (case (viewport-detail-level viewport)
          (:detailed :normal)
          (:normal :summary)
          (:summary :summary))))

(defun viewport-render (viewport state)
  "Render STATE through the viewport."
  (let ((focused (if (viewport-focus viewport)
                     (follow-path state (viewport-focus viewport))
                     state)))
    (if (viewport-filter viewport)
        (filter-state focused (viewport-filter viewport))
        focused)))

(defun follow-path (state path)
  "Follow PATH into STATE."
  (reduce (lambda (s key)
            (cond
              ((and (listp s) (numberp key)) (nth key s))
              ((and (listp s) (symbolp key)) (getf s key))
              (t s)))
          path
          :initial-value state))

(defun filter-state (state predicate)
  "Filter STATE with PREDICATE."
  (typecase state
    (list (remove-if-not predicate state))
    (t state)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Focus Management
;;; ═══════════════════════════════════════════════════════════════════

(defmethod focus-viewport ((viewport viewport))
  "Give focus to this viewport."
  (setf (viewport-has-focus viewport) t)
  viewport)

(defmethod unfocus-viewport ((viewport viewport))
  "Remove focus from this viewport."
  (setf (viewport-has-focus viewport) nil)
  viewport)

(defmethod viewport-focused-p ((viewport viewport))
  "Check if viewport currently has focus."
  (viewport-has-focus viewport))

;;; ═══════════════════════════════════════════════════════════════════
;;; Input Event Handling
;;; ═══════════════════════════════════════════════════════════════════

(defclass input-event ()
  ((type :initarg :type
         :accessor event-type
         :documentation "Event type: :key-press, :mouse-click, etc.")
   (data :initarg :data
         :accessor event-data
         :initform nil
         :documentation "Event-specific data"))
  (:documentation "Base class for input events"))

(defclass key-event (input-event)
  ((key :initarg :key
        :accessor event-key
        :documentation "The key that was pressed"))
  (:documentation "Keyboard key press event"))

(defclass mouse-event (input-event)
  ((button :initarg :button
           :accessor event-button
           :documentation "Mouse button (1=left, 2=middle, 3=right)")
   (x :initarg :x
      :accessor event-x
      :documentation "Mouse X coordinate")
   (y :initarg :y
      :accessor event-y
      :documentation "Mouse Y coordinate"))
  (:documentation "Mouse click event"))

(defgeneric handle-input-event (viewport event)
  (:documentation "Handle an input event for the viewport.")
  (:method ((viewport viewport) (event input-event))
    "Default event handler - does nothing."
    nil))

(defmethod handle-input-event ((viewport viewport) (event key-event))
  "Handle keyboard events for the viewport."
  (let ((key (event-key event)))
    (cond
      ((char= key #\r)
       ;; Reset viewport
       (set-focus viewport nil)
       (apply-filter viewport nil)
       (setf (viewport-detail-level viewport) :summary)
       t)
      ((or (char= key #\+) (char= key #\=))
       ;; Increase detail
       (expand-detail viewport)
       t)
      ((char= key #\-)
       ;; Decrease detail
       (collapse-detail viewport)
       t)
      (t nil))))

(defmethod handle-input-event ((viewport viewport) (event mouse-event))
  "Handle mouse events for the viewport."
  ;; For now, just acknowledge mouse clicks
  ;; Could be extended to handle specific viewport interactions
  t)

;;; ═══════════════════════════════════════════════════════════════════
;;; Raw Terminal Input Handling
;;; ═══════════════════════════════════════════════════════════════════

(defvar *input-thread* nil
  "Thread handling raw input when viewport has focus.")

(defvar *input-queue* (make-array 0 :adjustable t :fill-pointer 0)
  "Queue of pending input events.")

(defvar *input-queue-lock* (bordeaux-threads:make-lock "input-queue-lock")
  "Lock for synchronizing access to input queue.")

(defvar *input-queue-cv* (bordeaux-threads:make-condition-variable :name "input-queue-cv")
  "Condition variable for input queue.")

(defun parse-ansi-sequence (sequence)
  "Parse ANSI escape sequence into event.
   Returns nil if not a recognized sequence."
  (cond
    ;; Arrow keys: ESC [ A (up), ESC [ B (down), ESC [ C (right), ESC [ D (left)
    ((and (>= (length sequence) 3)
          (char= (char sequence 0) #\Escape)
          (char= (char sequence 1) #\[))
     (let ((final-char (char sequence 2)))
       (cond
         ((char= final-char #\A) (make-instance 'key-event :type :key-press :key :arrow-up))
         ((char= final-char #\B) (make-instance 'key-event :type :key-press :key :arrow-down))
         ((char= final-char #\C) (make-instance 'key-event :type :key-press :key :arrow-right))
         ((char= final-char #\D) (make-instance 'key-event :type :key-press :key :arrow-left)))))
    ;; Mouse events: ESC [ M <button> <x> <y>
    ((and (>= (length sequence) 6)
          (char= (char sequence 0) #\Escape)
          (char= (char sequence 1) #\[)
          (char= (char sequence 2) #\M))
     (let ((button (- (char-code (char sequence 3)) 32))
           (x (- (char-code (char sequence 4)) 32))
           (y (- (char-code (char sequence 5)) 32)))
       (make-instance 'mouse-event
                      :type :mouse-click
                      :button button
                      :x x
                      :y y)))
    (t nil)))

(defun read-raw-input ()
  "Read raw input from terminal, parsing escape sequences.
   Returns the next complete input event or character."
  (let ((char (read-char *standard-input* nil :eof)))
    (cond
      ((eq char :eof) :eof)
      ((char= char #\Escape)
       ;; Start of escape sequence - read more
       (let ((sequence (make-array 0 :adjustable t :fill-pointer 0
                                   :element-type 'character)))
         (vector-push-extend char sequence)
         ;; Read until we get a complete sequence or timeout
         (loop
           (let ((next-char (read-char-no-hang *standard-input* nil nil)))
             (cond
               ((null next-char)
                ;; No more chars available, return what we have
                (return (parse-ansi-sequence sequence)))
               ((and (char= next-char #\[)
                     (= (length sequence) 1))
                ;; Continue building sequence
                (vector-push-extend next-char sequence))
               ((and (>= (length sequence) 2)
                     (alpha-char-p next-char))
                ;; End of sequence
                (vector-push-extend next-char sequence)
                (return (parse-ansi-sequence sequence)))
               ((and (= (length sequence) 3)
                     (char= (char sequence 2) #\M))
                ;; Mouse event - need 3 more chars
                (vector-push-extend next-char sequence)
                (when (>= (length sequence) 6)
                  (return (parse-ansi-sequence sequence))))
               (t
                ;; Continue building
                (vector-push-extend next-char sequence)))))))
      (t
       ;; Regular character
       (make-instance 'key-event :type :key-press :key char)))))

(defun enqueue-input-event (event)
  "Add an input event to the queue."
  (bordeaux-threads:with-lock-held (*input-queue-lock*)
    (vector-push-extend event *input-queue*)
    (bordeaux-threads:condition-notify *input-queue-cv*)))

(defun dequeue-input-event (&key (timeout nil))
  "Remove and return the next input event from queue.
   Returns nil if timeout or no events."
  (bordeaux-threads:with-lock-held (*input-queue-lock*)
    (if (plusp (length *input-queue*))
        (vector-pop *input-queue*)
        (when timeout
          (bordeaux-threads:condition-wait *input-queue-cv* *input-queue-lock* :timeout timeout)
          (when (plusp (length *input-queue*))
            (vector-pop *input-queue*))))))

(defun start-input-listener (viewport)
  "Start listening for input events when viewport has focus."
  (when (and (viewport-has-focus viewport)
             (null *input-thread*))
    (setf *input-thread*
          (bordeaux-threads:make-thread
           (lambda ()
             (loop while (viewport-has-focus viewport) do
               (let ((event (read-raw-input)))
                 (when event
                   (enqueue-input-event event)))))
           :name "viewport-input-listener"))))

(defun stop-input-listener ()
  "Stop the input listener thread."
  (when *input-thread*
    (bordeaux-threads:destroy-thread *input-thread*)
    (setf *input-thread* nil)))

(defun process-pending-events (viewport)
  "Process all pending input events for the viewport."
  (loop
    (let ((event (dequeue-input-event :timeout 0.01)))
      (if event
          (handle-input-event viewport event)
          (return)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Listener Setup
;;; ═══════════════════════════════════════════════════════════════════

(defmethod setup-event-listeners ((viewport viewport))
  "Set up event listeners for the viewport.
   Enables raw mode and starts input processing."
  (when (viewport-has-focus viewport)
    ;; Enable mouse tracking in terminal (if supported)
    (format *standard-output* "~c[?1000h" #\Escape)  ; Enable mouse tracking
    (force-output *standard-output*)
    (start-input-listener viewport)))

(defmethod teardown-event-listeners ((viewport viewport))
  "Tear down event listeners for the viewport.
   Disables raw mode and stops input processing."
  ;; Disable mouse tracking
  (format *standard-output* "~c[?1000l" #\Escape)  ; Disable mouse tracking
  (force-output *standard-output*)
  (stop-input-listener))
