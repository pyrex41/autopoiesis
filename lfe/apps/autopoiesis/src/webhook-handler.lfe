(defmodule webhook-handler
  (export (init 2)))

(defun init (req0 state)
  (case (cowboy_req:method req0)
    (#"POST" (handle-post req0 state))
    (_ (reply-error 405 #"method_not_allowed" req0 state))))

(defun handle-post (req0 state)
  (case (cowboy_req:read_body req0)
    (`#(ok ,body ,req1)
     (if (> (byte_size body) 1048576)
         (reply-error 413 #"payload_too_large" req1 state)
         (case (catch (jsx:decode body '(return_maps)))
           (`#(EXIT ,_reason)
            (reply-error 400 #"invalid_json" req1 state))
           (decoded
            (conductor:queue-event (normalize-event decoded))
            (reply-json 200 (jsx:encode `#M(status #"accepted")) req1 state)))))
    (`#(more ,_body ,req1)
     (reply-error 413 #"payload_too_large" req1 state))))

(defun normalize-event (json-map)
  "Convert JSON map (binary keys) to an atom-keyed map for conductor."
  (let ((event-type (maps:get #"type" json-map #"unknown")))
    `#M(type ,(binary_to_atom event-type 'utf8)
        payload ,json-map)))

(defun reply-json (status body req state)
  (let ((req2 (cowboy_req:reply status
                #M(#"content-type" #"application/json")
                body req)))
    `#(ok ,req2 ,state)))

(defun reply-error (status error-key req state)
  (let ((body (iolist_to_binary
                (list #"{\"error\":\"" error-key #"\"}"))))
    (reply-json status body req state)))
