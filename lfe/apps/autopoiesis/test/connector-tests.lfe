(defmodule connector-tests
  (export all))

;;; EUnit tests for the HTTP connector layer.
;;; Run with: rebar3 eunit --module=connector-tests
;;;
;;; Tests: webhook-handler, health-handler, webhook-server

;;; ============================================================
;;; Health endpoint tests
;;; ============================================================

(defun health_endpoint_test ()
  "GET /health should return 200 with status ok."
  (with-running-app
    (lambda ()
      (case (httpc:request 'get #("http://localhost:4007/health" ()) "" '())
        (`#(ok #(,status-line ,_headers ,body))
         (let ((`#(,_ver ,code ,_reason) status-line))
           (assert-equal 200 code)
           (let ((decoded (jsx:decode (list_to_binary body) '(return_maps))))
             (assert-equal #"ok" (maps:get #"status" decoded)))))
        (`#(error ,reason)
         (error `#(http-request-failed ,reason)))))))

(defun health_wrong_method_test ()
  "POST /health should return 405."
  (with-running-app
    (lambda ()
      (case (httpc:request 'post
              #("http://localhost:4007/health"
                ()
                "application/json"
                "{}") "" '())
        (`#(ok #(,status-line ,_headers ,_body))
         (let ((`#(,_ver ,code ,_reason) status-line))
           (assert-equal 405 code)))
        (`#(error ,reason)
         (error `#(http-request-failed ,reason)))))))

;;; ============================================================
;;; Webhook endpoint tests
;;; ============================================================

(defun webhook_post_test ()
  "POST /webhook with valid JSON should return 200 with status accepted."
  (with-running-app
    (lambda ()
      (let ((body (binary_to_list
                    (jsx:encode `#M(type #"test_event" data #"hello")))))
        (case (httpc:request 'post
                `#("http://localhost:4007/webhook"
                   ()
                   "application/json"
                   ,body) "" '())
          (`#(ok #(,status-line ,_headers ,resp-body))
           (let ((`#(,_ver ,code ,_reason) status-line))
             (assert-equal 200 code)
             (let ((decoded (jsx:decode (list_to_binary resp-body) '(return_maps))))
               (assert-equal #"accepted" (maps:get #"status" decoded)))))
          (`#(error ,reason)
           (error `#(http-request-failed ,reason))))))))

(defun webhook_invalid_json_test ()
  "POST /webhook with invalid JSON should return 400."
  (with-running-app
    (lambda ()
      (case (httpc:request 'post
              #("http://localhost:4007/webhook"
                ()
                "application/json"
                "not valid json{{{") "" '())
        (`#(ok #(,status-line ,_headers ,_body))
         (let ((`#(,_ver ,code ,_reason) status-line))
           (assert-equal 400 code)))
        (`#(error ,reason)
         (error `#(http-request-failed ,reason)))))))

(defun webhook_wrong_method_test ()
  "GET /webhook should return 405."
  (with-running-app
    (lambda ()
      (case (httpc:request 'get #("http://localhost:4007/webhook" ()) "" '())
        (`#(ok #(,status-line ,_headers ,_body))
         (let ((`#(,_ver ,code ,_reason) status-line))
           (assert-equal 405 code)))
        (`#(error ,reason)
         (error `#(http-request-failed ,reason)))))))

(defun webhook_large_payload_test ()
  "POST /webhook with >1MB body should return 413."
  (with-running-app
    (lambda ()
      (let ((big-body (binary_to_list (binary:copy #"x" 1048577))))
        (case (httpc:request 'post
                `#("http://localhost:4007/webhook"
                   ()
                   "application/json"
                   ,big-body) "" '())
          (`#(ok #(,status-line ,_headers ,_body))
           (let ((`#(,_ver ,code ,_reason) status-line))
             (assert-equal 413 code)))
          (`#(error ,reason)
           (error `#(http-request-failed ,reason))))))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun with-running-app (test-fn)
  "Start inets and autopoiesis, run test, clean up."
  (try
    (progn
      (stop-app)
      (inets:start)
      (case (application:ensure_all_started 'autopoiesis)
        (`#(ok ,_apps)
         ;; Small delay for cowboy listener to be ready
         (timer:sleep 100)
         (funcall test-fn))
        (`#(error ,reason)
         (error `#(setup-failed ,reason))))
      (stop-app))
    (catch
      (`#(,type ,reason ,_stack)
       (stop-app)
       (error `#(test-exception ,type ,reason))))))

(defun stop-app ()
  "Stop autopoiesis and ensure cowboy listener is cleaned up."
  (application:stop 'autopoiesis)
  (catch (cowboy:stop_listener 'http_listener))
  (timer:sleep 300))

(defun assert-equal (expected actual)
  "Assert expected equals actual."
  (case (== expected actual)
    ('true 'ok)
    ('false (error `#(assertion-failed expected ,expected actual ,actual)))))
