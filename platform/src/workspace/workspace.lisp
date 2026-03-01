;;;; workspace.lisp - Per-task ephemeral workspaces with pluggable isolation
;;;;
;;;; A workspace is an ephemeral execution context for a task.
;;;; It provides:
;;;;   - A rooted filesystem (directory or sandbox)
;;;;   - Path resolution (relative paths -> absolute paths within workspace)
;;;;   - Isolation level (:none, :directory, :sandbox)
;;;;   - Automatic cleanup on exit
;;;;
;;;; The isolation backend is pluggable. :directory is built-in.
;;;; :sandbox is registered by autopoiesis/sandbox when loaded.

(in-package #:autopoiesis.workspace)

;;; ── Isolation Backend Protocol ──────────────────────────────────

(defclass isolation-backend ()
  ((name :initarg :name
         :accessor backend-name
         :documentation "Backend identifier keyword"))
  (:documentation "Base class for workspace isolation backends."))

(defgeneric backend-create-workspace (backend workspace)
  (:documentation "Set up the isolation environment for a workspace."))

(defgeneric backend-destroy-workspace (backend workspace)
  (:documentation "Tear down the isolation environment for a workspace."))

(defgeneric backend-exec (backend workspace command &key timeout working-directory)
  (:documentation "Execute a command in the workspace's isolation context.
   Returns (values stdout stderr exit-code)."))

(defgeneric backend-write-file (backend workspace path content)
  (:documentation "Write content to a file within the workspace.
   PATH is relative to the workspace root."))

(defgeneric backend-read-file (backend workspace path)
  (:documentation "Read a file from within the workspace.
   PATH is relative to the workspace root."))

(defgeneric backend-read-host-file (backend workspace path)
  (:documentation "Read a file from the HOST filesystem, bypassing isolation.
   Used when an agent in an isolated workspace needs to read source code,
   configuration, or other host files that are outside the workspace.
   Default implementation delegates to backend-read-file."))

;;; Default: same as backend-read-file (works for :none and :directory
;;; since they already read from the host filesystem).
(defmethod backend-read-host-file ((backend isolation-backend) workspace path)
  (backend-read-file backend workspace path))

;;; ── Backend Registry ────────────────────────────────────────────

(defvar *isolation-backends* (make-hash-table :test 'eq)
  "Registry of isolation backends by keyword name.")

(defun register-isolation-backend (name backend)
  "Register an isolation backend under NAME (a keyword)."
  (setf (gethash name *isolation-backends*) backend))

(defun find-isolation-backend (name)
  "Find an isolation backend by name."
  (gethash name *isolation-backends*))

;;; ── Directory Backend (built-in) ────────────────────────────────

(defclass directory-backend (isolation-backend)
  ()
  (:default-initargs :name :directory)
  (:documentation "Workspace isolation via host filesystem directories.
No process isolation — just a dedicated directory."))

(defmethod backend-create-workspace ((backend directory-backend) workspace)
  "Create the workspace directory on the host filesystem."
  (let ((root (workspace-root workspace)))
    (ensure-directories-exist (format nil "~A/.keep" root))
    root))

(defmethod backend-destroy-workspace ((backend directory-backend) workspace)
  "Optionally remove the workspace directory."
  ;; By default, we leave workspace directories for inspection.
  ;; Set workspace-status to :destroyed but don't delete files.
  (setf (workspace-status workspace) :destroyed))

(defmethod backend-exec ((backend directory-backend) workspace command
                         &key (timeout 120) working-directory)
  "Execute a command with the workspace root as working directory."
  (let ((dir (or working-directory (workspace-root workspace))))
    (handler-case
        (multiple-value-bind (stdout stderr exit-code)
            (uiop:run-program command
                              :directory dir
                              :output :string
                              :error-output :string
                              :ignore-error-status t)
          (values stdout stderr exit-code))
      (error (e)
        (values "" (format nil "Error: ~A" e) -1)))))

(defmethod backend-write-file ((backend directory-backend) workspace path content)
  "Write a file within the workspace directory."
  (let ((full-path (resolve-path path workspace)))
    (ensure-directories-exist full-path)
    (with-open-file (out full-path :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
      (write-string content out))
    full-path))

(defmethod backend-read-file ((backend directory-backend) workspace path)
  "Read a file from the workspace directory."
  (let ((full-path (resolve-path path workspace)))
    (if (probe-file full-path)
        (uiop:read-file-string full-path)
        (error "File not found: ~A" full-path))))

;; Register the directory backend immediately
(register-isolation-backend :directory (make-instance 'directory-backend))

;;; ── None Backend (pass-through) ─────────────────────────────────

(defclass none-backend (isolation-backend)
  ()
  (:default-initargs :name :none)
  (:documentation "No isolation — operations pass through to host filesystem."))

(defmethod backend-create-workspace ((backend none-backend) workspace)
  "No setup needed."
  (workspace-root workspace))

(defmethod backend-destroy-workspace ((backend none-backend) workspace)
  "No cleanup needed."
  (setf (workspace-status workspace) :destroyed))

(defmethod backend-exec ((backend none-backend) workspace command
                         &key (timeout 120) working-directory)
  "Execute on the host with optional working directory."
  (let ((dir (or working-directory
                 (workspace-root workspace)
                 (uiop:getcwd))))
    (handler-case
        (multiple-value-bind (stdout stderr exit-code)
            (uiop:run-program command
                              :directory dir
                              :output :string
                              :error-output :string
                              :ignore-error-status t)
          (values stdout stderr exit-code))
      (error (e)
        (values "" (format nil "Error: ~A" e) -1)))))

(defmethod backend-write-file ((backend none-backend) workspace path content)
  "Write directly to the path (no workspace prefixing for absolute paths)."
  (let ((full-path (if (uiop:absolute-pathname-p path)
                       path
                       (resolve-path path workspace))))
    (ensure-directories-exist full-path)
    (with-open-file (out full-path :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
      (write-string content out))
    full-path))

(defmethod backend-read-file ((backend none-backend) workspace path)
  "Read directly from the path."
  (let ((full-path (if (uiop:absolute-pathname-p path)
                       path
                       (resolve-path path workspace))))
    (if (probe-file full-path)
        (uiop:read-file-string full-path)
        (error "File not found: ~A" full-path))))

(register-isolation-backend :none (make-instance 'none-backend))

;;; ── Workspace Class ─────────────────────────────────────────────

(defclass workspace ()
  ((id :initarg :id
       :accessor workspace-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique workspace identifier")
   (agent-id :initarg :agent-id
             :accessor workspace-agent-id
             :initform nil
             :documentation "Agent this workspace belongs to")
   (task :initarg :task
         :accessor workspace-task
         :initform nil
         :documentation "Description of what this workspace is for")
   (isolation :initarg :isolation
              :accessor workspace-isolation
              :initform :directory
              :documentation "Isolation level: :none, :directory, :sandbox")
   (root :initarg :root
         :accessor workspace-root
         :documentation "Absolute path to workspace root")
   (sandbox-id :initarg :sandbox-id
               :accessor workspace-sandbox-id
               :initform nil
               :documentation "Sandbox ID when isolation is :sandbox")
   (status :initform :active
           :accessor workspace-status
           :documentation ":active, :suspended, :destroyed")
   (created-at :initform (get-universal-time)
               :accessor workspace-created-at)
   (metadata :initarg :metadata
             :accessor workspace-metadata
             :initform nil
             :documentation "Arbitrary plist of workspace metadata"))
  (:documentation "Ephemeral per-task execution context with configurable isolation."))

;;; ── Current Workspace ───────────────────────────────────────────

(defvar *current-workspace* nil
  "The currently active workspace. Bound by with-workspace.")

;;; ── Workspace Registry ──────────────────────────────────────────

(defvar *workspace-registry* (make-hash-table :test 'equal)
  "Active workspaces indexed by ID.")

(defvar *workspace-registry-lock* (bt:make-lock "workspace-registry"))

(defun find-workspace (id)
  "Find a workspace by ID."
  (bt:with-lock-held (*workspace-registry-lock*)
    (gethash id *workspace-registry*)))

(defun list-workspaces ()
  "List all active workspaces."
  (bt:with-lock-held (*workspace-registry-lock*)
    (loop for ws being the hash-values of *workspace-registry*
          when (eq (workspace-status ws) :active)
          collect ws)))

(defun list-agent-workspaces (agent-id)
  "List all active workspaces for a specific agent."
  (let ((normalized (normalize-agent-id agent-id)))
    (bt:with-lock-held (*workspace-registry-lock*)
      (loop for ws being the hash-values of *workspace-registry*
            when (and (eq (workspace-status ws) :active)
                      (equal (workspace-agent-id ws) normalized))
            collect ws))))

;;; ── Path Resolution ─────────────────────────────────────────────

(defun resolve-path (relative-path &optional (workspace *current-workspace*))
  "Resolve a relative path within the workspace root.
   If RELATIVE-PATH is already absolute, returns it unchanged (for :none isolation).
   If no workspace is bound, returns the path unchanged."
  (cond
    ((null workspace) relative-path)
    ((and (stringp relative-path)
          (> (length relative-path) 0)
          (char= (char relative-path 0) #\/))
     ;; Absolute path — only resolve within workspace for :directory and :sandbox
     (if (eq (workspace-isolation workspace) :none)
         relative-path
         (let ((root (workspace-root workspace)))
           (format nil "~A~A" root (subseq relative-path 1)))))
    (t
     ;; Relative path — always prefix with workspace root
     (let ((root (workspace-root workspace)))
       (format nil "~A~A" root relative-path)))))

(defun workspace-relative (absolute-path &optional (workspace *current-workspace*))
  "Convert an absolute path back to a workspace-relative path.
   Returns the path unchanged if it's not within the workspace."
  (when workspace
    (let ((root (workspace-root workspace)))
      (when (and (>= (length absolute-path) (length root))
                 (string= root (subseq absolute-path 0 (length root))))
        (format nil "/~A" (subseq absolute-path (length root)))))))

;;; ── Workspace Lifecycle ─────────────────────────────────────────

(defun create-workspace (agent-id task &key (isolation :directory)
                                             (root nil)
                                             (layers nil)
                                             (memory-mb 1024)
                                             (timeout 3600)
                                             metadata)
  "Create a new workspace for a task.

   AGENT-ID  - Agent this workspace belongs to
   TASK      - Description of the task
   ISOLATION - :none, :directory, or :sandbox
   ROOT      - Override workspace root path (auto-generated if nil)
   LAYERS    - Squashfs layers for :sandbox isolation
   MEMORY-MB - Memory limit for :sandbox isolation
   TIMEOUT   - Max lifetime in seconds for :sandbox isolation
   METADATA  - Arbitrary plist

   Returns the workspace object."
  (let* ((normalized-agent (when agent-id (normalize-agent-id agent-id)))
         (ws-id (autopoiesis.core:make-uuid))
         (ws-root (or root
                      (case isolation
                        (:none (format nil "~A" (uiop:getcwd)))
                        (:sandbox "/workspace/")
                        (otherwise
                         ;; Place under agent home if we have an agent
                         (if normalized-agent
                             (format nil "~A~A/workspaces/~A/"
                                     *agent-data-root* normalized-agent ws-id)
                             (format nil "/tmp/ap-workspace-~A/" ws-id))))))
         (workspace (make-instance 'workspace
                                   :id ws-id
                                   :agent-id normalized-agent
                                   :task task
                                   :isolation isolation
                                   :root ws-root
                                   :metadata (append
                                              (when layers (list :layers layers))
                                              (when memory-mb (list :memory-mb memory-mb))
                                              (when timeout (list :timeout timeout))
                                              metadata))))

    ;; Find the isolation backend and set up
    (let ((backend (find-isolation-backend isolation)))
      (unless backend
        (error "No isolation backend registered for ~A. ~
                Available backends: ~{~A~^, ~}"
               isolation
               (loop for k being the hash-keys of *isolation-backends* collect k)))
      (backend-create-workspace backend workspace))

    ;; Register
    (bt:with-lock-held (*workspace-registry-lock*)
      (setf (gethash ws-id *workspace-registry*) workspace))

    ;; Track in substrate
    (when autopoiesis.substrate:*store*
      (let ((eid (autopoiesis.substrate:intern-id
                  (format nil "workspace:~A" ws-id))))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom eid :workspace/id ws-id)
               (autopoiesis.substrate:make-datom eid :workspace/agent-id
                                                  (or normalized-agent ""))
               (autopoiesis.substrate:make-datom eid :workspace/task (or task ""))
               (autopoiesis.substrate:make-datom eid :workspace/isolation isolation)
               (autopoiesis.substrate:make-datom eid :workspace/root ws-root)
               (autopoiesis.substrate:make-datom eid :workspace/status :active)
               (autopoiesis.substrate:make-datom eid :workspace/created-at
                                                  (get-universal-time))))))

    workspace))

(defun destroy-workspace (workspace)
  "Clean up a workspace. Dispatches to the isolation backend."
  (let ((backend (find-isolation-backend (workspace-isolation workspace))))
    (when backend
      (handler-case
          (backend-destroy-workspace backend workspace)
        (error (e)
          (warn "Error destroying workspace ~A: ~A"
                (workspace-id workspace) e)))))
  ;; Unregister
  (bt:with-lock-held (*workspace-registry-lock*)
    (remhash (workspace-id workspace) *workspace-registry*))
  ;; Update substrate
  (when autopoiesis.substrate:*store*
    (let ((eid (autopoiesis.substrate:intern-id
                (format nil "workspace:~A" (workspace-id workspace)))))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom eid :workspace/status :destroyed)
             (autopoiesis.substrate:make-datom eid :workspace/destroyed-at
                                                (get-universal-time))))))
  (setf (workspace-status workspace) :destroyed)
  workspace)

;;; ── with-workspace Macro ────────────────────────────────────────

(defmacro with-workspace ((agent-or-id &key task (isolation :directory)
                                            layers memory-mb timeout
                                            metadata)
                          &body body)
  "Execute BODY with a workspace bound to *current-workspace*.

   Creates the workspace before BODY, binds it, executes BODY,
   and destroys the workspace on exit (normal or abnormal).

   Within BODY, all workspace-aware operations (ws-read-file, ws-write-file,
   ws-exec, etc.) automatically route through the workspace.

   Example:
     (with-workspace (my-agent :task \"analyze-data\"
                               :isolation :directory)
       (ws-write-file \"script.py\" \"print('hello')\")
       (ws-exec \"python script.py\"))"
  (let ((ws (gensym "WORKSPACE")))
    `(let ((,ws (create-workspace ,agent-or-id ,task
                                  :isolation ,isolation
                                  ,@(when layers `(:layers ,layers))
                                  ,@(when memory-mb `(:memory-mb ,memory-mb))
                                  ,@(when timeout `(:timeout ,timeout))
                                  ,@(when metadata `(:metadata ,metadata)))))
       (let ((*current-workspace* ,ws))
         (unwind-protect
              (progn ,@body)
           (destroy-workspace ,ws))))))
