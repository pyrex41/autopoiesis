# Sandbox Research Tool

## What This Is

A personal tool for exploring ideas by running parallel experiments in isolated sandboxes. You give it a research question, it spins up N sandboxes, runs a different approach in each one (install deps, write code, execute, evaluate), and hands you back a ranked summary of what worked.

This is **not** a product. It's a power tool for the person who built it.

## Why It Works

The value isn't the code — it's the compound effect of running it. In the time it takes you to manually prototype one approach, this tool has tried five and shown you which two are worth pursuing. The sandbox isolation means agents can `pip install` anything, run untrusted code, and blow up without consequences.

## Architecture

Two layers on top of the existing autopoiesis platform:

```
Layer 1: Sandbox Integration (already planned, see 2026-02-17-squashd-sandbox-integration.md)
  squashd-core library → sandbox-provider → substrate entity types → conductor dispatch

Layer 2: Research Campaign (THIS PLAN)
  research question → approach generation → parallel sandbox trials → result aggregation → human review
```

### Data Flow

```
User: "Is there an arb opportunity between DEX A and DEX B?"
  │
  ▼
plan-approaches (one-shot Claude call)
  → 5 approach plists, each with: name, setup commands, hypothesis, evaluation criteria
  │
  ▼
run-campaign (conductor dispatches 5 parallel sandbox workers)
  │
  ├─ Trial 0: sandbox + agentic-agent → installs deps, writes script, runs backtest
  ├─ Trial 1: sandbox + agentic-agent → different strategy, same data
  ├─ Trial 2: sandbox + agentic-agent → ...
  ├─ Trial 3: sandbox + agentic-agent → ...
  └─ Trial 4: sandbox + agentic-agent → ...
  │
  ▼
summarize-campaign (one-shot Claude call over all trial outputs)
  → ranked results with evidence
  │
  ▼
Human reviews, picks winners, optionally branches for deeper investigation
```

### How Each Trial Works

Each trial is an **agentic-agent with sandbox-backed tools**. The agent doesn't run inside the sandbox — it runs in AP and executes commands in the sandbox via `sandbox-exec` capability. This gives us full cognitive observability (thought streams, conversation recording) while keeping execution isolated.

The trial agent gets:
- A system prompt describing the research question and its specific approach
- Capabilities: `sandbox-exec`, `sandbox-write-file`, `sandbox-read-file`, `sandbox-install` (convenience wrappers around exec)
- A conversation context for recording the full investigation trail
- A max-turns budget (default 15)

The agent autonomously:
1. Plans what to install and code to write
2. Writes files into the sandbox via `sandbox-write-file`
3. Installs dependencies via `sandbox-install`
4. Runs its experiment via `sandbox-exec`
5. Reads output, evaluates against criteria
6. Writes a structured finding report as its final response

## Implementation

### Prerequisites

Sandbox integration (Phase 1-3 from the existing plan) must be complete first. This plan assumes `*sandbox-manager*` is available and `sandbox-provider` works.

### New Files

```
platform/src/research/
  packages.lisp           - Package definition
  campaign.lisp           - Campaign orchestration, trial management
  tools.lisp              - Sandbox-backed capabilities for trial agents
  interface.lisp          - Top-level API (run-research)
```

Plus ASDF system definition appended to `autopoiesis.asd` and test file in `platform/test/research-tests.lisp`.

---

## Phase 1: Sandbox Tool Capabilities

### File: `platform/src/research/tools.lisp`

Define capabilities that trial agents use to interact with their sandbox. Each capability takes a `sandbox-id` parameter and delegates to the sandbox manager.

```lisp
(in-package #:autopoiesis.research)

;;; Sandbox-backed capabilities for research trial agents.
;;; Each trial agent gets its own sandbox-id bound at creation.

(defvar *trial-sandbox-id* nil
  "Dynamically bound to the current trial's sandbox ID during execution.")

(autopoiesis.agent:defcapability sandbox-exec (&key command timeout working-directory)
  "Execute a shell command in the trial's sandbox.
   COMMAND - Shell command string to execute.
   TIMEOUT - Seconds before timeout (default: 120).
   WORKING-DIRECTORY - Directory to run in (default: /workspace).
   Returns stdout, stderr, and exit code."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-exec "Error: No sandbox bound for this trial"))
  (unless autopoiesis.sandbox:*sandbox-manager*
    (return-from sandbox-exec "Error: Sandbox manager not initialized"))
  (handler-case
      (let ((result (squashd:manager-exec
                     autopoiesis.sandbox:*sandbox-manager*
                     *trial-sandbox-id*
                     command
                     :timeout (or timeout 120)
                     :workdir (or working-directory "/workspace"))))
        (format nil "Exit code: ~A~%~%STDOUT:~%~A~@[~%STDERR:~%~A~]"
                (squashd:exec-result-exit-code result)
                (squashd:exec-result-stdout result)
                (let ((err (squashd:exec-result-stderr result)))
                  (when (and err (> (length err) 0)) err))))
    (error (e)
      (format nil "Sandbox exec error: ~A" e))))

(autopoiesis.agent:defcapability sandbox-write-file (&key path content)
  "Write a file into the trial's sandbox.
   PATH - Absolute path inside the sandbox (e.g., /workspace/script.py).
   CONTENT - File content as a string."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-write-file "Error: No sandbox bound"))
  ;; Write file by executing a heredoc command in the sandbox
  (handler-case
      (let* ((escaped (substitute-char content #\' "'\"'\"'"))
             (cmd (format nil "mkdir -p $(dirname '~A') && cat > '~A' << 'SANDBOX_EOF'~%~A~%SANDBOX_EOF"
                          path path content))
             (result (squashd:manager-exec
                      autopoiesis.sandbox:*sandbox-manager*
                      *trial-sandbox-id* cmd
                      :timeout 10)))
        (if (zerop (squashd:exec-result-exit-code result))
            (format nil "Wrote ~A bytes to ~A" (length content) path)
            (format nil "Error writing ~A: ~A" path
                    (squashd:exec-result-stderr result))))
    (error (e)
      (format nil "Error: ~A" e))))

(autopoiesis.agent:defcapability sandbox-read-file (&key path)
  "Read a file from the trial's sandbox.
   PATH - Absolute path inside the sandbox."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-read-file "Error: No sandbox bound"))
  (handler-case
      (let ((result (squashd:manager-exec
                     autopoiesis.sandbox:*sandbox-manager*
                     *trial-sandbox-id*
                     (format nil "cat '~A'" path)
                     :timeout 10)))
        (if (zerop (squashd:exec-result-exit-code result))
            (squashd:exec-result-stdout result)
            (format nil "Error reading ~A: ~A" path
                    (squashd:exec-result-stderr result))))
    (error (e)
      (format nil "Error: ~A" e))))

(autopoiesis.agent:defcapability sandbox-install (&key packages manager)
  "Install packages in the trial's sandbox.
   PACKAGES - Space-separated package names (e.g., \"pandas numpy matplotlib\").
   MANAGER - Package manager to use: \"pip\", \"npm\", \"apk\" (default: \"pip\")."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-install "Error: No sandbox bound"))
  (let* ((mgr (or manager "pip"))
         (cmd (cond
                ((string= mgr "pip") (format nil "pip install ~A" packages))
                ((string= mgr "npm") (format nil "npm install -g ~A" packages))
                ((string= mgr "apk") (format nil "apk add ~A" packages))
                (t (format nil "~A install ~A" mgr packages)))))
    (handler-case
        (let ((result (squashd:manager-exec
                       autopoiesis.sandbox:*sandbox-manager*
                       *trial-sandbox-id* cmd
                       :timeout 300  ; installs can be slow
                       :workdir "/workspace")))
          (if (zerop (squashd:exec-result-exit-code result))
              (format nil "Installed: ~A" packages)
              (format nil "Install failed (exit ~A): ~A"
                      (squashd:exec-result-exit-code result)
                      (squashd:exec-result-stderr result))))
      (error (e)
        (format nil "Error: ~A" e)))))

(defun research-tool-capabilities ()
  "Return the list of capability instances for research trial agents."
  (list (autopoiesis.agent:find-capability 'sandbox-exec)
        (autopoiesis.agent:find-capability 'sandbox-write-file)
        (autopoiesis.agent:find-capability 'sandbox-read-file)
        (autopoiesis.agent:find-capability 'sandbox-install)))
```

### Success Criteria
- [ ] All four capabilities compile and register
- [ ] `sandbox-exec` delegates to squashd manager when `*trial-sandbox-id*` is bound
- [ ] `sandbox-exec` returns error message when `*trial-sandbox-id*` is nil

---

## Phase 2: Campaign Orchestration

### File: `platform/src/research/campaign.lisp`

The campaign orchestrator coordinates the three-step flow: plan approaches, run trials, summarize results.

```lisp
(in-package #:autopoiesis.research)

;;; ── Campaign data structures ───────────────────────────────────

(defclass research-campaign ()
  ((id :initarg :id
       :accessor campaign-id
       :initform (autopoiesis.core:make-uuid))
   (question :initarg :question
             :accessor campaign-question
             :documentation "The research question")
   (num-approaches :initarg :num-approaches
                   :accessor campaign-num-approaches
                   :initform 5)
   (approaches :initarg :approaches
               :accessor campaign-approaches
               :initform nil
               :documentation "List of approach plists generated by plan-approaches")
   (trials :accessor campaign-trials
           :initform nil
           :documentation "List of trial result plists")
   (summary :accessor campaign-summary
            :initform nil
            :documentation "Final ranked summary")
   (status :accessor campaign-status
           :initform :pending
           :documentation ":pending :planning :running :summarizing :complete :failed")
   (layers :initarg :layers
           :accessor campaign-layers
           :initform '("000-base-alpine" "101-python")
           :documentation "Squashfs layers for trial sandboxes")
   (timeout :initarg :timeout
            :accessor campaign-timeout
            :initform 600
            :documentation "Per-trial timeout in seconds")
   (max-turns :initarg :max-turns
              :accessor campaign-max-turns
              :initform 15
              :documentation "Max agentic loop turns per trial")
   (created-at :initform (get-universal-time)
               :accessor campaign-created-at))
  (:documentation "A research campaign: question → approaches → trials → summary"))

;;; ── Step 1: Generate approaches ────────────────────────────────

(defun plan-approaches (campaign &key client)
  "Ask Claude to generate N different approaches for the research question.
   Returns list of approach plists: ((:name ... :hypothesis ... :setup ... :script-outline ...))."
  (setf (campaign-status campaign) :planning)
  (let* ((client (or client (autopoiesis.integration:make-claude-client)))
         (prompt (format nil "I have a research question I want to investigate by running ~A ~
                              parallel experiments in isolated Linux sandboxes (Alpine Linux with Python).~%~%~
                              Research question: ~A~%~%~
                              Generate exactly ~A different approaches to investigate this. ~
                              For each approach, provide:~%~
                              1. name: A short descriptive name (2-4 words)~%~
                              2. hypothesis: What this approach tests~%~
                              3. setup: What packages to install (pip packages)~%~
                              4. script_outline: Brief description of what the script should do~%~
                              5. evaluation: How to determine if this approach found something useful~%~%~
                              Respond with ONLY a JSON array of objects. No markdown, no explanation. ~
                              Each object has keys: name, hypothesis, setup, script_outline, evaluation."
                         (campaign-num-approaches campaign)
                         (campaign-question campaign)
                         (campaign-num-approaches campaign)))
         (response (autopoiesis.integration:claude-complete
                    client
                    (list `(("role" . "user") ("content" . ,prompt)))
                    :system "You are a research assistant. Output only valid JSON.")))
    ;; Parse the JSON response into a list of approach plists
    (let ((approaches (handler-case
                          (cl-json:decode-json-from-string
                           (autopoiesis.integration:response-text response))
                        (error (e)
                          (warn "Failed to parse approaches: ~A" e)
                          nil))))
      (setf (campaign-approaches campaign)
            (or approaches
                ;; Fallback: create N copies of a generic approach
                (loop for i from 0 below (campaign-num-approaches campaign)
                      collect `((:name . ,(format nil "approach-~A" i))
                                (:hypothesis . "Generic investigation")
                                (:setup . "")
                                (:script--outline . "Investigate the question")
                                (:evaluation . "Check if results are meaningful")))))
      (campaign-approaches campaign))))

;;; ── Step 2: Run trials ─────────────────────────────────────────

(defun make-trial-system-prompt (question approach)
  "Build the system prompt for a trial agent."
  (format nil "You are a research agent investigating a specific approach to a research question.~%~%~
               RESEARCH QUESTION: ~A~%~%~
               YOUR APPROACH: ~A~%~
               HYPOTHESIS: ~A~%~%~
               YOUR TASK:~%~
               1. Install required packages using sandbox_install~%~
               2. Write your experiment code using sandbox_write_file (write to /workspace/)~%~
               3. Run it using sandbox_exec~%~
               4. Read and analyze the output~%~
               5. Write a FINDINGS REPORT as your final message~%~%~
               FINDINGS REPORT FORMAT:~%~
               ## Approach: [name]~%~
               ## Result: [SUCCESS/PARTIAL/FAILURE]~%~
               ## Evidence: [what you found, with data]~%~
               ## Confidence: [HIGH/MEDIUM/LOW]~%~
               ## Next Steps: [what to investigate further if promising]~%~%~
               Be thorough but efficient. You have limited turns.~%~
               If an approach fails, document WHY it failed — that's valuable data too."
          question
          (cdr (assoc :name approach))
          (cdr (assoc :hypothesis approach))))

(defun run-trial (campaign approach index &key client)
  "Run a single trial: create sandbox, run agentic agent, collect results.
   Returns a trial result plist."
  (let* ((sandbox-id (format nil "trial-~A-~A"
                             (campaign-id campaign) index))
         (layers (campaign-layers campaign))
         (timeout (campaign-timeout campaign))
         (start-time (get-universal-time))
         (result-plist nil))

    (handler-case
        (progn
          ;; Create sandbox
          (squashd:manager-create-sandbox
           autopoiesis.sandbox:*sandbox-manager*
           sandbox-id
           :layers layers
           :memory-mb 1024
           :cpu 2.0
           :max-lifetime-s (+ timeout 120))

          ;; Create workspace directory
          (squashd:manager-exec
           autopoiesis.sandbox:*sandbox-manager*
           sandbox-id "mkdir -p /workspace"
           :timeout 5)

          ;; Run agentic agent with sandbox tools
          (let* ((system-prompt (make-trial-system-prompt
                                 (campaign-question campaign) approach))
                 (agent (autopoiesis.integration:make-agentic-agent
                         :name (format nil "trial-~A" index)
                         :system-prompt system-prompt
                         :capabilities '(sandbox-exec sandbox-write-file
                                         sandbox-read-file sandbox-install)
                         :max-turns (campaign-max-turns campaign)))
                 ;; Init conversation context for the trial
                 (ctx (when autopoiesis.substrate:*store*
                        (autopoiesis.integration:init-conversation-context
                         agent :name (format nil "trial-~A-~A" (campaign-id campaign) index))))
                 ;; Bind the sandbox for this trial's tools
                 (*trial-sandbox-id* sandbox-id))
            (declare (ignore ctx))

            ;; Run the agent
            (let ((response (autopoiesis.integration:agentic-agent-prompt
                             agent
                             (format nil "Begin investigating: ~A~%~%~
                                          Packages to install: ~A~%~
                                          Approach: ~A"
                                     (cdr (assoc :name approach))
                                     (or (cdr (assoc :setup approach)) "none")
                                     (or (cdr (assoc :script--outline approach)) "investigate")))))

              (setf result-plist
                    (list :index index
                          :approach-name (cdr (assoc :name approach))
                          :hypothesis (cdr (assoc :hypothesis approach))
                          :response response
                          :status :completed
                          :duration (- (get-universal-time) start-time)
                          :sandbox-id sandbox-id)))))

      (error (e)
        (setf result-plist
              (list :index index
                    :approach-name (cdr (assoc :name approach))
                    :hypothesis (cdr (assoc :hypothesis approach))
                    :response (format nil "Trial failed: ~A" e)
                    :status :failed
                    :duration (- (get-universal-time) start-time)
                    :sandbox-id sandbox-id))))

    ;; Always clean up sandbox
    (ignore-errors
      (squashd:manager-destroy-sandbox
       autopoiesis.sandbox:*sandbox-manager* sandbox-id))

    result-plist))

(defun run-all-trials (campaign &key client)
  "Run all trials in parallel using threads.
   Updates campaign-trials when all complete."
  (setf (campaign-status campaign) :running)
  (let* ((approaches (campaign-approaches campaign))
         (n (length approaches))
         (results (make-array n :initial-element nil))
         (lock (bt:make-lock "trial-results"))
         (completed (bt:make-condition-variable :name "trials-done"))
         (done-count 0)
         ;; Capture substrate bindings for child threads
         (captured-substrate autopoiesis.substrate:*substrate*)
         (captured-store autopoiesis.substrate:*store*)
         ;; Capture all substrate specials
         (captured-intern-table autopoiesis.substrate::*intern-table*)
         (captured-resolve-table autopoiesis.substrate::*resolve-table*)
         (captured-index autopoiesis.substrate::*index*)
         (captured-hooks autopoiesis.substrate::*hooks*))

    ;; Spawn one thread per trial
    (loop for approach in approaches
          for i from 0
          do (bt:make-thread
              (lambda ()
                ;; Rebind substrate specials in child thread
                (let ((autopoiesis.substrate:*substrate* captured-substrate)
                      (autopoiesis.substrate:*store* captured-store)
                      (autopoiesis.substrate::*intern-table* captured-intern-table)
                      (autopoiesis.substrate::*resolve-table* captured-resolve-table)
                      (autopoiesis.substrate::*index* captured-index)
                      (autopoiesis.substrate::*hooks* captured-hooks)
                      ;; Capture loop vars for closure
                      (my-approach approach)
                      (my-index i))
                  (let ((result (run-trial campaign my-approach my-index
                                          :client client)))
                    (bt:with-lock-held (lock)
                      (setf (aref results my-index) result)
                      (incf done-count)
                      (when (= done-count n)
                        (bt:condition-notify completed))))))
              :name (format nil "trial-~A" i)))

    ;; Wait for all trials to complete
    (bt:with-lock-held (lock)
      (loop while (< done-count n)
            do (bt:condition-wait completed lock
                                  :timeout (+ (campaign-timeout campaign) 60))))

    ;; Collect results
    (setf (campaign-trials campaign)
          (coerce results 'list))
    (campaign-trials campaign)))

;;; ── Step 3: Summarize results ──────────────────────────────────

(defun summarize-results (campaign &key client)
  "Ask Claude to rank and summarize all trial results.
   Returns a summary string."
  (setf (campaign-status campaign) :summarizing)
  (let* ((client (or client (autopoiesis.integration:make-claude-client)))
         (trial-reports
           (format nil "~{~A~^~%~%---~%~%~}"
                   (loop for trial in (campaign-trials campaign)
                         collect (format nil "## Trial ~A: ~A~%Status: ~A~%Duration: ~As~%~%~A"
                                         (getf trial :index)
                                         (getf trial :approach-name)
                                         (getf trial :status)
                                         (getf trial :duration)
                                         (getf trial :response)))))
         (prompt (format nil "I ran ~A parallel research trials to investigate:~%~%~A~%~%~
                              Here are all the trial reports:~%~%~A~%~%~
                              Please provide:~%~
                              1. A RANKED summary (best to worst) with 1-2 sentence justification each~%~
                              2. An overall VERDICT: was anything actionable found?~%~
                              3. RECOMMENDED NEXT STEPS if any approach showed promise~%~%~
                              Be concise and direct. I want to know: should I pursue any of these further?"
                         (length (campaign-trials campaign))
                         (campaign-question campaign)
                         trial-reports))
         (response (autopoiesis.integration:claude-complete
                    client
                    (list `(("role" . "user") ("content" . ,prompt)))
                    :system "You are evaluating research results. Be direct and honest about what worked and what didn't.")))
    (let ((summary (autopoiesis.integration:response-text response)))
      (setf (campaign-summary campaign) summary)
      (setf (campaign-status campaign) :complete)
      summary)))
```

### Success Criteria
- [ ] `plan-approaches` generates N approaches from a question
- [ ] `run-trial` creates sandbox, runs agent, cleans up
- [ ] `run-all-trials` runs N trials in parallel threads
- [ ] `summarize-results` produces a ranked summary
- [ ] Substrate records conversation context for each trial

---

## Phase 3: Top-Level Interface

### File: `platform/src/research/interface.lisp`

The entry point. One function call to go from question to ranked results.

```lisp
(in-package #:autopoiesis.research)

(defun run-research (question &key (num-approaches 5)
                                    (timeout 600)
                                    (max-turns 15)
                                    (layers '("000-base-alpine" "101-python"))
                                    client
                                    (stream *standard-output*))
  "Run a research campaign: generate approaches, execute in parallel sandboxes, summarize.

   QUESTION     - The research question to investigate
   NUM-APPROACHES - How many parallel approaches to try (default: 5)
   TIMEOUT      - Per-trial timeout in seconds (default: 600)
   MAX-TURNS    - Max agentic loop turns per trial (default: 15)
   LAYERS       - Squashfs layers for sandboxes (default: alpine + python)
   CLIENT       - Claude client (default: created from ANTHROPIC_API_KEY)
   STREAM       - Output stream for progress messages (default: *standard-output*)

   Returns the campaign object. Key accessors:
     (campaign-summary campaign)  - Ranked results
     (campaign-trials campaign)   - Individual trial results
     (campaign-approaches campaign) - Generated approaches

   Example:
     (run-research \"Is there a statistical arbitrage opportunity between ETH and BTC?\"
                   :num-approaches 3 :timeout 300)"

  (unless autopoiesis.sandbox:*sandbox-manager*
    (error "Sandbox manager not initialized. Call (autopoiesis.sandbox:start-sandbox-manager) first."))

  (let ((campaign (make-instance 'research-campaign
                                 :question question
                                 :num-approaches num-approaches
                                 :timeout timeout
                                 :max-turns max-turns
                                 :layers layers)))

    ;; Step 1: Generate approaches
    (format stream "~%[1/3] Planning ~A approaches for:~%  ~A~%" num-approaches question)
    (plan-approaches campaign :client client)
    (format stream "~%Approaches:~%")
    (loop for approach in (campaign-approaches campaign)
          for i from 1
          do (format stream "  ~A. ~A: ~A~%"
                     i
                     (cdr (assoc :name approach))
                     (cdr (assoc :hypothesis approach))))

    ;; Step 2: Run trials
    (format stream "~%[2/3] Running ~A trials in parallel sandboxes...~%"
            (length (campaign-approaches campaign)))
    (run-all-trials campaign :client client)
    (format stream "~%Trials complete:~%")
    (loop for trial in (campaign-trials campaign)
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
  (format stream "~%═══════════════════════════════════════════════════~%")
  (format stream "Research Campaign: ~A~%" (campaign-id campaign))
  (format stream "Question: ~A~%" (campaign-question campaign))
  (format stream "Status: ~A~%" (campaign-status campaign))
  (format stream "Duration: ~As~%"
          (- (get-universal-time) (campaign-created-at campaign)))
  (format stream "═══════════════════════════════════════════════════~%")
  (when (campaign-trials campaign)
    (format stream "~%TRIALS:~%")
    (dolist (trial (campaign-trials campaign))
      (format stream "~%── Trial ~A: ~A ──~%"
              (getf trial :index) (getf trial :approach-name))
      (format stream "Status: ~A | Duration: ~As~%"
              (getf trial :status) (getf trial :duration))
      (format stream "Hypothesis: ~A~%" (getf trial :hypothesis))
      (when (getf trial :response)
        (format stream "~%~A~%" (getf trial :response)))))
  (when (campaign-summary campaign)
    (format stream "~%═══════════════════════════════════════════════════~%")
    (format stream "SUMMARY:~%~%~A~%" (campaign-summary campaign)))
  (values))

(defun rerun-trial (campaign index &key client)
  "Re-run a specific trial from a campaign (e.g., after tweaking the approach).
   Returns the updated trial result."
  (let ((approach (nth index (campaign-approaches campaign))))
    (unless approach
      (error "No approach at index ~A" index))
    (let ((result (run-trial campaign approach index :client client)))
      ;; Replace the trial in the campaign
      (setf (nth index (campaign-trials campaign)) result)
      result)))
```

### Success Criteria
- [ ] `(run-research "question")` runs end-to-end and prints progress
- [ ] `(campaign-report campaign)` shows detailed results
- [ ] `(rerun-trial campaign 2)` re-runs a specific trial

---

## Phase 4: Package & System Definition

### File: `platform/src/research/packages.lisp`

```lisp
(defpackage #:autopoiesis.research
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads)
                    (#:sq #:squashd))
  (:export
   ;; Top-level API
   #:run-research
   #:campaign-report
   #:rerun-trial
   ;; Campaign class
   #:research-campaign
   #:campaign-id
   #:campaign-question
   #:campaign-approaches
   #:campaign-trials
   #:campaign-summary
   #:campaign-status
   ;; Trial sandbox binding
   #:*trial-sandbox-id*
   ;; Tool capabilities
   #:sandbox-exec
   #:sandbox-write-file
   #:sandbox-read-file
   #:sandbox-install
   #:research-tool-capabilities))
```

### ASDF system (append to `autopoiesis.asd`):

```lisp
;;; Research campaign layer (sandbox-backed parallel investigation)
(asdf:defsystem #:autopoiesis/research
  :description "Sandbox-backed parallel research campaigns"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:autopoiesis/sandbox)
  :components
  ((:module "src/research"
    :serial t
    :components
    ((:file "packages")
     (:file "tools")
     (:file "campaign")
     (:file "interface")))))
```

---

## Phase 5: Tests

### File: `platform/test/research-tests.lisp`

Mock-based tests that run without Linux/sandboxes:

1. **Campaign creation** - verify defaults, slot initialization
2. **Approach planning** - mock Claude response, verify parsing
3. **Trial execution** - mock sandbox manager, verify tool dispatch
4. **Summary generation** - mock Claude response, verify ranking
5. **Full pipeline** - mock everything, verify end-to-end flow
6. **Error handling** - sandbox failure, Claude API failure, timeout

The mock strategy: bind `*trial-sandbox-id*` and mock `squashd:manager-exec` to return canned results. Mock Claude via `*claude-complete-function*`.

### Success Criteria
- [ ] All unit tests pass on macOS/Linux without real sandboxes
- [ ] Existing AP tests still pass

---

## Usage Examples

### Basic research

```lisp
;; One-time setup (requires privileged Linux container with squashfs modules)
(autopoiesis.sandbox:start-sandbox-manager :data-dir "/data")

;; Run research
(run-research "What are the most effective Python libraries for time series anomaly detection?
               Compare at least 3 libraries on synthetic data with known anomalies."
              :num-approaches 4
              :timeout 300)
```

### Crypto research

```lisp
(run-research "Is there a profitable mean-reversion strategy for the SOL/USDC pair?
               Use free public API data. Backtest over the last 30 days."
              :num-approaches 5
              :layers '("000-base-alpine" "101-python")
              :timeout 600)
```

### Startup idea validation

```lisp
(run-research "Build a minimal working prototype of a CLI tool that converts
               natural language to SQL queries using a local LLM.
               Evaluate: accuracy on 10 test queries, latency, memory usage."
              :num-approaches 3
              :max-turns 20
              :timeout 900)
```

### Reviewing results later

```lisp
;; The campaign object is returned — save it
(defvar *last-campaign* (run-research "..."))

;; Print detailed report
(campaign-report *last-campaign*)

;; Re-run a promising trial with more turns
(let ((*trial-sandbox-id* nil)) ; will be rebound by run-trial
  (rerun-trial *last-campaign* 2))
```

---

## What's NOT in This Plan

- **Campaign persistence**: Campaigns live in memory for now. Substrate-backing is a natural extension but not MVP.
- **Web UI**: Results go to `*standard-output*`. A web dashboard is future work.
- **Cost tracking**: API token usage per trial. Easy to add via provider events but not MVP.
- **Approach iteration**: Having Claude refine approaches based on trial results (multi-round campaigns). Natural extension.
- **Distributed execution**: Everything runs in one SBCL process. Scaling across machines is a separate concern.

## Implementation Order

1. Sandbox integration (existing plan, Phases 1-3) — prerequisite
2. Phase 4 (package + ASDF) — scaffolding
3. Phase 1 (sandbox tool capabilities) — the agent's hands
4. Phase 2 (campaign orchestration) — the brain
5. Phase 3 (top-level interface) — the face
6. Phase 5 (tests) — confidence

## Dependencies

- Sandbox integration plan complete (squashd-core.asd + autopoiesis/sandbox)
- ANTHROPIC_API_KEY in environment
- Privileged Linux container with squashfs modules for real execution
- SBCL + Quicklisp

## Risk & Mitigation

| Risk | Mitigation |
|------|------------|
| Trial agents get stuck in loops | `max-turns` limit + per-trial timeout |
| Sandbox creation too slow for 5 parallel | Pre-pool sandboxes (optimization, not MVP) |
| Claude generates bad approaches | Allow manual approach override via `:approaches` kwarg |
| API costs from N parallel agents | Default to 5 approaches, 15 turns = ~75 API calls max |
| Substrate thread safety with 5 parallel writers | `transact!` is already atomic; intern-table has locks |
