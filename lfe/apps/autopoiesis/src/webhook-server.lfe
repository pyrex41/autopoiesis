(defmodule webhook-server
  (behaviour gen_server)
  (export (start_link 0) (stop 0)
          (init 1) (handle_call 3) (handle_cast 2) (handle_info 2)
          (terminate 2) (code_change 3)))

;;; Client API

(defun start_link ()
  (gen_server:start_link #(local webhook-server) 'webhook-server '() '()))

(defun stop ()
  (gen_server:stop 'webhook-server))

;;; gen_server callbacks

(defun init (_args)
  (let* ((port (application:get_env 'autopoiesis 'http_port 4007))
         (dispatch (cowboy_router:compile
                     `(#(_ (#("/webhook" webhook-handler ())
                            #("/health" health-handler ())))))))
    ;; Stop any stale listener from a previous unclean shutdown
    (catch (cowboy:stop_listener 'http_listener))
    (start-listener-with-retry port dispatch 3)))

(defun start-listener-with-retry (port dispatch retries)
  "Try to start cowboy listener, retrying on eaddrinuse."
  (case (cowboy:start_clear 'http_listener
          `(#(port ,port))
          `#M(env #M(dispatch ,dispatch)))
    (`#(ok ,_pid)
     (logger:info "Webhook server started on port ~p" (list port))
     `#(ok #M(port ,port)))
    (`#(error eaddrinuse) (when (> retries 0))
     (logger:info "Port ~p in use, retrying in 500ms (~p retries left)"
                  (list port retries))
     (timer:sleep 500)
     (catch (cowboy:stop_listener 'http_listener))
     (start-listener-with-retry port dispatch (- retries 1)))
    (`#(error ,reason)
     (logger:error "Failed to start webhook server: ~p" (list reason))
     `#(stop ,reason))))

(defun handle_call (_msg _from state)
  `#(reply ok ,state))

(defun handle_cast (_msg state)
  `#(noreply ,state))

(defun handle_info (_msg state)
  `#(noreply ,state))

(defun terminate (_reason _state)
  (cowboy:stop_listener 'http_listener)
  (logger:info "Webhook server stopped")
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))
