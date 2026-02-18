;;;; streaming.lisp - Streaming API for SKEL function calls
;;;; Provides streaming invocation of SKEL functions with real-time partial updates

(in-package #:autopoiesis.skel)

;;; ============================================================================
;;; Streaming Error Conditions
;;; ============================================================================

(define-condition skel-stream-error (skel-error)
  ((stream :initarg :stream :reader skel-stream-error-stream
           :documentation "The stream that encountered the error"))
  (:report (lambda (c s)
             (format s "SKEL streaming error: ~A" (skel-error-message c))))
  (:documentation "Base condition for streaming errors."))

(define-condition skel-stream-parse-error (skel-stream-error)
  ((accumulated :initarg :accumulated :reader skel-stream-accumulated-text
                :documentation "Text accumulated before the parse error"))
  (:report (lambda (c s)
             (format s "SKEL streaming parse error: ~A~%Accumulated text: ~S"
                     (skel-error-message c)
                     (subseq (skel-stream-accumulated-text c) 0
                             (min 200 (length (skel-stream-accumulated-text c)))))))
  (:documentation "Signaled when streaming parse fails."))

;;; ============================================================================
;;; SKEL Stream State Object
;;; ============================================================================

(defclass skel-stream ()
  ((status
    :initform :pending
    :accessor skel-stream-status
    :type (member :pending :streaming :complete :error :cancelled)
    :documentation "Current stream state.")
   (accumulated
    :initform ""
    :accessor skel-stream-accumulated
    :type string
    :documentation "Accumulated text from all stream chunks.")
   (partial-result
    :initform nil
    :accessor skel-stream-partial-result
    :documentation "Current partial object being built.")
   (final-result
    :initform nil
    :accessor skel-stream-final-result
    :documentation "Final parsed and validated result.")
   (error-value
    :initform nil
    :accessor skel-stream-error-value
    :documentation "Error object if status is :error.")
   (return-type
    :initarg :return-type
    :initform :string
    :reader skel-stream-return-type
    :documentation "Expected return type for parsing.")
   (function-name
    :initarg :function-name
    :initform nil
    :reader skel-stream-function-name
    :documentation "Name of the SKEL function being streamed.")
   (llm-stream
    :initform nil
    :accessor skel-stream-llm-stream
    :documentation "Underlying LLM stream object.")
   (lock
    :initform (bt:make-lock "skel-stream-lock")
    :reader skel-stream-lock
    :documentation "Lock for thread-safe access.")
   (condition-var
    :initform (bt:make-condition-variable :name "skel-stream-cv")
    :reader skel-stream-condition-var
    :documentation "Condition variable for waiting.")
   (on-partial-callback
    :initarg :on-partial
    :initform nil
    :accessor skel-stream-on-partial
    :documentation "Callback for partial updates.")
   (on-text-callback
    :initarg :on-text
    :initform nil
    :accessor skel-stream-on-text
    :documentation "Callback for raw text chunks.")
   (on-complete-callback
    :initarg :on-complete
    :initform nil
    :accessor skel-stream-on-complete
    :documentation "Callback when streaming completes.")
   (on-error-callback
    :initarg :on-error
    :initform nil
    :accessor skel-stream-on-error
    :documentation "Callback on error."))
  (:documentation "Represents an in-progress streaming SKEL function call."))

(defun make-skel-stream (&key return-type function-name
                              on-partial on-text on-complete on-error)
  "Create a new SKEL stream object."
  (make-instance 'skel-stream
                 :return-type return-type
                 :function-name function-name
                 :on-partial on-partial
                 :on-text on-text
                 :on-complete on-complete
                 :on-error on-error))

(defmethod print-object ((stream skel-stream) out)
  (print-unreadable-object (stream out :type t :identity t)
    (format out "~A ~A ~D chars"
            (skel-stream-function-name stream)
            (skel-stream-status stream)
            (length (skel-stream-accumulated stream)))))

;;; ============================================================================
;;; Stream Control Functions
;;; ============================================================================

(defun skel-stream-cancel (stream)
  "Cancel an in-progress SKEL stream."
  (bt:with-lock-held ((skel-stream-lock stream))
    (when (member (skel-stream-status stream) '(:pending :streaming))
      (when (skel-stream-llm-stream stream)
        (skel-stream-cancel-llm (skel-stream-llm-stream stream)))
      (setf (skel-stream-status stream) :cancelled)
      (bt:condition-notify (skel-stream-condition-var stream))
      t)))

(defun skel-stream-wait (stream &key (timeout 60))
  "Wait for SKEL stream to complete, returning the final result."
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (bt:with-lock-held ((skel-stream-lock stream))
      (loop while (member (skel-stream-status stream) '(:pending :streaming))
            do (let ((remaining (/ (- deadline (get-internal-real-time))
                                   internal-time-units-per-second)))
                 (when (<= remaining 0)
                   (error 'skel-stream-error
                          :message (format nil "Stream timed out after ~A seconds" timeout)
                          :stream stream))
                 (bt:condition-wait (skel-stream-condition-var stream)
                                    (skel-stream-lock stream)
                                    :timeout remaining)))))
  (case (skel-stream-status stream)
    (:complete (skel-stream-final-result stream))
    (:error (error (skel-stream-error-value stream)))
    (:cancelled (error 'skel-stream-error
                       :message "Stream was cancelled"
                       :stream stream))))

;;; ============================================================================
;;; Incremental JSON Parser for Streaming
;;; ============================================================================

(defstruct incremental-parser
  "State for incremental JSON parsing."
  (brace-depth 0 :type integer)
  (bracket-depth 0 :type integer)
  (in-string nil :type boolean)
  (escape-next nil :type boolean)
  (buffer "" :type string)
  (complete-p nil :type boolean))

(defun parser-balanced-p (parser)
  "Return T if the parser has seen balanced braces/brackets at depth 0."
  (and (zerop (incremental-parser-brace-depth parser))
       (zerop (incremental-parser-bracket-depth parser))
       (> (length (incremental-parser-buffer parser)) 0)
       (incremental-parser-complete-p parser)))

(defun parser-feed (parser text)
  "Feed TEXT to the incremental parser, tracking JSON structure."
  (setf (incremental-parser-buffer parser)
        (concatenate 'string (incremental-parser-buffer parser) text))
  (loop for char across text do
    (cond
      ((incremental-parser-escape-next parser)
       (setf (incremental-parser-escape-next parser) nil))
      ((and (incremental-parser-in-string parser)
            (char= char #\\))
       (setf (incremental-parser-escape-next parser) t))
      ((char= char #\")
       (setf (incremental-parser-in-string parser)
             (not (incremental-parser-in-string parser))))
      ((not (incremental-parser-in-string parser))
       (case char
         (#\{ (incf (incremental-parser-brace-depth parser)))
         (#\} (decf (incremental-parser-brace-depth parser))
              (when (zerop (incremental-parser-brace-depth parser))
                (setf (incremental-parser-complete-p parser) t)))
         (#\[ (incf (incremental-parser-bracket-depth parser)))
         (#\] (decf (incremental-parser-bracket-depth parser))
              (when (and (zerop (incremental-parser-bracket-depth parser))
                         (zerop (incremental-parser-brace-depth parser)))
                (setf (incremental-parser-complete-p parser) t)))))))
  (parser-balanced-p parser))

(defun parser-try-extract-partial (parser return-type)
  "Attempt to extract partial data from the current buffer."
  (let ((buffer (incremental-parser-buffer parser)))
    (when (zerop (length buffer))
      (return-from parser-try-extract-partial nil))
    (handler-case
        (let* ((preprocessed (handler-case
                                 (sap-preprocess buffer)
                               (error () buffer)))
               (fixable (fix-incomplete-json preprocessed)))
          (when fixable
            (handler-case
                (let ((parsed (cl-json:decode-json-from-string fixable)))
                  (if (and (symbolp return-type)
                           (get-skel-class return-type))
                      (let ((extracted (handler-case
                                           (sap-extract-with-schema
                                            parsed return-type
                                            :strict nil
                                            :validate-required nil)
                                         (error () nil))))
                        (when extracted
                          (values extracted
                                  (loop for (key val) on extracted by #'cddr
                                        when val collect key))))
                      (values parsed (list :value))))
              (error () nil))))
      (error () nil))))

(defun fix-incomplete-json (text)
  "Attempt to fix incomplete JSON by closing open structures."
  (when (zerop (length text))
    (return-from fix-incomplete-json nil))
  (let ((brace-depth 0)
        (bracket-depth 0)
        (in-string nil)
        (escape-next nil)
        (last-meaningful-pos 0))
    (loop for i from 0 below (length text)
          for char = (char text i) do
            (cond
              (escape-next
               (setf escape-next nil))
              ((and in-string (char= char #\\))
               (setf escape-next t))
              ((char= char #\")
               (setf in-string (not in-string))
               (setf last-meaningful-pos i))
              ((not in-string)
               (case char
                 (#\{ (incf brace-depth) (setf last-meaningful-pos i))
                 (#\} (decf brace-depth) (setf last-meaningful-pos i))
                 (#\[ (incf bracket-depth) (setf last-meaningful-pos i))
                 (#\] (decf bracket-depth) (setf last-meaningful-pos i))
                 ((#\: #\,) (setf last-meaningful-pos i))
                 (t (unless (member char '(#\Space #\Tab #\Newline #\Return))
                      (setf last-meaningful-pos i)))))))
    (let ((result (if in-string
                      (concatenate 'string text "\"")
                      text)))
      (when (> bracket-depth 0)
        (setf result (concatenate 'string result
                                  (make-string bracket-depth :initial-element #\]))))
      (when (> brace-depth 0)
        (setf result (concatenate 'string result
                                  (make-string brace-depth :initial-element #\}))))
      result)))

;;; ============================================================================
;;; Streaming Chunk Handler
;;; ============================================================================

(defun handle-stream-chunk (skel-stream parser text-delta)
  "Process a text chunk from the LLM stream."
  (bt:with-lock-held ((skel-stream-lock skel-stream))
    (setf (skel-stream-accumulated skel-stream)
          (concatenate 'string
                       (skel-stream-accumulated skel-stream)
                       text-delta))
    (when (eq (skel-stream-status skel-stream) :pending)
      (setf (skel-stream-status skel-stream) :streaming)))

  (when (skel-stream-on-text skel-stream)
    (funcall (skel-stream-on-text skel-stream) text-delta))

  (parser-feed parser text-delta)

  (let ((return-type (skel-stream-return-type skel-stream)))
    (when (and (symbolp return-type)
               (get-skel-class return-type))
      (multiple-value-bind (partial-plist fields-found)
          (parser-try-extract-partial parser return-type)
        (when partial-plist
          (let ((partial-obj (skel-stream-partial-result skel-stream)))
            (unless partial-obj
              (setf partial-obj (make-partial-instance return-type))
              (setf (skel-stream-partial-result skel-stream) partial-obj))
            (loop for (key val) on partial-plist by #'cddr
                  for slot-name = (intern (symbol-name key) (symbol-package return-type))
                  when val do
                    (handler-case
                        (update-partial-field partial-obj slot-name val)
                      (error ())))
            (when (skel-stream-on-partial skel-stream)
              (let ((coverage (partial-coverage partial-obj)))
                (funcall (skel-stream-on-partial skel-stream)
                         partial-obj coverage)))))))))

(defun handle-stream-complete (skel-stream parser llm-response)
  "Handle stream completion."
  (declare (ignore llm-response))
  (let ((accumulated (skel-stream-accumulated skel-stream))
        (return-type (skel-stream-return-type skel-stream)))
    (handler-case
        (let ((final-result (parse-llm-response accumulated return-type)))
          (bt:with-lock-held ((skel-stream-lock skel-stream))
            (setf (skel-stream-final-result skel-stream) final-result)
            (setf (skel-stream-status skel-stream) :complete)
            (when (skel-stream-partial-result skel-stream)
              (mark-partial-complete (skel-stream-partial-result skel-stream)))
            (bt:condition-notify (skel-stream-condition-var skel-stream)))
          (when (skel-stream-on-complete skel-stream)
            (funcall (skel-stream-on-complete skel-stream) final-result)))
      (error (e)
        (handle-stream-error skel-stream e)))))

(defun handle-stream-error (skel-stream error)
  "Handle a streaming error."
  (let ((err (if (typep error 'skel-stream-error)
                 error
                 (make-condition 'skel-stream-error
                                 :message (princ-to-string error)
                                 :stream skel-stream))))
    (bt:with-lock-held ((skel-stream-lock skel-stream))
      (setf (skel-stream-error-value skel-stream) err)
      (setf (skel-stream-status skel-stream) :error)
      (bt:condition-notify (skel-stream-condition-var skel-stream)))
    (when (skel-stream-on-error skel-stream)
      (funcall (skel-stream-on-error skel-stream) err))))

;;; ============================================================================
;;; Main Streaming API
;;; ============================================================================

(defun skel-stream (name &rest args
                    &key client config
                         on-partial on-text on-complete on-error
                    &allow-other-keys)
  "Stream a SKEL function call with real-time updates."
  (let ((func-args (remove-from-plist
                    args :client :config
                    :on-partial :on-text :on-complete :on-error)))
    (let ((func (get-skel-function name)))
      (unless func
        (error 'skel-error
               :message (format nil "Unknown SKEL function: ~A" name)))

      (let ((validated-args (validate-skel-arguments func func-args)))
        (let ((llm-client (ensure-llm-client client)))
          (let* ((func-config (or (skel-function-config func) *default-skel-config*))
                 (merged-config (if config
                                    (merge-configs func-config config)
                                    func-config))
                 (configured-client (apply-config-to-client llm-client merged-config))
                 (prompt (build-skel-prompt func validated-args))
                 (system-prompt (config-system-prompt merged-config))
                 (return-type (skel-function-return-type func))
                 (skel-stream (make-skel-stream
                               :return-type return-type
                               :function-name name
                               :on-partial on-partial
                               :on-text on-text
                               :on-complete on-complete
                               :on-error on-error))
                 (parser (make-incremental-parser)))

            (when (and (symbolp return-type) (get-skel-class return-type))
              (ensure-partial-class return-type))

            (let ((llm-stream
                    (skel-stream-message
                     configured-client
                     prompt
                     :system system-prompt
                     :on-chunk (lambda (text-delta)
                                 (handle-stream-chunk skel-stream parser text-delta))
                     :on-complete (lambda (response)
                                    (handle-stream-complete skel-stream parser response))
                     :on-error (lambda (err)
                                 (handle-stream-error skel-stream err)))))
              (setf (skel-stream-llm-stream skel-stream) llm-stream)
              skel-stream)))))))

;;; ============================================================================
;;; Convenience Wrappers
;;; ============================================================================

(defun stream-skel-call (name &rest args)
  "Convenience wrapper for skel-stream."
  (apply #'skel-stream name args))

(defun skel-stream-collect (name &rest args &key (timeout 60) &allow-other-keys)
  "Stream a SKEL function and collect all partial updates."
  (let ((partial-history '())
        (args-without-timeout (remove-from-plist args :timeout)))
    (let ((stream (apply #'skel-stream name
                         :on-partial (lambda (partial coverage)
                                       (push (cons partial coverage) partial-history))
                         args-without-timeout)))
      (values (skel-stream-wait stream :timeout timeout)
              (nreverse partial-history)))))

;;; ============================================================================
;;; Stream Status Utilities
;;; ============================================================================

(defun skel-stream-pending-p (stream)
  "Return T if the stream hasn't started yet."
  (eq (skel-stream-status stream) :pending))

(defun skel-stream-streaming-p (stream)
  "Return T if the stream is actively receiving data."
  (eq (skel-stream-status stream) :streaming))

(defun skel-stream-complete-p (stream)
  "Return T if the stream has completed successfully."
  (eq (skel-stream-status stream) :complete))

(defun skel-stream-error-p (stream)
  "Return T if the stream encountered an error."
  (eq (skel-stream-status stream) :error))

(defun skel-stream-cancelled-p (stream)
  "Return T if the stream was cancelled."
  (eq (skel-stream-status stream) :cancelled))

(defun skel-stream-done-p (stream)
  "Return T if the stream is in a terminal state."
  (member (skel-stream-status stream) '(:complete :error :cancelled)))

(defun skel-stream-coverage (stream)
  "Return the current coverage (0.0-1.0) of the partial result."
  (let ((partial (skel-stream-partial-result stream)))
    (if partial
        (partial-coverage partial)
        0.0)))
