;;;; persistent-membrane.lisp - Agent membrane (permission boundary)
;;;;
;;;; The membrane controls what actions an agent can take and what
;;;; modifications are allowed to its genome. All operations return
;;;; new agent structs; the original is never modified.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Membrane Queries
;;; ═══════════════════════════════════════════════════════════════════

(defun membrane-allows-p (agent action-type &optional source)
  "Check whether AGENT's membrane permits ACTION-TYPE.
   The membrane pmap key :allowed-actions maps to a pset of allowed keywords.
   If SOURCE is provided and membrane has :validate-source T, the source
   is validated via validate-extension-source.
   Returns T if allowed, NIL otherwise."
  (let ((membrane (persistent-agent-membrane agent)))
    ;; Check action type against allowed-actions set
    (let ((allowed-actions (pmap-get membrane :allowed-actions)))
      (when (and allowed-actions
                 (not (pset-contains-p allowed-actions action-type)))
        (return-from membrane-allows-p nil)))
    ;; If source validation is required, check it
    (when (and source (pmap-get membrane :validate-source))
      (multiple-value-bind (valid errors)
          (validate-extension-source source)
        (declare (ignore errors))
        (unless valid
          (return-from membrane-allows-p nil))))
    t))

;;; ═══════════════════════════════════════════════════════════════════
;;; Membrane Updates
;;; ═══════════════════════════════════════════════════════════════════

(defun membrane-update (agent key value)
  "Return a new agent with KEY set to VALUE in the membrane pmap."
  (let ((new-membrane (pmap-put (persistent-agent-membrane agent) key value)))
    (copy-persistent-agent agent :membrane new-membrane)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Genome Modification
;;; ═══════════════════════════════════════════════════════════════════

(defun propose-genome-modification (agent source-form)
  "Validate SOURCE-FORM against the agent's membrane and, if allowed,
   return a new agent with SOURCE-FORM prepended to the genome.
   Signals autopoiesis-error if the membrane rejects the modification."
  (unless (membrane-allows-p agent :genome-modification source-form)
    (error 'autopoiesis-error
           :message (format nil "Membrane rejected genome modification for agent ~a"
                            (persistent-agent-name agent))))
  (copy-persistent-agent agent
    :genome (cons source-form (persistent-agent-genome agent))))

(defun promote-to-genome (agent capability-name source-form)
  "Validate SOURCE-FORM, add it to the genome, and add CAPABILITY-NAME
   to the agent's capabilities pset. Returns a new agent.
   Signals autopoiesis-error if validation fails."
  ;; Validate source if membrane requires it
  (when (pmap-get (persistent-agent-membrane agent) :validate-source)
    (multiple-value-bind (valid errors)
        (validate-extension-source source-form)
      (declare (ignore errors))
      (unless valid
        (error 'autopoiesis-error
               :message (format nil "Source validation failed for capability ~a"
                                capability-name)))))
  ;; Check membrane allows genome modification
  (unless (membrane-allows-p agent :genome-modification source-form)
    (error 'autopoiesis-error
           :message (format nil "Membrane rejected promotion of ~a for agent ~a"
                            capability-name (persistent-agent-name agent))))
  (let* ((new-genome (cons source-form (persistent-agent-genome agent)))
         (new-caps (pset-add (persistent-agent-capabilities agent) capability-name)))
    (copy-persistent-agent agent
      :genome new-genome
      :capabilities new-caps)))
