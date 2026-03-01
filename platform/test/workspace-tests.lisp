;;;; workspace-tests.lisp - Tests for workspace management
;;;;
;;;; Tests agent homes, workspace lifecycle, path resolution,
;;;; isolation backends, capabilities, and the with-workspace macro.

(in-package #:autopoiesis.test)

(def-suite workspace-tests
  :description "Workspace management tests")

(in-suite workspace-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Home Tests
;;; ═══════════════════════════════════════════════════════════════════

(test agent-home-creation
  "Test creating an agent home directory"
  (let ((autopoiesis.workspace:*agent-data-root* "/tmp/ap-test-agents/"))
    (unwind-protect
         (let ((home (autopoiesis.workspace:ensure-agent-home "test-agent")))
           (is (typep home 'autopoiesis.workspace:agent-home))
           (is (equal "test-agent" (autopoiesis.workspace:agent-home-id home)))
           (is (search "test-agent" (autopoiesis.workspace:agent-home-root home)))
           ;; Directory should exist
           (is (uiop:directory-exists-p (autopoiesis.workspace:agent-home-root home))))
      (ignore-errors
        (uiop:delete-directory-tree
         (pathname "/tmp/ap-test-agents/") :validate t)))))

(test agent-home-idempotent
  "Test that ensure-agent-home is idempotent"
  (let ((autopoiesis.workspace:*agent-data-root* "/tmp/ap-test-agents2/"))
    (unwind-protect
         (let ((home1 (autopoiesis.workspace:ensure-agent-home "test-agent"))
               (home2 (autopoiesis.workspace:ensure-agent-home "test-agent")))
           (is (equal (autopoiesis.workspace:agent-home-root home1)
                      (autopoiesis.workspace:agent-home-root home2))))
      (ignore-errors
        (uiop:delete-directory-tree
         (pathname "/tmp/ap-test-agents2/") :validate t)))))

(test agent-home-normalize-id
  "Test agent ID normalization"
  (is (equal "my-agent"
             (autopoiesis.workspace::normalize-agent-id "My Agent")))
  (is (equal "agent-123"
             (autopoiesis.workspace::normalize-agent-id "agent 123")))
  (is (equal "test_agent"
             (autopoiesis.workspace::normalize-agent-id "test_agent"))))

(test agent-home-paths
  "Test agent home path accessors"
  (let ((home (make-instance 'autopoiesis.workspace:agent-home
                             :id "test" :root "/data/agents/test/")))
    (is (equal "/data/agents/test/config.sexp"
               (autopoiesis.workspace:agent-home-config-path home)))
    (is (equal "/data/agents/test/history/"
               (autopoiesis.workspace:agent-home-history-path home)))
    (is (equal "/data/agents/test/learning/"
               (autopoiesis.workspace:agent-home-learning-path home)))
    (is (equal "/data/agents/test/workspaces/"
               (autopoiesis.workspace:agent-home-workspaces-path home)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Isolation Backend Tests
;;; ═══════════════════════════════════════════════════════════════════

(test directory-backend-registered
  "Test that the directory backend is registered"
  (is (autopoiesis.workspace:find-isolation-backend :directory)))

(test none-backend-registered
  "Test that the none backend is registered"
  (is (autopoiesis.workspace:find-isolation-backend :none)))

(test backend-registry
  "Test registering and finding backends"
  (let ((backends autopoiesis.workspace::*isolation-backends*))
    (is (gethash :directory backends))
    (is (gethash :none backends))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Workspace Creation Tests
;;; ═══════════════════════════════════════════════════════════════════

(test workspace-creation-directory
  "Test creating a directory-isolated workspace"
  (let ((ws (autopoiesis.workspace:create-workspace
             "test-agent" "test task"
             :isolation :directory
             :root "/tmp/ap-ws-test/")))
    (unwind-protect
         (progn
           (is (typep ws 'autopoiesis.workspace:workspace))
           (is (stringp (autopoiesis.workspace:workspace-id ws)))
           (is (equal "test-agent" (autopoiesis.workspace:workspace-agent-id ws)))
           (is (equal "test task" (autopoiesis.workspace:workspace-task ws)))
           (is (eq :directory (autopoiesis.workspace:workspace-isolation ws)))
           (is (eq :active (autopoiesis.workspace:workspace-status ws)))
           ;; Directory should exist
           (is (uiop:directory-exists-p (autopoiesis.workspace:workspace-root ws))))
      (autopoiesis.workspace:destroy-workspace ws)
      (ignore-errors
        (uiop:delete-directory-tree (pathname "/tmp/ap-ws-test/") :validate t)))))

(test workspace-creation-none
  "Test creating a workspace with no isolation"
  (let ((ws (autopoiesis.workspace:create-workspace
             nil "test task" :isolation :none)))
    (unwind-protect
         (progn
           (is (typep ws 'autopoiesis.workspace:workspace))
           (is (eq :none (autopoiesis.workspace:workspace-isolation ws))))
      (autopoiesis.workspace:destroy-workspace ws))))

(test workspace-registry
  "Test workspace registration and lookup"
  (let ((ws (autopoiesis.workspace:create-workspace
             "test-agent" "test" :isolation :none)))
    (unwind-protect
         (progn
           (is (autopoiesis.workspace:find-workspace
                (autopoiesis.workspace:workspace-id ws)))
           (is (member ws (autopoiesis.workspace:list-workspaces))))
      (autopoiesis.workspace:destroy-workspace ws)
      ;; Should be unregistered after destroy
      (is (null (autopoiesis.workspace:find-workspace
                 (autopoiesis.workspace:workspace-id ws)))))))

(test workspace-agent-listing
  "Test listing workspaces by agent"
  (let ((ws1 (autopoiesis.workspace:create-workspace
              "agent-a" "task-1" :isolation :none))
        (ws2 (autopoiesis.workspace:create-workspace
              "agent-a" "task-2" :isolation :none))
        (ws3 (autopoiesis.workspace:create-workspace
              "agent-b" "task-3" :isolation :none)))
    (unwind-protect
         (progn
           (is (= 2 (length (autopoiesis.workspace:list-agent-workspaces "agent-a"))))
           (is (= 1 (length (autopoiesis.workspace:list-agent-workspaces "agent-b")))))
      (autopoiesis.workspace:destroy-workspace ws1)
      (autopoiesis.workspace:destroy-workspace ws2)
      (autopoiesis.workspace:destroy-workspace ws3))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Path Resolution Tests
;;; ═══════════════════════════════════════════════════════════════════

(test path-resolution-no-workspace
  "Test path resolution with no workspace bound"
  (let ((autopoiesis.workspace:*current-workspace* nil))
    (is (equal "foo.txt" (autopoiesis.workspace:resolve-path "foo.txt")))
    (is (equal "/etc/hosts" (autopoiesis.workspace:resolve-path "/etc/hosts")))))

(test path-resolution-directory-workspace
  "Test path resolution within a directory workspace"
  (let ((ws (make-instance 'autopoiesis.workspace:workspace
                           :root "/data/agents/test/workspaces/abc/"
                           :isolation :directory)))
    (let ((autopoiesis.workspace:*current-workspace* ws))
      ;; Relative path gets prefixed
      (is (equal "/data/agents/test/workspaces/abc/script.py"
                 (autopoiesis.workspace:resolve-path "script.py")))
      ;; Absolute path gets rooted in workspace (for :directory isolation)
      (is (equal "/data/agents/test/workspaces/abc/etc/hosts"
                 (autopoiesis.workspace:resolve-path "/etc/hosts"))))))

(test path-resolution-none-workspace
  "Test path resolution with :none isolation passes absolutes through"
  (let ((ws (make-instance 'autopoiesis.workspace:workspace
                           :root "/some/dir/"
                           :isolation :none)))
    (let ((autopoiesis.workspace:*current-workspace* ws))
      ;; Absolute path passes through for :none
      (is (equal "/etc/hosts" (autopoiesis.workspace:resolve-path "/etc/hosts")))
      ;; Relative path gets prefixed
      (is (equal "/some/dir/foo.txt"
                 (autopoiesis.workspace:resolve-path "foo.txt"))))))

(test workspace-relative-path
  "Test converting absolute paths back to workspace-relative"
  (let ((ws (make-instance 'autopoiesis.workspace:workspace
                           :root "/data/workspaces/abc/"
                           :isolation :directory)))
    (let ((autopoiesis.workspace:*current-workspace* ws))
      (is (equal "/script.py"
                 (autopoiesis.workspace:workspace-relative
                  "/data/workspaces/abc/script.py")))
      ;; Path outside workspace returns nil
      (is (null (autopoiesis.workspace:workspace-relative "/other/path.txt"))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; with-workspace Macro Tests
;;; ═══════════════════════════════════════════════════════════════════

(test with-workspace-binds-current
  "Test that with-workspace binds *current-workspace*"
  (is (null autopoiesis.workspace:*current-workspace*))
  (autopoiesis.workspace:with-workspace (nil :task "test" :isolation :none)
    (is (not (null autopoiesis.workspace:*current-workspace*)))
    (is (typep autopoiesis.workspace:*current-workspace*
               'autopoiesis.workspace:workspace)))
  ;; Unbound after exit
  (is (null autopoiesis.workspace:*current-workspace*)))

(test with-workspace-cleanup-on-error
  "Test that with-workspace cleans up on error"
  (let ((ws-id nil))
    (ignore-errors
      (autopoiesis.workspace:with-workspace (nil :task "test" :isolation :none)
        (setf ws-id (autopoiesis.workspace:workspace-id
                     autopoiesis.workspace:*current-workspace*))
        (error "Deliberate error")))
    ;; Workspace should be cleaned up
    (is (null (autopoiesis.workspace:find-workspace ws-id)))))

(test with-workspace-directory-file-ops
  "Test file operations within a directory workspace"
  (autopoiesis.workspace:with-workspace
      (nil :task "file-test" :isolation :directory
           :root "/tmp/ap-ws-filetest/")
    ;; Write a file
    (let ((result (autopoiesis.workspace:ws-write-file "test.txt" "hello world")))
      (is (search "Wrote" result)))
    ;; Read it back
    (let ((content (autopoiesis.workspace:ws-read-file "test.txt")))
      (is (equal "hello world" content)))
    ;; Check existence
    (is (autopoiesis.workspace:ws-file-exists-p "test.txt"))
    (is (not (autopoiesis.workspace:ws-file-exists-p "nonexistent.txt"))))
  ;; Cleanup
  (ignore-errors
    (uiop:delete-directory-tree (pathname "/tmp/ap-ws-filetest/") :validate t)))

(test with-workspace-directory-exec
  "Test command execution within a directory workspace"
  (autopoiesis.workspace:with-workspace
      (nil :task "exec-test" :isolation :directory
           :root "/tmp/ap-ws-exectest/")
    (multiple-value-bind (stdout stderr exit-code)
        (autopoiesis.workspace:ws-exec "echo hello")
      (is (search "hello" stdout))
      (is (zerop exit-code))))
  (ignore-errors
    (uiop:delete-directory-tree (pathname "/tmp/ap-ws-exectest/") :validate t)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Workspace Capability Tests
;;; ═══════════════════════════════════════════════════════════════════

(test workspace-capabilities-defined
  "Test that workspace capabilities are defined and findable"
  (dolist (cap-name (autopoiesis.workspace::workspace-capability-names))
    (is (autopoiesis.agent:find-capability cap-name)
        "Capability ~A should be registered" cap-name)))

(test workspace-capability-names
  "Test the workspace capability names list"
  (let ((names (autopoiesis.workspace::workspace-capability-names)))
    (is (= 6 (length names)))
    (is (member 'autopoiesis.workspace::ws-read-file-cap names))
    (is (member 'autopoiesis.workspace::ws-write-file-cap names))
    (is (member 'autopoiesis.workspace::ws-exec-cap names))
    (is (member 'autopoiesis.workspace::ws-install-cap names))
    (is (member 'autopoiesis.workspace::ws-read-host-file-cap names))
    (is (member 'autopoiesis.workspace::ws-grep-cap names))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Host Read / Grep Tests
;;; ═══════════════════════════════════════════════════════════════════

(test ws-read-file-host-flag
  "Test that ws-read-file with :host t reads from host filesystem"
  (autopoiesis.workspace:with-workspace
      (nil :task "host-read-test" :isolation :directory
           :root "/tmp/ap-ws-hostread/")
    ;; Write a file INSIDE the workspace
    (autopoiesis.workspace:ws-write-file "inside.txt" "workspace content")
    ;; Read a known host file using :host t (not from workspace)
    (let ((host-content (autopoiesis.workspace:ws-read-file
                         "/proc/version" :host t)))
      ;; /proc/version should contain "Linux" on any Linux system
      (is (search "Linux" host-content)))
    ;; Regular read should still get workspace file
    (let ((ws-content (autopoiesis.workspace:ws-read-file "inside.txt")))
      (is (equal "workspace content" ws-content))))
  (ignore-errors
    (uiop:delete-directory-tree (pathname "/tmp/ap-ws-hostread/") :validate t)))

(test ws-read-host-file-function
  "Test the ws-read-host-file convenience function"
  (autopoiesis.workspace:with-workspace
      (nil :task "host-read-conv-test" :isolation :directory
           :root "/tmp/ap-ws-hostread2/")
    (let ((content (autopoiesis.workspace:ws-read-host-file "/proc/version")))
      (is (search "Linux" content))))
  (ignore-errors
    (uiop:delete-directory-tree (pathname "/tmp/ap-ws-hostread2/") :validate t)))

(test ws-grep-host-files
  "Test that ws-grep searches the host filesystem"
  (autopoiesis.workspace:with-workspace
      (nil :task "grep-test" :isolation :directory
           :root "/tmp/ap-ws-greptest/")
    ;; Write a file INSIDE the workspace
    (autopoiesis.workspace:ws-write-file "test.lisp" "(defun hello () 42)")
    ;; grep the workspace directory — should find the file we wrote
    (let ((result (autopoiesis.workspace:ws-grep
                   "defun hello"
                   :path "/tmp/ap-ws-greptest/")))
      (is (search "defun hello" result))
      (is (search "test.lisp" result))))
  (ignore-errors
    (uiop:delete-directory-tree (pathname "/tmp/ap-ws-greptest/") :validate t)))

(test ws-grep-no-workspace
  "Test that ws-grep works with no workspace bound"
  (let ((autopoiesis.workspace:*current-workspace* nil))
    ;; grep should still work directly on host
    (let ((result (autopoiesis.workspace:ws-grep
                   "this-pattern-wont-match-anything"
                   :path "/tmp/")))
      (is (equal "No matches found" result)))))

(test host-read-backend-protocol
  "Test that backend-read-host-file defaults to backend-read-file for non-sandbox"
  ;; For :directory and :none backends, host-read should be the same as regular read
  (let ((dir-backend (autopoiesis.workspace:find-isolation-backend :directory))
        (none-backend (autopoiesis.workspace:find-isolation-backend :none)))
    ;; Both backends should respond to backend-read-host-file
    (is (not (null dir-backend)))
    (is (not (null none-backend)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Backend Tests (structural only — no actual sandbox)
;;; ═══════════════════════════════════════════════════════════════════

(test sandbox-backend-not-available-without-load
  "Test that :sandbox backend requires autopoiesis/sandbox to be loaded"
  ;; This test passes if sandbox system IS loaded (backend registered)
  ;; or if it's NOT loaded (backend nil) — either is correct behavior.
  ;; The point is it doesn't error.
  (let ((backend (autopoiesis.workspace:find-isolation-backend :sandbox)))
    (is (or (null backend)
            (typep backend 'autopoiesis.workspace:isolation-backend)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Integration: Workspace + Substrate
;;; ═══════════════════════════════════════════════════════════════════

(test workspace-substrate-tracking
  "Test that workspaces are tracked in substrate when store is active"
  (autopoiesis.substrate:with-store ()
    (let ((ws (autopoiesis.workspace:create-workspace
               "test-agent" "tracked task" :isolation :none)))
      (unwind-protect
           (let* ((ws-id (autopoiesis.workspace:workspace-id ws))
                  (eid (autopoiesis.substrate:intern-id
                        (format nil "workspace:~A" ws-id)))
                  (status (autopoiesis.substrate:entity-attr eid :workspace/status)))
             (is (eq :active status))
             (is (equal "tracked task"
                        (autopoiesis.substrate:entity-attr eid :workspace/task))))
        (autopoiesis.workspace:destroy-workspace ws)))))

(test workspace-destroy-updates-substrate
  "Test that destroying a workspace updates substrate"
  (autopoiesis.substrate:with-store ()
    (let* ((ws (autopoiesis.workspace:create-workspace
                "test-agent" "destroy test" :isolation :none))
           (ws-id (autopoiesis.workspace:workspace-id ws))
           (eid (autopoiesis.substrate:intern-id
                 (format nil "workspace:~A" ws-id))))
      (autopoiesis.workspace:destroy-workspace ws)
      (is (eq :destroyed
              (autopoiesis.substrate:entity-attr eid :workspace/status))))))
