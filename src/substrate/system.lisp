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
            ;; Phase 2: invoke affected systems
            (maphash (lambda (sys _)
                       (declare (ignore _))
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
                           (warn "System ~A error: ~A" (system-name sys) e))))
                     invoked))))
      (setf *system-dispatch-hook-installed* t))))

(defmacro defsystem (name (&key entity-type watches (access :read-only)) &body body)
  "Define a declaration-filtered reactive system.
   Declares what entity type and attributes this system watches.
   The framework builds a dispatch table and only matching systems fire.

   Example:
     (defsystem :restart-monitor
       (:entity-type :k8s/pod
        :watches (:k8s.pod/phase :k8s.pod/restarts)
        :access :read-only)
       (format t \"Pod changed: ~A~%\" entity))"
  `(progn
     (let ((descriptor (make-instance 'system-descriptor
                                      :name ',name
                                      :entity-type ,entity-type
                                      :watches ',watches
                                      :access ,access
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
