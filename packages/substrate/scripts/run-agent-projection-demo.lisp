;;;; run-agent-projection-demo.lisp - Slice 2 end-to-end with a REAL agent
;;;;
;;;; Same projection->capture->merge loop as run-tmpfs-projection-demo.lisp, but
;;;; a live coding agent does the work in the ephemeral dir. Best-effort / live
;;;; API + non-deterministic: we assert the MECHANISM (whatever the agent wrote
;;;; got captured to blobs+datoms, merged into base, and re-materializes
;;;; byte-exact), not specific content.
;;;;
;;;; Agent selected by env SB_AGENT (all default to your grok account):
;;;;   grok (default)  -> grok -p PROMPT --cwd DIR --always-approve         (grok.com)
;;;;   rho-grok        -> rho --model grok-code-fast-1 -C DIR -p PROMPT ...  (grok via rho)
;;;;   opencode-grok   -> opencode run --dir DIR -m xai/grok-4.3 PROMPT      (grok via opencode)
;;;;   rho             -> rho -C DIR -p PROMPT --output-format text          (Anthropic; may 429)
;;;;
;;;; Note: agents are known to sometimes write outside the cwd. If nothing lands
;;;; in the projection, we report it honestly -- the substrate loop is still
;;;; correct (see run-tmpfs-projection-demo.lisp, the deterministic GO).
;;;;
;;;;   SB_AGENT=opencode-grok sbcl --noinform --non-interactive --load \
;;;;     packages/substrate/scripts/run-agent-projection-demo.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-agent-projection-demo
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)
                    (#:snap #:autopoiesis.snapshot)))
(in-package #:sb-agent-projection-demo)

(defparameter *rho* "/Users/reuben/.local/bin/rho")
(defparameter *grok* "/Users/reuben/.grok/bin/grok")
(defparameter *opencode* "/Users/reuben/.bun/bin/opencode")
(defparameter *grok-model* "grok-4.3") ; xAI model id; rho accepts it as a raw model id
(defparameter *agent* (or (uiop:getenv "SB_AGENT") "grok"))

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

;;; --- bridge (same as run-tmpfs-projection-demo.lisp) ---
(defun bytes<-string (x) (babel:string-to-octets x :encoding :utf-8))
(defun string<-bytes (b) (babel:octets-to-string b :encoding :utf-8))
(defun file-key (path) (format nil "file:~A" path))

(defun base-set-file (cs path content)
  (let ((hash (snap::store-put-blob cs (bytes<-string content))))
    (s:transact! (list (s:make-datom (file-key path) "file/content-hash" hash)
                       (s:make-datom "module" "module/file" path)))
    hash))

(defun visible-paths (branch)
  (let ((paths (remove-duplicates
                (mapcar (lambda (e) (getf e :value))
                        (s:entity-history "module" "module/file" :last-n 10000))
                :test #'equal)))
    (dolist (w (s:datom-branch-writes branch))
      (when (equal (s:branch-write-attribute w) "module/file")
        (pushnew (s:branch-write-value w) paths :test #'equal)))
    paths))

(defun project-branch (branch cs dir)
  (let ((entries
          (loop for path in (visible-paths branch)
                for hash = (s:branch-read branch (file-key path) "file/content-hash")
                for bytes = (and hash (snap::store-get-blob cs hash))
                when bytes
                  collect (snap::make-file-entry path hash 33188 (length bytes) 0))))
    (snap::materialize-tree entries dir cs)
    entries))

(defun capture-into-branch (branch cs dir projected-entries)
  (let ((proj (make-hash-table :test 'equal)) (captured nil))
    (dolist (e projected-entries)
      (when (eq (snap::entry-type e) :file)
        (setf (gethash (snap::entry-path e) proj) (snap::entry-hash e))))
    (dolist (e (snap::scan-directory-flat dir cs
                  :exclude '(".git" "node_modules" ".opencode" ".ruff_cache"
                             "__pycache__" ".pytest_cache" ".mypy_cache")))
      (when (eq (snap::entry-type e) :file)
        (let* ((path (snap::entry-path e)) (hash (snap::entry-hash e))
               (old (gethash path proj)))
          (unless (equal old hash)
            (s:branch-stage branch (file-key path) "file/content-hash" hash)
            (unless old (s:branch-stage branch "module" "module/file" path))
            (push path captured)))))
    (nreverse captured)))

(defun read-disk-file (dir path)
  (string<-bytes (snap::read-file-bytes (namestring (merge-pathnames path dir)))))

(defun read-disk-bytes (dir path)
  (snap::read-file-bytes (namestring (merge-pathnames path dir))))

(defun files-byte-equal (dir1 dir2 path)
  "Binary-safe file comparison (handles non-UTF-8 content)."
  (equalp (read-disk-bytes dir1 path) (read-disk-bytes dir2 path)))

(defparameter *prompt*
  "In the CURRENT directory only, using relative paths: add a function greet(name) that returns the string 'Hello ' followed by name to main.py, and create a new file greet.py that imports greet from main and prints greet('world'). Make minimal edits.")

(defun drive-agent (dir)
  "Run the selected agent in DIR. Returns the exit code (0 = clean)."
  (let ((argv (cond
                ((string= *agent* "grok")
                 (list *grok* "-p" *prompt* "--cwd" (namestring dir) "--always-approve"))
                ((string= *agent* "rho-grok")
                 (list *rho* "--model" *grok-model* "-C" (namestring dir)
                       "-p" *prompt* "--output-format" "text"))
                ((string= *agent* "rho")
                 (list *rho* "-C" (namestring dir) "-p" *prompt* "--output-format" "text"))
                ((string= *agent* "opencode-grok")
                 (list *opencode* "run" "--dir" (namestring dir) "-m" "xai/grok-4.3" *prompt*))
                (t (error "unknown SB_AGENT ~A" *agent*)))))
    (format t "~&== driving agent [~A] in ~A ==~%  ~{~A ~}~%" *agent* dir argv)
    (handler-case
        (multiple-value-bind (out err code)
            (uiop:run-program argv :input nil :output :string :error-output :string
                                   :ignore-error-status t)
          (declare (ignore out))
          (format t "  (exit ~A)~@[ stderr: ~A~]~%" code
                  (when (and err (plusp (length err)))
                    (subseq err 0 (min 240 (length err)))))
          code)
      (error (e) (format t "  agent run errored: ~A~%" e) -1))))

(defun run-demo ()
  (setf *fails* nil)
  (s:with-store ()
    (s:declare-cardinality "file/content-hash" :one)
    (s:declare-cardinality "module/file"       :many)
    (let ((cs (snap::make-content-store))
          (h0 nil))
      (setf h0 (base-set-file cs "main.py" "def add(a, b):
    return a + b
"))
      (let* ((br (s:branch-fork :name "agent"))
             (dir (format nil "/tmp/sb-agent-proj-~A/" (get-universal-time)))
             (projected (progn (ensure-directories-exist dir) (project-branch br cs dir))))
        (check "projection reconstructed main.py for the agent"
               (search "def add" (read-disk-file dir "main.py")))

        (drive-agent dir)

        (let ((captured (capture-into-branch br cs dir projected)))
          (format t "  captured files: ~S~%" captured)
          (check "agent produced at least one captured file change" (plusp (length captured)))
          (check "base main.py unchanged before merge (still h0)"
                 (equal (s:entity-attr (file-key "main.py") "file/content-hash") h0))

          (multiple-value-bind (applied conflicts) (s:branch-merge br)
            (check "agent's captured writes merged into base"
                   (and (plusp applied) (null conflicts))
                   (list :applied applied :conflicts (length conflicts))))

          ;; round-trip fidelity: regenerate base into a fresh dir, compare bytes
          (when (plusp (length captured))
            (let ((dir2 (format nil "/tmp/sb-agent-verify-~A/" (get-universal-time)))
                  (br2 (s:branch-fork :name "verify")))
              (ensure-directories-exist dir2)
              (project-branch br2 cs dir2)
              (check "every captured file re-materializes byte-exact from substrate"
                     (every (lambda (p) (files-byte-equal dir dir2 p)) captured)
                     captured)
              (ignore-errors (uiop:delete-directory-tree (pathname dir2) :validate t))))
          (ignore-errors (uiop:delete-directory-tree (pathname dir) :validate t))))))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-demo))
