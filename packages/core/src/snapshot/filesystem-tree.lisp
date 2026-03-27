;;;; filesystem-tree.lisp - Content-addressed filesystem tree operations
;;;;
;;;; Bridges the gap between real filesystems and the snapshot DAG.
;;;; Provides: scan (directory → tree), diff (tree × tree → changeset),
;;;; materialize (tree → directory), and Merkle root hashing.
;;;;
;;;; Tree entries are S-expressions for seamless integration with the
;;;; existing snapshot infrastructure:
;;;;   (:file "path" :hash "sha256..." :mode 33188 :size 1234 :mtime 1711324800)
;;;;   (:directory "path" :mode 16877 :children ((:file ...) ...))

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Entry Constructors
;;; ═══════════════════════════════════════════════════════════════════

(defun make-file-entry (path hash mode size mtime)
  "Create a tree entry for a regular file."
  (list :file path :hash hash :mode mode :size size :mtime mtime))

(defun make-directory-entry (path mode)
  "Create a tree entry for a directory."
  (list :directory path :mode mode))

(defun make-symlink-entry (path target mode)
  "Create a tree entry for a symbolic link."
  (list :symlink path :target target :mode mode))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Entry Accessors
;;; ═══════════════════════════════════════════════════════════════════

(defun entry-type (entry)
  "Return the type of a tree entry (:file, :directory, or :symlink)."
  (first entry))

(defun entry-path (entry)
  "Return the path of a tree entry."
  (second entry))

(defun entry-hash (entry)
  "Return the content hash of a file entry."
  (getf (cddr entry) :hash))

(defun entry-mode (entry)
  "Return the POSIX mode of a tree entry."
  (getf (cddr entry) :mode))

(defun entry-size (entry)
  "Return the size of a file entry."
  (getf (cddr entry) :size))

(defun entry-mtime (entry)
  "Return the modification time of a file entry."
  (getf (cddr entry) :mtime))

(defun entry-target (entry)
  "Return the target of a symlink entry."
  (getf (cddr entry) :target))

;;; ═══════════════════════════════════════════════════════════════════
;;; Directory Scanning
;;; ═══════════════════════════════════════════════════════════════════

(defun scan-directory (root-path content-store &key (exclude nil))
  "Scan ROOT-PATH recursively, hash all files into CONTENT-STORE.
   Returns a sorted list of tree entries.

   EXCLUDE is a list of relative path prefixes to skip (e.g. '(\".git\" \"node_modules\")).

   Each file's content is stored in the content store (deduplication automatic).
   The returned tree entries reference content by hash."
  (let ((entries '())
        (root (namestring (truename root-path))))
    ;; Ensure root ends with /
    (unless (char= (char root (1- (length root))) #\/)
      (setf root (concatenate 'string root "/")))
    (scan-directory-recursive root root content-store exclude entries)
    ;; Sort by path for deterministic Merkle root
    (sort entries #'string< :key #'entry-path)))

(defun scan-directory-recursive (current-path root-path content-store exclude entries-acc)
  "Recursively scan CURRENT-PATH, accumulating entries.
   ENTRIES-ACC is modified in place (push onto the list stored in caller)."
  (let ((relative (enough-namestring current-path root-path)))
    ;; Check exclusions
    (when (and exclude
               (some (lambda (prefix)
                       (let ((rel-str (namestring relative)))
                         (or (string= rel-str prefix)
                             (and (> (length rel-str) (length prefix))
                                  (string= rel-str prefix
                                           :end1 (length prefix))))))
                     exclude))
      (return-from scan-directory-recursive entries-acc))
    ;; Process directory contents
    (dolist (entry (uiop:directory-files current-path))
      (let* ((entry-path (namestring entry))
             (rel-path (enough-namestring entry-path root-path))
             (rel-str (namestring rel-path)))
        ;; Skip excluded paths
        (unless (and exclude
                     (some (lambda (prefix)
                             (or (string= rel-str prefix)
                                 (and (> (length rel-str) (length prefix))
                                      (string= rel-str prefix
                                               :end1 (length prefix)))))
                           exclude))
          (cond
            ;; Symbolic link
            ((uiop:file-exists-p entry) ;; regular file
             (let* ((bytes (read-file-bytes entry-path))
                    (hash (store-put-blob content-store bytes))
                    (stat-mode (or (ignore-errors
                                     #+sbcl (sb-posix:stat-mode
                                             (sb-posix:stat entry-path))
                                     #-sbcl 33188)
                                   33188))
                    (stat-size (length bytes))
                    (stat-mtime (or (ignore-errors (file-write-date entry))
                                    (get-universal-time))))
               (push (make-file-entry rel-str hash stat-mode stat-size stat-mtime)
                     (cdr entries-acc))))))))
    ;; Process subdirectories
    (dolist (subdir (uiop:subdirectories current-path))
      (let* ((subdir-path (namestring subdir))
             (rel-path (enough-namestring subdir-path root-path))
             (rel-str (namestring rel-path)))
        (unless (and exclude
                     (some (lambda (prefix)
                             (or (string= rel-str prefix)
                                 (and (> (length rel-str) (length prefix))
                                      (string= rel-str prefix
                                               :end1 (length prefix)))))
                           exclude))
          (let ((stat-mode (or (ignore-errors
                                 #+sbcl (sb-posix:stat-mode
                                         (sb-posix:stat subdir-path))
                                 #-sbcl 16877)
                               16877)))
            (push (make-directory-entry rel-str stat-mode)
                  (cdr entries-acc)))
          (scan-directory-recursive subdir-path root-path
                                    content-store exclude entries-acc))))
    entries-acc))

(defun read-file-bytes (path)
  "Read a file as a byte vector."
  (with-open-file (stream path
                          :direction :input
                          :element-type '(unsigned-byte 8))
    (let* ((size (file-length stream))
           (buffer (make-array size :element-type '(unsigned-byte 8))))
      (read-sequence buffer stream)
      buffer)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Simplified Scanning (non-recursive accumulator)
;;; ═══════════════════════════════════════════════════════════════════

(defun scan-directory-flat (root-path content-store &key (exclude nil))
  "Scan ROOT-PATH, return sorted flat list of tree entries.
   Simpler implementation using UIOP for directory walking."
  (let ((entries '())
        (root (namestring (truename root-path))))
    (unless (char= (char root (1- (length root))) #\/)
      (setf root (concatenate 'string root "/")))
    ;; Walk all files
    (uiop:collect-sub*directories
     (pathname root)
     ;; Collect test: always true (collect all dirs)
     (constantly t)
     ;; Recurse test: check exclusions
     (lambda (dir)
       (let ((rel (enough-namestring (namestring dir) root)))
         (not (and exclude
                   (some (lambda (prefix)
                           (let ((rel-str (namestring rel)))
                             (or (string= rel-str prefix)
                                 (and (> (length rel-str) (length prefix))
                                      (string= rel-str prefix
                                               :end1 (length prefix))))))
                         exclude)))))
     ;; Collector: process each directory
     (lambda (dir)
       (let* ((dir-path (namestring dir))
              (rel-dir (enough-namestring dir-path root))
              (rel-dir-str (namestring rel-dir)))
         ;; Add directory entry (skip root itself)
         (when (and (> (length rel-dir-str) 0)
                    (not (string= rel-dir-str "")))
           (push (make-directory-entry
                  rel-dir-str
                  (or (ignore-errors
                        #+sbcl (sb-posix:stat-mode (sb-posix:stat dir-path))
                        #-sbcl 16877)
                      16877))
                 entries))
         ;; Add file entries
         (dolist (file (uiop:directory-files dir))
           (let* ((file-path (namestring file))
                  (rel-file (namestring (enough-namestring file-path root))))
             (when (uiop:file-exists-p file)
               (let* ((bytes (read-file-bytes file-path))
                      (hash (store-put-blob content-store bytes))
                      (stat-mode (or (ignore-errors
                                       #+sbcl (sb-posix:stat-mode
                                               (sb-posix:stat file-path))
                                       #-sbcl 33188)
                                     33188))
                      (stat-mtime (or (ignore-errors (file-write-date file))
                                      (get-universal-time))))
                 (push (make-file-entry rel-file hash stat-mode
                                        (length bytes) stat-mtime)
                       entries))))))))
    ;; Sort by path for deterministic ordering
    (sort entries #'string< :key #'entry-path)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Merkle Root Hash
;;; ═══════════════════════════════════════════════════════════════════

(defun tree-hash (entries)
  "Compute Merkle root hash of a sorted list of tree entries.
   The hash commits to all paths, content hashes, modes, and sizes.
   Same entries always produce the same root hash (deterministic)."
  (let ((digester (ironclad:make-digest :sha256)))
    (dolist (entry entries)
      (let ((canonical (canonical-entry-string entry)))
        (ironclad:update-digest
         digester
         (babel:string-to-octets canonical :encoding :utf-8))))
    (ironclad:byte-array-to-hex-string
     (ironclad:produce-digest digester))))

(defun canonical-entry-string (entry)
  "Produce a canonical string for a tree entry (for Merkle hashing).
   Format: TYPE:PATH:HASH:MODE:SIZE"
  (ecase (entry-type entry)
    (:file (format nil "F:~A:~A:~D:~D"
                   (entry-path entry)
                   (entry-hash entry)
                   (entry-mode entry)
                   (entry-size entry)))
    (:directory (format nil "D:~A:~D"
                        (entry-path entry)
                        (entry-mode entry)))
    (:symlink (format nil "L:~A:~A:~D"
                      (entry-path entry)
                      (entry-target entry)
                      (entry-mode entry)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Diffing
;;; ═══════════════════════════════════════════════════════════════════

(defun tree-diff (old-entries new-entries)
  "Compute diff between two sorted tree entry lists.
   Returns a list of change records:
     (:added entry)
     (:removed entry)
     (:modified old-entry new-entry)

   Both inputs must be sorted by path (as returned by scan-directory)."
  (let ((changes '())
        (old-map (make-hash-table :test 'equal))
        (new-map (make-hash-table :test 'equal)))
    ;; Index by path
    (dolist (e old-entries)
      (setf (gethash (entry-path e) old-map) e))
    (dolist (e new-entries)
      (setf (gethash (entry-path e) new-map) e))
    ;; Find removed and modified
    (maphash (lambda (path old-entry)
               (let ((new-entry (gethash path new-map)))
                 (cond
                   ((null new-entry)
                    (push (list :removed old-entry) changes))
                   ((not (entries-equal-p old-entry new-entry))
                    (push (list :modified old-entry new-entry) changes)))))
             old-map)
    ;; Find added
    (maphash (lambda (path new-entry)
               (unless (gethash path old-map)
                 (push (list :added new-entry) changes)))
             new-map)
    ;; Sort changes by path for deterministic output
    (sort changes #'string< :key (lambda (c) (entry-path (if (eq (first c) :modified)
                                                              (second c)
                                                              (second c)))))))

(defun entries-equal-p (a b)
  "Check if two tree entries represent the same state."
  (and (eq (entry-type a) (entry-type b))
       (string= (entry-path a) (entry-path b))
       (eql (entry-mode a) (entry-mode b))
       (cond
         ((eq (entry-type a) :file)
          (and (string= (entry-hash a) (entry-hash b))
               (eql (entry-size a) (entry-size b))))
         ((eq (entry-type a) :symlink)
          (string= (entry-target a) (entry-target b)))
         (t t))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Materialization
;;; ═══════════════════════════════════════════════════════════════════

(defun materialize-tree (entries target-dir content-store)
  "Write all tree entries to TARGET-DIR using blobs from CONTENT-STORE.
   Creates directories, writes files, creates symlinks.
   Returns the number of entries materialized."
  (let ((count 0)
        (target (namestring target-dir)))
    (unless (char= (char target (1- (length target))) #\/)
      (setf target (concatenate 'string target "/")))
    ;; Ensure target exists
    (ensure-directories-exist (pathname target))
    ;; Process entries in order (directories before their contents due to sorting)
    (dolist (entry entries)
      (let ((full-path (merge-pathnames (entry-path entry) target)))
        (ecase (entry-type entry)
          (:directory
           (ensure-directories-exist
            (make-pathname :directory (append (pathname-directory full-path)
                                             (list (car (last (pathname-directory full-path)))))
                           :defaults full-path))
           (ensure-directories-exist full-path)
           (incf count))
          (:file
           (let ((blob (store-get-blob content-store (entry-hash entry))))
             (when blob
               (ensure-directories-exist full-path)
               (write-file-bytes (namestring full-path) blob)
               (incf count))))
          (:symlink
           (ensure-directories-exist full-path)
           (ignore-errors
             #+sbcl (sb-posix:symlink (entry-target entry) (namestring full-path))
             #-sbcl nil)
           (incf count)))))
    count))

(defun materialize-diff (diff target-dir content-store)
  "Apply a tree diff to TARGET-DIR. Only writes changed/added files,
   removes deleted files. Much faster than full materialize-tree for
   incremental updates.
   Returns the number of operations performed."
  (let ((ops 0)
        (target (namestring target-dir)))
    (unless (char= (char target (1- (length target))) #\/)
      (setf target (concatenate 'string target "/")))
    (dolist (change diff)
      (let* ((change-type (first change))
             (entry (if (eq change-type :modified)
                        (third change)  ; new entry
                        (second change)))
             (full-path (merge-pathnames (entry-path entry) target)))
        (ecase change-type
          (:added
           (ecase (entry-type entry)
             (:directory
              (ensure-directories-exist full-path))
             (:file
              (let ((blob (store-get-blob content-store (entry-hash entry))))
                (when blob
                  (ensure-directories-exist full-path)
                  (write-file-bytes (namestring full-path) blob))))
             (:symlink
              (ensure-directories-exist full-path)
              (ignore-errors
                #+sbcl (sb-posix:symlink (entry-target entry) (namestring full-path))
                #-sbcl nil)))
           (incf ops))
          (:removed
           (let ((path-str (namestring full-path)))
             (cond
               ((eq (entry-type entry) :directory)
                (ignore-errors (uiop:delete-directory-tree
                                (pathname path-str) :validate t)))
               (t
                (ignore-errors (delete-file path-str)))))
           (incf ops))
          (:modified
           (when (eq (entry-type entry) :file)
             (let ((blob (store-get-blob content-store (entry-hash entry))))
               (when blob
                 (write-file-bytes (namestring full-path) blob))))
           (incf ops)))))
    ops))

(defun write-file-bytes (path bytes)
  "Write a byte vector to a file, creating parent directories as needed."
  (ensure-directories-exist (pathname path))
  (with-open-file (stream path
                          :direction :output
                          :element-type '(unsigned-byte 8)
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-sequence bytes stream)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun tree-file-count (entries)
  "Count the number of file entries in a tree."
  (count :file entries :key #'entry-type))

(defun tree-total-size (entries)
  "Sum the sizes of all file entries in a tree."
  (reduce #'+ entries
          :key (lambda (e) (if (eq (entry-type e) :file) (entry-size e) 0))
          :initial-value 0))

(defun tree-find-entry (entries path)
  "Find a tree entry by path. Returns entry or NIL."
  (find path entries :key #'entry-path :test #'string=))
