;;;; demo-setup.lisp — Comprehensive demo script for blog screenshots
;;;;
;;;; Creates all the state needed to populate the Command Center with
;;;; realistic data: agents, cognitive cycles, snapshots, branches,
;;;; teams, eval scenarios, Shen Prolog rules, and the API server.
;;;;
;;;; Usage:
;;;;   cd /path/to/autopoiesis && sbcl --load blog/demo-setup.lisp
;;;;
;;;; Each section is wrapped in handler-case so failures are non-fatal.
;;;; The script prints clear status messages and continues on error.

;;; ====================================================================
;;; Section 1: Bootstrap — load systems, open store, start conductor
;;; ====================================================================

(format t "~%========================================~%")
(format t " Autopoiesis Demo Setup~%")
(format t "========================================~%~%")

(require :asdf)

;; Register all package directories
(dolist (dir '("packages/core/" "packages/substrate/" "packages/api-server/"
              "packages/eval/" "packages/shen/" "packages/swarm/"
              "packages/team/" "packages/supervisor/" "packages/crystallize/"
              "packages/jarvis/" "packages/holodeck/" "packages/paperclip/"
              "packages/sandbox/" "packages/research/"
              "vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(format t "[1/8] Loading systems...~%")

;; Load core system (required — abort if this fails)
(handler-bind ((warning #'muffle-warning))
  (asdf:load-system :autopoiesis))
(format t "  - :autopoiesis loaded~%")

;; Load optional systems with graceful failure
(dolist (system '(:autopoiesis/api :autopoiesis-shen :autopoiesis/eval
                 :autopoiesis/swarm :autopoiesis/team))
  (handler-case
      (progn
        (handler-bind ((warning #'muffle-warning))
          (asdf:load-system system))
        (format t "  - ~A loaded~%" system))
    (error (e)
      (format *error-output* "  ! ~A unavailable: ~A~%" system e))))

;;; ====================================================================
;;; Shared mutable state — set by sections, read by later sections
;;; ====================================================================

(defvar *demo-agents* nil "Freshly created persistent agents.")
(defvar *demo-evolved* nil "Agents after cognitive cycles.")

;;; ====================================================================
;;; Main body — everything runs inside with-store
;;; ====================================================================

(format t "~%[1/8] Starting system (substrate + conductor)...~%")

(autopoiesis.substrate:with-store ()

  ;; Start system (conductor + monitoring)
  (handler-case
      (progn
        (autopoiesis.orchestration:start-system :start-conductor t)
        (format t "  - System started (conductor + monitoring)~%"))
    (error (e)
      (format *error-output* "  ! start-system partial failure: ~A~%" e)
      ;; Ensure at least the store is open
      (handler-case (autopoiesis.substrate:open-store)
        (error () nil))))

  ;; ==================================================================
  ;; Section 2: Create 5 agents
  ;; ==================================================================

  (format t "~%[2/8] Creating agents...~%")

  (handler-case
      (let ((specs '(("architect" :design :review :analyze)
                     ("coder"     :code :test :debug)
                     ("reviewer"  :review :security :analyze)
                     ("researcher" :search :analyze :report)
                     ("reasoner"  :logic :analyze :verify))))
        (setf *demo-agents*
              (mapcar (lambda (spec)
                        (autopoiesis.agent:make-persistent-agent
                         :name (first spec)
                         :capabilities (rest spec)))
                      specs))
        (dolist (a *demo-agents*)
          (format t "  - ~A: ~D capabilities~%"
                  (autopoiesis.agent:persistent-agent-name a)
                  (autopoiesis.core:pset-count
                   (autopoiesis.agent:persistent-agent-capabilities a)))))
    (error (e)
      (format *error-output* "  ! Agent creation failed: ~A~%" e)))

  ;; ==================================================================
  ;; Section 3: Run cognitive cycles
  ;; ==================================================================

  (format t "~%[3/8] Running cognitive cycles...~%")

  (handler-case
      (let ((inputs '(("architect"  "Design the authentication subsystem"
                                    "Review the API gateway architecture"
                                    "Analyze performance bottlenecks")
                      ("coder"      "Implement JWT token validation"
                                    "Write unit tests for auth module"
                                    "Debug race condition in session store")
                      ("reviewer"   "Review pull request #42: auth refactor"
                                    "Check for SQL injection vulnerabilities")
                      ("researcher" "Research OIDC best practices"
                                    "Analyze competitor auth implementations"
                                    "Report on OAuth2 security considerations")
                      ("reasoner"   "Verify authentication flow correctness"
                                    "Check deployment dependency graph"))))
        (setf *demo-evolved*
              (mapcar
               (lambda (agent)
                 (let* ((name (autopoiesis.agent:persistent-agent-name agent))
                        (agent-inputs (rest (assoc name inputs :test #'string=)))
                        (current agent))
                   (dolist (text agent-inputs)
                     (handler-case
                         (let* ((a1 (autopoiesis.agent:persistent-perceive
                                     current (list :input text)))
                                (a2 (autopoiesis.agent:persistent-reason a1))
                                (a3 (autopoiesis.agent:persistent-decide a2))
                                (a4 (autopoiesis.agent:persistent-act a3))
                                (a5 (autopoiesis.agent:persistent-reflect a4)))
                           (setf current a5))
                       (error (e)
                         ;; Partial cycle fallback
                         (handler-case
                             (let* ((a1 (autopoiesis.agent:persistent-perceive
                                         current (list :input text)))
                                    (a2 (autopoiesis.agent:persistent-reason a1)))
                               (setf current a2))
                           (error (e2)
                             (declare (ignore e2))
                             (format *error-output*
                                     "  ! Cycle failed for ~A: ~A~%" name e))))))
                   (format t "  - ~A: ~D thoughts after ~D cycles~%"
                           name
                           (autopoiesis.core:pvec-length
                            (autopoiesis.agent:persistent-agent-thoughts current))
                           (length agent-inputs))
                   current))
               *demo-agents*)))
    (error (e)
      (format *error-output* "  ! Cognitive cycle section failed: ~A~%" e)
      ;; Fallback: use un-evolved agents
      (unless *demo-evolved*
        (setf *demo-evolved* *demo-agents*))))

  ;; ==================================================================
  ;; Section 4: Snapshots and branches
  ;; ==================================================================

  (format t "~%[4/8] Creating snapshots and branches...~%")

  (handler-case
      (let ((snapshot-count 0))
        ;; Take snapshots of each evolved agent
        (dolist (agent (or *demo-evolved* *demo-agents*))
          (handler-case
              (let* ((name (autopoiesis.agent:persistent-agent-name agent))
                     (state (list :agent-name name
                                  :thoughts (autopoiesis.core:pvec-length
                                             (autopoiesis.agent:persistent-agent-thoughts agent))
                                  :capabilities (autopoiesis.core:pset-to-list
                                                 (autopoiesis.agent:persistent-agent-capabilities agent))))
                     (snap (autopoiesis.snapshot:make-snapshot
                            state
                            :metadata (list :agent name :demo t))))
                (incf snapshot-count)
                (format t "  - Snapshot ~A: ~A~%"
                        name (autopoiesis.snapshot:snapshot-id snap)))
            (error (e)
              (format *error-output* "  ! Snapshot failed: ~A~%" e))))

        ;; Create named branches
        (handler-case
            (progn
              (autopoiesis.snapshot:create-branch "feature/auth-redesign")
              (format t "  - Branch: feature/auth-redesign~%")
              (autopoiesis.snapshot:create-branch "experiment/prolog-reasoning")
              (format t "  - Branch: experiment/prolog-reasoning~%"))
          (error (e)
            (format *error-output* "  ! Branch creation failed: ~A~%" e)))

        ;; Fork the first agent
        (when *demo-evolved*
          (handler-case
              (multiple-value-bind (child updated-parent)
                  (autopoiesis.agent:persistent-fork
                   (first *demo-evolved*)
                   :name "architect-experimental")
                (declare (ignore updated-parent))
                (format t "  - Forked: ~A (from ~A)~%"
                        (autopoiesis.agent:persistent-agent-name child)
                        (autopoiesis.agent:persistent-agent-name (first *demo-evolved*)))
                ;; Run a cycle on the fork to diverge it
                (handler-case
                    (let* ((a1 (autopoiesis.agent:persistent-perceive
                                child '(:input "Explore microservices decomposition")))
                           (a2 (autopoiesis.agent:persistent-reason a1)))
                      (declare (ignore a2))
                      (format t "  - Fork diverged with additional cognition~%"))
                  (error (e)
                    (format *error-output* "  ! Fork divergence failed: ~A~%" e))))
            (error (e)
              (format *error-output* "  ! Fork failed: ~A~%" e))))

        (format t "  - Total snapshots: ~D~%" snapshot-count))
    (error (e)
      (format *error-output* "  ! Snapshot section failed: ~A~%" e)))

  ;; ==================================================================
  ;; Section 5: Teams
  ;; ==================================================================

  (format t "~%[5/8] Creating teams...~%")

  (handler-case
      (if (find-package :autopoiesis.team)
          (let ((create-fn (find-symbol "CREATE-TEAM" :autopoiesis.team)))
            (if (and create-fn (fboundp create-fn))
                (progn
                  ;; Team 1: Architecture review (leader-worker)
                  (handler-case
                      (progn
                        (funcall create-fn "architecture-review"
                                 :strategy :leader-worker
                                 :task "Review and improve system architecture")
                        (format t "  - Team: architecture-review (leader-worker)~%"))
                    (error (e)
                      (format *error-output* "  ! Team 1 failed: ~A~%" e)))
                  ;; Team 2: Security audit (parallel)
                  (handler-case
                      (progn
                        (funcall create-fn "security-audit"
                                 :strategy :parallel
                                 :task "Parallel security audit of all modules")
                        (format t "  - Team: security-audit (parallel)~%"))
                    (error (e)
                      (format *error-output* "  ! Team 2 failed: ~A~%" e))))
                (format t "  - Skipped (CREATE-TEAM not found)~%")))
          (format t "  - Skipped (autopoiesis.team not loaded)~%"))
    (error (e)
      (format *error-output* "  ! Team section failed: ~A~%" e)))

  ;; ==================================================================
  ;; Section 6: Eval — load builtin scenarios and create a run
  ;; ==================================================================

  (format t "~%[6/8] Loading eval scenarios...~%")

  (handler-case
      (if (find-package :autopoiesis.eval)
          (let ((load-fn (find-symbol "LOAD-BUILTIN-SCENARIOS" :autopoiesis.eval))
                (list-fn (find-symbol "LIST-SCENARIOS" :autopoiesis.eval))
                (create-run-fn (find-symbol "CREATE-EVAL-RUN" :autopoiesis.eval)))
            ;; Load builtin scenarios
            (when (and load-fn (fboundp load-fn))
              (funcall load-fn)
              (format t "  - Builtin scenarios loaded~%"))
            ;; Report count
            (when (and list-fn (fboundp list-fn))
              (let ((scenarios (funcall list-fn)))
                (format t "  - Total scenarios: ~D~%" (length scenarios))
                ;; Create a demo eval run (not executed — just metadata)
                (when (and create-run-fn (fboundp create-run-fn)
                           (>= (length scenarios) 3))
                  (handler-case
                      (let* ((subset (subseq scenarios 0 3))
                             (run-id (funcall create-run-fn
                                              :name "Demo Eval Run"
                                              :scenarios subset
                                              :harnesses '("echo-harness")
                                              :trials 1)))
                        (format t "  - Eval run created: ~A (3 scenarios)~%" run-id))
                    (error (e)
                      (format *error-output* "  ! Eval run creation failed: ~A~%" e)))))))
          (format t "  - Skipped (autopoiesis.eval not loaded)~%"))
    (error (e)
      (format *error-output* "  ! Eval section failed: ~A~%" e)))

  ;; ==================================================================
  ;; Section 7: Shen Prolog rules and reasoning agent
  ;; ==================================================================

  (format t "~%[7/8] Setting up Shen Prolog rules...~%")

  (handler-case
      (if (find-package :autopoiesis.shen)
          (let ((ensure-fn (find-symbol "ENSURE-SHEN-LOADED" :autopoiesis.shen))
                (define-fn (find-symbol "DEFINE-RULE" :autopoiesis.shen))
                (list-fn (find-symbol "LIST-RULES" :autopoiesis.shen))
                (add-knowledge-fn (find-symbol "ADD-KNOWLEDGE" :autopoiesis.shen)))

            ;; Try loading the Shen kernel (may fail if shen-cl not installed)
            (when (and ensure-fn (fboundp ensure-fn))
              (handler-case
                  (progn
                    (funcall ensure-fn)
                    (format t "  - Shen kernel loaded~%"))
                (error (e)
                  (format t "  - Shen runtime not installed (rules stored as data): ~A~%" e))))

            ;; Define rules — stored in *rule-store* even without Shen runtime
            (when (and define-fn (fboundp define-fn))
              ;; quality-check: required project files
              (handler-case
                  (progn
                    (funcall define-fn :quality-check
                             '((quality-check Tree)
                               <-- (has-file Tree "src/main.lisp")
                                   (has-file Tree "README.md")
                                   (has-file Tree "tests/run.lisp")))
                    (format t "  - Rule: :quality-check (required files)~%"))
                (error (e)
                  (format *error-output* "  ! Rule :quality-check failed: ~A~%" e)))

              ;; deploy-safe: dependency verification
              (handler-case
                  (progn
                    (funcall define-fn :deploy-safe
                             '((deploy-safe System)
                               <-- (all-deps-met System)
                                   (tests-pass System)
                                   (no-vulnerabilities System)))
                    (format t "  - Rule: :deploy-safe (deployment checks)~%"))
                (error (e)
                  (format *error-output* "  ! Rule :deploy-safe failed: ~A~%" e)))

              ;; code-review: PR quality checks
              (handler-case
                  (progn
                    (funcall define-fn :code-review
                             '((code-review Diff)
                               <-- (no-debug-prints Diff)
                                   (has-tests Diff)
                                   (follows-style Diff)))
                    (format t "  - Rule: :code-review (PR checks)~%"))
                (error (e)
                  (format *error-output* "  ! Rule :code-review failed: ~A~%" e))))

            ;; Report rule count
            (when (and list-fn (fboundp list-fn))
              (format t "  - Total rules defined: ~D~%" (length (funcall list-fn))))

            ;; Create a CLOS reasoning agent with the shen-reasoning-mixin
            (when (and add-knowledge-fn (fboundp add-knowledge-fn))
              (let ((mixin-sym (find-symbol "SHEN-REASONING-MIXIN" :autopoiesis.shen))
                    (agent-sym (find-symbol "AGENT" :autopoiesis.agent)))
                (when (and mixin-sym agent-sym
                           (find-class mixin-sym nil)
                           (find-class agent-sym nil))
                  (handler-case
                      (progn
                        ;; Build a combined class dynamically
                        (let ((prolog-class
                                (make-instance 'standard-class
                                               :name 'demo-prolog-agent
                                               :direct-superclasses
                                               (list (find-class agent-sym)
                                                     (find-class mixin-sym))
                                               :direct-slots nil)))
                          #+sbcl (sb-mop:finalize-inheritance prolog-class)
                          (let ((pa (make-instance prolog-class
                                                   :name "prolog-reasoner")))
                            (funcall add-knowledge-fn pa :ancestor
                                     '((ancestor X Y) <-- (parent X Y))
                                     '((ancestor X Y) <-- (parent X Z) (ancestor Z Y)))
                            (funcall add-knowledge-fn pa :code-safe
                                     '((code-safe Module) <-- (has-tests Module)
                                                               (no-eval Module)))
                            (format t "  - Prolog reasoning agent: 2 knowledge rules~%"))))
                    (error (e)
                      (format *error-output* "  ! Prolog agent failed: ~A~%" e)))))))
          (format t "  - Skipped (autopoiesis.shen not loaded)~%"))
    (error (e)
      (format *error-output* "  ! Shen section failed: ~A~%" e)))

  ;; ==================================================================
  ;; Section 8: Start API server and keep alive
  ;; ==================================================================

  (format t "~%[8/8] Starting API server...~%")

  (let ((api-port 8080)
        (server-started nil))
    (handler-case
        (if (find-package :autopoiesis.api)
            (let ((start-fn (find-symbol "START-API-SERVER" :autopoiesis.api)))
              (when (and start-fn (fboundp start-fn))
                (funcall start-fn :port api-port)
                (setf server-started t)
                (format t "  - API server running on port ~D~%" api-port)))
            (format t "  - Skipped (autopoiesis.api not loaded)~%"))
      (error (e)
        (format *error-output* "  ! API server failed: ~A~%" e)))

    (format t "~%========================================~%")
    (format t " Demo setup complete!~%")
    (format t "========================================~%~%")

    (when server-started
      (format t "Endpoints:~%")
      (format t "  REST API:     http://localhost:~D/api/agents~%" api-port)
      (format t "  WebSocket:    ws://localhost:~D/ws~%" api-port)
      (format t "  Scenarios:    http://localhost:~D/api/eval/scenarios~%" api-port)
      (format t "  Eval runs:    http://localhost:~D/api/eval/runs~%" api-port)
      (format t "~%"))

    (format t "Press Ctrl-C to stop.~%~%")

    ;; Keep the process alive
    (handler-case
        (loop (sleep 60))
      (#+sbcl sb-sys:interactive-interrupt
       #-sbcl condition ()
       (format t "~%Shutting down...~%")
       ;; Clean shutdown
       (handler-case
           (when (find-package :autopoiesis.api)
             (let ((stop-fn (find-symbol "STOP-API-SERVER" :autopoiesis.api)))
               (when (and stop-fn (fboundp stop-fn))
                 (funcall stop-fn)
                 (format t "  - API server stopped~%"))))
         (error (e)
           (format *error-output* "  ! API shutdown error: ~A~%" e)))
       (handler-case
           (let ((stop-fn (find-symbol "STOP-SYSTEM" :autopoiesis.orchestration)))
             (when (and stop-fn (fboundp stop-fn))
               (funcall stop-fn)))
         (error (e)
           (format *error-output* "  ! System shutdown error: ~A~%" e)))
       (format t "Done.~%")
       #+sbcl (sb-ext:exit)))))
