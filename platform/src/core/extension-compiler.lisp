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
   (id :initarg :id
       :accessor extension-id
       :initform nil
       :documentation "Unique identifier (auto-generated if not provided)")
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
                  :documentation ":strict, :moderate, or :trusted")
   (invocations :initarg :invocations
                :accessor extension-invocations
                :initform 0
                :documentation "Number of times this extension has been invoked")
   (errors :initarg :errors
           :accessor extension-errors
           :initform 0
           :documentation "Number of errors during invocation")
   (status :initarg :status
           :accessor extension-status
           :initform :pending
           :documentation ":pending, :validated, :rejected, or :promoted"))
  (:documentation "An agent-written extension"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *allowed-packages*
  '("COMMON-LISP" "KEYWORD" "AUTOPOIESIS.CORE" "AUTOPOIESIS.AGENT" "AUTOPOIESIS.SKEL" "ALEXANDRIA")
  "Package names agents are allowed to reference symbols from.
   Symbols from other packages will be rejected during validation.")

(defparameter *forbidden-symbols*
  '(;; Evaluation and compilation
    eval compile load require
    ;; File system operations
    open close delete-file rename-file probe-file
    with-open-file directory ensure-directories-exist
    ;; External processes
    run-program
    ;; Definition forms (agents shouldn't define global state)
    setf setq defvar defparameter defconstant
    defclass defmethod defgeneric defstruct
    defmacro define-compiler-macro
    ;; Package manipulation
    intern export import shadow shadowing-import
    use-package unuse-package make-package delete-package
    ;; Reader manipulation
    set-macro-character set-dispatch-macro-character
    ;; Dangerous introspection
    symbol-function fdefinition
    ;; Implementation-specific dangerous operations
    sb-ext:run-program sb-sys:foreign-symbol-address
    uiop:run-program uiop:launch-program)
  "Symbols agents are NOT allowed to use.
   These represent operations that could compromise system security.")

(defparameter *allowed-special-forms*
  '(;; Control flow
    if when unless cond case typecase etypecase
    ;; Binding forms
    let let* flet labels lambda
    ;; Sequencing
    progn prog1 prog2 block return-from
    ;; Iteration
    loop do do* dolist dotimes
    ;; Multiple values
    multiple-value-bind multiple-value-call values
    ;; Type declarations
    the declare locally
    ;; Quoting
    quote function
    ;; Conditionals
    and or)
  "Special forms and macros agents CAN use.
   This is a whitelist of safe control structures.")

(defparameter *sandbox-allowed-symbols*
  '(;; Core Lisp (safe subset)
    lambda let let* if cond case when unless
    progn prog1 prog2 block return-from
    and or not
    car cdr cons list list* append reverse
    first second third fourth fifth rest last nth nthcdr
    length elt subseq copy-seq
    mapcar mapc mapcan maplist mapl mapcon
    reduce
    remove remove-if remove-if-not delete delete-if delete-if-not
    find find-if find-if-not position position-if position-if-not
    member member-if member-if-not
    assoc assoc-if assoc-if-not rassoc rassoc-if rassoc-if-not
    count count-if count-if-not
    sort stable-sort merge
    ;; Arithmetic
    + - * / mod rem floor ceiling round truncate
    = < > <= >= /= min max abs signum
    1+ 1- incf decf
    expt sqrt log exp sin cos tan
    gcd lcm
    ;; Comparison
    eq eql equal equalp
    ;; Type predicates
    null atom listp consp numberp integerp floatp rationalp
    stringp symbolp functionp characterp arrayp vectorp
    hash-table-p packagep
    ;; String operations
    format prin1-to-string princ-to-string write-to-string
    string string= string/= string< string> string<= string>=
    string-equal string-not-equal string-lessp string-greaterp
    string-upcase string-downcase string-capitalize
    string-trim string-left-trim string-right-trim
    concatenate
    char char-code code-char
    ;; Type conversion
    coerce type-of typep subtypep
    ;; Multiple values
    values multiple-value-bind multiple-value-list
    ;; Function application
    funcall apply
    ;; Safe utilities
    identity constantly complement
    ;; Sequence operations
    every some notevery notany
    ;; Association lists
    acons pairlis
    ;; Property lists
    getf get-properties
    ;; Hash tables (read-only operations)
    gethash hash-table-count
    ;; Safe iteration
    loop do do* dolist dotimes
    ;; Error handling (limited)
    error warn
    ;; Misc safe operations
    zerop plusp minusp oddp evenp
    boundp fboundp
    ;; Constants
    t nil)
  "Symbols allowed in sandboxed agent code.
   This is the complete whitelist for :strict sandbox level.")

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
    (make-instance . "Direct instance creation requires approval")
    (setf . "Global mutation is forbidden")
    (setq . "Global mutation is forbidden")
    (defvar . "Global definitions are forbidden")
    (defparameter . "Global definitions are forbidden")
    (defun . "Global function definitions are forbidden")
    (defmacro . "Macro definitions are forbidden")
    (defclass . "Class definitions are forbidden")
    (defmethod . "Method definitions are forbidden"))
  "Patterns forbidden in agent code, with explanations.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun package-allowed-p (pkg)
  "Check if PKG is in the allowed packages list."
  (or (null pkg)
      (member (package-name pkg) *allowed-packages* :test #'string=)))

(defun symbol-forbidden-p (sym)
  "Check if SYM is in the forbidden symbols list."
  (member sym *forbidden-symbols* :test #'eq))

(defun validate-extension-code (code)
  "Validate agent-written code for safety.
   
   This is the core code walker that checks CODE for dangerous operations.
   
   Arguments:
     code - S-expression code to validate
   
   Returns: (values valid-p errors)
     valid-p - T if code passes validation
     errors  - List of validation error strings
   
   The walker checks:
   - Symbols in operator position against *sandbox-allowed-symbols* and *allowed-special-forms*
   - Operators against *forbidden-symbols*
   - Package restrictions from *allowed-packages*
   - Handles special forms correctly (lambda params, let bindings, flet/labels)
   - Quoted forms are treated as data and not recursively checked"
  (validate-extension-source code :sandbox-level :strict))

(defun validate-extension-source (source &key (sandbox-level :strict))
  "Validate that SOURCE is safe to compile.
   
   Arguments:
     source        - S-expression code to validate
     sandbox-level - :strict (default), :moderate, or :trusted
   
   Returns (values valid-p errors).
   
   Validation checks:
   1. Symbols in operator position must be in *sandbox-allowed-symbols* or *allowed-special-forms*
   2. Operators must come from *allowed-packages*
   3. No symbol from *forbidden-symbols* may appear in operator position
   4. Variable names and lambda parameters are NOT restricted
   5. Symbols in value position (variable references) are NOT restricted
   6. Locally defined functions (via flet/labels) are allowed as operators
   
   For :moderate sandbox-level, package restrictions are relaxed.
   For :trusted level, no validation is performed."
  (when (eq sandbox-level :trusted)
    (return-from validate-extension-source (values t nil)))
  
  (let ((errors nil)
        (local-functions nil))  ; Track locally defined function names
    (labels ((check-package (sym context)
               "Check if SYM comes from an allowed package (for operators only)."
               (when (and (symbolp sym)
                          (symbol-package sym)
                          (not (keywordp sym))
                          (not (member sym local-functions :test #'string=
                                       :key #'symbol-name))
                          (eq sandbox-level :strict))
                 (unless (package-allowed-p (symbol-package sym))
                   (push (format nil "Operator ~s from forbidden package ~a (~a)"
                                 sym (package-name (symbol-package sym)) context)
                         errors))))
             
             (check-forbidden-operator (sym)
               "Check if SYM is in the forbidden list (for operators only)."
               (when (and (symbolp sym)
                          (symbol-forbidden-p sym))
                 (push (format nil "Forbidden operator ~s" sym)
                       errors)))
             
             (check-operator (sym)
               "Check if SYM is an allowed operator."
               (unless (or (member sym *sandbox-allowed-symbols*)
                           (member sym *allowed-special-forms*)
                           (keywordp sym)
                           (null (symbol-package sym))
                           ;; Allow locally defined functions
                           (member sym local-functions :test #'string=
                                   :key #'symbol-name))
                 (push (format nil "Operator ~s is not in allowed list" sym)
                       errors)))
             
             (extract-local-fn-names (fn-defs)
               "Extract function names from flet/labels definitions."
               (loop for fn-def in fn-defs
                     when (and (consp fn-def) (symbolp (car fn-def)))
                     collect (car fn-def)))
             
             (check-form (form context)
               "Recursively check a form for safety.
                Only checks operators (car of lists), not variable references."
               (cond
                 ;; Nil is always safe
                 ((null form) nil)
                 
                 ;; Symbols in value position are NOT checked
                 ;; (they're variable references, which are unrestricted)
                 ((symbolp form) nil)
                 
                 ;; Non-list atoms (numbers, strings, etc.) are safe
                 ((atom form) nil)
                 
                 ;; List forms - check the operator
                 ((consp form)
                  (let ((head (car form)))
                    ;; Check forbidden patterns first
                    (dolist (forbidden *sandbox-forbidden-patterns*)
                      (when (and (symbolp head)
                                 (eq head (car forbidden)))
                        (push (cdr forbidden) errors)))
                    
                    ;; Check the operator (only for symbols)
                    (when (symbolp head)
                      (check-forbidden-operator head)
                      (check-package head "operator position")
                      (check-operator head))
                    
                    ;; Recurse into subforms, handling special cases
                    (cond
                      ;; Lambda: skip parameter list, check body
                      ((eq head 'lambda)
                       (when (cddr form)
                         (dolist (body-form (cddr form))
                           (check-form body-form "lambda body"))))
                      
                      ;; Let/let*: skip binding variable names, check init forms and body
                      ((member head '(let let*))
                       (when (cdr form)
                         (dolist (binding (cadr form))
                           (when (consp binding)
                             (check-form (cadr binding) "let binding")))
                         (dolist (body-form (cddr form))
                           (check-form body-form "let body"))))
                      
                      ;; Flet/labels: track local function names, check bodies
                      ((member head '(flet labels))
                       (when (cdr form)
                         ;; Add local function names to scope
                         (let ((new-fns (extract-local-fn-names (cadr form))))
                           (setf local-functions (append new-fns local-functions))
                           ;; Check function bodies
                           (dolist (fn-def (cadr form))
                             (when (and (consp fn-def) (cddr fn-def))
                               (dolist (body-form (cddr fn-def))
                                 (check-form body-form "flet/labels body"))))
                           ;; Check outer body
                           (dolist (body-form (cddr form))
                             (check-form body-form "flet/labels outer body")))))
                      
                      ;; Quote: don't recurse into quoted forms (they're data)
                      ((eq head 'quote) nil)
                      
                      ;; Declare: don't recurse into declarations (they're not executable)
                      ((eq head 'declare) nil)
                      
                      ;; Function: check the function name as an operator reference
                      ((eq head 'function)
                       (when (and (cdr form) (symbolp (cadr form)))
                         (let ((fn-name (cadr form)))
                           ;; Allow local functions in #'fn-name
                           (unless (member fn-name local-functions :test #'string=
                                           :key #'symbol-name)
                             (check-forbidden-operator fn-name)
                             (check-package fn-name "function reference")))))
                      
                      ;; Loop: check non-keyword clauses
                      ((eq head 'loop)
                       (dolist (clause (cdr form))
                         (unless (or (keywordp clause) (symbolp clause))
                           (check-form clause "loop clause"))))
                      
                      ;; Default: recurse into all subforms
                      (t
                       (dolist (subform (cdr form))
                         (check-form subform "subform")))))))))
      
      (check-form source "top-level")
      (values (null errors) (nreverse errors)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Compilation
;;; ═══════════════════════════════════════════════════════════════════

(defun compile-extension (name source &key author dependencies sandbox-level)
  "Safely compile agent-written code into an extension.
   
   Arguments:
     name          - Unique name for the extension
     source        - S-expression source code to compile
     author        - Optional agent ID that created this extension
     dependencies  - Optional list of extension names this depends on
     sandbox-level - :strict (default), :moderate, or :trusted
   
   Returns: (values extension errors)
     extension - Compiled extension object, or NIL if validation/compilation failed
     errors    - List of error strings (empty if successful)
   
   The function validates the source code against sandbox rules before
   attempting compilation. If validation fails, returns NIL with the
   validation errors. If compilation fails, returns NIL with the
   compilation error. Only returns an extension if both validation
   and compilation succeed."
  (let ((level (or sandbox-level :strict)))
    ;; Validate if sandboxed
    (when (member level '(:strict :moderate))
      (multiple-value-bind (valid validation-errors)
          (validate-extension-source source :sandbox-level level)
        (unless valid
          (return-from compile-extension
            (values nil validation-errors)))))

    ;; Attempt compilation with error handling
    (handler-case
        (let* ((fn-code `(lambda () ,source))
               (compiled-fn (compile nil fn-code))
               (extension (make-instance 'extension
                                         :name name
                                         :source source
                                         :compiled compiled-fn
                                         :author author
                                         :dependencies dependencies
                                         :sandbox-level level)))
          (values extension nil))
      ;; Handle compilation errors
      (error (e)
        (values nil (list (format nil "Compilation error: ~a" e)))))))

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

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Extension Registration
;;; ═══════════════════════════════════════════════════════════════════

(defun register-extension (agent-id code &key name (registry *extension-registry*))
  "Register a new extension from an agent.
   
   This function validates the code, compiles it if valid, and registers
   it in the extension registry. The extension is assigned a unique ID
   and tracked for invocation statistics.
   
   Arguments:
     agent-id - ID of the agent creating this extension
     code     - S-expression source code to compile
     name     - Optional name for the extension (auto-generated if not provided)
     registry - Extension registry to use (defaults to *extension-registry*)
   
   Returns: (values extension errors)
     extension - The registered extension object, or NIL if validation failed
     errors    - List of validation/compilation error strings"
  (let* ((ext-name (or name (format nil "ext-~a" (make-uuid))))
         (ext-id (make-uuid)))
    ;; Validate the code
    (multiple-value-bind (valid-p validation-errors)
        (validate-extension-source code :sandbox-level :strict)
      (if (not valid-p)
          ;; Return nil with errors if validation failed
          (values nil validation-errors)
          ;; Try to compile
          (handler-case
              (let* ((fn-code `(lambda () ,code))
                     (compiled-fn (compile nil fn-code))
                     (extension (make-instance 'extension
                                               :name ext-name
                                               :id ext-id
                                               :source code
                                               :compiled compiled-fn
                                               :author agent-id
                                               :status :validated
                                               :sandbox-level :strict)))
                ;; Register in the registry
                (setf (gethash ext-id registry) extension)
                (values extension nil))
            ;; Handle compilation errors
            (error (e)
              (values nil (list (format nil "Compilation error: ~a" e)))))))))

(defun invoke-extension (extension-id &key (registry *extension-registry*) args)
  "Safely invoke a registered extension by ID.
   
   This function looks up the extension, checks its status, and invokes it
   if valid. It tracks invocation counts and errors, automatically disabling
   extensions that fail too often.
   
   Arguments:
     extension-id - The unique ID of the extension to invoke
     registry     - Extension registry to use (defaults to *extension-registry*)
     args         - Arguments to pass to the extension (as a list)
   
   Returns: The result of the extension, or signals an error if:
     - Extension not found
     - Extension is not validated
     - Extension execution fails
   
   Side effects:
     - Increments extension-invocations counter
     - Increments extension-errors counter on failure
     - Sets extension-status to :rejected if errors exceed threshold"
  (let ((ext (gethash extension-id registry)))
    (unless ext
      (error 'autopoiesis-error
             :message (format nil "Extension not found: ~a" extension-id)))
    
    (unless (eq (extension-status ext) :validated)
      (error 'autopoiesis-error
             :message (format nil "Extension ~a is not validated (status: ~a)"
                              extension-id (extension-status ext))))
    
    ;; Track invocation
    (incf (extension-invocations ext))
    
    ;; Execute with error handling
    (handler-case
        (if args
            (apply (extension-compiled ext) args)
            (funcall (extension-compiled ext)))
      (error (e)
        ;; Track error
        (incf (extension-errors ext))
        ;; Auto-disable if too many errors
        (when (> (extension-errors ext) 3)
          (setf (extension-status ext) :rejected))
        ;; Re-signal the error
        (error 'autopoiesis-error
               :message (format nil "Extension ~a execution error: ~a"
                                extension-id e))))))

(defun clear-extension-registry (&key (registry *extension-registry*))
  "Clear all extensions from the registry."
  (clrhash registry))
