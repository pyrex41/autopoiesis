;;;; sandbox-backend-tests.lisp - Tests for content-addressed sandbox
;;;;
;;;; Tests blob storage, filesystem tree operations, execution backends,
;;;; sandbox lifecycle, changeset tracking, and DAG integration.

(defpackage #:autopoiesis.sandbox-backend.test
  (:use #:cl #:fiveam)
  (:export #:run-sandbox-backend-tests))

(in-package #:autopoiesis.sandbox-backend.test)

(def-suite sandbox-backend-tests
  :description "Content-addressed sandbox backend tests")

(in-suite sandbox-backend-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Blob Store Tests
;;; ═══════════════════════════════════════════════════════════════════

(test blob-hash-deterministic
  "Same bytes always produce the same hash"
  (let ((bytes (make-array 5 :element-type '(unsigned-byte 8)
                             :initial-contents '(72 101 108 108 111))))
    (is (string= (autopoiesis.snapshot:blob-hash bytes)
                 (autopoiesis.snapshot:blob-hash bytes)))))

(test blob-hash-different-content
  "Different bytes produce different hashes"
  (let ((a (make-array 3 :element-type '(unsigned-byte 8)
                         :initial-contents '(1 2 3)))
        (b (make-array 3 :element-type '(unsigned-byte 8)
                         :initial-contents '(4 5 6))))
    (is (not (string= (autopoiesis.snapshot:blob-hash a)
                      (autopoiesis.snapshot:blob-hash b))))))

(test store-put-blob-basic
  "Store and retrieve a blob"
  (let* ((store (autopoiesis.snapshot:make-content-store))
         (bytes (make-array 5 :element-type '(unsigned-byte 8)
                              :initial-contents '(72 101 108 108 111)))
         (hash (autopoiesis.snapshot:store-put-blob store bytes)))
    (is (stringp hash))
    (is (= 64 (length hash))) ; SHA-256 hex = 64 chars
    (is (autopoiesis.snapshot:store-blob-exists-p store hash))
    (let ((retrieved (autopoiesis.snapshot:store-get-blob store hash)))
      (is (not (null retrieved)))
      (is (= 5 (length retrieved)))
      (is (equalp bytes retrieved)))))

(test store-blob-dedup
  "Same content stored twice produces same hash, increments refcount"
  (let* ((store (autopoiesis.snapshot:make-content-store))
         (bytes (make-array 3 :element-type '(unsigned-byte 8)
                              :initial-contents '(1 2 3)))
         (hash1 (autopoiesis.snapshot:store-put-blob store bytes))
         (hash2 (autopoiesis.snapshot:store-put-blob store bytes)))
    (is (string= hash1 hash2))
    ;; First delete decrements refcount but doesn't remove (ref=1)
    (autopoiesis.snapshot:store-delete store hash1)
    (is (autopoiesis.snapshot:store-blob-exists-p store hash1))
    ;; Second delete removes it (ref=0)
    (autopoiesis.snapshot:store-delete store hash1)
    (is (not (autopoiesis.snapshot:store-blob-exists-p store hash1)))))

(test store-stats
  "Store stats reports correct counts"
  (let ((store (autopoiesis.snapshot:make-content-store)))
    ;; Add S-expression
    (autopoiesis.snapshot:store-put store '(hello world))
    ;; Add blob
    (autopoiesis.snapshot:store-put-blob
     store (make-array 3 :element-type '(unsigned-byte 8)
                         :initial-contents '(1 2 3)))
    (let ((stats (autopoiesis.snapshot:store-stats store)))
      (is (= 1 (getf stats :sexpr-count)))
      (is (= 1 (getf stats :blob-count)))
      (is (= 3 (getf stats :blob-bytes)))
      (is (= 2 (getf stats :total-entries))))))

(test store-exists-p-unified
  "store-exists-p checks both sexprs and blobs"
  (let* ((store (autopoiesis.snapshot:make-content-store))
         (sexpr-hash (autopoiesis.snapshot:store-put store '(test)))
         (blob-hash (autopoiesis.snapshot:store-put-blob
                     store (make-array 1 :element-type '(unsigned-byte 8)
                                         :initial-contents '(42)))))
    (is (autopoiesis.snapshot:store-exists-p store sexpr-hash))
    (is (autopoiesis.snapshot:store-exists-p store blob-hash))
    (is (not (autopoiesis.snapshot:store-exists-p store "nonexistent")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Entry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test tree-entry-constructors
  "Tree entry constructors and accessors"
  (let ((file (autopoiesis.snapshot:make-file-entry
               "src/main.py" "abc123" 33188 1234 1711324800)))
    (is (eq :file (autopoiesis.snapshot:entry-type file)))
    (is (string= "src/main.py" (autopoiesis.snapshot:entry-path file)))
    (is (string= "abc123" (autopoiesis.snapshot:entry-hash file)))
    (is (= 33188 (autopoiesis.snapshot:entry-mode file)))
    (is (= 1234 (autopoiesis.snapshot:entry-size file)))
    (is (= 1711324800 (autopoiesis.snapshot:entry-mtime file))))

  (let ((dir (autopoiesis.snapshot:make-directory-entry "src/" 16877)))
    (is (eq :directory (autopoiesis.snapshot:entry-type dir)))
    (is (string= "src/" (autopoiesis.snapshot:entry-path dir)))
    (is (= 16877 (autopoiesis.snapshot:entry-mode dir))))

  (let ((link (autopoiesis.snapshot:make-symlink-entry
               "link.txt" "/target" 41471)))
    (is (eq :symlink (autopoiesis.snapshot:entry-type link)))
    (is (string= "/target" (autopoiesis.snapshot:entry-target link)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Merkle Root Hash Tests
;;; ═══════════════════════════════════════════════════════════════════

(test tree-hash-deterministic
  "Same entries always produce the same Merkle root"
  (let ((entries (list (autopoiesis.snapshot:make-file-entry
                        "a.txt" "hash1" 33188 100 1000)
                       (autopoiesis.snapshot:make-file-entry
                        "b.txt" "hash2" 33188 200 2000))))
    (is (string= (autopoiesis.snapshot:tree-hash entries)
                 (autopoiesis.snapshot:tree-hash entries)))))

(test tree-hash-order-sensitive
  "Different ordering produces different hashes (entries must be pre-sorted)"
  (let ((entries-a (list (autopoiesis.snapshot:make-file-entry
                          "a.txt" "h1" 33188 100 1000)
                         (autopoiesis.snapshot:make-file-entry
                          "b.txt" "h2" 33188 200 2000)))
        (entries-b (list (autopoiesis.snapshot:make-file-entry
                          "b.txt" "h2" 33188 200 2000)
                         (autopoiesis.snapshot:make-file-entry
                          "a.txt" "h1" 33188 100 1000))))
    (is (not (string= (autopoiesis.snapshot:tree-hash entries-a)
                      (autopoiesis.snapshot:tree-hash entries-b))))))

(test tree-hash-content-sensitive
  "Changing a file hash changes the Merkle root"
  (let ((entries-a (list (autopoiesis.snapshot:make-file-entry
                          "a.txt" "hash1" 33188 100 1000)))
        (entries-b (list (autopoiesis.snapshot:make-file-entry
                          "a.txt" "hash2" 33188 100 1000))))
    (is (not (string= (autopoiesis.snapshot:tree-hash entries-a)
                      (autopoiesis.snapshot:tree-hash entries-b))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Diff Tests
;;; ═══════════════════════════════════════════════════════════════════

(test tree-diff-identical
  "Identical trees produce no diff"
  (let ((entries (list (autopoiesis.snapshot:make-file-entry
                        "a.txt" "hash1" 33188 100 1000))))
    (is (null (autopoiesis.snapshot:tree-diff entries entries)))))

(test tree-diff-added
  "New file detected as :added"
  (let ((old (list (autopoiesis.snapshot:make-file-entry
                    "a.txt" "hash1" 33188 100 1000)))
        (new (list (autopoiesis.snapshot:make-file-entry
                    "a.txt" "hash1" 33188 100 1000)
                   (autopoiesis.snapshot:make-file-entry
                    "b.txt" "hash2" 33188 200 2000))))
    (let ((diff (autopoiesis.snapshot:tree-diff old new)))
      (is (= 1 (length diff)))
      (is (eq :added (first (first diff))))
      (is (string= "b.txt"
                    (autopoiesis.snapshot:entry-path (second (first diff))))))))

(test tree-diff-removed
  "Deleted file detected as :removed"
  (let ((old (list (autopoiesis.snapshot:make-file-entry
                    "a.txt" "hash1" 33188 100 1000)
                   (autopoiesis.snapshot:make-file-entry
                    "b.txt" "hash2" 33188 200 2000)))
        (new (list (autopoiesis.snapshot:make-file-entry
                    "a.txt" "hash1" 33188 100 1000))))
    (let ((diff (autopoiesis.snapshot:tree-diff old new)))
      (is (= 1 (length diff)))
      (is (eq :removed (first (first diff)))))))

(test tree-diff-modified
  "Changed file hash detected as :modified"
  (let ((old (list (autopoiesis.snapshot:make-file-entry
                    "a.txt" "hash1" 33188 100 1000)))
        (new (list (autopoiesis.snapshot:make-file-entry
                    "a.txt" "hash2" 33188 150 2000))))
    (let ((diff (autopoiesis.snapshot:tree-diff old new)))
      (is (= 1 (length diff)))
      (is (eq :modified (first (first diff)))))))

(test tree-diff-complex
  "Multiple changes detected correctly"
  (let ((old (list (autopoiesis.snapshot:make-file-entry "a.txt" "h1" 33188 100 1000)
                   (autopoiesis.snapshot:make-file-entry "b.txt" "h2" 33188 200 2000)
                   (autopoiesis.snapshot:make-file-entry "c.txt" "h3" 33188 300 3000)))
        (new (list (autopoiesis.snapshot:make-file-entry "a.txt" "h1-new" 33188 100 1000)
                   (autopoiesis.snapshot:make-file-entry "c.txt" "h3" 33188 300 3000)
                   (autopoiesis.snapshot:make-file-entry "d.txt" "h4" 33188 400 4000))))
    (let ((diff (autopoiesis.snapshot:tree-diff old new)))
      ;; a.txt modified, b.txt removed, d.txt added = 3 changes
      (is (= 3 (length diff)))
      (let ((types (mapcar #'first diff)))
        (is (member :modified types))
        (is (member :removed types))
        (is (member :added types))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Filesystem Scan + Materialize Roundtrip Tests
;;; ═══════════════════════════════════════════════════════════════════

(test scan-and-materialize-roundtrip
  "Scan a directory, then materialize it elsewhere — contents match"
  (let ((store (autopoiesis.snapshot:make-content-store))
        (source-dir (uiop:ensure-pathname
                     (format nil "/tmp/ap-test-scan-~A/" (random 100000))
                     :ensure-directory t))
        (target-dir (uiop:ensure-pathname
                     (format nil "/tmp/ap-test-materialize-~A/" (random 100000))
                     :ensure-directory t)))
    (unwind-protect
         (progn
           ;; Create source files
           (ensure-directories-exist source-dir)
           (ensure-directories-exist (merge-pathnames "subdir/" source-dir))
           (with-open-file (s (merge-pathnames "hello.txt" source-dir)
                              :direction :output :if-exists :supersede)
             (write-string "Hello, world!" s))
           (with-open-file (s (merge-pathnames "subdir/nested.txt" source-dir)
                              :direction :output :if-exists :supersede)
             (write-string "Nested content" s))

           ;; Scan
           (let ((entries (autopoiesis.snapshot:scan-directory-flat
                           (namestring source-dir) store)))
             (is (> (length entries) 0))
             ;; Should have files
             (is (>= (autopoiesis.snapshot:tree-file-count entries) 2))

             ;; Materialize
             (ensure-directories-exist target-dir)
             (let ((count (autopoiesis.snapshot:materialize-tree
                           entries (namestring target-dir) store)))
               (is (> count 0)))

             ;; Verify files match
             (is (probe-file (merge-pathnames "hello.txt" target-dir)))
             (is (string= "Hello, world!"
                          (uiop:read-file-string
                           (merge-pathnames "hello.txt" target-dir))))
             (is (probe-file (merge-pathnames "subdir/nested.txt" target-dir)))
             (is (string= "Nested content"
                          (uiop:read-file-string
                           (merge-pathnames "subdir/nested.txt" target-dir))))))
      ;; Cleanup
      (ignore-errors
        (uiop:delete-directory-tree source-dir :validate t))
      (ignore-errors
        (uiop:delete-directory-tree target-dir :validate t)))))

(test materialize-diff-incremental
  "Incremental materialization only applies changes"
  (let ((store (autopoiesis.snapshot:make-content-store))
        (target-dir (uiop:ensure-pathname
                     (format nil "/tmp/ap-test-diff-~A/" (random 100000))
                     :ensure-directory t)))
    (unwind-protect
         (progn
           (ensure-directories-exist target-dir)
           ;; Create initial file
           (with-open-file (s (merge-pathnames "keep.txt" target-dir)
                              :direction :output :if-exists :supersede)
             (write-string "keep this" s))
           (with-open-file (s (merge-pathnames "remove.txt" target-dir)
                              :direction :output :if-exists :supersede)
             (write-string "remove this" s))

           ;; Build a diff: add new.txt, remove remove.txt
           (let* ((new-bytes (babel:string-to-octets "new content" :encoding :utf-8))
                  (new-hash (autopoiesis.snapshot:store-put-blob store new-bytes))
                  (diff (list (list :added
                                    (autopoiesis.snapshot:make-file-entry
                                     "new.txt" new-hash 33188
                                     (length new-bytes) (get-universal-time)))
                              (list :removed
                                    (autopoiesis.snapshot:make-file-entry
                                     "remove.txt" "old-hash" 33188 11 0)))))
             (let ((ops (autopoiesis.snapshot:materialize-diff
                         diff (namestring target-dir) store)))
               (is (= 2 ops))
               ;; new.txt should exist
               (is (probe-file (merge-pathnames "new.txt" target-dir)))
               (is (string= "new content"
                            (uiop:read-file-string
                             (merge-pathnames "new.txt" target-dir))))
               ;; remove.txt should be gone
               (is (not (probe-file (merge-pathnames "remove.txt" target-dir))))
               ;; keep.txt should be untouched
               (is (string= "keep this"
                            (uiop:read-file-string
                             (merge-pathnames "keep.txt" target-dir)))))))
      (ignore-errors
        (uiop:delete-directory-tree target-dir :validate t)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot with Tree Tests
;;; ═══════════════════════════════════════════════════════════════════

(test snapshot-with-tree
  "Snapshot with tree entries computes Merkle root"
  (let* ((entries (list (autopoiesis.snapshot:make-file-entry
                         "a.txt" "hash1" 33188 100 1000)))
         (snap (autopoiesis.snapshot:make-snapshot
                '(:agent "test") :tree-entries entries)))
    (is (not (null (autopoiesis.snapshot:snapshot-tree-root snap))))
    (is (= 64 (length (autopoiesis.snapshot:snapshot-tree-root snap))))
    (is (equal entries (autopoiesis.snapshot:snapshot-tree-entries snap)))))

(test snapshot-without-tree
  "Snapshot without tree entries has nil tree-root"
  (let ((snap (autopoiesis.snapshot:make-snapshot '(:agent "test"))))
    (is (null (autopoiesis.snapshot:snapshot-tree-root snap)))
    (is (null (autopoiesis.snapshot:snapshot-tree-entries snap)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Local Backend Tests
;;; ═══════════════════════════════════════════════════════════════════

(test local-backend-lifecycle
  "Create, exec, snapshot, destroy sandbox via local backend"
  (let* ((base-dir (format nil "/tmp/ap-test-backend-~A/" (random 100000)))
         (backend (autopoiesis.sandbox:make-local-backend :base-dir base-dir))
         (store (autopoiesis.snapshot:make-content-store))
         (sandbox-id "test-sb-1"))
    (unwind-protect
         (progn
           ;; Create
           (autopoiesis.sandbox:backend-create backend sandbox-id)
           (is (probe-file (pathname (format nil "~A~A/" base-dir sandbox-id))))

           ;; Write a file via exec
           (let ((result (autopoiesis.sandbox:backend-exec
                          backend sandbox-id
                          "echo 'hello world' > test.txt")))
             (is (= 0 (autopoiesis.sandbox:exec-result-exit-code result))))

           ;; Verify file exists
           (let ((result (autopoiesis.sandbox:backend-exec
                          backend sandbox-id "cat test.txt")))
             (is (= 0 (autopoiesis.sandbox:exec-result-exit-code result)))
             (is (search "hello world"
                         (autopoiesis.sandbox:exec-result-stdout result))))

           ;; Snapshot
           (let ((tree (autopoiesis.sandbox:backend-snapshot
                        backend sandbox-id store)))
             (is (> (length tree) 0))
             (is (>= (autopoiesis.snapshot:tree-file-count tree) 1)))

           ;; Destroy
           (autopoiesis.sandbox:backend-destroy backend sandbox-id)
           (is (not (probe-file
                     (pathname (format nil "~A~A/" base-dir sandbox-id))))))
      ;; Cleanup
      (ignore-errors
        (uiop:delete-directory-tree (pathname base-dir) :validate t)))))

(test local-backend-fork
  "Fork a sandbox via local backend"
  (let* ((base-dir (format nil "/tmp/ap-test-fork-~A/" (random 100000)))
         (backend (autopoiesis.sandbox:make-local-backend :base-dir base-dir)))
    (unwind-protect
         (progn
           ;; Create source
           (autopoiesis.sandbox:backend-create backend "source")
           (autopoiesis.sandbox:backend-exec backend "source"
                                             "echo 'original' > data.txt")

           ;; Fork
           (autopoiesis.sandbox:backend-fork backend "source" "forked")

           ;; Verify fork has the file
           (let ((result (autopoiesis.sandbox:backend-exec
                          backend "forked" "cat data.txt")))
             (is (= 0 (autopoiesis.sandbox:exec-result-exit-code result)))
             (is (search "original"
                         (autopoiesis.sandbox:exec-result-stdout result))))

           ;; Modify fork
           (autopoiesis.sandbox:backend-exec backend "forked"
                                             "echo 'modified' > data.txt")

           ;; Source unchanged
           (let ((result (autopoiesis.sandbox:backend-exec
                          backend "source" "cat data.txt")))
             (is (search "original"
                         (autopoiesis.sandbox:exec-result-stdout result))))

           ;; Cleanup
           (autopoiesis.sandbox:backend-destroy backend "source")
           (autopoiesis.sandbox:backend-destroy backend "forked"))
      (ignore-errors
        (uiop:delete-directory-tree (pathname base-dir) :validate t)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Manager Tests
;;; ═══════════════════════════════════════════════════════════════════

(test sandbox-manager-full-lifecycle
  "Full sandbox lifecycle through the manager"
  (let* ((base-dir (format nil "/tmp/ap-test-mgr-~A/" (random 100000)))
         (backend (autopoiesis.sandbox:make-local-backend :base-dir base-dir))
         (manager (autopoiesis.sandbox:make-sandbox-manager backend)))
    (unwind-protect
         (progn
           ;; Create
           (autopoiesis.sandbox:manager-create-sandbox manager "mgr-test-1")
           (let ((info (autopoiesis.sandbox:manager-sandbox-info
                        manager "mgr-test-1")))
             (is (not (null info)))
             (is (eq :ready (getf info :status))))

           ;; Exec
           (autopoiesis.sandbox:manager-exec
            manager "mgr-test-1" "echo 'test content' > file.txt")

           ;; Snapshot
           (let ((snap (autopoiesis.sandbox:manager-snapshot
                        manager "mgr-test-1" :label "snap-1")))
             (is (not (null (autopoiesis.snapshot:snapshot-id snap))))
             (is (not (null (autopoiesis.snapshot:snapshot-tree-root snap))))
             ;; Verify snapshot count updated
             (let ((info (autopoiesis.sandbox:manager-sandbox-info
                          manager "mgr-test-1")))
               (is (= 1 (getf info :snapshot-count)))))

           ;; Fork
           (autopoiesis.sandbox:manager-fork
            manager "mgr-test-1" "mgr-fork-1")
           (let ((info (autopoiesis.sandbox:manager-sandbox-info
                        manager "mgr-fork-1")))
             (is (not (null info)))
             (is (eq :ready (getf info :status))))

           ;; List
           (let ((all (autopoiesis.sandbox:manager-list-sandboxes manager)))
             (is (= 2 (length all))))

           ;; Destroy
           (autopoiesis.sandbox:manager-destroy-sandbox manager "mgr-test-1")
           (autopoiesis.sandbox:manager-destroy-sandbox manager "mgr-fork-1")
           (is (= 0 (length (autopoiesis.sandbox:manager-list-sandboxes
                             manager)))))
      (ignore-errors
        (uiop:delete-directory-tree (pathname base-dir) :validate t)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Changeset Tests
;;; ═══════════════════════════════════════════════════════════════════

(test changeset-basic
  "Basic changeset recording and querying"
  (let ((cs (autopoiesis.sandbox:make-changeset "test-sandbox")))
    (is (autopoiesis.sandbox:changeset-empty-p cs))
    (autopoiesis.sandbox:changeset-record cs "new.txt" :added)
    (autopoiesis.sandbox:changeset-record cs "modified.txt" :modified)
    (autopoiesis.sandbox:changeset-record cs "deleted.txt" :deleted)
    (is (not (autopoiesis.sandbox:changeset-empty-p cs)))
    (is (= 3 (autopoiesis.sandbox:changeset-change-count cs)))
    (let ((paths (autopoiesis.sandbox:changeset-changed-paths cs)))
      (is (= 3 (length paths)))
      (is (member "new.txt" paths :test #'string=))
      (is (member "modified.txt" paths :test #'string=))
      (is (member "deleted.txt" paths :test #'string=)))))

(test changeset-commit-incremental
  "Changeset commit builds tree from base + changes"
  (let* ((store (autopoiesis.snapshot:make-content-store))
         (base-entries (list (autopoiesis.snapshot:make-file-entry
                              "keep.txt" "hash-keep" 33188 100 1000)
                             (autopoiesis.snapshot:make-file-entry
                              "remove.txt" "hash-remove" 33188 200 2000)))
         (cs (autopoiesis.sandbox:make-changeset "test" :base-tree base-entries))
         (sandbox-dir (format nil "/tmp/ap-test-cs-~A/" (random 100000))))
    (unwind-protect
         (progn
           ;; Set up sandbox dir with modified file
           (ensure-directories-exist (pathname sandbox-dir))
           (with-open-file (s (merge-pathnames "new.txt" sandbox-dir)
                              :direction :output :if-exists :supersede)
             (write-string "new file content" s))
           ;; Record changes
           (autopoiesis.sandbox:changeset-record cs "remove.txt" :deleted)
           (autopoiesis.sandbox:changeset-record cs "new.txt" :added)
           ;; Commit
           (let ((new-tree (autopoiesis.sandbox:changeset-commit
                            cs sandbox-dir store)))
             ;; Should have keep.txt and new.txt, not remove.txt
             (is (= 2 (length new-tree)))
             (is (autopoiesis.snapshot:tree-find-entry new-tree "keep.txt"))
             (is (autopoiesis.snapshot:tree-find-entry new-tree "new.txt"))
             (is (not (autopoiesis.snapshot:tree-find-entry
                       new-tree "remove.txt")))))
      (ignore-errors
        (uiop:delete-directory-tree (pathname sandbox-dir) :validate t)))))

(test changeset-reset
  "Changeset reset clears changes and optionally updates base"
  (let* ((cs (autopoiesis.sandbox:make-changeset "test"))
         (new-base (list (autopoiesis.snapshot:make-file-entry
                          "x.txt" "hx" 33188 50 500))))
    (autopoiesis.sandbox:changeset-record cs "a.txt" :added)
    (is (= 1 (autopoiesis.sandbox:changeset-change-count cs)))
    (autopoiesis.sandbox:changeset-reset cs :new-base-tree new-base)
    (is (autopoiesis.sandbox:changeset-empty-p cs))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tree Utility Tests
;;; ═══════════════════════════════════════════════════════════════════

(test tree-utilities
  "tree-file-count, tree-total-size, tree-find-entry"
  (let ((entries (list (autopoiesis.snapshot:make-directory-entry "src/" 16877)
                       (autopoiesis.snapshot:make-file-entry
                        "src/a.txt" "h1" 33188 100 1000)
                       (autopoiesis.snapshot:make-file-entry
                        "src/b.txt" "h2" 33188 200 2000))))
    (is (= 2 (autopoiesis.snapshot:tree-file-count entries)))
    (is (= 300 (autopoiesis.snapshot:tree-total-size entries)))
    (is (not (null (autopoiesis.snapshot:tree-find-entry entries "src/a.txt"))))
    (is (null (autopoiesis.snapshot:tree-find-entry entries "nonexistent")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Backend Registry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test backend-registry
  "Register, find, and list backends"
  (let ((backend (autopoiesis.sandbox:make-local-backend
                  :base-dir "/tmp/ap-test-reg/")))
    (autopoiesis.sandbox:register-backend :test-local backend)
    (is (eq backend (autopoiesis.sandbox:find-backend :test-local)))
    (is (member :test-local (autopoiesis.sandbox:list-backends)))
    ;; Cleanup
    (remhash :test-local autopoiesis.sandbox:*backend-registry*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Run All Tests
;;; ═══════════════════════════════════════════════════════════════════

(defun run-sandbox-backend-tests ()
  "Run all sandbox backend tests."
  (run! 'sandbox-backend-tests))
