;;;; crystallize-tests.lisp - Tests for crystallization engine
;;;;
;;;; Tests emitter, capability/heuristic/genome crystallizers,
;;;; snapshot integration, ASDF fragment generation, and git export.

(in-package #:autopoiesis.test)

(def-suite crystallize-tests
  :description "Crystallization engine tests"
  :in all-tests)

(in-suite crystallize-tests)

;;; ===================================================================
;;; Helper Utilities
;;; ===================================================================

(defun make-test-promoted-capability (name &key (registry autopoiesis.agent:*capability-registry*))
  "Create and register a promoted agent-capability for testing."
  (let ((cap (make-instance 'autopoiesis.agent:agent-capability
                            :name name
                            :description (format nil "Test capability ~a" name)
                            :parameters '((x number) (y number))
                            :function (lambda (x y) (+ x y))
                            :source-agent "test-agent-id"
                            :source-code '(lambda (x y) (+ x y))
                            :promotion-status :promoted)))
    (autopoiesis.agent:register-capability cap :registry registry)
    cap))

(defun make-test-heuristic (id &key (confidence 0.8))
  "Create a test heuristic with given confidence."
  (autopoiesis.agent:make-heuristic
   :id id
   :name (format nil "test-heuristic-~a" id)
   :condition '(:task-type :test)
   :recommendation '(:action :test-action)
   :confidence confidence))

(defun make-test-agent ()
  "Create a minimal test agent for snapshot storage."
  (autopoiesis.agent:make-agent :name "test-crystallize-agent"))

;;; ===================================================================
;;; Emitter Tests
;;; ===================================================================

(test emit-to-file-basic
  "emit-to-file writes valid, readable .lisp files."
  (let ((tmp (merge-pathnames "test-emit.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-to-file '((defun foo () 42)) tmp)
          (is (not (null (probe-file tmp))))
          ;; Read back and verify
          (with-open-file (in tmp)
            (let ((form (read in)))
              (is (equal form '(defun foo () 42))))))
      (when (probe-file tmp) (delete-file tmp)))))

(test emit-to-file-multiple-forms
  "emit-to-file writes multiple forms that can all be read back."
  (let ((tmp (merge-pathnames "test-emit-multi.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-to-file
           '((defun foo () 1) (defun bar () 2) (defvar *baz* 3))
           tmp)
          (is (not (null (probe-file tmp))))
          (with-open-file (in tmp)
            (let ((f1 (read in nil))
                  (f2 (read in nil))
                  (f3 (read in nil))
                  (f4 (read in nil)))  ; should be EOF
              (is (equal f1 '(defun foo () 1)))
              (is (equal f2 '(defun bar () 2)))
              (is (equal f3 '(defvar *baz* 3)))
              (is (null f4)))))
      (when (probe-file tmp) (delete-file tmp)))))

(test emit-to-file-with-header
  "emit-to-file includes header comment when provided."
  (let ((tmp (merge-pathnames "test-emit-header.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-to-file
           '((defun foo () 42))
           tmp
           :header "Test header")
          (is (not (null (probe-file tmp))))
          ;; Check that header comment exists
          (let ((content (uiop:read-file-string tmp)))
            (is (search "Test header" content))
            (is (search "Auto-generated" content))))
      (when (probe-file tmp) (delete-file tmp)))))

(test emit-to-file-creates-directories
  "emit-to-file creates parent directories if they don't exist."
  (let* ((base (merge-pathnames "test-crystallize-dirs/" (uiop:temporary-directory)))
         (tmp (merge-pathnames "sub/dir/test.lisp" base)))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-to-file '((defun foo () 42)) tmp)
          (is (not (null (probe-file tmp)))))
      (uiop:delete-directory-tree base :validate t :if-does-not-exist :ignore))))

(test emit-to-file-returns-path
  "emit-to-file returns the output path."
  (let ((tmp (merge-pathnames "test-emit-ret.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (let ((result (autopoiesis.crystallize:emit-to-file '((+ 1 2)) tmp)))
          (is (equal result tmp)))
      (when (probe-file tmp) (delete-file tmp)))))

(test emit-to-file-empty-forms
  "emit-to-file handles empty forms list."
  (let ((tmp (merge-pathnames "test-emit-empty.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-to-file nil tmp)
          (is (not (null (probe-file tmp)))))
      (when (probe-file tmp) (delete-file tmp)))))

;;; ===================================================================
;;; Capability Crystallizer Tests
;;; ===================================================================

(test crystallize-capabilities-basic
  "crystallize-capabilities returns forms for promoted capabilities."
  (let ((registry (make-hash-table)))
    (make-test-promoted-capability :test-cap-1 :registry registry)
    (make-test-promoted-capability :test-cap-2 :registry registry)
    (let ((results (autopoiesis.crystallize:crystallize-capabilities :registry registry)))
      (is (= 2 (length results)))
      ;; Each result is (name . form)
      (is (every #'consp results))
      (is (every (lambda (r) (keywordp (car r))) results)))))

(test crystallize-capabilities-only-promoted
  "crystallize-capabilities skips non-promoted capabilities."
  (let ((registry (make-hash-table)))
    ;; Add a promoted one
    (make-test-promoted-capability :promoted-cap :registry registry)
    ;; Add a draft one (regular capability, not agent-capability)
    (let ((draft (make-instance 'autopoiesis.agent:capability
                                :name :draft-cap
                                :description "Draft"
                                :parameters nil
                                :function (lambda () nil))))
      (autopoiesis.agent:register-capability draft :registry registry))
    (let ((results (autopoiesis.crystallize:crystallize-capabilities :registry registry)))
      (is (= 1 (length results)))
      (is (eq :promoted-cap (caar results))))))

(test crystallize-capabilities-empty-registry
  "crystallize-capabilities returns nil for empty registry."
  (let ((registry (make-hash-table)))
    (is (null (autopoiesis.crystallize:crystallize-capabilities :registry registry)))))

(test crystallize-capabilities-form-structure
  "crystallize-capabilities produces well-formed defcapability forms."
  (let ((registry (make-hash-table)))
    (make-test-promoted-capability :structured-cap :registry registry)
    (let* ((results (autopoiesis.crystallize:crystallize-capabilities :registry registry))
           (form (cdar results)))
      ;; Form should start with defcapability symbol
      (is (listp form))
      (is (eq 'autopoiesis.agent:defcapability (first form)))
      ;; Second element is the name
      (is (eq :structured-cap (second form))))))

;;; ===================================================================
;;; Heuristic Crystallizer Tests
;;; ===================================================================

(test crystallize-heuristics-basic
  "crystallize-heuristics returns high-confidence heuristics."
  (let ((autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal)))
    (let ((h1 (make-test-heuristic "h1" :confidence 0.9))
          (h2 (make-test-heuristic "h2" :confidence 0.8)))
      (autopoiesis.agent:store-heuristic h1)
      (autopoiesis.agent:store-heuristic h2)
      (let ((results (autopoiesis.crystallize:crystallize-heuristics :min-confidence 0.7)))
        (is (= 2 (length results)))
        (is (every #'consp results))))))

(test crystallize-heuristics-filters-by-confidence
  "crystallize-heuristics filters out low-confidence heuristics."
  (let ((autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal)))
    (let ((h-high (make-test-heuristic "h-high" :confidence 0.9))
          (h-low (make-test-heuristic "h-low" :confidence 0.3)))
      (autopoiesis.agent:store-heuristic h-high)
      (autopoiesis.agent:store-heuristic h-low)
      (let ((results (autopoiesis.crystallize:crystallize-heuristics :min-confidence 0.7)))
        (is (= 1 (length results)))
        (is (string= "h-high" (caar results)))))))

(test crystallize-heuristics-custom-threshold
  "crystallize-heuristics respects custom min-confidence."
  (let ((autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal)))
    (let ((h1 (make-test-heuristic "h1" :confidence 0.5))
          (h2 (make-test-heuristic "h2" :confidence 0.6)))
      (autopoiesis.agent:store-heuristic h1)
      (autopoiesis.agent:store-heuristic h2)
      ;; With threshold 0.4, both should pass
      (let ((results (autopoiesis.crystallize:crystallize-heuristics :min-confidence 0.4)))
        (is (= 2 (length results))))
      ;; With threshold 0.55, only h2 should pass
      (let ((results (autopoiesis.crystallize:crystallize-heuristics :min-confidence 0.55)))
        (is (= 1 (length results)))))))

(test crystallize-heuristics-empty-store
  "crystallize-heuristics returns nil for empty store."
  (let ((autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal)))
    (is (null (autopoiesis.crystallize:crystallize-heuristics)))))

(test crystallize-heuristics-sexpr-form
  "crystallize-heuristics returns valid sexpr forms."
  (let ((autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal)))
    (let ((h1 (make-test-heuristic "h-form" :confidence 0.9)))
      (autopoiesis.agent:store-heuristic h1)
      (let* ((results (autopoiesis.crystallize:crystallize-heuristics))
             (sexpr (cdar results)))
        ;; Sexpr should be a valid heuristic representation
        (is (listp sexpr))))))

;;; ===================================================================
;;; Snapshot Integration Tests
;;; ===================================================================

(test store-crystallized-snapshot-basic
  "store-crystallized-snapshot creates a snapshot with crystallized metadata."
  (let ((autopoiesis.snapshot:*snapshot-store* nil)  ; no persistence
        (agent (make-test-agent)))
    (let ((snap (autopoiesis.crystallize:store-crystallized-snapshot
                 agent
                 '(:capabilities ((defun foo () 42)))
                 :label "test-label")))
      (is (not (null snap)))
      (is (typep snap 'autopoiesis.snapshot:snapshot))
      ;; Check metadata
      (let ((metadata (autopoiesis.snapshot:snapshot-metadata snap)))
        (is (equal '(:capabilities ((defun foo () 42)))
                   (getf metadata :crystallized)))
        (is (string= "test-label" (getf metadata :label)))
        (is (numberp (getf metadata :crystallized-at)))))))

(test store-crystallized-snapshot-agent-state
  "store-crystallized-snapshot captures current agent state."
  (let ((autopoiesis.snapshot:*snapshot-store* nil)
        (agent (make-test-agent)))
    (let* ((snap (autopoiesis.crystallize:store-crystallized-snapshot agent nil))
           (state (autopoiesis.snapshot:snapshot-agent-state snap)))
      ;; Agent state should be a valid sexpr
      (is (not (null state))))))

(test crystallize-all-basic
  "crystallize-all combines all crystallizers and stores snapshot."
  (let ((autopoiesis.snapshot:*snapshot-store* nil)
        (autopoiesis.agent:*capability-registry* (make-hash-table))
        (autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal))
        (agent (make-test-agent)))
    ;; Set up some test data
    (make-test-promoted-capability :all-cap :registry autopoiesis.agent:*capability-registry*)
    (let ((h (make-test-heuristic "all-h" :confidence 0.9)))
      (autopoiesis.agent:store-heuristic h))
    ;; Crystallize all
    (let ((snap (autopoiesis.crystallize:crystallize-all agent :label "all-test")))
      (is (not (null snap)))
      (is (typep snap 'autopoiesis.snapshot:snapshot))
      (let* ((metadata (autopoiesis.snapshot:snapshot-metadata snap))
             (crystallized (getf metadata :crystallized)))
        ;; Should have both capabilities and heuristics
        (is (not (null (getf crystallized :capabilities))))
        (is (not (null (getf crystallized :heuristics))))))))

(test crystallize-all-empty
  "crystallize-all works with no data to crystallize."
  (let ((autopoiesis.snapshot:*snapshot-store* nil)
        (autopoiesis.agent:*capability-registry* (make-hash-table))
        (autopoiesis.agent:*heuristic-store* (make-hash-table :test 'equal))
        (agent (make-test-agent)))
    (let ((snap (autopoiesis.crystallize:crystallize-all agent)))
      (is (not (null snap)))
      (let* ((metadata (autopoiesis.snapshot:snapshot-metadata snap))
             (crystallized (getf metadata :crystallized)))
        (is (null (getf crystallized :capabilities)))
        (is (null (getf crystallized :heuristics)))))))

;;; ===================================================================
;;; Git Export Tests
;;; ===================================================================

(test export-to-git-basic
  "export-to-git writes crystallized forms to filesystem."
  (let* ((autopoiesis.snapshot:*snapshot-store* nil)
         (agent (make-test-agent))
         (dir (merge-pathnames "test-export/" (uiop:temporary-directory)))
         (snap (autopoiesis.crystallize:store-crystallized-snapshot
                agent
                (list :capabilities '((autopoiesis.agent:defcapability :test-export nil "A test" :body 42))
                      :heuristics '((:heuristic :id "h1" :name "test"))))))
    (unwind-protect
        (let ((files (autopoiesis.crystallize:export-to-git snap :output-dir dir)))
          (is (not (null files)))
          (is (>= (length files) 1))
          ;; All files should exist
          (is (every #'probe-file files)))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test export-to-git-nil-crystallized
  "export-to-git returns nil when no crystallized data."
  (let* ((autopoiesis.snapshot:*snapshot-store* nil)
         (agent (make-test-agent))
         (snap (autopoiesis.snapshot:make-snapshot
                (autopoiesis.agent:agent-to-sexpr agent)
                :metadata nil)))
    (is (null (autopoiesis.crystallize:export-to-git snap)))))

(test export-to-git-capabilities-only
  "export-to-git writes capability files."
  (let* ((autopoiesis.snapshot:*snapshot-store* nil)
         (agent (make-test-agent))
         (dir (merge-pathnames "test-export-caps/" (uiop:temporary-directory)))
         (snap (autopoiesis.crystallize:store-crystallized-snapshot
                agent
                (list :capabilities '((autopoiesis.agent:defcapability :my-cap nil "desc" :body t))))))
    (unwind-protect
        (let ((files (autopoiesis.crystallize:export-to-git snap :output-dir dir)))
          (is (= 1 (length files)))
          ;; Should be in capabilities/ subdirectory
          (is (search "capabilities/" (namestring (first files)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test export-to-git-heuristics-only
  "export-to-git writes heuristic files."
  (let* ((autopoiesis.snapshot:*snapshot-store* nil)
         (agent (make-test-agent))
         (dir (merge-pathnames "test-export-heurs/" (uiop:temporary-directory)))
         (snap (autopoiesis.crystallize:store-crystallized-snapshot
                agent
                (list :heuristics '((:heuristic :id "h1") (:heuristic :id "h2"))))))
    (unwind-protect
        (let ((files (autopoiesis.crystallize:export-to-git snap :output-dir dir)))
          (is (= 1 (length files)))
          ;; Should be in heuristics/ subdirectory
          (is (search "heuristics/" (namestring (first files)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

;;; ===================================================================
;;; ASDF Fragment Tests
;;; ===================================================================

(test emit-asdf-fragment-basic
  "emit-asdf-fragment generates a valid defsystem form."
  (let ((tmp (merge-pathnames "test-asdf.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-asdf-fragment
           '(:capabilities-named ((:test-cap . (defun test-cap () 42))))
           tmp)
          (is (not (null (probe-file tmp))))
          ;; Read back and verify structure
          (with-open-file (in tmp)
            ;; Skip header comments
            (let ((line (read-line in nil)))
              (loop while (and line (eql (char line 0) #\;))
                    do (setq line (read-line in nil)))
              ;; Re-read from the non-comment position
              (file-position in 0))
            ;; Skip comment lines to read the form
            (let* ((content (uiop:read-file-string tmp))
                   ;; Find first open paren not in a comment
                   (form-start (position #\( content
                                         :test (lambda (ch c) (declare (ignore ch)) (char= c #\()))))
              (declare (ignore form-start))
              ;; File should contain asdf:defsystem
              (is (search "DEFSYSTEM" (string-upcase content))))))
      (when (probe-file tmp) (delete-file tmp)))))

(test emit-asdf-fragment-custom-system-name
  "emit-asdf-fragment uses custom system name."
  (let ((tmp (merge-pathnames "test-asdf-name.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (autopoiesis.crystallize:emit-asdf-fragment nil tmp :system-name "my-system")
          (let ((content (uiop:read-file-string tmp)))
            (is (search "MY-SYSTEM" (string-upcase content)))))
      (when (probe-file tmp) (delete-file tmp)))))

(test emit-asdf-fragment-returns-path
  "emit-asdf-fragment returns the output path."
  (let ((tmp (merge-pathnames "test-asdf-ret.lisp" (uiop:temporary-directory))))
    (unwind-protect
        (let ((result (autopoiesis.crystallize:emit-asdf-fragment nil tmp)))
          (is (equal result tmp)))
      (when (probe-file tmp) (delete-file tmp)))))

;;; ===================================================================
;;; Genome Crystallizer Tests
;;; ===================================================================

(test crystallize-genome-basic
  "crystallize-genome converts a genome to sexpr."
  ;; The swarm package should be loaded in the test environment
  (when (find-package :autopoiesis.swarm)
    (let* ((genome (autopoiesis.swarm:make-genome
                    :capabilities '(:read :write)
                    :heuristic-weights '((:h1 . 0.5))
                    :parameters '(:threshold 0.7)))
           (sexpr (autopoiesis.crystallize:crystallize-genome genome)))
      (is (not (null sexpr)))
      (is (listp sexpr)))))

(test crystallize-genomes-list
  "crystallize-genomes handles a list of genomes."
  (when (find-package :autopoiesis.swarm)
    (let* ((g1 (autopoiesis.swarm:make-genome :capabilities '(:a)))
           (g2 (autopoiesis.swarm:make-genome :capabilities '(:b)))
           (results (autopoiesis.crystallize:crystallize-genomes (list g1 g2))))
      (is (= 2 (length results)))
      (is (every #'consp results)))))

(test crystallize-genomes-empty
  "crystallize-genomes returns nil for empty list."
  (is (null (autopoiesis.crystallize:crystallize-genomes nil))))

;;; ===================================================================
;;; Trigger Condition Tests
;;; ===================================================================

(test create-performance-trigger-basic
  "create-performance-trigger creates and registers a performance trigger."
  (let* ((trigger (autopoiesis.crystallize:create-performance-trigger
                   "test-trigger" "Test performance trigger"
                   :heuristic-confidence 0.8))
         (retrieved (autopoiesis.crystallize:get-trigger
                     (autopoiesis.crystallize:trigger-condition-id trigger))))
    (is (not (null trigger)))
    (is (string= "test-trigger" (autopoiesis.crystallize:trigger-condition-name trigger)))
    (is (eq :heuristic-confidence
            (autopoiesis.crystallize:performance-threshold-trigger-metric-type trigger)))
    (is (= 0.8 (autopoiesis.crystallize:performance-threshold-trigger-threshold trigger)))
    (is (eq trigger retrieved))))

(test create-scheduled-trigger-basic
  "create-scheduled-trigger creates and registers a scheduled trigger."
  (let* ((trigger (autopoiesis.crystallize:create-scheduled-trigger
                   "daily-trigger" "Daily crystallization" 86400))
         (retrieved (autopoiesis.crystallize:get-trigger
                     (autopoiesis.crystallize:trigger-condition-id trigger))))
    (is (not (null trigger)))
    (is (string= "daily-trigger" (autopoiesis.crystallize:trigger-condition-name trigger)))
    (is (= 86400 (autopoiesis.crystallize:scheduled-interval-trigger-interval-seconds trigger)))
    (is (eq trigger retrieved))))

(test trigger-registry-operations
  "Trigger registry operations work correctly."
  (let ((trigger1 (autopoiesis.crystallize:create-performance-trigger
                   "trig1" "Trigger 1" :success-rate 0.9))
        (trigger2 (autopoiesis.crystallize:create-scheduled-trigger
                   "trig2" "Trigger 2" 3600)))
    ;; Should have 2 triggers now (plus any existing ones from other tests)
    (let ((all-triggers (autopoiesis.crystallize:list-triggers)))
      (is (>= (length all-triggers) 2)))
    ;; Unregister one
    (autopoiesis.crystallize:unregister-trigger
     (autopoiesis.crystallize:trigger-condition-id trigger1))
    (is (null (autopoiesis.crystallize:get-trigger
               (autopoiesis.crystallize:trigger-condition-id trigger1))))
    ;; Other should still exist
    (is (not (null (autopoiesis.crystallize:get-trigger
                    (autopoiesis.crystallize:trigger-condition-id trigger2)))))))

(test performance-trigger-evaluation
  "Performance trigger evaluates correctly."
  (let ((trigger (autopoiesis.crystallize:create-performance-trigger
                  "perf-test" "Performance test trigger"
                  :heuristic-confidence 0.5 :comparison :above)))
    ;; Initially should not trigger (no agent data)
    (is (null (autopoiesis.crystallize:evaluate-trigger trigger)))
    ;; Test cooldown mechanism
    (setf (autopoiesis.crystallize:trigger-condition-last-triggered trigger)
          (get-universal-time))
    ;; Should not trigger due to cooldown
    (is (null (autopoiesis.crystallize:evaluate-trigger trigger)))))

(test scheduled-trigger-evaluation
  "Scheduled trigger evaluates correctly."
  (let ((trigger (autopoiesis.crystallize:create-scheduled-trigger
                  "sched-test" "Scheduled test trigger" 3600)))
    ;; Set next trigger time to past
    (setf (autopoiesis.crystallize:scheduled-interval-trigger-next-trigger-time trigger)
          (- (get-universal-time) 100))
    ;; Should trigger
    (is (not (null (autopoiesis.crystallize:evaluate-trigger trigger))))
    ;; Next trigger time should be updated
    (is (> (autopoiesis.crystallize:scheduled-interval-trigger-next-trigger-time trigger)
           (get-universal-time)))))

(test trigger-serialization
  "Triggers can be serialized to/from plists."
  (let* ((perf-trigger (autopoiesis.crystallize:create-performance-trigger
                        "serialize-test" "Serialization test"
                        :success-rate 0.75 :agent-id "test-agent"))
         (sched-trigger (autopoiesis.crystallize:create-scheduled-trigger
                         "serialize-sched" "Scheduled serialization" 7200))
         (perf-plist (autopoiesis.crystallize:trigger-to-plist perf-trigger))
         (sched-plist (autopoiesis.crystallize:trigger-to-plist sched-trigger)))
    ;; Check plist structure
    (is (eq :performance-threshold-trigger (getf perf-plist :type)))
    (is (= 0.75 (getf perf-plist :threshold)))
    (is (string= "test-agent" (getf perf-plist :agent-id)))
    (is (eq :scheduled-interval-trigger (getf sched-plist :type)))
    (is (= 7200 (getf sched-plist :interval-seconds)))
    ;; Reconstruct from plist
    (let ((reconstructed-perf (autopoiesis.crystallize:plist-to-trigger perf-plist))
          (reconstructed-sched (autopoiesis.crystallize:plist-to-trigger sched-plist)))
      (is (not (null reconstructed-perf)))
      (is (not (null reconstructed-sched)))
      (is (string= "serialize-test"
                   (autopoiesis.crystallize:trigger-condition-name reconstructed-perf)))
      (is (string= "serialize-sched"
                   (autopoiesis.crystallize:trigger-condition-name reconstructed-sched))))))
