(in-package :cl-user)
(defpackage woo.http2.constants
  (:use :cl)
  (:export ;; Frame types (RFC 9113 Section 6)
           :+frame-data+
           :+frame-headers+
           :+frame-priority+
           :+frame-rst-stream+
           :+frame-settings+
           :+frame-push-promise+
           :+frame-ping+
           :+frame-goaway+
           :+frame-window-update+
           :+frame-continuation+
           ;; Flags
           :+flag-end-stream+
           :+flag-end-headers+
           :+flag-padded+
           :+flag-priority+
           :+flag-ack+
           ;; Settings identifiers
           :+settings-header-table-size+
           :+settings-enable-push+
           :+settings-max-concurrent-streams+
           :+settings-initial-window-size+
           :+settings-max-frame-size+
           :+settings-max-header-list-size+
           ;; Error codes
           :+no-error+
           :+protocol-error+
           :+internal-error+
           :+flow-control-error+
           :+settings-timeout+
           :+stream-closed+
           :+frame-size-error+
           :+refused-stream+
           :+cancel+
           :+compression-error+
           :+connect-error+
           :+enhance-your-calm+
           :+inadequate-security+
           :+http-1-1-required+
           ;; Defaults
           :+default-header-table-size+
           :+default-initial-window-size+
           :+default-max-frame-size+
           :+max-frame-size-limit+
           :+connection-preface+
           :+connection-preface-length+))
(in-package :woo.http2.constants)

;; Frame types (RFC 9113 Section 6)
(defconstant +frame-data+ #x0)
(defconstant +frame-headers+ #x1)
(defconstant +frame-priority+ #x2)
(defconstant +frame-rst-stream+ #x3)
(defconstant +frame-settings+ #x4)
(defconstant +frame-push-promise+ #x5)
(defconstant +frame-ping+ #x6)
(defconstant +frame-goaway+ #x7)
(defconstant +frame-window-update+ #x8)
(defconstant +frame-continuation+ #x9)

;; Frame flags
(defconstant +flag-end-stream+ #x1)
(defconstant +flag-end-headers+ #x4)
(defconstant +flag-padded+ #x8)
(defconstant +flag-priority+ #x20)
(defconstant +flag-ack+ #x1)

;; Settings identifiers (RFC 9113 Section 6.5.2)
(defconstant +settings-header-table-size+ #x1)
(defconstant +settings-enable-push+ #x2)
(defconstant +settings-max-concurrent-streams+ #x3)
(defconstant +settings-initial-window-size+ #x4)
(defconstant +settings-max-frame-size+ #x5)
(defconstant +settings-max-header-list-size+ #x6)

;; Error codes (RFC 9113 Section 7)
(defconstant +no-error+ #x0)
(defconstant +protocol-error+ #x1)
(defconstant +internal-error+ #x2)
(defconstant +flow-control-error+ #x3)
(defconstant +settings-timeout+ #x4)
(defconstant +stream-closed+ #x5)
(defconstant +frame-size-error+ #x6)
(defconstant +refused-stream+ #x7)
(defconstant +cancel+ #x8)
(defconstant +compression-error+ #x9)
(defconstant +connect-error+ #xA)
(defconstant +enhance-your-calm+ #xB)
(defconstant +inadequate-security+ #xC)
(defconstant +http-1-1-required+ #xD)

;; Default values (RFC 9113 Section 6.5.2)
(defconstant +default-header-table-size+ 4096)
(defconstant +default-initial-window-size+ 65535)
(defconstant +default-max-frame-size+ 16384)
(defconstant +max-frame-size-limit+ 16777215)  ; 2^24 - 1

;; Connection preface (RFC 9113 Section 3.4)
(defconstant +connection-preface-length+ 24)
(defvar +connection-preface+
  (make-array 24 :element-type '(unsigned-byte 8)
              :initial-contents '(#x50 #x52 #x49 #x20 #x2a #x20 #x48 #x54
                                  #x54 #x50 #x2f #x32 #x2e #x30 #x0d #x0a
                                  #x0d #x0a #x53 #x4d #x0d #x0a #x0d #x0a)))
;; "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
