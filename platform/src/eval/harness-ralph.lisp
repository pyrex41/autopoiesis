;;;; harness-ralph.lisp - Ralph loop harness
;;;;
;;;; Wraps the ralph autonomous build loop (platform/ralph/loop.sh)
;;;; as an eval harness. Creates a temp working directory, writes the
;;;; scenario as an implementation plan, runs the loop, and measures results.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Ralph Harness Class
;;; ===================================================================

(defclass ralph-harness (eval-harness)
  ((backend :initarg :backend
            :accessor rh-backend
            :initform "claude"
            :type string
            :documentation "CLI backend to use: claude, cursor, opencode")
   (mode :initarg :mode
         :accessor rh-mode
         :initform "build"
         :type string
         :documentation "Ralph mode: build or plan")
   (max-iterations :initarg :max-iterations
                   :accessor rh-max-iterations
                   :initform 5
                   :type integer
                   :documentation "Maximum loop iterations")
   (loop-script :initarg :loop-script
                :accessor rh-loop-script
                :initform nil
                :documentation "Path to loop.sh. Auto-detected if nil.")
   (template-dir :initarg :template-dir
                 :accessor rh-template-dir
                 :initform nil
                 :documentation "Template directory to copy for each eval. If nil, creates empty git repo."))
  (:documentation "Harness wrapping ralph loop.sh for multi-iteration autonomous eval."))

(defun make-ralph-harness (name &key (backend "claude") (mode "build")
                                   (max-iterations 5) loop-script template-dir
                                   (description ""))
  "Create a ralph loop harness."
  (make-instance 'ralph-harness
                 :name name
                 :description (if (string= description "")
                                  (format nil "Ralph loop (~a, ~a, ~a iters)"
                                          backend mode max-iterations)
                                  description)
                 :backend backend
                 :mode mode
                 :max-iterations max-iterations
                 :loop-script loop-script
                 :template-dir template-dir))

;;; ===================================================================
;;; Helpers
;;; ===================================================================

(defun find-ralph-script ()
  "Find the ralph loop.sh script relative to the platform directory."
  (let ((candidates (list
                     (merge-pathnames "platform/ralph/loop.sh"
                                      (asdf:system-source-directory :autopoiesis))
                     (merge-pathnames "ralph/loop.sh"
                                      (asdf:system-source-directory :autopoiesis)))))
    (find-if #'probe-file candidates)))

(defun make-ralph-work-dir ()
  "Create a temporary working directory for a ralph eval run."
  (let ((dir (merge-pathnames
              (format nil "eval-ralph-~a/" (make-uuid))
              (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    dir))

(defun write-ralph-prompt (dir mode prompt)
  "Write the eval prompt to the appropriate ralph prompt file."
  (let ((prompt-file (merge-pathnames
                      (format nil "ralph/PROMPT_~a.md" mode)
                      dir)))
    (ensure-directories-exist prompt-file)
    (with-open-file (out prompt-file :direction :output :if-exists :supersede)
      (write-string prompt out))))

(defun write-ralph-plan (dir spec)
  "Write the scenario spec to IMPLEMENTATION_PLAN.md."
  (let ((plan-file (merge-pathnames "ralph/IMPLEMENTATION_PLAN.md" dir)))
    (ensure-directories-exist plan-file)
    (with-open-file (out plan-file :direction :output :if-exists :supersede)
      (write-string spec out))))

(defun count-git-commits (dir)
  "Count the number of git commits in a directory."
  (handler-case
      (let ((output (uiop:run-program
                     (list "git" "-C" (namestring dir) "rev-list" "--count" "HEAD")
                     :output '(:string :stripped))))
        (parse-integer output :junk-allowed t))
    (error () 0)))

(defun read-stop-reason (dir)
  "Read the ralph stop reason file if it exists."
  (let ((stop-file (merge-pathnames "ralph/.stop" dir)))
    (when (probe-file stop-file)
      (uiop:read-file-string stop-file))))

(defun cleanup-ralph-dir (dir)
  "Remove a temporary ralph working directory."
  (handler-case
      (uiop:delete-directory-tree dir :validate t)
    (error () nil)))

;;; ===================================================================
;;; Harness Protocol
;;; ===================================================================

(defmethod harness-run-scenario ((harness ralph-harness) scenario-plist &key timeout)
  "Run scenario through ralph loop.sh."
  (let* ((prompt (getf scenario-plist :eval-scenario/prompt))
         (description (getf scenario-plist :eval-scenario/description))
         (verifier (getf scenario-plist :eval-scenario/verifier))
         (expected (getf scenario-plist :eval-scenario/expected))
         (effective-timeout (or timeout
                                (getf scenario-plist :eval-scenario/timeout)
                                600)) ; ralph loops need more time
         (script (or (rh-loop-script harness) (find-ralph-script)))
         (work-dir (make-ralph-work-dir))
         (start-time (get-precise-time)))
    (unless script
      (return-from harness-run-scenario
        (list :output "Ralph loop.sh not found"
              :duration 0 :exit-code -1 :passed :error
              :metadata (list :error "loop.sh not found"))))
    (unwind-protect
        (handler-case
            (progn
              ;; Set up working directory
              (if (rh-template-dir harness)
                  ;; Copy template
                  (uiop:run-program
                   (list "cp" "-r" (namestring (rh-template-dir harness)) (namestring work-dir)))
                  ;; Init empty git repo
                  (uiop:run-program
                   (list "git" "-C" (namestring work-dir) "init" "-q")))
              ;; Write prompt and plan
              (write-ralph-prompt work-dir (rh-mode harness) prompt)
              (write-ralph-plan work-dir (or description prompt))
              ;; Run ralph loop
              (let* ((command (format nil "cd ~a && bash ~a ~a ~a ~a"
                                     (shell-escape (namestring work-dir))
                                     (shell-escape (namestring script))
                                     (rh-mode harness)
                                     (rh-backend harness)
                                     (rh-max-iterations harness)))
                     (output (uiop:run-program
                              (list "/bin/sh" "-c" command)
                              :output '(:string :stripped)
                              :error-output '(:string :stripped)
                              :ignore-error-status t))
                     (duration (/ (- (get-precise-time) start-time) 1000000.0))
                     (commits (count-git-commits work-dir))
                     (stop-reason (read-stop-reason work-dir))
                     ;; Run verifier against the working directory state
                     (passed (if verifier
                                 (run-verifier verifier (or output "")
                                               :expected expected
                                               :exit-code 0)
                                 nil)))
                (list :output output
                      :tool-calls nil
                      :duration duration
                      :cost nil ; ralph doesn't report cost directly
                      :turns commits ; commits ≈ iterations ≈ turns
                      :exit-code 0
                      :passed passed
                      :metadata (list :backend (rh-backend harness)
                                      :mode (rh-mode harness)
                                      :max-iterations (rh-max-iterations harness)
                                      :actual-commits commits
                                      :stop-reason stop-reason
                                      :work-dir (namestring work-dir)))))
          (error (e)
            (let ((duration (/ (- (get-precise-time) start-time) 1000000.0)))
              (list :output (format nil "Ralph error: ~a" e)
                    :duration duration
                    :exit-code -1
                    :passed :error
                    :metadata (list :error (format nil "~a" e))))))
      ;; Cleanup (but only if no errors need investigation)
      ;; For now, leave work-dir for debugging; caller can clean up
      nil)))

(defmethod harness-to-config-plist ((harness ralph-harness))
  (list :type "ralph"
        :name (harness-name harness)
        :backend (rh-backend harness)
        :mode (rh-mode harness)
        :max-iterations (rh-max-iterations harness)))
