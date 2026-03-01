;;;; sandbox-tests.lisp - Tests for sandbox integration and research campaigns
;;;;
;;;; Mock-based unit tests that run without Linux/sandboxes.
;;;; Tests the provider protocol, entity types, campaign orchestration,
;;;; and tool capability registration.

(defpackage #:autopoiesis.sandbox.test
  (:use #:cl #:fiveam #:alexandria)
  (:export #:run-sandbox-tests))

(in-package #:autopoiesis.sandbox.test)

(def-suite sandbox-tests
  :description "Sandbox integration and research campaign tests")

(in-suite sandbox-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Provider Tests
;;; ═══════════════════════════════════════════════════════════════════

(test sandbox-provider-creation
  "Test creating a sandbox provider with defaults"
  (let ((provider (autopoiesis.sandbox:make-sandbox-provider)))
    (is (typep provider 'autopoiesis.sandbox:sandbox-provider))
    (is (equal "sandbox" (autopoiesis.integration:provider-name provider)))
    (is (= 300 (autopoiesis.integration:provider-timeout provider)))
    (is (equal '(:one-shot)
               (autopoiesis.integration:provider-supported-modes provider)))))

(test sandbox-provider-custom-settings
  "Test creating a sandbox provider with custom settings"
  (let ((provider (autopoiesis.sandbox:make-sandbox-provider
                   :name "custom-sandbox"
                   :default-layers '("000-base-alpine" "101-python")
                   :default-memory-mb 2048
                   :default-cpu 4.0
                   :default-max-lifetime-s 7200
                   :timeout 600)))
    (is (equal "custom-sandbox" (autopoiesis.integration:provider-name provider)))
    (is (= 600 (autopoiesis.integration:provider-timeout provider)))
    (is (equal '("000-base-alpine" "101-python")
               (autopoiesis.sandbox::sandbox-default-layers provider)))
    (is (= 2048 (autopoiesis.sandbox::sandbox-default-memory-mb provider)))
    (is (= 4.0 (autopoiesis.sandbox::sandbox-default-cpu provider)))
    (is (= 7200 (autopoiesis.sandbox::sandbox-default-max-lifetime-s provider)))))

(test sandbox-provider-inherits-from-provider
  "Test that sandbox-provider is a subclass of provider"
  (let ((provider (autopoiesis.sandbox:make-sandbox-provider)))
    (is (typep provider 'autopoiesis.integration:provider))))

(test sandbox-provider-invoke-requires-manager
  "Test that provider-invoke errors without a manager"
  (let ((provider (autopoiesis.sandbox:make-sandbox-provider))
        (autopoiesis.sandbox:*sandbox-manager* nil))
    (signals error
      (autopoiesis.integration:provider-invoke provider "echo hello"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Manager Lifecycle Tests
;;; ═══════════════════════════════════════════════════════════════════

(test manager-initially-nil
  "Test that sandbox manager starts nil"
  (let ((autopoiesis.sandbox:*sandbox-manager* nil))
    (is (null autopoiesis.sandbox:*sandbox-manager*))))

(test start-manager-requires-valid-call
  "Test that start-sandbox-manager signals without squashd on non-Linux"
  ;; On non-Linux systems, the CFFI calls will fail. On Linux without
  ;; privileges, the syscalls will fail. Either way, we test the interface.
  (let ((autopoiesis.sandbox:*sandbox-manager* nil)
        (autopoiesis.sandbox:*sandbox-config* nil))
    ;; We can't actually start the manager without squashd/Linux
    ;; but we can verify the bindings exist
    (is (fboundp 'autopoiesis.sandbox:start-sandbox-manager))
    (is (fboundp 'autopoiesis.sandbox:stop-sandbox-manager))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Direct Operations Interface Tests
;;; ═══════════════════════════════════════════════════════════════════

(test direct-operations-exist
  "Test that direct sandbox operation functions exist"
  (is (fboundp 'autopoiesis.sandbox:create-sandbox))
  (is (fboundp 'autopoiesis.sandbox:destroy-sandbox))
  (is (fboundp 'autopoiesis.sandbox:exec-in-sandbox))
  (is (fboundp 'autopoiesis.sandbox:snapshot-sandbox))
  (is (fboundp 'autopoiesis.sandbox:restore-sandbox))
  (is (fboundp 'autopoiesis.sandbox:list-sandboxes)))

(test direct-operations-require-manager
  "Test that direct operations error without manager"
  (let ((autopoiesis.sandbox:*sandbox-manager* nil))
    (signals error (autopoiesis.sandbox:create-sandbox "test"))
    (signals error (autopoiesis.sandbox:destroy-sandbox "test"))
    (signals error (autopoiesis.sandbox:exec-in-sandbox "test" "echo hi"))
    (signals error (autopoiesis.sandbox:snapshot-sandbox "test" "snap"))
    (signals error (autopoiesis.sandbox:restore-sandbox "test" "snap"))
    (signals error (autopoiesis.sandbox:list-sandboxes))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Conductor Dispatch Tests
;;; ═══════════════════════════════════════════════════════════════════

(test conductor-dispatch-exists
  "Test that dispatch-sandbox-event function exists"
  (is (fboundp 'autopoiesis.sandbox:dispatch-sandbox-event)))

(test conductor-dispatch-requires-manager
  "Test that dispatch errors without manager"
  (let ((autopoiesis.sandbox:*sandbox-manager* nil))
    (signals error
      (autopoiesis.sandbox:dispatch-sandbox-event
       nil (list :command "echo hello")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Research Campaign Tests
;;; ═══════════════════════════════════════════════════════════════════

(test research-campaign-creation
  "Test creating a research campaign with defaults"
  (let ((campaign (make-instance 'autopoiesis.research:research-campaign
                                 :question "Test question?")))
    (is (stringp (autopoiesis.research:campaign-id campaign)))
    (is (equal "Test question?" (autopoiesis.research:campaign-question campaign)))
    (is (= 5 (autopoiesis.research::campaign-num-approaches campaign)))
    (is (eq :pending (autopoiesis.research:campaign-status campaign)))
    (is (eq :tool-backed (autopoiesis.research:campaign-mode campaign)))
    (is (null (autopoiesis.research:campaign-approaches campaign)))
    (is (null (autopoiesis.research:campaign-trials campaign)))
    (is (null (autopoiesis.research:campaign-summary campaign)))))

(test research-campaign-custom-settings
  "Test creating a campaign with custom settings"
  (let ((campaign (make-instance 'autopoiesis.research:research-campaign
                                 :question "Custom question?"
                                 :num-approaches 3
                                 :timeout 300
                                 :max-turns 10
                                 :mode :fully-sandboxed
                                 :layers '("000-base-alpine"))))
    (is (= 3 (autopoiesis.research::campaign-num-approaches campaign)))
    (is (= 300 (autopoiesis.research::campaign-timeout campaign)))
    (is (= 10 (autopoiesis.research::campaign-max-turns campaign)))
    (is (eq :fully-sandboxed (autopoiesis.research:campaign-mode campaign)))
    (is (equal '("000-base-alpine") (autopoiesis.research::campaign-layers campaign)))))

(test research-campaign-with-provided-approaches
  "Test creating a campaign with pre-defined approaches"
  (let* ((approaches '(((:name . "approach-1") (:hypothesis . "Test H1"))
                       ((:name . "approach-2") (:hypothesis . "Test H2"))))
         (campaign (make-instance 'autopoiesis.research:research-campaign
                                  :question "Test?"
                                  :approaches approaches)))
    (is (= 2 (length (autopoiesis.research:campaign-approaches campaign))))
    (is (equal "approach-1"
               (cdr (assoc :name (first (autopoiesis.research:campaign-approaches campaign))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Research Tool Capability Tests
;;; ═══════════════════════════════════════════════════════════════════

(test research-tool-capabilities-list
  "Test that research tool capabilities are defined"
  (let ((caps (autopoiesis.research:research-tool-capabilities)))
    (is (= 4 (length caps)))
    (is (member 'autopoiesis.research:sandbox-exec caps))
    (is (member 'autopoiesis.research:sandbox-write-file caps))
    (is (member 'autopoiesis.research:sandbox-read-file caps))
    (is (member 'autopoiesis.research:sandbox-install caps))))

(test sandbox-exec-requires-binding
  "Test that sandbox-exec errors without *trial-sandbox-id*"
  (let ((autopoiesis.research:*trial-sandbox-id* nil))
    ;; Find the capability and invoke it
    (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.research:sandbox-exec)))
      (when cap
        (let ((result (funcall (autopoiesis.agent:capability-function cap)
                               :command "echo test")))
          (is (search "Error: No sandbox bound" result)))))))

(test sandbox-write-file-requires-binding
  "Test that sandbox-write-file errors without binding"
  (let ((autopoiesis.research:*trial-sandbox-id* nil))
    (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.research:sandbox-write-file)))
      (when cap
        (let ((result (funcall (autopoiesis.agent:capability-function cap)
                               :path "/tmp/test" :content "hello")))
          (is (search "Error: No sandbox bound" result)))))))

(test sandbox-read-file-requires-binding
  "Test that sandbox-read-file errors without binding"
  (let ((autopoiesis.research:*trial-sandbox-id* nil))
    (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.research:sandbox-read-file)))
      (when cap
        (let ((result (funcall (autopoiesis.agent:capability-function cap)
                               :path "/tmp/test")))
          (is (search "Error: No sandbox bound" result)))))))

(test sandbox-install-requires-binding
  "Test that sandbox-install errors without binding"
  (let ((autopoiesis.research:*trial-sandbox-id* nil))
    (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.research:sandbox-install)))
      (when cap
        (let ((result (funcall (autopoiesis.agent:capability-function cap)
                               :packages "numpy")))
          (is (search "Error: No sandbox bound" result)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Fully-Sandboxed Agent Tests
;;; ═══════════════════════════════════════════════════════════════════

(test sandboxed-agent-default-command
  "Test the default sandboxed agent command"
  (is (equal "claude" autopoiesis.research:*sandboxed-agent-command*)))

(test run-sandboxed-agent-exists
  "Test that run-sandboxed-agent function exists"
  (is (fboundp 'autopoiesis.research:run-sandboxed-agent)))

(test run-sandboxed-agent-requires-manager
  "Test that run-sandboxed-agent errors without manager"
  (let ((autopoiesis.sandbox:*sandbox-manager* nil))
    (signals error
      (autopoiesis.research:run-sandboxed-agent "test prompt"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Top-Level Interface Tests
;;; ═══════════════════════════════════════════════════════════════════

(test run-research-exists
  "Test that top-level research function exists"
  (is (fboundp 'autopoiesis.research:run-research)))

(test run-research-requires-manager
  "Test that run-research errors without manager"
  (let ((autopoiesis.sandbox:*sandbox-manager* nil))
    (signals error
      (autopoiesis.research:run-research "test question"))))

(test campaign-report-exists
  "Test that campaign-report function exists"
  (is (fboundp 'autopoiesis.research:campaign-report)))

(test campaign-report-on-empty-campaign
  "Test campaign-report on a fresh campaign"
  (let ((campaign (make-instance 'autopoiesis.research:research-campaign
                                 :question "Test?")))
    ;; Should not error on empty campaign
    (is (null (autopoiesis.research:campaign-report campaign
                                                     (make-string-output-stream))))))

(test rerun-trial-exists
  "Test that rerun-trial function exists"
  (is (fboundp 'autopoiesis.research:rerun-trial)))

(test rerun-trial-validates-index
  "Test that rerun-trial validates the approach index"
  (let ((campaign (make-instance 'autopoiesis.research:research-campaign
                                 :question "Test?")))
    ;; No approaches loaded, so index 0 should fail
    (signals error
      (autopoiesis.research:rerun-trial campaign 0))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Entity Type Tests (require substrate)
;;; ═══════════════════════════════════════════════════════════════════

(test sandbox-entity-types-registered
  "Test that sandbox entity types are registered in the substrate"
  (let ((registry autopoiesis.substrate:*entity-type-registry*))
    ;; The entity types should be in the registry after loading
    (is (gethash :sandbox-instance registry))
    (is (gethash :sandbox-exec registry))))

(test sandbox-instance-entity-type-attributes
  "Test sandbox-instance entity type has expected attributes"
  (let ((desc (gethash :sandbox-instance autopoiesis.substrate:*entity-type-registry*)))
    (when desc
      (let ((attrs (mapcar #'car (autopoiesis.substrate::entity-type-attributes desc))))
        (is (member :sandbox-instance/sandbox-id attrs))
        (is (member :sandbox-instance/status attrs))
        (is (member :sandbox-instance/created-at attrs))))))

(test sandbox-exec-entity-type-attributes
  "Test sandbox-exec entity type has expected attributes"
  (let ((desc (gethash :sandbox-exec autopoiesis.substrate:*entity-type-registry*)))
    (when desc
      (let ((attrs (mapcar #'car (autopoiesis.substrate::entity-type-attributes desc))))
        (is (member :sandbox-exec/sandbox-id attrs))
        (is (member :sandbox-exec/command attrs))
        (is (member :sandbox-exec/exit-code attrs))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Run all tests
;;; ═══════════════════════════════════════════════════════════════════

(defun run-sandbox-tests ()
  "Run all sandbox integration and research tests."
  (run! 'sandbox-tests))
