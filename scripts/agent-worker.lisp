#!/usr/bin/env sbcl --script

(require :asdf)

;; Load Quicklisp for dependency resolution
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
                                        (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; Add project root to ASDF search path
;; Script is at <project>/scripts/agent-worker.lisp
;; Project root is one level up
(let ((project-root (make-pathname
                      :directory (butlast
                                  (pathname-directory
                                    (or *load-truename*
                                        *default-pathname-defaults*))))))
  (push project-root asdf:*central-registry*))

(asdf:load-system :autopoiesis)

(defpackage :autopoiesis.worker
  (:use :cl :autopoiesis.core :autopoiesis.agent :autopoiesis.snapshot)
  (:export
   #:*agent*
   #:*start-time*))

(in-package :autopoiesis.worker)

;; Protocol message comments
;;
;; LFE→CL messages:
;;   init: (:init :agent-id <id> :name <name>)
;;   heartbeat: (heartbeat agent-id timestamp)
;;   task: (task task-id description parameters)
;;   status-request: (status-request agent-id)
;;   snapshot: (snapshot agent-id)
;;   shutdown: (shutdown reason)
;;
;; CL→LFE messages:
;;   status: (status agent-id state info)
;;   task-result: (task-result task-id result)
;;   snapshot-result: (snapshot-result snapshot-id hash)
;;   heartbeat-ack: (heartbeat-ack timestamp)
;;   error: (error message details)

(defvar *agent* nil
  "Current agent instance running in this worker.")

(defvar *start-time* (get-universal-time)
  "Time when this worker was started.")

(defun send-response (sexpr)
  "Write S-expression to stdout and flush."
  (prin1 sexpr *standard-output*)
  (terpri *standard-output*)
  (finish-output *standard-output*))

(defun handle-inject-observation (msg)
  "Inject an observation into the agent's thought stream."
  (let ((content (getf (cdr msg) :content)))
    (let ((obs (autopoiesis.core:make-observation content :source :external)))
      (autopoiesis.core:stream-append (agent-thought-stream *agent*) obs)
      (send-response `(:ok :type :observation-injected)))))

(defun handle-init (msg)
  "Initialize the worker by restoring an agent from snapshot or creating new.
   Message format: (:init :agent-id <id> :name <name>)
   If a snapshot exists for AGENT-ID, restores from it. Otherwise creates
   a new agent. Starts the agent and sets *agent*."
  (let ((args (cdr msg)))
    (let ((agent-id (getf args :agent-id))
          (name (getf args :name "unnamed")))
      (handler-case
          (let* ((restored (when agent-id
                             (restore-agent-from-snapshot agent-id)))
                 (agent (or restored
                            (make-agent :name name))))
            (start-agent agent)
            (setf *agent* agent)
            (setf *start-time* (get-universal-time))
            (send-response `(:ok :type :init
                                 :agent-id ,(agent-id agent)
                                 :restored ,(not (null restored)))))
        (error (e)
          (send-response `(:error :type :init-failed
                                  :message ,(princ-to-string e))))))))

(defun handle-cognitive-cycle (msg)
  "Run one cognitive cycle on the current agent.
Counts thoughts added during the cycle and returns the result.
On error, sends a :cycle-failed response instead of crashing."
  (let ((environment (getf (cdr msg) :environment)))
    (handler-case
        (let* ((thoughts-before (stream-length (agent-thought-stream *agent*)))
               (result (cognitive-cycle *agent* environment))
               (thoughts-after (stream-length (agent-thought-stream *agent*))))
          (send-response `(:ok :type :cycle-complete
                               :result ,result
                               :thoughts-added ,(- thoughts-after thoughts-before))))
      (error (e)
        (send-response `(:error :type :cycle-failed
                                :message ,(princ-to-string e)))))))

(defun handle-snapshot (msg)
  "Create snapshot of current agent state."
  (declare (ignore msg))
  (let ((snapshot (make-snapshot (agent-to-sexpr *agent*))))
    (save-snapshot snapshot)
    (send-response `(:ok :type :snapshot-complete
                        :snapshot-id ,(snapshot-id snapshot)
                        :hash ,(snapshot-hash snapshot)))))

(defun handle-shutdown (msg)
  "Clean shutdown."
  (declare (ignore msg))
  (when *agent*
    (stop-agent *agent*)
    ;; Create final snapshot
    (let ((snapshot (make-snapshot (agent-to-sexpr *agent*)
                                   :metadata `(:shutdown-reason :command))))
      ;; Save it (assuming store is set up)
      (save-snapshot snapshot)))
  (send-response `(:ok :type :shutdown))
  (sb-ext:exit :code 0))

(defun send-heartbeat ()
  "Send periodic heartbeat to stdout."
  (when *agent*
    (let ((thoughts (autopoiesis.core:stream-length (agent-thought-stream *agent*)))
          (uptime (- (get-universal-time) *start-time*)))
      (send-response `(:heartbeat :thoughts ,thoughts :uptime-seconds ,uptime)))))

(defun start-heartbeat-thread ()
  "Start a thread that sends heartbeat every 10 seconds."
  (bt:make-thread
   (lambda ()
     (loop
       (sleep 10)
       (send-heartbeat)))
   :name "heartbeat-thread"))

(defun handle-command (command)
  "Dispatch command to handler."
  (case (car command)
    (:init (handle-init command))
    (:cognitive-cycle (handle-cognitive-cycle command))
    (:snapshot (handle-snapshot command))
    (:inject-observation (handle-inject-observation command))
    (:shutdown (handle-shutdown command))
    (otherwise (send-response `(:error :type :unknown-command
                                       :command ,(car command))))))

;; Main message processing loop
(loop
  (handler-case
      (let ((command (read *standard-input* nil :eof)))
        (if (eq command :eof)
            (progn
              ;; EOF: clean shutdown
              (when *agent*
                (stop-agent *agent*)
                (let ((snapshot (make-snapshot (agent-to-sexpr *agent*)
                                               :metadata `(:shutdown-reason :eof))))
                  (save-snapshot snapshot)))
              (return))
            (handle-command command)))
    (error (e)
      (send-response `(:error :type :parse-error :message ,(princ-to-string e))))))
