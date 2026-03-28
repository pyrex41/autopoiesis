;;;; reasoning.lisp - Shen Prolog reasoning mixin for agents
;;;;
;;;; Provides a CLOS mixin class that, when mixed into an agent,
;;;; specializes the `reason` generic to query the agent's Prolog
;;;; knowledge base during the reasoning phase.
;;;;
;;;; Opt-in: only agents created with the mixin get Prolog reasoning.
;;;; Regular agents are completely unaffected.

(in-package #:autopoiesis.shen)

;;; ===================================================================
;;; Reasoning Mixin Class
;;; ===================================================================

(defclass shen-reasoning-mixin ()
  ((knowledge-base :initarg :knowledge-base
                   :accessor agent-knowledge-base
                   :initform nil
                   :documentation "List of (rule-name . clauses) pairs.
Loaded into Shen before each reasoning phase."))
  (:documentation "Mixin class that adds Prolog-powered reasoning to agents.
Mix into an agent class to enable Shen Prolog queries during the reason phase.

Example:
  (defclass prolog-agent (agent shen-reasoning-mixin) ())
  (let ((a (make-instance 'prolog-agent :name \"reasoner\")))
    (add-knowledge a :ancestor
      '((ancestor X Y) <-- (parent X Y))
      '((ancestor X Y) <-- (parent X Z) (ancestor Z Y)))
    (cognitive-cycle a env))"))

;;; ===================================================================
;;; Knowledge Base Management
;;; ===================================================================

(defun add-knowledge (agent rule-name &rest clauses)
  "Add a Prolog rule to an agent's knowledge base.
   RULE-NAME is a keyword. CLAUSES are Prolog clause S-expressions."
  (check-type rule-name keyword)
  (let ((kb (agent-knowledge-base agent)))
    (setf (agent-knowledge-base agent)
          (cons (cons rule-name clauses)
                (remove rule-name kb :key #'car)))))

(defun remove-knowledge (agent rule-name)
  "Remove a rule from an agent's knowledge base."
  (setf (agent-knowledge-base agent)
        (remove rule-name (agent-knowledge-base agent) :key #'car)))

(defun clear-knowledge (agent)
  "Remove all rules from an agent's knowledge base."
  (setf (agent-knowledge-base agent) nil))

;;; ===================================================================
;;; Reasoning Integration
;;; ===================================================================

(defun load-agent-knowledge (agent)
  "Load an agent's knowledge base into Shen's rule store.
   Clears previous rules first to prevent cross-agent contamination.
   Called before each reasoning phase (under *shen-lock*)."
  (clear-rules)
  (dolist (entry (agent-knowledge-base agent))
    (define-rule (car entry) (cdr entry))))

(defun reason-with-prolog (agent observations)
  "Run Prolog reasoning over an agent's knowledge base and observations.
   Returns a list of derived facts as S-expressions, or NIL."
  (unless (shen-available-p)
    (return-from reason-with-prolog nil))
  (handler-case
      (progn
        ;; Load agent's rules into Shen
        (load-agent-knowledge agent)
        ;; Assert observations as temporary facts
        ;; (observations are passed as-is to Prolog queries)
        (let ((results nil))
          ;; Query each rule in the KB with the observations as context
          (dolist (entry (agent-knowledge-base agent))
            (let* ((rule-name (car entry))
                   (result (handler-case
                               (query-rules rule-name :context observations)
                             (error () nil))))
              (when result
                (push (list :derived rule-name result) results))))
          (nreverse results)))
    (error (e)
      (warn "Prolog reasoning error for agent ~A: ~A"
            (if (slot-boundp agent 'autopoiesis.agent::name)
                (slot-value agent 'autopoiesis.agent::name)
                "?")
            e)
      nil)))

;;; ===================================================================
;;; Method Specialization
;;; ===================================================================

;; Specialize the `reason` generic for agents with the mixin.
;; Uses :around to augment (not replace) existing reasoning.
;; NOTE: autopoiesis is a declared dependency so the package should always
;; exist at load time. The warning catches misconfiguration early.
(let* ((agent-pkg (find-package :autopoiesis.agent))
       (reason-fn (when agent-pkg (find-symbol "REASON" agent-pkg))))
  (if (and reason-fn (fboundp reason-fn))
      (eval
       `(defmethod ,(intern "REASON" agent-pkg) :around
          ((agent shen-reasoning-mixin) observations)
          (let* ((prolog-results (reason-with-prolog agent observations))
                 ;; Augment observations with Prolog-derived facts
                 (augmented (if prolog-results
                                (append (when (listp observations) observations)
                                        (list :prolog-derived prolog-results))
                                observations)))
            (call-next-method agent augmented))))
      (warn "autopoiesis.shen: Could not install REASON :around method. ~
             Is :autopoiesis loaded? shen-reasoning-mixin will be inert.")))

;;; ===================================================================
;;; Persistent Agent Integration (via metadata pmap)
;;; ===================================================================

(defun save-knowledge-to-pmap (agent)
  "Save an agent's knowledge base to its persistent metadata pmap.
   Returns the updated metadata pmap (does not mutate agent)."
  (let* ((pkg (find-package :autopoiesis.core))
         (pmap-put (when pkg (find-symbol "PMAP-PUT" pkg)))
         (kb-sexpr (mapcar (lambda (entry) (cons (car entry) (cdr entry)))
                           (agent-knowledge-base agent))))
    (when (and pmap-put (fboundp pmap-put))
      ;; Return a new pmap with the KB stored
      ;; Caller is responsible for attaching to agent
      (funcall pmap-put
               (or (ignore-errors
                     (slot-value agent 'autopoiesis.agent::metadata))
                   (funcall (find-symbol "PMAP-EMPTY" pkg)))
               :shen-rules
               kb-sexpr))))

(defun load-knowledge-from-pmap (agent pmap)
  "Load knowledge base from a persistent metadata pmap into the agent."
  (let* ((pkg (find-package :autopoiesis.core))
         (pmap-get (when pkg (find-symbol "PMAP-GET" pkg)))
         (kb-data (when (and pmap-get (fboundp pmap-get))
                    (funcall pmap-get pmap :shen-rules))))
    (when kb-data
      (setf (agent-knowledge-base agent) kb-data))))
