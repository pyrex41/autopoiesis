;;;; interface.lisp - Top-level research API
;;;;
;;;; The entry point for running research campaigns.
;;;; One function call to go from question to ranked results.

(in-package #:autopoiesis.research)

(defun run-research (question &key (num-approaches 5)
                                    (timeout 600)
                                    (max-turns 15)
                                    (mode :tool-backed)
                                    (layers '("000-base-alpine" "101-python"))
                                    (agent-command *sandboxed-agent-command*)
                                    approaches
                                    client
                                    (stream *standard-output*))
  "Run a research campaign: generate approaches, execute in parallel sandboxes, summarize.

   QUESTION       - The research question to investigate
   NUM-APPROACHES - How many parallel approaches to try (default: 5)
   TIMEOUT        - Per-trial timeout in seconds (default: 600)
   MAX-TURNS      - Max agentic loop turns per trial in :tool-backed mode (default: 15)
   MODE           - :tool-backed (agent in AP, sandbox for exec) or
                    :fully-sandboxed (entire agent CLI runs in sandbox)
   LAYERS         - Squashfs layers for sandboxes (default: alpine + python)
   AGENT-COMMAND  - CLI command for fully-sandboxed mode (default: 'claude')
   APPROACHES     - Pre-defined approaches (skip generation if provided).
                    List of alists with keys :name, :hypothesis, :setup, :script--outline
   CLIENT         - Claude client (default: created from ANTHROPIC_API_KEY)
   STREAM         - Output stream for progress messages (default: *standard-output*)

   Returns the campaign object. Key accessors:
     (campaign-summary campaign)    - Ranked results
     (campaign-trials campaign)     - Individual trial results
     (campaign-approaches campaign) - Generated approaches

   Examples:

   ;; Tool-backed mode (default): agent runs in AP, executes in sandbox
   (run-research \"Is there a profitable momentum strategy for BTC/ETH?\"
                 :num-approaches 3 :timeout 300)

   ;; Fully-sandboxed mode: Claude Code runs inside the sandbox
   (run-research \"Build and benchmark a Rust vs Python web scraper\"
                 :mode :fully-sandboxed
                 :agent-command \"claude\"
                 :num-approaches 2
                 :layers '(\"000-base-alpine\" \"101-python\" \"102-nodejs\"))"

  (unless autopoiesis.sandbox:*sandbox-manager*
    (error "Sandbox manager not initialized. Call (autopoiesis.sandbox:start-sandbox-manager) first."))

  (let ((campaign (make-instance 'research-campaign
                                 :question question
                                 :num-approaches num-approaches
                                 :timeout timeout
                                 :max-turns max-turns
                                 :mode mode
                                 :layers layers)))

    ;; Step 1: Generate approaches (or use provided ones)
    (if approaches
        (progn
          (setf (campaign-approaches campaign) approaches)
          (format stream "~%Using ~A provided approaches for:~%  ~A~%"
                  (length approaches) question))
        (progn
          (format stream "~%[1/3] Planning ~A approaches for:~%  ~A~%"
                  num-approaches question)
          (plan-approaches campaign :client client)))

    (format stream "~%Approaches:~%")
    (loop for approach in (campaign-approaches campaign)
          for i from 1
          do (format stream "  ~A. ~A: ~A~%"
                     i
                     (cdr (assoc :name approach))
                     (cdr (assoc :hypothesis approach))))

    ;; Step 2: Run trials
    (format stream "~%[2/3] Running ~A trials in parallel sandboxes (~A mode)...~%"
            (length (campaign-approaches campaign))
            mode)
    (run-all-trials campaign :client client :agent-command agent-command)
    (format stream "~%Trials complete:~%")
    (loop for trial in (campaign-trials campaign)
          when trial
          do (format stream "  ~A: ~A (~As)~%"
                     (getf trial :approach-name)
                     (getf trial :status)
                     (getf trial :duration)))

    ;; Step 3: Summarize
    (format stream "~%[3/3] Analyzing results...~%")
    (summarize-results campaign :client client)
    (format stream "~%~A~%" (campaign-summary campaign))

    campaign))

(defun campaign-report (campaign &optional (stream *standard-output*))
  "Print a detailed report of a completed campaign."
  (format stream "~%~A~%" (make-string 60 :initial-element #\=))
  (format stream "Research Campaign: ~A~%" (campaign-id campaign))
  (format stream "Question: ~A~%" (campaign-question campaign))
  (format stream "Status: ~A | Mode: ~A~%" (campaign-status campaign) (campaign-mode campaign))
  (format stream "Duration: ~As~%"
          (- (get-universal-time) (campaign-created-at campaign)))
  (format stream "~A~%" (make-string 60 :initial-element #\=))
  (when (campaign-trials campaign)
    (format stream "~%TRIALS:~%")
    (dolist (trial (campaign-trials campaign))
      (when trial
        (format stream "~%~A Trial ~A: ~A ~A~%"
                (make-string 40 :initial-element #\-)
                (getf trial :index) (getf trial :approach-name)
                (make-string 1 :initial-element #\-))
        (format stream "Status: ~A | Mode: ~A | Duration: ~As~%"
                (getf trial :status) (getf trial :mode) (getf trial :duration))
        (format stream "Hypothesis: ~A~%" (getf trial :hypothesis))
        (when (getf trial :response)
          (format stream "~%~A~%" (getf trial :response))))))
  (when (campaign-summary campaign)
    (format stream "~%~A~%" (make-string 60 :initial-element #\=))
    (format stream "SUMMARY:~%~%~A~%" (campaign-summary campaign)))
  (values))

(defun rerun-trial (campaign index &key client agent-command)
  "Re-run a specific trial from a campaign (e.g., after tweaking the approach).
   Returns the updated trial result."
  (let ((approach (nth index (campaign-approaches campaign))))
    (unless approach
      (error "No approach at index ~A (campaign has ~A approaches)"
             index (length (campaign-approaches campaign))))
    (let ((result (run-trial campaign approach index
                             :client client
                             :agent-command agent-command)))
      ;; Replace the trial in the campaign
      (when (< index (length (campaign-trials campaign)))
        (setf (nth index (campaign-trials campaign)) result))
      result)))
