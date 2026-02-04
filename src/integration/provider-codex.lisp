;;;; provider-codex.lisp - OpenAI Codex CLI provider
;;;;
;;;; Wraps the `codex` CLI tool as an inference provider.
;;;; Parses JSONL (newline-delimited JSON) output.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Codex Provider Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass codex-provider (provider)
  ((full-auto :initarg :full-auto
              :accessor codex-full-auto
              :initform t
              :documentation "Whether to run in full-auto mode (sandboxed)"))
  (:default-initargs :name "codex" :command "codex")
  (:documentation "Provider for the OpenAI Codex CLI tool.

Invokes `codex exec` with --json for JSONL output. Parses line-by-line
to extract text from message.completed events, tool calls from
function_call items, and turn counts from turn.completed events."))

(defun make-codex-provider (&key (name "codex") (command "codex")
                              working-directory default-model
                              (max-turns 10) (timeout 300)
                              env extra-args (full-auto t))
  "Create a Codex provider instance."
  (make-instance 'codex-provider
                 :name name
                 :command command
                 :working-directory working-directory
                 :default-model default-model
                 :max-turns max-turns
                 :timeout timeout
                 :env env
                 :extra-args extra-args
                 :full-auto full-auto))

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-supported-modes ((provider codex-provider))
  '(:one-shot))

(defmethod provider-build-command ((provider codex-provider) prompt &key tools)
  "Build codex CLI command."
  (declare (ignore tools))
  (let ((args (list "exec" prompt "--json")))
    (when (codex-full-auto provider)
      (push "--full-auto" args))
    (when (provider-extra-args provider)
      (setf args (append args (provider-extra-args provider))))
    (values (provider-command provider) args)))

(defmethod provider-parse-output ((provider codex-provider) raw-output)
  "Parse Codex JSONL output.

   Codex outputs newline-delimited JSON events following the OpenAI
   Responses API streaming format. We extract:
   - Text from response.completed or message.completed content
   - Tool calls from function_call_arguments.done events
   - Turn count from turn.completed events
   - Also handles item.completed with nested content"
  (let ((text-parts nil)
        (tool-calls nil)
        (turns 0))
    (handler-case
        (with-input-from-string (s raw-output)
          (loop for line = (read-line s nil nil)
                while line
                when (and (> (length line) 0)
                          (char= (char line 0) #\{))
                  do (handler-case
                         (let* ((json (cl-json:decode-json-from-string line))
                                (event-type (or (cdr (assoc :type json)) "")))
                           (cond
                             ;; response.completed — final response with output items
                             ((string= event-type "response.completed")
                              (let ((response (cdr (assoc :response json))))
                                (when response
                                  (let ((output (cdr (assoc :output response))))
                                    (when (listp output)
                                      (dolist (item output)
                                        (let ((item-type (cdr (assoc :type item))))
                                          (cond
                                            ((string= item-type "message")
                                             (let ((content (cdr (assoc :content item))))
                                               (when (listp content)
                                                 (dolist (part content)
                                                   (let ((text (cdr (assoc :text part))))
                                                     (when text (push text text-parts)))))))
                                            ((string= item-type "function_call")
                                             (push (list :name (cdr (assoc :name item))
                                                         :input (cdr (assoc :arguments item)))
                                                   tool-calls))))))))))
                             ;; item.completed — individual completed item
                             ((string= event-type "item.completed")
                              (let* ((item (cdr (assoc :item json)))
                                     (item-type (cdr (assoc :type item))))
                                (cond
                                  ((string= item-type "message")
                                   (let ((content (cdr (assoc :content item))))
                                     (when (listp content)
                                       (dolist (part content)
                                         (let ((text (cdr (assoc :text part))))
                                           (when text (push text text-parts)))))))
                                  ((string= item-type "function_call")
                                   (push (list :name (cdr (assoc :name item))
                                               :input (cdr (assoc :arguments item)))
                                         tool-calls)))))
                             ;; function_call_arguments.done
                             ((string= event-type "function_call_arguments.done")
                              (push (list :name (cdr (assoc :name json))
                                          :input (cdr (assoc :arguments json)))
                                    tool-calls))
                             ;; Turn completed
                             ((or (string= event-type "turn.completed")
                                  (string= event-type "turn.finished"))
                              (incf turns))))
                       (error () nil))))
      (error (e)
        (declare (ignore e))))
    (make-provider-result
     :text (format nil "~{~a~}" (nreverse text-parts))
     :tool-calls (nreverse tool-calls)
     :turns (if (> turns 0) turns nil))))

(defmethod provider-to-sexpr ((provider codex-provider))
  "Serialize Codex provider configuration."
  (let ((base (call-next-method)))
    (append base
            (list :full-auto (codex-full-auto provider)))))
