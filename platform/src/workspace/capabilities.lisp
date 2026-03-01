;;;; capabilities.lisp - Workspace-aware file and exec capabilities
;;;;
;;;; These capabilities check *current-workspace* and route operations
;;;; through the appropriate isolation backend. When no workspace is
;;;; bound, they fall back to direct host filesystem access (same as
;;;; the original builtin-tools.lisp capabilities).
;;;;
;;;; Agents that need workspace isolation should use these capabilities
;;;; instead of the raw read-file/write-file/run-command from builtin-tools.

(in-package #:autopoiesis.workspace)

;;; ── Workspace-Aware Operations ──────────────────────────────────
;;;
;;; These are plain functions, not capabilities. They can be called
;;; from within agentic loops, capability bodies, or user code.

(defun %apply-line-filter (content start-line end-line)
  "Apply line filtering to file content when start-line or end-line is given."
  (if (or start-line end-line)
      (let ((lines (uiop:split-string content :separator '(#\Newline))))
        (format nil "~{~A~^~%~}"
                (subseq lines
                        (max 0 (1- (or start-line 1)))
                        (min (length lines) (or end-line (length lines))))))
      content))

(defun %read-host-file (path &key start-line end-line)
  "Read a file directly from the host filesystem."
  (let ((full-path (if (uiop:absolute-pathname-p path)
                       path
                       (merge-pathnames path (uiop:getcwd)))))
    (if (probe-file full-path)
        (%apply-line-filter (uiop:read-file-string full-path)
                            start-line end-line)
        (format nil "Error: File not found: ~A" full-path))))

(defun ws-read-file (path &key start-line end-line host)
  "Read a file, resolving through the current workspace if one is bound.
   PATH can be relative (resolved against workspace root) or absolute.
   HOST - When non-nil, read from the host filesystem even if a workspace
          is bound. This allows agents in sandbox-isolated workspaces to
          read source code, configs, and other host files.
   Returns file contents as a string."
  (if (or (null *current-workspace*) host)
      ;; Direct host access (no workspace, or explicit :host t)
      (if (and host *current-workspace*)
          ;; Explicit host read from within a workspace
          (let ((backend (find-isolation-backend
                          (workspace-isolation *current-workspace*))))
            (handler-case
                (%apply-line-filter
                 (backend-read-host-file backend *current-workspace* path)
                 start-line end-line)
              (error (e)
                (format nil "Error reading host file ~A: ~A" path e))))
          ;; No workspace at all
          (handler-case
              (%read-host-file path :start-line start-line :end-line end-line)
            (error (e)
              (format nil "Error reading ~A: ~A" path e))))
      ;; Workspace-routed read
      (let ((backend (find-isolation-backend
                      (workspace-isolation *current-workspace*))))
        (handler-case
            (%apply-line-filter
             (backend-read-file backend *current-workspace* path)
             start-line end-line)
          (error (e)
            (format nil "Error reading ~A: ~A" path e))))))

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

(defun ws-read-host-file (path &key start-line end-line)
  "Read a file from the HOST filesystem, regardless of workspace isolation.
   This is a convenience wrapper for (ws-read-file path :host t ...).
   Agents in sandbox-isolated workspaces can use this to read source code,
   configuration files, or any other file on the host machine."
  (ws-read-file path :start-line start-line :end-line end-line :host t))

(defun ws-grep (pattern &key path file-pattern)
  "Search for PATTERN in files on the HOST filesystem.
   Always searches the host, regardless of workspace isolation.
   This ensures agents in sandboxed workspaces can still grep source code.

   PATTERN     - String to search for in file contents.
   PATH        - Directory to search (default: current directory).
   FILE-PATTERN - Glob to filter files (default: '*.*').
   Returns matching lines with file:line: prefix."
  (handler-case
      (let ((results nil)
            (search-path (or path (namestring (uiop:getcwd))))
            (file-glob (or file-pattern "*.*")))
        (dolist (file (directory (merge-pathnames file-glob search-path)))
          (when (and (probe-file file)
                     (not (uiop:directory-pathname-p file)))
            (handler-case
                (with-open-file (in file :direction :input)
                  (loop for line = (read-line in nil nil)
                        for line-num from 1
                        while line
                        when (search pattern line)
                        do (push (format nil "~A:~A: ~A"
                                         (namestring file) line-num line)
                                 results)))
              (error () nil))))  ; Skip unreadable files
        (if results
            (format nil "~{~A~^~%~}" (nreverse results))
            "No matches found"))
    (error (e)
      (format nil "Error searching: ~A" e))))

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

(autopoiesis.agent:defcapability ws-read-file-cap (&key path start-line end-line host)
  "Read a file within the current workspace.
   PATH can be relative to workspace root or absolute.
   HOST - When true, read from the host filesystem even if in a sandbox.
          Use this to read source code, configs, or reference files.
   Returns file contents as a string."
  :permissions (:file-read)
  :body
  (ws-read-file path :start-line start-line :end-line end-line :host host))

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

(autopoiesis.agent:defcapability ws-read-host-file-cap (&key path start-line end-line)
  "Read a file from the HOST filesystem, bypassing workspace isolation.
   Always reads from the host, even if the current workspace uses sandbox
   isolation. Use this when you need to read source code, configuration,
   or reference files on the host machine."
  :permissions (:file-read)
  :body
  (ws-read-host-file path :start-line start-line :end-line end-line))

(autopoiesis.agent:defcapability ws-grep-cap (&key pattern path file-pattern)
  "Search for PATTERN in files on the HOST filesystem.
   Always searches the host, regardless of workspace isolation.
   PATH is the directory to search (default: current directory).
   FILE-PATTERN is a glob to filter files (default: '*.*').
   Returns matching lines with file:line: prefix."
  :permissions (:file-read)
  :body
  (ws-grep pattern :path path :file-pattern file-pattern))

(defun workspace-capability-names ()
  "Return the list of workspace-aware capability names."
  '(ws-read-file-cap ws-write-file-cap ws-exec-cap ws-install-cap
    ws-read-host-file-cap ws-grep-cap))
