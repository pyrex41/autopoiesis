;;;; history.lisp - Historical tracking and performance trends
;;;;
;;;; Query historical eval data via substrate temporal queries to
;;;; track harness performance over time.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Performance Trends
;;; ===================================================================

(defun harness-performance-history (harness-name &key scenario-id since)
  "Query pass rate and metrics for a harness over time.
   Returns a list of run summaries sorted by creation date:
   ((:run-id :run-name :created-at :pass-rate :avg-duration :avg-cost :trials) ...)

   HARNESS-NAME — filter to this harness
   SCENARIO-ID — optional, filter to this scenario
   SINCE — optional, universal-time cutoff"
  (let ((run-eids (find-entities-by-type :eval-run))
        (results nil))
    (dolist (run-eid run-eids)
      (let* ((run-state (entity-state run-eid))
             (created (getf run-state :eval-run/created-at))
             (status (getf run-state :eval-run/status))
             (harnesses (getf run-state :eval-run/harnesses)))
        ;; Filter: only complete runs that include this harness
        (when (and (eq status :complete)
                   (member harness-name harnesses :test #'string=)
                   (or (null since) (>= created since)))
          ;; Get trials for this harness in this run
          (let* ((trial-eids (list-trials run-eid :harness harness-name
                                          :scenario scenario-id))
                 (trial-states (mapcar #'entity-state trial-eids))
                 (metrics (compute-hard-metrics trial-states)))
            (push (list :run-id run-eid
                        :run-name (getf run-state :eval-run/name)
                        :created-at created
                        :pass-rate (getf metrics :pass-rate)
                        :avg-duration (getf metrics :avg-duration)
                        :avg-cost (getf metrics :avg-cost)
                        :trials (getf metrics :total-trials))
                  results)))))
    ;; Sort by creation date ascending
    (sort results #'< :key (lambda (r) (getf r :created-at)))))

(defun scenario-performance-history (scenario-id &key since)
  "Query performance across all harnesses for a scenario over time.
   Returns a list of (:run-id :created-at :harness-results ...)
   where harness-results is an alist of (harness-name . pass-rate)."
  (let ((run-eids (find-entities-by-type :eval-run))
        (results nil))
    (dolist (run-eid run-eids)
      (let* ((run-state (entity-state run-eid))
             (created (getf run-state :eval-run/created-at))
             (status (getf run-state :eval-run/status))
             (scenarios (getf run-state :eval-run/scenarios))
             (harnesses (getf run-state :eval-run/harnesses)))
        (when (and (eq status :complete)
                   (member scenario-id scenarios)
                   (or (null since) (>= created since)))
          (let ((harness-results
                  (mapcar (lambda (hname)
                            (let* ((trials (list-trials run-eid
                                                       :harness hname
                                                       :scenario scenario-id))
                                   (states (mapcar #'entity-state trials))
                                   (metrics (compute-hard-metrics states)))
                              (cons hname (getf metrics :pass-rate))))
                          harnesses)))
            (push (list :run-id run-eid
                        :run-name (getf run-state :eval-run/name)
                        :created-at created
                        :harness-results harness-results)
                  results)))))
    (sort results #'< :key (lambda (r) (getf r :created-at)))))

;;; ===================================================================
;;; Summary Statistics
;;; ===================================================================

(defun eval-summary ()
  "Get a high-level summary of all eval data.
   Returns a plist with:
     :total-scenarios :total-runs :total-trials
     :completed-runs :active-harnesses
     :best-harness :worst-harness"
  (let* ((scenarios (list-scenarios))
         (runs (find-entities-by-type :eval-run))
         (completed-runs (remove-if-not
                          (lambda (eid)
                            (eq :complete (entity-attr eid :eval-run/status)))
                          runs))
         ;; Collect all unique harness names from completed runs
         (all-harnesses (remove-duplicates
                         (loop for eid in completed-runs
                               append (entity-attr eid :eval-run/harnesses))
                         :test #'string=))
         ;; Compute pass rates per harness across all runs
         (harness-rates
           (mapcar (lambda (hname)
                     (let* ((all-trials nil))
                       (dolist (run-eid completed-runs)
                         (let ((trials (list-trials run-eid :harness hname)))
                           (dolist (t-eid trials)
                             (push (entity-state t-eid) all-trials))))
                       (let ((metrics (compute-hard-metrics all-trials)))
                         (cons hname (getf metrics :pass-rate)))))
                   all-harnesses))
         (sorted-rates (sort (copy-list harness-rates) #'> :key #'cdr)))
    (list :total-scenarios (length scenarios)
          :total-runs (length runs)
          :completed-runs (length completed-runs)
          :active-harnesses (length all-harnesses)
          :total-trials (loop for eid in runs
                              sum (length (find-trials-for-run eid)))
          :best-harness (when sorted-rates (car (first sorted-rates)))
          :best-pass-rate (when sorted-rates (cdr (first sorted-rates)))
          :worst-harness (when sorted-rates (car (alexandria:lastcar sorted-rates)))
          :worst-pass-rate (when sorted-rates (cdr (alexandria:lastcar sorted-rates)))
          :harness-rankings sorted-rates)))
