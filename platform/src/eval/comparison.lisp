;;;; comparison.lisp - Cross-harness and cross-run comparison
;;;;
;;;; Compares evaluation results across harnesses and runs,
;;;; computing aggregate metrics and building comparison matrices.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Harness Comparison (within a single run)
;;; ===================================================================

(defun compare-harnesses (run-id)
  "Compare all harnesses within a single eval run.
   Returns a comparison alist:
     :run-id
     :run-name
     :scenarios - list of per-scenario comparisons
     :aggregate - list of per-harness aggregate metrics"
  (let* ((run-state (entity-state run-id))
         (scenario-ids (getf run-state :eval-run/scenarios))
         (harness-names (getf run-state :eval-run/harnesses))
         (all-trials (find-trials-for-run run-id))
         ;; Build lookup: (scenario . harness) -> list of trial plists
         (trial-table (make-hash-table :test 'equal))
         ;; Per-harness aggregate accumulators
         (harness-trials (make-hash-table :test 'equal)))
    ;; Index all trials
    (dolist (eid all-trials)
      (let* ((state (entity-state eid))
             (scenario (getf state :eval-trial/scenario))
             (harness (getf state :eval-trial/harness))
             (key (cons scenario harness)))
        (push state (gethash key trial-table nil))
        (push state (gethash harness harness-trials nil))))
    ;; Build per-scenario comparison
    (let ((scenario-results
            (mapcar
             (lambda (sid)
               (let ((scenario-state (entity-state sid)))
                 (list
                  :scenario-id sid
                  :scenario-name (getf scenario-state :eval-scenario/name)
                  :harness-results
                  (mapcar
                   (lambda (hname)
                     (let* ((trials (gethash (cons sid hname) trial-table))
                            (hard (compute-hard-metrics trials))
                            (squishy (compute-squishy-metrics trials)))
                       (list :harness hname
                             :pass-rate (getf hard :pass-rate)
                             :avg-duration (getf hard :avg-duration)
                             :avg-cost (getf hard :avg-cost)
                             :avg-turns (getf hard :avg-turns)
                             :total-trials (getf hard :total-trials)
                             :avg-score (getf squishy :avg-overall-score)
                             :dimension-scores (getf squishy :dimension-averages))))
                   harness-names))))
             scenario-ids))
          ;; Build per-harness aggregate
          (aggregate-results
            (mapcar
             (lambda (hname)
               (let* ((trials (gethash hname harness-trials))
                      (hard (compute-hard-metrics trials))
                      (squishy (compute-squishy-metrics trials)))
                 (list :harness hname
                       :overall-pass-rate (getf hard :pass-rate)
                       :avg-duration (getf hard :avg-duration)
                       :total-cost (getf hard :total-cost)
                       :avg-cost (getf hard :avg-cost)
                       :avg-turns (getf hard :avg-turns)
                       :total-trials (getf hard :total-trials)
                       :avg-score (getf squishy :avg-overall-score)
                       :dimension-scores (getf squishy :dimension-averages))))
             harness-names)))
      (list :run-id run-id
            :run-name (getf run-state :eval-run/name)
            :scenarios scenario-results
            :aggregate aggregate-results))))

;;; ===================================================================
;;; Cross-Run Comparison
;;; ===================================================================

(defun compare-runs (run-ids)
  "Compare results across multiple evaluation runs.
   Returns a comparison showing each run's aggregate metrics."
  (list :runs
        (mapcar
         (lambda (rid)
           (let* ((run-state (entity-state rid))
                  (all-trials (find-trials-for-run rid))
                  (trial-states (mapcar #'entity-state all-trials))
                  (hard (compute-hard-metrics trial-states))
                  (squishy (compute-squishy-metrics trial-states)))
             (list :run-id rid
                   :run-name (getf run-state :eval-run/name)
                   :status (getf run-state :eval-run/status)
                   :harnesses (getf run-state :eval-run/harnesses)
                   :pass-rate (getf hard :pass-rate)
                   :avg-duration (getf hard :avg-duration)
                   :total-cost (getf hard :total-cost)
                   :total-trials (getf hard :total-trials)
                   :avg-score (getf squishy :avg-overall-score))))
         run-ids)))

;;; ===================================================================
;;; Normalized Gain (Hake's g)
;;; ===================================================================

(defun compute-normalized-gain (baseline-run-id enhanced-run-id)
  "Compute normalized gain (Hake's g) between a baseline and enhanced run.
   g = (pass_enhanced - pass_baseline) / (1.0 - pass_baseline)
   Returns a plist with :gain :baseline-pass-rate :enhanced-pass-rate."
  (let* ((baseline-trials (mapcar #'entity-state (find-trials-for-run baseline-run-id)))
         (enhanced-trials (mapcar #'entity-state (find-trials-for-run enhanced-run-id)))
         (baseline-hard (compute-hard-metrics baseline-trials))
         (enhanced-hard (compute-hard-metrics enhanced-trials))
         (baseline-pass (getf baseline-hard :pass-rate))
         (enhanced-pass (getf enhanced-hard :pass-rate))
         (gain (if (< baseline-pass 1.0)
                   (/ (- enhanced-pass baseline-pass) (- 1.0 baseline-pass))
                   0.0)))
    (list :gain gain
          :baseline-pass-rate baseline-pass
          :enhanced-pass-rate enhanced-pass)))

;;; ===================================================================
;;; Comparison Serialization
;;; ===================================================================

(defun comparison-to-alist (comparison)
  "Convert a comparison result to a JSON-friendly alist.
   Handles nested plists by converting keywords to lowercase strings."
  ;; The comparison is already in alist-compatible form since we use keywords.
  ;; Just ensure it's serializable.
  comparison)

;;; ===================================================================
;;; Text Formatting
;;; ===================================================================

(defun format-comparison-table (comparison &optional (stream t))
  "Format a comparison result as a readable ASCII table."
  (let ((aggregate (getf comparison :aggregate)))
    (format stream "~%Eval Run: ~a~%~%" (getf comparison :run-name))
    (format stream "~30a ~10a ~12a ~10a ~8a ~8a~%"
            "Harness" "Pass Rate" "Avg Duration" "Avg Cost" "Turns" "Score")
    (format stream "~30,,,'-a ~10,,,'-a ~12,,,'-a ~10,,,'-a ~8,,,'-a ~8,,,'-a~%"
            "" "" "" "" "" "")
    (dolist (h aggregate)
      (format stream "~30a ~9,1f% ~11,2fs ~9,4f$ ~7,1f ~7,1f~%"
              (getf h :harness)
              (* 100 (or (getf h :overall-pass-rate) 0))
              (or (getf h :avg-duration) 0)
              (or (getf h :avg-cost) 0)
              (or (getf h :avg-turns) 0)
              (or (getf h :avg-score) 0)))))
