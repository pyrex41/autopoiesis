;;;; run.lisp - Eval run creation and execution
;;;;
;;;; Manages the lifecycle of evaluation runs: creating trial entities,
;;;; dispatching to harnesses, collecting results, and tracking progress.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Run Creation
;;; ===================================================================

(defun create-eval-run (&key name scenarios harnesses (trials 3) config)
  "Create an eval run entity and pre-create all trial entities.
   NAME is a string description of this run.
   SCENARIOS is a list of scenario entity IDs.
   HARNESSES is a list of harness name strings.
   TRIALS is the number of repetitions per scenario*harness combo.
   CONFIG is an optional plist of extra configuration.
   Returns the run entity ID."
  (unless (and name scenarios harnesses)
    (error 'autopoiesis-error
           :message "create-eval-run requires :name, :scenarios, and :harnesses"))
  (let ((run-eid (intern-id (format nil "eval-run-~a" (make-uuid))))
        (now (get-universal-time)))
    ;; Create run entity
    (with-batch-transaction ()
      (transact!
       (list (make-datom run-eid :entity/type :eval-run)
             (make-datom run-eid :eval-run/name name)
             (make-datom run-eid :eval-run/status :pending)
             (make-datom run-eid :eval-run/scenarios scenarios)
             (make-datom run-eid :eval-run/harnesses harnesses)
             (make-datom run-eid :eval-run/trials trials)
             (make-datom run-eid :eval-run/created-at now)))
      (when config
        (transact! (list (make-datom run-eid :eval-run/config config)))))
    ;; Pre-create trial entities
    (dolist (scenario-id scenarios)
      (dolist (harness-name harnesses)
        (dotimes (trial-idx trials)
          (let ((trial-eid (intern-id (format nil "eval-trial-~a" (make-uuid)))))
            (transact!
             (list (make-datom trial-eid :entity/type :eval-trial)
                   (make-datom trial-eid :eval-trial/run run-eid)
                   (make-datom trial-eid :eval-trial/scenario scenario-id)
                   (make-datom trial-eid :eval-trial/harness harness-name)
                   (make-datom trial-eid :eval-trial/trial-num (1+ trial-idx))
                   (make-datom trial-eid :eval-trial/status :pending)))))))
    run-eid))

;;; ===================================================================
;;; Run Execution
;;; ===================================================================

(defun execute-eval-run (run-id &key parallel judge on-trial-complete)
  "Execute all trials for an eval run.
   PARALLEL — when T, execute harnesses concurrently via lparallel.
   JUDGE — when T, run LLM-as-judge after each trial.
   ON-TRIAL-COMPLETE — optional callback (trial-eid trial-plist) called after each trial.

   Returns the run entity ID."
  ;; Update run status
  (transact! (list (make-datom run-id :eval-run/status :running)))
  (handler-case
      (let ((trial-eids (find-trials-for-run run-id)))
        (if parallel
            (execute-trials-parallel trial-eids run-id :judge judge
                                    :on-trial-complete on-trial-complete)
            (execute-trials-sequential trial-eids run-id :judge judge
                                       :on-trial-complete on-trial-complete))
        ;; Mark run complete
        (transact! (list (make-datom run-id :eval-run/status :complete)
                         (make-datom run-id :eval-run/completed-at (get-universal-time)))))
    (error (e)
      (transact! (list (make-datom run-id :eval-run/status :failed)))
      (error e)))
  run-id)

(defun execute-trials-sequential (trial-eids run-id &key judge on-trial-complete)
  "Execute trials one at a time."
  (declare (ignore run-id))
  (dolist (trial-eid trial-eids)
    (when (eq :pending (entity-attr trial-eid :eval-trial/status))
      (execute-single-trial trial-eid :judge judge
                            :on-trial-complete on-trial-complete))))

(defun execute-trials-parallel (trial-eids run-id &key judge on-trial-complete)
  "Execute trials with parallelism across harnesses."
  (declare (ignore run-id))
  ;; Group trials by harness for parallel execution
  (let ((by-harness (make-hash-table :test 'equal)))
    (dolist (eid trial-eids)
      (let ((h (entity-attr eid :eval-trial/harness)))
        (push eid (gethash h by-harness nil))))
    ;; Check if lparallel is available
    (let ((kernel-available
            (and (find-package :lparallel)
                 (let ((ksym (find-symbol "*KERNEL*" :lparallel)))
                   (and ksym (boundp ksym) (symbol-value ksym))))))
      (if kernel-available
          ;; Parallel: each harness group runs in parallel
          (let ((pmap-fn (find-symbol "PMAP" :lparallel)))
            (funcall pmap-fn 'list
                     (lambda (harness-name)
                       (dolist (eid (gethash harness-name by-harness))
                         (when (eq :pending (entity-attr eid :eval-trial/status))
                           (execute-single-trial eid :judge judge
                                                 :on-trial-complete on-trial-complete))))
                     (loop for k being the hash-keys of by-harness collect k)))
          ;; Fallback: sequential
          (maphash (lambda (harness-name eids)
                     (declare (ignore harness-name))
                     (dolist (eid eids)
                       (when (eq :pending (entity-attr eid :eval-trial/status))
                         (execute-single-trial eid :judge judge
                                               :on-trial-complete on-trial-complete))))
                   by-harness)))))

(defun execute-single-trial (trial-eid &key judge on-trial-complete)
  "Execute a single eval trial."
  (let* ((scenario-id (entity-attr trial-eid :eval-trial/scenario))
         (harness-name (entity-attr trial-eid :eval-trial/harness))
         ;; Build scenario plist from individual entity-attr reads
         ;; (entity-state has caching issues with repeated calls on same entity)
         (scenario-plist (list :eval-scenario/name (entity-attr scenario-id :eval-scenario/name)
                               :eval-scenario/description (entity-attr scenario-id :eval-scenario/description)
                               :eval-scenario/prompt (entity-attr scenario-id :eval-scenario/prompt)
                               :eval-scenario/domain (entity-attr scenario-id :eval-scenario/domain)
                               :eval-scenario/verifier (entity-attr scenario-id :eval-scenario/verifier)
                               :eval-scenario/rubric (entity-attr scenario-id :eval-scenario/rubric)
                               :eval-scenario/expected (entity-attr scenario-id :eval-scenario/expected)
                               :eval-scenario/timeout (entity-attr scenario-id :eval-scenario/timeout)))
         (harness (find-harness harness-name))
         (now (get-universal-time)))
    ;; Mark as running
    (transact! (list (make-datom trial-eid :eval-trial/status :running)
                     (make-datom trial-eid :eval-trial/started-at now)))
    (if (null harness)
        ;; Harness not found
        (transact! (list (make-datom trial-eid :eval-trial/status :failed)
                         (make-datom trial-eid :eval-trial/completed-at (get-universal-time))
                         (make-datom trial-eid :eval-trial/passed :error)
                         (make-datom trial-eid :eval-trial/output
                                     (format nil "Harness not found: ~a" harness-name))))
        ;; Run the harness
        (handler-case
            (let ((result (harness-run-scenario harness scenario-plist)))
              ;; Store hard metrics
              (let ((datoms (list (make-datom trial-eid :eval-trial/status :complete)
                                  (make-datom trial-eid :eval-trial/completed-at (get-universal-time))
                                  (make-datom trial-eid :eval-trial/duration (getf result :duration))
                                  (make-datom trial-eid :eval-trial/output (getf result :output))
                                  (make-datom trial-eid :eval-trial/tool-calls (getf result :tool-calls)))))
                (when (getf result :cost)
                  (push (make-datom trial-eid :eval-trial/cost (getf result :cost)) datoms))
                (when (getf result :turns)
                  (push (make-datom trial-eid :eval-trial/turns (getf result :turns)) datoms))
                (when (getf result :exit-code)
                  (push (make-datom trial-eid :eval-trial/exit-code (getf result :exit-code)) datoms))
                (when (getf result :passed)
                  (push (make-datom trial-eid :eval-trial/passed (getf result :passed)) datoms))
                (when (getf result :raw-provider-result)
                  (push (make-datom trial-eid :eval-trial/raw-result
                                    (getf result :raw-provider-result)) datoms))
                (transact! datoms))
              ;; Run judge if requested
              (when (and judge
                         (getf result :output)
                         (getf scenario-plist :eval-scenario/rubric))
                (handler-case
                    (let ((judge-result (run-judge scenario-plist (getf result :output))))
                      (when (getf judge-result :success)
                        (transact!
                         (list (make-datom trial-eid :eval-trial/judge-scores
                                          (append (list (cons "score" (getf judge-result :overall-score)))
                                                  (getf judge-result :dimensions)))
                               (make-datom trial-eid :eval-trial/judge-reasoning
                                          (getf judge-result :reasoning))))))
                  (error (e)
                    (declare (ignore e))
                    nil))))
          (error (e)
            (transact!
             (list (make-datom trial-eid :eval-trial/status :failed)
                   (make-datom trial-eid :eval-trial/completed-at (get-universal-time))
                   (make-datom trial-eid :eval-trial/passed :error)
                   (make-datom trial-eid :eval-trial/output (format nil "Error: ~a" e)))))))
    ;; Callback
    (when on-trial-complete
      (funcall on-trial-complete trial-eid (entity-state trial-eid)))))

;;; ===================================================================
;;; Run Queries
;;; ===================================================================

(defun find-trials-for-run (run-id)
  "Find all trial entity IDs belonging to a run."
  (find-entities :eval-trial/run run-id))

(defun get-eval-run (run-id)
  "Get run details including trial count summaries.
   Returns a plist with run state plus :trial-summary."
  (let* ((state (entity-state run-id))
         (trial-eids (find-trials-for-run run-id))
         (statuses (mapcar (lambda (eid)
                             (entity-attr eid :eval-trial/status))
                           trial-eids)))
    (when (getf state :eval-run/name)
      (append state
              (list :trial-summary
                    (list :total (length trial-eids)
                          :pending (count :pending statuses)
                          :running (count :running statuses)
                          :complete (count :complete statuses)
                          :failed (count :failed statuses)))))))

(defun list-eval-runs (&key status)
  "List all eval run entity IDs, optionally filtered by status."
  (let ((all (find-entities-by-type :eval-run)))
    (if status
        (remove-if-not (lambda (eid)
                         (eq status (entity-attr eid :eval-run/status)))
                       all)
        all)))

(defun cancel-eval-run (run-id)
  "Cancel a running eval by setting status to :cancelled.
   Does not abort in-flight trials."
  (transact! (list (make-datom run-id :eval-run/status :cancelled)))
  t)

;;; ===================================================================
;;; Trial Queries
;;; ===================================================================

(defun get-trial (trial-eid)
  "Get full trial state as a plist."
  (entity-state trial-eid))

(defun list-trials (run-id &key harness scenario status)
  "List trial entity IDs for a run with optional filters."
  (let ((all (find-trials-for-run run-id)))
    (when harness
      (setf all (remove-if-not
                 (lambda (eid)
                   (string= harness (entity-attr eid :eval-trial/harness)))
                 all)))
    (when scenario
      (setf all (remove-if-not
                 (lambda (eid)
                   (eql scenario (entity-attr eid :eval-trial/scenario)))
                 all)))
    (when status
      (setf all (remove-if-not
                 (lambda (eid)
                   (eq status (entity-attr eid :eval-trial/status)))
                 all)))
    all))

(defun trial-to-alist (trial-eid)
  "Convert a trial entity to a JSON-friendly alist."
  (let ((state (entity-state trial-eid)))
    (when (getf state :eval-trial/run)
      `((:id . ,trial-eid)
        (:run-id . ,(getf state :eval-trial/run))
        (:scenario-id . ,(getf state :eval-trial/scenario))
        (:harness . ,(getf state :eval-trial/harness))
        (:trial-num . ,(getf state :eval-trial/trial-num))
        (:status . ,(string-downcase (symbol-name (or (getf state :eval-trial/status) :unknown))))
        (:duration . ,(getf state :eval-trial/duration))
        (:cost . ,(getf state :eval-trial/cost))
        (:turns . ,(getf state :eval-trial/turns))
        (:exit-code . ,(getf state :eval-trial/exit-code))
        (:passed . ,(let ((p (getf state :eval-trial/passed)))
                      (when p (string-downcase (symbol-name p)))))
        (:judge-scores . ,(getf state :eval-trial/judge-scores))
        (:started-at . ,(getf state :eval-trial/started-at))
        (:completed-at . ,(getf state :eval-trial/completed-at))))))

;;; ===================================================================
;;; Run Serialization
;;; ===================================================================

(defun run-to-alist (run-id)
  "Convert a run entity to a JSON-friendly alist."
  (let* ((run-data (get-eval-run run-id))
         (summary (getf run-data :trial-summary)))
    (when (getf run-data :eval-run/name)
      `((:id . ,run-id)
        (:name . ,(getf run-data :eval-run/name))
        (:status . ,(string-downcase (symbol-name (or (getf run-data :eval-run/status) :unknown))))
        (:scenarios . ,(getf run-data :eval-run/scenarios))
        (:harnesses . ,(getf run-data :eval-run/harnesses))
        (:trials-per-combo . ,(getf run-data :eval-run/trials))
        (:total-trials . ,(getf summary :total))
        (:completed-trials . ,(+ (or (getf summary :complete) 0)
                                  (or (getf summary :failed) 0)))
        (:created-at . ,(getf run-data :eval-run/created-at))
        (:completed-at . ,(getf run-data :eval-run/completed-at))))))
