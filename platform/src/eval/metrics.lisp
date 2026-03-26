;;;; metrics.lisp - Hard and squishy metric aggregation
;;;;
;;;; Compute aggregate statistics from collections of eval trial results.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Utility Functions
;;; ===================================================================

(defun median (values)
  "Compute the median of a list of numbers. Returns nil for empty list."
  (when values
    (let ((sorted (sort (copy-list values) #'<))
          (n (length values)))
      (if (oddp n)
          (nth (floor n 2) sorted)
          (/ (+ (nth (1- (/ n 2)) sorted)
                (nth (/ n 2) sorted))
             2.0)))))

(defun percentile (values p)
  "Compute the P-th percentile (0-100) of VALUES."
  (when values
    (let* ((sorted (sort (copy-list values) #'<))
           (n (length sorted))
           (idx (min (1- n) (floor (* n (/ p 100.0))))))
      (nth idx sorted))))

(defun safe-mean (values)
  "Compute the mean of VALUES, returning nil for empty list."
  (when values
    (/ (reduce #'+ values) (length values))))

;;; ===================================================================
;;; Hard Metrics
;;; ===================================================================

(defun compute-hard-metrics (trial-plists)
  "Compute aggregate hard metrics from a list of trial result plists.
   Each plist should have keys like :eval-trial/duration, :eval-trial/cost, etc.

   Returns a plist with:
     :total-trials :passed :failed :errors :skipped
     :pass-rate
     :avg-duration :min-duration :max-duration :p50-duration :p95-duration
     :total-cost :avg-cost
     :avg-turns :total-turns"
  (let* ((n (length trial-plists))
         ;; Count outcomes
         (outcomes (mapcar (lambda (tr) (getf tr :eval-trial/passed)) trial-plists))
         (passed (count :pass outcomes))
         (failed (count :fail outcomes))
         (errors (count :error outcomes))
         (skipped (count :skip outcomes))
         ;; Duration stats
         (durations (remove nil (mapcar (lambda (tr) (getf tr :eval-trial/duration)) trial-plists)))
         ;; Cost stats
         (costs (remove nil (mapcar (lambda (tr) (getf tr :eval-trial/cost)) trial-plists)))
         ;; Turn stats
         (turns (remove nil (mapcar (lambda (tr) (getf tr :eval-trial/turns)) trial-plists))))
    (list :total-trials n
          :passed passed
          :failed failed
          :errors errors
          :skipped skipped
          :pass-rate (if (> n 0) (/ (float passed) n) 0.0)

          :avg-duration (safe-mean durations)
          :min-duration (when durations (reduce #'min durations))
          :max-duration (when durations (reduce #'max durations))
          :p50-duration (median durations)
          :p95-duration (percentile durations 95)

          :total-cost (when costs (reduce #'+ costs))
          :avg-cost (safe-mean costs)

          :avg-turns (safe-mean turns)
          :total-turns (when turns (reduce #'+ turns)))))

;;; ===================================================================
;;; Squishy Metrics
;;; ===================================================================

(defun compute-squishy-metrics (trial-plists)
  "Compute aggregate squishy (judge) metrics from trial plists.
   Each plist should have :eval-trial/judge-scores as an alist.

   Returns a plist with:
     :avg-overall-score :min-overall-score :max-overall-score
     :dimension-averages - alist of (dimension . avg-score)
     :trials-judged"
  (let* ((all-scores (remove nil (mapcar (lambda (tr)
                                           (getf tr :eval-trial/judge-scores))
                                         trial-plists)))
         (n (length all-scores))
         ;; Extract overall scores (look for "score" or :overall key)
         (overall-scores
           (remove nil
                   (mapcar (lambda (scores)
                             (or (cdr (assoc "score" scores :test #'string-equal))
                                 (cdr (assoc :score scores))
                                 (cdr (assoc "overall" scores :test #'string-equal))))
                           all-scores)))
         ;; Collect per-dimension scores
         (dim-table (make-hash-table :test 'equal)))
    ;; Accumulate dimension scores
    (dolist (scores all-scores)
      (dolist (pair scores)
        (when (and (consp pair) (numberp (cdr pair))
                   (not (string-equal (car pair) "score"))
                   (not (eq (car pair) :score)))
          (push (cdr pair) (gethash (if (stringp (car pair))
                                        (car pair)
                                        (string-downcase (symbol-name (car pair))))
                                    dim-table nil)))))
    (let ((dim-avgs nil))
      (maphash (lambda (k vs)
                 (push (cons k (safe-mean vs)) dim-avgs))
               dim-table)
      (list :avg-overall-score (safe-mean overall-scores)
            :min-overall-score (when overall-scores (reduce #'min overall-scores))
            :max-overall-score (when overall-scores (reduce #'max overall-scores))
            :dimension-averages (nreverse dim-avgs)
            :trials-judged n))))

;;; ===================================================================
;;; Sandbox Metrics
;;; ===================================================================

(defun compute-sandbox-metrics (trial-plists)
  "Compute aggregate sandbox-specific metrics from trial plists.
   Each plist should have :eval-trial/metadata with sandbox keys.
   Returns a plist of sandbox-specific aggregates."
  (let* ((metadatas (remove nil (mapcar (lambda (tr)
                                          (getf tr :eval-trial/metadata))
                                        trial-plists)))
         (deltas (remove nil (mapcar (lambda (m) (getf m :file-count-delta)) metadatas)))
         (added (remove nil (mapcar (lambda (m) (getf m :files-added)) metadatas)))
         (removed (remove nil (mapcar (lambda (m) (getf m :files-removed)) metadatas)))
         (modified (remove nil (mapcar (lambda (m) (getf m :files-modified)) metadatas)))
         (bytes (remove nil (mapcar (lambda (m) (getf m :bytes-written-total)) metadatas)))
         (hashes (remove nil (mapcar (lambda (m) (getf m :tree-hash-after)) metadatas))))
    (list :trials-with-sandbox-data (length metadatas)
          :avg-file-count-delta (safe-mean deltas)
          :total-files-added (when added (reduce #'+ added))
          :total-files-removed (when removed (reduce #'+ removed))
          :total-files-modified (when modified (reduce #'+ modified))
          :avg-bytes-written (safe-mean bytes)
          :total-bytes-written (when bytes (reduce #'+ bytes))
          :unique-tree-hashes (length (remove-duplicates hashes :test #'equal)))))
