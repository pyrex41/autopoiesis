;;;; authentication.lisp - User authentication and session management for Autopoiesis
;;;;
;;;; Implements user models, authentication (login/logout), session management,
;;;; and integration with the permission system.
;;;; Phase 10.2: Security Hardening

(in-package #:autopoiesis.security)

;;; ═══════════════════════════════════════════════════════════════════
;;; User Entity Type
;;; ═══════════════════════════════════════════════════════════════════

(define-entity-type :user
  (:user/username      :type string  :required t)
  (:user/email         :type (or null string))
  (:user/password-hash :type string  :required t)
  (:user/created-at    :type integer :required t)
  (:user/last-login    :type (or null integer))
  (:user/active        :type boolean)
  (:user/roles         :type list))

(defclass user ()
  ((id :initarg :id
       :accessor user-id
       :documentation "User entity ID")
   (username :initarg :username
             :accessor user-username
             :type string
             :documentation "Unique username")
   (email :initarg :email
          :accessor user-email
          :type (or null string)
          :documentation "Email address")
   (password-hash :initarg :password-hash
                  :accessor user-password-hash
                  :type string
                  :documentation "BCrypt password hash")
   (created-at :initarg :created-at
               :accessor user-created-at
               :type integer
               :documentation "Creation timestamp")
   (last-login :initarg :last-login
               :accessor user-last-login
               :type (or null integer)
               :documentation "Last login timestamp")
   (active :initarg :active
           :accessor user-active-p
           :type boolean
           :documentation "Whether account is active")
   (roles :initarg :roles
          :accessor user-roles
          :type list
          :documentation "List of role keywords"))
  (:documentation "User account representation."))

(defun user-p (obj)
  "Return T if OBJ is a user."
  (typep obj 'user))

(defmethod print-object ((user user) stream)
  (print-unreadable-object (user stream :type t)
    (format stream "~a (~a)"
            (user-username user)
            (if (user-active-p user) "active" "inactive"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Password Hashing
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *bcrypt-cost* 12
  "BCrypt cost factor for password hashing.")

(defun hash-password (password)
  "Hash a password using BCrypt.
  
  Arguments:
    password - Plain text password string
    
  Returns: BCrypt hash string"
  (ironclad:pbkdf2-hash-password-to-combined-string
   (babel:string-to-octets password :encoding :utf-8)
   :iterations (expt 2 *bcrypt-cost*)))

(defun verify-password (password hash)
  "Verify a password against a BCrypt hash.
  
  Arguments:
    password - Plain text password string
    hash - BCrypt hash string
    
  Returns: T if password matches, NIL otherwise"
  (ironclad:pbkdf2-check-password
   (babel:string-to-octets password :encoding :utf-8)
   hash))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Management Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun create-user (username password &key email roles (active t))
  "Create a new user account.
  
  Arguments:
    username - Unique username (validated)
    password - Plain text password (will be hashed)
    email - Optional email address
    roles - List of role keywords (default: (:user))
    active - Whether account should be active (default: T)
    
  Returns: user object or signals error if username exists"
  ;; Validate input
  (with-validated-input (username username *validation-spec-agent-id*)
    (with-validated-input (password password '(:string :min-length 8 :max-length 128))
      (when email
        (with-validated-input (email email '(:string :pattern "^[^@]+@[^@]+\\.[^@]+$"))))
      
      ;; Check if username already exists
      (when (find-user-by-username username)
        (error 'validation-error
               :input username
               :spec *validation-spec-agent-id*
               :errors (list "Username already exists")))
      
      ;; Create user entity in substrate
      (let* ((user-id (intern-id (format nil "user:~a" username)))
             (now (get-universal-time))
             (password-hash (hash-password password))
             (user-roles (or roles (list :user)))
             (datoms (list
                      (make-datom user-id :entity/type :user)
                      (make-datom user-id :user/username username)
                      (make-datom user-id :user/email email)
                      (make-datom user-id :user/password-hash password-hash)
                      (make-datom user-id :user/created-at now)
                      (make-datom user-id :user/active active)
                      (make-datom user-id :user/roles user-roles))))
        
        (transact! datoms)
        
        ;; Audit the user creation
        (audit-log "system" :create :user :success
                   (format nil "Created user ~a with roles ~a" username user-roles))
        
        ;; Return user object
        (make-user-from-entity user-id)))))

(defun find-user-by-username (username)
  "Find a user by username.
  
  Arguments:
    username - Username to search for
    
  Returns: user object or NIL if not found"
  (let ((user-ids (find-entities :user/username username)))
    (when user-ids
      (make-user-from-entity (first user-ids)))))

(defun find-user-by-id (user-id)
  "Find a user by entity ID.
  
  Arguments:
    user-id - User entity ID
    
  Returns: user object or NIL if not found"
  (when (entity-attr user-id :user/username)
    (make-user-from-entity user-id)))

(defun make-user-from-entity (user-id)
  "Create a user object from entity ID.

  Arguments:
    user-id - User entity ID

  Returns: user object"
  ;; Use entity-attr for each field individually to avoid entity-state
  ;; plist corruption from entity/attribute ID resolve table collisions.
  (make-instance 'user
                 :id user-id
                 :username (entity-attr user-id :user/username)
                 :email (entity-attr user-id :user/email)
                 :password-hash (entity-attr user-id :user/password-hash)
                 :created-at (entity-attr user-id :user/created-at)
                 :last-login (entity-attr user-id :user/last-login)
                 :active (multiple-value-bind (val found-p)
                           (entity-attr user-id :user/active)
                           (if found-p val t))
                 :roles (or (entity-attr user-id :user/roles) (list :user))))

(defun update-user-last-login (user)
  "Update the last login timestamp for a user.
  
  Arguments:
    user - user object
    
  Returns: updated user object"
  (let* ((now (get-universal-time))
         (datoms (list (make-datom (user-id user) :user/last-login now))))
    (transact! datoms)
    (setf (user-last-login user) now)
    user))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Management
;;; ═══════════════════════════════════════════════════════════════════

(define-entity-type :session/auth
  (:session/token      :type string  :required t)
  (:session/user-id    :type integer :required t)
  (:session/created-at :type integer :required t)
  (:session/expires-at :type integer :required t)
  (:session/active     :type boolean)
  (:session/ip-address :type (or null string))
  (:session/user-agent :type (or null string)))

(defclass session ()
  ((id :initarg :id
       :accessor session-id
       :documentation "Session entity ID")
   (token :initarg :token
          :accessor session-token
          :type string
          :documentation "Unique session token")
   (user-id :initarg :user-id
            :accessor session-user-id
            :documentation "User entity ID")
   (created-at :initarg :created-at
               :accessor session-created-at
               :type integer
               :documentation "Creation timestamp")
   (expires-at :initarg :expires-at
               :accessor session-expires-at
               :type integer
               :documentation "Expiration timestamp")
   (active :initarg :active
           :accessor session-active-p
           :type boolean
           :documentation "Whether session is active")
   (ip-address :initarg :ip-address
               :accessor session-ip-address
               :type (or null string)
               :documentation "Client IP address")
   (user-agent :initarg :user-agent
               :accessor session-user-agent
               :type (or null string)
               :documentation "Client user agent"))
  (:documentation "User session representation."))

(defun session-p (obj)
  "Return T if OBJ is an auth session."
  (typep obj 'session))

(defmethod print-object ((session session) stream)
  (print-unreadable-object (session stream :type t)
    (format stream "~a (~a)"
            (session-token session)
            (if (session-active-p session) "active" "inactive"))))

(defparameter *session-lifetime* (* 24 60 60)  ; 24 hours in seconds
  "Default session lifetime in seconds.")

(defparameter *session-token-length* 64
  "Length of session tokens in characters.")

(defun generate-session-token ()
  "Generate a cryptographically secure random session token.

  Returns: Random token string"
  (let ((bytes (ironclad:random-data *session-token-length*)))
    (ironclad:byte-array-to-hex-string bytes)))

(defun create-session (user &key ip-address user-agent (lifetime *session-lifetime*))
  "Create a new session for a user.
  
  Arguments:
    user - user object
    ip-address - Optional client IP address
    user-agent - Optional client user agent
    lifetime - Session lifetime in seconds (default: 24 hours)
    
  Returns: session object"
  (let* ((token (generate-session-token))
         (now (get-universal-time))
         (expires-at (+ now lifetime))
         (session-id (intern-id (format nil "session:~a" token)))
         (datoms (list
                  (make-datom session-id :entity/type :session)
                  (make-datom session-id :session/token token)
                  (make-datom session-id :session/user-id (user-id user))
                  (make-datom session-id :session/created-at now)
                  (make-datom session-id :session/expires-at expires-at)
                  (make-datom session-id :session/active t)
                  (make-datom session-id :session/ip-address ip-address)
                  (make-datom session-id :session/user-agent user-agent))))
    
    (transact! datoms)
    
    ;; Audit the session creation
    (audit-log (user-username user) :create :session :success
               (format nil "Created session from ~a" ip-address))
    
    ;; Return session object
    (make-session-from-entity session-id)))

(defun find-session-by-token (token)
  "Find a session by token.
  
  Arguments:
    token - Session token string
    
  Returns: session object or NIL if not found/expired/inactive"
  (let ((session-ids (find-entities :session/token token)))
    (when session-ids
      (let ((session (make-session-from-entity (first session-ids))))
        ;; Check if session is active and not expired
        (when (and (session-active-p session)
                   (> (session-expires-at session) (get-universal-time)))
          session)))))

(defun make-session-from-entity (session-id)
  "Create a session object from entity ID.

  Arguments:
    session-id - Session entity ID

  Returns: session object"
  ;; Use entity-attr for each field individually to avoid entity-state
  ;; plist corruption from entity/attribute ID resolve table collisions.
  (make-instance 'session
                 :id session-id
                 :token (entity-attr session-id :session/token)
                 :user-id (entity-attr session-id :session/user-id)
                 :created-at (entity-attr session-id :session/created-at)
                 :expires-at (entity-attr session-id :session/expires-at)
                 :active (multiple-value-bind (val found-p)
                           (entity-attr session-id :session/active)
                           (if found-p val t))
                 :ip-address (entity-attr session-id :session/ip-address)
                 :user-agent (entity-attr session-id :session/user-agent)))

(defun invalidate-session (session)
  "Invalidate a session.
  
  Arguments:
    session - session object
    
  Returns: T if invalidated successfully"
  (let ((datoms (list (make-datom (session-id session) :session/active nil))))
    (transact! datoms)
    (setf (session-active-p session) nil)
    
    ;; Audit the session invalidation
    (audit-log (resolve-id (session-user-id session)) :delete :session :success
               "Session invalidated")
    t))

(defun cleanup-expired-sessions ()
  "Remove expired sessions from the database.
  
  Returns: Number of sessions cleaned up"
  (let* ((now (get-universal-time))
         (all-session-ids (find-entities :entity/type :session))
         (expired-session-ids
          (remove-if-not
           (lambda (entity-id)
             (let ((state (entity-state entity-id)))
               (or (not (getf state :session/active t))
                   (<= (getf state :session/expires-at 0) now))))
           all-session-ids)))
    
    ;; Mark expired sessions as inactive
    (dolist (session-id expired-session-ids)
      (transact! (list (make-datom session-id :session/active nil))))
    
    (length expired-session-ids)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Authentication Functions
;;; ═══════════════════════════════════════════════════════════════════

(define-condition authentication-error (error)
  ((username :initarg :username
             :reader authentication-error-username
             :documentation "Username that failed authentication"))
  (:documentation "Signaled when authentication fails.")
  (:report (lambda (condition stream)
             (format stream "Authentication failed for user ~a"
                     (authentication-error-username condition)))))

(define-condition invalid-credentials (authentication-error)
  ()
  (:documentation "Signaled when username/password combination is invalid.")
  (:report (lambda (condition stream)
             (format stream "Invalid credentials for user ~a"
                     (authentication-error-username condition)))))

(define-condition account-inactive (authentication-error)
  ()
  (:documentation "Signaled when attempting to authenticate with an inactive account.")
  (:report (lambda (condition stream)
             (format stream "Account ~a is inactive"
                     (authentication-error-username condition)))))

(defun authenticate-user (username password &key ip-address user-agent)
  "Authenticate a user with username and password.
  
  Arguments:
    username - Username string
    password - Password string
    ip-address - Optional client IP address
    user-agent - Optional client user agent
    
  Returns: session object on success
  Signals: authentication-error on failure"
  (let ((user (find-user-by-username username)))
    (unless user
      ;; Don't reveal whether username exists for security
      (audit-log username :login :user :failure "User not found")
      (error 'invalid-credentials :username username))
    
    ;; Check if account is active
    (unless (user-active-p user)
      (audit-log username :login :user :failure "Account inactive")
      (error 'account-inactive :username username))
    
    ;; Verify password
    (unless (verify-password password (user-password-hash user))
      (audit-log username :login :user :failure "Invalid password")
      (error 'invalid-credentials :username username))
    
    ;; Update last login
    (update-user-last-login user)
    
    ;; Create session
    (let ((session (create-session user :ip-address ip-address :user-agent user-agent)))
      (audit-log username :login :user :success
                 (format nil "Login from ~a" ip-address))
      session)))

(defun logout-user (session)
  "Log out a user by invalidating their session.
  
  Arguments:
    session - session object
    
  Returns: T on success"
  (let ((username (resolve-id (session-user-id session))))
    (invalidate-session session)
    (audit-log username :logout :user :success "User logged out")
    t))

(defun validate-session-token (token)
  "Validate a session token and return the associated user.
  
  Arguments:
    token - Session token string
    
  Returns: (values user session) on success, (values NIL NIL) on failure"
  (let ((session (find-session-by-token token)))
    (if session
        (let ((user (find-user-by-id (session-user-id session))))
          (if user
              (values user session)
              (values nil nil)))
        (values nil nil))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Authorization Integration
;;; ═══════════════════════════════════════════════════════════════════

(defun setup-user-permissions (user)
  "Set up permissions for a user based on their roles.
  
  Arguments:
    user - user object
    
  Returns: list of permissions assigned"
  (let ((permissions nil))
    ;; Clear existing permissions for this user
    (clear-agent-permissions (user-username user))
    
    ;; Assign permissions based on roles
    (dolist (role (user-roles user))
      (case role
        (:admin
         (setf permissions (append permissions *admin-permissions*)))
        (:user
         (setf permissions (append permissions *default-agent-permissions*)))
        (:sandbox
         (setf permissions (append permissions *sandbox-permissions*)))))
    
    ;; Grant the permissions
    (dolist (perm permissions)
      (grant-permission (user-username user) perm))
    
    permissions))

(defun get-user-permissions (user-or-username)
  "Get permissions for a user.

  Arguments:
    user-or-username - user object or username string

  Returns: list of permissions"
  (let ((username (if (stringp user-or-username)
                      user-or-username
                      (user-username user-or-username))))
    (get-agent-permissions username)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defvar *authentication-initialized* nil
  "Whether authentication system has been initialized.")

(defun init-authentication-system ()
  "Initialize the authentication system.
  
  This sets up entity types and performs any necessary initialization."
  (unless *authentication-initialized*
    ;; Entity types are defined at compile time, but we can do runtime setup here
    (setf *authentication-initialized* t)
    
    ;; Start periodic cleanup of expired sessions (every hour)
    ;; This would be done by the conductor in a real implementation
    (format *error-output* "~&Authentication system initialized~%")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Utility Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun list-users (&key (active-only t))
  "List all users.
  
  Arguments:
    active-only - If T, only return active users (default: T)
    
  Returns: list of user objects"
  (let* ((all-user-ids (find-entities :entity/type :user))
         (user-ids (if active-only
                       (remove-if-not (lambda (eid)
                                        (entity-attr eid :user/active))
                                      all-user-ids)
                       all-user-ids)))
    (mapcar #'make-user-from-entity user-ids)))

(defun change-user-password (username old-password new-password)
  "Change a user's password.
  
  Arguments:
    username - Username
    old-password - Current password
    new-password - New password
    
  Returns: T on success
  Signals: authentication-error on failure"
  ;; First authenticate with old password
  (authenticate-user username old-password)
  
  ;; Validate new password
  (with-validated-input (new-password new-password '(:string :min-length 8 :max-length 128))
    (let* ((user (find-user-by-username username))
           (new-hash (hash-password new-password))
           (datoms (list (make-datom (user-id user) :user/password-hash new-hash))))
      
      (transact! datoms)
      (setf (user-password-hash user) new-hash)
      
      (audit-log username :update :user :success "Password changed")
      t)))