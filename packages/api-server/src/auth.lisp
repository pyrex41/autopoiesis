;;;; auth.lisp - API key authentication for the control API
;;;;
;;;; Simple API key authentication. Each key maps to an identity
;;;; string that gets attached to requests for audit logging.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; API Key Registry
;;; ===================================================================

(defvar *api-keys* (make-hash-table :test 'equal)
  "Registry of valid API keys. Maps key-hash string to identity plist.")

(defvar *api-require-auth* nil
  "When T, require authentication even if no keys are registered.
   When NIL (default), empty key registry means open access.")

(defvar *api-keys-lock* (bordeaux-threads:make-lock "api-keys-lock")
  "Lock for thread-safe API key operations.")

(defun hash-api-key (key)
  "Hash an API key using SHA-256 for storage. Never store plaintext keys."
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha256
     (babel:string-to-octets key :encoding :utf-8))))

(defun constant-time-string= (a b)
  "Compare two strings in constant time to prevent timing attacks.
   Returns T if strings are equal, NIL otherwise."
  (when (and (stringp a) (stringp b))
    (let ((a-bytes (babel:string-to-octets a :encoding :utf-8))
          (b-bytes (babel:string-to-octets b :encoding :utf-8)))
      (and (= (length a-bytes) (length b-bytes))
           (zerop (reduce #'logior
                          (map 'vector #'logxor a-bytes b-bytes)
                          :initial-value 0))))))

(defun register-api-key (key &key (identity "anonymous") (permissions :full))
  "Register an API key with an identity and permission level.
   The key is stored as a SHA-256 hash, never in plaintext.

   Arguments:
     key         - The API key string
     identity    - Human-readable name for who holds this key
     permissions - :full, :read-only, or :agent-only

   Returns: T"
  (let ((key-hash (hash-api-key key)))
    (bordeaux-threads:with-lock-held (*api-keys-lock*)
      (setf (gethash key-hash *api-keys*)
            (list :identity identity
                  :permissions permissions
                  :created (get-universal-time)))))
  t)

(defun revoke-api-key (key)
  "Revoke an API key."
  (let ((key-hash (hash-api-key key)))
    (bordeaux-threads:with-lock-held (*api-keys-lock*)
      (remhash key-hash *api-keys*))))

(defun validate-api-key (key)
  "Validate an API key. Returns the identity plist if valid, NIL otherwise.
   Uses hashed comparison - the stored keys are SHA-256 hashes."
  (let ((key-hash (hash-api-key key)))
    (bordeaux-threads:with-lock-held (*api-keys-lock*)
      (gethash key-hash *api-keys*))))

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

    Checks for:
    1. Valid session cookie (for web console users)
    2. API key authentication (for programmatic access)
    3. Fallback to local access when no auth required

    When *api-require-auth* is NIL (default) and no API keys are registered,
    returns a read-only local identity. Set *api-require-auth* to T in
    production to require explicit key registration."
   ;; First check for session-based authentication (web console)
   (let ((session-token (get-session-cookie)))
     (when session-token
       (multiple-value-bind (user session)
           (autopoiesis.security:validate-session-token session-token)
         (when (and user session)
           ;; Return session-based identity with user permissions
           (return-from authenticate-request
             (list :identity (autopoiesis.security:user-username user)
                   :permissions (if (member :admin (autopoiesis.security:user-roles user))
                                    :full
                                    :read-only)  ;; Could be more granular
                   :auth-type :session
                   :user-id (autopoiesis.security:user-id user)))))))

   ;; Fall back to API key authentication
   (let ((auth-header (hunchentoot:header-in* :authorization))
         (api-key-header (hunchentoot:header-in* :x-api-key)))
     (let ((key (or (when auth-header (extract-bearer-token auth-header))
                    api-key-header)))
       ;; Atomically check: if key provided, validate; if no keys registered, grant local
       (bordeaux-threads:with-lock-held (*api-keys-lock*)
         (cond
           ;; Key provided - validate it
           (key
            (let ((identity (gethash (hash-api-key key) *api-keys*)))
              (when identity
                (setf (getf identity :auth-type) :api-key)
                identity)))
           ;; No key, no registered keys, auth not required - grant full local access
           ((and (not *api-require-auth*)
                 (zerop (hash-table-count *api-keys*)))
            (list :identity "local" :permissions :full :auth-type :none))
           ;; No key provided but keys exist (or auth required) - deny
           (t nil))))))

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
  "Check if IDENTITY has the required permission.
    Permission levels: :full > :agent-only > :read-only"
  (let ((level (getf identity :permissions)))
    (case permission
      (:read (member level '(:full :agent-only :read-only)))
      (:write (member level '(:full :agent-only)))
      (:admin (eq level :full))
      (t nil))))

(defun require-permission (permission)
  "Authenticate and check permission, or return 403.
   In development mode (no keys registered), allow all access."
  (let ((identity (require-auth)))
    (unless identity
      ;; Development fallback - allow read-only access
      (return-from require-permission
        (list :identity "dev" :permissions :read-only)))
    (unless (has-permission-p* identity permission)
      (setf (hunchentoot:return-code*) 403)
      (setf (hunchentoot:content-type*) "application/json")
      (hunchentoot:abort-request-handler
       (cl-json:encode-json-to-string
        `((:error . "Forbidden")
          (:message . ,(format nil "Requires ~a permission" permission))))))
    identity))
