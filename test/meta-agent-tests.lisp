;;;; meta-agent-tests.lisp - Tests for Phase 5 meta-agent orchestration
;;;;
;;;; Tests the CL-side orchestration tools: sub-agent spawning via substrate,
;;;; cognitive branching, session management via substrate datoms.
;;;; All state is now in the substrate (no legacy hash tables or queues).

(in-package #:autopoiesis.test)

;;; ===================================================================
;;; Test Suite
;;; ===================================================================

(def-suite meta-agent-tests
  :description "Tests for Phase 5 meta-agent orchestration"
  :in integration-tests)

(in-suite meta-agent-tests)

;;; ===================================================================
;;; Sub-Agent Registry Tests (substrate-backed)
;;; ===================================================================

(test sub-agent-update-creates-datoms
  "update-sub-agent writes datoms to the substrate."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.integration:update-sub-agent "test-agent-1"
      :status :running :task "analyze logs")
    (let ((eid (autopoiesis.substrate:intern-id "test-agent-1")))
      (is (eq :running (autopoiesis.substrate:entity-attr eid :agent/status)))
      (is (equal "analyze logs" (autopoiesis.substrate:entity-attr eid :agent/task))))))

(test sub-agent-update-merges
  "update-sub-agent merges new properties with existing datoms."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.integration:update-sub-agent "agent-2"
      :status :running :task "test")
    (autopoiesis.integration:update-sub-agent "agent-2"
      :status :complete :result "done")
    (let ((eid (autopoiesis.substrate:intern-id "agent-2")))
      (is (eq :complete (autopoiesis.substrate:entity-attr eid :agent/status)))
      (is (equal "done" (autopoiesis.substrate:entity-attr eid :agent/result))))))

;;; ===================================================================
;;; Capability Registration Tests
;;; ===================================================================

(test spawn-agent-capability-registered
  "spawn-agent capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::spawn-agent)))))

(test query-agent-capability-registered
  "query-agent capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::query-agent)))))

(test await-agent-capability-registered
  "await-agent capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::await-agent)))))

(test fork-branch-capability-registered
  "fork-branch capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::fork-branch)))))

(test compare-branches-capability-registered
  "compare-branches capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::compare-branches)))))

(test save-session-capability-registered
  "save-session capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::save-session)))))

(test resume-session-capability-registered
  "resume-session capability is registered."
  (is (not (null (autopoiesis.agent:find-capability
                   'autopoiesis.integration::resume-session)))))

;;; ===================================================================
;;; Spawn-Agent Tool Tests (substrate-backed)
;;; ===================================================================

(test spawn-agent-creates-datoms
  "spawn-agent creates agent datoms in the substrate."
  (autopoiesis.substrate:with-store ()
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::spawn-agent
                    :name "test-worker" :task "do something")))
      ;; Returns a string with the agent-id
      (is (stringp result))
      (is (search "Spawning" result))
      ;; Find the agent in the substrate
      (let ((agents (autopoiesis.substrate:find-entities :agent/status :running)))
        (is (>= (length agents) 1))))))

(test spawn-agent-records-name-and-task
  "spawn-agent records agent name and task as datoms."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.agent:invoke-capability
      'autopoiesis.integration::spawn-agent
      :name "worker-1" :task "check status")
    ;; Find running agents and check their attributes
    (let ((agents (autopoiesis.substrate:find-entities :agent/status :running)))
      (is (>= (length agents) 1))
      (let ((eid (first agents)))
        (is (equal "worker-1" (autopoiesis.substrate:entity-attr eid :agent/name)))
        (is (equal "check status" (autopoiesis.substrate:entity-attr eid :agent/task)))))))

;;; ===================================================================
;;; Query-Agent Tool Tests (substrate-backed)
;;; ===================================================================

(test query-agent-found
  "query-agent returns status for known agent."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.integration:update-sub-agent "qa-1"
      :status :running :task "test")
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::query-agent
                    :agent-id "qa-1")))
      (is (stringp result))
      (is (search "RUNNING" result)))))

(test query-agent-not-found
  "query-agent returns message for unknown agent."
  (autopoiesis.substrate:with-store ()
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::query-agent
                    :agent-id "nonexistent")))
      (is (stringp result))
      (is (search "not found" result)))))

;;; ===================================================================
;;; Await-Agent Tool Tests (substrate-backed)
;;; ===================================================================

(test await-agent-already-complete
  "await-agent returns immediately if agent is already complete."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.integration:update-sub-agent "await-1"
      :status :complete :result "all done")
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::await-agent
                    :agent-id "await-1" :timeout 1)))
      (is (stringp result))
      (is (search "complete" (string-downcase result))))))

(test await-agent-already-failed
  "await-agent returns immediately if agent has failed."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.integration:update-sub-agent "await-2"
      :status :failed :error "crash")
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::await-agent
                    :agent-id "await-2" :timeout 1)))
      (is (stringp result))
      (is (search "failed" (string-downcase result))))))

;;; ===================================================================
;;; Fork-Branch Tool Tests
;;; ===================================================================

(test fork-branch-creates-branch
  "fork-branch creates a snapshot branch."
  (let ((store (autopoiesis.snapshot:make-snapshot-store
                (merge-pathnames "test-meta-fork/"
                                 (uiop:temporary-directory)))))
    (let ((autopoiesis.snapshot:*snapshot-store* store))
      (let ((result (autopoiesis.agent:invoke-capability
                      'autopoiesis.integration::fork-branch
                      :name "experiment")))
        (is (stringp result))
        (is (search "experiment" result))))))

;;; ===================================================================
;;; Compare-Branches Tool Tests
;;; ===================================================================

(test compare-branches-nonexistent
  "compare-branches handles missing branches gracefully."
  (let ((store (autopoiesis.snapshot:make-snapshot-store
                (merge-pathnames "test-meta-compare/"
                                 (uiop:temporary-directory)))))
    (let ((autopoiesis.snapshot:*snapshot-store* store))
      (let ((result (autopoiesis.agent:invoke-capability
                      'autopoiesis.integration::compare-branches
                      :branch-a "nope-a" :branch-b "nope-b")))
        (is (stringp result))))))

;;; ===================================================================
;;; Save/Resume Session Tool Tests (substrate-backed)
;;; ===================================================================

(test save-session-creates-datoms
  "save-session creates session datoms in the substrate."
  (autopoiesis.substrate:with-store ()
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::save-session
                    :name "my-session")))
      (is (stringp result))
      (is (search "my-session" result))
      ;; Verify datoms exist
      (let ((eid (autopoiesis.substrate:intern-id "my-session")))
        (is (equal "my-session" (autopoiesis.substrate:entity-attr eid :session/name)))
        (is (integerp (autopoiesis.substrate:entity-attr eid :session/saved-at)))))))

(test resume-session-reads-substrate
  "resume-session reads session from the substrate."
  (autopoiesis.substrate:with-store ()
    ;; Save first
    (autopoiesis.agent:invoke-capability
      'autopoiesis.integration::save-session
      :name "resume-test")
    ;; Then resume
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::resume-session
                    :name "resume-test")))
      (is (stringp result))
      (is (search "resumed" result)))))

(test resume-session-not-found
  "resume-session handles missing session."
  (autopoiesis.substrate:with-store ()
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::resume-session
                    :name "nonexistent-session")))
      (is (stringp result))
      (is (search "not found" result)))))
