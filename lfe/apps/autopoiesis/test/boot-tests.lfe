(defmodule boot-tests
  (export all))

;;; EUnit tests for application boot and initial state verification.
;;; Run with: rebar3 eunit --module=boot-tests
;;;
;;; These tests verify:
;;; - Application can be started via application:ensure_all_started/1
;;; - All supervisors are running
;;; - Agent list is empty at boot
;;; - System is in a clean initial state

;;; ============================================================
;;; Application boot tests
;;; ============================================================

(defun application_started_test ()
  "Verify autopoiesis application can start and is running."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start the application with all dependencies
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       (logger:info "Boot test: Application started successfully")
       ;; Verify it's in the running apps list
       (let ((running-apps (application:which_applications)))
         (assert-truthy
           (lists:any
             (lambda (app)
               (case app
                 (`#(autopoiesis ,_desc ,_vsn) 'true)
                 (_ 'false)))
             running-apps)))
       ;; Clean up
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

(defun supervisors_running_test ()
  "Verify all expected supervisors are running after boot."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start the application
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       ;; Check main supervisor
       (assert-supervisor-running 'autopoiesis-sup)

       ;; Check agent supervisor
       (assert-supervisor-running 'agent-sup)

       ;; Check connector supervisor
       (assert-supervisor-running 'connector-sup)

       ;; Check conductor (a worker, not a supervisor)
       (assert-process-running 'conductor)

       ;; Clean up
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

(defun agent_list_empty_test ()
  "Verify no agents are running at boot."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start the application
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       ;; Check agent list is empty
       (let ((agents (agent-sup:list-agents)))
         (case agents
           ('() 'ok)
           (non-empty
             (progn
               (application:stop 'autopoiesis)
               (error `#(expected-empty-agent-list-got ,non-empty))))))

       ;; Clean up
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

;;; ============================================================
;;; Individual component boot tests
;;; ============================================================

(defun start_link_autopoiesis_sup_test ()
  "Test starting the main supervisor directly."
  ;; Ensure clean state - stop app if running
  (ensure-clean-state)
  (catch (unregister 'autopoiesis-sup))
  (catch (unregister 'agent-sup))
  (catch (unregister 'connector-sup))
  (catch (unregister 'conductor))

  ;; Start the supervisor
  (case (autopoiesis-sup:start_link)
    (`#(ok ,pid)
     (progn
       (assert-truthy (is_pid pid))
       (assert-truthy (is_process_alive pid))
       ;; Verify it's registered
       (assert-equal pid (whereis 'autopoiesis-sup))
       ;; Clean up - use unlink to avoid EXIT signal killing test process
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (error-result
      (error `#(supervisor-start-failed ,error-result)))))

(defun start_link_agent_sup_test ()
  "Test starting the agent supervisor directly."
  ;; Ensure clean state - stop app if running
  (ensure-clean-state)
  (catch (unregister 'agent-sup))

  ;; Start the supervisor
  (case (agent-sup:start_link)
    (`#(ok ,pid)
     (progn
       (assert-truthy (is_pid pid))
       (assert-truthy (is_process_alive pid))
       ;; Verify it's registered
       (assert-equal pid (whereis 'agent-sup))
       ;; Verify initial children list is empty
       (let ((children (agent-sup:list-agents)))
         (assert-equal '() children))
       ;; Clean up - use unlink to avoid EXIT signal killing test process
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (error-result
      (error `#(agent-sup-start-failed ,error-result)))))

(defun start_link_connector_sup_test ()
  "Test starting the connector supervisor directly."
  ;; Ensure clean state - stop app if running
  (ensure-clean-state)
  (catch (unregister 'connector-sup))

  ;; Start the supervisor
  (case (connector-sup:start_link)
    (`#(ok ,pid)
     (progn
       (assert-truthy (is_pid pid))
       (assert-truthy (is_process_alive pid))
       ;; Verify it's registered
       (assert-equal pid (whereis 'connector-sup))
       ;; Clean up - use unlink to avoid EXIT signal killing test process
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (error-result
      (error `#(connector-sup-start-failed ,error-result)))))

;;; ============================================================
;;; Supervisor hierarchy tests
;;; ============================================================

(defun supervisor_children_test ()
  "Verify the supervisor child hierarchy is correct."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start the application
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       ;; Get children of main supervisor
       (let ((children (supervisor:which_children 'autopoiesis-sup)))
         ;; Should have exactly 3 children: agent-sup, connector-sup, and conductor
         (assert-equal 3 (length children))

         ;; Check all expected children are present
         (assert-truthy (has-child-id 'agent-sup children))
         (assert-truthy (has-child-id 'connector-sup children))
         (assert-truthy (has-child-id 'conductor children)))

       ;; Clean up
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

(defun supervisor_strategy_test ()
  "Verify supervisor strategies are configured correctly."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start the application
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       ;; Main supervisor should use one_for_one
       (let ((main-strategy (get-supervisor-strategy 'autopoiesis-sup)))
         (assert-equal 'one_for_one main-strategy))

       ;; Agent supervisor should use simple_one_for_one
       (let ((agent-strategy (get-supervisor-strategy 'agent-sup)))
         (assert-equal 'simple_one_for_one agent-strategy))

       ;; Connector supervisor should use one_for_one
       (let ((connector-strategy (get-supervisor-strategy 'connector-sup)))
         (assert-equal 'one_for_one connector-strategy))

       ;; Clean up
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

;;; ============================================================
;;; Application metadata tests
;;; ============================================================

(defun application_metadata_test ()
  "Verify application metadata is correct."
  ;; Unload first if already loaded
  (catch (application:unload 'autopoiesis))

  (let ((app-key (application:load 'autopoiesis)))
    (case app-key
      ('ok
       (progn
         ;; Check description
         (let ((desc (application:get_key 'autopoiesis 'description)))
           (case desc
             (`#(ok ,_desc-str) 'ok)
             (_ (error 'missing-description))))

         ;; Check version
         (let ((vsn (application:get_key 'autopoiesis 'vsn)))
           (case vsn
             (`#(ok "0.1.0") 'ok)
             (other (error `#(unexpected-version ,other)))))

         ;; Check mod (application callback)
         (let ((mod (application:get_key 'autopoiesis 'mod)))
           (case mod
             ;; Module name should be autopoiesis-app (with hyphens)
             (`#(ok #(autopoiesis-app ())) 'ok)
             (other (error `#(unexpected-mod ,other)))))

         ;; Unload for clean state
         (application:unload 'autopoiesis)))
      (`#(error #(already_loaded autopoiesis))
       ;; If already loaded, that's OK - just verify the keys
       (progn
         ;; Check description
         (let ((desc (application:get_key 'autopoiesis 'description)))
           (case desc
             (`#(ok ,_desc-str) 'ok)
             (_ (error 'missing-description))))

         ;; Check version
         (let ((vsn (application:get_key 'autopoiesis 'vsn)))
           (case vsn
             (`#(ok "0.1.0") 'ok)
             (other (error `#(unexpected-version ,other)))))

         ;; Check mod (application callback)
         (let ((mod (application:get_key 'autopoiesis 'mod)))
           (case mod
             ;; Module name should be autopoiesis-app (with hyphens)
             (`#(ok #(autopoiesis-app ())) 'ok)
             (other (error `#(unexpected-mod ,other)))))))
      (error-val (error `#(app-load-failed ,error-val))))))

;;; ============================================================
;;; Boot edge cases and error handling
;;; ============================================================

(defun double_boot_test ()
  "Verify starting an already-running application is handled gracefully."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start once
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       ;; Try to start again
       (let ((result (application:ensure_all_started 'autopoiesis)))
         (case result
           ;; Should return ok with empty list (no new apps started)
           (`#(ok ()) 'ok)
           ;; Or should return ok with list of already started apps
           (`#(ok ,_apps) 'ok)
           (error-result
             (progn
               (application:stop 'autopoiesis)
               (error `#(double-boot-failed ,error-result))))))

       ;; Clean up
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

(defun stop_and_restart_test ()
  "Verify application can be stopped and restarted cleanly."
  ;; Stop if already running
  (ensure-clean-state)

  ;; Start
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_started-apps)
     (progn
       ;; Stop
       (catch (cowboy:stop_listener 'http_listener))
       (case (application:stop 'autopoiesis)
         ('ok
          (progn
            ;; Verify stopped
            (let ((running-apps (application:which_applications)))
              (assert-truthy
                (not (lists:any
                       (lambda (app)
                         (case app
                           (`#(autopoiesis ,_ ,_) 'true)
                           (_ 'false)))
                       running-apps))))

            ;; Restart
            (case (application:ensure_all_started 'autopoiesis)
              (`#(ok ,_restarted-apps)
               (progn
                 ;; Verify running again
                 (let ((running-apps2 (application:which_applications)))
                   (assert-truthy
                     (lists:any
                       (lambda (app)
                         (case app
                           (`#(autopoiesis ,_ ,_) 'true)
                           (_ 'false)))
                       running-apps2)))

                 ;; Clean up
                 (application:stop 'autopoiesis)))
              (`#(error ,reason)
               (error `#(restart-failed ,reason))))))
         (error-val (error `#(stop-failed ,error-val))))))
    (`#(error ,reason)
     (error `#(boot-failed ,reason)))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun ensure-clean-state ()
  "Stop app and cowboy listener to ensure clean state between tests."
  (application:stop 'autopoiesis)
  (catch (cowboy:stop_listener 'http_listener))
  (timer:sleep 300))

(defun assert-truthy (val)
  "Assert value is truthy (not false, not undefined)."
  (case val
    ('false (error 'assertion-failed))
    ('undefined (error 'assertion-failed))
    (_ 'ok)))

(defun assert-equal (expected actual)
  "Assert expected equals actual."
  (case (== expected actual)
    ('true 'ok)
    ('false (error `#(assertion-failed expected ,expected actual ,actual)))))

(defun assert-process-running (name)
  "Assert a process with given name is running and registered."
  (case (whereis name)
    ('undefined
     (error `#(process-not-registered ,name)))
    (pid
     (assert-truthy (is_process_alive pid)))))

(defun assert-supervisor-running (name)
  "Assert a supervisor with given name is running and registered."
  ;; Check if registered
  (case (whereis name)
    ('undefined
     (error `#(supervisor-not-registered ,name)))
    (pid
     (progn
       ;; Verify it's alive
       (assert-truthy (is_process_alive pid))

       ;; Verify it's a supervisor by calling a supervisor function
       (case (catch (supervisor:which_children name))
         (`#(EXIT ,_reason)
          (error `#(not-a-supervisor ,name)))
         (_children 'ok))))))

(defun has-child-id (id children)
  "Check if a child with given id exists in children list."
  (lists:any
    (lambda (child)
      (case child
        (`#(,child-id ,_pid ,_type ,_modules)
         (== id child-id))
        (_ 'false)))
    children))

(defun get-supervisor-strategy (name)
  "Get the restart strategy of a supervisor."
  (case (catch (supervisor:get_childspec name 'dummy))
    (`#(EXIT #(noproc ,_)) 'not-running)
    (`#(EXIT #(badarg ,_))
     ;; For simple_one_for_one, get_childspec may fail
     ;; Fall back to checking init callback manually
     (get-supervisor-strategy-from-module name))
    (_
     (get-supervisor-strategy-from-module name))))

(defun get-supervisor-strategy-from-module (name)
  "Get supervisor strategy by calling the init function directly."
  ;; Call the module's init function
  (case (catch (call name 'init '()))
    (`#(ok #(,flags ,_children))
     (maps:get 'strategy flags))
    (other
     (error `#(failed-to-get-strategy ,name ,other)))))
