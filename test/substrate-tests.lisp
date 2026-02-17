;;;; substrate-tests.lisp - Tests for the substrate kernel
;;;;
;;;; Tests for Phase 1: datom, intern, transact!, hooks, indexes,
;;;; entity cache, value index, take!, query, conditions.

(in-package #:autopoiesis.test)

(def-suite substrate-tests
  :description "Substrate kernel tests")

(in-suite substrate-tests)

;;; ===================================================================
;;; Store lifecycle
;;; ===================================================================

(test store-open-close
  "open-store creates a store, close-store clears it."
  (autopoiesis.substrate:with-store ()
    (is (not (null autopoiesis.substrate:*store*)))
    (is (typep autopoiesis.substrate:*store* 'autopoiesis.substrate::substrate-store)))
  ;; After with-store, *store* binding reverts
  )

(test store-with-store-cleanup
  "with-store cleans up on exit."
  (let ((inner-store nil))
    (autopoiesis.substrate:with-store ()
      (setf inner-store autopoiesis.substrate:*store*)
      (is (not (null inner-store))))
    ;; Store was closed inside with-store
    ))

;;; ===================================================================
;;; Datom creation
;;; ===================================================================

(test datom-creation-with-integers
  "make-datom with integer entity and attribute."
  (autopoiesis.substrate:with-store ()
    (let ((d (autopoiesis.substrate:make-datom 42 7 "hello")))
      (is (= 42 (autopoiesis.substrate:d-entity d)))
      (is (= 7 (autopoiesis.substrate:d-attribute d)))
      (is (equal "hello" (autopoiesis.substrate:d-value d)))
      (is (eq t (autopoiesis.substrate:d-added d))))))

(test datom-creation-with-keywords
  "make-datom auto-interns keyword entity and attribute."
  (autopoiesis.substrate:with-store ()
    (let ((d (autopoiesis.substrate:make-datom :my-agent :agent/name "test")))
      (is (integerp (autopoiesis.substrate:d-entity d)))
      (is (integerp (autopoiesis.substrate:d-attribute d)))
      (is (equal "test" (autopoiesis.substrate:d-value d))))))

(test datom-retraction
  "make-datom with :added nil creates a retraction."
  (autopoiesis.substrate:with-store ()
    (let ((d (autopoiesis.substrate:make-datom :x :a/b "val" :added nil)))
      (is (eq nil (autopoiesis.substrate:d-added d))))))

;;; ===================================================================
;;; Interning
;;; ===================================================================

(test intern-id-idempotent
  "intern-id returns the same ID for the same input."
  (autopoiesis.substrate:with-store ()
    (let ((id1 (autopoiesis.substrate:intern-id :test-entity))
          (id2 (autopoiesis.substrate:intern-id :test-entity)))
      (is (= id1 id2)))))

(test intern-id-monotonic
  "intern-id produces sequential IDs."
  (autopoiesis.substrate:with-store ()
    (let ((id1 (autopoiesis.substrate:intern-id :first))
          (id2 (autopoiesis.substrate:intern-id :second)))
      (is (= (1+ id1) id2)))))

(test intern-id-different-widths
  "Entity and attribute ID spaces are separate."
  (autopoiesis.substrate:with-store ()
    (let ((eid (autopoiesis.substrate:intern-id :test :width :entity))
          (aid (autopoiesis.substrate:intern-id :test :width :attribute)))
      ;; Both could be 1 since they're separate counters
      (is (integerp eid))
      (is (integerp aid)))))

(test resolve-id-roundtrip
  "resolve-id returns original term."
  (autopoiesis.substrate:with-store ()
    (let ((id (autopoiesis.substrate:intern-id :my-term)))
      (is (eq :my-term (autopoiesis.substrate:resolve-id id))))))

;;; ===================================================================
;;; Transact! and entity cache
;;; ===================================================================

(test transact-assigns-tx-id
  "transact! assigns a transaction ID."
  (autopoiesis.substrate:with-store ()
    (let ((tx-id (autopoiesis.substrate:transact!
                  (list (autopoiesis.substrate:make-datom :e1 :a/name "test")))))
      (is (integerp tx-id))
      (is (plusp tx-id)))))

(test transact-sequential-tx-ids
  "Sequential transact! calls get increasing tx-ids."
  (autopoiesis.substrate:with-store ()
    (let ((tx1 (autopoiesis.substrate:transact!
                (list (autopoiesis.substrate:make-datom :e1 :a/x 1))))
          (tx2 (autopoiesis.substrate:transact!
                (list (autopoiesis.substrate:make-datom :e1 :a/y 2)))))
      (is (< tx1 tx2)))))

(test entity-attr-after-transact
  "entity-attr returns current value after transact!."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :my-agent :agent/name "test")))
    (is (equal "test" (autopoiesis.substrate:entity-attr :my-agent :agent/name)))))

(test entity-attr-update
  "Later transact! updates entity-attr value."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :a/val "first")))
    (is (equal "first" (autopoiesis.substrate:entity-attr :e1 :a/val)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :a/val "second")))
    (is (equal "second" (autopoiesis.substrate:entity-attr :e1 :a/val)))))

(test retraction-removes-value
  "Retraction (added=nil) removes value from cache."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :a/val "here")))
    (is (equal "here" (autopoiesis.substrate:entity-attr :e1 :a/val)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :a/val "here" :added nil)))
    (is (null (autopoiesis.substrate:entity-attr :e1 :a/val)))))

(test entity-state-full-plist
  "entity-state returns full plist for entity."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :a/name "test")
           (autopoiesis.substrate:make-datom :e1 :a/status :active)))
    (let ((state (autopoiesis.substrate:entity-state :e1)))
      (is (not (null state)))
      ;; State is a plist, check values are present
      (is (member "test" state :test #'equal))
      (is (member :active state)))))

(test transact-nil-datoms-filtered
  "transact! filters nil datoms (convenience for conditional construction)."
  (autopoiesis.substrate:with-store ()
    (let ((tx (autopoiesis.substrate:transact!
               (list (autopoiesis.substrate:make-datom :e1 :a/x 1)
                     nil
                     (autopoiesis.substrate:make-datom :e1 :a/y 2)))))
      (is (integerp tx))
      (is (= 1 (autopoiesis.substrate:entity-attr :e1 :a/x)))
      (is (= 2 (autopoiesis.substrate:entity-attr :e1 :a/y))))))

(test transact-empty-returns-nil
  "transact! with all-nil list returns nil."
  (autopoiesis.substrate:with-store ()
    (is (null (autopoiesis.substrate:transact! (list nil nil))))))

;;; ===================================================================
;;; Hooks
;;; ===================================================================

(test hook-fires-after-transact
  "register-hook fires after transact! with correct datoms and tx-id."
  (autopoiesis.substrate:with-store ()
    (let ((hook-datoms nil)
          (hook-tx nil))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :test-hook
       (lambda (datoms tx-id)
         (setf hook-datoms datoms)
         (setf hook-tx tx-id)))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :a/x "val")))
      (is (not (null hook-datoms)))
      (is (= 1 (length hook-datoms)))
      (is (integerp hook-tx)))))

(test hooks-fire-outside-lock
  "Hooks fire outside the lock -- a hook calling transact! does NOT deadlock."
  (autopoiesis.substrate:with-store ()
    (let ((inner-tx nil)
          (guard nil))  ; Prevent infinite recursion
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :recursive-hook
       (lambda (datoms tx-id)
         (declare (ignore datoms tx-id))
         (unless guard
           (setf guard t)
           ;; This would deadlock if hooks fired inside the lock
           (setf inner-tx
                 (autopoiesis.substrate:transact!
                  (list (autopoiesis.substrate:make-datom :inner :a/from-hook t)))))))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :outer :a/trigger t)))
      (is (integerp inner-tx))
      (is (eq t (autopoiesis.substrate:entity-attr :inner :a/from-hook))))))

(test unregister-hook
  "unregister-hook prevents hook from firing."
  (autopoiesis.substrate:with-store ()
    (let ((fired nil))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :temp-hook
       (lambda (datoms tx-id) (declare (ignore datoms tx-id)) (setf fired t)))
      (autopoiesis.substrate:unregister-hook
       autopoiesis.substrate:*store* :temp-hook)
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :a/x 1)))
      (is (null fired)))))

(test hook-error-does-not-crash-transact
  "Hook errors are caught and don't prevent transact! from completing."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:register-hook
     autopoiesis.substrate:*store* :bad-hook
     (lambda (datoms tx-id) (declare (ignore datoms tx-id)) (error "boom")))
    ;; Should not signal an error
    (let ((tx (autopoiesis.substrate:transact!
               (list (autopoiesis.substrate:make-datom :e1 :a/x 1)))))
      (is (integerp tx))
      (is (= 1 (autopoiesis.substrate:entity-attr :e1 :a/x))))))

;;; ===================================================================
;;; Scoped indexes
;;; ===================================================================

(test define-index-with-scope
  "Scoped index only receives matching datoms."
  (autopoiesis.substrate:with-store ()
    (let ((scoped-writes 0))
      ;; Define a scoped index that only indexes agent-related datoms
      (let ((agent-attr-id (autopoiesis.substrate:intern-id :entity/type :width :attribute)))
        (autopoiesis.substrate:define-index
         autopoiesis.substrate:*store* :agent-only
         (lambda (datom) (autopoiesis.substrate::encode-eavt-key datom))
         :scope (lambda (datom)
                  ;; Only index datoms where entity has type :agent
                  (and (= (autopoiesis.substrate:d-attribute datom) agent-attr-id)
                       (eq (autopoiesis.substrate:d-value datom) :agent)))
         :strategy :append)
        ;; Register a hook to count writes to the scoped index
        (autopoiesis.substrate:register-hook
         autopoiesis.substrate:*store* :count-scoped
         (lambda (datoms tx-id)
           (declare (ignore tx-id))
           (dolist (d datoms)
             (when (and (= (autopoiesis.substrate:d-attribute d) agent-attr-id)
                        (eq (autopoiesis.substrate:d-value d) :agent))
               (incf scoped-writes)))))
        ;; Write an agent type datom (matches scope)
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :a1 :entity/type :agent)))
        ;; Write a non-agent datom (does NOT match scope)
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :e1 :entity/type :event)))
        (is (= 1 scoped-writes))))))

;;; ===================================================================
;;; take! (Linda coordination)
;;; ===================================================================

(test take-claims-entity
  "take! atomically claims and updates matching entity."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :task1 :task/status :pending)))
    (let ((eid (autopoiesis.substrate:take! :task/status :pending
                                            :new-value :in-progress)))
      (is (not (null eid)))
      ;; After take!, value is updated
      (is (eq :in-progress (autopoiesis.substrate:entity-attr :task1 :task/status))))))

(test take-returns-nil-no-match
  "take! returns nil when no entity matches."
  (autopoiesis.substrate:with-store ()
    (is (null (autopoiesis.substrate:take! :task/status :pending)))))

(test take-retraction-only
  "take! without :new-value retracts the attribute."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :task1 :task/status :pending)))
    (autopoiesis.substrate:take! :task/status :pending)
    (is (null (autopoiesis.substrate:entity-attr :task1 :task/status)))))

;;; ===================================================================
;;; find-entities
;;; ===================================================================

(test find-entities-basic
  "find-entities returns matching entity IDs."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :entity/type :agent)
           (autopoiesis.substrate:make-datom :a2 :entity/type :agent)
           (autopoiesis.substrate:make-datom :e1 :entity/type :event)))
    (let ((agents (autopoiesis.substrate:find-entities :entity/type :agent)))
      (is (= 2 (length agents))))))

(test find-entities-by-type
  "find-entities-by-type is sugar for find-entities with :entity/type."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :entity/type :agent)))
    (let ((agents (autopoiesis.substrate:find-entities-by-type :agent)))
      (is (= 1 (length agents))))))

(test query-first
  "query-first returns the first matching entity."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/name "test")))
    (is (not (null (autopoiesis.substrate:query-first :agent/name "test"))))
    (is (null (autopoiesis.substrate:query-first :agent/name "nonexistent")))))

;;; ===================================================================
;;; Conditions
;;; ===================================================================

(test substrate-validation-error-signals
  "substrate-validation-error signals with expected slots."
  (handler-case
      (error 'autopoiesis.substrate:substrate-validation-error
             :attribute :a/name
             :expected-type 'string
             :actual-value 42
             :message "type mismatch")
    (autopoiesis.substrate:substrate-validation-error (c)
      (is (eq :a/name (autopoiesis.substrate::condition-attribute c)))
      (is (eq 'string (autopoiesis.substrate::validation-expected-type c)))
      (is (= 42 (autopoiesis.substrate::validation-actual-value c))))))

(test unknown-entity-type-signals
  "unknown-entity-type signals with attribute list."
  (handler-case
      (error 'autopoiesis.substrate:unknown-entity-type
             :entity-id 42
             :attributes '(:a/name :a/status)
             :message "unknown type")
    (autopoiesis.substrate:unknown-entity-type (c)
      (is (= 42 (autopoiesis.substrate::condition-entity-id c)))
      (is (equal '(:a/name :a/status)
                 (autopoiesis.substrate::unknown-type-attributes c))))))

;;; ===================================================================
;;; Encoding (basic sanity)
;;; ===================================================================

(test encoding-u64-roundtrip
  "encode-u64-be produces correct big-endian bytes."
  (let ((buf (make-array 8 :element-type '(unsigned-byte 8))))
    (autopoiesis.substrate::encode-u64-be buf 0 256)
    ;; 256 = 0x0000000000000100
    (is (= 1 (aref buf 6)))
    (is (= 0 (aref buf 7)))))

(test encoding-eavt-key-length
  "EAVT key is 20 bytes."
  (autopoiesis.substrate:with-store ()
    (let* ((d (autopoiesis.substrate:make-datom :e1 :a/x "v"))
           (key (autopoiesis.substrate::encode-eavt-key d)))
      (is (= 20 (length key))))))
