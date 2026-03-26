;;;; persistent-cognition.lisp - Immutable cognitive operations
;;;;
;;;; Each function returns a NEW persistent-agent struct with updated thoughts.
;;;; The original agent is never modified.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Construction
;;; ═══════════════════════════════════════════════════════════════════

(defun make-persistent-thought (type content &key extra)
  "Create a thought plist for the persistent cognition layer.
   TYPE is one of :observation, :reasoning, :decision, :action, :reflection."
  (let ((thought (list :type type
                       :content content
                       :timestamp (get-precise-time)
                       :id (make-uuid))))
    (if extra
        (append thought extra)
        thought)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cognitive Phases
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-perceive (agent environment)
  "Perceive ENVIRONMENT and record an observation thought.
   Returns a new agent with the observation appended to thoughts."
  (let* ((content (cond
                    ((listp environment) environment)
                    ((stringp environment) (list :raw environment))
                    (t (list :raw (princ-to-string environment)))))
         (thought (make-persistent-thought :observation content
                    :extra (list :source :environment)))
         (new-thoughts (pvec-push (persistent-agent-thoughts agent) thought)))
    (copy-persistent-agent agent :thoughts new-thoughts)))

(defun persistent-reason (agent)
  "Examine recent thoughts and generate a reasoning thought.
   Returns a new agent with reasoning appended to thoughts."
  (let* ((thoughts (persistent-agent-thoughts agent))
         (len (pvec-length thoughts))
         ;; Gather recent observations
         (recent (loop for i from (max 0 (- len 10)) below len
                       for th = (pvec-ref thoughts i)
                       when (eq (getf th :type) :observation)
                         collect th))
         (reasoning-content
           (list :observations-count (length recent)
                 :summary (if recent
                              (getf (first (last recent)) :content)
                              :no-observations)
                 :heuristics-available (length (persistent-agent-heuristics agent))))
         (thought (make-persistent-thought :reasoning reasoning-content))
         (new-thoughts (pvec-push thoughts thought)))
    (copy-persistent-agent agent :thoughts new-thoughts)))

(defun persistent-decide (agent)
  "Look at observations and reasoning, generate a decision thought.
   Returns a new agent with decision appended to thoughts."
  (let* ((thoughts (persistent-agent-thoughts agent))
         (len (pvec-length thoughts))
         ;; Find most recent reasoning
         (latest-reasoning
           (loop for i from (1- len) downto (max 0 (- len 10))
                 for th = (pvec-ref thoughts i)
                 when (eq (getf th :type) :reasoning)
                   return th))
         ;; Check applicable heuristics
         (heuristics (persistent-agent-heuristics agent))
         (decision-content
           (list :based-on (when latest-reasoning (getf latest-reasoning :id))
                 :action :continue
                 :confidence (if heuristics 0.8 0.5)
                 :heuristics-applied (length heuristics)))
         (thought (make-persistent-thought :decision decision-content))
         (new-thoughts (pvec-push thoughts thought)))
    (copy-persistent-agent agent :thoughts new-thoughts)))

(defun persistent-act (agent action)
  "Execute ACTION and record an action thought.
   WARNING: This phase has SIDE EFFECTS. If ACTION specifies a :capability,
   it will be invoked through the mutable *capability-registry*.
   Returns a new agent with the action result recorded in thoughts."
  (let* ((capability-name (when (listp action) (getf action :capability)))
         (capability-args (when (listp action) (getf action :args)))
         ;; Side-effectful: invoke capability if specified
         (result (if (and capability-name
                         (pset-contains-p (persistent-agent-capabilities agent)
                                          capability-name))
                     (handler-case
                         (list :status :success
                               :result (apply #'invoke-capability
                                              capability-name
                                              (or capability-args nil)))
                       (error (e)
                         (list :status :error
                               :error (princ-to-string e))))
                     (list :status :no-op
                           :reason (if capability-name
                                       :capability-not-available
                                       :no-capability-specified))))
         (thought (make-persistent-thought :action
                    (list :input action :result result)))
         (new-thoughts (pvec-push (persistent-agent-thoughts agent) thought)))
    (copy-persistent-agent agent :thoughts new-thoughts)))

(defun persistent-reflect (agent)
  "Review the last cycle's thoughts and generate a reflection.
   May include self-modification proposals in the reflection content.
   Returns a new agent with the reflection appended to thoughts."
  (let* ((thoughts (persistent-agent-thoughts agent))
         (len (pvec-length thoughts))
         ;; Collect this cycle's thoughts (last 4-5 thoughts from perceive through act)
         (cycle-start (max 0 (- len 5)))
         (cycle-thoughts
           (loop for i from cycle-start below len
                 collect (pvec-ref thoughts i)))
         ;; Analyze action outcomes
         (action-thoughts (remove-if-not
                           (lambda (th) (eq (getf th :type) :action))
                           cycle-thoughts))
         (errors (count-if
                  (lambda (th)
                    (let ((result (getf (getf th :content) :result)))
                      (eq (getf result :status) :error)))
                  action-thoughts))
         (reflection-content
           (list :cycle-length (length cycle-thoughts)
                 :actions-taken (length action-thoughts)
                 :errors errors
                 :assessment (cond
                               ((> errors 0) :needs-improvement)
                               ((null action-thoughts) :idle)
                               (t :satisfactory))
                 :proposals nil))
         (thought (make-persistent-thought :reflection reflection-content))
         (new-thoughts (pvec-push thoughts thought)))
    (copy-persistent-agent agent :thoughts new-thoughts)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Full Cognitive Cycle
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-cognitive-cycle (agent environment)
  "Run the perceive->reason->decide->act->reflect pipeline.
   Returns the final agent with all cycle thoughts appended.
   The original AGENT is never modified."
  (let* ((a1 (persistent-perceive agent environment))
         (a2 (persistent-reason a1))
         (a3 (persistent-decide a2))
         ;; Extract the decision to determine action
         (decision-thought (pvec-last (persistent-agent-thoughts a3)))
         (action (getf (getf decision-thought :content) :action))
         (a4 (persistent-act a3 action))
         (a5 (persistent-reflect a4)))
    a5))
