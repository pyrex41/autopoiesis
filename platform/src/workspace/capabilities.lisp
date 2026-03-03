;;;; capabilities.lisp - Workspace-aware file and exec capabilities
;;;;
;;;; These capabilities check *current-workspace* and route operations
;;;; through the appropriate isolation backend. When no workspace is
;;;; bound, they fall back to direct host filesystem access (same as
;;;; the original builtin-tools.lisp capabilities).
;;;;
;;;; For :sandbox isolation, the sandbox is hermetic — all reads, writes,
;;;; and exec are confined within the sandbox. To give an agent access to
;;;; host files, use :references when creating the workspace. Reference
;;;; directories are snapshotted into read-only squashfs layers and mounted
;;;; at /ref/<name>/ inside the sandbox.

(in-package #:autopoiesis.workspace)

;;; ── Workspace-Aware Operations ──────────────────────────────────
;;;
;;; These are plain functions, not capabilities. They can be called
;;; from within agentic loops, capability bodies, or user code.

(defun ws-read-file (path &key start-line end-line)
  "Read a file, resolving through the current workspace if one is bound.
   PATH can be relative (resolved against workspace root) or absolute.
   For :sandbox workspaces, reads are confined to the sandbox.
   Host files are available at /ref/<name>/ via :references.
   Returns file contents as a string."
  (if *current-workspace*
      (let ((backend (find-isolation-backend
                      (workspace-isolation *current-workspace*))))
        (handler-case
            (let ((content (backend-read-file backend *current-workspace* path)))
              (if (or start-line end-line)
                  ;; Apply line filtering
                  (let ((lines (uiop:split-string content :separator '(#\Newline))))
                    (format nil "~{~A~^~%~}"
                            (subseq lines
                                    (max 0 (1- (or start-line 1)))
                                    (min (length lines) (or end-line (length lines))))))
                  content))
          (error (e)
            (format nil "Error reading ~A: ~A" path e))))
      ;; No workspace — direct host access
      (handler-case
          (let ((full-path (if (uiop:absolute-pathname-p path)
                               path
                               (merge-pathnames path (uiop:getcwd)))))
            (if (probe-file full-path)
                (let ((content (uiop:read-file-string full-path)))
                  (if (or start-line end-line)
                      (let ((lines (uiop:split-string content :separator '(#\Newline))))
                        (format nil "~{~A~^~%~}"
                                (subseq lines
                                        (max 0 (1- (or start-line 1)))
                                        (min (length lines) (or end-line (length lines))))))
                      content))
                (format nil "Error: File not found: ~A" full-path)))
        (error (e)
          (format nil "Error reading ~A: ~A" path e)))))

(defun ws-write-file (path content)
  "Write a file, resolving through the current workspace if one is bound.
   PATH can be relative or absolute.
   Returns the resolved path on success."
  (if *current-workspace*
      (let ((backend (find-isolation-backend
                      (workspace-isolation *current-workspace*))))
        (handler-case
            (progn
              (backend-write-file backend *current-workspace* path content)
              (format nil "Wrote ~A bytes to ~A" (length content) path))
          (error (e)
            (format nil "Error writing ~A: ~A" path e))))
      ;; No workspace — direct host access
      (handler-case
          (let ((full-path (if (uiop:absolute-pathname-p path)
                               path
                               (merge-pathnames path (uiop:getcwd)))))
            (ensure-directories-exist full-path)
            (with-open-file (out full-path :direction :output
                                           :if-exists :supersede
                                           :if-does-not-exist :create)
              (write-string content out))
            (format nil "Wrote ~A bytes to ~A" (length content) full-path))
        (error (e)
          (format nil "Error writing ~A: ~A" path e)))))

(defun ws-exec (command &key (timeout 120) working-directory)
  "Execute a command in the current workspace's context.
   For :sandbox isolation, runs inside the sandbox.
   For :directory isolation, runs with workspace root as cwd.
   For :none, runs on the host.
   Returns (values stdout stderr exit-code)."
  (if *current-workspace*
      (let ((backend (find-isolation-backend
                      (workspace-isolation *current-workspace*))))
        (backend-exec backend *current-workspace* command
                      :timeout timeout
                      :working-directory working-directory))
      ;; No workspace — direct host access
      (let ((dir (or working-directory (uiop:getcwd))))
        (handler-case
            (multiple-value-bind (stdout stderr exit-code)
                (uiop:run-program command
                                  :directory dir
                                  :output :string
                                  :error-output :string
                                  :ignore-error-status t)
              (values stdout stderr exit-code))
          (error (e)
            (values "" (format nil "Error: ~A" e) -1))))))

(defun ws-list-directory (&key (path ".") pattern)
  "List directory contents within the current workspace.
   PATH is relative to workspace root (default: root itself)."
  (if *current-workspace*
      (let ((full-path (resolve-path path)))
        (handler-case
            (let ((entries (directory (merge-pathnames
                                      (or pattern "*.*")
                                      (pathname full-path)))))
              (if entries
                  (format nil "~{~A~^~%~}" (mapcar #'namestring entries))
                  "No files found"))
          (error (e)
            (format nil "Error listing ~A: ~A" path e))))
      ;; No workspace
      (handler-case
          (let ((entries (directory (merge-pathnames
                                    (or pattern "*.*")
                                    (pathname path)))))
            (if entries
                (format nil "~{~A~^~%~}" (mapcar #'namestring entries))
                "No files found"))
        (error (e)
          (format nil "Error listing ~A: ~A" path e)))))

(defun ws-file-exists-p (path)
  "Check if a file exists within the current workspace."
  (if *current-workspace*
      (let ((full-path (resolve-path path)))
        (if (probe-file full-path) t nil))
      (if (probe-file path) t nil)))

;;; ── Workspace Capabilities (for agentic agents) ────────────────
;;;
;;; These register as capabilities that agentic agents can use as tools.
;;; They delegate to the ws-* functions above.

(autopoiesis.agent:defcapability ws-read-file-cap (&key path start-line end-line)
  "Read a file within the current workspace.
   PATH can be relative to workspace root or absolute within the sandbox.
   For sandbox workspaces, host files are available at /ref/<name>/
   via the :references mechanism.
   Returns file contents as a string."
  :permissions (:file-read)
  :body
  (ws-read-file path :start-line start-line :end-line end-line))

(autopoiesis.agent:defcapability ws-write-file-cap (&key path content)
  "Write a file within the current workspace.
   PATH can be relative to workspace root or absolute.
   Creates parent directories if needed."
  :permissions (:file-write)
  :body
  (ws-write-file path content))

(autopoiesis.agent:defcapability ws-exec-cap (&key command timeout working-directory)
  "Execute a command within the current workspace.
   Commands run with the workspace root as working directory.
   For sandbox-isolated workspaces, commands run inside the sandbox."
  :permissions (:shell)
  :body
  (multiple-value-bind (stdout stderr exit-code)
      (ws-exec command :timeout (or timeout 120)
                       :working-directory working-directory)
    (let ((result (if (and stderr (> (length stderr) 0))
                      (format nil "~A~%~A" stdout stderr)
                      stdout)))
      (if (zerop exit-code)
          result
          (format nil "~A~%[Exit code: ~A]" result exit-code)))))

(autopoiesis.agent:defcapability ws-install-cap (&key packages manager)
  "Install packages within the current workspace.
   PACKAGES - Space-separated package names.
   MANAGER - Package manager: pip, npm, apk (default: pip)."
  :permissions (:shell)
  :body
  (let* ((mgr (or manager "pip"))
         (cmd (cond
                ((string= mgr "pip") (format nil "pip install --quiet ~A" packages))
                ((string= mgr "npm") (format nil "npm install -g ~A" packages))
                ((string= mgr "apk") (format nil "apk add --quiet ~A" packages))
                (t (format nil "~A install ~A" mgr packages)))))
    (multiple-value-bind (stdout stderr exit-code)
        (ws-exec cmd :timeout 300)
      (if (zerop exit-code)
          (format nil "Installed: ~A" packages)
          (format nil "Install failed (exit ~A): ~A" exit-code stderr)))))

;;; ── Team Coordination Capabilities ───────────────────────────────

(autopoiesis.agent:defcapability team-workspace-read (&key workspace-id key)
  "Read a value from the team workspace shared memory.
   WORKSPACE-ID - The workspace identifier.
   KEY - String key to read."
  :permissions (:file-read)
  :body
  (let ((value (workspace-get workspace-id key)))
    (if value
        (format nil "~S" value)
        (format nil "Key ~A not found in workspace ~A" key workspace-id))))

(autopoiesis.agent:defcapability team-workspace-write (&key workspace-id key value)
  "Write a value to the team workspace shared memory.
   WORKSPACE-ID - The workspace identifier.
   KEY - String key to write.
   VALUE - Value to store."
  :permissions (:file-write)
  :body
  (workspace-put workspace-id key value)
  (format nil "Stored ~A = ~S in workspace ~A" key value workspace-id))

(autopoiesis.agent:defcapability team-claim-task (&key workspace-id agent-id)
  "Claim the next available task from the workspace queue.
   WORKSPACE-ID - The workspace identifier.
   AGENT-ID - Optional agent ID to track who claimed the task."
  :permissions (:orchestration)
  :body
  (multiple-value-bind (task-id content)
      (workspace-claim-task workspace-id agent-id)
    (if task-id
        (format nil "Claimed task ~A: ~A" task-id content)
        (format nil "No pending tasks in workspace ~A" workspace-id))))

(autopoiesis.agent:defcapability team-submit-result (&key task-id result)
  "Submit a result for a previously claimed task.
   TASK-ID - The task identifier from team_claim_task.
   RESULT - The result value."
  :permissions (:orchestration)
  :body
  (workspace-submit-result task-id result)
  (format nil "Result submitted for task ~A" task-id))

(autopoiesis.agent:defcapability team-broadcast (&key team-id message)
  "Broadcast a message to all members of a team.
   TEAM-ID - The team identifier.
   MESSAGE - Message content to send to all members."
  :permissions (:orchestration)
  :body
  (let ((find-fn (find-symbol "FIND-TEAM" :autopoiesis.team))
        (members-fn (find-symbol "TEAM-MEMBERS" :autopoiesis.team))
        (send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (if (and find-fn members-fn send-fn)
        (let ((team (funcall find-fn team-id)))
          (if team
              (let ((members (funcall members-fn team))
                    (count 0))
                (dolist (mid members)
                  (funcall send-fn "team-system" mid message)
                  (incf count))
                (format nil "Broadcast to ~A team members" count))
              (format nil "Error: Team ~A not found" team-id)))
        "Error: Required modules not loaded")))

(defun workspace-capability-names ()
  "Return the list of workspace-aware capability names."
  '(ws-read-file-cap ws-write-file-cap ws-exec-cap ws-install-cap
    team-workspace-read team-workspace-write team-claim-task
    team-submit-result team-broadcast))
