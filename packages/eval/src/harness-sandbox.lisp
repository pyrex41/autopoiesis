;;;; harness-sandbox.lisp - Content-addressed sandbox harness
;;;;
;;;; Runs eval scenarios inside isolated, snapshotable sandboxes.
;;;; Captures before/after filesystem diffs as additional eval data,
;;;; enabling filesystem-aware verifiers and richer LLM judge context.
;;;;
;;;; Uses dynamic resolution (find-package/find-symbol) so the eval
;;;; system loads even when autopoiesis/sandbox-backends is not present.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Sandbox Harness Class
;;; ===================================================================

(defclass sandbox-harness (eval-harness)
  ((backend-type :initarg :backend-type
                 :accessor sbh-backend-type
                 :initform :local
                 :type keyword
                 :documentation "Backend to use: :local or :docker")
   (base-dir :initarg :base-dir
             :accessor sbh-base-dir
             :initform "/tmp/ap-eval-sandboxes/"
             :type string
             :documentation "Base directory for sandbox roots")
   (baseline-setup :initarg :baseline-setup
                   :accessor sbh-baseline-setup
                   :initform nil
                   :documentation "List of (path . content) pairs to write before each trial")
   (command-template :initarg :command-template
                     :accessor sbh-command-template
                     :initform "{{prompt}}"
                     :type string
                     :documentation "Shell command template. {{prompt}} replaced with scenario prompt.")
   (capture-diff :initarg :capture-diff
                 :accessor sbh-capture-diff
                 :initform t
                 :documentation "When T, snapshots before/after and computes filesystem diff")
   (use-fork :initarg :use-fork
             :accessor sbh-use-fork
             :initform nil
             :documentation "When T, fork from a shared baseline for parallel trials")
   (manager :initarg :manager
            :accessor sbh-manager
            :initform nil
            :documentation "Cached sandbox-manager instance (lazy-initialized)"))
  (:documentation "Harness that runs scenarios inside content-addressed sandboxes.
Each trial gets its own sandbox with before/after diff capture."))

(defun make-sandbox-harness (name &key (backend-type :local)
                                       (base-dir "/tmp/ap-eval-sandboxes/")
                                       baseline-setup
                                       (command-template "{{prompt}}")
                                       (capture-diff t)
                                       (use-fork nil)
                                       (description ""))
  "Create a sandbox harness for eval runs."
  (make-instance 'sandbox-harness
                 :name name
                 :description (if (string= description "")
                                  (format nil "Sandbox (~a)" backend-type)
                                  description)
                 :backend-type backend-type
                 :base-dir base-dir
                 :baseline-setup baseline-setup
                 :command-template command-template
                 :capture-diff capture-diff
                 :use-fork use-fork))

;;; ===================================================================
;;; Dynamic Resolution (sandbox + snapshot packages)
;;; ===================================================================

(defun sandbox-pkg-available-p ()
  "Check if the sandbox backends package is loaded."
  (find-package :autopoiesis.sandbox))

(defun %sandbox-call (fn-name &rest args)
  "Call a function from autopoiesis.sandbox dynamically."
  (let* ((pkg (find-package :autopoiesis.sandbox))
         (fn (when pkg (find-symbol fn-name pkg))))
    (if (and fn (fboundp fn))
        (apply fn args)
        (error "Sandbox function ~A not available. Load autopoiesis/sandbox-backends."
               fn-name))))

(defun %snapshot-call (fn-name &rest args)
  "Call a function from autopoiesis.snapshot dynamically."
  (let* ((pkg (find-package :autopoiesis.snapshot))
         (fn (when pkg (find-symbol fn-name pkg))))
    (if (and fn (fboundp fn))
        (apply fn args)
        (error "Snapshot function ~A not available." fn-name))))

(defun %snapshot-call-safe (fn-name &rest args)
  "Call a snapshot function, returning NIL if not available."
  (let* ((pkg (find-package :autopoiesis.snapshot))
         (fn (when pkg (find-symbol fn-name pkg))))
    (when (and fn (fboundp fn))
      (apply fn args))))

;;; ===================================================================
;;; Manager Lifecycle
;;; ===================================================================

(defun ensure-sandbox-manager (harness)
  "Lazily initialize the sandbox manager for this harness."
  (or (sbh-manager harness)
      (let* ((backend (ecase (sbh-backend-type harness)
                        (:local (%sandbox-call "MAKE-LOCAL-BACKEND"
                                               :base-dir (sbh-base-dir harness)))
                        (:docker (%sandbox-call "MAKE-DOCKER-BACKEND"))))
             (store (%snapshot-call "MAKE-CONTENT-STORE"))
             (mgr (%sandbox-call "MAKE-SANDBOX-MANAGER" backend
                                 :content-store store)))
        (setf (sbh-manager harness) mgr)
        mgr)))

(defun make-sandbox-id ()
  "Generate a unique sandbox ID for a trial."
  (format nil "eval-~D-~6,'0D" (get-universal-time) (random 1000000)))

;;; ===================================================================
;;; Shell Interpolation
;;; ===================================================================

(defun sbh-interpolate-prompt (template prompt)
  "Replace {{prompt}} in TEMPLATE with shell-escaped PROMPT."
  (let ((escaped (sbh-shell-escape prompt)))
    (cl-ppcre:regex-replace-all "\\{\\{prompt\\}\\}" template escaped)))

(defun sbh-shell-escape (str)
  "Escape a string for safe shell interpolation in single quotes."
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for ch across str
          do (if (char= ch #\')
                 (write-string "'\\''" out)
                 (write-char ch out)))
    (write-char #\' out)))

;;; ===================================================================
;;; Diff Summary (human-readable, for LLM judge)
;;; ===================================================================

(defun format-diff-summary (diff &key (max-lines 30))
  "Format a tree-diff result as a human-readable summary string."
  (when (null diff) (return-from format-diff-summary nil))
  (with-output-to-string (out)
    (let ((added 0) (removed 0) (modified 0))
      (dolist (change diff)
        (ecase (first change)
          (:added (incf added))
          (:removed (incf removed))
          (:modified (incf modified))))
      (format out "~D change~:P: +~D added, -~D removed, ~D modified~%"
              (length diff) added removed modified)
      (let ((line-count 1))
        (dolist (change diff)
          (when (>= line-count max-lines)
            (format out "... and ~D more changes~%" (- (length diff) line-count))
            (return))
          (let* ((type (first change))
                 (entry (if (eq type :modified) (third change) (second change)))
                 (path (%snapshot-call-safe "ENTRY-PATH" entry)))
            (format out "  ~A ~A~%"
                    (ecase type (:added "+") (:removed "-") (:modified "~"))
                    (or path "?")))
          (incf line-count))))))

;;; ===================================================================
;;; Baseline Setup
;;; ===================================================================

(defun write-baseline-files (manager sandbox-id baseline-setup)
  "Write baseline files into a sandbox."
  (when baseline-setup
    (let ((root (%sandbox-call "BACKEND-SANDBOX-ROOT"
                               (%sandbox-call "MANAGER-BACKEND" manager)
                               sandbox-id)))
      (dolist (pair baseline-setup)
        (let ((full-path (merge-pathnames (car pair) root)))
          (ensure-directories-exist full-path)
          (with-open-file (out full-path :direction :output
                                        :if-exists :supersede
                                        :if-does-not-exist :create)
            (write-string (cdr pair) out)))))))

;;; ===================================================================
;;; Core Execution (shared by direct and fork paths)
;;; ===================================================================

(defun sandbox-execute-trial (harness manager sandbox-id scenario-plist
                              &key timeout)
  "Execute a scenario in an existing sandbox. Returns result plist."
  (let* ((prompt (getf scenario-plist :eval-scenario/prompt))
         (verifier (getf scenario-plist :eval-scenario/verifier))
         (expected (getf scenario-plist :eval-scenario/expected))
         (effective-timeout (or timeout
                               (getf scenario-plist :eval-scenario/timeout)
                               300))
         (start-time (get-internal-real-time))
         before-tree after-tree diff exec-result)
    (handler-case
        (progn
          ;; Snapshot before-state
          (when (sbh-capture-diff harness)
            (let ((snap (%sandbox-call "MANAGER-SNAPSHOT" manager sandbox-id
                                       :label "before")))
              (setf before-tree (%snapshot-call-safe "SNAPSHOT-TREE-ENTRIES" snap))))
          ;; Execute command
          (let ((command (sbh-interpolate-prompt (sbh-command-template harness)
                                                 (or prompt ""))))
            (setf exec-result (%sandbox-call "MANAGER-EXEC" manager sandbox-id
                                             command :timeout effective-timeout)))
          ;; Snapshot after-state
          (when (sbh-capture-diff harness)
            (let ((snap (%sandbox-call "MANAGER-SNAPSHOT" manager sandbox-id
                                       :label "after")))
              (setf after-tree (%snapshot-call-safe "SNAPSHOT-TREE-ENTRIES" snap))))
          ;; Compute diff
          (when (and before-tree after-tree)
            (setf diff (%snapshot-call "TREE-DIFF" before-tree after-tree)))
          ;; Build result
          (let* ((stdout (%sandbox-call "EXEC-RESULT-STDOUT" exec-result))
                 (stderr (%sandbox-call "EXEC-RESULT-STDERR" exec-result))
                 (exit-code (%sandbox-call "EXEC-RESULT-EXIT-CODE" exec-result))
                 (duration (float (/ (- (get-internal-real-time) start-time)
                                     internal-time-units-per-second)))
                 (file-count-before (if before-tree
                                        (%snapshot-call "TREE-FILE-COUNT" before-tree) 0))
                 (file-count-after (if after-tree
                                       (%snapshot-call "TREE-FILE-COUNT" after-tree) 0))
                 (metadata (list :sandbox-id sandbox-id
                                 :file-count-before file-count-before
                                 :file-count-after file-count-after
                                 :file-count-delta (- file-count-after file-count-before)
                                 :bytes-written-total (if after-tree
                                                         (%snapshot-call "TREE-TOTAL-SIZE" after-tree) 0)
                                 :tree-hash-before (when before-tree
                                                     (%snapshot-call "TREE-HASH" before-tree))
                                 :tree-hash-after (when after-tree
                                                    (%snapshot-call "TREE-HASH" after-tree))
                                 :files-added (count :added diff :key #'first)
                                 :files-removed (count :removed diff :key #'first)
                                 :files-modified (count :modified diff :key #'first)
                                 :diff-summary (format-diff-summary diff)
                                 :after-tree after-tree
                                 :stderr stderr))
                 (partial-result (list :output stdout :exit-code exit-code :metadata metadata))
                 (passed (when verifier
                           (run-verifier verifier stdout
                                         :expected expected :exit-code exit-code
                                         :result partial-result))))
            (list :output stdout :tool-calls nil :duration duration
                  :cost nil :turns nil :exit-code exit-code
                  :passed passed :metadata metadata)))
      (error (e)
        (list :output (format nil "Error: ~A" e)
              :duration (float (/ (- (get-internal-real-time) start-time)
                                  internal-time-units-per-second))
              :exit-code -1 :passed :error
              :metadata (list :sandbox-id sandbox-id :error (format nil "~A" e)))))))

;;; ===================================================================
;;; Harness Protocol
;;; ===================================================================

(defmethod harness-run-scenario ((harness sandbox-harness) scenario-plist &key timeout)
  "Run scenario inside a content-addressed sandbox."
  (unless (sandbox-pkg-available-p)
    (return-from harness-run-scenario
      (list :output "Error: autopoiesis/sandbox-backends not loaded."
            :duration 0 :exit-code -1 :passed :error
            :metadata (list :error "sandbox-package-not-available"))))
  (let* ((manager (ensure-sandbox-manager harness))
         (sandbox-id (make-sandbox-id)))
    (unwind-protect
         (progn
           (%sandbox-call "MANAGER-CREATE-SANDBOX" manager sandbox-id)
           (when (sbh-baseline-setup harness)
             (write-baseline-files manager sandbox-id (sbh-baseline-setup harness)))
           (sandbox-execute-trial harness manager sandbox-id scenario-plist
                                 :timeout timeout))
      (handler-case
          (%sandbox-call "MANAGER-DESTROY-SANDBOX" manager sandbox-id)
        (error () nil)))))

;;; ===================================================================
;;; Fork-Based Trial Support
;;; ===================================================================

(defun sandbox-prepare-baseline (harness scenario-plist)
  "Create a baseline sandbox with setup files and snapshot it.
   Returns baseline sandbox-id. Used when use-fork is T."
  (declare (ignore scenario-plist))
  (let* ((manager (ensure-sandbox-manager harness))
         (baseline-id (format nil "baseline-~D" (get-universal-time))))
    (%sandbox-call "MANAGER-CREATE-SANDBOX" manager baseline-id)
    (when (sbh-baseline-setup harness)
      (write-baseline-files manager baseline-id (sbh-baseline-setup harness)))
    (%sandbox-call "MANAGER-SNAPSHOT" manager baseline-id :label "baseline")
    baseline-id))

(defun sandbox-run-in-fork (harness baseline-id scenario-plist &key timeout)
  "Fork from BASELINE-ID, run scenario in fork, return result."
  (let* ((manager (ensure-sandbox-manager harness))
         (fork-id (make-sandbox-id)))
    (%sandbox-call "MANAGER-FORK" manager baseline-id fork-id :label "eval-fork")
    (unwind-protect
         (sandbox-execute-trial harness manager fork-id scenario-plist :timeout timeout)
      (handler-case
          (%sandbox-call "MANAGER-DESTROY-SANDBOX" manager fork-id)
        (error () nil)))))

(defun sandbox-destroy-baseline (harness baseline-id)
  "Destroy a baseline sandbox after all fork trials are done."
  (handler-case
      (let ((manager (sbh-manager harness)))
        (when manager
          (%sandbox-call "MANAGER-DESTROY-SANDBOX" manager baseline-id)))
    (error () nil)))

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defmethod harness-to-config-plist ((harness sandbox-harness))
  (list :type "sandbox"
        :name (harness-name harness)
        :config (list :backend-type (sbh-backend-type harness)
                      :base-dir (sbh-base-dir harness)
                      :command-template (sbh-command-template harness)
                      :capture-diff (sbh-capture-diff harness)
                      :use-fork (sbh-use-fork harness))))
