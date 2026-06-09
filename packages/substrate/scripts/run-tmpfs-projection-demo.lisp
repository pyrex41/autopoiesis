;;;; run-tmpfs-projection-demo.lisp - Slice 2: ephemeral projection + write-capture
;;;;
;;;; Proves the Kyle-Mistele 80/20: an agent's "files" live in the substrate
;;;; (content-addressed blobs + per-file datoms on a speculative branch); a cheap
;;;; ephemeral dir is PROJECTED from them for the agent to work in, and the
;;;; agent's writes are CAPTURED back onto the branch as datoms -- no VM, the
;;;; POSIX dir is a disposable, regenerable cache; the substrate is truth.
;;;;
;;;; File model (reuses the Slice-0/1 cardinality-aware merge verbatim):
;;;;   file:<path>  file/content-hash  <blob-hash>   (:one  -> same-file edit = conflict)
;;;;   module       module/file        <path>        (:many -> different files union)
;;;;
;;;; Bridge (project/capture) lives here, not in substrate: it spans
;;;; autopoiesis.snapshot (blobs/trees) + autopoiesis.substrate (branches), and
;;;; snapshot depends on substrate, so the bridge belongs one layer up.
;;;; Promotable to a core-level module later.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/substrate/scripts/run-tmpfs-projection-demo.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/" "./packages/substrate/"
               "./packages/api-server/" "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-projection-demo
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)
                    (#:snap #:autopoiesis.snapshot)))
(in-package #:sb-projection-demo)

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

;;; ===================================================================
;;; Bridge: substrate branch  <->  on-disk projection
;;; ===================================================================

(defun bytes<-string (s) (babel:string-to-octets s :encoding :utf-8))
(defun string<-bytes (b) (babel:octets-to-string b :encoding :utf-8))
(defun file-key (path) (format nil "file:~A" path))

(defun base-set-file (cs path content)
  "Store CONTENT as a blob and assert the base datoms for PATH."
  (let ((hash (snap::store-put-blob cs (bytes<-string content))))
    (s:transact! (list (s:make-datom (file-key path) "file/content-hash" hash)
                       (s:make-datom "module" "module/file" path)))
    hash))

(defun visible-paths (branch)
  "All file paths visible to BRANCH = base module/file (the EAVT append log)
   UNION any module/file paths staged in the branch overlay."
  (let ((paths (remove-duplicates
                (mapcar (lambda (e) (getf e :value))
                        (s:entity-history "module" "module/file" :last-n 10000))
                :test #'equal)))
    (dolist (w (s:datom-branch-writes branch))
      (when (equal (s:branch-write-attribute w) "module/file")
        (pushnew (s:branch-write-value w) paths :test #'equal)))
    paths))

(defun project-branch (branch cs dir)
  "Materialize BRANCH's visible file tree into DIR. Returns the projected
   tree entries (so capture can diff against them)."
  (let ((entries
          (loop for path in (visible-paths branch)
                for hash = (s:branch-read branch (file-key path) "file/content-hash")
                for bytes = (and hash (snap::store-get-blob cs hash))
                when bytes
                  collect (snap::make-file-entry path hash 33188 (length bytes) 0))))
    (snap::materialize-tree entries dir cs)
    entries))

(defun capture-into-branch (branch cs dir projected-entries)
  "Scan DIR, stage every added/modified file back onto BRANCH as datoms.
   Compares by content-hash per path (mode-insensitive). Returns #captured."
  (let ((proj (make-hash-table :test 'equal)) (n 0))
    (dolist (e projected-entries)
      (when (eq (snap::entry-type e) :file)
        (setf (gethash (snap::entry-path e) proj) (snap::entry-hash e))))
    (dolist (e (snap::scan-directory-flat dir cs))
      (when (eq (snap::entry-type e) :file)
        (let* ((path (snap::entry-path e))
               (hash (snap::entry-hash e))
               (old (gethash path proj)))
          (unless (equal old hash)              ; added or modified
            (s:branch-stage branch (file-key path) "file/content-hash" hash)
            (unless old (s:branch-stage branch "module" "module/file" path))
            (incf n)))))
    n))

(defun fresh-dir (tag)
  (let ((d (format nil "/tmp/sb-proj-~A-~A/" tag (get-universal-time))))
    (ensure-directories-exist d)
    d))

(defun read-disk-file (dir path)
  (string<-bytes (snap::read-file-bytes (namestring (merge-pathnames path dir)))))

;;; ===================================================================
;;; Demo
;;; ===================================================================

(defun run-demo ()
  (setf *fails* nil)
  (s:with-store ()
    (s:declare-cardinality "file/content-hash" :one)
    (s:declare-cardinality "module/file"       :many)
    (let ((cs (snap::make-content-store))
          (h0 nil))

      ;; --- base workspace: one file ---
      (setf h0 (base-set-file cs "main.py" "print('hi')~%"))

      ;; --- fork a branch and PROJECT it to an ephemeral dir ---
      (let* ((br (s:branch-fork :name "agent-sim"))
             (dir (fresh-dir "sim"))
             (projected (project-branch br cs dir)))
        (check "projection reconstructed main.py on disk"
               (equal (read-disk-file dir "main.py") "print('hi')~%"))

        ;; --- a (simulated) agent works in the ephemeral dir ---
        ;; modifies main.py and creates util.py -- ordinary POSIX writes.
        (snap::write-file-bytes (namestring (merge-pathnames "main.py" dir))
                                (bytes<-string "print('hi')~%def greet(): return 42~%"))
        (snap::write-file-bytes (namestring (merge-pathnames "util.py" dir))
                                (bytes<-string "X = 1~%"))

        ;; --- CAPTURE the agent's writes back onto the branch ---
        (let ((captured (capture-into-branch br cs dir projected)))
          (check "captured 2 file writes (modified main.py + added util.py)"
                 (= captured 2) captured))

        ;; base must be untouched until merge (work lives on the branch)
        (check "base main.py unchanged before merge (still h0)"
               (equal (s:entity-attr (file-key "main.py") "file/content-hash") h0))
        (check "base has no util.py before merge"
               (null (s:entity-attr (file-key "util.py") "file/content-hash")))

        ;; --- MERGE the branch back to base ---
        (multiple-value-bind (applied conflicts) (s:branch-merge br)
          (check "merge applied the captured writes, no conflicts"
                 (and (>= applied 2) (null conflicts)) (list :applied applied)))

        ;; --- the agent's work is now substrate truth ---
        (check "base main.py now points at the edited blob"
               (not (equal (s:entity-attr (file-key "main.py") "file/content-hash") h0)))
        (check "base util.py exists post-merge"
               (s:entity-attr (file-key "util.py") "file/content-hash"))

        ;; --- POSIX is disposable: nuke the dir, regenerate from substrate ---
        (ignore-errors (uiop:delete-directory-tree (pathname dir) :validate t))
        (let* ((br2 (s:branch-fork :name "verify"))
               (dir2 (fresh-dir "verify")))
          (project-branch br2 cs dir2)
          (check "re-materialized main.py reproduces the agent's exact bytes"
                 (equal (read-disk-file dir2 "main.py")
                        "print('hi')~%def greet(): return 42~%"))
          (check "re-materialized util.py reproduces the agent's exact bytes"
                 (equal (read-disk-file dir2 "util.py") "X = 1~%"))
          (ignore-errors (uiop:delete-directory-tree (pathname dir2) :validate t))))

      ;; --- per-file conflict: two branches edit the SAME file differently ---
      ;; (ties projection/capture to the Slice-1 parallel merge: different files
      ;;  union, same file diverges -> flagged)
      (let* ((ba (s:branch-fork :name "edit-a"))
             (bb (s:branch-fork :name "edit-b"))
             (ha (snap::store-put-blob cs (bytes<-string "VERSION-A~%")))
             (hb (snap::store-put-blob cs (bytes<-string "VERSION-B~%"))))
        (s:branch-stage ba (file-key "main.py") "file/content-hash" ha)
        (s:branch-stage bb (file-key "main.py") "file/content-hash" hb)
        (multiple-value-bind (a-applied a-conflicts) (s:branch-merge ba)
          (declare (ignorable a-applied))
          (check "first same-file edit merges clean" (null a-conflicts)))
        (multiple-value-bind (b-applied b-conflicts) (s:branch-merge bb)
          (declare (ignorable b-applied))
          (check "second same-file edit FLAGGED as conflict (per-file granularity)"
                 (and (= 1 (length b-conflicts))
                      (equal (s:merge-conflict-attribute (first b-conflicts))
                             "file/content-hash")))))))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-demo))
