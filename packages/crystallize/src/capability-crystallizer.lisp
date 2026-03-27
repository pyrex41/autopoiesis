;;;; capability-crystallizer.lisp - Crystallize promoted capabilities
;;;;
;;;; Extracts promoted agent-defined capabilities as loadable defcapability forms.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; Capability Crystallization
;;; ===================================================================

(defun crystallize-capabilities (&key (registry autopoiesis.agent:*capability-registry*))
  "Extract crystallized forms from promoted agent-defined capabilities.
   Returns a list of (name . defcapability-form) pairs."
  (let ((results nil))
    (dolist (cap (autopoiesis.agent:list-capabilities :registry registry))
      (when (and (typep cap 'autopoiesis.agent:agent-capability)
                 (eq (autopoiesis.agent:cap-promotion-status cap) :promoted))
        (let* ((name (autopoiesis.agent:capability-name cap))
               (desc (autopoiesis.agent:capability-description cap))
               (params (autopoiesis.agent:capability-parameters cap))
               (source (autopoiesis.agent:cap-source-code cap))
               ;; Reconstruct defcapability form
               (form `(autopoiesis.agent:defcapability ,name
                        ,(if params
                             (mapcar (lambda (p) (if (listp p) `(&key ,@p) p)) params)
                             nil)
                        ,desc
                        :body
                        ,@(if (and (listp source) (eq (first source) 'lambda))
                              (cddr source)  ; skip lambda and params
                              (list source)))))
          (push (cons name form) results))))
    (nreverse results)))
