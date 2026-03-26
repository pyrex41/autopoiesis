;;;; datom.lisp - The datom: atomic fact in the substrate
;;;;
;;;; A datom is (entity, attribute, value, tx, added).
;;;; Entity IDs are u64, attribute IDs are u32.
;;;; make-datom auto-interns non-integer entity and attribute arguments.

(in-package #:autopoiesis.substrate)

(defstruct (datom (:conc-name d-)
                  (:constructor %make-datom))
  "An atomic fact: entity has attribute with value at transaction tx."
  (entity    0   :type (unsigned-byte 64))
  (attribute 0   :type (unsigned-byte 32))
  (value     nil)
  (tx        0   :type (unsigned-byte 64))
  (added     t   :type boolean))

(defun make-datom (entity attribute value &key (added t))
  "Create a datom. ENTITY and ATTRIBUTE are auto-interned if not integers.
   Entity IDs use u64 counter, attribute IDs use u32 counter."
  (let ((eid (if (integerp entity) entity (intern-id entity :width :entity)))
        (aid (if (integerp attribute) attribute (intern-id attribute :width :attribute))))
    (%make-datom :entity eid :attribute aid :value value :added added)))
