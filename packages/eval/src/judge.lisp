;;;; judge.lisp - LLM-as-judge evaluation via SKEL typed functions
;;;;
;;;; Uses SKEL's define-skel-class and define-skel-function to create
;;;; a structured LLM judge that scores agent outputs against rubrics.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Judge Assessment Structure
;;; ===================================================================

;; Define SKEL class for structured judge output if SKEL is available
(when (find-package :autopoiesis.skel)
  (let ((define-class-fn (find-symbol "DEFINE-SKEL-CLASS-FN" :autopoiesis.skel)))
    (declare (ignore define-class-fn))))

;; We define the judge as a plain function that uses the agentic loop
;; or SKEL if available, falling back to a simpler approach.

(defvar *judge-system-prompt*
  "You are an expert evaluator assessing the quality of agent output.
You will be given a task description, evaluation rubric, and the agent's output.
Score the output on a scale of 1-10 for each dimension in the rubric.

IMPORTANT: You MUST respond with ONLY a valid JSON object in this exact format:
{
  \"score\": <integer 1-10 overall quality>,
  \"dimensions\": {\"<dimension_name>\": <integer 1-10>, ...},
  \"reasoning\": \"<brief explanation of scores>\"
}

Do not include any text before or after the JSON object."
  "System prompt for the LLM judge.")

(defun build-judge-prompt (scenario-description rubric output &optional expected diff-context)
  "Build the user prompt for the judge.
   DIFF-CONTEXT is an optional string showing filesystem changes from sandbox execution."
  (format nil "## Task Description~%~a~%~%## Evaluation Rubric~%~a~%~%~@[## Expected Output~%~a~%~%~]~@[## Filesystem Changes~%~a~%~%~]## Actual Output~%~a~%~%Score the output according to the rubric. Return ONLY a JSON object."
          scenario-description rubric expected diff-context output))

(defun parse-judge-response (response)
  "Parse a judge response string into a plist (:score :dimensions :reasoning).
   Returns nil if parsing fails."
  (handler-case
      (let* (;; Strip markdown fences if present
             (cleaned (if (search "```" response)
                          (let* ((start (or (search "{" response) 0))
                                 (end (or (position #\} response :from-end t) (length response))))
                            (subseq response start (1+ end)))
                          response))
             ;; Find the JSON object boundaries
             (json-start (position #\{ cleaned))
             (json-end (position #\} cleaned :from-end t)))
        (when (and json-start json-end (< json-start json-end))
          (let* ((json-str (subseq cleaned json-start (1+ json-end)))
                 (parsed (cl-json:decode-json-from-string json-str))
                 (score (cdr (assoc :score parsed)))
                 (dimensions (cdr (assoc :dimensions parsed)))
                 (reasoning (cdr (assoc :reasoning parsed))))
            (list :score (when (integerp score) score)
                  :dimensions (when (listp dimensions)
                                (mapcar (lambda (pair)
                                          (cons (string-downcase (symbol-name (car pair)))
                                                (cdr pair)))
                                        dimensions))
                  :reasoning reasoning))))
    (error (e)
      (declare (ignore e))
      nil)))

(defun run-judge (scenario-plist output &key (num-judges 1) client diff-context)
  "Run LLM judge NUM-JUDGES times and return aggregated scores.

   SCENARIO-PLIST is the entity-state of an eval-scenario.
   OUTPUT is the agent's text output to evaluate.
   NUM-JUDGES is how many independent judge runs to perform (default 1).
   CLIENT is an optional LLM client override.
   DIFF-CONTEXT is an optional string of filesystem changes from sandbox execution.

   Returns a plist:
     :overall-score   - median overall score (1-10 or nil)
     :dimensions      - alist of (dimension . median-score)
     :reasoning       - list of reasoning strings from judges
     :agreement       - float [0,1] measuring inter-judge agreement
     :raw-scores      - list of all individual score plists
     :success         - T if at least one judge succeeded"
  (declare (ignore client))
  (let* ((description (or (getf scenario-plist :eval-scenario/description) ""))
         (rubric (let ((r (getf scenario-plist :eval-scenario/rubric)))
                   (if (stringp r) r
                       (if r (format nil "~a" r)
                           "Evaluate for correctness, completeness, and quality."))))
         (expected (getf scenario-plist :eval-scenario/expected))
         (prompt (build-judge-prompt description rubric output expected diff-context))
         (scores nil)
         (reasonings nil))
    ;; Run judges
    (dotimes (i num-judges)
      (declare (ignore i))
      (handler-case
          (let* (;; Try to use SKEL if available, otherwise use a basic approach
                 (response (invoke-judge-llm prompt))
                 (parsed (parse-judge-response response)))
            (when parsed
              (push parsed scores)
              (when (getf parsed :reasoning)
                (push (getf parsed :reasoning) reasonings))))
        (error (e)
          (declare (ignore e))
          nil)))
    ;; Aggregate results
    (if (null scores)
        (list :overall-score nil
              :dimensions nil
              :reasoning nil
              :agreement 0.0
              :raw-scores nil
              :success nil)
        (let* ((overall-scores (remove nil (mapcar (lambda (s) (getf s :score)) scores)))
               (median-score (when overall-scores
                               (nth (floor (length overall-scores) 2)
                                    (sort (copy-list overall-scores) #'<))))
               ;; Aggregate dimensions
               (all-dims (make-hash-table :test 'equal))
               (_ (dolist (s scores)
                    (dolist (d (getf s :dimensions))
                      (push (cdr d) (gethash (car d) all-dims nil)))))
               (median-dims (let ((result nil))
                              (maphash (lambda (k vs)
                                         (let ((sorted (sort (copy-list vs) #'<)))
                                           (push (cons k (nth (floor (length sorted) 2) sorted))
                                                 result)))
                                       all-dims)
                              (nreverse result)))
               ;; Compute agreement (standard deviation / range)
               (agreement (if (> (length overall-scores) 1)
                              (let* ((mean (/ (reduce #'+ overall-scores) (length overall-scores)))
                                     (variance (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2))
                                                                      overall-scores))
                                                  (length overall-scores)))
                                     (std-dev (sqrt variance)))
                                ;; Normalize: 0 std-dev = perfect agreement (1.0),
                                ;; 4.5 std-dev (max for 1-10 range) = no agreement (0.0)
                                (max 0.0 (- 1.0 (/ std-dev 4.5))))
                              1.0)))
          (declare (ignore _))
          (list :overall-score median-score
                :dimensions median-dims
                :reasoning (nreverse reasonings)
                :agreement agreement
                :raw-scores scores
                :success t)))))

;;; ===================================================================
;;; LLM Invocation (uses agentic-loop or SKEL if available)
;;; ===================================================================

(defun invoke-judge-llm (prompt)
  "Invoke an LLM for judging. Tries SKEL, then agentic-loop, then errors.
   Returns the response text string."
  ;; Try using the Claude bridge directly if available
  (let ((bridge-pkg (find-package :autopoiesis.integration)))
    (when bridge-pkg
      (let ((complete-fn (find-symbol "AGENTIC-COMPLETE" bridge-pkg))
            (make-client-fn (find-symbol "MAKE-CLAUDE-CLIENT" bridge-pkg)))
        (when (and complete-fn (fboundp complete-fn)
                   make-client-fn (fboundp make-client-fn))
          (let* ((client (funcall make-client-fn))
                 (messages (list (list (cons "role" "user")
                                       (cons "content" prompt))))
                 (response (funcall complete-fn client messages
                                    :system *judge-system-prompt*)))
            (return-from invoke-judge-llm response))))))
  ;; Fallback: signal error
  (error 'autopoiesis-error
         :message "No LLM client available for judge invocation. Ensure autopoiesis.integration is loaded."))
