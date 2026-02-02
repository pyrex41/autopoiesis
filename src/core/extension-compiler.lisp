;;;; extension-compiler.lisp - Agent-written code compilation
;;;;
;;;; Enables agents to write and install new code safely.
;;;; Extensions are validated before compilation.

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Extension Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass extension ()
  ((name :initarg :name
         :accessor extension-name
         :documentation "Unique name for this extension")
   (source :initarg :source
           :accessor extension-source
           :documentation "S-expression source code")
   (compiled :initarg :compiled
             :accessor extension-compiled
             :initform nil
             :documentation "Compiled form")
   (author :initarg :author
           :accessor extension-author
           :initform nil
           :documentation "Agent that created this extension")
   (created :initarg :created
            :accessor extension-created
            :initform (get-universal-time))
   (dependencies :initarg :dependencies
                 :accessor extension-dependencies
                 :initform nil
                 :documentation "Other extensions this depends on")
   (provides :initarg :provides
             :accessor extension-provides
             :initform nil
             :documentation "Capabilities this extension provides")
   (sandbox-level :initarg :sandbox-level
                  :accessor extension-sandbox-level
                  :initform :strict
                  :documentation ":strict, :moderate, or :trusted"))
  (:documentation "An agent-written extension"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *sandbox-allowed-symbols*
  '(;; Core Lisp (safe subset)
    lambda let let* if cond case when unless
    progn prog1 prog2 block return-from
    and or not
    car cdr cons list list* append reverse
    first second third fourth fifth rest last nth
    length elt subseq
    mapcar mapc mapcan remove remove-if remove-if-not
    find find-if find-if-not position member assoc
    + - * / mod floor ceiling round truncate
    = < > <= >= /= min max abs
    eq eql equal equalp
    null atom listp consp numberp stringp symbolp functionp
    format prin1-to-string princ-to-string
    string string= string< string> concatenate
    coerce type-of typep
    values multiple-value-bind
    funcall apply
    ;; Safe utilities
    identity constantly complement)
  "Symbols allowed in sandboxed agent code.")

(defparameter *sandbox-forbidden-patterns*
  '((eval . "Direct eval is forbidden")
    (compile . "Direct compile is forbidden")
    (load . "Loading files is forbidden")
    (delete-file . "File deletion is forbidden")
    (rename-file . "File renaming is forbidden")
    (open . "Direct file access is forbidden")
    (run-program . "External programs are forbidden")
    (sb-ext:run-program . "External programs are forbidden")
    (uiop:run-program . "External programs are forbidden")
    (make-instance . "Direct instance creation requires approval"))
  "Patterns forbidden in agent code, with explanations.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-extension-source (source)
  "Validate that SOURCE is safe to compile.
   Returns (values valid-p errors).
   Only checks symbols in operator position (car of lists) against allowed list.
   Variable names and lambda parameters are not restricted."
  (let ((errors nil))
    (labels ((check-operator (sym)
               "Check if SYM is an allowed operator."
               (unless (or (member sym *sandbox-allowed-symbols*)
                           (keywordp sym)
                           (null (symbol-package sym))
                           (eql (symbol-package sym) (find-package :keyword)))
                 (push (format nil "Operator ~a is not in allowed list" sym)
                       errors)))
             (check-form (form)
               (when (consp form)
                 (let ((head (car form)))
                   ;; Check forbidden patterns
                   (dolist (forbidden *sandbox-forbidden-patterns*)
                     (when (and (symbolp head)
                                (eq head (car forbidden)))
                       (push (cdr forbidden) errors)))
                   ;; Check if head is an allowed operator (only if symbol)
                   (when (symbolp head)
                     (check-operator head))
                   ;; Recurse into subforms (skip lambda parameter lists)
                   (cond
                     ;; For lambda, skip the param list
                     ((eq head 'lambda)
                      (when (cddr form)
                        (dolist (body-form (cddr form))
                          (check-form body-form))))
                     ;; For let/let*, skip bindings' variable names
                     ((member head '(let let*))
                      (when (cdr form)
                        (dolist (binding (cadr form))
                          (when (consp binding)
                            (check-form (cadr binding))))
                        (dolist (body-form (cddr form))
                          (check-form body-form))))
                     ;; Otherwise recurse into all subforms
                     (t
                      (dolist (subform (cdr form))
                        (check-form subform))))))))
      (check-form source)
      (values (null errors) (nreverse errors)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Compilation
;;; ═══════════════════════════════════════════════════════════════════

(defun compile-extension (name source &key author dependencies sandbox-level)
  "Compile SOURCE into an extension.
   Validates safety before compilation."
  (let ((level (or sandbox-level :strict)))
    ;; Validate if sandboxed
    (when (member level '(:strict :moderate))
      (multiple-value-bind (valid errors)
          (validate-extension-source source)
        (unless valid
          (error 'validation-error
                 :errors errors))))

    ;; Create extension
    (let ((extension (make-instance 'extension
                                    :name name
                                    :source source
                                    :author author
                                    :dependencies dependencies
                                    :sandbox-level level)))
      ;; Compile the source
      (setf (extension-compiled extension)
            (compile nil `(lambda () ,source)))
      extension)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Extension Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *extension-registry* (make-hash-table :test 'equal)
  "Global registry of installed extensions.")

(defun install-extension (extension &key (registry *extension-registry*))
  "Install EXTENSION into REGISTRY, making it available."
  ;; Check dependencies
  (dolist (dep (extension-dependencies extension))
    (unless (gethash dep registry)
      (error 'autopoiesis-error
             :message (format nil "Missing dependency: ~a" dep))))

  ;; Install
  (setf (gethash (extension-name extension) registry) extension)
  extension)

(defun uninstall-extension (name &key (registry *extension-registry*))
  "Remove extension NAME from REGISTRY."
  (remhash name registry))

(defun find-extension (name &key (registry *extension-registry*))
  "Find extension by NAME."
  (gethash name registry))

(defun list-extensions (&key (registry *extension-registry*))
  "List all installed extensions."
  (loop for ext being the hash-values of registry
        collect ext))

(defun execute-extension (extension &rest args)
  "Execute a compiled extension with ARGS."
  (when (extension-compiled extension)
    (apply (extension-compiled extension) args)))
