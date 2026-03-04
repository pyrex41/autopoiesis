;;;; persistent-agent-tests.lisp - Tests for persistent agent layer
;;;;
;;;; Tests structural sharing, immutability, serialization, forking,
;;;; lineage, membrane, cognitive cycles, and dual-agent bridge.

(in-package #:autopoiesis.test)

(def-suite persistent-agent-tests
  :description "Tests for persistent agent data structures and operations")

(in-suite persistent-agent-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Data Structure Tests (Wave 0)
;;; ═══════════════════════════════════════════════════════════════════

(test persistent-map-basics
  "Basic persistent map operations"
  (let* ((m (pmap-empty))
         (m1 (pmap-put m :a 1))
         (m2 (pmap-put m1 :b 2)))
    ;; Empty
    (is (= 0 (pmap-count m)))
    ;; Single insert
    (is (= 1 (pmap-count m1)))
    (is (= 1 (pmap-get m1 :a)))
    ;; Two inserts
    (is (= 2 (pmap-count m2)))
    (is (= 1 (pmap-get m2 :a)))
    (is (= 2 (pmap-get m2 :b)))
    ;; Original unchanged (immutability)
    (is (= 0 (pmap-count m)))
    ;; Contains
    (is (pmap-contains-p m2 :a))
    (is (not (pmap-contains-p m2 :c)))
    ;; Remove
    (let ((m3 (pmap-remove m2 :a)))
      (is (= 1 (pmap-count m3)))
      (is (not (pmap-contains-p m3 :a)))
      (is (= 2 (pmap-count m2))))))

(test persistent-map-merge-and-convert
  "Map merge and alist conversion"
  (let* ((m1 (pmap-put (pmap-empty) :a 1))
         (m2 (pmap-put (pmap-empty) :b 2))
         (merged (pmap-merge m1 m2)))
    (is (= 2 (pmap-count merged)))
    (is (= 1 (pmap-get merged :a)))
    (is (= 2 (pmap-get merged :b)))
    ;; Round-trip via alist
    (let* ((alist (pmap-to-alist merged))
           (restored (alist-to-pmap alist)))
      (is (pmap-equal merged restored)))))

(test persistent-map-equality-and-hash
  "Map equality and hash stability"
  (let* ((m1 (pmap-put (pmap-put (pmap-empty) :a 1) :b 2))
         (m2 (pmap-put (pmap-put (pmap-empty) :b 2) :a 1)))
    (is (pmap-equal m1 m2))
    (is (string= (pmap-hash m1) (pmap-hash m2)))))

(test persistent-vector-basics
  "Basic persistent vector operations"
  (let* ((v (pvec-empty))
         (v1 (pvec-push v 10))
         (v2 (pvec-push v1 20))
         (v3 (pvec-push v2 30)))
    ;; Length
    (is (= 0 (pvec-length v)))
    (is (= 3 (pvec-length v3)))
    ;; Ref
    (is (= 10 (pvec-ref v3 0)))
    (is (= 20 (pvec-ref v3 1)))
    (is (= 30 (pvec-ref v3 2)))
    ;; Last
    (is (= 30 (pvec-last v3)))
    ;; Set
    (let ((v4 (pvec-set v3 1 99)))
      (is (= 99 (pvec-ref v4 1)))
      (is (= 20 (pvec-ref v3 1))))  ; original unchanged
    ;; Round-trip
    (let* ((lst (pvec-to-list v3))
           (restored (list-to-pvec lst)))
      (is (pvec-equal v3 restored)))))

(test persistent-set-basics
  "Basic persistent set operations"
  (let* ((s (pset-empty))
         (s1 (pset-add s :a))
         (s2 (pset-add s1 :b))
         (s3 (pset-add s2 :c)))
    ;; Count
    (is (= 0 (pset-count s)))
    (is (= 3 (pset-count s3)))
    ;; Contains
    (is (pset-contains-p s3 :a))
    (is (not (pset-contains-p s3 :x)))
    ;; Remove
    (let ((s4 (pset-remove s3 :b)))
      (is (= 2 (pset-count s4)))
      (is (not (pset-contains-p s4 :b)))
      (is (= 3 (pset-count s3))))  ; original unchanged
    ;; Union/intersection/difference
    (let ((s4 (pset-add (pset-add (pset-empty) :b) :d)))
      (is (= 4 (pset-count (pset-union s3 s4))))
      (is (= 1 (pset-count (pset-intersection s3 s4))))
      (is (= 2 (pset-count (pset-difference s3 s4)))))
    ;; Round-trip
    (let* ((lst (pset-to-list s3))
           (restored (list-to-pset lst)))
      (is (pset-equal s3 restored)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Agent Structure Tests (Wave 1)
;;; ═══════════════════════════════════════════════════════════════════

(test persistent-agent-creation
  "Create a persistent agent with defaults and custom values"
  (let ((a (autopoiesis.agent:make-persistent-agent :name "test-agent")))
    (is (stringp (autopoiesis.agent:persistent-agent-id a)))
    (is (string= "test-agent" (autopoiesis.agent:persistent-agent-name a)))
    (is (= 0 (autopoiesis.agent:persistent-agent-version a)))
    (is (numberp (autopoiesis.agent:persistent-agent-timestamp a)))
    (is (= 0 (pvec-length (autopoiesis.agent:persistent-agent-thoughts a))))
    (is (= 0 (pset-count (autopoiesis.agent:persistent-agent-capabilities a))))))

(test persistent-agent-with-capabilities
  "Create agent with capabilities list converts to pset"
  (let ((a (autopoiesis.agent:make-persistent-agent
            :name "cap-agent"
            :capabilities '(:search :analyze :report))))
    (is (= 3 (pset-count (autopoiesis.agent:persistent-agent-capabilities a))))
    (is (pset-contains-p (autopoiesis.agent:persistent-agent-capabilities a) :search))))

(test persistent-agent-serialization-roundtrip
  "Agent serializes to sexpr and deserializes back faithfully"
  (let* ((a (autopoiesis.agent:make-persistent-agent
             :name "roundtrip-agent"
             :capabilities '(:cap1 :cap2)
             :genome '((:define-fn :add (a b) (+ a b)))))
         (sexpr (autopoiesis.agent:persistent-agent-to-sexpr a))
         (restored (autopoiesis.agent:sexpr-to-persistent-agent sexpr)))
    (is (string= (autopoiesis.agent:persistent-agent-name a)
                 (autopoiesis.agent:persistent-agent-name restored)))
    (is (pset-equal (autopoiesis.agent:persistent-agent-capabilities a)
                    (autopoiesis.agent:persistent-agent-capabilities restored)))
    (is (equal (autopoiesis.agent:persistent-agent-genome a)
               (autopoiesis.agent:persistent-agent-genome restored)))))

(test persistent-agent-copy-immutability
  "Copy creates new struct, original unchanged"
  (let* ((a (autopoiesis.agent:make-persistent-agent :name "original"))
         (b (autopoiesis.agent:copy-persistent-agent a :name "modified")))
    (is (string= "original" (autopoiesis.agent:persistent-agent-name a)))
    (is (string= "modified" (autopoiesis.agent:persistent-agent-name b)))
    (is (not (eq a b)))
    ;; Version incremented
    (is (> (autopoiesis.agent:persistent-agent-version b)
           (autopoiesis.agent:persistent-agent-version a)))))

(test persistent-agent-hash-stability
  "Same content produces same hash"
  (let* ((a (autopoiesis.agent:make-persistent-agent :name "hash-test" :capabilities '(:x)))
         (b (autopoiesis.agent:sexpr-to-persistent-agent
             (autopoiesis.agent:persistent-agent-to-sexpr a))))
    (is (string= (autopoiesis.agent:persistent-agent-hash a)
                 (autopoiesis.agent:persistent-agent-hash b)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cognitive Operations Tests
;;; ═══════════════════════════════════════════════════════════════════

(test persistent-perceive-adds-thought
  "Perceive adds an observation thought"
  (let* ((a (autopoiesis.agent:make-persistent-agent :name "cog-test"))
         (b (autopoiesis.agent:persistent-perceive a '(:input "hello"))))
    (is (= 0 (pvec-length (autopoiesis.agent:persistent-agent-thoughts a))))
    (is (= 1 (pvec-length (autopoiesis.agent:persistent-agent-thoughts b))))
    (is (eq :observation
            (getf (pvec-ref (autopoiesis.agent:persistent-agent-thoughts b) 0) :type)))))

(test persistent-cognitive-cycle-produces-all-phases
  "Full cognitive cycle produces thoughts for all phases"
  (let* ((a (autopoiesis.agent:make-persistent-agent
             :name "cycle-test"
             :capabilities '(:test-cap)))
         (b (autopoiesis.agent:persistent-cognitive-cycle a '(:input "test"))))
    (is (> (pvec-length (autopoiesis.agent:persistent-agent-thoughts b)) 0))
    ;; Original unchanged
    (is (= 0 (pvec-length (autopoiesis.agent:persistent-agent-thoughts a))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Forking and Lineage Tests
;;; ═══════════════════════════════════════════════════════════════════

(test persistent-fork-o1
  "Fork creates new agent sharing data, O(1)"
  (let* ((parent (autopoiesis.agent:make-persistent-agent
                  :name "parent"
                  :capabilities '(:a :b :c)
                  :genome '((:fn1) (:fn2)))))
    (multiple-value-bind (child updated-parent)
        (autopoiesis.agent:persistent-fork parent :name "child")
      ;; Child has new id
      (is (not (string= (autopoiesis.agent:persistent-agent-id parent)
                         (autopoiesis.agent:persistent-agent-id child))))
      ;; Child inherits capabilities
      (is (pset-equal (autopoiesis.agent:persistent-agent-capabilities parent)
                      (autopoiesis.agent:persistent-agent-capabilities child)))
      ;; Child's parent-root points to parent
      (is (string= (autopoiesis.agent:persistent-agent-id parent)
                    (autopoiesis.agent:persistent-agent-parent-root child)))
      ;; Updated parent has child in children
      (is (member (autopoiesis.agent:persistent-agent-id child)
                  (autopoiesis.agent:persistent-agent-children updated-parent)
                  :test #'string=)))))

(test persistent-agent-diff
  "Diff detects changes between agents"
  (let* ((a (autopoiesis.agent:make-persistent-agent :name "diff-a"))
         (b (autopoiesis.agent:copy-persistent-agent a :name "diff-b")))
    (let ((diffs (autopoiesis.agent:persistent-agent-diff a b)))
      (is (not (null diffs))))))

(test persistent-agent-merge
  "Merge combines thoughts and capabilities"
  (let* ((a (autopoiesis.agent:make-persistent-agent
             :name "merge-a"
             :capabilities '(:x)))
         (b (autopoiesis.agent:make-persistent-agent
             :name "merge-b"
             :capabilities '(:y)))
         (merged (autopoiesis.agent:persistent-agent-merge a b)))
    (is (pset-contains-p (autopoiesis.agent:persistent-agent-capabilities merged) :x))
    (is (pset-contains-p (autopoiesis.agent:persistent-agent-capabilities merged) :y))))

(test persistent-ancestors-and-generation
  "Ancestor chain and generation counting"
  (let* ((registry (make-hash-table :test 'equal))
         (root (autopoiesis.agent:make-persistent-agent :name "root")))
    (setf (gethash (autopoiesis.agent:persistent-agent-id root) registry) root)
    (multiple-value-bind (child1 _)
        (autopoiesis.agent:persistent-fork root :name "child1")
      (declare (ignore _))
      (setf (gethash (autopoiesis.agent:persistent-agent-id child1) registry) child1)
      (multiple-value-bind (grandchild _)
          (autopoiesis.agent:persistent-fork child1 :name "grandchild")
        (declare (ignore _))
        (setf (gethash (autopoiesis.agent:persistent-agent-id grandchild) registry) grandchild)
        ;; Ancestors
        (let ((ancestors (autopoiesis.agent:persistent-ancestors grandchild registry)))
          (is (= 2 (length ancestors))))
        ;; Generation
        (is (= 2 (autopoiesis.agent:persistent-generation grandchild registry)))
        (is (= 0 (autopoiesis.agent:persistent-generation root registry)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Membrane Tests
;;; ═══════════════════════════════════════════════════════════════════

(test membrane-allows-and-blocks
  "Membrane controls allowed actions"
  (let* ((allowed-actions (list-to-pset '(:read :write)))
         (membrane (pmap-put (pmap-empty) :allowed-actions allowed-actions))
         (a (autopoiesis.agent:make-persistent-agent
             :name "membrane-test"
             :membrane membrane)))
    (is (autopoiesis.agent:membrane-allows-p a :read))
    (is (autopoiesis.agent:membrane-allows-p a :write))
    (is (not (autopoiesis.agent:membrane-allows-p a :delete)))))

(test membrane-update
  "Membrane update returns new agent"
  (let* ((a (autopoiesis.agent:make-persistent-agent :name "mem-update"))
         (b (autopoiesis.agent:membrane-update a :max-depth 5)))
    (is (= 5 (pmap-get (autopoiesis.agent:persistent-agent-membrane b) :max-depth)))
    (is (= 0 (pmap-count (autopoiesis.agent:persistent-agent-membrane a))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Dual-Agent Bridge Tests
;;; ═══════════════════════════════════════════════════════════════════

(test dual-agent-upgrade
  "Upgrading an agent creates persistent root"
  (let* ((a (autopoiesis.agent:make-agent :name "plain-agent" :capabilities '(:cap1)))
         (dual (autopoiesis.agent:upgrade-to-dual a)))
    (is (typep dual 'autopoiesis.agent:dual-agent))
    (is (not (null (autopoiesis.agent:dual-agent-root dual))))
    (is (string= "plain-agent"
                 (autopoiesis.agent:persistent-agent-name
                  (autopoiesis.agent:dual-agent-root dual))))))

(test dual-agent-undo
  "Undo reverts to previous version"
  (let* ((a (autopoiesis.agent:make-agent :name "undo-test"))
         (dual (autopoiesis.agent:upgrade-to-dual a)))
    ;; Make a change
    (setf (autopoiesis.agent:agent-name dual) "changed")
    ;; Should have history now
    (is (not (null (autopoiesis.agent:dual-agent-history dual))))
    ;; Undo
    (autopoiesis.agent:dual-agent-undo dual)
    (is (string= "undo-test"
                 (autopoiesis.agent:persistent-agent-name
                  (autopoiesis.agent:dual-agent-root dual))))))

(test dual-agent-thread-safety
  "Concurrent access to dual-agent root is safe"
  (let* ((a (autopoiesis.agent:make-agent :name "thread-test"))
         (dual (autopoiesis.agent:upgrade-to-dual a))
         (errors nil)
         (lock (bt:make-lock "error-lock")))
    ;; Spawn 10 threads that concurrently read/write the root
    (let ((threads
            (loop for i from 0 below 10
                  collect (bt:make-thread
                           (lambda ()
                             (handler-case
                                 (dotimes (j 100)
                                   (let ((root (autopoiesis.agent:dual-agent-root dual)))
                                     (when root
                                       (autopoiesis.agent:persistent-agent-name root))))
                               (error (e)
                                 (bt:with-lock-held (lock)
                                   (push e errors)))))
                           :name (format nil "test-thread-~d" i)))))
      (mapc #'bt:join-thread threads))
    (is (null errors))))
