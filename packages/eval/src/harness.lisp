;;;; harness.lisp - Eval harness protocol and registry
;;;;
;;;; The eval-harness is the key abstraction: it normalizes any execution shape
;;;; (single provider invoke, ralph loop, team campaign, shell command) into a
;;;; uniform "run scenario, get result plist" interface.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Harness Protocol
;;; ===================================================================

(defclass eval-harness ()
  ((name :initarg :name
         :accessor harness-name
         :type string
         :documentation "Unique name for this harness (e.g., \"claude-code\", \"ralph-opus\")")
   (description :initarg :description
                :accessor harness-description
                :initform ""
                :type string
                :documentation "Human-readable description")
   (config :initarg :config
           :accessor harness-config
           :initform nil
           :documentation "Harness-specific configuration plist"))
  (:documentation "Abstract eval harness. Subclass and implement harness-run-scenario."))

(defgeneric harness-run-scenario (harness scenario-plist &key timeout)
  (:documentation "Execute SCENARIO-PLIST on this harness.
   SCENARIO-PLIST is the full entity-state of an eval-scenario.

   Returns a result plist with keys:
     :output      - text output (string)
     :tool-calls  - list of tool call plists
     :duration    - wall-clock seconds (number)
     :cost        - USD cost (number or nil)
     :turns       - agentic turns (integer or nil)
     :exit-code   - process exit code (integer or nil)
     :passed      - :pass/:fail/:error/:skip based on verifier (keyword or nil)
     :metadata    - harness-specific extra data (plist)"))

(defgeneric harness-to-config-plist (harness)
  (:documentation "Serialize harness configuration to a plist for storage.")
  (:method ((harness eval-harness))
    (list :type (string-downcase (symbol-name (type-of harness)))
          :name (harness-name harness)
          :config (harness-config harness))))

(defmethod print-object ((harness eval-harness) stream)
  (print-unreadable-object (harness stream :type t)
    (format stream "~a" (harness-name harness))))

;;; ===================================================================
;;; Harness Registry
;;; ===================================================================

(defvar *harness-registry* (make-hash-table :test 'equal)
  "Registry of eval harnesses keyed by name.")

(defvar *harness-registry-lock* (bordeaux-threads:make-lock "harness-registry")
  "Lock for thread-safe harness registry access.")

(defun register-harness (harness)
  "Register an eval harness. Returns the harness."
  (bordeaux-threads:with-lock-held (*harness-registry-lock*)
    (setf (gethash (harness-name harness) *harness-registry*) harness))
  harness)

(defun find-harness (name)
  "Find a registered harness by name. Returns nil if not found."
  (bordeaux-threads:with-lock-held (*harness-registry-lock*)
    (gethash name *harness-registry*)))

(defun list-harnesses ()
  "Return a list of all registered harnesses."
  (bordeaux-threads:with-lock-held (*harness-registry-lock*)
    (loop for h being the hash-values of *harness-registry* collect h)))

(defun clear-harness-registry ()
  "Clear all registered harnesses."
  (bordeaux-threads:with-lock-held (*harness-registry-lock*)
    (clrhash *harness-registry*)))
