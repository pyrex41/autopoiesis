;;;; system.lisp - defsystem macro for declaration-filtered reactive dispatch
;;;;
;;;; Systems declare what entity types and attributes they watch.
;;;; The framework builds a dispatch table and only invokes matching systems.

(in-package #:autopoiesis.substrate)

(defvar *system-registry* (make-hash-table :test 'eq)
  "Registry of substrate systems: name -> system-descriptor")

(defvar *dispatch-table* (make-hash-table :test 'eql)
  "Dispatch index: attribute-id -> list of system-descriptors.
   Built from system :watches declarations.")

(defclass system-descriptor ()
  ((name :initarg :name :reader system-name)
   (entity-type :initarg :entity-type :reader system-entity-type
                :documentation "Keyword for the entity type this system watches, or nil for all")
   (watches :initarg :watches :reader system-watches
            :documentation "List of attribute keywords this system cares about")
   (access :initarg :access :reader system-access
           :documentation ":read-only or :read-write")
   (after :initarg :after :reader system-after :initform nil
          :documentation "List of system names this system must fire after")
   (before :initarg :before :reader system-before :initform nil
           :documentation "List of system names this system must fire before")
   (handler :initarg :handler :reader system-handler
            :documentation "Function (entity datoms tx-id) called on matching changes"))
  (:documentation "A reactive system that processes entity changes"))

(defvar *system-dispatch-hook-installed* nil
  "Whether the global system dispatch hook has been installed.")

(defun reset-system-state ()
  "Reset all system state. For testing only."
  (clrhash *system-registry*)
  (clrhash *dispatch-table*)
  (setf *system-dispatch-hook-installed* nil))

(define-condition circular-system-dependency (substrate-error)
  ((cycle :initarg :cycle :reader circular-dependency-cycle))
  (:report (lambda (c s) (format s "Circular system dependency: ~{~A~^ -> ~}"
                                 (circular-dependency-cycle c))))
  (:documentation "Signaled when defsystem dependencies form a cycle."))

(defun topological-sort-systems (systems)
  "Sort SYSTEMS (list of system-descriptors) respecting :after/:before constraints.
   Returns a sorted list. Signals CIRCULAR-SYSTEM-DEPENDENCY on cycles."
  (let ((name->sys (make-hash-table :test 'eq))
        (edges (make-hash-table :test 'eq))     ; name -> list of names that must come after
        (in-degree (make-hash-table :test 'eq))
        (result nil))
    ;; Index systems by name
    (dolist (sys systems)
      (setf (gethash (system-name sys) name->sys) sys)
      (setf (gethash (system-name sys) in-degree) 0))
    ;; Build directed edges: A -> B means A fires before B
    (dolist (sys systems)
      (let ((name (system-name sys)))
        ;; :after means this system fires after each listed system
        (dolist (dep (system-after sys))
          (when (gethash dep name->sys)
            (push name (gethash dep edges))
            (incf (gethash name in-degree))))
        ;; :before means this system fires before each listed system
        (dolist (dep (system-before sys))
          (when (gethash dep name->sys)
            (push dep (gethash name edges))
            (incf (gethash dep in-degree))))))
    ;; Kahn's algorithm
    (let ((queue nil))
      ;; Seed queue with zero-in-degree nodes
      (maphash (lambda (name deg)
                 (when (zerop deg) (push name queue)))
               in-degree)
      (loop while queue do
        (let* ((name (pop queue))
               (sys (gethash name name->sys)))
          (push sys result)
          (dolist (next (gethash name edges))
            (decf (gethash next in-degree))
            (when (zerop (gethash next in-degree))
              (push next queue))))))
    ;; Check for cycles
    (when (/= (length result) (length systems))
      (let ((remaining (remove-if (lambda (sys)
                                    (member sys result))
                                  systems)))
        (error 'circular-system-dependency
               :cycle (mapcar #'system-name remaining))))
    (nreverse result)))

(defun ensure-system-dispatch-hook ()
  "Install the system dispatch hook (once). Dispatches to systems
   via the dispatch table, not by scanning all systems."
  (unless *system-dispatch-hook-installed*
    (when *store*
      (register-hook *store* :system-dispatch
        (lambda (datoms tx-id)
          (let ((invoked (make-hash-table :test 'eq)))
            ;; Phase 1: narrow to affected systems via dispatch table
            (dolist (d datoms)
              (dolist (sys (gethash (d-attribute d) *dispatch-table*))
                (unless (gethash sys invoked)
                  ;; Check entity type matches (if system has a type filter)
                  (let ((eid (d-entity d)))
                    (when (or (null (system-entity-type sys))
                              (eq (entity-attr eid :entity/type)
                                  (system-entity-type sys)))
                      (setf (gethash sys invoked) t))))))
            ;; Phase 2: topological sort affected systems, then invoke in order
            (let ((affected nil))
              (maphash (lambda (sys _)
                         (declare (ignore _))
                         (push sys affected))
                       invoked)
              (setf affected (topological-sort-systems affected))
              (dolist (sys affected)
                (handler-case
                    (let ((entity-type (system-entity-type sys)))
                      (dolist (d datoms)
                        (when (member (d-attribute d)
                                      (mapcar (lambda (w)
                                                (if (integerp w) w
                                                    (gethash w *intern-table*)))
                                              (system-watches sys)))
                          (let ((entity (if entity-type
                                            (make-typed-entity entity-type (d-entity d))
                                            nil)))
                            (funcall (system-handler sys) entity datoms tx-id)))))
                  (error (e)
                    (warn "System ~A error: ~A" (system-name sys) e))))))))
      (setf *system-dispatch-hook-installed* t))))

(defmacro defsystem (name (&key entity-type watches (access :read-only) after before) &body body)
  "Define a declaration-filtered reactive system.
   Declares what entity type and attributes this system watches.
   The framework builds a dispatch table and only matching systems fire.

   :AFTER - list of system names this system must fire after.
   :BEFORE - list of system names this system must fire before.

   Example:
     (defsystem :derived-status
       (:entity-type :agent
        :watches (:agent/error-count :agent/uptime)
        :after (:cache-invalidation)
        :access :read-only)
       (format t \"Status changed: ~A~%\" entity))"
  `(progn
     (let ((descriptor (make-instance 'system-descriptor
                                      :name ',name
                                      :entity-type ,entity-type
                                      :watches ',watches
                                      :access ,access
                                      :after ',after
                                      :before ',before
                                      :handler (lambda (entity datoms tx-id)
                                                 (declare (ignorable entity datoms tx-id))
                                                 ,@body))))
       ;; Register in system registry
       (setf (gethash ',name *system-registry*) descriptor)
       ;; Build dispatch table entries
       (dolist (attr ',watches)
         (let ((aid (intern-id attr :width :attribute)))
           (push descriptor (gethash aid *dispatch-table*))))
       ;; Install the dispatch hook if needed
       (ensure-system-dispatch-hook)
       ',name)))
