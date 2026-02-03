;;;; backup.lisp - Backup and restore functionality
;;;;
;;;; Provides backup creation and restoration for snapshot stores.
;;;; Supports full backups, incremental backups, and point-in-time restore.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Backup Metadata
;;; ═══════════════════════════════════════════════════════════════════

(defclass backup-metadata ()
  ((id :initarg :id
       :accessor backup-id
       :documentation "Unique backup identifier")
   (timestamp :initarg :timestamp
              :accessor backup-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When the backup was created")
   (backup-type :initarg :backup-type
                :accessor backup-type
                :initform :full
                :documentation ":full or :incremental")
   (source-path :initarg :source-path
                :accessor backup-source-path
                :documentation "Path to the source store")
   (snapshot-count :initarg :snapshot-count
                   :accessor backup-snapshot-count
                   :initform 0
                   :documentation "Number of snapshots in backup")
   (parent-backup :initarg :parent-backup
                  :accessor backup-parent
                  :initform nil
                  :documentation "ID of parent backup for incremental")
   (checksum :initarg :checksum
             :accessor backup-checksum
             :initform nil
             :documentation "Checksum for integrity verification")
   (status :initarg :status
           :accessor backup-status
           :initform :pending
           :documentation ":pending :in-progress :completed :failed")
   (description :initarg :description
                :accessor backup-description
                :initform nil
                :documentation "Optional description"))
  (:documentation "Metadata for a backup archive."))

(defun make-backup-metadata (&key (type :full) source-path parent-backup description)
  "Create backup metadata."
  (make-instance 'backup-metadata
                 :id (autopoiesis.core:make-uuid)
                 :backup-type type
                 :source-path source-path
                 :parent-backup parent-backup
                 :description description))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backup Result
;;; ═══════════════════════════════════════════════════════════════════

(defclass backup-result ()
  ((success-p :initarg :success-p
              :accessor backup-success-p
              :initform nil
              :documentation "Whether backup succeeded")
   (metadata :initarg :metadata
             :accessor backup-result-metadata
             :documentation "Backup metadata")
   (backup-path :initarg :backup-path
                :accessor backup-result-path
                :documentation "Path where backup was stored")
   (errors :initarg :errors
           :accessor backup-errors
           :initform nil
           :documentation "List of errors encountered")
   (warnings :initarg :warnings
             :accessor backup-warnings
             :initform nil
             :documentation "List of warnings"))
  (:documentation "Result of a backup operation."))

(defun make-backup-result (&key success-p metadata backup-path errors warnings)
  "Create a backup result."
  (make-instance 'backup-result
                 :success-p success-p
                 :metadata metadata
                 :backup-path backup-path
                 :errors errors
                 :warnings warnings))

;;; ═══════════════════════════════════════════════════════════════════
;;; Restore Result
;;; ═══════════════════════════════════════════════════════════════════

(defclass restore-result ()
  ((success-p :initarg :success-p
              :accessor restore-success-p
              :initform nil
              :documentation "Whether restore succeeded")
   (snapshots-restored :initarg :snapshots-restored
                       :accessor restore-snapshot-count
                       :initform 0
                       :documentation "Number of snapshots restored")
   (target-path :initarg :target-path
                :accessor restore-target-path
                :documentation "Path where data was restored")
   (errors :initarg :errors
           :accessor restore-errors
           :initform nil
           :documentation "List of errors encountered")
   (warnings :initarg :warnings
             :accessor restore-warnings
             :initform nil
             :documentation "List of warnings"))
  (:documentation "Result of a restore operation."))

(defun make-restore-result (&key success-p snapshots-restored target-path errors warnings)
  "Create a restore result."
  (make-instance 'restore-result
                 :success-p success-p
                 :snapshots-restored snapshots-restored
                 :target-path target-path
                 :errors errors
                 :warnings warnings))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backup Directory Structure
;;; ═══════════════════════════════════════════════════════════════════

(defun backup-directory-path (backup-path backup-id)
  "Return the directory path for a specific backup."
  (merge-pathnames (format nil "~a/" backup-id) backup-path))

(defun backup-metadata-path (backup-dir)
  "Return the path to backup metadata file."
  (merge-pathnames "metadata.sexpr" backup-dir))

(defun backup-snapshots-path (backup-dir)
  "Return the path to backup snapshots directory."
  (merge-pathnames "snapshots/" backup-dir))

(defun backup-index-path (backup-dir)
  "Return the path to backup index file."
  (merge-pathnames "index.sexpr" backup-dir))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backup Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun metadata-to-sexpr (metadata)
  "Convert backup metadata to S-expression."
  `(backup-metadata
    :version 1
    :id ,(backup-id metadata)
    :timestamp ,(backup-timestamp metadata)
    :backup-type ,(backup-type metadata)
    :source-path ,(namestring (backup-source-path metadata))
    :snapshot-count ,(backup-snapshot-count metadata)
    :parent-backup ,(backup-parent metadata)
    :checksum ,(backup-checksum metadata)
    :status ,(backup-status metadata)
    :description ,(backup-description metadata)))

(defun sexpr-to-metadata (sexpr)
  "Reconstruct backup metadata from S-expression."
  (unless (and (listp sexpr) (eq (first sexpr) 'backup-metadata))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Invalid backup metadata S-expression"))
  (let ((plist (rest sexpr)))
    (make-instance 'backup-metadata
                   :id (getf plist :id)
                   :timestamp (getf plist :timestamp)
                   :backup-type (getf plist :backup-type)
                   :source-path (pathname (getf plist :source-path))
                   :snapshot-count (getf plist :snapshot-count)
                   :parent-backup (getf plist :parent-backup)
                   :checksum (getf plist :checksum)
                   :status (getf plist :status)
                   :description (getf plist :description))))

(defun save-backup-metadata (metadata backup-dir)
  "Save backup metadata to disk."
  (let ((path (backup-metadata-path backup-dir)))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create
                              :external-format :utf-8)
      (let ((*print-readably* t)
            (*print-circle* t)
            (*package* (find-package :autopoiesis.snapshot)))
        (prin1 (metadata-to-sexpr metadata) out)))))

(defun load-backup-metadata (backup-dir)
  "Load backup metadata from disk."
  (let ((path (backup-metadata-path backup-dir)))
    (unless (probe-file path)
      (return-from load-backup-metadata nil))
    (with-open-file (in path :direction :input :external-format :utf-8)
      (let ((*package* (find-package :autopoiesis.snapshot)))
        (sexpr-to-metadata (read in))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Checksum Calculation
;;; ═══════════════════════════════════════════════════════════════════

(defun calculate-backup-checksum (backup-dir)
  "Calculate checksum for backup integrity verification."
  (let ((digester (ironclad:make-digest :sha256))
        (snapshot-dir (backup-snapshots-path backup-dir)))
    (when (probe-file snapshot-dir)
      ;; Hash all snapshot files in sorted order for determinism
      (let ((files (sort (directory (merge-pathnames "*/*.sexpr" snapshot-dir))
                         #'string< :key #'namestring)))
        (dolist (file files)
          (with-open-file (in file :direction :input
                                   :element-type '(unsigned-byte 8))
            (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))))
              (loop for bytes-read = (read-sequence buffer in)
                    while (plusp bytes-read)
                    do (ironclad:update-digest digester buffer :end bytes-read)))))))
    (ironclad:byte-array-to-hex-string (ironclad:produce-digest digester))))

(defun verify-backup-checksum (backup-dir expected-checksum)
  "Verify backup integrity by comparing checksums."
  (let ((actual-checksum (calculate-backup-checksum backup-dir)))
    (string= actual-checksum expected-checksum)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Full Backup
;;; ═══════════════════════════════════════════════════════════════════

(defun create-backup (backup-path &key (store *snapshot-store*) description)
  "Create a full backup of the snapshot store.
   
   Arguments:
     backup-path - Directory to store backups
     store       - Snapshot store to backup (defaults to *snapshot-store*)
     description - Optional description for the backup
   
   Returns: backup-result with success status and metadata"
  (unless store
    (return-from create-backup
      (make-backup-result :success-p nil
                          :errors '("No snapshot store provided"))))
  
  (let* ((metadata (make-backup-metadata :type :full
                                         :source-path (store-base-path store)
                                         :description description))
         (backup-id (backup-id metadata))
         (backup-dir (backup-directory-path backup-path backup-id))
         (errors nil)
         (warnings nil)
         (snapshot-count 0))
    
    ;; Update status
    (setf (backup-status metadata) :in-progress)
    
    (handler-case
        (progn
          ;; Create backup directory structure
          (ensure-directories-exist backup-dir)
          (ensure-directories-exist (backup-snapshots-path backup-dir))
          
          ;; Copy all snapshots
          (let ((snapshot-ids (list-snapshots :store store)))
            (dolist (id snapshot-ids)
              (handler-case
                  (let ((snapshot (load-snapshot id store)))
                    (when snapshot
                      (copy-snapshot-to-backup snapshot backup-dir)
                      (incf snapshot-count)))
                (error (e)
                  (push (format nil "Failed to backup snapshot ~a: ~a" id e) warnings)))))
          
          ;; Save index
          (save-backup-index store backup-dir)
          
          ;; Update metadata
          (setf (backup-snapshot-count metadata) snapshot-count)
          (setf (backup-checksum metadata) (calculate-backup-checksum backup-dir))
          (setf (backup-status metadata) :completed)
          
          ;; Save metadata
          (save-backup-metadata metadata backup-dir)
          
          (make-backup-result :success-p t
                              :metadata metadata
                              :backup-path backup-dir
                              :warnings warnings))
      
      (error (e)
        (setf (backup-status metadata) :failed)
        (push (format nil "Backup failed: ~a" e) errors)
        ;; Try to save metadata even on failure
        (ignore-errors (save-backup-metadata metadata backup-dir))
        (make-backup-result :success-p nil
                            :metadata metadata
                            :backup-path backup-dir
                            :errors errors
                            :warnings warnings)))))

(defun copy-snapshot-to-backup (snapshot backup-dir)
  "Copy a single snapshot to backup directory."
  (let* ((id (snapshot-id snapshot))
         (prefix (subseq id 0 (min 2 (length id))))
         (target-dir (merge-pathnames (format nil "snapshots/~a/" prefix)
                                      backup-dir))
         (target-path (merge-pathnames (format nil "~a.sexpr" id) target-dir)))
    (ensure-directories-exist target-path)
    (with-open-file (out target-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      (let ((*print-readably* t)
            (*print-circle* t)
            (*print-length* nil)
            (*print-level* nil)
            (*package* (find-package :autopoiesis.core)))
        (prin1 (snapshot-to-sexpr snapshot) out)))))

(defun save-backup-index (store backup-dir)
  "Save store index to backup."
  (when (store-index store)
    (let ((index (store-index store))
          (path (backup-index-path backup-dir)))
      (ensure-directories-exist path)
      (with-open-file (out path :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create
                                :external-format :utf-8)
        (let ((*print-readably* t)
              (*print-circle* t)
              (*package* (find-package :autopoiesis.core)))
          (prin1
           `(snapshot-index
             :version 1
             :by-id ,(loop for k being the hash-keys of (index-by-id index)
                           using (hash-value v)
                           collect (cons k v))
             :by-parent ,(loop for k being the hash-keys of (index-by-parent index)
                               using (hash-value v)
                               when v collect (cons k v))
             :root-ids ,(index-root-ids index)
             :by-timestamp ,(index-by-timestamp index))
           out))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Incremental Backup
;;; ═══════════════════════════════════════════════════════════════════

(defun create-incremental-backup (backup-path parent-backup-id
                                  &key (store *snapshot-store*) description)
  "Create an incremental backup containing only new/changed snapshots.
   
   Arguments:
     backup-path      - Directory containing backups
     parent-backup-id - ID of the parent backup to base this on
     store            - Snapshot store to backup
     description      - Optional description
   
   Returns: backup-result"
  (unless store
    (return-from create-incremental-backup
      (make-backup-result :success-p nil
                          :errors '("No snapshot store provided"))))
  
  ;; Load parent backup metadata
  (let ((parent-dir (backup-directory-path backup-path parent-backup-id)))
    (unless (probe-file parent-dir)
      (return-from create-incremental-backup
        (make-backup-result :success-p nil
                            :errors (list (format nil "Parent backup not found: ~a"
                                                  parent-backup-id)))))
    
    (let* ((parent-metadata (load-backup-metadata parent-dir))
           (parent-ids (get-backup-snapshot-ids parent-dir))
           (metadata (make-backup-metadata :type :incremental
                                           :source-path (store-base-path store)
                                           :parent-backup parent-backup-id
                                           :description description))
           (backup-id (backup-id metadata))
           (backup-dir (backup-directory-path backup-path backup-id))
           (errors nil)
           (warnings nil)
           (snapshot-count 0))
      
      (setf (backup-status metadata) :in-progress)
      
      (handler-case
          (progn
            (ensure-directories-exist backup-dir)
            (ensure-directories-exist (backup-snapshots-path backup-dir))
            
            ;; Only backup snapshots not in parent
            (let ((current-ids (list-snapshots :store store)))
              (dolist (id current-ids)
                (unless (member id parent-ids :test #'string=)
                  (handler-case
                      (let ((snapshot (load-snapshot id store)))
                        (when snapshot
                          (copy-snapshot-to-backup snapshot backup-dir)
                          (incf snapshot-count)))
                    (error (e)
                      (push (format nil "Failed to backup snapshot ~a: ~a" id e) warnings))))))
            
            ;; Save index (full index for this point in time)
            (save-backup-index store backup-dir)
            
            ;; Update metadata
            (setf (backup-snapshot-count metadata) snapshot-count)
            (setf (backup-checksum metadata) (calculate-backup-checksum backup-dir))
            (setf (backup-status metadata) :completed)
            
            (save-backup-metadata metadata backup-dir)
            
            (make-backup-result :success-p t
                                :metadata metadata
                                :backup-path backup-dir
                                :warnings warnings))
        
        (error (e)
          (setf (backup-status metadata) :failed)
          (push (format nil "Incremental backup failed: ~a" e) errors)
          (ignore-errors (save-backup-metadata metadata backup-dir))
          (make-backup-result :success-p nil
                              :metadata metadata
                              :backup-path backup-dir
                              :errors errors
                              :warnings warnings))))))

(defun get-backup-snapshot-ids (backup-dir)
  "Get list of snapshot IDs in a backup."
  (let ((snapshot-dir (backup-snapshots-path backup-dir))
        (ids nil))
    (when (probe-file snapshot-dir)
      (dolist (subdir (directory (merge-pathnames "*/" snapshot-dir)))
        (dolist (file (directory (merge-pathnames "*.sexpr" subdir)))
          (push (pathname-name file) ids))))
    ids))

;;; ═══════════════════════════════════════════════════════════════════
;;; Restore Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun restore-backup (backup-path backup-id target-path
                       &key verify-checksum)
  "Restore a backup to a target directory.
   
   Arguments:
     backup-path      - Directory containing backups
     backup-id        - ID of backup to restore
     target-path      - Directory to restore to (will be created)
     verify-checksum  - If T, verify backup integrity before restore
   
   Returns: restore-result"
  (let ((backup-dir (backup-directory-path backup-path backup-id)))
    (unless (probe-file backup-dir)
      (return-from restore-backup
        (make-restore-result :success-p nil
                             :errors (list (format nil "Backup not found: ~a" backup-id)))))
    
    (let ((metadata (load-backup-metadata backup-dir))
          (errors nil)
          (warnings nil)
          (snapshot-count 0))
      
      ;; Verify checksum if requested
      (when verify-checksum
        (unless (verify-backup-checksum backup-dir (backup-checksum metadata))
          (return-from restore-backup
            (make-restore-result :success-p nil
                                 :errors '("Backup checksum verification failed")))))
      
      (handler-case
          (progn
            ;; For incremental backups, restore parent chain first
            (when (eq (backup-type metadata) :incremental)
              (let ((parent-id (backup-parent metadata)))
                (when parent-id
                  (let ((parent-result (restore-backup backup-path parent-id target-path
                                                       :verify-checksum verify-checksum)))
                    (unless (restore-success-p parent-result)
                      (return-from restore-backup parent-result))
                    (incf snapshot-count (restore-snapshot-count parent-result))
                    (setf warnings (append warnings (restore-warnings parent-result)))))))
            
            ;; Create target store structure
            (ensure-directories-exist target-path)
            (ensure-directories-exist (merge-pathnames "snapshots/" target-path))
            (ensure-directories-exist (merge-pathnames "index/" target-path))
            
            ;; Copy snapshots from backup
            (let ((snapshot-dir (backup-snapshots-path backup-dir)))
              (when (probe-file snapshot-dir)
                (dolist (subdir (directory (merge-pathnames "*/" snapshot-dir)))
                  (dolist (file (directory (merge-pathnames "*.sexpr" subdir)))
                    (handler-case
                        (progn
                          (copy-snapshot-file file target-path)
                          (incf snapshot-count))
                      (error (e)
                        (push (format nil "Failed to restore ~a: ~a"
                                      (pathname-name file) e)
                              warnings)))))))
            
            ;; Copy index
            (let ((backup-index (backup-index-path backup-dir))
                  (target-index (merge-pathnames "index/snapshots.idx" target-path)))
              (when (probe-file backup-index)
                (uiop:copy-file backup-index target-index)))
            
            (make-restore-result :success-p t
                                 :snapshots-restored snapshot-count
                                 :target-path target-path
                                 :warnings warnings))
        
        (error (e)
          (push (format nil "Restore failed: ~a" e) errors)
          (make-restore-result :success-p nil
                               :snapshots-restored snapshot-count
                               :target-path target-path
                               :errors errors
                               :warnings warnings))))))

(defun copy-snapshot-file (source-file target-path)
  "Copy a snapshot file to target store."
  (let* ((id (pathname-name source-file))
         (prefix (subseq id 0 (min 2 (length id))))
         (target-dir (merge-pathnames (format nil "snapshots/~a/" prefix) target-path))
         (target-file (merge-pathnames (format nil "~a.sexpr" id) target-dir)))
    (ensure-directories-exist target-file)
    (uiop:copy-file source-file target-file)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backup Management
;;; ═══════════════════════════════════════════════════════════════════

(defun list-backups (backup-path)
  "List all backups in a backup directory.
   
   Returns: List of backup-metadata objects, sorted by timestamp (newest first)"
  (unless (probe-file backup-path)
    (return-from list-backups nil))
  (let ((backups nil))
    (dolist (dir (directory (merge-pathnames "*/" backup-path)))
      (let ((metadata (load-backup-metadata dir)))
        (when metadata
          (push metadata backups))))
    (sort backups #'> :key #'backup-timestamp)))

(defun get-backup-info (backup-path backup-id)
  "Get detailed information about a specific backup.
   
   Returns: backup-metadata or NIL if not found"
  (let ((backup-dir (backup-directory-path backup-path backup-id)))
    (when (probe-file backup-dir)
      (load-backup-metadata backup-dir))))

(defun delete-backup (backup-path backup-id)
  "Delete a backup.
   
   Note: Will not delete if other backups depend on it (incremental chain).
   
   Returns: T if deleted, NIL otherwise"
  (let ((backup-dir (backup-directory-path backup-path backup-id)))
    (unless (probe-file backup-dir)
      (return-from delete-backup nil))
    
    ;; Check for dependent backups
    (let ((dependents (find-dependent-backups backup-path backup-id)))
      (when dependents
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "Cannot delete backup ~a: ~d backups depend on it"
                                backup-id (length dependents)))))
    
    ;; Delete the backup directory
    (uiop:delete-directory-tree backup-dir :validate t)
    t))

(defun find-dependent-backups (backup-path backup-id)
  "Find backups that depend on the given backup (incremental children)."
  (let ((dependents nil))
    (dolist (metadata (list-backups backup-path))
      (when (and (eq (backup-type metadata) :incremental)
                 (string= (backup-parent metadata) backup-id))
        (push metadata dependents)))
    dependents))

;;; ═══════════════════════════════════════════════════════════════════
;;; Point-in-Time Restore
;;; ═══════════════════════════════════════════════════════════════════

(defun find-backup-for-timestamp (backup-path timestamp)
  "Find the most recent backup before or at TIMESTAMP.
   
   Returns: backup-metadata or NIL"
  (let ((backups (list-backups backup-path)))
    (find-if (lambda (b) (<= (backup-timestamp b) timestamp)) backups)))

(defun restore-to-timestamp (backup-path timestamp target-path
                             &key verify-checksum)
  "Restore to a specific point in time.
   
   Arguments:
     backup-path     - Directory containing backups
     timestamp       - Target timestamp to restore to
     target-path     - Directory to restore to
     verify-checksum - If T, verify backup integrity
   
   Returns: restore-result"
  (let ((backup (find-backup-for-timestamp backup-path timestamp)))
    (if backup
        (restore-backup backup-path (backup-id backup) target-path
                        :verify-checksum verify-checksum)
        (make-restore-result :success-p nil
                             :errors (list (format nil "No backup found for timestamp ~a"
                                                   timestamp))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backup Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-backup (backup-path backup-id)
  "Validate a backup's integrity.
   
   Returns: consistency-result"
  (let ((backup-dir (backup-directory-path backup-path backup-id))
        (errors nil)
        (warnings nil)
        (details nil))
    
    (unless (probe-file backup-dir)
      (return-from validate-backup
        (make-consistency-result :backup-validation
                                 :passed-p nil
                                 :errors (list (format nil "Backup not found: ~a" backup-id)))))
    
    (let ((metadata (load-backup-metadata backup-dir)))
      (unless metadata
        (return-from validate-backup
          (make-consistency-result :backup-validation
                                   :passed-p nil
                                   :errors '("Could not load backup metadata"))))
      
      ;; Verify checksum
      (if (backup-checksum metadata)
          (if (verify-backup-checksum backup-dir (backup-checksum metadata))
              (push "Checksum verified" details)
              (push "Checksum mismatch - backup may be corrupted" errors))
          (push "No checksum stored - cannot verify integrity" warnings))
      
      ;; Verify snapshot count
      (let ((actual-count (length (get-backup-snapshot-ids backup-dir))))
        (if (= actual-count (backup-snapshot-count metadata))
            (push (format nil "Snapshot count verified: ~d" actual-count) details)
            (push (format nil "Snapshot count mismatch: expected ~d, found ~d"
                          (backup-snapshot-count metadata) actual-count)
                  errors)))
      
      ;; Verify all snapshot files are readable
      (let ((snapshot-dir (backup-snapshots-path backup-dir)))
        (when (probe-file snapshot-dir)
          (dolist (subdir (directory (merge-pathnames "*/" snapshot-dir)))
            (dolist (file (directory (merge-pathnames "*.sexpr" subdir)))
              (handler-case
                  (with-open-file (in file :direction :input :external-format :utf-8)
                    (let ((*package* (find-package :autopoiesis.core)))
                      (read in)))  ; Just verify it's readable
                (error (e)
                  (push (format nil "Corrupt snapshot file ~a: ~a"
                                (pathname-name file) e)
                        errors)))))))
      
      (make-consistency-result :backup-validation
                               :passed-p (null errors)
                               :errors errors
                               :warnings warnings
                               :details details))))
