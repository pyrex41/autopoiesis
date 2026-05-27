;;;; aether-blob-store-test.lisp - Standalone durability test.
;;;;
;;;; Verifies that aether-blob-store survives "restart" (close + re-open)
;;;; and that hydrate-content-store-blobs rehydrates a fresh content-store
;;;; with the bytes captured into LMDB on a previous run.
;;;;
;;;; Run via:
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/api-server/scripts/run-aether-blob-store-test.lisp

(in-package #:autopoiesis.api)

(defun %test-bytes (s)
  (babel:string-to-octets s :encoding :utf-8))

(defun %temp-blob-path ()
  (format nil "/tmp/aether-blob-store-test-~A/" (get-universal-time)))

(defun aether-blob-store-roundtrip-test ()
  "Write a blob, close the env, re-open at the same path, read it back."
  (let* ((path (%temp-blob-path))
         (payload (%test-bytes "hello, durable world"))
         (hash nil))
    (unwind-protect
         (progn
           ;; Round 1: open, write, close.
           (let ((*aether-blob-store-path* path))
             (close-aether-blob-store)
             (assert (ensure-aether-blob-store path) ()
                     "ensure-aether-blob-store returned NIL on first open")
             ;; Compute hash the same way substrate does.
             (setf hash (ironclad:byte-array-to-hex-string
                         (ironclad:digest-sequence :sha256 payload)))
             (persist-aether-blob hash payload)
             (assert (aether-blob-exists-p hash) ()
                     "Blob not found right after persist")
             (close-aether-blob-store))
           ;; Round 2: re-open at the same path, blob must still be there.
           (let ((*aether-blob-store-path* path))
             (assert (ensure-aether-blob-store path) ()
                     "ensure-aether-blob-store returned NIL on reopen")
             (let ((loaded (load-aether-blob hash)))
               (assert loaded () "Blob did not survive close/reopen")
               (assert (equalp payload loaded) ()
                       "Bytes differ across close/reopen"))
             (close-aether-blob-store))
           (format t "~&[ok] roundtrip survives close/reopen at ~A~%" path)
           t)
      (ignore-errors (uiop:delete-directory-tree
                      (pathname path) :validate t :if-does-not-exist :ignore)))))

(defun aether-blob-store-hydrate-test ()
  "persist-content-store-blobs → close → fresh content-store →
   hydrate-content-store-blobs → blobs are back."
  (let* ((path (%temp-blob-path))
         (b1 (%test-bytes "file one contents"))
         (b2 (%test-bytes "file two contents — different bytes")))
    (unwind-protect
         (let ((*aether-blob-store-path* path))
           (close-aether-blob-store)
           ;; Round 1: stash via a content-store.
           (let* ((store (autopoiesis.snapshot:make-content-store))
                  (h1 (autopoiesis.snapshot:store-put-blob store b1))
                  (h2 (autopoiesis.snapshot:store-put-blob store b2))
                  (written (persist-content-store-blobs store)))
             (assert (= written 2) ()
                     "Expected to write 2 blobs, wrote ~A" written)
             (close-aether-blob-store)
             ;; Round 2: brand-new content-store, hydrate from LMDB.
             (let* ((store2 (autopoiesis.snapshot:make-content-store))
                    (hydrated (hydrate-content-store-blobs store2 (list h1 h2))))
               (assert (= hydrated 2) ()
                       "Expected to hydrate 2 blobs, hydrated ~A" hydrated)
               (let ((got1 (autopoiesis.snapshot:store-get-blob store2 h1))
                     (got2 (autopoiesis.snapshot:store-get-blob store2 h2)))
                 (assert (equalp b1 got1) () "Hydrated b1 mismatched")
                 (assert (equalp b2 got2) () "Hydrated b2 mismatched")))
             (close-aether-blob-store))
           (format t "~&[ok] hydrate restores bytes into a fresh content-store~%")
           t)
      (ignore-errors (uiop:delete-directory-tree
                      (pathname path) :validate t :if-does-not-exist :ignore)))))

(defun aether-blob-store-idempotent-test ()
  "Persisting the same hash twice does NOT count as a second write."
  (let* ((path (%temp-blob-path))
         (payload (%test-bytes "idempotent")))
    (unwind-protect
         (let ((*aether-blob-store-path* path))
           (close-aether-blob-store)
           (let* ((store (autopoiesis.snapshot:make-content-store)))
             (autopoiesis.snapshot:store-put-blob store payload)
             (let ((w1 (persist-content-store-blobs store))
                   (w2 (persist-content-store-blobs store)))
               (assert (= w1 1) () "First call should write 1, wrote ~A" w1)
               (assert (= w2 0) () "Second call should write 0, wrote ~A" w2)))
           (close-aether-blob-store)
           (format t "~&[ok] persist-content-store-blobs is idempotent~%")
           t)
      (ignore-errors (uiop:delete-directory-tree
                      (pathname path) :validate t :if-does-not-exist :ignore)))))

(defun run-aether-blob-store-tests ()
  "Run all standalone aether-blob-store tests. Signals an error on failure."
  (aether-blob-store-roundtrip-test)
  (aether-blob-store-hydrate-test)
  (aether-blob-store-idempotent-test)
  (format t "~&aether-blob-store: all tests passed.~%")
  t)
