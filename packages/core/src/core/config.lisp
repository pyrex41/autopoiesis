;;;; config.lisp - Production configuration management
;;;;
;;;; Provides hierarchical configuration with file loading and merging.

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Default Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *default-config*
  '(:server (:host "0.0.0.0"
             :port 8080
             :max-connections 100)
    :storage (:type :sqlite
              :path "/data/autopoiesis.db"
              :cache-size 1000)
    :logging (:level :info
              :file "/data/logs/autopoiesis.log"
              :rotate-size 10485760)  ; 10MB
    :security (:sandbox-level :strict
               :audit-enabled t
               :max-extension-size 10000)
    :performance (:parallel-systems t
                  :gc-threshold 100000000)
    :claude (:model "claude-sonnet-4-20250514"
             :max-tokens 4096
             :timeout 30))
  "Default configuration for Autopoiesis.
   This provides sensible defaults that can be overridden by file or environment.")

(defvar *current-config* nil
  "The currently active configuration.
   Set by load-config or initialize-config.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Merging
;;; ═══════════════════════════════════════════════════════════════════

(defun merge-configs (base override)
  "Recursively merge OVERRIDE configuration into BASE.
   
   Arguments:
     base    - Base configuration plist
     override - Override configuration plist (takes precedence)
   
   Returns: Merged configuration plist
   
   Merge rules:
   - If both values are plists, merge recursively
   - Otherwise, override value wins if present
   - Base value is used if override is missing"
  (cond
    ;; Both nil - return nil
    ((and (null base) (null override))
     nil)
    ;; Override is nil - use base
    ((null override)
     base)
    ;; Base is nil - use override
    ((null base)
     override)
    ;; Both are plists - merge recursively
    ((and (plist-p base) (plist-p override))
     (let ((result (copy-list base)))
       (loop for (key value) on override by #'cddr
             do (let ((base-value (getf result key)))
                  (setf (getf result key)
                        (if (and (plist-p base-value) (plist-p value))
                            (merge-configs base-value value)
                            value))))
       result))
    ;; Otherwise, override wins
    (t override)))

(defun plist-p (obj)
  "Check if OBJ is a property list (list with keyword keys)."
  (and (listp obj)
       (evenp (length obj))
       (loop for (key value) on obj by #'cddr
             always (keywordp key))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Loading
;;; ═══════════════════════════════════════════════════════════════════

(defun load-config (&optional (path nil))
  "Load configuration from file, merging with defaults.
   
   Arguments:
     path - Path to configuration file (optional)
            If nil, tries standard locations:
            1. /etc/autopoiesis/config.lisp
            2. ~/.autopoiesis/config.lisp
            3. ./config.lisp
   
   Returns: Merged configuration plist
   
   The configuration file should contain a single plist expression."
  (let* ((config-path (or path (find-config-file)))
         (file-config (when config-path
                        (load-config-from-file config-path)))
         (env-config (load-config-from-env))
         (merged (merge-configs *default-config*
                               (merge-configs file-config env-config))))
    (setf *current-config* merged)
    merged))

(defun find-config-file ()
  "Find configuration file in standard locations."
  (let ((paths (list "/etc/autopoiesis/config.lisp"
                     (merge-pathnames ".autopoiesis/config.lisp"
                                      (user-homedir-pathname))
                     "config.lisp")))
    (find-if #'probe-file paths)))

(defun load-config-from-file (path)
  "Load configuration from a file.
   
   Arguments:
     path - Path to configuration file
   
   Returns: Configuration plist or NIL on error"
  (handler-case
      (when (probe-file path)
        (with-open-file (in path :direction :input)
          (let ((config (read in nil nil)))
            (if (plist-p config)
                config
                (progn
                  (warn "Configuration file ~a does not contain a valid plist" path)
                  nil)))))
    (error (e)
      (warn "Error loading configuration from ~a: ~a" path e)
      nil)))

(defun load-config-from-env ()
  "Load configuration overrides from environment variables.
   
   Environment variables:
     AUTOPOIESIS_HOST        - Server host
     AUTOPOIESIS_PORT        - Server port
     AUTOPOIESIS_DATA_DIR    - Data directory
     AUTOPOIESIS_LOG_LEVEL   - Logging level (debug, info, warn, error)
     AUTOPOIESIS_LOG_FILE    - Log file path
     ANTHROPIC_API_KEY       - Claude API key (stored in :claude :api-key)
     AUTOPOIESIS_MODEL       - Claude model name
   
   Returns: Configuration plist with environment overrides"
  (let ((config nil))
    ;; Server settings
    (when-let ((host (uiop:getenv "AUTOPOIESIS_HOST")))
      (setf (getf (getf config :server) :host) host))
    (when-let ((port (uiop:getenv "AUTOPOIESIS_PORT")))
      (setf (getf (getf config :server) :port) (parse-integer port :junk-allowed t)))
    
    ;; Storage settings
    (when-let ((data-dir (uiop:getenv "AUTOPOIESIS_DATA_DIR")))
      (setf (getf (getf config :storage) :path)
            (merge-pathnames "autopoiesis.db" data-dir)))
    
    ;; Logging settings
    (when-let ((log-level (uiop:getenv "AUTOPOIESIS_LOG_LEVEL")))
      (setf (getf (getf config :logging) :level)
            (intern (string-upcase log-level) :keyword)))
    (when-let ((log-file (uiop:getenv "AUTOPOIESIS_LOG_FILE")))
      (setf (getf (getf config :logging) :file) log-file))
    
    ;; Claude settings
    (when-let ((api-key (uiop:getenv "ANTHROPIC_API_KEY")))
      (setf (getf (getf config :claude) :api-key) api-key))
    (when-let ((model (uiop:getenv "AUTOPOIESIS_MODEL")))
      (setf (getf (getf config :claude) :model) model))
    
    config))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Access
;;; ═══════════════════════════════════════════════════════════════════

(defun config-get (path &optional default)
  "Get configuration value by path.
   
   Arguments:
     path    - List of keywords representing the path, e.g. '(:server :port)
     default - Default value if path not found
   
   Returns: Configuration value or DEFAULT
   
   Examples:
     (config-get '(:server :port))        => 8080
     (config-get '(:claude :model))       => \"claude-sonnet-4-20250514\"
     (config-get '(:missing :key) :none)  => :none"
  (let ((config (or *current-config* *default-config*)))
    (config-get-path config path default)))

(defun config-get-path (config path default)
  "Navigate CONFIG by PATH, returning DEFAULT if not found."
  (if (null path)
      config
      (let ((value (getf config (first path) :not-found)))
        (if (eq value :not-found)
            default
            (if (rest path)
                (if (plist-p value)
                    (config-get-path value (rest path) default)
                    default)
                value)))))

(defun config-set (path value)
  "Set configuration value at PATH.
   
   Arguments:
     path  - List of keywords representing the path
     value - Value to set
   
   Returns: The new value
   
   Note: This modifies *current-config*. If *current-config* is nil,
   it will be initialized from *default-config* first."
  (unless *current-config*
    (setf *current-config* (copy-tree *default-config*)))
  (setf *current-config* (config-set-path *current-config* path value))
  value)

(defun config-set-path (config path value)
  "Set VALUE at PATH in CONFIG, creating intermediate plists as needed.
   Returns the modified config."
  (cond
    ;; Empty path - just return value (shouldn't happen normally)
    ((null path)
     value)
    ;; Single key - set directly
    ((null (rest path))
     (let ((result (copy-list (or config nil))))
       (setf (getf result (first path)) value)
       result))
    ;; Multiple keys - recurse
    (t
     (let* ((result (copy-list (or config nil)))
            (subconfig (getf result (first path)))
            (new-subconfig (config-set-path 
                            (if (plist-p subconfig) subconfig nil)
                            (rest path) 
                            value)))
       (setf (getf result (first path)) new-subconfig)
       result))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defun initialize-config (&key (path nil) (load-env t))
  "Initialize the configuration system.
   
   Arguments:
     path     - Optional path to configuration file
     load-env - Whether to load environment overrides (default T)
   
   Returns: The initialized configuration"
  (let* ((file-config (when path (load-config-from-file path)))
         (env-config (when load-env (load-config-from-env)))
         (merged (merge-configs *default-config*
                               (merge-configs file-config env-config))))
    (setf *current-config* merged)
    merged))

(defun reset-config ()
  "Reset configuration to defaults."
  (setf *current-config* (copy-tree *default-config*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-config (&optional (config *current-config*))
  "Validate configuration structure and values.
   
   Returns: (values valid-p errors)
     valid-p - T if configuration is valid
     errors  - List of validation error strings"
  (let ((errors nil)
        (config (or config *default-config*)))
    
    ;; Check required sections exist
    (dolist (section '(:server :storage :logging :security :performance :claude))
      (unless (getf config section)
        (push (format nil "Missing required section: ~a" section) errors)))
    
    ;; Validate server section
    (let ((server (getf config :server)))
      (when server
        (let ((port (getf server :port)))
          (when (and port (not (typep port '(integer 1 65535))))
            (push (format nil "Invalid server port: ~a (must be 1-65535)" port) errors)))
        (let ((max-conn (getf server :max-connections)))
          (when (and max-conn (not (typep max-conn '(integer 1))))
            (push (format nil "Invalid max-connections: ~a" max-conn) errors)))))
    
    ;; Validate logging section
    (let ((logging (getf config :logging)))
      (when logging
        (let ((level (getf logging :level)))
          (when (and level (not (member level '(:debug :info :warn :error))))
            (push (format nil "Invalid log level: ~a" level) errors)))
        (let ((rotate-size (getf logging :rotate-size)))
          (when (and rotate-size (not (typep rotate-size '(integer 1))))
            (push (format nil "Invalid rotate-size: ~a" rotate-size) errors)))))
    
    ;; Validate security section
    (let ((security (getf config :security)))
      (when security
        (let ((sandbox (getf security :sandbox-level)))
          (when (and sandbox (not (member sandbox '(:strict :moderate :permissive))))
            (push (format nil "Invalid sandbox-level: ~a" sandbox) errors)))))
    
    ;; Validate claude section
    (let ((claude (getf config :claude)))
      (when claude
        (let ((timeout (getf claude :timeout)))
          (when (and timeout (not (typep timeout '(integer 1))))
            (push (format nil "Invalid claude timeout: ~a" timeout) errors)))
        (let ((max-tokens (getf claude :max-tokens)))
          (when (and max-tokens (not (typep max-tokens '(integer 1))))
            (push (format nil "Invalid max-tokens: ~a" max-tokens) errors)))))
    
    (values (null errors) (nreverse errors))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Export
;;; ═══════════════════════════════════════════════════════════════════

(defun save-config (path &optional (config *current-config*))
  "Save configuration to a file.
   
   Arguments:
     path   - Path to save configuration to
     config - Configuration to save (default *current-config*)
   
   Returns: T on success, NIL on failure"
  (handler-case
      (progn
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
          (let ((*print-pretty* t)
                (*print-right-margin* 80))
            (write config :stream out)
            (terpri out)))
        t)
    (error (e)
      (warn "Error saving configuration to ~a: ~a" path e)
      nil)))

(defun config-to-string (&optional (config *current-config*))
  "Convert configuration to a readable string."
  (with-output-to-string (out)
    (let ((*print-pretty* t)
          (*print-right-margin* 80))
      (write (or config *default-config*) :stream out))))
