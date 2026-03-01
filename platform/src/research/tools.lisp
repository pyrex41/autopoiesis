;;;; tools.lisp - Sandbox-backed capabilities for research trial agents
;;;;
;;;; Defines capabilities that trial agents use to interact with their sandbox.
;;;; Each capability takes advantage of the dynamically-bound *trial-sandbox-id*
;;;; to route commands to the correct sandbox.
;;;;
;;;; These are used in :tool-backed mode where the agent runs in AP
;;;; and executes commands in the sandbox via tool calls.

(in-package #:autopoiesis.research)

;;; ── Trial sandbox binding ───────────────────────────────────────

(defvar *trial-sandbox-id* nil
  "Dynamically bound to the current trial's sandbox ID during execution.")

;;; ── Sandbox tool capabilities ───────────────────────────────────

(autopoiesis.agent:defcapability sandbox-exec (&key command timeout working-directory)
  "Execute a shell command in the trial's sandbox.
   COMMAND - Shell command string to execute.
   TIMEOUT - Seconds before timeout (default: 120).
   WORKING-DIRECTORY - Directory to run in (default: /workspace).
   Returns stdout, stderr, and exit code."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-exec "Error: No sandbox bound for this trial"))
  (unless autopoiesis.sandbox:*sandbox-manager*
    (return-from sandbox-exec "Error: Sandbox manager not initialized"))
  (handler-case
      (let ((result (autopoiesis.sandbox:exec-in-sandbox
                     *trial-sandbox-id*
                     command
                     :timeout (or timeout 120)
                     :workdir (or working-directory "/workspace"))))
        (let ((exit-code (squashd:exec-result-exit-code result))
              (stdout (squashd:exec-result-stdout result))
              (stderr (squashd:exec-result-stderr result)))
          (format nil "Exit code: ~A~%~%STDOUT:~%~A~@[~%~%STDERR:~%~A~]"
                  exit-code stdout
                  (when (and stderr (> (length stderr) 0)) stderr))))
    (error (e)
      (format nil "Sandbox exec error: ~A" e))))

(autopoiesis.agent:defcapability sandbox-write-file (&key path content)
  "Write a file into the trial's sandbox.
   PATH - Absolute path inside the sandbox (e.g., /workspace/script.py).
   CONTENT - File content as a string."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-write-file "Error: No sandbox bound"))
  (unless autopoiesis.sandbox:*sandbox-manager*
    (return-from sandbox-write-file "Error: Sandbox manager not initialized"))
  ;; Write via base64 encoding to avoid shell escaping issues
  (handler-case
      (let* ((encoded (ironclad:byte-array-to-hex-string
                       (babel:string-to-octets content :encoding :utf-8)))
             ;; Use printf with hex for safe transfer, or simpler: just use cat with heredoc
             ;; Actually, the safest approach is base64
             (b64 (cl-base64:string-to-base64-string content))
             (cmd (format nil "mkdir -p \"$(dirname '~A')\" && echo '~A' | base64 -d > '~A'"
                          path b64 path))
             (result (autopoiesis.sandbox:exec-in-sandbox
                      *trial-sandbox-id* cmd :timeout 10)))
        (declare (ignore encoded))
        (if (zerop (squashd:exec-result-exit-code result))
            (format nil "Wrote ~A bytes to ~A" (length content) path)
            (format nil "Error writing ~A: ~A" path
                    (squashd:exec-result-stderr result))))
    (error (e)
      (format nil "Error: ~A" e))))

(autopoiesis.agent:defcapability sandbox-read-file (&key path)
  "Read a file from the trial's sandbox.
   PATH - Absolute path inside the sandbox."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-read-file "Error: No sandbox bound"))
  (unless autopoiesis.sandbox:*sandbox-manager*
    (return-from sandbox-read-file "Error: Sandbox manager not initialized"))
  (handler-case
      (let ((result (autopoiesis.sandbox:exec-in-sandbox
                     *trial-sandbox-id*
                     (format nil "cat '~A'" path)
                     :timeout 10)))
        (if (zerop (squashd:exec-result-exit-code result))
            (squashd:exec-result-stdout result)
            (format nil "Error reading ~A: ~A" path
                    (squashd:exec-result-stderr result))))
    (error (e)
      (format nil "Error: ~A" e))))

(autopoiesis.agent:defcapability sandbox-install (&key packages manager)
  "Install packages in the trial's sandbox.
   PACKAGES - Space-separated package names (e.g., \"pandas numpy matplotlib\").
   MANAGER - Package manager to use: \"pip\", \"npm\", \"apk\" (default: \"pip\")."
  :permissions (:sandbox-execution)
  :body
  (unless *trial-sandbox-id*
    (return-from sandbox-install "Error: No sandbox bound"))
  (unless autopoiesis.sandbox:*sandbox-manager*
    (return-from sandbox-install "Error: Sandbox manager not initialized"))
  (let* ((mgr (or manager "pip"))
         (cmd (cond
                ((string= mgr "pip") (format nil "pip install --quiet ~A" packages))
                ((string= mgr "npm") (format nil "npm install -g ~A" packages))
                ((string= mgr "apk") (format nil "apk add --quiet ~A" packages))
                (t (format nil "~A install ~A" mgr packages)))))
    (handler-case
        (let ((result (autopoiesis.sandbox:exec-in-sandbox
                       *trial-sandbox-id* cmd
                       :timeout 300  ; installs can be slow
                       :workdir "/workspace")))
          (if (zerop (squashd:exec-result-exit-code result))
              (format nil "Installed: ~A" packages)
              (format nil "Install failed (exit ~A): ~A"
                      (squashd:exec-result-exit-code result)
                      (squashd:exec-result-stderr result))))
      (error (e)
        (format nil "Error: ~A" e)))))

(defun research-tool-capabilities ()
  "Return the list of capability names for research trial agents."
  '(sandbox-exec sandbox-write-file sandbox-read-file sandbox-install))
