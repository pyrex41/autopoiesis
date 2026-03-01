;;;; provider-tests.lisp - Tests for the provider subsystem
;;;;
;;;; Tests provider protocol, registry, results, and cognitive loop integration.

(in-package #:autopoiesis.test)

(def-suite provider-tests
  :description "Provider subsystem tests")

(in-suite provider-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Mock Provider
;;; ═══════════════════════════════════════════════════════════════════

(defclass mock-provider (autopoiesis.integration:provider)
  ((canned-output :initarg :canned-output
                  :accessor mock-canned-output
                  :initform "mock response"
                  :documentation "Pre-configured response text")
   (canned-tool-calls :initarg :canned-tool-calls
                      :accessor mock-canned-tool-calls
                      :initform nil
                      :documentation "Pre-configured tool calls")
   (canned-exit-code :initarg :canned-exit-code
                     :accessor mock-canned-exit-code
                     :initform 0
                     :documentation "Pre-configured exit code")
   (invoke-count :initarg :invoke-count
                 :accessor mock-invoke-count
                 :initform 0
                 :documentation "Number of times invoke was called")
   (last-prompt :initarg :last-prompt
                :accessor mock-last-prompt
                :initform nil
                :documentation "Last prompt passed to invoke"))
  (:default-initargs :name "mock" :command "echo")
  (:documentation "Mock provider for testing without subprocess execution."))

(defun make-mock-provider (&key (name "mock") (canned-output "mock response")
                             canned-tool-calls (canned-exit-code 0))
  "Create a mock provider."
  (make-instance 'mock-provider
                 :name name
                 :command "echo"
                 :canned-output canned-output
                 :canned-tool-calls canned-tool-calls
                 :canned-exit-code canned-exit-code))

(defmethod autopoiesis.integration:provider-invoke
    ((provider mock-provider) prompt &key tools mode agent-id)
  "Mock invoke - returns canned result without spawning subprocess."
  (declare (ignore tools mode agent-id))
  (incf (mock-invoke-count provider))
  (setf (mock-last-prompt provider) prompt)
  (autopoiesis.integration:make-provider-result
   :provider-name (autopoiesis.integration:provider-name provider)
   :text (mock-canned-output provider)
   :tool-calls (mock-canned-tool-calls provider)
   :turns 1
   :cost 0.001
   :duration 0.5
   :exit-code (mock-canned-exit-code provider)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Registry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test provider-registry-register
  "Test registering a provider"
  (let ((autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
    (let ((p (make-mock-provider :name "test-reg")))
      (autopoiesis.integration:register-provider p)
      (is (eq p (autopoiesis.integration:find-provider "test-reg"))))))

(test provider-registry-find
  "Test finding a registered provider"
  (let ((autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
    (is (null (autopoiesis.integration:find-provider "nonexistent")))
    (let ((p (make-mock-provider :name "findme")))
      (autopoiesis.integration:register-provider p)
      (is (eq p (autopoiesis.integration:find-provider "findme"))))))

(test provider-registry-list
  "Test listing all providers"
  (let ((autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
    (is (null (autopoiesis.integration:list-providers)))
    (autopoiesis.integration:register-provider (make-mock-provider :name "p1"))
    (autopoiesis.integration:register-provider (make-mock-provider :name "p2"))
    (is (= 2 (length (autopoiesis.integration:list-providers))))))

(test provider-registry-unregister
  "Test unregistering a provider"
  (let ((autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
    (autopoiesis.integration:register-provider (make-mock-provider :name "removeme"))
    (is (autopoiesis.integration:find-provider "removeme"))
    (autopoiesis.integration:unregister-provider "removeme")
    (is (null (autopoiesis.integration:find-provider "removeme")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Result Tests
;;; ═══════════════════════════════════════════════════════════════════

(test provider-result-creation
  "Test creating a provider result"
  (let ((r (autopoiesis.integration:make-provider-result
            :provider-name "test"
            :text "hello"
            :exit-code 0
            :turns 3
            :cost 0.01)))
    (is (string= "test" (autopoiesis.integration:provider-result-provider-name r)))
    (is (string= "hello" (autopoiesis.integration:provider-result-text r)))
    (is (= 0 (autopoiesis.integration:provider-result-exit-code r)))
    (is (= 3 (autopoiesis.integration:provider-result-turns r)))
    (is (= 0.01 (autopoiesis.integration:provider-result-cost r)))))

(test provider-result-success-p
  "Test result-success-p predicate"
  (let ((success (autopoiesis.integration:make-provider-result :exit-code 0))
        (failure (autopoiesis.integration:make-provider-result :exit-code 1)))
    (is (autopoiesis.integration:result-success-p success))
    (is (not (autopoiesis.integration:result-success-p failure)))))

(test provider-result-sexpr-round-trip
  "Test provider result S-expression serialization round-trip"
  (let* ((original (autopoiesis.integration:make-provider-result
                    :provider-name "test"
                    :text "round trip"
                    :turns 5
                    :cost 0.02
                    :exit-code 0
                    :session-id "sess-123"))
         (sexpr (autopoiesis.integration:provider-result-to-sexpr original))
         (restored (autopoiesis.integration:sexpr-to-provider-result sexpr)))
    (is (string= "test" (autopoiesis.integration:provider-result-provider-name restored)))
    (is (string= "round trip" (autopoiesis.integration:provider-result-text restored)))
    (is (= 5 (autopoiesis.integration:provider-result-turns restored)))
    (is (= 0.02 (autopoiesis.integration:provider-result-cost restored)))
    (is (= 0 (autopoiesis.integration:provider-result-exit-code restored)))
    (is (string= "sess-123" (autopoiesis.integration:provider-result-session-id restored)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider-Backed Agent Tests
;;; ═══════════════════════════════════════════════════════════════════

(test provider-backed-agent-creation
  "Test creating a provider-backed agent"
  (let ((p (make-mock-provider :name "agent-test")))
    (let ((agent (autopoiesis.integration:make-provider-backed-agent
                  p :name "test-agent" :system-prompt "You are helpful")))
      (is (string= "test-agent" (autopoiesis.agent:agent-name agent)))
      (is (eq p (autopoiesis.integration:agent-provider agent)))
      (is (string= "You are helpful" (autopoiesis.integration:agent-system-prompt agent)))
      (is (eq :one-shot (autopoiesis.integration:agent-invocation-mode agent))))))

(test provider-backed-agent-creation-from-registry
  "Test creating a provider-backed agent with provider name lookup"
  (let ((autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
    (let ((p (make-mock-provider :name "reg-provider")))
      (autopoiesis.integration:register-provider p)
      (let ((agent (autopoiesis.integration:make-provider-backed-agent "reg-provider")))
        (is (eq p (autopoiesis.integration:agent-provider agent)))))))

(test provider-backed-agent-cognitive-cycle
  "Test running a cognitive cycle with mock provider"
  (let ((autopoiesis.integration:*events-enabled* nil))
    (let* ((p (make-mock-provider :name "cycle-test" :canned-output "cycle result"))
           (agent (autopoiesis.integration:make-provider-backed-agent
                   p :name "cycle-agent")))
      (autopoiesis.agent:start-agent agent)
      (let ((result (autopoiesis.agent:cognitive-cycle agent "test prompt")))
        (is (not (null result)))
        (is (typep result 'autopoiesis.integration:provider-result))
        (is (string= "cycle result" (autopoiesis.integration:provider-result-text result)))
        (is (= 1 (mock-invoke-count p)))))))

(test provider-backed-agent-thought-recording
  "Test that provider exchange is recorded in thought stream"
  (let ((autopoiesis.integration:*events-enabled* nil))
    (let* ((p (make-mock-provider
               :name "thought-test"
               :canned-output "thought result"
               :canned-tool-calls (list (list :name "read_file" :input "/tmp/test"))))
           (agent (autopoiesis.integration:make-provider-backed-agent
                   p :name "thought-agent")))
      (autopoiesis.agent:start-agent agent)
      (autopoiesis.agent:cognitive-cycle agent "record test")
      ;; Should have thoughts: decision + observation(prompt) + action(tool) +
      ;; observation(result) + reflection(summary) + reflection(outcome)
      (let ((count (autopoiesis.core:stream-length
                    (autopoiesis.agent:agent-thought-stream agent))))
        ;; At minimum: decision, prompt obs, tool action, result obs, summary reflection, outcome reflection
        (is (>= count 4))))))

(test provider-agent-prompt-convenience
  "Test provider-agent-prompt convenience function"
  (let ((autopoiesis.integration:*events-enabled* nil))
    (let* ((p (make-mock-provider :name "prompt-test" :canned-output "prompt result"))
           (agent (autopoiesis.integration:make-provider-backed-agent
                   p :name "prompt-agent")))
      (let ((result (autopoiesis.integration:provider-agent-prompt agent "hello")))
        (is (not (null result)))
        (is (string= "prompt result" (autopoiesis.integration:provider-result-text result)))
        ;; With prompt registry, system prompt may be prepended
        (is (search "hello" (mock-last-prompt p)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Command Building Tests
;;; ═══════════════════════════════════════════════════════════════════

(test claude-code-command-building
  "Test Claude Code provider command building"
  (let ((p (autopoiesis.integration:make-claude-code-provider
            :max-turns 5 :skip-permissions t)))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test prompt")
      (is (string= "claude" cmd))
      (is (member "-p" args :test #'string=))
      (is (member "--output-format" args :test #'string=))
      (is (member "--dangerously-skip-permissions" args :test #'string=))
      (is (member "--max-turns" args :test #'string=)))))

(test codex-command-building
  "Test Codex provider command building"
  (let ((p (autopoiesis.integration:make-codex-provider :full-auto t)))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test prompt")
      (is (string= "codex" cmd))
      (is (member "exec" args :test #'string=))
      (is (member "--json" args :test #'string=))
      (is (member "--full-auto" args :test #'string=))
      ;; Verify no invalid flags
      (is (not (member "--ask-for-approval" args :test #'string=))))))

(test opencode-command-building
  "Test OpenCode provider command building"
  (let ((p (autopoiesis.integration:make-opencode-provider)))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test prompt")
      (is (string= "opencode" cmd))
      (is (member "run" args :test #'string=))
      (is (member "--format" args :test #'string=)))))

(test cursor-command-building
  "Test Cursor provider command building"
  (let ((p (autopoiesis.integration:make-cursor-provider :force t)))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test prompt")
      (is (string= "cursor-agent" cmd))
      (is (member "-p" args :test #'string=))
      (is (member "--output-format" args :test #'string=))
      (is (member "--force" args :test #'string=)))))

(test nanobot-provider-creation
  "Test NanoBot provider creation and slot defaults"
  (let ((p (autopoiesis.integration:make-nanobot-provider
            :workspace "/tmp/test")))
    (is (not (null p)))
    (is (string= "nanobot" (autopoiesis.integration:provider-name p)))
    (is (string= "nanobot" (autopoiesis.integration:provider-command p)))
    (is (string= "/tmp/test" (autopoiesis.integration:nanobot-workspace p)))))

(test nanobot-provider-build-command
  "Test NanoBot provider command building"
  (let ((p (autopoiesis.integration:make-nanobot-provider
            :workspace "/tmp/ws")))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "do stuff")
      (is (string= "nanobot" cmd))
      (is (member "agent" args :test #'string=))
      (is (member "--no-markdown" args :test #'string=))
      (is (member "-m" args :test #'string=))
      (is (member "--workspace" args :test #'string=)))))

(test nanosquash-provider-creation
  "Test Nanosquash provider creation and slot defaults"
  (let ((p (autopoiesis.integration:make-nanosquash-provider
            :layers #("000-base-alpine"))))
    (is (not (null p)))
    (is (string= "nanosquash" (autopoiesis.integration:provider-name p)))
    (is (string= "nanosquash" (autopoiesis.integration:provider-command p)))
    (is (equalp #("000-base-alpine") (autopoiesis.integration:nanosquash-layers p)))
    (is (eq t (autopoiesis.integration:nanosquash-ephemeral p)))
    (is (null (autopoiesis.integration:nanosquash-sandbox-id p)))))

(test nanosquash-native-p-check
  "Test nanosquash-native-p returns nil when cl-nanosquash not loaded"
  (is (null (autopoiesis.integration:nanosquash-native-p))))

(test nanosquash-provider-serialization
  "Test nanosquash provider serialization round-trip"
  (let ((p (autopoiesis.integration:make-nanosquash-provider
            :name "ns-test" :sandbox-id "test-box"
            :layers #("layer1") :ephemeral nil)))
    (let ((sexpr (autopoiesis.integration:provider-to-sexpr p)))
      (is (eq :provider (first sexpr)))
      (is (string= "ns-test" (getf (rest sexpr) :name)))
      (is (string= "test-box" (getf (rest sexpr) :sandbox-id)))
      (is (equalp #("layer1") (getf (rest sexpr) :layers)))
      (is (null (getf (rest sexpr) :ephemeral))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tool Formatting Tests
;;; ═══════════════════════════════════════════════════════════════════

(test provider-tool-formatting
  "Test provider tool name extraction"
  (let ((p (make-mock-provider)))
    (let ((tools (list '(("name" . "read_file") ("description" . "Read a file"))
                       '(("name" . "write_file") ("description" . "Write a file")))))
      (let ((names (autopoiesis.integration:provider-format-tools p tools)))
        (is (= 2 (length names)))
        (is (member "read_file" names :test #'string=))
        (is (member "write_file" names :test #'string=))))))

(test provider-tool-formatting-strings
  "Test provider tool formatting with string inputs"
  (let ((p (make-mock-provider)))
    (let ((names (autopoiesis.integration:provider-format-tools
                  p (list "read_file" "write_file"))))
      (is (= 2 (length names)))
      (is (member "read_file" names :test #'string=)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Serialization Tests
;;; ═══════════════════════════════════════════════════════════════════

(test provider-serialization
  "Test provider serialization to S-expression"
  (let ((p (autopoiesis.integration:make-claude-code-provider
            :name "ser-test" :max-turns 5 :timeout 60)))
    (let ((sexpr (autopoiesis.integration:provider-to-sexpr p)))
      (is (eq :provider (first sexpr)))
      (is (string= "ser-test" (getf (rest sexpr) :name)))
      (is (= 5 (getf (rest sexpr) :max-turns)))
      (is (= 60 (getf (rest sexpr) :timeout))))))

(test provider-backed-agent-serialization
  "Test provider-backed agent serialization"
  (let ((p (autopoiesis.integration:make-claude-code-provider :name "ser-agent")))
    (let* ((agent (autopoiesis.integration:make-provider-backed-agent
                   p :name "my-agent" :system-prompt "Be helpful"))
           (sexpr (autopoiesis.integration:provider-backed-agent-to-sexpr agent)))
      (is (eq :provider-backed-agent (first sexpr)))
      (is (string= "my-agent" (getf (rest sexpr) :name)))
      (is (string= "Be helpful" (getf (rest sexpr) :system-prompt))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Status Tests
;;; ═══════════════════════════════════════════════════════════════════

(test provider-status
  "Test provider status reporting"
  (let ((p (autopoiesis.integration:make-claude-code-provider :name "status-test")))
    (let ((status (autopoiesis.integration:provider-status p)))
      (is (string= "status-test" (getf status :name)))
      (is (string= "claude" (getf status :command)))
      (is (member :one-shot (getf status :modes)))
      (is (not (getf status :alive))))))

(test provider-supported-modes
  "Test provider supported modes"
  (is (member :one-shot (autopoiesis.integration:provider-supported-modes
                          (autopoiesis.integration:make-claude-code-provider))))
  (is (member :streaming (autopoiesis.integration:provider-supported-modes
                           (autopoiesis.integration:make-claude-code-provider))))
  (is (equal '(:one-shot) (autopoiesis.integration:provider-supported-modes
                             (autopoiesis.integration:make-codex-provider))))
  (is (equal '(:one-shot) (autopoiesis.integration:provider-supported-modes
                             (autopoiesis.integration:make-cursor-provider))))
  (is (equal '(:one-shot) (autopoiesis.integration:provider-supported-modes
                             (autopoiesis.integration:make-nanobot-provider))))
  (is (equal '(:one-shot) (autopoiesis.integration:provider-supported-modes
                             (autopoiesis.integration:make-nanosquash-provider)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Pi Provider Tests
;;; ═══════════════════════════════════════════════════════════════════

(test pi-provider-creation
  "Test Pi provider creation and defaults"
  (let ((p (autopoiesis.integration:make-pi-provider)))
    (is (string= "pi" (autopoiesis.integration:provider-name p)))
    (is (string= "pi" (autopoiesis.integration:provider-command p)))
    (is (null (autopoiesis.integration:pi-thinking p)))
    (is (string= "safe" (autopoiesis.integration:pi-extension-policy p)))))

(test pi-provider-creation-with-options
  "Test Pi provider creation with custom options"
  (let ((p (autopoiesis.integration:make-pi-provider
            :thinking "medium" :extension-policy "balanced"
            :default-model "gpt-4o")))
    (is (string= "medium" (autopoiesis.integration:pi-thinking p)))
    (is (string= "balanced" (autopoiesis.integration:pi-extension-policy p)))
    (is (string= "gpt-4o" (autopoiesis.integration:provider-default-model p)))))

(test pi-command-building
  "Test Pi provider command building"
  (let ((p (autopoiesis.integration:make-pi-provider :thinking "high")))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "fix the bug")
      (is (string= "pi" cmd))
      (is (member "-p" args :test #'string=))
      (is (member "--mode" args :test #'string=))
      (is (member "json" args :test #'string=))
      (is (member "--thinking" args :test #'string=))
      (is (member "high" args :test #'string=)))))

(test pi-command-building-with-tools
  "Test Pi provider command building with tools"
  (let ((p (autopoiesis.integration:make-pi-provider)))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test"
                                                        :tools (list "read_file" "write_file"))
      (declare (ignore cmd))
      (is (member "--tools" args :test #'string=))
      ;; Tools should be comma-separated
      (let ((tools-pos (position "--tools" args :test #'string=)))
        (when tools-pos
          (let ((tools-val (nth (1+ tools-pos) args)))
            (is (search "read_file" tools-val))
            (is (search "write_file" tools-val))))))))

(test pi-command-building-with-model
  "Test Pi provider command building with model"
  (let ((p (autopoiesis.integration:make-pi-provider :default-model "claude-sonnet")))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test")
      (declare (ignore cmd))
      (is (member "--model" args :test #'string=))
      (is (member "claude-sonnet" args :test #'string=)))))

(test pi-supported-modes
  "Test Pi provider supported modes"
  (let ((p (autopoiesis.integration:make-pi-provider)))
    (is (member :one-shot (autopoiesis.integration:provider-supported-modes p)))
    (is (member :streaming (autopoiesis.integration:provider-supported-modes p)))))

(test pi-provider-serialization
  "Test Pi provider serialization"
  (let* ((p (autopoiesis.integration:make-pi-provider
             :thinking "medium" :extension-policy "balanced"))
         (sexpr (autopoiesis.integration:provider-to-sexpr p)))
    (is (eq :provider (first sexpr)))
    (is (string= "pi" (getf (rest sexpr) :name)))
    (is (string= "medium" (getf (rest sexpr) :thinking)))
    (is (string= "balanced" (getf (rest sexpr) :extension-policy)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Enhanced OpenCode Provider Tests
;;; ═══════════════════════════════════════════════════════════════════

(test opencode-enhanced-command-building
  "Test OpenCode provider enhanced command building with agent-mode and no-tui"
  (let ((p (autopoiesis.integration:make-opencode-provider
            :agent-mode "debug" :no-tui t)))
    (multiple-value-bind (cmd args)
        (autopoiesis.integration:provider-build-command p "test prompt")
      (is (string= "opencode" cmd))
      (is (member "run" args :test #'string=))
      (is (member "--no-tui" args :test #'string=))
      (is (member "--agent" args :test #'string=))
      (is (member "debug" args :test #'string=)))))

(test opencode-agent-mode-default
  "Test OpenCode provider default agent mode"
  (let ((p (autopoiesis.integration:make-opencode-provider)))
    (is (string= "build" (autopoiesis.integration:opencode-agent-mode p)))
    (is (eq t (autopoiesis.integration:opencode-no-tui p)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Meta-Dispatcher Tests
;;; ═══════════════════════════════════════════════════════════════════

(test select-coding-backend-default
  "Test select-coding-backend returns :claude-code for general prompts"
  (is (eq :claude-code (autopoiesis.integration:select-coding-backend "fix the login bug")))
  (is (eq :claude-code (autopoiesis.integration:select-coding-backend "add a new endpoint"))))

(test select-coding-backend-pi
  "Test select-coding-backend returns :pi for refactoring tasks"
  (is (eq :pi (autopoiesis.integration:select-coding-backend "refactor all files in src/")))
  (is (eq :pi (autopoiesis.integration:select-coding-backend "migrate from v1 to v2 API")))
  (is (eq :pi (autopoiesis.integration:select-coding-backend "rewrite the parser module"))))

(test select-coding-backend-opencode
  "Test select-coding-backend returns :opencode for GitHub tasks"
  (is (eq :opencode (autopoiesis.integration:select-coding-backend "create a PR for this change")))
  (is (eq :opencode (autopoiesis.integration:select-coding-backend "open an issue for the bug")))
  (is (eq :opencode (autopoiesis.integration:select-coding-backend "review the PR #42"))))

(test ensure-coding-provider-creates
  "Test ensure-coding-provider creates and registers providers"
  (let ((autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
    (let ((p (autopoiesis.integration:ensure-coding-provider :pi)))
      (is (typep p 'autopoiesis.integration:pi-provider))
      ;; Should be registered now
      (is (eq p (autopoiesis.integration:find-provider "pi"))))))
