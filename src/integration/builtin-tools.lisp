;;;; builtin-tools.lisp - Built-in external tools
;;;;
;;;; Provides file system, web, and shell tools as capabilities that
;;;; agents can use to interact with the external environment.
;;;;
;;;; Note: All parameters are keyword parameters to be compatible with
;;;; Claude tool invocation which always passes arguments as keywords.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; File System Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability read-file (&key path start-line end-line)
  "Read contents of a file at PATH.

   Optional START-LINE and END-LINE parameters allow reading a range of lines.
   Returns the file contents as a string, or an error message on failure."
  :permissions (:file-read)
  :body
  (handler-case
      (if (not (probe-file path))
          (format nil "Error: File not found: ~a" path)
          (with-open-file (in path :direction :input)
            (let ((lines (loop for line = (read-line in nil nil)
                               for i from 1
                               while line
                               when (and (or (null start-line) (>= i start-line))
                                         (or (null end-line) (<= i end-line)))
                               collect line)))
              (format nil "~{~a~^~%~}" lines))))
    (error (e)
      (format nil "Error reading file ~a: ~a" path e))))

(autopoiesis.agent:defcapability write-file (&key path content)
  "Write CONTENT to file at PATH.

   Creates parent directories if they don't exist.
   Returns a success message or an error message on failure."
  :permissions (:file-write)
  :body
  (handler-case
      (progn
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
          (write-string content out))
        (format nil "Successfully wrote ~a bytes to ~a"
                (length content) path))
    (error (e)
      (format nil "Error writing file ~a: ~a" path e))))

(autopoiesis.agent:defcapability list-directory (&key path pattern recursive)
  "List contents of directory at PATH.

   Optional PATTERN is a glob pattern to filter results (default '*').
   If RECURSIVE is true, searches subdirectories too.
   Returns a newline-separated list of file paths."
  :permissions (:file-read)
  :body
  (handler-case
      (let* ((dir-path (if (char= (char path (1- (length path))) #\/)
                           path
                           (concatenate 'string path "/")))
             (wild-path (merge-pathnames (or pattern "*.*")
                                         (pathname dir-path)))
             (entries (if recursive
                          (directory (make-pathname
                                      :defaults wild-path
                                      :directory (append (pathname-directory wild-path)
                                                        '(:wild-inferiors))))
                          (directory wild-path))))
        (if entries
            (format nil "~{~a~^~%~}" (mapcar #'namestring entries))
            "No files found"))
    (error (e)
      (format nil "Error listing directory ~a: ~a" path e))))

(autopoiesis.agent:defcapability file-exists-p (&key path)
  "Check if a file exists at PATH.

   Returns 'true' if the file exists, 'false' otherwise."
  :permissions (:file-read)
  :body
  (if (probe-file path) "true" "false"))

(autopoiesis.agent:defcapability delete-file-tool (&key path)
  "Delete the file at PATH.

   Returns a success message or an error message on failure."
  :permissions (:file-write)
  :body
  (handler-case
      (progn
        (delete-file path)
        (format nil "Successfully deleted ~a" path))
    (file-error (e)
      (format nil "Error deleting ~a: ~a" path e))))

(autopoiesis.agent:defcapability glob-files (&key pattern base-directory)
  "Find files matching PATTERN.

   BASE-DIRECTORY defaults to current working directory.
   Returns a newline-separated list of matching file paths."
  :permissions (:file-read)
  :body
  (handler-case
      (let* ((base (or base-directory (uiop:getcwd)))
             (full-pattern (merge-pathnames pattern base))
             (matches (directory full-pattern)))
        (if matches
            (format nil "~{~a~^~%~}" (mapcar #'namestring matches))
            "No matches found"))
    (error (e)
      (format nil "Error searching for ~a: ~a" pattern e))))

(autopoiesis.agent:defcapability grep-files (&key pattern path file-pattern)
  "Search for PATTERN in files.

   PATH is the directory to search (default: current directory).
   FILE-PATTERN is a glob to filter files (default: '**/*').
   Returns matching lines with file:line: prefix."
  :permissions (:file-read)
  :body
  (handler-case
      (let ((results nil)
            (search-path (or path (uiop:getcwd)))
            (file-glob (or file-pattern "**/*")))
        (dolist (file (directory (merge-pathnames file-glob search-path)))
          (when (and (probe-file file)
                     (not (uiop:directory-pathname-p file)))
            (handler-case
                (with-open-file (in file :direction :input)
                  (loop for line = (read-line in nil nil)
                        for line-num from 1
                        while line
                        when (search pattern line)
                        do (push (format nil "~a:~a: ~a"
                                         (namestring file) line-num line)
                                 results)))
              (error () nil))))  ; Skip unreadable files
        (if results
            (format nil "~{~a~^~%~}" (nreverse results))
            "No matches found"))
    (error (e)
      (format nil "Error searching: ~a" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Web Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability web-fetch (&key url method headers body)
  "Fetch content from URL.

   METHOD defaults to :GET.
   HEADERS is an alist of header name-value pairs.
   BODY is the request body (for POST/PUT/etc).
   Returns the response body as a string, or an error message."
  :permissions (:network)
  :body
  (handler-case
      (let* ((method-key (if method
                             (intern (string-upcase method) :keyword)
                             :get))
             (response (dex:request url
                                    :method method-key
                                    :headers headers
                                    :content body)))
        (if (stringp response)
            response
            (babel:octets-to-string response :encoding :utf-8)))
    (dex:http-request-failed (e)
      (format nil "HTTP request failed (~a): ~a"
              (dex:response-status e)
              (dex:response-body e)))
    (error (e)
      (format nil "Error fetching ~a: ~a" url e))))

(autopoiesis.agent:defcapability web-head (&key url headers)
  "Perform a HEAD request to URL.

   Returns response headers as a string, or an error message."
  :permissions (:network)
  :body
  (handler-case
      (multiple-value-bind (body status headers)
          (dex:head url :headers headers)
        (declare (ignore body))
        (format nil "Status: ~a~%Headers:~%~{~a: ~a~^~%~}"
                status
                (loop for (k . v) in headers
                      collect k collect v)))
    (error (e)
      (format nil "Error fetching ~a: ~a" url e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Shell Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability run-command (&key command working-directory timeout)
  "Run a shell command.

   WORKING-DIRECTORY defaults to current directory.
   TIMEOUT in seconds (default: no timeout).
   Returns command output (stdout + stderr combined) as a string."
  :permissions (:shell)
  :body
  (handler-case
      (let* ((dir (or working-directory (uiop:getcwd))))
        (multiple-value-bind (output error-output exit-code)
            (uiop:run-program command
                              :directory dir
                              :output :string
                              :error-output :string
                              :ignore-error-status t)
          (let ((result (if (and error-output (> (length error-output) 0))
                            (format nil "~a~%~a" output error-output)
                            output)))
            (if (zerop exit-code)
                result
                (format nil "~a~%[Exit code: ~a]" result exit-code)))))
    (error (e)
      (format nil "Error running command: ~a" e))))

(autopoiesis.agent:defcapability git-status (&key directory)
  "Get git status.

   DIRECTORY defaults to current working directory.
   Returns porcelain status output."
  :permissions (:shell)
  :body
  (funcall (autopoiesis.agent:capability-function
            (autopoiesis.agent:find-capability 'run-command))
           :command "git status --porcelain"
           :working-directory directory))

(autopoiesis.agent:defcapability git-diff (&key directory staged)
  "Get git diff.

   DIRECTORY defaults to current working directory.
   If STAGED is true, shows staged changes only.
   Returns diff output."
  :permissions (:shell)
  :body
  (funcall (autopoiesis.agent:capability-function
            (autopoiesis.agent:find-capability 'run-command))
           :command (if staged "git diff --staged" "git diff")
           :working-directory directory))

(autopoiesis.agent:defcapability git-log (&key directory count format-string)
  "Get git log.

   DIRECTORY defaults to current working directory.
   COUNT limits the number of commits (default: 10).
   FORMAT-STRING customizes output format (default: oneline).
   Returns log output."
  :permissions (:shell)
  :body
  (let ((n (or count 10))
        (fmt (or format-string "oneline")))
    (funcall (autopoiesis.agent:capability-function
              (autopoiesis.agent:find-capability 'run-command))
             :command (format nil "git log -~a --format=~a" n fmt)
             :working-directory directory)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tool Registration
;;; ═══════════════════════════════════════════════════════════════════

(defvar *builtin-tools-registered* nil
  "Flag indicating whether builtin tools have been registered.")

(defun builtin-tool-symbols ()
  "Return a list of all builtin tool symbols (in this package).

   These are the actual symbols used as capability names by defcapability."
  '(read-file write-file list-directory file-exists-p
    delete-file-tool glob-files grep-files
    web-fetch web-head
    run-command git-status git-diff git-log))

(defun register-builtin-tools (&key (registry autopoiesis.agent:*capability-registry*))
  "Register all built-in tools in the capability registry.

   REGISTRY defaults to the global capability registry.
   Returns the list of registered capability names.

   Note: The capabilities are registered with their symbol names from
   the autopoiesis.integration package (e.g., read-file, not :read-file)."
  (let ((registered nil))
    (dolist (name (builtin-tool-symbols))
      (let ((cap (autopoiesis.agent:find-capability name)))
        (when cap
          (autopoiesis.agent:register-capability cap :registry registry)
          (push name registered))))
    (setf *builtin-tools-registered* t)
    (nreverse registered)))

(defun unregister-builtin-tools (&key (registry autopoiesis.agent:*capability-registry*))
  "Unregister all built-in tools from the capability registry.

   REGISTRY defaults to the global capability registry."
  (dolist (name (builtin-tool-symbols))
    (autopoiesis.agent:unregister-capability name :registry registry))
  (setf *builtin-tools-registered* nil))

(defun list-builtin-tools ()
  "Return a list of all builtin tool names as symbols.

   Note: These are symbols in the autopoiesis.integration package."
  (builtin-tool-symbols))
