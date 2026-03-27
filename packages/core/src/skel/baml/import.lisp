;;;; import.lisp - BAML file import system

(in-package #:autopoiesis.skel.baml)

;;; ============================================================================
;;; Client Registry
;;; ============================================================================

(defvar *baml-clients* (make-hash-table :test 'equal)
  "Registry of BAML client configurations.")

(defun register-baml-client (client-def)
  "Register a BAML client definition for use in functions."
  (setf (gethash (baml-client-def-name client-def) *baml-clients*)
        client-def))

(defun resolve-baml-client (name)
  "Resolve a BAML client reference to actual provider/model."
  (or (gethash name *baml-clients*)
      (parse-shorthand-client name)))

(defun parse-shorthand-client (name)
  "Parse a shorthand client reference like \"openai/gpt-4\"."
  (when (and name (stringp name))
    (let ((parts (cl-ppcre:split "/" name)))
      (when (= (length parts) 2)
        (make-baml-client-def
         :name name
         :provider (first parts)
         :options (list :model (second parts)))))))

(defun clear-baml-clients ()
  "Clear all registered BAML clients."
  (clrhash *baml-clients*))

(defun list-baml-clients ()
  "Return a list of all registered client names."
  (let ((names nil))
    (maphash (lambda (k v)
               (declare (ignore v))
               (push k names))
             *baml-clients*)
    (nreverse names)))

;;; ============================================================================
;;; File Import
;;; ============================================================================

(defun read-file-content (path)
  "Read file content as a string."
  (handler-case
      (uiop:read-file-string path)
    (error (e)
      (error 'baml-import-error
             :path path
             :message "Failed to read file"
             :cause e))))

(defun import-baml-file (path &key (eval-p t))
  "Import a .baml file and register SKEL definitions."
  (let* ((path (pathname path))
         (content (read-file-content path))
         (definitions (handler-case
                          (parse-baml-content content)
                        (baml-error (e)
                          (error 'baml-import-error
                                 :path path
                                 :message "Parse error"
                                 :cause e))))
         (defined-symbols nil))

    (dolist (def definitions)
      (etypecase def
        (baml-class
         (let ((skel-class (baml-class->skel-class def)))
           (when eval-p
             (eval skel-class))
           (push (intern (lisp-symbol-name (baml-class-name def)))
                 defined-symbols)))

        (baml-function
         (let ((skel-func (baml-function->skel-function def)))
           (when eval-p
             (eval skel-func))
           (push (intern (lisp-symbol-name (baml-function-name def)))
                 defined-symbols)))

        (baml-enum
         (let ((skel-enum (baml-enum->skel-enum def)))
           (when eval-p
             (eval skel-enum))
           (push (intern (lisp-symbol-name (baml-enum-name def)))
                 defined-symbols)))

        (baml-client-def
         (register-baml-client def))))

    (nreverse defined-symbols)))

(defun import-baml-string (content &key (eval-p t))
  "Import BAML definitions from a string."
  (let ((definitions (parse-baml-content content))
        (defined-symbols nil))

    (dolist (def definitions)
      (etypecase def
        (baml-class
         (let ((skel-class (baml-class->skel-class def)))
           (when eval-p
             (eval skel-class))
           (push (intern (lisp-symbol-name (baml-class-name def)))
                 defined-symbols)))

        (baml-function
         (let ((skel-func (baml-function->skel-function def)))
           (when eval-p
             (eval skel-func))
           (push (intern (lisp-symbol-name (baml-function-name def)))
                 defined-symbols)))

        (baml-enum
         (let ((skel-enum (baml-enum->skel-enum def)))
           (when eval-p
             (eval skel-enum))
           (push (intern (lisp-symbol-name (baml-enum-name def)))
                 defined-symbols)))

        (baml-client-def
         (register-baml-client def))))

    (nreverse defined-symbols)))

;;; ============================================================================
;;; Directory Import
;;; ============================================================================

(defun find-baml-files (directory &key (recursive t))
  "Find all .baml files in a directory."
  (let ((pattern (if recursive "**/*.baml" "*.baml")))
    (directory (merge-pathnames pattern (pathname directory)))))

(defun import-baml-directory (path &key (recursive t) (eval-p t) (continue-on-error t))
  "Import all .baml files from a directory."
  (let ((files (find-baml-files path :recursive recursive))
        (results nil)
        (errors nil))

    (dolist (file files)
      (handler-case
          (let ((symbols (import-baml-file file :eval-p eval-p)))
            (push (cons file symbols) results))
        (baml-error (e)
          (if continue-on-error
              (progn
                (push (cons file e) errors)
                (warn "Failed to parse ~A: ~A" file e))
              (error e)))))

    (values (nreverse results)
            (nreverse errors))))

;;; ============================================================================
;;; Inspection Utilities
;;; ============================================================================

(defun preview-baml-import (path)
  "Preview what would be imported from a BAML file without evaluating."
  (let* ((content (read-file-content path))
         (definitions (parse-baml-content content))
         (classes nil)
         (functions nil)
         (enums nil)
         (clients nil))

    (dolist (def definitions)
      (etypecase def
        (baml-class (push def classes))
        (baml-function (push def functions))
        (baml-enum (push def enums))
        (baml-client-def (push def clients))))

    `((:classes . ,(nreverse classes))
      (:functions . ,(nreverse functions))
      (:enums . ,(nreverse enums))
      (:clients . ,(nreverse clients)))))

(defun baml-file-info (path)
  "Get summary information about a BAML file."
  (let ((preview (preview-baml-import path)))
    (list :path path
          :class-count (length (cdr (assoc :classes preview)))
          :class-names (mapcar #'baml-class-name (cdr (assoc :classes preview)))
          :function-count (length (cdr (assoc :functions preview)))
          :function-names (mapcar #'baml-function-name (cdr (assoc :functions preview)))
          :enum-count (length (cdr (assoc :enums preview)))
          :enum-names (mapcar #'baml-enum-name (cdr (assoc :enums preview)))
          :client-count (length (cdr (assoc :clients preview)))
          :client-names (mapcar #'baml-client-def-name (cdr (assoc :clients preview))))))
