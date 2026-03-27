(in-package :cl-user)
(defpackage woo.http2.hpack
  (:use :cl)
  (:import-from :trivial-utf-8
                :string-to-utf-8-bytes
                :utf-8-bytes-to-string)
  (:export :make-hpack-context
           :hpack-context
           :hpack-context-max-dynamic-table-size
           :hpack-encode-headers
           :hpack-decode-headers
           :hpack-context-update-size))
(in-package :woo.http2.hpack)

;; Static table (RFC 7541 Appendix A)
;; Index 1-61, stored as (name . value) pairs
(defvar *static-table*
  #(nil  ; Index 0 is invalid
    (":authority" . "")
    (":method" . "GET")
    (":method" . "POST")
    (":path" . "/")
    (":path" . "/index.html")
    (":scheme" . "http")
    (":scheme" . "https")
    (":status" . "200")
    (":status" . "204")
    (":status" . "206")
    (":status" . "304")
    (":status" . "400")
    (":status" . "404")
    (":status" . "500")
    ("accept-charset" . "")
    ("accept-encoding" . "gzip, deflate")
    ("accept-language" . "")
    ("accept-ranges" . "")
    ("accept" . "")
    ("access-control-allow-origin" . "")
    ("age" . "")
    ("allow" . "")
    ("authorization" . "")
    ("cache-control" . "")
    ("content-disposition" . "")
    ("content-encoding" . "")
    ("content-language" . "")
    ("content-length" . "")
    ("content-location" . "")
    ("content-range" . "")
    ("content-type" . "")
    ("cookie" . "")
    ("date" . "")
    ("etag" . "")
    ("expect" . "")
    ("expires" . "")
    ("from" . "")
    ("host" . "")
    ("if-match" . "")
    ("if-modified-since" . "")
    ("if-none-match" . "")
    ("if-range" . "")
    ("if-unmodified-since" . "")
    ("last-modified" . "")
    ("link" . "")
    ("location" . "")
    ("max-forwards" . "")
    ("proxy-authenticate" . "")
    ("proxy-authorization" . "")
    ("range" . "")
    ("referer" . "")
    ("refresh" . "")
    ("retry-after" . "")
    ("server" . "")
    ("set-cookie" . "")
    ("strict-transport-security" . "")
    ("transfer-encoding" . "")
    ("user-agent" . "")
    ("vary" . "")
    ("via" . "")
    ("www-authenticate" . "")))

(defstruct hpack-context
  "HPACK encoder/decoder context with dynamic table."
  (dynamic-table (make-array 0 :adjustable t :fill-pointer 0))
  (dynamic-table-size 0 :type fixnum)
  (max-dynamic-table-size 4096 :type fixnum))

(defun hpack-entry-size (name value)
  "Calculate entry size per RFC 7541 Section 4.1.
   Size = length of name + length of value + 32 bytes overhead."
  (+ 32
     (length name)
     (length value)))

(defun hpack-context-evict (ctx)
  "Evict entries from dynamic table until size <= max size."
  (loop while (and (> (length (hpack-context-dynamic-table ctx)) 0)
                   (> (hpack-context-dynamic-table-size ctx)
                      (hpack-context-max-dynamic-table-size ctx)))
        do (let* ((table (hpack-context-dynamic-table ctx))
                  (entry (aref table (1- (length table)))))
             ;; Remove oldest entry (at the end)
             (decf (hpack-context-dynamic-table-size ctx)
                   (hpack-entry-size (car entry) (cdr entry)))
             (vector-pop table))))

(defun hpack-context-add-entry (ctx name value)
  "Add entry to dynamic table (at the beginning, index 62)."
  (let ((size (hpack-entry-size name value)))
    (when (<= size (hpack-context-max-dynamic-table-size ctx))
      ;; Add to front by shifting all elements
      (let ((table (hpack-context-dynamic-table ctx)))
        (vector-push-extend nil table)
        ;; Shift elements right
        (loop for i from (1- (length table)) downto 1
              do (setf (aref table i) (aref table (1- i))))
        ;; Insert new entry at front
        (setf (aref table 0) (cons name value)))
      (incf (hpack-context-dynamic-table-size ctx) size)
      (hpack-context-evict ctx))))

(defun hpack-context-update-size (ctx new-size)
  "Update max dynamic table size and evict if necessary."
  (setf (hpack-context-max-dynamic-table-size ctx) new-size)
  (hpack-context-evict ctx))

(defun hpack-lookup-index (ctx index)
  "Look up entry by index (1-based).
   Indices 1-61 are static table, 62+ are dynamic table."
  (let ((static-len (1- (length *static-table*))))  ; 61 entries
    (cond
      ((zerop index)
       (error "Invalid HPACK index 0"))
      ((<= index static-len)
       (aref *static-table* index))
      (t
       (let ((dyn-idx (- index static-len 1))
             (dyn-table (hpack-context-dynamic-table ctx)))
         (when (< dyn-idx (length dyn-table))
           (aref dyn-table dyn-idx)))))))

(defun hpack-find-header (ctx name value)
  "Find header in tables. Returns (values index name-only-p).
   INDEX is the table index if found, NAME-ONLY-P is T if only name matches."
  ;; Search static table first
  (loop for i from 1 below (length *static-table*)
        for entry = (aref *static-table* i)
        when (string= (car entry) name)
        do (if (string= (cdr entry) value)
               (return-from hpack-find-header (values i nil))
               (return-from hpack-find-header (values i t))))
  ;; Search dynamic table
  (loop for i from 0 below (length (hpack-context-dynamic-table ctx))
        for entry = (aref (hpack-context-dynamic-table ctx) i)
        when (string= (car entry) name)
        do (let ((idx (+ 62 i)))
             (if (string= (cdr entry) value)
                 (return-from hpack-find-header (values idx nil))
                 (return-from hpack-find-header (values idx t)))))
  (values nil nil))

;;; Integer encoding/decoding (RFC 7541 Section 5.1)

(defun hpack-decode-integer (data start prefix-bits)
  "Decode HPACK integer starting at START with PREFIX-BITS prefix.
   Returns (values integer bytes-consumed)."
  (let* ((max-prefix (1- (ash 1 prefix-bits)))
         (value (logand (aref data start) max-prefix))
         (idx 1))
    (when (= value max-prefix)
      (loop for shift from 0 by 7
            for byte = (aref data (+ start idx))
            do (incf value (ash (logand byte #x7F) shift))
               (incf idx)
            while (logbitp 7 byte)))
    (values value idx)))

(defun hpack-encode-integer (value prefix-bits first-byte)
  "Encode HPACK integer with PREFIX-BITS prefix.
   FIRST-BYTE contains the non-prefix bits in the first byte.
   Returns list of bytes."
  (let ((max-prefix (1- (ash 1 prefix-bits))))
    (if (< value max-prefix)
        (list (logior first-byte value))
        (let ((bytes (list (logior first-byte max-prefix))))
          (decf value max-prefix)
          (loop while (>= value 128)
                do (push (logior #x80 (logand value #x7F)) bytes)
                   (setf value (ash value -7)))
          (push value bytes)
          (nreverse bytes)))))

;;; String encoding/decoding (RFC 7541 Section 5.2)

(defun hpack-decode-string (data start)
  "Decode HPACK string starting at START.
   Returns (values string bytes-consumed)."
  (let ((huffman-p (logbitp 7 (aref data start))))
    (multiple-value-bind (length consumed)
        (hpack-decode-integer data start 7)
      (let ((str-start (+ start consumed))
            (str-end (+ start consumed length)))
        (if huffman-p
            ;; TODO: Implement Huffman decoding
            ;; For now, we'll decode it as raw bytes (will fail for actual Huffman)
            (values (utf-8-bytes-to-string data :start str-start :end str-end)
                    (+ consumed length))
            (values (utf-8-bytes-to-string data :start str-start :end str-end)
                    (+ consumed length)))))))

(defun hpack-encode-string (string &key (huffman nil))
  "Encode HPACK string.
   Returns byte vector."
  (declare (ignore huffman))  ; TODO: Huffman encoding
  (let* ((bytes (string-to-utf-8-bytes string))
         (len (length bytes))
         (len-bytes (hpack-encode-integer len 7 0))
         (result (make-array (+ (length len-bytes) len)
                             :element-type '(unsigned-byte 8))))
    (loop for i from 0 below (length len-bytes)
          do (setf (aref result i) (nth i len-bytes)))
    (replace result bytes :start1 (length len-bytes))
    result))

;;; Header block decoding (RFC 7541 Section 6)

(defun hpack-decode-headers (ctx data &key (start 0) (end (length data)))
  "Decode HPACK header block.
   Returns list of (name . value) pairs as strings."
  (let ((headers nil)
        (idx start))
    (loop while (< idx end)
          for byte = (aref data idx)
          do (cond
               ;; Indexed Header Field (Section 6.1) - starts with 1
               ((logbitp 7 byte)
                (multiple-value-bind (index consumed)
                    (hpack-decode-integer data idx 7)
                  (let ((entry (hpack-lookup-index ctx index)))
                    (when entry
                      (push (cons (car entry) (cdr entry)) headers)))
                  (incf idx consumed)))

               ;; Literal Header Field with Incremental Indexing (Section 6.2.1) - starts with 01
               ((= (logand byte #xC0) #x40)
                (multiple-value-bind (index consumed)
                    (hpack-decode-integer data idx 6)
                  (incf idx consumed)
                  (let (name value)
                    (if (zerop index)
                        ;; New name
                        (multiple-value-bind (n c)
                            (hpack-decode-string data idx)
                          (setf name n)
                          (incf idx c))
                        ;; Indexed name
                        (setf name (car (hpack-lookup-index ctx index))))
                    (multiple-value-bind (v c)
                        (hpack-decode-string data idx)
                      (setf value v)
                      (incf idx c))
                    (hpack-context-add-entry ctx name value)
                    (push (cons name value) headers))))

               ;; Dynamic Table Size Update (Section 6.3) - starts with 001
               ((= (logand byte #xE0) #x20)
                (multiple-value-bind (size consumed)
                    (hpack-decode-integer data idx 5)
                  (hpack-context-update-size ctx size)
                  (incf idx consumed)))

               ;; Literal Header Field without Indexing (Section 6.2.2) - starts with 0000
               ;; Literal Header Field Never Indexed (Section 6.2.3) - starts with 0001
               (t
                (let ((prefix-bits 4))
                  (multiple-value-bind (index consumed)
                      (hpack-decode-integer data idx prefix-bits)
                    (incf idx consumed)
                    (let (name value)
                      (if (zerop index)
                          ;; New name
                          (multiple-value-bind (n c)
                              (hpack-decode-string data idx)
                            (setf name n)
                            (incf idx c))
                          ;; Indexed name
                          (setf name (car (hpack-lookup-index ctx index))))
                      (multiple-value-bind (v c)
                          (hpack-decode-string data idx)
                        (setf value v)
                        (incf idx c))
                      ;; Don't add to dynamic table
                      (push (cons name value) headers)))))))
    (nreverse headers)))

;;; Header block encoding

(defun hpack-encode-headers (ctx headers)
  "Encode headers to HPACK block.
   HEADERS is a list of (name . value) pairs.
   Uses literal without indexing for simplicity (can be optimized later)."
  (let ((parts nil))
    (dolist (header headers)
      (let* ((name (car header))
             (value (cdr header))
             (name-str (etypecase name
                         (string name)
                         (keyword (string-downcase (symbol-name name)))
                         (symbol (string-downcase (symbol-name name))))))
        ;; Try to find name in static/dynamic table
        (multiple-value-bind (index name-only-p)
            (hpack-find-header ctx name-str value)
          (cond
            ;; Full match - use indexed representation
            ((and index (not name-only-p))
             (let ((bytes (hpack-encode-integer index 7 #x80)))
               (push (make-array (length bytes)
                                 :element-type '(unsigned-byte 8)
                                 :initial-contents bytes)
                     parts)))
            ;; Name match - use literal with indexed name
            (index
             (let* ((name-bytes (hpack-encode-integer index 4 #x00))
                    (value-enc (hpack-encode-string value))
                    (part (make-array (+ (length name-bytes) (length value-enc))
                                      :element-type '(unsigned-byte 8))))
               (loop for i from 0 below (length name-bytes)
                     do (setf (aref part i) (nth i name-bytes)))
               (replace part value-enc :start1 (length name-bytes))
               (push part parts)))
            ;; No match - literal with new name
            (t
             (let* ((name-enc (hpack-encode-string name-str))
                    (value-enc (hpack-encode-string value))
                    (part (make-array (+ 1 (length name-enc) (length value-enc))
                                      :element-type '(unsigned-byte 8))))
               ;; Literal without indexing, new name (0000 0000)
               (setf (aref part 0) #x00)
               (replace part name-enc :start1 1)
               (replace part value-enc :start1 (1+ (length name-enc)))
               (push part parts)))))))
    ;; Concatenate all parts
    (let* ((total-len (reduce #'+ parts :key #'length))
           (result (make-array total-len :element-type '(unsigned-byte 8)))
           (idx 0))
      (dolist (part (nreverse parts))
        (replace result part :start1 idx)
        (incf idx (length part)))
      result)))
