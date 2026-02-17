;;;; audit.lisp - Audit logging with rotation for Autopoiesis
;;;;
;;;; Implements audit trail logging with automatic log rotation.
;;;; Phase 10.2: Security Hardening

(in-package #:autopoiesis.security)

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Entry Structure
;;; ═══════════════════════════════════════════════════════════════════

(defstruct audit-entry
  "Represents a single audit log entry."
  (timestamp (get-universal-time) :type integer)
  (agent-id nil :type (or null string))
  (action nil :type (or null keyword))
  (resource nil :type (or null keyword string))
  (result nil :type (or null keyword))
  (details nil :type (or null string list)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Variables
;;; ═══════════════════════════════════════════════════════════════════

(defvar *audit-log* nil
  "Current audit log output stream. NIL means logging is disabled.")

(defvar *audit-log-path* nil
  "Path to the current audit log file.")

(defvar *audit-log-max-size* (* 10 1024 1024)  ; 10MB default
  "Maximum size of audit log file before rotation (in bytes).")

(defvar *audit-log-max-files* 5
  "Maximum number of rotated audit log files to keep.")

(defvar *audit-log-lock* (bordeaux-threads:make-recursive-lock "audit-log-lock")
  "Recursive lock for thread-safe audit logging.")

(defvar *audit-log-current-size* 0
  "Current size of the audit log file in bytes.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun format-timestamp (universal-time)
  "Format a universal time as ISO 8601 string."
  (multiple-value-bind (second minute hour date month year)
      (decode-universal-time universal-time 0)
    (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
            year month date hour minute second)))

(defun serialize-audit-entry (entry)
  "Serialize an audit entry to a JSON string.
   
   Arguments:
     entry - audit-entry struct
   
   Returns: JSON string representation"
  (cl-json:encode-json-to-string
   `((:timestamp . ,(format-timestamp (audit-entry-timestamp entry)))
     (:agent-id . ,(audit-entry-agent-id entry))
     (:action . ,(when (audit-entry-action entry)
                   (string-downcase (symbol-name (audit-entry-action entry)))))
     (:resource . ,(let ((res (audit-entry-resource entry)))
                     (cond
                       ((keywordp res) (string-downcase (symbol-name res)))
                       ((stringp res) res)
                       (t nil))))
     (:result . ,(when (audit-entry-result entry)
                   (string-downcase (symbol-name (audit-entry-result entry)))))
     (:details . ,(let ((details (audit-entry-details entry)))
                    (if (stringp details)
                        details
                        (when details (prin1-to-string details))))))))

(defun deserialize-audit-entry (json-string)
  "Deserialize a JSON string to an audit entry.
   
   Arguments:
     json-string - JSON representation of audit entry
   
   Returns: audit-entry struct"
  (let ((data (cl-json:decode-json-from-string json-string)))
    (make-audit-entry
     :timestamp (or (parse-iso-timestamp (cdr (assoc :timestamp data)))
                    (get-universal-time))
     :agent-id (cdr (assoc :agent-id data))
     :action (let ((a (cdr (assoc :action data))))
               (when a (intern (string-upcase a) :keyword)))
     :resource (let ((r (cdr (assoc :resource data))))
                 (when r
                   (if (find #\: r)
                       r  ; Keep as string if it looks like a path
                       (intern (string-upcase r) :keyword))))
     :result (let ((r (cdr (assoc :result data))))
               (when r (intern (string-upcase r) :keyword)))
     :details (cdr (assoc :details data)))))

(defun parse-iso-timestamp (timestamp-string)
  "Parse an ISO 8601 timestamp string to universal time.
   Returns NIL if parsing fails."
  (when (and timestamp-string (>= (length timestamp-string) 19))
    (handler-case
        (let ((year (parse-integer (subseq timestamp-string 0 4)))
              (month (parse-integer (subseq timestamp-string 5 7)))
              (day (parse-integer (subseq timestamp-string 8 10)))
              (hour (parse-integer (subseq timestamp-string 11 13)))
              (minute (parse-integer (subseq timestamp-string 14 16)))
              (second (parse-integer (subseq timestamp-string 17 19))))
          (encode-universal-time second minute hour day month year 0))
      (error () nil))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Log Rotation
;;; ═══════════════════════════════════════════════════════════════════

(defun rotate-audit-log ()
  "Rotate the audit log file.
   
   Renames current log to .1, shifts existing rotated logs (.1 -> .2, etc.),
   and deletes logs beyond *audit-log-max-files*.
   
   Returns: T if rotation succeeded, NIL otherwise"
  (when (and *audit-log-path* (probe-file *audit-log-path*))
    (bordeaux-threads:with-recursive-lock-held (*audit-log-lock*)
      ;; Close current log
      (when *audit-log*
        (close *audit-log*)
        (setf *audit-log* nil))
      
      ;; Delete oldest log if it exists
      (let ((oldest (make-pathname :defaults *audit-log-path*
                                   :type (format nil "~a.~d" 
                                                 (pathname-type *audit-log-path*)
                                                 *audit-log-max-files*))))
        (when (probe-file oldest)
          (delete-file oldest)))
      
      ;; Shift existing rotated logs
      (loop for i from (1- *audit-log-max-files*) downto 1
            do (let ((old-path (make-pathname :defaults *audit-log-path*
                                              :type (format nil "~a.~d"
                                                            (pathname-type *audit-log-path*)
                                                            i)))
                     (new-path (make-pathname :defaults *audit-log-path*
                                              :type (format nil "~a.~d"
                                                            (pathname-type *audit-log-path*)
                                                            (1+ i)))))
                 (when (probe-file old-path)
                   (rename-file old-path new-path))))
      
      ;; Rename current log to .1
      (let ((rotated-path (make-pathname :defaults *audit-log-path*
                                         :type (format nil "~a.1"
                                                       (pathname-type *audit-log-path*)))))
        (rename-file *audit-log-path* rotated-path))
      
      ;; Open new log file
      (setf *audit-log* (open *audit-log-path*
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create))
      (setf *audit-log-current-size* 0)
      t)))

(defun check-rotation-needed ()
  "Check if log rotation is needed based on current file size.
   Triggers rotation if size exceeds *audit-log-max-size*."
  (when (and *audit-log-path*
             (> *audit-log-current-size* *audit-log-max-size*))
    (rotate-audit-log)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Logging Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun audit-log-active-p ()
  "Check if audit logging is currently active."
  (not (null *audit-log*)))

(defun audit-log (agent-id action resource result &optional details)
  "Log an action to the audit trail.
   
   Arguments:
     agent-id - ID of the agent performing the action
     action   - Action being performed (keyword)
     resource - Resource being acted upon (keyword or string)
     result   - Result of the action (:success, :failure, :error)
     details  - Optional additional details (string or list)
   
   Returns: The audit entry that was logged, or NIL if logging is disabled"
  (when *audit-log*
    (let ((entry (make-audit-entry
                  :timestamp (get-universal-time)
                  :agent-id agent-id
                  :action action
                  :resource resource
                  :result result
                  :details details)))
      (bordeaux-threads:with-recursive-lock-held (*audit-log-lock*)
        (let ((line (serialize-audit-entry entry)))
          (write-line line *audit-log*)
          (force-output *audit-log*)
          (incf *audit-log-current-size* (1+ (length line)))
          (check-rotation-needed)))
      entry)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Logging Macros
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-audit ((agent action resource) &body body)
  "Execute body with audit logging of the result.
   
   Logs the action before execution and the result after.
   
   Usage:
     (with-audit (agent :read :snapshot)
       (load-snapshot id))
   
   Arguments:
     agent    - Agent object or agent-id string
     action   - Action keyword
     resource - Resource keyword or string"
  (let ((agent-var (gensym "AGENT"))
        (agent-id-var (gensym "AGENT-ID"))
        (result-var (gensym "RESULT"))
        (error-var (gensym "ERROR")))
    `(let* ((,agent-var ,agent)
            (,agent-id-var (if (stringp ,agent-var)
                               ,agent-var
                               (when ,agent-var
                                 (autopoiesis.agent:agent-id ,agent-var))))
            (,result-var nil)
            (,error-var nil))
       (unwind-protect
            (handler-case
                (progn
                  (setf ,result-var (progn ,@body))
                  (audit-log ,agent-id-var ,action ,resource :success)
                  ,result-var)
              (error (e)
                (setf ,error-var e)
                (audit-log ,agent-id-var ,action ,resource :error
                           (princ-to-string e))
                (error e)))
         (when (and (null ,result-var) (null ,error-var))
           (audit-log ,agent-id-var ,action ,resource :failure))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Log Management
;;; ═══════════════════════════════════════════════════════════════════

(defun start-audit-logging (path &key (max-size *audit-log-max-size*)
                                      (max-files *audit-log-max-files*))
  "Start audit logging to the specified file.
   
   Arguments:
     path      - Path to the audit log file
     max-size  - Maximum file size before rotation (default 10MB)
     max-files - Maximum number of rotated files to keep (default 5)
   
   Returns: T if logging started successfully"
  (bordeaux-threads:with-recursive-lock-held (*audit-log-lock*)
    ;; Close existing log if any
    (when *audit-log*
      (close *audit-log*)
      (setf *audit-log* nil))
    
    ;; Set configuration
    (setf *audit-log-path* (pathname path))
    (setf *audit-log-max-size* max-size)
    (setf *audit-log-max-files* max-files)
    
    ;; Ensure directory exists
    (ensure-directories-exist *audit-log-path*)
    
    ;; Open log file (append if exists)
    (setf *audit-log* (open *audit-log-path*
                            :direction :output
                            :if-exists :append
                            :if-does-not-exist :create))
    
    ;; Get current file size
    (setf *audit-log-current-size*
          (if (probe-file *audit-log-path*)
              (with-open-file (f *audit-log-path*)
                (file-length f))
              0))
    
    ;; Log startup (directly, without acquiring lock again)
    (let ((entry (make-audit-entry
                  :timestamp (get-universal-time)
                  :agent-id "system"
                  :action :start
                  :resource :audit-log
                  :result :success
                  :details (format nil "Audit logging started: ~a" path))))
      (let ((line (serialize-audit-entry entry)))
        (write-line line *audit-log*)
        (force-output *audit-log*)
        (incf *audit-log-current-size* (1+ (length line)))))
    t))

(defun stop-audit-logging ()
  "Stop audit logging and close the log file.
   
   Returns: T if logging was stopped, NIL if it wasn't active"
  (bordeaux-threads:with-recursive-lock-held (*audit-log-lock*)
    (when *audit-log*
      ;; Log shutdown before closing
      (let ((entry (make-audit-entry
                    :timestamp (get-universal-time)
                    :agent-id "system"
                    :action :stop
                    :resource :audit-log
                    :result :success)))
        (write-line (serialize-audit-entry entry) *audit-log*)
        (force-output *audit-log*))
      
      (close *audit-log*)
      (setf *audit-log* nil)
      (setf *audit-log-path* nil)
      (setf *audit-log-current-size* 0)
      t)))

(defmacro with-audit-logging ((path &key (max-size '*audit-log-max-size*)
                                         (max-files '*audit-log-max-files*))
                              &body body)
  "Execute body with audit logging enabled to the specified path.
   
   Automatically starts and stops audit logging around the body.
   
   Usage:
     (with-audit-logging (\"/var/log/autopoiesis/audit.log\")
       (do-something))"
  `(progn
     (start-audit-logging ,path :max-size ,max-size :max-files ,max-files)
     (unwind-protect
          (progn ,@body)
       (stop-audit-logging))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Log Reading
;;; ═══════════════════════════════════════════════════════════════════

(defun read-audit-log (path &key (limit nil) (agent-id nil) (action nil)
                                 (resource nil) (result nil)
                                 (start-time nil) (end-time nil))
  "Read and filter audit log entries from a file.
   
   Arguments:
     path       - Path to the audit log file
     limit      - Maximum number of entries to return
     agent-id   - Filter by agent ID
     action     - Filter by action keyword
     resource   - Filter by resource
     result     - Filter by result keyword
     start-time - Filter entries after this universal time
     end-time   - Filter entries before this universal time
   
   Returns: List of audit-entry structs matching the filters"
  (when (probe-file path)
    (with-open-file (in path :direction :input)
      (let ((entries nil)
            (count 0))
        (loop for line = (read-line in nil nil)
              while (and line
                         (or (null limit) (< count limit)))
              do (handler-case
                     (let ((entry (deserialize-audit-entry line)))
                       (when (and (or (null agent-id)
                                      (equal agent-id (audit-entry-agent-id entry)))
                                  (or (null action)
                                      (eq action (audit-entry-action entry)))
                                  (or (null resource)
                                      (equal resource (audit-entry-resource entry)))
                                  (or (null result)
                                      (eq result (audit-entry-result entry)))
                                  (or (null start-time)
                                      (>= (audit-entry-timestamp entry) start-time))
                                  (or (null end-time)
                                      (<= (audit-entry-timestamp entry) end-time)))
                         (push entry entries)
                         (incf count)))
                   (error () nil)))  ; Skip malformed lines
        (nreverse entries)))))
