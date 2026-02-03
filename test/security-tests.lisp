;;;; security-tests.lisp - Tests for security module
;;;;
;;;; Tests for the permission system and security hardening.
;;;; Phase 10.2: Security Hardening

(in-package #:autopoiesis.test)

(def-suite security-tests
  :description "Tests for security module")

(in-suite security-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Resource Tests
;;; ═══════════════════════════════════════════════════════════════════

(test resource-creation
  "Test creating resource instances"
  (let ((res (autopoiesis.security:make-resource :snapshot)))
    (is (eq :snapshot (autopoiesis.security:resource-type res)))
    (is (null (autopoiesis.security:resource-id res)))
    (is (null (autopoiesis.security:resource-owner res))))
  
  (let ((res (autopoiesis.security:make-resource :agent 
                                                  :id "agent-123"
                                                  :owner "admin")))
    (is (eq :agent (autopoiesis.security:resource-type res)))
    (is (string= "agent-123" (autopoiesis.security:resource-id res)))
    (is (string= "admin" (autopoiesis.security:resource-owner res)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Tests
;;; ═══════════════════════════════════════════════════════════════════

(test permission-creation
  "Test creating permission instances"
  (let ((perm (autopoiesis.security:make-permission 
               "read-snapshots" 
               autopoiesis.security:+resource-snapshot+
               (list autopoiesis.security:+action-read+))))
    (is (string= "read-snapshots" (autopoiesis.security:permission-name perm)))
    (is (eq :snapshot (autopoiesis.security:resource-type 
                       (autopoiesis.security:permission-resource perm))))
    (is (member :read (autopoiesis.security:permission-actions perm)))))

(test permission-templates
  "Test permission template functions"
  ;; Read-only permission
  (let ((perm (autopoiesis.security:make-read-only-permission 
               "test-read" :snapshot)))
    (is (equal '(:read) (autopoiesis.security:permission-actions perm))))
  
  ;; Execute-only permission
  (let ((perm (autopoiesis.security:make-execute-only-permission 
               "test-exec" :capability)))
    (is (equal '(:execute) (autopoiesis.security:permission-actions perm))))
  
  ;; Full access permission
  (let ((perm (autopoiesis.security:make-full-access-permission 
               "test-full" :agent)))
    (is (member :read (autopoiesis.security:permission-actions perm)))
    (is (member :write (autopoiesis.security:permission-actions perm)))
    (is (member :delete (autopoiesis.security:permission-actions perm)))
    (is (member :admin (autopoiesis.security:permission-actions perm)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Registry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test permission-registry-basic
  "Test basic permission registry operations"
  ;; Clear any existing permissions
  (autopoiesis.security:clear-agent-permissions)
  
  ;; Initially no permissions
  (is (null (autopoiesis.security:get-agent-permissions "test-agent")))
  
  ;; Grant a permission
  (let ((perm (autopoiesis.security:make-permission 
               "test-perm" :snapshot '(:read))))
    (autopoiesis.security:grant-permission "test-agent" perm)
    (is (= 1 (length (autopoiesis.security:get-agent-permissions "test-agent")))))
  
  ;; Revoke the permission
  (autopoiesis.security:revoke-permission "test-agent" "test-perm")
  (is (null (autopoiesis.security:get-agent-permissions "test-agent")))
  
  ;; Clean up
  (autopoiesis.security:clear-agent-permissions))

(test permission-registry-multiple
  "Test multiple permissions per agent"
  (autopoiesis.security:clear-agent-permissions)
  
  (let ((perm1 (autopoiesis.security:make-permission "perm1" :snapshot '(:read)))
        (perm2 (autopoiesis.security:make-permission "perm2" :agent '(:read :write)))
        (perm3 (autopoiesis.security:make-permission "perm3" :capability '(:execute))))
    
    (autopoiesis.security:grant-permission "multi-agent" perm1)
    (autopoiesis.security:grant-permission "multi-agent" perm2)
    (autopoiesis.security:grant-permission "multi-agent" perm3)
    
    (is (= 3 (length (autopoiesis.security:get-agent-permissions "multi-agent"))))
    
    ;; Revoke middle permission
    (autopoiesis.security:revoke-permission "multi-agent" "perm2")
    (is (= 2 (length (autopoiesis.security:get-agent-permissions "multi-agent")))))
  
  (autopoiesis.security:clear-agent-permissions))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Checking Tests
;;; ═══════════════════════════════════════════════════════════════════

(test check-permission-basic
  "Test basic permission checking"
  (autopoiesis.security:clear-agent-permissions)
  
  ;; Grant read permission on snapshots
  (let ((perm (autopoiesis.security:make-permission 
               "read-snaps" :snapshot '(:read))))
    (autopoiesis.security:grant-permission "checker-agent" perm))
  
  ;; Should have read permission
  (is-true (autopoiesis.security:check-permission 
            "checker-agent" :snapshot :read))
  
  ;; Should NOT have write permission
  (is-false (autopoiesis.security:check-permission 
             "checker-agent" :snapshot :write))
  
  ;; Should NOT have permission on different resource
  (is-false (autopoiesis.security:check-permission 
             "checker-agent" :agent :read))
  
  (autopoiesis.security:clear-agent-permissions))

(test check-permission-admin
  "Test that admin permission grants all actions"
  (autopoiesis.security:clear-agent-permissions)
  
  ;; Grant admin permission on agents
  (let ((perm (autopoiesis.security:make-permission 
               "admin-agents" :agent '(:admin))))
    (autopoiesis.security:grant-permission "admin-agent" perm))
  
  ;; Admin should grant all actions
  (is-true (autopoiesis.security:check-permission 
            "admin-agent" :agent :read))
  (is-true (autopoiesis.security:check-permission 
            "admin-agent" :agent :write))
  (is-true (autopoiesis.security:check-permission 
            "admin-agent" :agent :delete))
  (is-true (autopoiesis.security:check-permission 
            "admin-agent" :agent :execute))
  
  ;; But not on other resources
  (is-false (autopoiesis.security:check-permission 
             "admin-agent" :snapshot :read))
  
  (autopoiesis.security:clear-agent-permissions))

(test check-permission-with-resource-id
  "Test permission checking with specific resource IDs"
  (autopoiesis.security:clear-agent-permissions)
  
  ;; Grant permission on specific snapshot
  (let ((perm (autopoiesis.security:make-permission 
               "specific-snap" :snapshot '(:read :write)
               :resource-id "snap-001")))
    (autopoiesis.security:grant-permission "specific-agent" perm))
  
  ;; Should have permission on that specific snapshot
  (is-true (autopoiesis.security:check-permission 
            "specific-agent" :snapshot :read :resource-id "snap-001"))
  
  ;; Wildcard permission (no specific ID) should also match
  (is-true (autopoiesis.security:check-permission 
            "specific-agent" :snapshot :read))
  
  (autopoiesis.security:clear-agent-permissions))

(test has-permission-p-predicate
  "Test has-permission-p predicate function"
  (autopoiesis.security:clear-agent-permissions)
  
  (let ((perm (autopoiesis.security:make-permission 
               "test" :capability '(:execute))))
    (autopoiesis.security:grant-permission "pred-agent" perm))
  
  (is-true (autopoiesis.security:has-permission-p 
            "pred-agent" :capability :execute))
  (is-false (autopoiesis.security:has-permission-p 
             "pred-agent" :capability :delete))
  
  (autopoiesis.security:clear-agent-permissions))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Denied Condition Tests
;;; ═══════════════════════════════════════════════════════════════════

(test permission-denied-condition
  "Test permission-denied condition signaling"
  (autopoiesis.security:clear-agent-permissions)
  
  ;; No permissions granted - should signal error
  (signals autopoiesis.security:permission-denied
    (autopoiesis.security:with-permission-check ("denied-agent" :snapshot :write)
      (error "Should not reach here")))
  
  ;; Grant permission - should succeed
  (let ((perm (autopoiesis.security:make-permission 
               "allowed" :snapshot '(:write))))
    (autopoiesis.security:grant-permission "allowed-agent" perm))
  
  (finishes
    (autopoiesis.security:with-permission-check ("allowed-agent" :snapshot :write)
      :success))
  
  (autopoiesis.security:clear-agent-permissions))

(test permission-denied-condition-details
  "Test permission-denied condition contains correct details"
  (autopoiesis.security:clear-agent-permissions)
  
  (handler-case
      (autopoiesis.security:with-permission-check ("detail-agent" :file :delete 
                                                    :resource-id "important.txt")
        (error "Should not reach here"))
    (autopoiesis.security:permission-denied (c)
      (is (string= "detail-agent" (autopoiesis.security:permission-denied-agent c)))
      (is (eq :delete (autopoiesis.security:permission-denied-action c)))
      (is (eq :file (autopoiesis.security:resource-type 
                     (autopoiesis.security:permission-denied-resource c))))))
  
  (autopoiesis.security:clear-agent-permissions))

;;; ═══════════════════════════════════════════════════════════════════
;;; Permission Matrix Tests
;;; ═══════════════════════════════════════════════════════════════════

(test permission-matrix-basic
  "Test permission matrix creation and checking"
  (let* ((perms (list (autopoiesis.security:make-permission 
                       "p1" :snapshot '(:read :write))
                      (autopoiesis.security:make-permission 
                       "p2" :agent '(:read))))
         (matrix (autopoiesis.security:make-permission-matrix perms)))
    
    ;; Check granted permissions
    (is-true (autopoiesis.security:matrix-check matrix :snapshot :read))
    (is-true (autopoiesis.security:matrix-check matrix :snapshot :write))
    (is-true (autopoiesis.security:matrix-check matrix :agent :read))
    
    ;; Check non-granted permissions
    (is-false (autopoiesis.security:matrix-check matrix :snapshot :delete))
    (is-false (autopoiesis.security:matrix-check matrix :agent :write))))

(test permission-matrix-grant-revoke
  "Test granting and revoking in permission matrix"
  (let ((matrix (autopoiesis.security:make-permission-matrix)))
    ;; Initially empty
    (is-false (autopoiesis.security:matrix-check matrix :file :read))
    
    ;; Grant permission
    (autopoiesis.security:matrix-grant matrix :file :read)
    (is-true (autopoiesis.security:matrix-check matrix :file :read))
    
    ;; Revoke permission
    (autopoiesis.security:matrix-revoke matrix :file :read)
    (is-false (autopoiesis.security:matrix-check matrix :file :read))))

(test permission-matrix-admin-override
  "Test that admin in matrix grants all actions"
  (let* ((perms (list (autopoiesis.security:make-permission 
                       "admin" :network '(:admin))))
         (matrix (autopoiesis.security:make-permission-matrix perms)))
    
    ;; Admin should grant all actions
    (is-true (autopoiesis.security:matrix-check matrix :network :read))
    (is-true (autopoiesis.security:matrix-check matrix :network :write))
    (is-true (autopoiesis.security:matrix-check matrix :network :delete))))

(test permission-matrix-to-list
  "Test converting matrix back to list"
  (let ((matrix (autopoiesis.security:make-permission-matrix)))
    (autopoiesis.security:matrix-grant matrix :snapshot :read)
    (autopoiesis.security:matrix-grant matrix :snapshot :write)
    (autopoiesis.security:matrix-grant matrix :agent :execute)
    
    (let ((list (autopoiesis.security:matrix-to-list matrix)))
      (is (= 3 (length list)))
      (is (member '(:snapshot :read) list :test #'equal))
      (is (member '(:snapshot :write) list :test #'equal))
      (is (member '(:agent :execute) list :test #'equal)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Default Permission Sets Tests
;;; ═══════════════════════════════════════════════════════════════════

(test default-permission-sets
  "Test that default permission sets are defined correctly"
  ;; Default agent permissions
  (is (listp autopoiesis.security:*default-agent-permissions*))
  (is (plusp (length autopoiesis.security:*default-agent-permissions*)))
  
  ;; Admin permissions
  (is (listp autopoiesis.security:*admin-permissions*))
  (is (plusp (length autopoiesis.security:*admin-permissions*)))
  
  ;; Sandbox permissions
  (is (listp autopoiesis.security:*sandbox-permissions*))
  (is (plusp (length autopoiesis.security:*sandbox-permissions*))))

(test default-permissions-coverage
  "Test that default permissions cover expected resources"
  ;; Admin should have permissions for all resource types
  (let ((admin-resources (mapcar (lambda (p) 
                                   (autopoiesis.security:resource-type 
                                    (autopoiesis.security:permission-resource p)))
                                 autopoiesis.security:*admin-permissions*)))
    (is (member :snapshot admin-resources))
    (is (member :agent admin-resources))
    (is (member :capability admin-resources))
    (is (member :extension admin-resources))
    (is (member :file admin-resources))
    (is (member :network admin-resources))
    (is (member :system admin-resources))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Action Constants Tests
;;; ═══════════════════════════════════════════════════════════════════

(test action-constants
  "Test that action constants are defined"
  (is (eq :read autopoiesis.security:+action-read+))
  (is (eq :write autopoiesis.security:+action-write+))
  (is (eq :execute autopoiesis.security:+action-execute+))
  (is (eq :delete autopoiesis.security:+action-delete+))
  (is (eq :create autopoiesis.security:+action-create+))
  (is (eq :admin autopoiesis.security:+action-admin+)))

(test all-actions-function
  "Test all-actions returns all action constants"
  (let ((actions (autopoiesis.security:all-actions)))
    (is (= 6 (length actions)))
    (is (member :read actions))
    (is (member :write actions))
    (is (member :execute actions))
    (is (member :delete actions))
    (is (member :create actions))
    (is (member :admin actions))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Resource Type Constants Tests
;;; ═══════════════════════════════════════════════════════════════════

(test resource-type-constants
  "Test that resource type constants are defined"
  (is (eq :snapshot autopoiesis.security:+resource-snapshot+))
  (is (eq :agent autopoiesis.security:+resource-agent+))
  (is (eq :capability autopoiesis.security:+resource-capability+))
  (is (eq :extension autopoiesis.security:+resource-extension+))
  (is (eq :file autopoiesis.security:+resource-file+))
  (is (eq :network autopoiesis.security:+resource-network+))
  (is (eq :system autopoiesis.security:+resource-system+)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Integration Tests
;;; ═══════════════════════════════════════════════════════════════════

(test permission-workflow
  "Test a complete permission workflow"
  (autopoiesis.security:clear-agent-permissions)
  
  ;; Create a new agent with default permissions
  (dolist (perm autopoiesis.security:*default-agent-permissions*)
    (autopoiesis.security:grant-permission "workflow-agent" perm))
  
  ;; Agent should be able to read snapshots (from defaults)
  (is-true (autopoiesis.security:check-permission 
            "workflow-agent" :snapshot :read))
  
  ;; Agent should be able to execute capabilities (from defaults)
  (is-true (autopoiesis.security:check-permission 
            "workflow-agent" :capability :execute))
  
  ;; Agent should NOT be able to delete snapshots
  (is-false (autopoiesis.security:check-permission 
             "workflow-agent" :snapshot :delete))
  
  ;; Grant additional permission
  (autopoiesis.security:grant-permission 
   "workflow-agent"
   (autopoiesis.security:make-permission "write-snaps" :snapshot '(:write)))
  
  ;; Now agent can write snapshots
  (is-true (autopoiesis.security:check-permission 
            "workflow-agent" :snapshot :write))
  
  (autopoiesis.security:clear-agent-permissions))
