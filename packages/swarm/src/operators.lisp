;;;; operators.lisp - Genetic operators for genome evolution
;;;;
;;;; Provides crossover and mutation operators that produce new genomes
;;;; from existing ones while tracking lineage.

(in-package #:autopoiesis.swarm)

;;; ===================================================================
;;; Crossover
;;; ===================================================================

(defun crossover-genomes (parent-a parent-b)
  "Perform uniform crossover between PARENT-A and PARENT-B.
   Capabilities: each from either parent with 50% chance (deduped).
   Heuristic weights: shared keys averaged, unique keys kept.
   Parameters: shared numeric keys blended 50/50, others from either parent.
   Returns a new genome with both parents in lineage."
  (let* ((child-caps (remove-duplicates
                      (append
                       (remove-if (lambda (c) (declare (ignore c)) (zerop (random 2)))
                                  (genome-capabilities parent-a))
                       (remove-if (lambda (c) (declare (ignore c)) (zerop (random 2)))
                                  (genome-capabilities parent-b)))
                      :test #'equal))
         (child-weights (crossover-alist
                         (genome-heuristic-weights parent-a)
                         (genome-heuristic-weights parent-b)))
         (child-params (crossover-plist
                        (genome-parameters parent-a)
                        (genome-parameters parent-b)))
         (child-gen (1+ (max (genome-generation parent-a)
                             (genome-generation parent-b)))))
    (make-genome
     :capabilities child-caps
     :heuristic-weights child-weights
     :parameters child-params
     :lineage (list (genome-id parent-a) (genome-id parent-b))
     :generation child-gen)))

(defun crossover-alist (alist-a alist-b)
  "Crossover two alists. Shared keys get averaged values; unique keys kept."
  (let ((result nil)
        (keys-a (mapcar #'car alist-a))
        (keys-b (mapcar #'car alist-b)))
    ;; Shared keys: average
    (dolist (key (intersection keys-a keys-b :test #'equal))
      (let ((va (cdr (assoc key alist-a :test #'equal)))
            (vb (cdr (assoc key alist-b :test #'equal))))
        (push (cons key (if (and (numberp va) (numberp vb))
                            (/ (+ va vb) 2.0)
                            (if (zerop (random 2)) va vb)))
              result)))
    ;; Unique to A
    (dolist (key (set-difference keys-a keys-b :test #'equal))
      (push (assoc key alist-a :test #'equal) result))
    ;; Unique to B
    (dolist (key (set-difference keys-b keys-a :test #'equal))
      (push (assoc key alist-b :test #'equal) result))
    (nreverse result)))

(defun crossover-plist (plist-a plist-b)
  "Crossover two plists. Shared numeric keys blended 50/50."
  (let ((result nil)
        (keys-a (loop for (k v) on plist-a by #'cddr collect k))
        (keys-b (loop for (k v) on plist-b by #'cddr collect k)))
    ;; All keys from both parents
    (dolist (key (remove-duplicates (append keys-a keys-b) :test #'equal))
      (let ((va (getf plist-a key))
            (vb (getf plist-b key)))
        (cond
          ((and va vb (numberp va) (numberp vb))
           ;; Blend numeric values
           (setf result (append result (list key (/ (+ va vb) 2.0)))))
          ((and va vb)
           ;; Non-numeric: pick from either
           (setf result (append result (list key (if (zerop (random 2)) va vb)))))
          (va (setf result (append result (list key va))))
          (vb (setf result (append result (list key vb)))))))
    result))

;;; ===================================================================
;;; Mutation
;;; ===================================================================

(defun mutate-genome (genome &key (mutation-rate 0.1))
  "Create a mutated copy of GENOME. Each mutation type occurs independently
   with probability MUTATION-RATE. The original genome is not modified."
  (let ((new-caps (copy-list (genome-capabilities genome)))
        (new-weights (copy-alist-fresh (genome-heuristic-weights genome)))
        (new-params (copy-list (genome-parameters genome))))
    ;; Mutate capabilities: add a random one
    (when (< (random 1.0) mutation-rate)
      (let ((available (available-capability-names)))
        (when available
          (let ((cap (nth (random (length available)) available)))
            (pushnew cap new-caps :test #'equal)))))
    ;; Mutate capabilities: remove a random one
    (when (and new-caps (< (random 1.0) mutation-rate))
      (let ((idx (random (length new-caps))))
        (setf new-caps (remove-if (constantly t) new-caps :start idx :end (1+ idx)))))
    ;; Mutate heuristic weights: perturb a random weight
    (when (and new-weights (< (random 1.0) mutation-rate))
      (let* ((idx (random (length new-weights)))
             (entry (nth idx new-weights))
             (old-val (cdr entry)))
        (when (numberp old-val)
          (setf (cdr (nth idx new-weights))
                (+ old-val (- (random 0.2) 0.1))))))
    ;; Mutate parameters: adjust a random numeric parameter
    (when (and new-params (< (random 1.0) mutation-rate))
      (let* ((keys (loop for (k v) on new-params by #'cddr
                         when (numberp v) collect k))
             (key (when keys (nth (random (length keys)) keys))))
        (when key
          (let ((old-val (getf new-params key)))
            (setf (getf new-params key)
                  (+ old-val (- (random 0.2) 0.1)))))))
    (make-genome
     :capabilities new-caps
     :heuristic-weights new-weights
     :parameters new-params
     :lineage (list (genome-id genome))
     :generation (genome-generation genome))))

(defun available-capability-names ()
  "Get list of registered capability names, or a default list."
  (let ((caps (autopoiesis.agent:list-capabilities)))
    (if caps
        (mapcar #'autopoiesis.agent:capability-name caps)
        '(:read :write :execute :communicate :introspect))))

(defun copy-alist-fresh (alist)
  "Return a fresh copy of ALIST with new cons cells."
  (mapcar (lambda (pair) (cons (car pair) (cdr pair))) alist))
