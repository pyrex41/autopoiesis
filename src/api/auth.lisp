;;;; auth.lisp - API key authentication for the control API
;;;;
;;;; Simple API key authentication. Each key maps to an identity
;;;; string that gets attached to requests for audit logging.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; API Key Registry
;;; ===================================================================

(defvar *api-keys* (make-hash-table :test 'equal)
  "Registry of valid API keys. Maps key string to identity plist.")

(defvar *api-keys-lock* (bordeaux-threads:make-lock "api-keys-lock")
  "Lock for thread-safe API key operations.")

(defun register-api-key (key &key (identity "anonymous") (permissions :full))
  "Register an API key with an identity and permission level.

   Arguments:
     key         - The API key string
     identity    - Human-readable name for who holds this key
     permissions - :full, :read-only, or :agent-only

   Returns: T"
  (bordeaux-threads:with-lock-held (*api-keys-lock*)
    (setf (gethash key *api-keys*)
          (list :identity identity
                :permissions permissions
                :created (get-universal-time))))
  t)

(defun revoke-api-key (key)
  "Revoke an API key."
  (bordeaux-threads:with-lock-held (*api-keys-lock*)
    (remhash key *api-keys*)))

(defun validate-api-key (key)
  "Validate an API key. Returns the identity plist if valid, NIL otherwise."
  (bordeaux-threads:with-lock-held (*api-keys-lock*)
    (gethash key *api-keys*)))

(defun api-keys-empty-p ()
  "Return T if no API keys are registered (auth disabled)."
  (bordeaux-threads:with-lock-held (*api-keys-lock*)
    (zerop (hash-table-count *api-keys*))))

;;; ===================================================================
;;; Request Authentication
;;; ===================================================================

(defun authenticate-request ()
  "Authenticate the current Hunchentoot request.
   Returns the identity plist, or NIL if authentication fails.
   If no API keys are registered, authentication is disabled (returns a default identity)."
  (when (api-keys-empty-p)
    (return-from authenticate-request
      (list :identity "local" :permissions :full)))
  (let ((auth-header (hunchentoot:header-in* :authorization)))
    (when auth-header
      (let ((key (extract-bearer-token auth-header)))
        (when key
          (return-from authenticate-request (validate-api-key key))))))
  ;; Also check X-API-Key header
  (let ((api-key-header (hunchentoot:header-in* :x-api-key)))
    (when api-key-header
      (return-from authenticate-request (validate-api-key api-key-header))))
  nil)

(defun extract-bearer-token (header-value)
  "Extract the token from a 'Bearer <token>' authorization header."
  (when (and header-value
             (> (length header-value) 7)
             (string-equal "Bearer " (subseq header-value 0 7)))
    (subseq header-value 7)))

(defun require-auth ()
  "Authenticate the current request or return 401.
   Returns the identity plist on success."
  (let ((identity (authenticate-request)))
    (unless identity
      (setf (hunchentoot:return-code*) 401)
      (setf (hunchentoot:content-type*) "application/json")
      (hunchentoot:abort-request-handler
       (cl-json:encode-json-to-string
        '((:error . "Unauthorized") (:message . "Valid API key required")))))
    identity))

(defun has-permission-p* (identity permission)
  "Check if IDENTITY has the required PERMISSION.
   Permission levels: :full > :agent-only > :read-only"
  (let ((level (getf identity :permissions)))
    (case permission
      (:read (member level '(:full :agent-only :read-only)))
      (:write (member level '(:full :agent-only)))
      (:admin (eq level :full))
      (t nil))))

(defun require-permission (permission)
  "Authenticate and check permission, or return 403."
  (let ((identity (require-auth)))
    (unless (has-permission-p* identity permission)
      (setf (hunchentoot:return-code*) 403)
      (setf (hunchentoot:content-type*) "application/json")
      (hunchentoot:abort-request-handler
       (cl-json:encode-json-to-string
        `((:error . "Forbidden")
          (:message . ,(format nil "Requires ~a permission" permission))))))
    identity))
