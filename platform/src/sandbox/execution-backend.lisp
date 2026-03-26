;;;; execution-backend.lisp - Pluggable execution backend protocol
;;;;
;;;; Defines the generic interface for sandbox execution backends.
;;;; AP doesn't care whether execution happens in overlayfs, Docker,
;;;; a remote VM, or a local directory — it just materializes state
;;;; from the DAG and collects results.
;;;;
;;;; Backends implement this protocol via CLOS generic functions.
;;;; The DAG (content store + snapshot tree) owns the truth.
;;;; Backends are ephemeral materializations.

(in-package #:autopoiesis.sandbox)

;;; ═══════════════════════════════════════════════════════════════════
;;; Backend Protocol (generic functions)
;;; ═══════════════════════════════════════════════════════════════════

(defclass execution-backend ()
  ((name :initarg :name
         :accessor backend-name
         :documentation "Backend identifier keyword (:local, :docker, :remote, :squashd)")
   (config :initarg :config
           :accessor backend-config
           :initform nil
           :documentation "Backend-specific configuration plist"))
  (:documentation "Base class for sandbox execution backends."))

(defgeneric backend-create (backend sandbox-id &key tree content-store config)
  (:documentation
   "Create a new sandbox execution environment.
    TREE is a list of filesystem tree entries to materialize.
    CONTENT-STORE provides blob content for file entries.
    CONFIG is a plist of backend-specific options (memory, cpu, etc).
    Returns the sandbox-id on success."))

(defgeneric backend-destroy (backend sandbox-id)
  (:documentation
   "Destroy a sandbox execution environment and clean up resources.
    Returns the sandbox-id on success."))

(defgeneric backend-exec (backend sandbox-id command &key timeout env workdir)
  (:documentation
   "Execute COMMAND in the sandbox. Returns an exec-result plist:
    (:exit-code N :stdout \"...\" :stderr \"...\" :duration-ms N)
    TIMEOUT is in seconds. ENV is an alist of environment variables.
    WORKDIR is the working directory inside the sandbox."))

(defgeneric backend-snapshot (backend sandbox-id content-store)
  (:documentation
   "Capture the current filesystem state of the sandbox.
    Scans the sandbox filesystem, stores new blobs in CONTENT-STORE.
    Returns a sorted list of tree entries (ready for snapshot creation)."))

(defgeneric backend-restore (backend sandbox-id tree content-store &key incremental)
  (:documentation
   "Restore sandbox filesystem to match TREE.
    If INCREMENTAL is true, computes diff against current state and
    only applies changes. Otherwise, full materialization.
    Returns the number of operations performed."))

(defgeneric backend-fork (backend source-id new-id)
  (:documentation
   "Fork a sandbox. If the backend supports native COW (btrfs, Docker),
    use it. Otherwise, returns NIL and the caller should materialize from DAG.
    Returns the new sandbox-id on success, or NIL if not supported natively."))

(defgeneric backend-sandbox-root (backend sandbox-id)
  (:documentation
   "Return the filesystem root path of the sandbox.
    Used for direct file access when needed."))

(defgeneric backend-supports-native-fork-p (backend)
  (:documentation
   "Return T if this backend supports native COW forking.")
  ;; Default: no native fork support
  (:method ((backend execution-backend)) nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Exec Result (backend-agnostic)
;;; ═══════════════════════════════════════════════════════════════════

(defun make-exec-result (&key (exit-code 0) (stdout "") (stderr "")
                              (duration-ms 0) sandbox-id command)
  "Create a standard exec result plist."
  (list :exit-code exit-code
        :stdout stdout
        :stderr stderr
        :duration-ms duration-ms
        :sandbox-id sandbox-id
        :command command))

(defun exec-result-exit-code (result)
  "Get exit code from exec result."
  (getf result :exit-code))

(defun exec-result-stdout (result)
  "Get stdout from exec result."
  (getf result :stdout))

(defun exec-result-stderr (result)
  "Get stderr from exec result."
  (getf result :stderr))

(defun exec-result-duration-ms (result)
  "Get duration in ms from exec result."
  (getf result :duration-ms))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backend Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *backend-registry* (make-hash-table :test 'eq)
  "Registry of available execution backends by keyword name.")

(defun register-backend (name backend)
  "Register an execution backend by NAME (keyword)."
  (setf (gethash name *backend-registry*) backend))

(defun find-backend (name)
  "Look up a registered execution backend by NAME."
  (or (gethash name *backend-registry*)
      (error "No execution backend registered with name ~S" name)))

(defun list-backends ()
  "Return a list of registered backend names."
  (let ((names '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             *backend-registry*)
    names))
