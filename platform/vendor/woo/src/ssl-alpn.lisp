(in-package :cl-user)
(defpackage woo.ssl.alpn
  (:use :cl)
  (:import-from :cffi
                :defcfun
                :defcallback
                :foreign-funcall
                :foreign-alloc
                :foreign-free
                :mem-ref
                :mem-aref
                :with-foreign-object
                :with-foreign-pointer
                :null-pointer-p
                :null-pointer
                :pointer
                :inc-pointer)
  (:import-from :trivial-utf-8
                :string-to-utf-8-bytes)
  (:export :ssl-ctx-set-alpn-select-callback
           :ssl-get0-alpn-selected
           :make-alpn-selector
           :+ssl-tlsext-err-ok+
           :+ssl-tlsext-err-alert-fatal+
           :+ssl-tlsext-err-noack+))
(in-package :woo.ssl.alpn)

;; OpenSSL ALPN callback return values
(defconstant +ssl-tlsext-err-ok+ 0)
(defconstant +ssl-tlsext-err-alert-fatal+ 2)
(defconstant +ssl-tlsext-err-noack+ 3)

;; FFI bindings to OpenSSL ALPN functions
;;
;; SSL_CTX_set_alpn_select_cb:
;; void SSL_CTX_set_alpn_select_cb(SSL_CTX *ctx,
;;                                 int (*cb)(SSL *ssl,
;;                                           const unsigned char **out,
;;                                           unsigned char *outlen,
;;                                           const unsigned char *in,
;;                                           unsigned int inlen,
;;                                           void *arg),
;;                                 void *arg);

(cffi:defcfun ("SSL_CTX_set_alpn_select_cb" %ssl-ctx-set-alpn-select-cb) :void
  (ctx :pointer)
  (cb :pointer)
  (arg :pointer))

;; SSL_get0_alpn_selected:
;; void SSL_get0_alpn_selected(const SSL *ssl,
;;                             const unsigned char **data,
;;                             unsigned int *len);

(cffi:defcfun ("SSL_get0_alpn_selected" %ssl-get0-alpn-selected) :void
  (ssl :pointer)
  (data :pointer)   ; const unsigned char **
  (len :pointer))   ; unsigned int *

(defun ssl-get0-alpn-selected (ssl-handle)
  "Get the ALPN protocol selected during handshake.
   Returns the protocol as a string, or NIL if no protocol was negotiated."
  (cffi:with-foreign-objects ((data-ptr :pointer)
                               (len-ptr :unsigned-int))
    (%ssl-get0-alpn-selected ssl-handle data-ptr len-ptr)
    (let ((data (cffi:mem-ref data-ptr :pointer))
          (len (cffi:mem-ref len-ptr :unsigned-int)))
      (unless (or (cffi:null-pointer-p data) (zerop len))
        (let ((result (make-string len)))
          (dotimes (i len)
            (setf (char result i)
                  (code-char (cffi:mem-aref data :unsigned-char i))))
          result)))))

(defun parse-alpn-protocols (data len)
  "Parse ALPN protocol list from wire format into list of strings.
   Wire format: length-prefixed strings (1 byte length + string bytes)."
  (let ((protocols nil)
        (idx 0))
    (loop while (< idx len)
          for proto-len = (cffi:mem-aref data :unsigned-char idx)
          do (incf idx)
             (when (and (> proto-len 0) (<= (+ idx proto-len) len))
               (let ((proto (make-string proto-len)))
                 (dotimes (i proto-len)
                   (setf (char proto i)
                         (code-char (cffi:mem-aref data :unsigned-char (+ idx i)))))
                 (push proto protocols)))
             (incf idx proto-len))
    (nreverse protocols)))

(defun find-protocol-in-buffer (data len protocol)
  "Find a protocol string in the ALPN wire format buffer.
   Returns (values pointer length) if found, NIL otherwise.
   The pointer points directly into the input buffer."
  (let ((idx 0)
        (proto-len (length protocol)))
    (loop while (< idx len)
          for entry-len = (cffi:mem-aref data :unsigned-char idx)
          do (when (= entry-len proto-len)
               ;; Check if this entry matches
               (let ((match t))
                 (dotimes (i proto-len)
                   (unless (char= (char protocol i)
                                  (code-char (cffi:mem-aref data :unsigned-char (+ idx 1 i))))
                     (setf match nil)
                     (return)))
                 (when match
                   (return-from find-protocol-in-buffer
                     (values (cffi:inc-pointer data (1+ idx)) proto-len)))))
             (incf idx (1+ entry-len)))
    nil))

;; Global variable to hold the ALPN selector function
;; This is needed because the callback doesn't have access to Lisp closures
(defvar *alpn-selector* nil
  "Function that selects ALPN protocol from client's list.
   Should return protocol string or NIL.")

(defvar *preferred-protocols* '("http/1.1")
  "List of preferred ALPN protocols in order of preference.")

(cffi:defcallback alpn-select-cb :int
    ((ssl :pointer) (out :pointer) (outlen :pointer)
     (in :pointer) (inlen :unsigned-int) (arg :pointer))
  "ALPN selection callback invoked by OpenSSL during TLS handshake."
  (declare (ignore ssl arg))
  (handler-case
      (let ((client-protocols (parse-alpn-protocols in inlen)))
        ;; Try each preferred protocol in order
        (dolist (proto *preferred-protocols*)
          (when (member proto client-protocols :test #'string=)
            ;; Found a match - point output to the protocol in the input buffer
            (multiple-value-bind (ptr len)
                (find-protocol-in-buffer in inlen proto)
              (when ptr
                (setf (cffi:mem-ref out :pointer) ptr)
                (setf (cffi:mem-ref outlen :unsigned-char) len)
                (return-from alpn-select-cb +ssl-tlsext-err-ok+)))))
        ;; No match found - no protocol selected
        +ssl-tlsext-err-noack+)
    (error (e)
      (vom:error "ALPN callback error: ~A" e)
      +ssl-tlsext-err-alert-fatal+)))

(defun ssl-ctx-set-alpn-select-callback (ssl-ctx preferred-protocols)
  "Set up ALPN protocol selection on an SSL context.
   PREFERRED-PROTOCOLS is a list of protocol strings in preference order,
   e.g., '(\"h2\" \"http/1.1\")."
  (setf *preferred-protocols* preferred-protocols)
  (%ssl-ctx-set-alpn-select-cb ssl-ctx
                                (cffi:callback alpn-select-cb)
                                (cffi:null-pointer)))

(defun make-alpn-selector (preferred-protocols)
  "Create an ALPN selector function.
   Returns first matching protocol from client's list, or NIL.
   This is a convenience function - the actual selection uses *preferred-protocols*."
  (lambda (client-protocols)
    (dolist (proto preferred-protocols)
      (when (member proto client-protocols :test #'string=)
        (return proto)))))
