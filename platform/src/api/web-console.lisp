;;;; web-console.lisp - Web console authentication and user interface
;;;;
;;;; Provides web-based authentication and user management for the Autopoiesis platform.
;;;; Includes login/logout handlers, session cookie management, and protected routes.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Cookie Management
;;; ═══════════════════════════════════════════════════════════════════

(defvar *session-cookie-name* "autopoiesis-session"
  "Name of the session cookie.")

(defvar *session-cookie-secure* nil
  "Whether to set the secure flag on session cookies (should be T in production).")

(defvar *session-cookie-http-only* t
  "Whether session cookies should be HTTP-only.")

(defvar *session-cookie-path* "/"
  "Path for session cookies.")

(defvar *session-cookie-max-age* (* 24 60 60)  ; 24 hours
  "Max age for session cookies in seconds.")

(defun set-session-cookie (token)
  "Set a session cookie with the given token."
  (hunchentoot:set-cookie *session-cookie-name*
                         :value token
                         :path *session-cookie-path*
                         :max-age *session-cookie-max-age*
                         :secure *session-cookie-secure*
                         :http-only *session-cookie-http-only*))

(defun get-session-cookie ()
  "Get the session token from the request cookie."
  (hunchentoot:cookie-in *session-cookie-name*))

(defun clear-session-cookie ()
  "Clear the session cookie."
  (hunchentoot:set-cookie *session-cookie-name*
                         :value ""
                         :path *session-cookie-path*
                         :max-age 0
                         :secure *session-cookie-secure*
                         :http-only *session-cookie-http-only*))

;;; ═══════════════════════════════════════════════════════════════════
;;; Web Authentication Handlers
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-login-page ()
  "Serve the login page HTML."
  (let ((login-html
         "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Autopoiesis - Login</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #1a1a1a;
            color: #e0e0e0;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .login-container {
            background: #2d2d2d;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            width: 100%;
            max-width: 400px;
        }
        .login-container h1 {
            color: #00d4aa;
            text-align: center;
            margin-bottom: 2rem;
        }
        .form-group {
            margin-bottom: 1rem;
        }
        label {
            display: block;
            margin-bottom: 0.5rem;
            color: #e0e0e0;
        }
        input[type=\"text\"], input[type=\"password\"] {
            width: 100%;
            padding: 0.75rem;
            border: 1px solid #404040;
            border-radius: 4px;
            background: #1a1a1a;
            color: #e0e0e0;
            box-sizing: border-box;
        }
        input[type=\"text\"]:focus, input[type=\"password\"]:focus {
            outline: none;
            border-color: #00d4aa;
        }
        button {
            width: 100%;
            padding: 0.75rem;
            background: #00d4aa;
            color: #1a1a1a;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 1rem;
            font-weight: bold;
        }
        button:hover {
            background: #00b894;
        }
        .error {
            color: #ff6b6b;
            margin-top: 1rem;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class=\"login-container\">
        <h1>Autopoiesis</h1>
        <form method=\"POST\" action=\"/auth/login\">
            <div class=\"form-group\">
                <label for=\"username\">Username</label>
                <input type=\"text\" id=\"username\" name=\"username\" required>
            </div>
            <div class=\"form-group\">
                <label for=\"password\">Password</label>
                <input type=\"password\" id=\"password\" name=\"password\" required>
            </div>
            <button type=\"submit\">Login</button>
        </form>
        <div id=\"error\" class=\"error\" style=\"display: none;\"></div>
    </div>

    <script>
        // Check for error parameter in URL
        const urlParams = new URLSearchParams(window.location.search);
        const error = urlParams.get('error');
        if (error) {
            const errorDiv = document.getElementById('error');
            errorDiv.textContent = decodeURIComponent(error);
            errorDiv.style.display = 'block';
        }
    </script>
</body>
</html>"))
    (list 200
          (list :content-type "text/html; charset=utf-8")
          (list login-html))))

(defun handle-login-post ()
  "Handle POST request to /auth/login."
  (let* ((username (hunchentoot:post-parameter "username"))
         (password (hunchentoot:post-parameter "password"))
         (ip-address (hunchentoot:remote-addr))
         (user-agent (hunchentoot:user-agent)))
    (handler-case
        (let ((session (autopoiesis.security:authenticate-user
                        username password
                        :ip-address ip-address
                        :user-agent user-agent)))
          ;; Set session cookie
          (set-session-cookie (autopoiesis.security:session-token session))

          ;; Audit successful login
          (autopoiesis.security:audit-log username :login :web-console :success
                                          (format nil "Web console login from ~a" ip-address))

          ;; Redirect to dashboard
          (hunchentoot:redirect "/dashboard" :code 302))
      (autopoiesis.security:authentication-error (e)
        ;; Audit failed login
        (autopoiesis.security:audit-log (autopoiesis.security:authentication-error-username e)
                                        :login :web-console :failure
                                        (format nil "Web console login failed from ~a" ip-address))

        ;; Redirect back to login with error
        (hunchentoot:redirect (format nil "/login?error=~a"
                                      (hunchentoot:url-encode "Invalid username or password"))
                              :code 302))
      (autopoiesis.security:account-inactive (e)
        ;; Audit inactive account login attempt
        (autopoiesis.security:audit-log (autopoiesis.security:authentication-error-username e)
                                        :login :web-console :failure
                                        "Web console login to inactive account")

        ;; Redirect back to login with error
        (hunchentoot:redirect (format nil "/login?error=~a"
                                      (hunchentoot:url-encode "Account is inactive"))
                              :code 302)))))

(defun handle-logout ()
  "Handle logout request."
  (let ((session-token (get-session-cookie)))
    (when session-token
      (multiple-value-bind (user session)
          (autopoiesis.security:validate-session-token session-token)
        (when (and user session)
          ;; Invalidate session
          (autopoiesis.security:logout-user session)

          ;; Audit logout
          (autopoiesis.security:audit-log (autopoiesis.security:user-username user)
                                          :logout :web-console :success
                                          "Web console logout"))))

    ;; Clear session cookie
    (clear-session-cookie)

    ;; Redirect to login
    (hunchentoot:redirect "/login" :code 302)))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Management Pages
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-user-management-page ()
  "Serve the user management page (admin only)."
  (require-web-auth-with-permission :admin)
  (let ((users-html
         (format nil
          "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Autopoiesis - User Management</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #1a1a1a;
            color: #e0e0e0;
            margin: 0;
            padding: 20px;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2rem;
        }
        .header h1 {
            color: #00d4aa;
        }
        .logout-btn {
            padding: 0.5rem 1rem;
            background: #404040;
            color: #e0e0e0;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            text-decoration: none;
        }
        .logout-btn:hover {
            background: #555;
        }
        .user-table {
            width: 100%;
            border-collapse: collapse;
            background: #2d2d2d;
            border-radius: 8px;
            overflow: hidden;
        }
        .user-table th, .user-table td {
            padding: 1rem;
            text-align: left;
            border-bottom: 1px solid #404040;
        }
        .user-table th {
            background: #404040;
            color: #00d4aa;
        }
        .status-active {
            color: #00d4aa;
        }
        .status-inactive {
            color: #666;
        }
        .role-admin {
            background: #ff6b6b;
            color: white;
            padding: 0.25rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8em;
        }
        .role-user {
            background: #00d4aa;
            color: white;
            padding: 0.25rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8em;
        }
        .create-user-btn {
            padding: 0.75rem 1.5rem;
            background: #00d4aa;
            color: #1a1a1a;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 1rem;
            margin-bottom: 1rem;
        }
        .create-user-btn:hover {
            background: #00b894;
        }
    </style>
</head>
<body>
    <div class=\"header\">
        <h1>User Management</h1>
        <a href=\"/logout\" class=\"logout-btn\">Logout</a>
    </div>

    <button class=\"create-user-btn\" onclick=\"showCreateUserForm()\">Create New User</button>

    <table class=\"user-table\">
        <thead>
            <tr>
                <th>Username</th>
                <th>Email</th>
                <th>Roles</th>
                <th>Status</th>
                <th>Last Login</th>
                <th>Created</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody id=\"users-table-body\">
            ~a
        </tbody>
    </table>

    <script>
        async function loadUsers() {
            try {
                const response = await fetch('/api/users');
                const users = await response.json();
                const tbody = document.getElementById('users-table-body');

                tbody.innerHTML = users.map(user => `
                    <tr>
                        <td>${user.username}</td>
                        <td>${user.email || ''}</td>
                        <td>${user.roles.map(role => `<span class=\"role-${role}\">${role}</span>`).join(' ')}</td>
                        <td class=\"${user.active ? 'status-active' : 'status-inactive'}\">${user.active ? 'Active' : 'Inactive'}</td>
                        <td>${user.last_login ? new Date(user.last_login * 1000).toLocaleString() : 'Never'}</td>
                        <td>${new Date(user.created_at * 1000).toLocaleString()}</td>
                        <td>
                            <button onclick=\"toggleUserStatus('${user.username}', ${!user.active})\">
                                ${user.active ? 'Deactivate' : 'Activate'}
                            </button>
                        </td>
                    </tr>
                `).join('');
            } catch (error) {
                console.error('Failed to load users:', error);
            }
        }

        function showCreateUserForm() {
            const username = prompt('Enter username:');
            if (!username) return;

            const email = prompt('Enter email (optional):');
            const password = prompt('Enter password:');
            if (!password) return;

            const roles = prompt('Enter roles (comma-separated, default: user):') || 'user';
            const roleList = roles.split(',').map(r => r.trim());

            fetch('/api/users', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    username: username,
                    password: password,
                    email: email || undefined,
                    roles: roleList
                })
            })
            .then(response => {
                if (response.ok) {
                    loadUsers();
                } else {
                    alert('Failed to create user');
                }
            })
            .catch(error => {
                console.error('Error creating user:', error);
                alert('Error creating user');
            });
        }

        async function toggleUserStatus(username, activate) {
            try {
                const response = await fetch(`/api/users/${username}/status`, {
                    method: 'PATCH',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        active: activate
                    })
                });

                if (response.ok) {
                    loadUsers();
                } else {
                    alert('Failed to update user status');
                }
            } catch (error) {
                console.error('Error updating user status:', error);
                alert('Error updating user status');
            }
        }

        // Load users on page load
        loadUsers();
    </script>
</body>
</html>"
          (generate-users-table-html))))
    (list 200
          (list :content-type "text/html; charset=utf-8")
          (list users-html))))

(defun generate-users-table-html ()
  "Generate HTML for the users table."
  (let ((users (autopoiesis.security:list-users)))
    (format nil "~{~a~}"
            (mapcar #'user-to-table-row-html users))))

(defun user-to-table-row-html (user)
  "Convert a user object to HTML table row."
  (format nil
          "<tr>
    <td>~a</td>
    <td>~a</td>
    <td>~{<span class=\"role-~a\">~a</span> ~}</td>
    <td class=\"~a\">~a</td>
    <td>~a</td>
    <td>~a</td>
    <td><button onclick=\"toggleUserStatus('~a', ~a)\">~a</button></td>
</tr>"
          (autopoiesis.security:user-username user)
          (or (autopoiesis.security:user-email user) "")
          (mapcan (lambda (role) (list role role)) (autopoiesis.security:user-roles user))
          (if (autopoiesis.security:user-active-p user) "status-active" "status-inactive")
          (if (autopoiesis.security:user-active-p user) "Active" "Inactive")
          (if (autopoiesis.security:user-last-login user)
              (format-timestring nil (autopoiesis.security:user-last-login user))
              "Never")
          (format-timestring nil (autopoiesis.security:user-created-at user))
          (autopoiesis.security:user-username user)
          (not (autopoiesis.security:user-active-p user))
          (if (autopoiesis.security:user-active-p user) "Deactivate" "Activate")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Authentication Middleware
;;; ═══════════════════════════════════════════════════════════════════

(defun require-web-auth ()
  "Require web authentication, redirecting to login if not authenticated.
   Returns the authenticated user object."
  (let ((session-token (get-session-cookie)))
    (unless session-token
      (hunchentoot:redirect "/login" :code 302)
      (return-from require-web-auth nil))

    (multiple-value-bind (user session)
        (autopoiesis.security:validate-session-token session-token)
      (unless (and user session)
        ;; Clear invalid cookie
        (clear-session-cookie)
        (hunchentoot:redirect "/login" :code 302)
        (return-from require-web-auth nil))

      ;; Update session cookie (refresh expiry)
      (set-session-cookie (autopoiesis.security:session-token session))

      user)))

(defun require-web-auth-with-permission (permission)
  "Require web authentication and specific permission.
   Redirects to login if not authenticated, or returns 403 if no permission."
  (let ((user (require-web-auth)))
    (unless user
      (return-from require-web-auth-with-permission nil))

    ;; Check permission using existing permission system
    (unless (autopoiesis.security:has-permission-p
             (autopoiesis.security:user-username user)
             permission)
      (setf (hunchentoot:return-code*) 403)
      (setf (hunchentoot:content-type*) "text/html")
      (hunchentoot:abort-request-handler
       "<!DOCTYPE html>
<html>
<head><title>Access Denied</title></head>
<body>
    <h1>Access Denied</h1>
    <p>You don't have permission to access this resource.</p>
    <a href=\"/dashboard\">Back to Dashboard</a>
</body>
</html>")
      (return-from require-web-auth-with-permission nil))

    user))

;;; ═══════════════════════════════════════════════════════════════════
;;; Dashboard Handler
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-dashboard ()
  "Serve the main dashboard page (requires authentication)."
  (let ((user (require-web-auth)))
    (unless user
      (return-from handle-dashboard nil))

    ;; Serve the existing dashboard.html but add user info
    (let* ((dashboard-path (merge-pathnames "dashboard.html" *api-static-path*))
           (dashboard-content (uiop:read-file-string dashboard-path)))
      ;; Add user info to the header
      (let ((modified-content
             (cl-ppcre:regex-replace
              "<div class=\"header\">"
              dashboard-content
              (format nil "<div class=\"header\">
    <div class=\"user-info\">
        Logged in as: <strong>~a</strong>
        <a href=\"/logout\" style=\"margin-left: 1rem; color: #00d4aa;\">Logout</a>
    </div>"
                      (autopoiesis.security:user-username user)))))
        (list 200
              (list :content-type "text/html; charset=utf-8")
              (list modified-content))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User API Endpoints
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-users-api ()
  "Handle GET /api/users - list all users (admin only)."
  (require-auth)  ;; API auth
  (let ((identity (authenticate-request)))
    (unless (has-permission-p* identity :admin)
      (json-error "Admin permission required" :status 403 :error-type "Forbidden"))

    (let ((users (autopoiesis.security:list-users)))
      (json-ok (mapcar #'user-to-json users)))))

(defun handle-create-user ()
  "Handle POST /api/users - create new user (admin only)."
  (require-auth)
  (let ((identity (authenticate-request)))
    (unless (has-permission-p* identity :admin)
      (json-error "Admin permission required" :status 403 :error-type "Forbidden"))

    (let* ((body (parse-json-body))
           (username (getf body :username))
           (password (getf body :password))
           (email (getf body :email))
           (roles (getf body :roles (list :user))))

      ;; Validate required fields
      (unless (and username password)
        (json-error "Username and password are required" :status 400 :error-type "Bad Request"))

      ;; Create user
      (let ((user (autopoiesis.security:create-user username password :email email :roles roles)))
        (json-ok (user-to-json user) :status 201)))))

(defun handle-user-status-update (username)
  "Handle PATCH /api/users/:username/status - update user active status."
  (require-auth)
  (let ((identity (authenticate-request)))
    (unless (has-permission-p* identity :admin)
      (json-error "Admin permission required" :status 403 :error-type "Forbidden"))

    (let* ((body (parse-json-body))
           (active (getf body :active))
           (user (autopoiesis.security:find-user-by-username username)))

      (unless user
        (json-not-found "User" username))

      ;; Update user active status in substrate
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom
              :entity (autopoiesis.security:user-id user)
              :attribute :user/active
              :value active)))

      ;; Update local object
      (setf (autopoiesis.security:user-active-p user) active)

      ;; Audit the change
      (autopoiesis.security:audit-log (getf identity :identity)
                                      :update :user :success
                                      (format nil "~a user ~a (active: ~a)"
                                              (if active "Activated" "Deactivated")
                                              username active))

      (json-ok (user-to-json user)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; JSON Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun user-to-json (user)
  "Convert user object to JSON-compatible plist."
  (list :id (autopoiesis.security:user-id user)
        :username (autopoiesis.security:user-username user)
        :email (autopoiesis.security:user-email user)
        :roles (autopoiesis.security:user-roles user)
        :active (autopoiesis.security:user-active-p user)
        :created-at (autopoiesis.security:user-created-at user)
        :last-login (autopoiesis.security:user-last-login user)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Route Integration
;;; ═══════════════════════════════════════════════════════════════════

(defvar *web-console-routes-added* nil
  "Whether web console routes have been added to the dispatch table.")

(defun add-web-console-routes ()
  "Add web console routes to Hunchentoot's dispatch table."
  (unless *web-console-routes-added*
    (push (hunchentoot:create-prefix-dispatcher "/login" #'handle-login-route)
          hunchentoot:*dispatch-table*)
    (push (hunchentoot:create-prefix-dispatcher "/auth/login" #'handle-login-post-route)
          hunchentoot:*dispatch-table*)
    (push (hunchentoot:create-prefix-dispatcher "/logout" #'handle-logout-route)
          hunchentoot:*dispatch-table*)
    (push (hunchentoot:create-prefix-dispatcher "/dashboard" #'handle-dashboard-route)
          hunchentoot:*dispatch-table*)
    (push (hunchentoot:create-prefix-dispatcher "/admin/users" #'handle-user-management-route)
          hunchentoot:*dispatch-table*)
    (push (hunchentoot:create-regex-dispatcher "^/api/users" #'handle-users-api-route)
          hunchentoot:*dispatch-table*)
    (setf *web-console-routes-added* t)))

(defun handle-login-route ()
  "Route handler for /login."
  (handle-login-page))

(defun handle-login-post-route ()
  "Route handler for POST /auth/login."
  (when (eq (hunchentoot:request-method*) :post)
    (handle-login-post)))

(defun handle-logout-route ()
  "Route handler for /logout."
  (handle-logout))

(defun handle-dashboard-route ()
  "Route handler for /dashboard."
  (handle-dashboard))

(defun handle-user-management-route ()
  "Route handler for /admin/users."
  (handle-user-management-page))

(defun handle-users-api-route ()
  "Route handler for /api/users*."
  (let ((uri (hunchentoot:request-uri*)))
    (cond
      ((string= uri "/api/users")
       (case (hunchentoot:request-method*)
         (:get (handle-users-api))
         (:post (handle-create-user))))
      ((cl-ppcre:scan "^/api/users/([^/]+)/status$" uri)
       (let ((username (cl-ppcre:regex-replace "^/api/users/([^/]+)/status$" uri "\\1")))
         (when (eq (hunchentoot:request-method*) :patch)
           (handle-user-status-update username))))
      (t (json-not-found "User API endpoint" uri)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defvar *web-console-initialized* nil
  "Whether web console has been initialized.")

(defun init-web-console ()
  "Initialize the web console system."
  (unless *web-console-initialized*
    ;; Ensure authentication system is initialized
    (autopoiesis.security:init-authentication-system)

    ;; Add web console routes
    (add-web-console-routes)

    (setf *web-console-initialized* t)
    (log:info "Web console initialized")))