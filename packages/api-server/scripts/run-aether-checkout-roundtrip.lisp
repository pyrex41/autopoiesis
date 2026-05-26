;;;; run-aether-checkout-roundtrip.lisp - End-to-end durability smoke test.
;;;;
;;;; Simulates a real AETHER cycle:
;;;;   1. Set up a tiny source tree on disk.
;;;;   2. Scan it into a content-store (in-memory) AND mirror blobs to LMDB.
;;;;   3. Drop the in-memory state (close everything).
;;;;   4. Open a brand-new content-store, hydrate from LMDB.
;;;;   5. materialize-tree into a checkout dir and verify file contents.
;;;;
;;;; This is what makes "checkout a pre-restart snapshot" work without
;;;; needing to actually restart SBCL inside the test driver.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/api-server/scripts/run-aether-checkout-roundtrip.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/"
               "./packages/substrate/"
               "./packages/api-server/"
               "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis :silent t)
(ql:quickload :autopoiesis/api :silent t)

(defun write-string-to-file (path content)
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
    (write-string content out)))

(defun read-file-string (path)
  (with-open-file (in path :direction :input :external-format :utf-8)
    (with-output-to-string (s)
      (loop for line = (read-line in nil nil)
            while line do (write-line line s)))))

(defun run-roundtrip ()
  (let* ((work-root (format nil "/tmp/aether-checkout-roundtrip-~A/"
                            (get-universal-time)))
         (src (concatenate 'string work-root "src/"))
         (out (concatenate 'string work-root "out/"))
         (blob-path (concatenate 'string work-root "blobs/")))
    (unwind-protect
         (progn
           (ensure-directories-exist src)
           (ensure-directories-exist out)
           (write-string-to-file (concatenate 'string src "hello.txt")
                                 "hello from pre-restart")
           (write-string-to-file (concatenate 'string src "sub/nested.txt")
                                 "nested content survives")
           ;; Phase 1: scan + persist to LMDB.
           (let ((autopoiesis.api::*aether-blob-store-path* blob-path))
             (autopoiesis.api::close-aether-blob-store)
             (let* ((store-a (autopoiesis.snapshot:make-content-store))
                    (entries (autopoiesis.snapshot:scan-directory-flat
                              (uiop:ensure-directory-pathname src)
                              store-a)))
               (assert entries () "scan-directory-flat returned no entries")
               (autopoiesis.api::persist-content-store-blobs store-a)
               ;; SIMULATE RESTART: drop everything, close LMDB.
               (autopoiesis.api::close-aether-blob-store)
               (setf store-a nil)
               (sb-ext:gc :full t)
               ;; Phase 2: fresh content-store, hydrate from LMDB, materialize.
               (autopoiesis.api::close-aether-blob-store)
               (let* ((store-b (autopoiesis.snapshot:make-content-store))
                      (hashes (autopoiesis.api::tree-entry-hashes entries))
                      (hydrated (autopoiesis.api::hydrate-content-store-blobs
                                 store-b hashes)))
                 (assert (= hydrated (length hashes)) ()
                         "Expected to hydrate ~A blobs, got ~A"
                         (length hashes) hydrated)
                 (autopoiesis.snapshot:materialize-tree
                  entries
                  (uiop:ensure-directory-pathname out)
                  store-b))
               ;; Verify files.
               (let ((got1 (read-file-string
                            (concatenate 'string out "hello.txt")))
                     (got2 (read-file-string
                            (concatenate 'string out "sub/nested.txt"))))
                 (assert (search "hello from pre-restart" got1) ()
                         "hello.txt content mismatch: ~A" got1)
                 (assert (search "nested content survives" got2) ()
                         "nested.txt content mismatch: ~A" got2))
               (autopoiesis.api::close-aether-blob-store)
               (format t "~&[ok] full checkout roundtrip works at ~A~%"
                       work-root)))
           t)
      (ignore-errors (uiop:delete-directory-tree
                      (pathname work-root) :validate t
                      :if-does-not-exist :ignore)))))

(handler-case
    (progn (run-roundtrip) (sb-ext:exit :code 0))
  (error (e)
    (format *error-output* "~&checkout-roundtrip FAILED: ~A~%" e)
    (sb-ext:exit :code 1)))
