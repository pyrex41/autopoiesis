;;;; consistency.lisp - State consistency checks for Autopoiesis
;;;;
;;;; Provides comprehensive consistency verification for:
;;;; - Snapshot DAG integrity (parent references)
;;;; - Content hash verification
;;;; - Branch head validity
;;;; - Index consistency with filesystem
;;;; - Agent state structure validation

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Consistency Check Results
;;; ═══════════════════════════════════════════════════════════════════

(defclass consistency-result ()
  ((check-name :initarg :check-name
               :accessor result-check-name
               :documentation "Name of the consistency check")
   (passed-p :initarg :passed-p
             :accessor result-passed-p
             :initform t
             :documentation "Whether the check passed")
   (errors :initarg :errors
           :accessor result-errors
           :initform nil
           :documentation "List of error descriptions")
   (warnings :initarg :warnings
             :accessor result-warnings
             :initform nil
             :documentation "List of warning descriptions")
   (details :initarg :details
            :accessor result-details
            :initform nil
            :documentation "Additional details about the check")
   (timestamp :initarg :timestamp
              :accessor result-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When the check was performed"))
  (:documentation "Result of a consistency check"))

(defun make-consistency-result (check-name &key (passed-p t) errors warnings details)
  "Create a consistency check result."
  (make-instance 'consistency-result
                 :check-name check-name
                 :passed-p passed-p
                 :errors errors
                 :warnings warnings
                 :details details))

(defmethod print-object ((result consistency-result) stream)
  (print-unreadable-object (result stream :type t)
    (format stream "~a: ~a~@[ (~d errors)~]~@[ (~d warnings)~]"
            (result-check-name result)
            (if (result-passed-p result) "PASS" "FAIL")
            (length (result-errors result))
            (length (result-warnings result)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Comprehensive Consistency Report
;;; ═══════════════════════════════════════════════════════════════════

(defclass consistency-report ()
  ((results :initarg :results
            :accessor report-results
            :initform nil
            :documentation "List of consistency-result objects")
   (overall-passed-p :initarg :overall-passed-p
                     :accessor report-passed-p
                     :initform t
                     :documentation "Whether all checks passed")
   (total-errors :initarg :total-errors
                 :accessor report-total-errors
                 :initform 0
                 :documentation "Total number of errors across all checks")
   (total-warnings :initarg :total-warnings
                   :accessor report-total-warnings
                   :initform 0
                   :documentation "Total number of warnings across all checks")
   (timestamp :initarg :timestamp
              :accessor report-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When the report was generated"))
  (:documentation "Comprehensive consistency check report"))

(defun make-consistency-report (results)
  "Create a consistency report from a list of results."
  (let ((total-errors 0)
        (total-warnings 0)
        (all-passed t))
    (dolist (result results)
      (incf total-errors (length (result-errors result)))
      (incf total-warnings (length (result-warnings result)))
      (unless (result-passed-p result)
        (setf all-passed nil)))
    (make-instance 'consistency-report
                   :results results
                   :overall-passed-p all-passed
                   :total-errors total-errors
                   :total-warnings total-warnings)))

(defmethod print-object ((report consistency-report) stream)
  (print-unreadable-object (report stream :type t)
    (format stream "~a: ~d checks, ~d errors, ~d warnings"
            (if (report-passed-p report) "PASS" "FAIL")
            (length (report-results report))
            (report-total-errors report)
            (report-total-warnings report))))

;;; ═══════════════════════════════════════════════════════════════════
;;; DAG Integrity Checks
;;; ═══════════════════════════════════════════════════════════════════

(defun check-dag-integrity (&optional (store *snapshot-store*))
  "Verify snapshot DAG integrity.
   
   Checks:
   - All parent references point to existing snapshots
   - No cycles in the DAG
   - All snapshots are reachable from roots
   
   Returns: consistency-result"
  (unless store
    (return-from check-dag-integrity
      (make-consistency-result :dag-integrity
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (all-ids (list-snapshots :store store))
        (visited (make-hash-table :test 'equal))
        (in-path (make-hash-table :test 'equal)))
    
    ;; Check parent references exist
    (dolist (id all-ids)
      (let* ((meta (when (store-index store)
                     (gethash id (index-by-id (store-index store)))))
             (parent-id (when meta (getf meta :parent))))
        (when (and parent-id (not (member parent-id all-ids :test #'equal)))
          (push (format nil "Snapshot ~a references non-existent parent ~a" id parent-id)
                errors))))
    
    ;; Check for cycles using DFS
    (labels ((check-cycle (id path)
               (cond
                 ((gethash id in-path)
                  (push (format nil "Cycle detected: ~{~a~^ -> ~} -> ~a"
                                (reverse path) id)
                        errors)
                  nil)
                 ((gethash id visited)
                  t)
                 (t
                  (setf (gethash id in-path) t)
                  (let* ((meta (when (store-index store)
                                 (gethash id (index-by-id (store-index store)))))
                         (parent-id (when meta (getf meta :parent))))
                    (when parent-id
                      (check-cycle parent-id (cons id path))))
                  (setf (gethash id visited) t)
                  (remhash id in-path)
                  t))))
      (dolist (id all-ids)
        (unless (gethash id visited)
          (check-cycle id nil))))
    
    ;; Count roots and check reachability
    (let ((root-count 0)
          (reachable (make-hash-table :test 'equal)))
      (dolist (id all-ids)
        (let* ((meta (when (store-index store)
                       (gethash id (index-by-id (store-index store)))))
               (parent-id (when meta (getf meta :parent))))
          (unless parent-id
            (incf root-count)
            ;; Mark all descendants as reachable
            (labels ((mark-reachable (snap-id)
                       (unless (gethash snap-id reachable)
                         (setf (gethash snap-id reachable) t)
                         (dolist (child-id (snapshot-children snap-id store))
                           (mark-reachable child-id)))))
              (mark-reachable id)))))
      
      (push (format nil "Found ~d root snapshot(s)" root-count) details)
      
      ;; Check for unreachable snapshots
      (dolist (id all-ids)
        (unless (gethash id reachable)
          (push (format nil "Snapshot ~a is not reachable from any root" id)
                warnings))))
    
    (push (format nil "Checked ~d snapshots" (length all-ids)) details)
    
    (make-consistency-result :dag-integrity
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Content Hash Verification
;;; ═══════════════════════════════════════════════════════════════════

(defun check-content-hashes (&key (store *snapshot-store*) (sample-size nil))
  "Verify content hashes match actual content.
   
   Arguments:
     store - Snapshot store to check
     sample-size - If provided, only check this many random snapshots
   
   Returns: consistency-result"
  (unless store
    (return-from check-content-hashes
      (make-consistency-result :content-hashes
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (all-ids (list-snapshots :store store))
        (checked 0)
        (mismatches 0))
    
    ;; Optionally sample
    (when (and sample-size (< sample-size (length all-ids)))
      (setf all-ids (subseq (alexandria:shuffle (copy-list all-ids)) 0 sample-size))
      (push (format nil "Sampling ~d of ~d snapshots" sample-size (length all-ids)) details))
    
    (dolist (id all-ids)
      (let ((snapshot (load-snapshot id store)))
        (when snapshot
          (incf checked)
          (let* ((stored-hash (snapshot-hash snapshot))
                 (computed-hash (autopoiesis.core:sexpr-hash (snapshot-agent-state snapshot))))
            (unless (equal stored-hash computed-hash)
              (incf mismatches)
              (push (format nil "Hash mismatch for ~a: stored=~a, computed=~a"
                            id stored-hash computed-hash)
                    errors))))))
    
    (push (format nil "Verified ~d snapshots, ~d mismatches" checked mismatches) details)
    
    (make-consistency-result :content-hashes
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Consistency
;;; ═══════════════════════════════════════════════════════════════════

(defun check-branch-consistency (&key (registry *branch-registry*) (store *snapshot-store*))
  "Verify branch heads point to valid snapshots.
   
   Returns: consistency-result"
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (branch-count 0))
    
    (maphash (lambda (name branch)
               (incf branch-count)
               (let ((head-id (branch-head branch)))
                 (cond
                   ((null head-id)
                    (push (format nil "Branch ~a has no head" name) warnings))
                   ((and store (not (snapshot-exists-p head-id store)))
                    (push (format nil "Branch ~a head ~a does not exist" name head-id)
                          errors)))))
             registry)
    
    (push (format nil "Checked ~d branches" branch-count) details)
    
    (make-consistency-result :branch-consistency
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Index Consistency
;;; ═══════════════════════════════════════════════════════════════════

(defun check-index-consistency (&optional (store *snapshot-store*))
  "Verify index is consistent with filesystem.
   
   Checks:
   - All indexed snapshots exist on disk
   - All disk snapshots are in index
   - Parent relationships in index match actual snapshots
   
   Returns: consistency-result"
  (unless store
    (return-from check-index-consistency
      (make-consistency-result :index-consistency
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (unless (store-index store)
    (return-from check-index-consistency
      (make-consistency-result :index-consistency
                               :passed-p nil
                               :errors '("No index loaded"))))
  
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (index (store-index store))
        (indexed-ids (make-hash-table :test 'equal))
        (disk-ids (make-hash-table :test 'equal)))
    
    ;; Collect indexed IDs
    (maphash (lambda (id meta)
               (declare (ignore meta))
               (setf (gethash id indexed-ids) t))
             (index-by-id index))
    
    ;; Scan disk for actual files
    (let ((snapshot-dir (merge-pathnames "snapshots/" (store-base-path store))))
      (when (probe-file snapshot-dir)
        (dolist (subdir (directory (merge-pathnames "*/" snapshot-dir)))
          (dolist (file (directory (merge-pathnames "*.sexpr" subdir)))
            (let ((id (pathname-name file)))
              (setf (gethash id disk-ids) t))))))
    
    ;; Check indexed but not on disk
    (maphash (lambda (id v)
               (declare (ignore v))
               (unless (gethash id disk-ids)
                 (push (format nil "Indexed snapshot ~a not found on disk" id) errors)))
             indexed-ids)
    
    ;; Check on disk but not indexed
    (maphash (lambda (id v)
               (declare (ignore v))
               (unless (gethash id indexed-ids)
                 (push (format nil "Disk snapshot ~a not in index" id) warnings)))
             disk-ids)
    
    ;; Verify parent relationships
    (maphash (lambda (id meta)
               (let ((indexed-parent (getf meta :parent)))
                 (when indexed-parent
                   (let ((snapshot (load-snapshot id store)))
                     (when snapshot
                       (unless (equal indexed-parent (snapshot-parent snapshot))
                         (push (format nil "Parent mismatch for ~a: index=~a, actual=~a"
                                       id indexed-parent (snapshot-parent snapshot))
                               errors)))))))
             (index-by-id index))
    
    (push (format nil "Index: ~d entries, Disk: ~d files"
                  (hash-table-count indexed-ids)
                  (hash-table-count disk-ids))
          details)
    
    (make-consistency-result :index-consistency
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent State Structure Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun check-agent-state-structure (snapshot)
  "Verify agent state in SNAPSHOT has valid structure.
   
   Returns: consistency-result"
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (state (snapshot-agent-state snapshot)))
    
    (cond
      ((null state)
       (push "Agent state is nil" warnings))
      ((not (listp state))
       (push (format nil "Agent state is not a list: ~a" (type-of state)) errors))
      (t
       ;; Check for expected structure
       (let ((has-id nil)
             (has-state nil)
             (has-thoughts nil))
         (when (and (listp state) (> (length state) 1))
           (let ((plist (rest state)))
             (when (getf plist :id) (setf has-id t))
             (when (getf plist :state) (setf has-state t))
             (when (getf plist :thought-stream) (setf has-thoughts t))))
         
         (unless has-id
           (push "Agent state missing :id" warnings))
         (unless has-state
           (push "Agent state missing :state" warnings))
         (unless has-thoughts
           (push "Agent state missing :thought-stream" warnings))
         
         (push (format nil "State has ~d top-level elements"
                       (if (listp state) (length state) 0))
               details))))
    
    (make-consistency-result :agent-state-structure
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

(defun check-all-agent-states (&key (store *snapshot-store*) (sample-size nil))
  "Check agent state structure for all (or sampled) snapshots.
   
   Returns: consistency-result"
  (unless store
    (return-from check-all-agent-states
      (make-consistency-result :all-agent-states
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (all-ids (list-snapshots :store store))
        (checked 0)
        (invalid 0))
    
    ;; Optionally sample
    (when (and sample-size (< sample-size (length all-ids)))
      (setf all-ids (subseq (alexandria:shuffle (copy-list all-ids)) 0 sample-size)))
    
    (dolist (id all-ids)
      (let ((snapshot (load-snapshot id store)))
        (when snapshot
          (incf checked)
          (let ((result (check-agent-state-structure snapshot)))
            (unless (result-passed-p result)
              (incf invalid)
              (dolist (err (result-errors result))
                (push (format nil "~a: ~a" id err) errors)))
            (dolist (warn (result-warnings result))
              (push (format nil "~a: ~a" id warn) warnings))))))
    
    (push (format nil "Checked ~d snapshots, ~d invalid" checked invalid) details)
    
    (make-consistency-result :all-agent-states
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Timestamp Consistency
;;; ═══════════════════════════════════════════════════════════════════

(defun check-timestamp-ordering (&optional (store *snapshot-store*))
  "Verify timestamps are consistent with DAG structure.
   
   A child snapshot should have a timestamp >= its parent.
   
   Returns: consistency-result"
  (unless store
    (return-from check-timestamp-ordering
      (make-consistency-result :timestamp-ordering
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (let ((errors nil)
        (warnings nil)
        (details nil)
        (all-ids (list-snapshots :store store))
        (violations 0))
    
    (dolist (id all-ids)
      (let* ((meta (when (store-index store)
                     (gethash id (index-by-id (store-index store)))))
             (timestamp (when meta (getf meta :timestamp)))
             (parent-id (when meta (getf meta :parent))))
        (when parent-id
          (let* ((parent-meta (gethash parent-id (index-by-id (store-index store))))
                 (parent-timestamp (when parent-meta (getf parent-meta :timestamp))))
            (when (and timestamp parent-timestamp (< timestamp parent-timestamp))
              (incf violations)
              (push (format nil "Snapshot ~a (t=~,3f) has earlier timestamp than parent ~a (t=~,3f)"
                            id timestamp parent-id parent-timestamp)
                    errors))))))
    
    (push (format nil "Checked ~d snapshots, ~d timestamp violations"
                  (length all-ids) violations)
          details)
    
    (make-consistency-result :timestamp-ordering
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :warnings (nreverse warnings)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Comprehensive Consistency Check
;;; ═══════════════════════════════════════════════════════════════════

(defun run-consistency-checks (&key (store *snapshot-store*)
                                    (branch-registry *branch-registry*)
                                    (checks :all)
                                    (sample-size nil))
  "Run comprehensive consistency checks.
   
   Arguments:
     store - Snapshot store to check
     branch-registry - Branch registry to check
     checks - :all or list of check names (:dag :hashes :branches :index :states :timestamps)
     sample-size - For expensive checks, limit to this many samples
   
   Returns: consistency-report"
  (let ((results nil)
        (check-list (if (eq checks :all)
                        '(:dag :hashes :branches :index :states :timestamps)
                        checks)))
    
    (when (member :dag check-list)
      (push (check-dag-integrity store) results))
    
    (when (member :hashes check-list)
      (push (check-content-hashes :store store :sample-size sample-size) results))
    
    (when (member :branches check-list)
      (push (check-branch-consistency :registry branch-registry :store store) results))
    
    (when (member :index check-list)
      (push (check-index-consistency store) results))
    
    (when (member :states check-list)
      (push (check-all-agent-states :store store :sample-size sample-size) results))
    
    (when (member :timestamps check-list)
      (push (check-timestamp-ordering store) results))
    
    (make-consistency-report (nreverse results))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Repair Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun repair-index (&optional (store *snapshot-store*))
  "Rebuild index from disk to fix index inconsistencies.
   
   Returns: consistency-result of the repair operation"
  (unless store
    (return-from repair-index
      (make-consistency-result :repair-index
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (let ((details nil))
    (handler-case
        (progn
          (push "Rebuilding index from disk..." details)
          (rebuild-store-index store)
          (push "Index rebuild complete" details)
          (push (format nil "Index now contains ~d entries"
                        (hash-table-count (index-by-id (store-index store))))
                details)
          (make-consistency-result :repair-index
                                   :passed-p t
                                   :details (nreverse details)))
      (error (e)
        (push (format nil "Repair failed: ~a" e) details)
        (make-consistency-result :repair-index
                                 :passed-p nil
                                 :errors (list (format nil "~a" e))
                                 :details (nreverse details))))))

(defun repair-orphaned-snapshots (&optional (store *snapshot-store*))
  "Handle orphaned snapshots (those with invalid parent references).
   
   Options:
   - Set parent to nil (make them roots)
   - Delete them
   
   This function sets them as roots.
   
   Returns: consistency-result"
  (unless store
    (return-from repair-orphaned-snapshots
      (make-consistency-result :repair-orphans
                               :passed-p nil
                               :errors '("No snapshot store provided"))))
  
  (let ((errors nil)
        (details nil)
        (repaired 0)
        (all-ids (list-snapshots :store store)))
    
    (dolist (id all-ids)
      (let ((snapshot (load-snapshot id store)))
        (when snapshot
          (let ((parent-id (snapshot-parent snapshot)))
            (when (and parent-id (not (snapshot-exists-p parent-id store)))
              (handler-case
                  (progn
                    ;; Set parent to nil
                    (setf (snapshot-parent snapshot) nil)
                    ;; Re-save
                    (save-snapshot snapshot store)
                    (incf repaired)
                    (push (format nil "Repaired orphan ~a (was parent ~a)" id parent-id)
                          details))
                (error (e)
                  (push (format nil "Failed to repair ~a: ~a" id e) errors))))))))
    
    (push (format nil "Repaired ~d orphaned snapshots" repaired) details)
    
    (make-consistency-result :repair-orphans
                             :passed-p (null errors)
                             :errors (nreverse errors)
                             :details (nreverse details))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Reporting Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun print-consistency-report (report &optional (stream *standard-output*))
  "Print a human-readable consistency report."
  (format stream "~&═══════════════════════════════════════════════════════════════~%")
  (format stream "CONSISTENCY CHECK REPORT~%")
  (format stream "Generated: ~a~%" (report-timestamp report))
  (format stream "Overall: ~a~%" (if (report-passed-p report) "PASS" "FAIL"))
  (format stream "Total Errors: ~d~%" (report-total-errors report))
  (format stream "Total Warnings: ~d~%" (report-total-warnings report))
  (format stream "═══════════════════════════════════════════════════════════════~%")
  
  (dolist (result (report-results report))
    (format stream "~%─── ~a ───~%" (result-check-name result))
    (format stream "Status: ~a~%" (if (result-passed-p result) "PASS" "FAIL"))
    
    (when (result-details result)
      (format stream "Details:~%")
      (dolist (detail (result-details result))
        (format stream "  • ~a~%" detail)))
    
    (when (result-errors result)
      (format stream "Errors:~%")
      (dolist (err (result-errors result))
        (format stream "  ✗ ~a~%" err)))
    
    (when (result-warnings result)
      (format stream "Warnings:~%")
      (dolist (warn (result-warnings result))
        (format stream "  ⚠ ~a~%" warn))))
  
  (format stream "~%═══════════════════════════════════════════════════════════════~%"))

(defun consistency-report-to-sexpr (report)
  "Convert consistency report to S-expression for serialization."
  `(consistency-report
    :timestamp ,(report-timestamp report)
    :passed-p ,(report-passed-p report)
    :total-errors ,(report-total-errors report)
    :total-warnings ,(report-total-warnings report)
    :results ,(mapcar (lambda (r)
                        `(result
                          :check-name ,(result-check-name r)
                          :passed-p ,(result-passed-p r)
                          :errors ,(result-errors r)
                          :warnings ,(result-warnings r)
                          :details ,(result-details r)
                          :timestamp ,(result-timestamp r)))
                      (report-results report))))
