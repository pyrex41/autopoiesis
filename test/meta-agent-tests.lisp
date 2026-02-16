;;;; meta-agent-tests.lisp - Tests for Phase 5 meta-agent orchestration
;;;;
;;;; Tests the CL-side orchestration tools: sub-agent spawning, queuing,
;;;; cognitive branching, session management, and the request drain mechanism.
;;;;
;;;; Note: Full bridge handlers live in scripts/agent-worker.lisp (standalone).
;;;; These tests cover the underlying tool functions and state management.
;;;; Capabilities are invoked via invoke-capability, not as direct functions.

(in-package #:autopoiesis.test)

;;; ===================================================================
;;; Test Suite
;;; ===================================================================

(def-suite meta-agent-tests
  :description "Tests for Phase 5 meta-agent orchestration"
  :in integration-tests)

(in-suite meta-agent-tests)

;;; ===================================================================
;;; Orchestration Request Queue Tests
;;; ===================================================================

(test orchestration-queue-initially-empty
  "orchestration-requests starts as nil."
  (let ((autopoiesis.integration::*orchestration-requests* nil))
    (is (null (autopoiesis.integration:drain-orchestration-requests)))))

(test orchestration-queue-fifo
  "Queued requests drain in FIFO order."
  (let ((autopoiesis.integration::*orchestration-requests* nil))
    (autopoiesis.integration:queue-orchestration-request '(:type :spawn :id "a"))
    (autopoiesis.integration:queue-orchestration-request '(:type :spawn :id "b"))
    (autopoiesis.integration:queue-orchestration-request '(:type :save :id "c"))
    (let ((drained (autopoiesis.integration:drain-orchestration-requests)))
      (is (= 3 (length drained)))
      ;; FIFO: first queued = first drained
      (is (equal "a" (getf (first drained) :id)))
      (is (equal "c" (getf (third drained) :id))))))

(test orchestration-queue-clears-after-drain
  "Draining clears the queue."
  (let ((autopoiesis.integration::*orchestration-requests* nil))
    (autopoiesis.integration:queue-orchestration-request '(:type :test))
    (autopoiesis.integration:drain-orchestration-requests)
    (is (null (autopoiesis.integration:drain-orchestration-requests)))))

;;; ===================================================================
;;; Sub-Agent Registry Tests
;;; ===================================================================

(test sub-agent-registry-update
  "update-sub-agent creates and updates registry entries."
  (let ((autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (autopoiesis.integration:update-sub-agent "test-agent-1"
      :status :running :task "analyze logs")
    (let ((entry (gethash "test-agent-1" autopoiesis.integration::*sub-agents*)))
      (is (not (null entry)))
      (is (eq :running (getf entry :status)))
      (is (equal "analyze logs" (getf entry :task))))))

(test sub-agent-registry-update-merges
  "update-sub-agent merges new properties with existing."
  (let ((autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (autopoiesis.integration:update-sub-agent "agent-2"
      :status :running :task "test")
    (autopoiesis.integration:update-sub-agent "agent-2"
      :status :complete :result "done")
    (let ((entry (gethash "agent-2" autopoiesis.integration::*sub-agents*)))
      (is (eq :complete (getf entry :status)))
      (is (equal "done" (getf entry :result))))))

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
;;; Spawn-Agent Tool Tests
;;; ===================================================================

(test spawn-agent-queues-request
  "spawn-agent tool queues an orchestration request."
  (let ((autopoiesis.integration::*orchestration-requests* nil)
        (autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::spawn-agent
                    :name "test-worker" :task "do something")))
      ;; Returns an agent-id string
      (is (stringp result))
      ;; Should have queued a request
      (let ((reqs (autopoiesis.integration:drain-orchestration-requests)))
        (is (= 1 (length reqs)))
        (is (eq :spawn-agent (getf (first reqs) :type)))))))

(test spawn-agent-registers-in-sub-agents
  "spawn-agent registers the new agent as spawning in *sub-agents*."
  (let ((autopoiesis.integration::*orchestration-requests* nil)
        (autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (autopoiesis.agent:invoke-capability
      'autopoiesis.integration::spawn-agent
      :name "worker-1" :task "check status")
    ;; Should have exactly one entry in sub-agents
    (is (= 1 (hash-table-count autopoiesis.integration::*sub-agents*)))
    ;; The entry should have :spawning status
    (let ((entry (block found
                   (maphash (lambda (k v)
                              (declare (ignore k))
                              (return-from found v))
                            autopoiesis.integration::*sub-agents*))))
      (is (not (null entry)))
      (is (eq :spawning (getf entry :status))))))

;;; ===================================================================
;;; Query-Agent Tool Tests
;;; ===================================================================

(test query-agent-found
  "query-agent returns status for known agent."
  (let ((autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (autopoiesis.integration:update-sub-agent "qa-1"
      :status :running :task "test")
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::query-agent
                    :agent-id "qa-1")))
      (is (stringp result))
      (is (search "RUNNING" result)))))

(test query-agent-not-found
  "query-agent returns message for unknown agent."
  (let ((autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::query-agent
                    :agent-id "nonexistent")))
      (is (stringp result))
      (is (search "not found" result)))))

;;; ===================================================================
;;; Await-Agent Tool Tests
;;; ===================================================================

(test await-agent-already-complete
  "await-agent returns immediately if agent is already complete."
  (let ((autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
    (autopoiesis.integration:update-sub-agent "await-1"
      :status :complete :result "all done")
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::await-agent
                    :agent-id "await-1" :timeout 1)))
      (is (stringp result))
      (is (search "complete" (string-downcase result))))))

(test await-agent-already-failed
  "await-agent returns immediately if agent has failed."
  (let ((autopoiesis.integration::*sub-agents* (make-hash-table :test 'equal)))
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
        ;; Should mention the branch name
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
;;; Session Directory Tests
;;; ===================================================================

(test ensure-session-directory-creates
  "ensure-session-directory creates the directory."
  (let ((autopoiesis.integration::*session-directory*
          (merge-pathnames "test-meta-sessions/"
                           (uiop:temporary-directory))))
    (let ((dir (autopoiesis.integration:ensure-session-directory)))
      (is (not (null dir)))
      (is (uiop:directory-exists-p dir)))))

;;; ===================================================================
;;; Save/Resume Session Tool Tests
;;; ===================================================================

(test save-session-queues-request
  "save-session queues an orchestration request."
  (let ((autopoiesis.integration::*orchestration-requests* nil)
        (autopoiesis.integration::*session-directory*
          (merge-pathnames "test-meta-save/" (uiop:temporary-directory))))
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::save-session
                    :name "my-session")))
      (is (stringp result))
      (let ((reqs (autopoiesis.integration:drain-orchestration-requests)))
        (is (= 1 (length reqs)))
        (is (eq :save-session (getf (first reqs) :type)))))))

(test resume-session-queues-request
  "resume-session queues an orchestration request."
  (let ((autopoiesis.integration::*orchestration-requests* nil))
    (let ((result (autopoiesis.agent:invoke-capability
                    'autopoiesis.integration::resume-session
                    :name "my-session")))
      (is (stringp result))
      (let ((reqs (autopoiesis.integration:drain-orchestration-requests)))
        (is (= 1 (length reqs)))
        (is (eq :resume-session (getf (first reqs) :type)))))))
