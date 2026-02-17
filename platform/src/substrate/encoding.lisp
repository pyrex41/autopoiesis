;;;; encoding.lisp - Big-endian key encoding for B+ tree ordering
;;;;
;;;; Encodes datoms as byte arrays for LMDB index keys.
;;;; Big-endian ensures lexicographic byte ordering matches numeric ordering.

(in-package #:autopoiesis.substrate)

(defun encode-u64-be (buf offset value)
  "Encode a u64 value as 8 big-endian bytes into BUF at OFFSET."
  (loop for i from 7 downto 0
        do (setf (aref buf (+ offset (- 7 i)))
                 (ldb (byte 8 (* i 8)) value))))

(defun encode-u32-be (buf offset value)
  "Encode a u32 value as 4 big-endian bytes into BUF at OFFSET."
  (loop for i from 3 downto 0
        do (setf (aref buf (+ offset (- 3 i)))
                 (ldb (byte 8 (* i 8)) value))))

(defun encode-eavt-key (datom)
  "Encode datom as EAVT key for entity-centric lookups.
   Layout: [entity:8][attribute:4][tx:8] = 20 bytes."
  (let ((buf (make-array 20 :element-type '(unsigned-byte 8))))
    (encode-u64-be buf 0 (d-entity datom))
    (encode-u32-be buf 8 (d-attribute datom))
    (encode-u64-be buf 12 (d-tx datom))
    buf))

(defun encode-aevt-key (datom)
  "Encode datom as AEVT key for attribute-centric lookups.
   Layout: [attribute:4][entity:8][tx:8] = 20 bytes."
  (let ((buf (make-array 20 :element-type '(unsigned-byte 8))))
    (encode-u32-be buf 0 (d-attribute datom))
    (encode-u64-be buf 4 (d-entity datom))
    (encode-u64-be buf 12 (d-tx datom))
    buf))

(defun encode-ea-key (datom)
  "Encode datom as EA key for current-value lookups.
   Layout: [entity:8][attribute:4] = 12 bytes."
  (let ((buf (make-array 12 :element-type '(unsigned-byte 8))))
    (encode-u64-be buf 0 (d-entity datom))
    (encode-u32-be buf 8 (d-attribute datom))
    buf))
