;;;; entity-type.lisp - define-entity-type macro and typed entity access
;;;;
;;;; Generates: schema metadata stored as datoms, CLOS class with MOP
;;;; slot-unbound loading from entity cache. Pattern from defcapability
;;;; at src/agent/capability.lisp.

(in-package #:autopoiesis.substrate)

(defvar *entity-type-registry* (make-hash-table :test 'eq)
  "Registry of declared entity types: keyword -> entity-type-descriptor")

(defclass entity-type-descriptor ()
  ((name :initarg :name :reader entity-type-name)
   (attributes :initarg :attributes :reader entity-type-attributes
               :documentation "List of (attr-keyword . options)")
   (class-name :initarg :class-name :reader entity-type-class-name))
  (:documentation "Metadata about a declared entity type"))

(defun slot-name-to-attribute (type-name slot-name)
  "Convert a slot name to its corresponding attribute keyword.
   E.g., for type :turn, slot ROLE -> :turn/role"
  (intern (format nil "~A/~A" (string-upcase type-name) (string-upcase slot-name))
          :keyword))

(defun attribute-to-slot-name (type-name attribute)
  "Convert an attribute keyword to its corresponding slot name.
   E.g., for type :turn, :turn/role -> ROLE"
  (let* ((attr-str (symbol-name attribute))
         (prefix (format nil "~A/" (string-upcase type-name)))
         (prefix-len (length prefix)))
    (when (and (>= (length attr-str) prefix-len)
               (string= prefix (subseq attr-str 0 prefix-len)))
      (intern (subseq attr-str prefix-len)
              (find-package :autopoiesis.substrate)))))

(defmacro define-entity-type (name &body attribute-specs)
  "Define a substrate entity type. Generates:
   1. Schema metadata stored in the type registry
   2. A CLOS class with MOP slot-unbound loading from entity cache

   Example:
     (define-entity-type :turn
       (:turn/role       :type keyword  :required t)
       (:turn/content-hash :type string :required t)
       (:turn/parent     :type (or null integer)))

   After this, you can:
     (let ((turn (make-typed-entity :turn eid)))
       (slot-value turn 'role)  ; slot-unbound -> loads from entity-attr"
  (let* ((type-str (string-upcase (symbol-name name)))
         (class-sym (intern (format nil "~A-ENTITY" type-str)))
         (prefix (format nil "~A/" type-str))
         (slot-defs
           (loop for spec in attribute-specs
                 for attr = (car spec)
                 for attr-str = (symbol-name attr)
                 for slash-pos = (position #\/ attr-str)
                 for slot-name = (if slash-pos
                                     (intern (subseq attr-str (1+ slash-pos))
                                             (find-package :autopoiesis.substrate))
                                     (intern attr-str (find-package :autopoiesis.substrate)))
                 collect (list slot-name attr))))
    `(progn
       ;; Generate CLOS class
       (defclass ,class-sym ()
         ((entity-id :initarg :entity-id :reader entity-id
                     :documentation "Substrate entity ID for this typed entity")
          ,@(loop for (slot-name attr) in slot-defs
                  collect `(,slot-name
                            :initarg ,(intern (symbol-name slot-name) :keyword))))
         (:documentation ,(format nil "Typed entity class for ~A" name)))

       ;; MOP slot-unbound: cache miss -> load from substrate
       (defmethod slot-unbound (class (entity ,class-sym) (slot-name symbol))
         (declare (ignore class))
         ;; Try to find the attribute for this slot
         (let* ((attr-keyword (slot-name-to-attribute ,name slot-name))
                (value (entity-attr (entity-id entity) attr-keyword)))
           (when value
             (setf (slot-value entity slot-name) value))
           value))

       ;; Register in type registry
       (setf (gethash ,name *entity-type-registry*)
             (make-instance 'entity-type-descriptor
                            :name ,name
                            :attributes ',attribute-specs
                            :class-name ',class-sym))

       ',name)))

(defun make-typed-entity (type-keyword entity-id)
  "Create a typed entity wrapper. Slot access lazily loads from substrate."
  (let ((descriptor (gethash type-keyword *entity-type-registry*)))
    (unless descriptor
      (error 'unknown-entity-type
             :entity-id entity-id
             :attributes (list type-keyword)
             :message (format nil "Unknown entity type: ~A" type-keyword)))
    (make-instance (entity-type-class-name descriptor)
                   :entity-id entity-id)))
