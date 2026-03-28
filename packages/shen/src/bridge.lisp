;;;; bridge.lisp - CL↔Shen interface
;;;;
;;;; Thread-safe bridge for evaluating Shen expressions and running
;;;; Prolog queries. Shen is loaded lazily at runtime via shen-cl's
;;;; bootstrap mechanism. All Shen calls are serialized through
;;;; *shen-lock* because Shen uses global mutable state.

(in-package #:autopoiesis.shen)

;;; ===================================================================
;;; State
;;; ===================================================================

(defvar *shen-lock* (bt:make-lock "shen")
  "Lock serializing all Shen calls (Shen uses global mutable state).")

(defvar *shen-loaded-p* nil
  "T when the Shen kernel has been loaded into this image.")

(defvar *shen-install-path* nil
  "Path to shen-cl's install.lsp. Auto-detected or set manually.")

;;; ===================================================================
;;; Availability Check
;;; ===================================================================

(defun shen-available-p ()
  "Return T if Shen is loaded and ready for queries.
   Non-blocking, no side effects."
  (and *shen-loaded-p*
       (find-package :shen)
       t))

;;; ===================================================================
;;; Loading
;;; ===================================================================

(defun find-shen-install ()
  "Try to locate shen-cl's install.lsp in common locations.
   Returns pathname or NIL."
  (let ((candidates (list
                     ;; Relative to AP repo
                     (merge-pathnames "vendor/shen-cl/install.lsp"
                                      (asdf:system-source-directory :autopoiesis))
                     ;; Home directory
                     (merge-pathnames "shen-cl/install.lsp"
                                      (user-homedir-pathname))
                     ;; Quicklisp local-projects
                     (merge-pathnames "quicklisp/local-projects/shen-cl/install.lsp"
                                      (user-homedir-pathname))
                     ;; System-wide
                     #P"/usr/local/share/shen-cl/install.lsp"
                     #P"/opt/shen-cl/install.lsp")))
    (find-if #'probe-file candidates)))

(defun ensure-shen-loaded (&key path)
  "Load the Shen kernel if not already loaded. Idempotent.
   PATH overrides auto-detection of install.lsp location.
   Returns T on success, signals error on failure."
  (when *shen-loaded-p*
    (return-from ensure-shen-loaded t))
  (bt:with-lock-held (*shen-lock*)
    ;; Double-check under lock
    (when *shen-loaded-p*
      (return-from ensure-shen-loaded t))
    (let ((install-path (or path
                            *shen-install-path*
                            (find-shen-install))))
      (unless install-path
        (error "Cannot find shen-cl install.lsp. ~
                Set autopoiesis.shen:*shen-install-path* or pass :path, ~
                or install shen-cl to ~/shen-cl/ or vendor/shen-cl/."))
      (unless (probe-file install-path)
        (error "Shen install.lsp not found at ~A" install-path))
      (handler-case
          (progn
            (load install-path :verbose nil :print nil)
            (unless (find-package :shen)
              (error "Shen loaded but :SHEN package not found"))
            (setf *shen-loaded-p* t)
            (setf *shen-install-path* install-path)
            t)
        (error (e)
          (error "Failed to load Shen from ~A: ~A" install-path e))))))

;;; ===================================================================
;;; Evaluation
;;; ===================================================================

(defun shen-eval (form)
  "Evaluate a Shen expression. Thread-safe.
   FORM is an S-expression in Shen syntax.
   Returns the Shen result converted to CL values.
   Signals error if Shen is not loaded."
  (unless (shen-available-p)
    (error "Shen is not loaded. Call (ensure-shen-loaded) first."))
  (bt:with-lock-held (*shen-lock*)
    (let* ((eval-fn (find-symbol "EVAL-KL" :shen))
           (result (when (and eval-fn (fboundp eval-fn))
                     (funcall eval-fn form))))
      (shen-to-cl result))))

(defun shen-query (query-form)
  "Run a Shen Prolog query. Thread-safe.
   QUERY-FORM is a list that will be wrapped in (prolog? ... (return ...)).
   Returns the query result or NIL if the query fails.
   Signals error if Shen is not loaded."
  (unless (shen-available-p)
    (error "Shen is not loaded. Call (ensure-shen-loaded) first."))
  (bt:with-lock-held (*shen-lock*)
    ;; Build: (prolog? <query-form> (return Result))
    (let* ((wrapped `(prolog? ,@query-form (return Result)))
           (eval-fn (find-symbol "EVAL-KL" :shen))
           (result (when (and eval-fn (fboundp eval-fn))
                     (handler-case
                         (funcall eval-fn wrapped)
                       (error () nil)))))
      (shen-to-cl result))))

;;; ===================================================================
;;; Value Conversion
;;; ===================================================================

(defun shen-to-cl (value)
  "Convert a Shen value to CL conventions.
   Shen's 'true' → T, 'false' → NIL."
  (cond
    ((and (symbolp value) (string= (symbol-name value) "true")) t)
    ((and (symbolp value) (string= (symbol-name value) "false")) nil)
    (t value)))

(defun cl-to-shen (value)
  "Convert a CL value to Shen conventions.
   T → 'true', NIL → 'false'."
  (cond
    ((eq value t) (intern "true" :shen))
    ((null value) (intern "false" :shen))
    (t value)))
