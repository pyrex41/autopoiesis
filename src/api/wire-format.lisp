;;;; wire-format.lisp - Hybrid JSON/MessagePack wire format
;;;;
;;;; The protocol uses two frame types over WebSocket:
;;;;
;;;;   TEXT frames  = JSON  (control messages: create, subscribe, ping, etc.)
;;;;   BINARY frames = MessagePack (data streams: thoughts, events, 3D updates)
;;;;
;;;; Clients detect the difference natively:
;;;;   ws.onmessage = (e) => {
;;;;     if (e.data instanceof ArrayBuffer) decodeMsgpack(e.data)
;;;;     else JSON.parse(e.data)
;;;;   }
;;;;
;;;; This gives us human-readable devtools for control flow
;;;; and compact binary for high-frequency data.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Wire Format Types
;;; ═══════════════════════════════════════════════════════════════════

(deftype wire-format ()
  "Supported wire formats for WebSocket messages."
  '(member :json :msgpack))

(defparameter *control-format* :json
  "Format for control messages (infrequent, human-readable).")

(defparameter *stream-format* :msgpack
  "Format for data stream messages (frequent, compact).")

;;; ═══════════════════════════════════════════════════════════════════
;;; Data categories - which messages use which format
;;; ═══════════════════════════════════════════════════════════════════

(defvar *stream-message-types*
  '("event" "thought_added" "agent_state_changed" "blocking_request"
    "holodeck_frame" "metrics_update" "position_update")
  "Message types that are sent as binary (MessagePack) data streams.
These are high-frequency push messages from server to client.")

(defun stream-message-p (msg-type)
  "Return T if MSG-TYPE should be sent as a binary data stream."
  (member msg-type *stream-message-types* :test #'equal))

;;; ═══════════════════════════════════════════════════════════════════
;;; JSON Encoding (text frames - control messages)
;;; ═══════════════════════════════════════════════════════════════════

(defun encode-json (data)
  "Encode DATA as a JSON string for text WebSocket frames."
  (com.inuoe.jzon:stringify data))

(defun decode-json (string)
  "Decode a JSON string from a text WebSocket frame."
  (handler-case
      (com.inuoe.jzon:parse string)
    (error (e)
      (log:warn "JSON decode error: ~a" e)
      nil)))

;;; ═══════════════════════════════════════════════════════════════════
;;; MessagePack Encoding (binary frames - data streams)
;;; ═══════════════════════════════════════════════════════════════════

(defun encode-msgpack (data)
  "Encode DATA as a MessagePack byte vector for binary WebSocket frames.
Converts hash-tables to alists for cl-messagepack compatibility."
  (let ((messagepack:*encode-alist-as-map* t))
    (messagepack:encode (prepare-for-msgpack data))))

(defun decode-msgpack (bytes)
  "Decode a MessagePack byte vector from a binary WebSocket frame."
  (let ((messagepack:*decoder-prefers-alists* t)
        (messagepack:*decode-bin-as-string* t))
    (handler-case
        (messagepack:decode bytes)
      (error (e)
        (log:warn "MessagePack decode error: ~a" e)
        nil))))

(defun string-keyed-plist-p (list)
  "Return T if LIST looks like a string-keyed plist (alternating string keys and values)."
  (and (consp list)
       (evenp (length list))
       (loop for (k v) on list by #'cddr
             always (stringp k))))

(defun prepare-for-msgpack (data)
  "Recursively convert hash-tables and string-keyed plists to alists for MessagePack encoding.
cl-messagepack encodes alists as maps when *encode-alist-as-map* is T."
  (typecase data
    (hash-table
     (let ((alist nil))
       (maphash (lambda (k v)
                  (push (cons k (prepare-for-msgpack v)) alist))
                data)
       (nreverse alist)))
    (null nil)  ; CL NIL -> MessagePack nil, not empty array
    (list
     (if (string-keyed-plist-p data)
         ;; Convert string-keyed plist to alist for map encoding
         (loop for (k v) on data by #'cddr
               collect (cons k (prepare-for-msgpack v)))
         ;; Regular list -> array
         (mapcar #'prepare-for-msgpack data)))
    (symbol (string-downcase (symbol-name data)))  ; safety net for stray keywords
    (t data)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Unified Encode/Decode
;;; ═══════════════════════════════════════════════════════════════════

(defun encode-control (data)
  "Encode a control message (JSON text frame).
Used for: responses to client requests, errors, subscription confirmations."
  (encode-json data))

(defun encode-stream (data)
  "Encode a data stream message (MessagePack binary frame).
Used for: pushed events, thought updates, 3D frame data, metrics."
  (encode-msgpack data))

(defun encode-auto (data)
  "Auto-select encoding based on message type.
Looks at the 'type' field to decide JSON vs MessagePack."
  (let ((msg-type (typecase data
                    (hash-table (gethash "type" data))
                    (list (cdr (assoc "type" data :test #'equal)))
                    (t nil))))
    (if (and msg-type (stream-message-p msg-type))
        (values (encode-stream data) :binary)
        (values (encode-control data) :text))))

;;; ═══════════════════════════════════════════════════════════════════
;;; WebSocket Send Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun ws-send-text (ws string)
  "Send a JSON text frame."
  (websocket-driver:send ws string))

(defun ws-send-binary (ws bytes)
  "Send a MessagePack binary frame."
  (websocket-driver:send-binary ws bytes))

(defun ws-send-auto (ws data)
  "Send data over WebSocket, auto-selecting text or binary format."
  (multiple-value-bind (encoded frame-type) (encode-auto data)
    (if (eq frame-type :binary)
        (ws-send-binary ws encoded)
        (ws-send-text ws encoded))))
