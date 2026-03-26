;;;; sandbox-tools.lisp - DAG-aware tool wrappers for sandbox execution
;;;;
;;;; When an agent runs inside a managed sandbox, file operations are
;;;; intercepted to track changes in the changeset. This enables
;;;; incremental snapshots: on commit, only changed files are hashed
;;;; and stored, not the entire filesystem.
;;;;
;;;; The read path is always native filesystem (zero overhead).
;;;; The write path adds minimal overhead: record path in changeset.
;;;;
;;;; Uses dynamic resolution (find-package/find-symbol) so this file
;;;; compiles without autopoiesis/sandbox-backends loaded.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Dynamic Resolution
;;; ═══════════════════════════════════════════════════════════════════

(defun %sandbox-call (fn-name &rest args)
  "Call a function from autopoiesis.sandbox dynamically."
  (let* ((pkg (find-package :autopoiesis.sandbox))
         (fn (when pkg (find-symbol fn-name pkg))))
    (if (and fn (fboundp fn))
        (apply fn args)
        (error "Sandbox function ~A not available. Load autopoiesis/sandbox-backends."
               fn-name))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Context (dynamic variables)
;;; ═══════════════════════════════════════════════════════════════════

(defvar *sandbox-context* nil
  "When non-nil, a plist describing the active sandbox context:
   :manager     - sandbox-manager instance
   :sandbox-id  - current sandbox ID
   :changeset   - changeset tracking file changes
   :root-path   - filesystem root of the sandbox")

(defun in-sandbox-p ()
  "Return T if currently executing within a sandbox context."
  (not (null *sandbox-context*)))

(defun current-sandbox-id ()
  "Return the current sandbox ID, or NIL."
  (getf *sandbox-context* :sandbox-id))

(defun current-changeset ()
  "Return the current changeset, or NIL."
  (getf *sandbox-context* :changeset))

(defun current-sandbox-root ()
  "Return the current sandbox root path, or NIL."
  (getf *sandbox-context* :root-path))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Context Macro
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-sandbox-context ((manager sandbox-id &key changeset) &body body)
  "Execute BODY within a sandbox context. File tool operations will
   be intercepted to track changes in the changeset."
  (let ((root-var (gensym "ROOT"))
        (mgr-var (gensym "MGR"))
        (sid-var (gensym "SID")))
    `(let* ((,mgr-var ,manager)
            (,sid-var ,sandbox-id)
            (,root-var (%sandbox-call "BACKEND-SANDBOX-ROOT"
                                      (%sandbox-call "MANAGER-BACKEND" ,mgr-var)
                                      ,sid-var))
            (*sandbox-context*
              (list :manager ,mgr-var
                    :sandbox-id ,sid-var
                    :changeset ,changeset
                    :root-path ,root-var)))
       ,@body)))

;;; ═══════════════════════════════════════════════════════════════════
;;; DAG-Aware File Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun sandbox-write-file (path content)
  "Write CONTENT to PATH, tracking the change if in sandbox context.
   Falls back to normal write if not in a sandbox."
  (handler-case
      (progn
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
          (write-string content out))
        ;; Track in changeset if in sandbox
        (when (and (in-sandbox-p) (current-changeset))
          (let* ((root (current-sandbox-root))
                 (rel-path (enough-namestring path root)))
            (%sandbox-call "CHANGESET-RECORD-WRITE"
                           (current-changeset) (namestring rel-path))))
        (format nil "Successfully wrote ~A bytes to ~A"
                (length content) path))
    (error (e)
      (format nil "Error writing file ~A: ~A" path e))))

(defun sandbox-delete-file (path)
  "Delete PATH, tracking the change if in sandbox context."
  (handler-case
      (progn
        (delete-file path)
        ;; Track in changeset if in sandbox
        (when (and (in-sandbox-p) (current-changeset))
          (let* ((root (current-sandbox-root))
                 (rel-path (enough-namestring path root)))
            (%sandbox-call "CHANGESET-RECORD-DELETE"
                           (current-changeset) (namestring rel-path))))
        (format nil "Deleted ~A" path))
    (error (e)
      (format nil "Error deleting ~A: ~A" path e))))

(defun sandbox-exec-command (command &key (timeout 300) workdir)
  "Execute COMMAND, using sandbox backend if in context.
   Otherwise falls through to local shell execution."
  (if (in-sandbox-p)
      (let* ((manager (getf *sandbox-context* :manager))
             (sandbox-id (current-sandbox-id))
             (result (%sandbox-call "MANAGER-EXEC"
                                    manager sandbox-id command
                                    :timeout timeout :workdir workdir)))
        (format nil "Exit code: ~A~%~A~@[~%STDERR: ~A~]"
                (%sandbox-call "EXEC-RESULT-EXIT-CODE" result)
                (%sandbox-call "EXEC-RESULT-STDOUT" result)
                (let ((err (%sandbox-call "EXEC-RESULT-STDERR" result)))
                  (when (and err (> (length err) 0)) err))))
      ;; Not in sandbox — direct execution
      (handler-case
          (multiple-value-bind (output error-output exit-code)
              (uiop:run-program (list "/bin/sh" "-c" command)
                                :directory workdir
                                :output '(:string :stripped t)
                                :error-output '(:string :stripped t)
                                :ignore-error-status t)
            (format nil "Exit code: ~A~%~A~@[~%STDERR: ~A~]"
                    exit-code output
                    (when (and error-output (> (length error-output) 0))
                      error-output)))
        (error (e)
          (format nil "Error executing command: ~A" e)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Operations (convenience wrappers)
;;; ═══════════════════════════════════════════════════════════════════

(defun sandbox-snapshot (&key label)
  "Create a snapshot of the current sandbox. Must be in sandbox context.
   If changeset is available and has tracked changes, uses incremental
   snapshot. Otherwise does a full scan.
   Returns the snapshot object."
  (unless (in-sandbox-p)
    (error "Not in sandbox context. Use with-sandbox-context."))
  (let* ((manager (getf *sandbox-context* :manager))
         (sandbox-id (current-sandbox-id))
         (changeset (current-changeset))
         (snapshot (%sandbox-call "MANAGER-SNAPSHOT"
                                  manager sandbox-id :label label)))
    ;; Reset changeset after successful snapshot
    (when changeset
      (%sandbox-call "CHANGESET-RESET"
                     changeset
                     :new-base-tree (autopoiesis.snapshot:snapshot-tree-entries snapshot)))
    snapshot))

(defun sandbox-fork (new-id &key label)
  "Fork the current sandbox. Must be in sandbox context.
   Returns new sandbox-id."
  (unless (in-sandbox-p)
    (error "Not in sandbox context. Use with-sandbox-context."))
  (%sandbox-call "MANAGER-FORK"
                 (getf *sandbox-context* :manager)
                 (current-sandbox-id)
                 new-id
                 :label label))

(defun sandbox-restore (snapshot)
  "Restore the current sandbox to a snapshot state.
   Must be in sandbox context. Returns operation count."
  (unless (in-sandbox-p)
    (error "Not in sandbox context. Use with-sandbox-context."))
  (%sandbox-call "MANAGER-RESTORE"
                 (getf *sandbox-context* :manager)
                 (current-sandbox-id)
                 snapshot
                 :incremental t))
