;;;; provider-codex.lisp - OpenAI Codex CLI provider
;;;;
;;;; Wraps the `codex` CLI tool as an inference provider.
;;;; Parses JSONL (newline-delimited JSON) output.

(in-package #:autopoiesis.integration)

(define-cli-provider :codex
  (:command "codex")
  (:modes (:one-shot))
  (:documentation "Provider for the OpenAI Codex CLI tool.

Invokes `codex exec` with --json for JSONL output. Parses line-by-line
to extract text from message.completed events, tool calls from
function_call items, and turn counts from turn.completed events.")
  (:extra-slots
    (full-auto :initarg :full-auto
               :accessor codex-full-auto
               :initform t
               :documentation "Whether to run in full-auto mode (sandboxed)"))
  (:build-command (provider prompt)
    "Build codex CLI command."
    (let ((args (list "exec" prompt "--json")))
      (when (codex-full-auto provider)
        (push "--full-auto" args))
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :jsonl-events
    ;; response.completed — final response with output items
    ("response.completed"
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
    ("item.completed"
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
    ("function_call_arguments.done"
      (push (list :name (cdr (assoc :name json))
                  :input (cdr (assoc :arguments json)))
            tool-calls))
    ;; Turn completed
    ("turn.completed"
      (incf turns))
    ("turn.finished"
      (incf turns))))
