;;;; message-format.lisp - Message formatting for Claude
;;;;
;;;; Convert between internal representation and Claude API format.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Formatting
;;; ═══════════════════════════════════════════════════════════════════

(defun format-message (role content &key name)
  "Format a message for Claude API."
  (let ((msg `(("role" . ,role)
               ("content" . ,content))))
    (when name
      (push (cons "name" name) msg))
    msg))

(defun format-user-message (content)
  "Format a user message."
  (format-message "user" content))

(defun format-assistant-message (content)
  "Format an assistant message."
  (format-message "assistant" content))

(defun format-tool-result (tool-use-id result &key is-error)
  "Format a tool result message."
  `(("role" . "user")
    ("content" . ((("type" . "tool_result")
                   ("tool_use_id" . ,tool-use-id)
                   ("content" . ,result)
                   ,@(when is-error '(("is_error" . t))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Response Parsing
;;; ═══════════════════════════════════════════════════════════════════

(defun parse-response (response)
  "Parse a Claude API response."
  (let ((content (cdr (assoc "content" response :test #'string=))))
    (when content
      (parse-content-blocks content))))

(defun parse-content-blocks (blocks)
  "Parse content blocks from response."
  (loop for block in blocks
        collect (parse-content-block block)))

(defun parse-content-block (block)
  "Parse a single content block."
  (let ((type (cdr (assoc "type" block :test #'string=))))
    (cond
      ((string= type "text")
       `(:text ,(cdr (assoc "text" block :test #'string=))))
      ((string= type "tool_use")
       `(:tool-use
         :id ,(cdr (assoc "id" block :test #'string=))
         :name ,(cdr (assoc "name" block :test #'string=))
         :input ,(cdr (assoc "input" block :test #'string=))))
      (t `(:unknown ,block)))))

(defun extract-tool-calls (response)
  "Extract tool calls from a parsed response."
  (remove-if-not (lambda (block)
                   (and (consp block) (eq (car block) :tool-use)))
                 (parse-response response)))
