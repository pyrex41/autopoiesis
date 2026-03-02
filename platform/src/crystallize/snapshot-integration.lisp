;;;; snapshot-integration.lisp - Store crystallized source in snapshot DAG
;;;;
;;;; The DAG is the primary store for crystallized forms.
;;;; Snapshots capture the full crystallized state at a point in time.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; Snapshot Storage
;;; ===================================================================

(defun store-crystallized-snapshot (agent crystallized-forms &key label)
  "Store crystallized source as a snapshot in the DAG.
   The snapshot's agent-state is the current agent state.
   The crystallized forms are stored in snapshot metadata under :crystallized."
  (let ((snap (autopoiesis.snapshot:make-snapshot
               (autopoiesis.agent:agent-to-sexpr agent)
               :metadata (list :crystallized crystallized-forms
                               :label label
                               :crystallized-at (get-universal-time)))))
    (when autopoiesis.snapshot:*snapshot-store*
      (autopoiesis.snapshot:save-snapshot snap))
    snap))

(defun crystallize-all (agent &key label (min-confidence 0.7))
  "Crystallize all available components and store as snapshot.
   Returns the snapshot."
  (let* ((cap-forms (crystallize-capabilities))
         (heur-forms (crystallize-heuristics :min-confidence min-confidence))
         (all-forms (list :capabilities (mapcar #'cdr cap-forms)
                          :heuristics (mapcar #'cdr heur-forms))))
    (store-crystallized-snapshot agent all-forms :label label)))
