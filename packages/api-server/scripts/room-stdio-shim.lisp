;;;; room-stdio-shim.lisp - A stdio MCP transport that proxies to the room HTTP /mcp.
;;;;
;;;; Headless coding-agent harnesses (Claude Code, Codex, opencode) surface
;;;; stdio MCP tools more reliably than Streamable-HTTP. This shim speaks the
;;;; MCP JSON-RPC dialect on stdin/stdout (newline-delimited JSON, the stdio
;;;; transport framing) and proxies every request to the already-running room
;;;; server's Streamable-HTTP /mcp endpoint with dexador, transparently
;;;; carrying the mcp-session-id the HTTP server hands back on `initialize`.
;;;;
;;;; Wire in to a real agent, e.g.:
;;;;   claude mcp add room -- sbcl --noinform --non-interactive \
;;;;     --load packages/api-server/scripts/room-stdio-shim.lisp
;;;; with ROOM_MCP_URL pointing at the running room server (default below).
;;;;
;;;;   ROOM_MCP_URL=http://127.0.0.1:8243/mcp
;;;;
;;;; Notifications (no id) get no response, exactly as MCP requires. Anything
;;;; we can't parse becomes a JSON-RPC parse error. All diagnostics go to
;;;; stderr so they never corrupt the stdout JSON-RPC channel.

(in-package #:cl-user)

;; Quietly load just what the shim needs: an HTTP client + JSON. We avoid
;; loading the whole platform here -- the shim is a thin proxy.
(handler-bind ((warning #'muffle-warning))
  (ql:quickload :dexador :silent t)
  (ql:quickload :com.inuoe.jzon :silent t))

(defpackage #:room-stdio-shim
  (:use #:cl)
  (:local-nicknames (#:jzon #:com.inuoe.jzon)))
(in-package #:room-stdio-shim)

(defparameter *mcp-url*
  (or (uiop:getenv "ROOM_MCP_URL") "http://127.0.0.1:8243/mcp")
  "The Streamable-HTTP /mcp endpoint of the running room server.")

(defvar *session-id* nil
  "mcp-session-id handed back by the HTTP server on initialize; replayed
   on every subsequent request so the proxied calls share one session.")

(defun log-err (fmt &rest args)
  "Diagnostics to stderr (never stdout, which is the JSON-RPC channel)."
  (format *error-output* "~&[room-stdio-shim] ~?~%" fmt args)
  (force-output *error-output*))

(defun http-forward (raw-json)
  "Forward one raw JSON-RPC request string to the HTTP /mcp endpoint.
   Returns (values response-body-string http-status). Captures and reuses the
   mcp-session-id header from the response (set on initialize)."
  (multiple-value-bind (body status headers)
      (handler-case
          (dex:post *mcp-url*
                    :headers (append '(("content-type" . "application/json")
                                       ("accept" . "application/json, text/event-stream"))
                                     (when *session-id*
                                       `(("mcp-session-id" . ,*session-id*))))
                    :content raw-json
                    :read-timeout 30)
        ;; dexador signals on non-2xx; recover the body/status so JSON-RPC
        ;; errors from the server still reach the client.
        (dexador.error:http-request-failed (e)
          (values (dexador.error:response-body e)
                  (dexador.error:response-status e)
                  (dexador.error:response-headers e))))
    (when (and (not *session-id*) (hash-table-p headers))
      (let ((sid (gethash "mcp-session-id" headers)))
        (when sid
          (setf *session-id* sid)
          (log-err "captured session-id ~a" sid))))
    (values body status)))

(defun jsonrpc-error-string (id code message)
  "Build a JSON-RPC 2.0 error response as a string."
  (jzon:stringify
   (let ((ht (make-hash-table :test 'equal)))
     (setf (gethash "jsonrpc" ht) "2.0"
           (gethash "id" ht) (or id 'null)
           (gethash "error" ht)
           (let ((e (make-hash-table :test 'equal)))
             (setf (gethash "code" e) code
                   (gethash "message" e) message)
             e))
     ht)))

(defun request-has-id-p (raw)
  "True if the parsed JSON-RPC request carries an id (a request, not a
   notification). Parses RAW defensively."
  (handler-case
      (let ((obj (jzon:parse raw)))
        (and (hash-table-p obj)
             (nth-value 1 (gethash "id" obj))))
    (error () nil)))

(defun emit (line)
  "Write one JSON line to stdout (the MCP stdio channel) and flush."
  (write-string line *standard-output*)
  (write-char #\Newline *standard-output*)
  (force-output *standard-output*))

(defun run ()
  (log-err "starting; proxying stdio MCP -> ~a" *mcp-url*)
  (loop
    (let ((line (read-line *standard-input* nil :eof)))
      (when (eq line :eof)
        (log-err "stdin closed; exiting")
        (return))
      (when (> (length (string-trim '(#\Space #\Tab #\Return) line)) 0)
        (handler-case
            (let ((has-id (request-has-id-p line)))
              (multiple-value-bind (body status) (http-forward line)
                (declare (ignore status))
                (cond
                  ;; Notification (no id): MCP forbids a response. The HTTP
                  ;; server returns 202 + empty body; emit nothing.
                  ((not has-id) nil)
                  ;; Request: relay the server's JSON-RPC response verbatim.
                  ((and body (> (length body) 0))
                   (emit (string-trim '(#\Space #\Tab #\Return #\Newline) body)))
                  ;; Request but empty body (shouldn't happen): synthesize error.
                  (t
                   (emit (jsonrpc-error-string nil -32603
                                               "Empty response from room server"))))))
          (error (e)
            (log-err "error handling line: ~a" e)
            ;; Best-effort: if it was a request, send an error back.
            (when (request-has-id-p line)
              (emit (jsonrpc-error-string nil -32603
                                          (format nil "shim error: ~a" e))))))))))

(run)
(uiop:quit 0)
