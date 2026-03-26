(defpackage woo.ssl
  (:use :cl)
  (:import-from :cl+ssl
                :with-new-ssl
                :install-nonblock-flag
                :ssl-set-fd
                :ssl-set-accept-state
                :*default-cipher-list*
                :ssl-set-cipher-list
                :with-pem-password
                :install-key-and-cert)
  (:import-from :woo.ev.socket
                :socket-fd
                :socket-ssl-handle)
  (:import-from :woo.ssl.alpn
                :ssl-ctx-set-alpn-select-callback
                :ssl-get0-alpn-selected)
  (:export :init-ssl-handle
           :get-negotiated-protocol
           :*alpn-protocols*
           :configure-alpn))
(in-package :woo.ssl)

(defvar *alpn-protocols* '("http/1.1")
  "List of ALPN protocols to advertise, in preference order.
   Set to '(\"h2\" \"http/1.1\") to enable HTTP/2.
   Default is HTTP/1.1 only for backward compatibility.")

(defvar *alpn-configured-p* nil
  "Whether ALPN has been configured on the SSL context.")

(defun configure-alpn ()
  "Configure ALPN on the global SSL context.
   This should be called once before accepting connections.
   It's automatically called by init-ssl-handle if not already done."
  (unless *alpn-configured-p*
    (handler-case
        (progn
          ;; Access the SSL context from cl+ssl's global context
          ;; The global context stores the raw SSL_CTX pointer
          (let ((ctx cl+ssl::*ssl-global-context*))
            (when ctx
              (ssl-ctx-set-alpn-select-callback ctx *alpn-protocols*)
              (setf *alpn-configured-p* t)
              (vom:info "ALPN configured with protocols: ~A" *alpn-protocols*))))
      (error (e)
        (vom:warn "Failed to configure ALPN: ~A" e)))))

(defun init-ssl-handle (socket ssl-cert-file ssl-key-file ssl-key-password)
  "Initialize SSL handle for a socket.
   Sets up TLS with the provided certificate and key.
   Configures ALPN if not already done."
  ;; Configure ALPN once on first connection
  (configure-alpn)

  (let ((client-fd (socket-fd socket)))
    (with-new-ssl (handle)
      (install-nonblock-flag client-fd)
      (ssl-set-fd handle client-fd)
      (ssl-set-accept-state handle)
      (when *default-cipher-list*
        (ssl-set-cipher-list handle *default-cipher-list*))
      (setf (socket-ssl-handle socket) handle)
      (with-pem-password ((or ssl-key-password ""))
        (install-key-and-cert
         handle
         ssl-key-file
         ssl-cert-file))
      socket)))

(defun get-negotiated-protocol (socket)
  "Get the ALPN-negotiated protocol for this socket.
   Returns the protocol string (e.g., \"h2\" or \"http/1.1\") or NIL
   if no protocol was negotiated (e.g., client doesn't support ALPN)."
  (let ((ssl-handle (socket-ssl-handle socket)))
    (when ssl-handle
      (ssl-get0-alpn-selected ssl-handle))))
