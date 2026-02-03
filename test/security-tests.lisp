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
    (autopoiesis.security:with-validated-input (x 123 (:string))
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
