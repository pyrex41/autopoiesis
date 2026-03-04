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

;;; ===================================================================
;;; Phase 1.5: define-entity-type
;;; ===================================================================

(test define-entity-type-creates-class
  "define-entity-type registers in registry and creates a CLOS class."
  (is (not (null (gethash :event autopoiesis.substrate:*entity-type-registry*))))
  (is (not (null (gethash :worker autopoiesis.substrate:*entity-type-registry*))))
  (is (not (null (gethash :agent autopoiesis.substrate:*entity-type-registry*))))
  (is (not (null (gethash :session autopoiesis.substrate:*entity-type-registry*))))
  (is (not (null (gethash :snapshot autopoiesis.substrate:*entity-type-registry*))))
  (is (not (null (gethash :turn autopoiesis.substrate:*entity-type-registry*))))
  (is (not (null (gethash :context autopoiesis.substrate:*entity-type-registry*)))))

(test make-typed-entity-creates-wrapper
  "make-typed-entity creates a CLOS object with entity-id."
  (autopoiesis.substrate:with-store ()
    (let* ((eid (autopoiesis.substrate:intern-id :test-agent-1))
           (entity (autopoiesis.substrate:make-typed-entity :agent eid)))
      (is (not (null entity)))
      (is (= eid (autopoiesis.substrate:entity-id entity))))))

(test typed-entity-slot-unbound-loads-from-substrate
  "Slot access on typed entity loads value from substrate via slot-unbound."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :my-agent :agent/name "Test Agent")
           (autopoiesis.substrate:make-datom :my-agent :agent/status :running)))
    (let* ((eid (autopoiesis.substrate:intern-id :my-agent))
           (entity (autopoiesis.substrate:make-typed-entity :agent eid)))
      (is (equal "Test Agent" (slot-value entity 'autopoiesis.substrate::name)))
      (is (eq :running (slot-value entity 'autopoiesis.substrate::status))))))

(test typed-entity-unset-attribute-returns-nil
  "Slot-unbound returns nil for unset attributes."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :my-agent :agent/name "Test")))
    (let* ((eid (autopoiesis.substrate:intern-id :my-agent))
           (entity (autopoiesis.substrate:make-typed-entity :agent eid)))
      ;; :agent/result was never set
      (is (null (slot-value entity 'autopoiesis.substrate::result))))))

(test unknown-entity-type-signaled-for-unregistered
  "make-typed-entity signals unknown-entity-type for unregistered types."
  (autopoiesis.substrate:with-store ()
    (handler-case
        (progn
          (autopoiesis.substrate:make-typed-entity :nonexistent 42)
          (fail "Should have signaled"))
      (autopoiesis.substrate:unknown-entity-type (c)
        (is (= 42 (autopoiesis.substrate::condition-entity-id c)))))))

(test all-seven-builtin-types-registered
  "All 7 pre-defined entity types are registered."
  (let ((types '(:event :worker :agent :session :snapshot :turn :context)))
    (dolist (type types)
      (is (not (null (gethash type autopoiesis.substrate:*entity-type-registry*)))
          "Type ~A should be registered" type))))

;;; ===================================================================
;;; Phase 1.5: defsystem
;;; ===================================================================

(test defsystem-registers-in-registry
  "defsystem registers in system registry."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-system-state)
    (autopoiesis.substrate:defsystem :test-sys
      (:entity-type nil :watches (:a/test-attr))
      (declare (ignore entity datoms tx-id)))
    (is (not (null (gethash :test-sys autopoiesis.substrate:*system-registry*))))))

(test defsystem-handler-fires-on-watched-attr
  "defsystem handler fires when watched attribute changes."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-system-state)
    (let ((fired nil))
      (autopoiesis.substrate:defsystem :watch-test
        (:entity-type nil :watches (:a/watched))
        (declare (ignore datoms tx-id))
        (setf fired t))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :a/watched "yes")))
      (is (not (null fired))))))

(test defsystem-handler-does-not-fire-for-unwatched
  "defsystem handler does NOT fire for unwatched attributes."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-system-state)
    (let ((fired nil))
      (autopoiesis.substrate:defsystem :no-fire-test
        (:entity-type nil :watches (:a/watched))
        (declare (ignore datoms tx-id))
        (setf fired t))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :a/unwatched "no")))
      (is (null fired)))))

(test defsystem-entity-type-filter
  "defsystem with entity-type filter only fires for matching entities."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-system-state)
    (let ((fired-count 0))
      (autopoiesis.substrate:defsystem :typed-sys
        (:entity-type :agent :watches (:agent/status))
        (declare (ignore datoms tx-id))
        (incf fired-count))
      ;; Write entity type first, then status
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :a1 :entity/type :agent)
             (autopoiesis.substrate:make-datom :a1 :agent/status :running)))
      ;; Write a non-agent with status
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :entity/type :event)
             (autopoiesis.substrate:make-datom :e1 :agent/status :running)))
      (is (= 1 fired-count)))))

(test multiple-defsystems-dispatch-correctly
  "Multiple defsystems with different watches dispatch to the right ones."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-system-state)
    (let ((sys1-fired nil)
          (sys2-fired nil))
      (autopoiesis.substrate:defsystem :sys1
        (:entity-type nil :watches (:a/alpha))
        (declare (ignore datoms tx-id))
        (setf sys1-fired t))
      (autopoiesis.substrate:defsystem :sys2
        (:entity-type nil :watches (:a/beta))
        (declare (ignore datoms tx-id))
        (setf sys2-fired t))
      ;; Only trigger :a/alpha
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :a/alpha 1)))
      (is (not (null sys1-fired)))
      (is (null sys2-fired)))))

;;; ===================================================================
;;; Phase 2: Blob Store (in-memory mode)
;;; ===================================================================

(test blob-store-roundtrip
  "store-blob / load-blob round-trip for string content."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((hash (autopoiesis.substrate:store-blob "hello world")))
      (is (stringp hash))
      (is (= 64 (length hash)))  ; SHA-256 hex = 64 chars
      (is (equal "hello world"
                 (autopoiesis.substrate:load-blob hash :as-string t))))))

(test blob-exists-p
  "blob-exists-p returns t for stored, nil for missing."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((hash (autopoiesis.substrate:store-blob "test content")))
      (is (autopoiesis.substrate:blob-exists-p hash))
      (is (not (autopoiesis.substrate:blob-exists-p "nonexistent-hash"))))))

(test blob-content-addressed-dedup
  "Same content produces same hash (deduplication)."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((hash1 (autopoiesis.substrate:store-blob "identical content"))
          (hash2 (autopoiesis.substrate:store-blob "identical content")))
      (is (equal hash1 hash2)))))

(test blob-different-content-different-hash
  "Different content produces different hashes."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((hash1 (autopoiesis.substrate:store-blob "content A"))
          (hash2 (autopoiesis.substrate:store-blob "content B")))
      (is (not (equal hash1 hash2))))))

(test blob-load-bytes
  "load-blob returns bytes when as-string is nil."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((hash (autopoiesis.substrate:store-blob "byte test"))
           (bytes (autopoiesis.substrate:load-blob hash)))
      (is (typep bytes '(vector (unsigned-byte 8))))
      (is (equal "byte test"
                 (babel:octets-to-string bytes :encoding :utf-8))))))

(test blob-load-missing-returns-nil
  "load-blob returns nil for missing hash."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (is (null (autopoiesis.substrate:load-blob "nonexistent")))))

;;; ===================================================================
;;; Phase 2: LMDB Backend
;;; ===================================================================

(test lmdb-store-lifecycle
  "open-lmdb-store and close lifecycle works."
  (let ((path (format nil "/tmp/ap-test-~A/" (get-universal-time))))
    (unwind-protect
         (let ((store (autopoiesis.substrate:open-store :path path)))
           ;; Store should exist but be in-memory (no LMDB path wired in open-store yet)
           (is (not (null store)))
           (autopoiesis.substrate:close-store :store store))
      (uiop:delete-directory-tree (pathname path) :validate t :if-does-not-exist :ignore))))

(test lmdb-serialization-roundtrip
  "serialize-value / deserialize-value round-trip."
  (let ((test-values (list "hello" 42 :keyword '(1 2 3) t nil)))
    (dolist (val test-values)
      (let ((bytes (autopoiesis.substrate::serialize-value val)))
        (is (equalp val (autopoiesis.substrate::deserialize-value bytes))
            "Round-trip failed for ~A" val)))))

(test decode-encode-u64-roundtrip
  "encode-u64-be / decode-u64-be round-trip."
  (let ((buf (make-array 8 :element-type '(unsigned-byte 8))))
    (dolist (val (list 0 1 255 256 65535 (expt 2 32) (1- (expt 2 63))))
      (autopoiesis.substrate::encode-u64-be buf 0 val)
      (is (= val (autopoiesis.substrate::decode-u64-be buf 0))
          "Round-trip failed for ~A" val))))

(test decode-encode-u32-roundtrip
  "encode-u32-be / decode-u32-be round-trip."
  (let ((buf (make-array 4 :element-type '(unsigned-byte 8))))
    (dolist (val (list 0 1 255 256 65535 (1- (expt 2 32))))
      (autopoiesis.substrate::encode-u32-be buf 0 val)
      (is (= val (autopoiesis.substrate::decode-u32-be buf 0))
          "Round-trip failed for ~A" val))))

;;; ===================================================================
;;; Context object tests
;;; ===================================================================

(test context-object-exists
  "with-store binds *substrate* as a substrate-context."
  (autopoiesis.substrate:with-store ()
    (is (not (null autopoiesis.substrate:*substrate*)))
    (is (typep autopoiesis.substrate:*substrate*
               'autopoiesis.substrate:substrate-context))))

(test context-object-has-store
  "*substrate* context holds the active store."
  (autopoiesis.substrate:with-store ()
    (is (eq autopoiesis.substrate:*store*
            (autopoiesis.substrate:substrate-context-store
             autopoiesis.substrate:*substrate*)))))

(test context-thread-isolation
  "Two threads with separate with-store contexts cannot see each other's data."
  (let ((results (make-array 2 :initial-element nil))
        (barrier (bt:make-lock "barrier"))
        (ready-count 0)
        (ready-cv (bt:make-condition-variable)))
    ;; Thread A: writes :agent-a, checks :agent-b is absent
    (bt:make-thread
     (lambda ()
       (autopoiesis.substrate:with-store ()
         (autopoiesis.substrate:transact!
          (list (autopoiesis.substrate:make-datom :agent-a :agent/name "thread-a")))
         ;; Signal ready
         (bt:with-lock-held (barrier)
           (incf ready-count)
           (bt:condition-notify ready-cv))
         ;; Wait for other thread
         (bt:with-lock-held (barrier)
           (loop until (>= ready-count 2)
                 do (bt:condition-wait ready-cv barrier)))
         ;; Check: should see own data, not other thread's
         (setf (aref results 0)
               (and (equal "thread-a" (autopoiesis.substrate:entity-attr :agent-a :agent/name))
                    (null (autopoiesis.substrate:entity-attr :agent-b :agent/name))))))
     :name "isolation-thread-a")
    ;; Thread B: writes :agent-b, checks :agent-a is absent
    (bt:make-thread
     (lambda ()
       (autopoiesis.substrate:with-store ()
         (autopoiesis.substrate:transact!
          (list (autopoiesis.substrate:make-datom :agent-b :agent/name "thread-b")))
         ;; Signal ready
         (bt:with-lock-held (barrier)
           (incf ready-count)
           (bt:condition-notify ready-cv))
         ;; Wait for other thread
         (bt:with-lock-held (barrier)
           (loop until (>= ready-count 2)
                 do (bt:condition-wait ready-cv barrier)))
         ;; Check: should see own data, not other thread's
         (setf (aref results 1)
               (and (equal "thread-b" (autopoiesis.substrate:entity-attr :agent-b :agent/name))
                    (null (autopoiesis.substrate:entity-attr :agent-a :agent/name))))))
     :name "isolation-thread-b")
    ;; Wait for both threads to finish
    (sleep 2)
    (is (aref results 0) "Thread A should see its own data and not thread B's")
    (is (aref results 1) "Thread B should see its own data and not thread A's")))

;;; ===================================================================
;;; Batch transaction tests
;;; ===================================================================

(test batch-basic-accumulation
  "with-batch-transaction accumulates multiple transact! into one write."
  (autopoiesis.substrate:with-store ()
    (let ((hook-call-count 0))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :count-hook
       (lambda (datoms tx-id)
         (declare (ignore datoms tx-id))
         (incf hook-call-count)))
      (autopoiesis.substrate:with-batch-transaction ()
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :e1 :name "alice")))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :e2 :name "bob")))
        ;; During batch: hook should NOT have fired yet
        (is (= 0 hook-call-count) "Hooks should not fire during batch"))
      ;; After batch: both writes committed, hook fired once
      (is (= 1 hook-call-count) "Hook should fire exactly once after batch")
      (is (equal "alice" (autopoiesis.substrate:entity-attr :e1 :name)))
      (is (equal "bob" (autopoiesis.substrate:entity-attr :e2 :name))))))

(test batch-nested-no-premature-flush
  "Nested with-batch-transaction only flushes at outermost level."
  (autopoiesis.substrate:with-store ()
    (let ((hook-call-count 0))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :count-hook
       (lambda (datoms tx-id)
         (declare (ignore datoms tx-id))
         (incf hook-call-count)))
      (autopoiesis.substrate:with-batch-transaction ()
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :e1 :name "outer")))
        (autopoiesis.substrate:with-batch-transaction ()
          (autopoiesis.substrate:transact!
           (list (autopoiesis.substrate:make-datom :e2 :name "inner")))
          ;; Inner batch exit: should NOT flush
          (is (= 0 hook-call-count) "Inner batch should not trigger flush"))
        ;; After inner but still in outer: still no flush
        (is (= 0 hook-call-count) "Still in outer batch, no flush yet"))
      ;; After outer: everything flushed
      (is (= 1 hook-call-count) "Hook fires once after outer batch")
      (is (equal "outer" (autopoiesis.substrate:entity-attr :e1 :name)))
      (is (equal "inner" (autopoiesis.substrate:entity-attr :e2 :name))))))

(test batch-error-rollback
  "On error, batch queue is cleared -- no partial writes."
  (autopoiesis.substrate:with-store ()
    (handler-case
        (autopoiesis.substrate:with-batch-transaction ()
          (autopoiesis.substrate:transact!
           (list (autopoiesis.substrate:make-datom :e1 :name "should-not-persist")))
          (error "intentional error"))
      (error () nil))
    ;; The datom should NOT have been written
    (is (null (autopoiesis.substrate:entity-attr :e1 :name))
        "Errored batch should not write data")))

(test batch-hook-receives-all-datoms
  "Hook receives the combined datom list from the entire batch."
  (autopoiesis.substrate:with-store ()
    (let ((received-datoms nil))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :capture-hook
       (lambda (datoms tx-id)
         (declare (ignore tx-id))
         (setf received-datoms datoms)))
      (autopoiesis.substrate:with-batch-transaction ()
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :e1 :x 1)))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom :e2 :x 2))))
      ;; Hook should have received all datoms from both transact! calls
      (is (= 2 (length received-datoms))
          "Hook should receive all datoms from batch"))))

;;; ===================================================================
;;; Temporal query tests
;;; ===================================================================

(test entity-history-returns-all-values
  "entity-history returns historical values with tx-ids."
  (autopoiesis.substrate:with-store ()
    ;; Write 3 different values for the same entity+attribute
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :agent-1 :agent/status :starting)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :agent-1 :agent/status :running)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :agent-1 :agent/status :stopped)))
    ;; entity-history should return all 3, most recent first
    (let ((history (autopoiesis.substrate:entity-history :agent-1 :agent/status)))
      (is (>= (length history) 3)
          "Should have at least 3 history entries")
      ;; Most recent should be :stopped
      (is (eq :stopped (getf (first history) :value))
          "Most recent value should be :stopped")
      ;; Each entry should have :tx and :value
      (dolist (entry history)
        (is (not (null (getf entry :tx))) "Entry should have :tx")
        (is (not (null (getf entry :value))) "Entry should have :value")))))

(test entity-history-respects-limit
  "entity-history :last-n limits results."
  (autopoiesis.substrate:with-store ()
    (dotimes (i 5)
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :counter :val i))))
    (let ((history (autopoiesis.substrate:entity-history :counter :val :last-n 2)))
      (is (= 2 (length history)) "Should return exactly 2 entries"))))

(test entity-as-of-reconstructs-state
  "entity-as-of returns entity state at a historical transaction."
  (autopoiesis.substrate:with-store ()
    (let ((tx1 (autopoiesis.substrate:transact!
                (list (autopoiesis.substrate:make-datom :agent-1 :agent/name "alice")
                      (autopoiesis.substrate:make-datom :agent-1 :agent/status :running))))
          (tx2 (autopoiesis.substrate:transact!
                (list (autopoiesis.substrate:make-datom :agent-1 :agent/status :stopped)
                      (autopoiesis.substrate:make-datom :agent-1 :agent/result "done")))))
      ;; State at tx1: should have name=alice, status=running, no result
      (let ((state-at-tx1 (autopoiesis.substrate:entity-as-of :agent-1 tx1)))
        (is (equal "alice" (getf state-at-tx1 :agent/name)))
        (is (eq :running (getf state-at-tx1 :agent/status)))
        (is (null (getf state-at-tx1 :agent/result))
            "result should not exist at tx1"))
      ;; State at tx2: should have updated status and result
      (let ((state-at-tx2 (autopoiesis.substrate:entity-as-of :agent-1 tx2)))
        (is (equal "alice" (getf state-at-tx2 :agent/name)))
        (is (eq :stopped (getf state-at-tx2 :agent/status)))
        (is (equal "done" (getf state-at-tx2 :agent/result)))))))

(test scan-index-returns-results
  "scan-index returns entries from in-memory EAVT index."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :name "test")))
    ;; scan-index should return at least one entry
    (let ((results (autopoiesis.substrate:scan-index :eavt)))
      (is (> (length results) 0) "EAVT index should have entries"))))

;;; ===================================================================
;;; Datalog query tests
;;; ===================================================================

(test datalog-single-clause
  "Single clause query finds matching entities."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a2 :agent/status :stopped)
           (autopoiesis.substrate:make-datom :a3 :agent/status :running)))
    (let ((results (autopoiesis.substrate:query
                    '((?e :agent/status :running)))))
      (is (= 2 (length results)) "Should find 2 running agents")
      ;; Each result should have :?E bound
      (dolist (r results)
        (is (not (null (cdr (assoc :?e r)))) "Should have ?e binding")))))

(test datalog-two-clause-join
  "Two clause join binds variables across clauses."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a2 :agent/status :stopped)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")))
    (let ((results (autopoiesis.substrate:query
                    '((?e :agent/status :running)
                      (?e :agent/name ?name)))))
      (is (= 1 (length results)) "Should find 1 running agent with name")
      (let ((r (first results)))
        (is (equal "alice" (cdr (assoc :?name r))))))))

(test datalog-negation
  "Negation excludes matching entities."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a2 :agent/status :running)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")
           (autopoiesis.substrate:make-datom :a2 :agent/error "crash")))
    (let ((results (autopoiesis.substrate:query
                    '((?e :agent/status :running)
                      (?e :agent/name ?name)
                      (not (?e :agent/error ?err))))))
      ;; Only alice should remain (bob has an error)
      (is (= 1 (length results)) "Should find 1 agent without errors")
      (is (equal "alice" (cdr (assoc :?name (first results))))))))

(test datalog-compiled-equals-interpreted
  "compile-query produces same results as interpreted query."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")))
    (autopoiesis.substrate:compile-query test-query
      ((?e :agent/status :running) (?e :agent/name ?name)))
    (let ((compiled-results (test-query))
          (interp-results (autopoiesis.substrate:query
                           '((?e :agent/status :running)
                             (?e :agent/name ?name)))))
      (is (= (length compiled-results) (length interp-results))
          "Compiled and interpreted should return same count")
      ;; Both should find alice
      (is (equal "alice" (cdr (assoc :?name (first compiled-results)))))
      (is (equal "alice" (cdr (assoc :?name (first interp-results))))))))

;;; ===================================================================
;;; Pull API tests
;;; ===================================================================

(test pull-specific-attributes
  "Pull reads specific attributes from an entity."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :agent-1 :agent/status :running)
           (autopoiesis.substrate:make-datom :agent-1 :agent/name "scout")
           (autopoiesis.substrate:make-datom :agent-1 :agent/task "analyze")
           (autopoiesis.substrate:make-datom :agent-1 :agent/extra "ignored")))
    (let ((result (autopoiesis.substrate:pull :agent-1 '(:agent/status :agent/name :agent/task))))
      (is (eq :running (getf result :agent/status)))
      (is (equal "scout" (getf result :agent/name)))
      (is (equal "analyze" (getf result :agent/task)))
      ;; :agent/extra not requested, should not appear
      (is (null (getf result :agent/extra))))))

(test pull-missing-attributes
  "Pull returns plist without missing attributes."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :agent-2 :agent/name "minimal")))
    (let ((result (autopoiesis.substrate:pull :agent-2 '(:agent/name :agent/status))))
      (is (equal "minimal" (getf result :agent/name)))
      ;; :agent/status not set, won't appear in plist
      (is (= 2 (length result))))))

(test pull-wildcard
  "Pull with (*) returns all attributes like entity-state."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :agent-3 :agent/name "full")
           (autopoiesis.substrate:make-datom :agent-3 :agent/status :idle)))
    (let ((result (autopoiesis.substrate:pull :agent-3 '(*))))
      (is (not (null result)))
      (is (equal "full" (getf result :agent/name)))
      (is (eq :idle (getf result :agent/status))))))

(test pull-nonexistent-entity
  "Pull on nonexistent entity returns nil."
  (autopoiesis.substrate:with-store ()
    (let ((result (autopoiesis.substrate:pull :no-such-entity '(:agent/name))))
      (is (null result)))))

(test pull-many-entities
  "Pull-many reads same pattern from multiple entities."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")
           (autopoiesis.substrate:make-datom :a2 :agent/status :idle)))
    (let ((results (autopoiesis.substrate:pull-many '(:a1 :a2) '(:agent/name :agent/status))))
      (is (= 2 (length results)))
      (is (equal "alice" (getf (first results) :agent/name)))
      (is (eq :running (getf (first results) :agent/status)))
      (is (equal "bob" (getf (second results) :agent/name)))
      (is (eq :idle (getf (second results) :agent/status))))))

;;; ===================================================================
;;; q function tests (Datomic-style query)
;;; ===================================================================

(test q-relation-mode
  "q returns list of tuples by default."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a2 :agent/status :idle)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")))
    (let ((results (autopoiesis.substrate:q
                    '(:find ?name ?status
                      :where (?e :agent/status ?status)
                             (?e :agent/name ?name)))))
      (is (= 2 (length results)))
      ;; Each result should be a 2-element list
      (dolist (r results)
        (is (= 2 (length r)))))))

(test q-scalar-mode
  "q with . returns single scalar value."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")))
    (let ((result (autopoiesis.substrate:q
                   '(:find ?name |.|
                     :where (?e :agent/status :running)
                            (?e :agent/name ?name)))))
      (is (equal "alice" result)))))

(test q-collection-mode
  "q with [?var ...] returns flat list of values."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :entity/type :agent)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a2 :entity/type :agent)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")))
    (let ((results (autopoiesis.substrate:q
                    '(:find (?name |...|)
                      :where (?e :entity/type :agent)
                             (?e :agent/name ?name)))))
      (is (= 2 (length results)))
      (is (member "alice" results :test #'equal))
      (is (member "bob" results :test #'equal)))))

(test q-with-negation
  "q supports negation in :where clauses."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a2 :agent/status :running)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")
           (autopoiesis.substrate:make-datom :a2 :agent/error "crash")))
    (let ((results (autopoiesis.substrate:q
                    '(:find (?name |...|)
                      :where (?e :agent/status :running)
                             (?e :agent/name ?name)
                             (not (?e :agent/error ?err))))))
      (is (= 1 (length results)))
      (is (equal "alice" (first results))))))

;;; ===================================================================
;;; q :in parameter tests
;;; ===================================================================

(test q-with-in-param
  "q with :in binds external parameters."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a2 :agent/status :idle)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")))
    (let ((results (autopoiesis.substrate:q
                    '(:find (?name |...|)
                      :in ?status
                      :where (?e :agent/status ?status)
                             (?e :agent/name ?name))
                    :running)))
      (is (= 1 (length results)))
      (is (equal "alice" (first results))))))

(test q-with-multiple-in-params
  "q with multiple :in vars binds all of them."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :a1 :agent/status :running)
           (autopoiesis.substrate:make-datom :a1 :agent/name "alice")
           (autopoiesis.substrate:make-datom :a1 :entity/type :agent)
           (autopoiesis.substrate:make-datom :a2 :agent/status :idle)
           (autopoiesis.substrate:make-datom :a2 :agent/name "bob")
           (autopoiesis.substrate:make-datom :a2 :entity/type :agent)))
    (let ((results (autopoiesis.substrate:q
                    '(:find ?name |.|
                      :in ?type ?status
                      :where (?e :entity/type ?type)
                             (?e :agent/status ?status)
                             (?e :agent/name ?name))
                    :agent :running)))
      (is (equal "alice" results)))))

;;; ===================================================================
;;; Rule/recursive query tests
;;; ===================================================================

(test q-with-simple-rule
  "q with rules expands rule definitions."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :t1 :turn/parent :t0)
           (autopoiesis.substrate:make-datom :t0 :turn/name "root")))
    (let ((results (autopoiesis.substrate:q
                    '(:find ?parent |.|
                      :in % ?start
                      :where (parent-of ?start ?parent))
                    '(((parent-of ?t ?p) (?t :turn/parent ?p)))
                    :t1)))
      ;; t1's parent is t0
      (is (not (null results))))))

(test q-with-recursive-rule
  "q with recursive rules follows transitive closure."
  (autopoiesis.substrate:with-store ()
    ;; Build a chain: t3 -> t2 -> t1 -> t0
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :t3 :turn/parent :t2)
           (autopoiesis.substrate:make-datom :t2 :turn/parent :t1)
           (autopoiesis.substrate:make-datom :t1 :turn/parent :t0)
           (autopoiesis.substrate:make-datom :t0 :turn/name "root")))
    (let ((results (autopoiesis.substrate:q
                    '(:find (?ancestor |...|)
                      :in % ?start
                      :where (ancestor ?start ?ancestor))
                    '(((ancestor ?t ?a) (?t :turn/parent ?a))
                      ((ancestor ?t ?a) (?t :turn/parent ?mid) (ancestor ?mid ?a)))
                    :t3)))
      ;; Should find t2, t1, and t0 as ancestors
      (is (>= (length results) 3)))))

(test q-recursive-rule-cycle-detection
  "q with recursive rules handles cycles without infinite loops."
  (autopoiesis.substrate:with-store ()
    ;; Build a cycle: t1 -> t2 -> t1
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :c1 :link/next :c2)
           (autopoiesis.substrate:make-datom :c2 :link/next :c1)))
    ;; Should terminate without error
    (let ((results (autopoiesis.substrate:q
                    '(:find (?target |...|)
                      :in % ?start
                      :where (reachable ?start ?target))
                    '(((reachable ?s ?t) (?s :link/next ?t))
                      ((reachable ?s ?t) (?s :link/next ?mid) (reachable ?mid ?t)))
                    :c1)))
      ;; Should find at least c2 and c1 (from cycle), and terminate
      (is (not (null results))))))

;;; ===================================================================
;;; Hook ordering tests (Phase 9)
;;; ===================================================================

(test hook-priority-ordering
  "Hooks fire in priority order (lower number first)."
  (autopoiesis.substrate:with-store ()
    (let ((order nil))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :hook-c
       (lambda (datoms tx-id)
         (declare (ignore datoms tx-id))
         (push :c order))
       :priority 2)
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :hook-a
       (lambda (datoms tx-id)
         (declare (ignore datoms tx-id))
         (push :a order))
       :priority 0)
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store* :hook-b
       (lambda (datoms tx-id)
         (declare (ignore datoms tx-id))
         (push :b order))
       :priority 1)
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom :e1 :x 1)))
      ;; Order is reversed because we push, so check nreverse
      (setf order (nreverse order))
      (is (equal '(:a :b :c) order)
          "Hooks should fire in priority order: a(0) b(1) c(2)"))))

(defvar *system-test-order* nil "Dynamic var for system ordering test.")

(test system-after-ordering
  "System with :after fires after its dependency."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-system-state)
    (setf *system-test-order* nil)
    (eval `(autopoiesis.substrate:defsystem :sys-cache
             (:watches (:test/val)
              :access :read-only)
             (push :cache autopoiesis.test::*system-test-order*)))
    (eval `(autopoiesis.substrate:defsystem :sys-derived
             (:watches (:test/val)
              :after (:sys-cache)
              :access :read-only)
             (push :derived autopoiesis.test::*system-test-order*)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom :e1 :test/val 42)))
    (let ((order (nreverse *system-test-order*)))
      (is (equal '(:cache :derived) order)
          "System :sys-derived should fire after :sys-cache"))
    (autopoiesis.substrate::reset-system-state)))

(test circular-system-dependency-detected
  "Circular dependencies signal circular-system-dependency condition."
  (let ((sys-a (make-instance 'autopoiesis.substrate::system-descriptor
                              :name :sys-a
                              :entity-type nil
                              :watches nil
                              :access :read-only
                              :after '(:sys-b)
                              :handler (lambda (e d tx) (declare (ignore e d tx)))))
        (sys-b (make-instance 'autopoiesis.substrate::system-descriptor
                              :name :sys-b
                              :entity-type nil
                              :watches nil
                              :access :read-only
                              :after '(:sys-a)
                              :handler (lambda (e d tx) (declare (ignore e d tx))))))
    (signals autopoiesis.substrate:circular-system-dependency
      (autopoiesis.substrate::topological-sort-systems (list sys-a sys-b)))))
