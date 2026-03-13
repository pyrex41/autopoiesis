;;;; dispatch.lisp - Tool call parsing and dispatch
;;;;
;;;; Parses tool calls from Pi's JSON responses and dispatches them
;;;; through the capability system, optionally wrapping in supervisor
;;;; checkpoints.

(in-package #:autopoiesis.jarvis)

;;; ===================================================================
;;; Tool Call Parsing
;;; ===================================================================

(defun parse-tool-call (json-response)
  "Parse a tool call from Pi's JSON response.

   Expects an alist with a :TOOL--USE key containing :NAME and :ARGUMENTS.
   Returns (values tool-name arguments) or NIL if no tool call present."
  (when (and json-response (listp json-response))
    (let ((tool-use (cdr (assoc :tool--use json-response))))
      (when tool-use
        (values (cdr (assoc :name tool-use))
                (cdr (assoc :arguments tool-use)))))))

;;; ===================================================================
;;; Tool Invocation
;;; ===================================================================

(defun invoke-tool (capability arguments)
  "Invoke a capability with parsed arguments.

   CAPABILITY - a capability object from the registry
   ARGUMENTS - an alist of (key . value) pairs from JSON

   Returns the result of calling the capability function, or an error string."
  (handler-case
      (let ((args (when arguments
                    (loop for (k . v) in arguments
                          collect (intern (string-upcase (string k)) :keyword)
                          collect v))))
        (apply (autopoiesis.agent:capability-function capability) args))
    (error (e)
      (format nil "Error: ~a" e))))

;;; ===================================================================
;;; Dispatch with Supervisor Integration
;;; ===================================================================

(defun dispatch-tool-call (session tool-name arguments)
  "Dispatch a tool call through the capability system.

   Looks up the capability by converting TOOL-NAME from snake_case to
   :KEBAB-CASE keyword. If the supervisor is enabled and available,
   wraps the invocation in a checkpoint.

   Returns the tool result as a string, or an error message."
  (let* ((cap-name (autopoiesis.integration:tool-name-to-lisp-name tool-name))
         (capability (autopoiesis.agent:find-capability cap-name)))
    (unless capability
      (return-from dispatch-tool-call
        (format nil "Error: Unknown tool ~a" tool-name)))
    (let ((agent (jarvis-agent session)))
      (if (and (jarvis-supervisor-enabled-p session)
               (find-package :autopoiesis.supervisor)
               (let ((sym (find-symbol "CHECKPOINT-AGENT" :autopoiesis.supervisor)))
                 (and sym (fboundp sym))))
          ;; Wrap in checkpoint via funcall to avoid compile-time dependency
          (let ((checkpoint-fn (find-symbol "CHECKPOINT-AGENT"
                                            :autopoiesis.supervisor))
                (promote-fn (find-symbol "PROMOTE-CHECKPOINT"
                                         :autopoiesis.supervisor))
                (revert-fn (find-symbol "REVERT-TO-STABLE"
                                        :autopoiesis.supervisor)))
            (handler-case
                (progn
                  ;; Manually implement checkpoint-and-revert pattern
                  (funcall checkpoint-fn agent
                           :operation (format nil "tool:~a" tool-name))
                  (let ((result (invoke-tool capability arguments)))
                    ;; If we got here without error, promote
                    (when promote-fn
                      (ignore-errors (funcall promote-fn)))
                    result))
              (error (e)
                ;; On error, revert and report
                (ignore-errors
                  (when revert-fn
                    (funcall revert-fn agent)))
                (format nil "Error in ~a: ~a" tool-name e))))
          ;; No supervisor - direct invocation with checkpoint context
          (let ((sup-pkg (find-package :autopoiesis.supervisor)))
            (if (and sup-pkg agent)
                (progn
                  (setf (symbol-value (find-symbol "*CURRENT-AGENT-FOR-CHECKPOINT*" sup-pkg))
                        agent)
                  (unwind-protect
                       (invoke-tool capability arguments)
                    (setf (symbol-value (find-symbol "*CURRENT-AGENT-FOR-CHECKPOINT*" sup-pkg))
                          nil)))
                (invoke-tool capability arguments))))))
