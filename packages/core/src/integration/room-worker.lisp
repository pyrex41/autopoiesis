;;;; room-worker.lisp - Orchestrator-spawned worker + fan-in into a shared room.
;;;;
;;;; The end-to-end loop the product hinges on:
;;;;   conductor dispatches :room-work -> run-room-work spawns a WORKER thread
;;;;   -> the worker forks its own speculative branch, runs ONE agent turn via
;;;;      the provider abstraction (provider-invoke -- grok via rho today, the
;;;;      long-lived codex app-server provider once its endpoint is up), POSTS
;;;;      the agent's output onto its branch, and registers the branch.
;;;;   Then the ORCHESTRATOR fans in (fan-in-room): it merges the staged
;;;;      branches sequentially -- independent facts union, a same-(E,A)
;;;;      divergence is FLAGGED for the lead, never silently lost.
;;;;
;;;; Work (parallel, per-worker branches) is separated from integration
;;;; (sequential, orchestrator/lead-gated) -- which is the product's design and
;;;; also what makes conflict detection well-defined (all staging precedes any
;;;; merge). Provider-agnostic: any provider drops into the same loop.
;;;;
;;;; Lives in the integration module (loaded after orchestration + substrate);
;;;; conductor's dispatch-event reaches run-room-work via uiop:symbol-call.

(in-package #:autopoiesis.integration)

(defvar *room-branches* (make-hash-table :test 'equal)
  "task-id -> (cons worker-name branch) for branches awaiting fan-in.")
(defvar *room-branches-lock* (bordeaux-threads:make-lock "room-branches"))

(defun %register-room-branch (task-id worker branch)
  (bordeaux-threads:with-lock-held (*room-branches-lock*)
    (setf (gethash task-id *room-branches*) (cons worker branch))))

(defun run-room-work (conductor event-data)
  "Dispatch handler for a :room-work event. Spawns a worker that runs one agent
   turn and STAGES its output onto its own branch (no merge -- the orchestrator
   fans in later via fan-in-room). EVENT-DATA plist:
     :problem entity the work is about   :prompt turn prompt
     :provider provider instance         :worker worker/branch name
   Caller declares cardinalities for :room/proposal (:one) and :room/note (:many)."
  (let* ((problem  (getf event-data :problem))
         (prompt   (getf event-data :prompt))
         (provider (getf event-data :provider))
         (worker   (or (getf event-data :worker) "worker"))
         (task-id  (format nil "room-worker-~A-~A" problem worker))
         (cap-sub   autopoiesis.substrate:*substrate*)
         (cap-store autopoiesis.substrate:*store*))
    (autopoiesis.orchestration:register-worker
     conductor task-id
     (bt:make-thread
      (lambda ()
        (let ((autopoiesis.substrate:*substrate* cap-sub)
              (autopoiesis.substrate:*store* cap-store))
          (handler-case
              (let* ((branch (autopoiesis.substrate:branch-fork :name worker))
                     (result (provider-invoke provider prompt))
                     (text (string-trim '(#\Space #\Newline #\Return #\Tab)
                                        (or (provider-result-text result) ""))))
                (autopoiesis.substrate:branch-stage branch problem :room/proposal text)
                (autopoiesis.substrate:branch-stage branch problem :room/note
                                                    (format nil "~A: ~A" worker text))
                (%register-room-branch task-id worker branch)
                (autopoiesis.orchestration:unregister-worker
                 conductor task-id :status :complete
                 :result (format nil "~A => ~S" worker text)))
            (error (e)
              (autopoiesis.orchestration:unregister-worker
               conductor task-id :status :failed :error-msg (format nil "~A" e))))))
      :name task-id))
    task-id))

(defun fan-in-room (problem &key (store autopoiesis.substrate:*store*))
  "Orchestrator/lead fan-in: merge all staged room branches into the base
   sequentially. Independent facts union; cardinality-one divergences are
   recorded as :room/conflict facts (flagged, not lost). Returns
   (values total-applied conflicts). Drains the staged-branch registry."
  (let ((applied 0) (all-conflicts nil))
    (bordeaux-threads:with-lock-held (*room-branches-lock*)
      (maphash
       (lambda (task-id entry)
         (declare (ignore task-id))
         (destructuring-bind (worker . branch) entry
           (multiple-value-bind (n conflicts)
               (autopoiesis.substrate:branch-merge branch :store store)
             (incf applied n)
             (dolist (c conflicts)
               (push c all-conflicts)
               (autopoiesis.substrate:transact!
                (list (autopoiesis.substrate:make-datom
                       problem :room/conflict
                       (format nil "~A proposed ~S but base held ~S"
                               worker
                               (autopoiesis.substrate:merge-conflict-wanted c)
                               (autopoiesis.substrate:merge-conflict-base-now c)))))))))
       *room-branches*)
      (clrhash *room-branches*))
    (values applied (nreverse all-conflicts))))
