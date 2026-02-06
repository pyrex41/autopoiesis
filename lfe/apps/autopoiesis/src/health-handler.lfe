(defmodule health-handler
  (export (init 2)))

(defun init (req0 state)
  (case (cowboy_req:method req0)
    (#"GET" (handle-get req0 state))
    (_ (reply-error 405 #"method_not_allowed" req0 state))))

(defun handle-get (req0 state)
  (try
    (let* ((cond-status (conductor:status))
           (tick-count (maps:get 'tick-count cond-status 0))
           (queue-length (maps:get 'event-queue-length cond-status 0))
           (health-status (if (and (> tick-count 0) (< queue-length 1000))
                              #"ok"
                              #"degraded"))
           (body (jsx:encode
                   `#M(status ,health-status
                       tick_count ,tick-count
                       event_queue_length ,queue-length
                       events_processed ,(maps:get 'events-processed cond-status 0)
                       timers_fired ,(maps:get 'timers-fired cond-status 0)))))
      (reply-json 200 body req0 state))
    (catch
      (`#(,_type ,_reason ,_stack)
       (let ((body (jsx:encode `#M(status #"error" message #"conductor unavailable"))))
         (reply-json 503 body req0 state))))))

(defun reply-json (status body req state)
  (let ((req2 (cowboy_req:reply status
                #M(#"content-type" #"application/json")
                body req)))
    `#(ok ,req2 ,state)))

(defun reply-error (status error-key req state)
  (let ((body (iolist_to_binary
                (list #"{\"error\":\"" error-key #"\"}"))))
    (reply-json status body req state)))
