;;;; builtin-tools.lisp - Built-in external tools
;;;;
;;;; Provides file system, web, and shell tools as capabilities that
;;;; agents can use to interact with the external environment.
;;;;
;;;; Note: All parameters are keyword parameters to be compatible with
;;;; Claude tool invocation which always passes arguments as keywords.

(in-package #:autopoiesis.integration)

;;; Phase 5: Orchestration state
(defvar *sub-agents* (make-hash-table :test 'equal)
  "Registry of spawned sub-agents. Maps agent-id to status plist.")

(defvar *orchestration-requests* nil
  "Queue of orchestration requests for the bridge.
   Drained by the agent-worker after each agentic turn.")

(defvar *session-directory* nil
  "Directory for persisting sessions. Set by agent-worker on init.")

;;; ═══════════════════════════════════════════════════════════════════
;;; File System Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability read-file (&key path start-line end-line)
  "Read contents of a file at PATH.

   Optional START-LINE and END-LINE parameters allow reading a range of lines.
   Returns the file contents as a string, or an error message on failure."
  :permissions (:file-read)
  :body
  (handler-case
      (if (not (probe-file path))
          (format nil "Error: File not found: ~a" path)
          (with-open-file (in path :direction :input)
            (let ((lines (loop for line = (read-line in nil nil)
                               for i from 1
                               while line
                               when (and (or (null start-line) (>= i start-line))
                                         (or (null end-line) (<= i end-line)))
                               collect line)))
              (format nil "~{~a~^~%~}" lines))))
    (error (e)
      (format nil "Error reading file ~a: ~a" path e))))

(autopoiesis.agent:defcapability write-file (&key path content)
  "Write CONTENT to file at PATH.

   Creates parent directories if they don't exist.
   Returns a success message or an error message on failure."
  :permissions (:file-write)
  :body
  (handler-case
      (progn
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
          (write-string content out))
        (format nil "Successfully wrote ~a bytes to ~a"
                (length content) path))
    (error (e)
      (format nil "Error writing file ~a: ~a" path e))))

(autopoiesis.agent:defcapability list-directory (&key path pattern recursive)
  "List contents of directory at PATH.

   Optional PATTERN is a glob pattern to filter results (default '*').
   If RECURSIVE is true, searches subdirectories too.
   Returns a newline-separated list of file paths."
  :permissions (:file-read)
  :body
  (handler-case
      (let* ((dir-path (if (char= (char path (1- (length path))) #\/)
                           path
                           (concatenate 'string path "/")))
             (wild-path (merge-pathnames (or pattern "*.*")
                                         (pathname dir-path)))
             (entries (if recursive
                          (directory (make-pathname
                                      :defaults wild-path
                                      :directory (append (pathname-directory wild-path)
                                                        '(:wild-inferiors))))
                          (directory wild-path))))
        (if entries
            (format nil "~{~a~^~%~}" (mapcar #'namestring entries))
            "No files found"))
    (error (e)
      (format nil "Error listing directory ~a: ~a" path e))))

(autopoiesis.agent:defcapability file-exists-p (&key path)
  "Check if a file exists at PATH.

   Returns 'true' if the file exists, 'false' otherwise."
  :permissions (:file-read)
  :body
  (if (probe-file path) "true" "false"))

(autopoiesis.agent:defcapability delete-file-tool (&key path)
  "Delete the file at PATH.

   Returns a success message or an error message on failure."
  :permissions (:file-write)
  :body
  (handler-case
      (progn
        (delete-file path)
        (format nil "Successfully deleted ~a" path))
    (file-error (e)
      (format nil "Error deleting ~a: ~a" path e))))

(autopoiesis.agent:defcapability glob-files (&key pattern base-directory)
  "Find files matching PATTERN.

   BASE-DIRECTORY defaults to current working directory.
   Returns a newline-separated list of matching file paths."
  :permissions (:file-read)
  :body
  (handler-case
      (let* ((base (or base-directory (uiop:getcwd)))
             (full-pattern (merge-pathnames pattern base))
             (matches (directory full-pattern)))
        (if matches
            (format nil "~{~a~^~%~}" (mapcar #'namestring matches))
            "No matches found"))
    (error (e)
      (format nil "Error searching for ~a: ~a" pattern e))))

(autopoiesis.agent:defcapability grep-files (&key pattern path file-pattern)
  "Search for PATTERN in files.

   PATH is the directory to search (default: current directory).
   FILE-PATTERN is a glob to filter files (default: '**/*').
   Returns matching lines with file:line: prefix."
  :permissions (:file-read)
  :body
  (handler-case
      (let ((results nil)
            (search-path (or path (uiop:getcwd)))
            (file-glob (or file-pattern "**/*")))
        (dolist (file (directory (merge-pathnames file-glob search-path)))
          (when (and (probe-file file)
                     (not (uiop:directory-pathname-p file)))
            (handler-case
                (with-open-file (in file :direction :input)
                  (loop for line = (read-line in nil nil)
                        for line-num from 1
                        while line
                        when (search pattern line)
                        do (push (format nil "~a:~a: ~a"
                                         (namestring file) line-num line)
                                 results)))
              (error () nil))))  ; Skip unreadable files
        (if results
            (format nil "~{~a~^~%~}" (nreverse results))
            "No matches found"))
    (error (e)
      (format nil "Error searching: ~a" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Web Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability web-fetch (&key url method headers body)
  "Fetch content from URL.

   METHOD defaults to :GET.
   HEADERS is an alist of header name-value pairs.
   BODY is the request body (for POST/PUT/etc).
   Returns the response body as a string, or an error message."
  :permissions (:network)
  :body
  (handler-case
      (let* ((method-key (if method
                             (intern (string-upcase method) :keyword)
                             :get))
             (response (dex:request url
                                    :method method-key
                                    :headers headers
                                    :content body)))
        (if (stringp response)
            response
            (babel:octets-to-string response :encoding :utf-8)))
    (dex:http-request-failed (e)
      (format nil "HTTP request failed (~a): ~a"
              (dex:response-status e)
              (dex:response-body e)))
    (error (e)
      (format nil "Error fetching ~a: ~a" url e))))

(autopoiesis.agent:defcapability web-head (&key url headers)
  "Perform a HEAD request to URL.

   Returns response headers as a string, or an error message."
  :permissions (:network)
  :body
  (handler-case
      (multiple-value-bind (body status headers)
          (dex:head url :headers headers)
        (declare (ignore body))
        (format nil "Status: ~a~%Headers:~%~{~a: ~a~^~%~}"
                status
                (loop for (k . v) in headers
                      collect k collect v)))
    (error (e)
      (format nil "Error fetching ~a: ~a" url e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Shell Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability run-command (&key command working-directory timeout)
  "Run a shell command.

   WORKING-DIRECTORY defaults to current directory.
   TIMEOUT in seconds (default: no timeout).
   Returns command output (stdout + stderr combined) as a string."
  :permissions (:shell)
  :body
  (handler-case
      (let* ((dir (or working-directory (uiop:getcwd))))
        (multiple-value-bind (output error-output exit-code)
            (uiop:run-program command
                              :directory dir
                              :output :string
                              :error-output :string
                              :ignore-error-status t)
          (let ((result (if (and error-output (> (length error-output) 0))
                            (format nil "~a~%~a" output error-output)
                            output)))
            (if (zerop exit-code)
                result
                (format nil "~a~%[Exit code: ~a]" result exit-code)))))
    (error (e)
      (format nil "Error running command: ~a" e))))

(autopoiesis.agent:defcapability git-status (&key directory)
  "Get git status.

   DIRECTORY defaults to current working directory.
   Returns porcelain status output."
  :permissions (:shell)
  :body
  (funcall (autopoiesis.agent:capability-function
            (autopoiesis.agent:find-capability 'run-command))
           :command "git status --porcelain"
           :working-directory directory))

(autopoiesis.agent:defcapability git-diff (&key directory staged)
  "Get git diff.

   DIRECTORY defaults to current working directory.
   If STAGED is true, shows staged changes only.
   Returns diff output."
  :permissions (:shell)
  :body
  (funcall (autopoiesis.agent:capability-function
            (autopoiesis.agent:find-capability 'run-command))
           :command (if staged "git diff --staged" "git diff")
           :working-directory directory))

(autopoiesis.agent:defcapability git-log (&key directory count format-string)
  "Get git log.

   DIRECTORY defaults to current working directory.
   COUNT limits the number of commits (default: 10).
   FORMAT-STRING customizes output format (default: oneline).
   Returns log output."
  :permissions (:shell)
  :body
  (let ((n (or count 10))
        (fmt (or format-string "oneline")))
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'run-command))
             :command (format nil "git log -~a --format=~a" n fmt)
             :working-directory directory)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Self-Extension Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability define-capability-tool (&key name description parameters code)
  "Define a new capability by writing Lisp code.

   NAME - String name for the new capability (e.g., \"calculate-sum\")
   DESCRIPTION - Human-readable description of what the capability does
   PARAMETERS - S-expression string describing parameters as ((name type) ...)
                e.g., \"((numbers list))\" or \"((x integer) (y integer))\"
   CODE - S-expression string of the implementation body
          e.g., \"(reduce #'+ numbers)\" or \"(+ x y)\"
          Code is validated against the sandbox whitelist before compilation.

   Returns a success message with the capability name, or an error message."
  :permissions (:self-extend)
  :body
  (handler-case
      (let* ((cap-name (intern (string-upcase name) :keyword))
             (parsed-params (read-from-string parameters))
             (parsed-code (read-from-string code))
             (body-forms (if (and (consp parsed-code)
                                  (consp (car parsed-code)))
                             ;; Multiple forms: ((form1) (form2))
                             parsed-code
                             ;; Single form: (form)
                             (list parsed-code))))
        ;; Use a minimal agent for the definition workflow.
        ;; The capability gets added to the agent AND registered globally
        ;; so that test-capability and promote-capability can find it.
        (let ((temp-agent (make-instance 'autopoiesis.agent:agent
                                         :name "extension-definer")))
          (multiple-value-bind (cap errors)
              (autopoiesis.agent:agent-define-capability
               temp-agent cap-name description parsed-params body-forms)
            (if cap
                (progn
                  ;; Register in global registry so test/promote can find it
                  (autopoiesis.agent:register-capability cap)
                  (format nil "Capability ~a defined successfully (status: ~a). Use test_capability_tool to test it before promoting."
                          name (autopoiesis.agent:cap-promotion-status cap)))
                (format nil "Error defining capability ~a: ~{~a~^; ~}" name errors)))))
    (error (e)
      (format nil "Error: ~a" e))))

(autopoiesis.agent:defcapability test-capability-tool (&key name test-cases)
  "Test a previously defined capability with test cases.

   NAME - String name of the capability to test (e.g., \"calculate-sum\")
   TEST-CASES - S-expression string of test cases as ((input expected) ...)
                e.g., \"(((2 3) 5) ((10 20) 30))\"
                Each test case is (input expected-output) where input is
                passed to the capability and result is compared to expected.

   Returns test results showing pass/fail for each case."
  :permissions (:self-extend)
  :body
  (handler-case
      (let* ((cap-name (intern (string-upcase name) :keyword))
             (parsed-tests (read-from-string test-cases))
             (cap (autopoiesis.agent:find-capability cap-name)))
        (if (not cap)
            (format nil "Error: Capability ~a not found in registry" name)
            (if (not (typep cap 'autopoiesis.agent:agent-capability))
                (format nil "Error: ~a is a built-in capability and cannot be tested this way" name)
                (multiple-value-bind (passed-p results)
                    (autopoiesis.agent:test-agent-capability cap parsed-tests)
                  (format nil "~a: ~a~%~{  ~a~^~%~}"
                          name
                          (if passed-p "ALL TESTS PASSED" "SOME TESTS FAILED")
                          (mapcar (lambda (r)
                                    (format nil "[~a] input=~s expected=~s~a"
                                            (getf r :status)
                                            (getf r :input)
                                            (getf r :expected)
                                            (if (eq (getf r :status) :error)
                                                (format nil " error=~a" (getf r :error))
                                                (format nil " actual=~s" (getf r :actual)))))
                                  results))))))
    (error (e)
      (format nil "Error: ~a" e))))

(autopoiesis.agent:defcapability promote-capability-tool (&key name)
  "Promote a tested capability to the global registry.

   NAME - String name of the capability to promote (e.g., \"calculate-sum\")

   The capability must have been tested first (via test_capability) and all
   tests must have passed. On success, the capability becomes globally
   available as a tool in subsequent agentic loop turns.

   Returns a success or failure message."
  :permissions (:self-extend)
  :body
  (handler-case
      (let* ((cap-name (intern (string-upcase name) :keyword))
             (cap (autopoiesis.agent:find-capability cap-name)))
        (if (not cap)
            (format nil "Error: Capability ~a not found" name)
            (if (not (typep cap 'autopoiesis.agent:agent-capability))
                (format nil "Error: ~a is a built-in capability and cannot be promoted" name)
                (if (autopoiesis.agent:promote-capability cap)
                    (format nil "Capability ~a promoted to global registry. It is now available as a tool."
                            name)
                    (format nil "Error: Cannot promote ~a. Status is ~a (must be :testing with all tests passing)."
                            name (autopoiesis.agent:cap-promotion-status cap))))))
    (error (e)
      (format nil "Error: ~a" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Introspection Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability list-capabilities-tool (&key filter)
  "List all available capabilities with descriptions.

   FILTER - Optional string to filter capabilities by name (case-insensitive).

   Returns a formatted list of all capabilities showing name, description,
   and parameters."
  :permissions ()
  :body
  (let* ((all-caps (autopoiesis.agent:list-capabilities))
         (filtered (if filter
                       (remove-if-not
                        (lambda (cap)
                          (search (string-upcase filter)
                                  (string-upcase (string (autopoiesis.agent:capability-name cap)))))
                        all-caps)
                       all-caps)))
    (if (null filtered)
        "No capabilities found."
        (format nil "~{~a~^~%~%~}"
                (mapcar (lambda (cap)
                          (format nil "~a~%  ~a~@[~%  Parameters: ~a~]~@[~%  [agent-defined, status: ~a]~]"
                                  (autopoiesis.agent:capability-name cap)
                                  (or (autopoiesis.agent:capability-description cap) "(no description)")
                                  (autopoiesis.agent:capability-parameters cap)
                                  (when (typep cap 'autopoiesis.agent:agent-capability)
                                    (autopoiesis.agent:cap-promotion-status cap))))
                        filtered)))))

(autopoiesis.agent:defcapability inspect-thoughts (&key count agent-name)
  "Inspect recent thoughts from an agent's thought stream.

   COUNT - Number of recent thoughts to return (default: 10)
   AGENT-NAME - Not currently used (reserved for multi-agent introspection)

   Returns a formatted list of recent thoughts showing type, content,
   and timestamp."
  :permissions ()
  :body
  (declare (ignore agent-name))
  (let ((n (or count 10)))
    ;; Since this tool runs in the context of an agentic loop without
    ;; direct access to the calling agent, return a message about usage.
    ;; In practice, the agent can access its own thought stream.
    (format nil "inspect-thoughts: This tool provides thought stream introspection.~%To inspect thoughts, the agent should use its own thought-stream via the cognitive loop.~%Requested last ~a thoughts." n)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Orchestration Tools (Phase 5: Meta-Agent)
;;; ═══════════════════════════════════════════════════════════════════

(defun queue-orchestration-request (request)
  "Add an orchestration request to the pending queue."
  (push request *orchestration-requests*))

(defun drain-orchestration-requests ()
  "Return and clear all pending orchestration requests."
  (prog1 (nreverse *orchestration-requests*)
    (setf *orchestration-requests* nil)))

(defun update-sub-agent (agent-id &rest plist)
  "Update a sub-agent's status in the registry."
  (let ((existing (or (gethash agent-id *sub-agents*) nil)))
    (loop for (k v) on plist by #'cddr
          do (setf (getf existing k) v))
    (setf (gethash agent-id *sub-agents*) existing)))

(autopoiesis.agent:defcapability spawn-agent (&key name task capabilities system-prompt max-turns)
  "Spawn a new agent to work on TASK under LFE supervision.
   NAME - Human-readable name for the agent.
   TASK - Description of the work to perform.
   CAPABILITIES - List of capability keywords the sub-agent can use.
   SYSTEM-PROMPT - Override the default system prompt.
   MAX-TURNS - Limit agentic loop iterations (default 25).
   Returns an agent-id for monitoring via query_agent and await_agent."
  :permissions (:orchestration)
  :body
  (declare (ignore system-prompt))
  (let ((agent-id (format nil "sub-~A-~A"
                          (or name "agent")
                          (autopoiesis.core:make-uuid))))
    (update-sub-agent agent-id
                      :status :spawning
                      :task task
                      :name (or name "sub-agent")
                      :started (get-universal-time))
    (queue-orchestration-request
     (list :type :spawn-agent
           :agent-id agent-id
           :name (or name "sub-agent")
           :task (or task "")
           :capabilities capabilities
           :max-turns (or max-turns 25)))
    (format nil "Spawning agent '~A' with ID ~A to work on: ~A~%Use query_agent with agent-id \"~A\" to check status."
            (or name "sub-agent") agent-id (or task "(no task)") agent-id)))

(autopoiesis.agent:defcapability query-agent (&key agent-id)
  "Check status of a spawned sub-agent.
   AGENT-ID - The ID returned by spawn_agent.
   Returns status, task, elapsed time, and result if complete."
  :permissions (:orchestration)
  :body
  (let ((info (gethash agent-id *sub-agents*)))
    (if (not info)
        (format nil "Error: Agent ~A not found in registry" agent-id)
        (let ((status (getf info :status))
              (task (getf info :task))
              (started (getf info :started))
              (result (getf info :result)))
          (format nil "Agent: ~A~%Status: ~A~%Task: ~A~%Elapsed: ~As~@[~%Result: ~A~]"
                  agent-id status task
                  (if started (- (get-universal-time) started) 0)
                  result)))))

(autopoiesis.agent:defcapability await-agent (&key agent-id timeout)
  "Wait for a spawned agent to complete its task.
   AGENT-ID - The ID returned by spawn_agent.
   TIMEOUT - Seconds to wait (default 300).
   Returns the agent's result when complete."
  :permissions (:orchestration)
  :body
  (let ((max-wait (or timeout 300))
        (info (gethash agent-id *sub-agents*)))
    (cond
      ((not info)
       (format nil "Error: Agent ~A not found" agent-id))
      ((member (getf info :status) '(:complete :failed))
       (format nil "Agent ~A ~(~A~): ~A" agent-id (getf info :status)
               (or (getf info :result) (getf info :error) "(no details)")))
      (t
       (loop for elapsed from 0 by 2
             while (< elapsed max-wait)
             do (sleep 2)
                (let ((current (gethash agent-id *sub-agents*)))
                  (when (and current (member (getf current :status) '(:complete :failed)))
                    (return (format nil "Agent ~A ~(~A~): ~A" agent-id
                                    (getf current :status)
                                    (or (getf current :result) (getf current :error))))))
             finally (return (format nil "Timeout: agent ~A still ~(~A~) after ~As"
                                     agent-id (getf info :status) max-wait)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cognitive Branching Tools (Phase 5: Meta-Agent)
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability fork-branch (&key name from-snapshot)
  "Create a cognitive branch.
   NAME - Name for the new branch.
   FROM-SNAPSHOT - Optional snapshot ID to branch from.
   Returns branch creation info."
  :permissions ()
  :body
  (handler-case
      (progn
        (autopoiesis.snapshot:create-branch name :from-snapshot from-snapshot)
        (format nil "Branch '~A' created~@[ from snapshot ~A~]" name from-snapshot))
    (error (e)
      (format nil "Error creating branch: ~A" e))))

(autopoiesis.agent:defcapability compare-branches (&key branch-a branch-b)
  "Compare two cognitive branches to see how they diverged.
   BRANCH-A - Name of the first branch.
   BRANCH-B - Name of the second branch.
   Returns a diff of the two branch heads."
  :permissions ()
  :body
  (handler-case
      (let* ((branches (autopoiesis.snapshot:list-branches))
             (a (find branch-a branches :key #'autopoiesis.snapshot:branch-name :test #'string=))
             (b (find branch-b branches :key #'autopoiesis.snapshot:branch-name :test #'string=)))
        (cond
          ((not a) (format nil "Error: Branch ~A not found" branch-a))
          ((not b) (format nil "Error: Branch ~A not found" branch-b))
          ((not (autopoiesis.snapshot:branch-head a))
           (format nil "Error: Branch ~A has no snapshots" branch-a))
          ((not (autopoiesis.snapshot:branch-head b))
           (format nil "Error: Branch ~A has no snapshots" branch-b))
          (t
           (let* ((snap-a (autopoiesis.snapshot:load-snapshot (autopoiesis.snapshot:branch-head a)))
                  (snap-b (autopoiesis.snapshot:load-snapshot (autopoiesis.snapshot:branch-head b)))
                  (edits (autopoiesis.core:sexpr-diff
                          (autopoiesis.snapshot:snapshot-agent-state snap-a)
                          (autopoiesis.snapshot:snapshot-agent-state snap-b))))
             (format nil "Comparing ~A (head: ~A) vs ~A (head: ~A):~%~A edit~:P~%~{  ~A~^~%~}"
                     branch-a (autopoiesis.snapshot:branch-head a)
                     branch-b (autopoiesis.snapshot:branch-head b)
                     (length edits)
                     (mapcar #'princ-to-string edits))))))
    (error (e)
      (format nil "Error comparing branches: ~A" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Management Tools (Phase 5: Meta-Agent)
;;; ═══════════════════════════════════════════════════════════════════

(defun ensure-session-directory ()
  "Ensure session directory exists and return it."
  (let ((dir (or *session-directory*
                 (merge-pathnames "autopoiesis-sessions/"
                                  (uiop:temporary-directory)))))
    (ensure-directories-exist dir)
    dir))

(autopoiesis.agent:defcapability save-session (&key name)
  "Save the current session state for later resumption.
   NAME - A human-readable name for this session.
   Sends a save request through the bridge protocol.
   Returns the session name for use with resume_session."
  :permissions ()
  :body
  (let ((session-id (or name (format nil "session-~A" (autopoiesis.core:make-uuid)))))
    (queue-orchestration-request
     (list :type :save-session :name session-id))
    (format nil "Session save requested as '~A'" session-id)))

(autopoiesis.agent:defcapability resume-session (&key name)
  "Resume a previously saved session.
   NAME - The session name/ID from save_session.
   Sends a resume request through the bridge protocol."
  :permissions ()
  :body
  (queue-orchestration-request
   (list :type :resume-session :name name))
  (format nil "Session resume requested for '~A'" name))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tool Registration
;;; ═══════════════════════════════════════════════════════════════════

(defvar *builtin-tools-registered* nil
  "Flag indicating whether builtin tools have been registered.")

(defun builtin-tool-symbols ()
  "Return a list of all builtin tool symbols (in this package).

   These are the actual symbols used as capability names by defcapability."
  '(read-file write-file list-directory file-exists-p
    delete-file-tool glob-files grep-files
    web-fetch web-head
    run-command git-status git-diff git-log
    ;; Self-extension tools
    define-capability-tool test-capability-tool promote-capability-tool
    ;; Introspection tools
    list-capabilities-tool inspect-thoughts
    ;; Orchestration tools (Phase 5)
    spawn-agent query-agent await-agent
    ;; Cognitive branching tools (Phase 5)
    fork-branch compare-branches
    ;; Session management tools (Phase 5)
    save-session resume-session))

(defun register-builtin-tools (&key (registry autopoiesis.agent:*capability-registry*))
  "Register all built-in tools in the capability registry.

   REGISTRY defaults to the global capability registry.
   Returns the list of registered capability names.

   Note: The capabilities are registered with their symbol names from
   the autopoiesis.integration package (e.g., read-file, not :read-file)."
  (let ((registered nil))
    (dolist (name (builtin-tool-symbols))
      (let ((cap (autopoiesis.agent:find-capability name)))
        (when cap
          (autopoiesis.agent:register-capability cap :registry registry)
          (push name registered))))
    (setf *builtin-tools-registered* t)
    (nreverse registered)))

(defun unregister-builtin-tools (&key (registry autopoiesis.agent:*capability-registry*))
  "Unregister all built-in tools from the capability registry.

   REGISTRY defaults to the global capability registry."
  (dolist (name (builtin-tool-symbols))
    (autopoiesis.agent:unregister-capability name :registry registry))
  (setf *builtin-tools-registered* nil))

(defun list-builtin-tools ()
  "Return a list of all builtin tool names as symbols.

   Note: These are symbols in the autopoiesis.integration package."
  (builtin-tool-symbols))
