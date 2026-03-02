;;;; git-tools-tests.lisp - Tests for git write operations
;;;;
;;;; Tests git-add, git-commit, git-checkout-branch, git-create-worktree.

(in-package #:autopoiesis.test)

(def-suite git-tools-tests
  :description "Tests for git write operations"
  :in all-tests)

(in-suite git-tools-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Mock infrastructure
;;; ═══════════════════════════════════════════════════════════════════

(defvar *captured-commands* nil)

(defun make-mock-run-command ()
  "Create a mock run-command that captures commands."
  (lambda (&key command working-directory timeout)
    (declare (ignore timeout))
    (push (list :command command :directory working-directory) *captured-commands*)
    (format nil "mock: ~a" command)))

(defmacro with-mock-run-command (&body body)
  "Execute BODY with run-command mocked to capture commands."
  `(let ((*captured-commands* nil))
     (let ((original-cap (autopoiesis.agent:find-capability 'autopoiesis.integration::run-command)))
       (unwind-protect
           (progn
             (let ((mock-cap (autopoiesis.agent:make-capability
                              'autopoiesis.integration::run-command
                              (make-mock-run-command)
                              :description "Mock run-command")))
               (autopoiesis.agent:register-capability mock-cap)
               ,@body))
         (when original-cap
           (autopoiesis.agent:register-capability original-cap))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; git-add tests
;;; ═══════════════════════════════════════════════════════════════════

(test git-add-exists
  "git-add capability is registered."
  (autopoiesis.integration:register-builtin-tools)
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add)))))

(test git-add-permissions
  "git-add has correct permissions."
  (autopoiesis.integration:register-builtin-tools)
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add)))
    (is (member :shell (autopoiesis.agent:capability-permissions cap)))
    (is (member :git-write (autopoiesis.agent:capability-permissions cap)))))

(test git-add-all
  "git-add with :all t stages everything."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add))
             :all t)
    (is (= 1 (length *captured-commands*)))
    (is (search "git add -A" (getf (first *captured-commands*) :command)))))

(test git-add-files
  "git-add with specific files."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add))
             :files '("foo.lisp" "bar.lisp"))
    (is (search "foo.lisp" (getf (first *captured-commands*) :command)))
    (is (search "bar.lisp" (getf (first *captured-commands*) :command)))))

(test git-add-single-file
  "git-add with a single file string."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add))
             :files "README.md")
    (is (search "git add README.md" (getf (first *captured-commands*) :command)))))

(test git-add-default-all
  "git-add with no args defaults to -A."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add)))
    (is (search "git add -A" (getf (first *captured-commands*) :command)))))

(test git-add-with-directory
  "git-add passes working directory."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-add))
             :all t :directory "/tmp/repo")
    (is (equal "/tmp/repo" (getf (first *captured-commands*) :directory)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; git-commit tests
;;; ═══════════════════════════════════════════════════════════════════

(test git-commit-exists
  "git-commit capability is registered."
  (autopoiesis.integration:register-builtin-tools)
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::git-commit)))))

(test git-commit-permissions
  "git-commit has correct permissions."
  (autopoiesis.integration:register-builtin-tools)
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-commit)))
    (is (member :shell (autopoiesis.agent:capability-permissions cap)))
    (is (member :git-write (autopoiesis.agent:capability-permissions cap)))))

(test git-commit-requires-message
  "git-commit requires a message."
  (autopoiesis.integration:register-builtin-tools)
  (let ((result (funcall (autopoiesis.agent:capability-function
                          (autopoiesis.agent:find-capability 'autopoiesis.integration::git-commit)))))
    (is (search "Error" result))))

(test git-commit-with-message
  "git-commit creates commit with message."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-commit))
             :message "test commit")
    (is (= 1 (length *captured-commands*)))
    (is (search "git commit" (getf (first *captured-commands*) :command)))
    (is (search "test commit" (getf (first *captured-commands*) :command)))))

(test git-commit-amend
  "git-commit with amend flag."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-commit))
             :message "amended" :amend t)
    (is (search "--amend" (getf (first *captured-commands*) :command)))))

(test git-commit-no-amend
  "git-commit without amend does not include --amend."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-commit))
             :message "normal commit")
    (is (not (search "--amend" (getf (first *captured-commands*) :command))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; git-checkout-branch tests
;;; ═══════════════════════════════════════════════════════════════════

(test git-checkout-branch-exists
  "git-checkout-branch is registered."
  (autopoiesis.integration:register-builtin-tools)
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::git-checkout-branch)))))

(test git-checkout-branch-permissions
  "git-checkout-branch has correct permissions."
  (autopoiesis.integration:register-builtin-tools)
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-checkout-branch)))
    (is (member :shell (autopoiesis.agent:capability-permissions cap)))
    (is (member :git-write (autopoiesis.agent:capability-permissions cap)))))

(test git-checkout-branch-requires-name
  "git-checkout-branch requires name."
  (autopoiesis.integration:register-builtin-tools)
  (let ((result (funcall (autopoiesis.agent:capability-function
                          (autopoiesis.agent:find-capability 'autopoiesis.integration::git-checkout-branch)))))
    (is (search "Error" result))))

(test git-checkout-branch-switch
  "git-checkout-branch switches branch."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-checkout-branch))
             :name "feature")
    (is (search "git checkout" (getf (first *captured-commands*) :command)))
    (is (search "feature" (getf (first *captured-commands*) :command)))))

(test git-checkout-branch-create
  "git-checkout-branch with create flag."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-checkout-branch))
             :name "new-branch" :create t)
    (is (search "-b" (getf (first *captured-commands*) :command)))))

(test git-checkout-branch-no-create
  "git-checkout-branch without create does not include -b."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-checkout-branch))
             :name "existing-branch")
    (is (not (search "-b" (getf (first *captured-commands*) :command))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; git-create-worktree tests
;;; ═══════════════════════════════════════════════════════════════════

(test git-worktree-exists
  "git-create-worktree is registered."
  (autopoiesis.integration:register-builtin-tools)
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::git-create-worktree)))))

(test git-worktree-permissions
  "git-create-worktree has correct permissions."
  (autopoiesis.integration:register-builtin-tools)
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-create-worktree)))
    (is (member :shell (autopoiesis.agent:capability-permissions cap)))
    (is (member :git-write (autopoiesis.agent:capability-permissions cap)))))

(test git-worktree-requires-path
  "git-create-worktree requires path."
  (autopoiesis.integration:register-builtin-tools)
  (let ((result (funcall (autopoiesis.agent:capability-function
                          (autopoiesis.agent:find-capability 'autopoiesis.integration::git-create-worktree)))))
    (is (search "Error" result))))

(test git-worktree-basic
  "git-create-worktree creates worktree."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-create-worktree))
             :path "/tmp/wt")
    (is (search "git worktree add" (getf (first *captured-commands*) :command)))
    (is (search "/tmp/wt" (getf (first *captured-commands*) :command)))))

(test git-worktree-with-branch
  "git-create-worktree with branch."
  (autopoiesis.integration:register-builtin-tools)
  (with-mock-run-command
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'autopoiesis.integration::git-create-worktree))
             :path "/tmp/wt" :branch "feature")
    (is (search "feature" (getf (first *captured-commands*) :command)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; builtin-tool-symbols tests
;;; ═══════════════════════════════════════════════════════════════════

(test git-tools-in-builtin-symbols
  "New git tools are in builtin-tool-symbols."
  (let ((symbols (autopoiesis.integration:builtin-tool-symbols)))
    (is (member 'autopoiesis.integration::git-add symbols))
    (is (member 'autopoiesis.integration::git-commit symbols))
    (is (member 'autopoiesis.integration::git-checkout-branch symbols))
    (is (member 'autopoiesis.integration::git-create-worktree symbols))))
