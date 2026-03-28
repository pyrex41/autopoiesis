;;;; start-backend.lisp — Start the autopoiesis backend for screenshots
(require :asdf)
(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))

;; Register package directories with ASDF
(dolist (dir '("packages/core/" "packages/substrate/" "packages/api-server/"
              "packages/eval/" "packages/shen/" "packages/swarm/"
              "packages/team/" "packages/supervisor/" "packages/crystallize/"
              "packages/jarvis/" "packages/paperclip/"
              "packages/sandbox/" "packages/research/"
              "vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

;; Explicitly load .asd files whose system names don't match their filenames
;; (e.g., api-server.asd defines system "autopoiesis/api")
(dolist (asd '("packages/api-server/api-server.asd"
              "packages/eval/eval.asd"
              "packages/shen/autopoiesis-shen.asd"
              "packages/swarm/swarm.asd"
              "packages/team/team.asd"
              "packages/supervisor/supervisor.asd"))
  (when (probe-file asd)
    (handler-case (asdf:load-asd (truename asd))
      (error () nil))))

(format t "~%=== Loading core ===~%")
(handler-bind ((warning #'muffle-warning))
  (ql:quickload :autopoiesis :silent t))
(format t "Core loaded.~%")

(format t "~%=== Loading API server ===~%")
(handler-case
    (progn
      (handler-bind ((warning #'muffle-warning))
        (ql:quickload :autopoiesis/api :silent t))
      (format t "API server loaded.~%"))
  (error (e)
    (format t "API load error: ~A~%" e)))

;; Load optional packages
(handler-case
    (handler-bind ((warning #'muffle-warning))
      (ql:quickload :autopoiesis/eval :silent t)
      (format t "Eval loaded.~%"))
  (error (e) (format t "Eval skip: ~A~%" e)))

(handler-case
    (handler-bind ((warning #'muffle-warning))
      (ql:quickload :autopoiesis-shen :silent t)
      (format t "Shen extension loaded.~%"))
  (error (e) (format t "Shen skip: ~A~%" e)))

;; Open store and start system
(format t "~%=== Starting system ===~%")
(autopoiesis.substrate:open-store)
(format t "Store opened.~%")

;; Create demo agents
(format t "~%=== Creating demo agents ===~%")
(let* ((architect (autopoiesis.agent:make-persistent-agent
                   :name "architect"
                   :capabilities '(:design :review :analyze)))
       (coder (autopoiesis.agent:make-persistent-agent
               :name "coder"
               :capabilities '(:code :test :debug)))
       (reviewer (autopoiesis.agent:make-persistent-agent
                  :name "reviewer"
                  :capabilities '(:review :security :analyze)))
       (researcher (autopoiesis.agent:make-persistent-agent
                    :name "researcher"
                    :capabilities '(:search :analyze :report)))
       (reasoner (autopoiesis.agent:make-persistent-agent
                  :name "reasoner"
                  :capabilities '(:logic :analyze :verify))))

  ;; Run cognitive cycles to generate thoughts
  (format t "Running cognitive cycles...~%")
  (handler-case
      (progn
        (setf architect (autopoiesis.agent:persistent-perceive architect '(:input "design auth module")))
        (setf architect (autopoiesis.agent:persistent-reason architect))
        (setf coder (autopoiesis.agent:persistent-perceive coder '(:input "implement JWT tokens")))
        (setf coder (autopoiesis.agent:persistent-reason coder))
        (setf reviewer (autopoiesis.agent:persistent-perceive reviewer '(:input "review auth code for vulnerabilities")))
        (setf reviewer (autopoiesis.agent:persistent-reason reviewer))
        (setf researcher (autopoiesis.agent:persistent-perceive researcher '(:input "compare OAuth2 vs SAML")))
        (setf researcher (autopoiesis.agent:persistent-reason researcher))
        (setf reasoner (autopoiesis.agent:persistent-perceive reasoner '(:input "verify deployment constraints")))
        (setf reasoner (autopoiesis.agent:persistent-reason reasoner))
        (format t "Cognitive cycles complete.~%"))
    (error (e) (format t "Cycle error: ~A~%" e)))

  ;; Fork an agent
  (format t "Forking architect...~%")
  (handler-case
      (multiple-value-bind (child parent)
          (autopoiesis.agent:persistent-fork architect :name "architect-v2")
        (declare (ignore parent))
        (format t "Forked: ~A~%" (autopoiesis.agent:persistent-agent-name child)))
    (error (e) (format t "Fork error: ~A~%" e)))

  ;; Take snapshots
  (format t "Taking snapshots...~%")
  (handler-case
      (progn
        (autopoiesis.snapshot:make-snapshot architect)
        (autopoiesis.snapshot:make-snapshot coder)
        (autopoiesis.snapshot:make-snapshot reviewer)
        (format t "Snapshots created.~%"))
    (error (e) (format t "Snapshot error: ~A~%" e))))

;; Load eval scenarios
(format t "~%=== Loading eval scenarios ===~%")
(handler-case
    (let ((pkg (find-package :autopoiesis.eval)))
      (when pkg
        (let ((load-fn (find-symbol "LOAD-BUILTIN-SCENARIOS" pkg)))
          (when (and load-fn (fboundp load-fn))
            (funcall load-fn)
            (format t "18 builtin scenarios loaded.~%")))))
  (error (e) (format t "Eval scenario error: ~A~%" e)))

;; Define Prolog rules (works without Shen)
(format t "~%=== Defining Prolog rules ===~%")
(handler-case
    (let ((pkg (find-package :autopoiesis.shen)))
      (when pkg
        (let ((define-fn (find-symbol "DEFINE-RULE" pkg)))
          (when (and define-fn (fboundp define-fn))
            (funcall define-fn :quality-check
                     '((quality-check Tree) <--
                       (has-file Tree "README.md")
                       (has-file Tree "src/")
                       (has-file Tree "tests/")))
            (funcall define-fn :deploy-safe
                     '((deploy-safe Module) <--
                       (tested Module)
                       (all-deps-tested Module)))
            (funcall define-fn :code-review
                     '((code-review File) <--
                       (has-tests File)
                       (no-lint-errors File)
                       (documented File)))
            (format t "3 Prolog rules defined.~%")))))
  (error (e) (format t "Prolog error: ~A~%" e)))

;; Start API server
(format t "~%=== Starting API server ===~%")
(handler-case
    (let ((pkg (find-package :autopoiesis.api)))
      (when pkg
        (let ((start-fn (find-symbol "START-API-SERVER" pkg)))
          (when (and start-fn (fboundp start-fn))
            (funcall start-fn :port 9090)
            (format t "~%API server started.~%")
            (format t "  WebSocket: ws://localhost:9090/ws~%")
            (format t "  REST:      http://localhost:9090/api/~%")))))
  (error (e) (format t "API server error: ~A~%" e)))

(format t "~%=== Backend ready for screenshots ===~%")
(format t "Start frontend: cd frontends/command-center && AP_WS_PORT=9090 AP_REST_PORT=9090 bun run dev~%")
(format t "Press Ctrl-C to stop.~%")

;; Keep alive
(handler-case
    (loop (sleep 60))
  (sb-sys:interactive-interrupt ()
    (format t "~%Shutting down...~%")
    (sb-ext:exit)))
