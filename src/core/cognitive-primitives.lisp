;;;; cognitive-primitives.lisp - Basic thought structures for Autopoiesis
;;;;
;;;; Defines the fundamental cognitive types:
;;;; - Thought: A unit of agent cognition
;;;; - Decision: A choice point with alternatives
;;;; - Action: An effect on the world
;;;; - Observation: Input from the world
;;;; - Reflection: Metacognition

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought - A unit of agent cognition
;;; ═══════════════════════════════════════════════════════════════════

(defclass thought ()
  ((id :initarg :id
       :accessor thought-id
       :initform (make-uuid)
       :documentation "Unique identifier for this thought")
   (timestamp :initarg :timestamp
              :accessor thought-timestamp
              :initform (get-precise-time)
              :documentation "When this thought occurred")
   (content :initarg :content
            :accessor thought-content
            :initform nil
            :documentation "The S-expression content of the thought")
   (type :initarg :type
         :accessor thought-type
         :initform :generic
         :documentation "Category: :reasoning :planning :executing :reflecting :generic")
   (confidence :initarg :confidence
               :accessor thought-confidence
               :initform 1.0
               :documentation "Agent's confidence in this thought [0, 1]")
   (provenance :initarg :provenance
               :accessor thought-provenance
               :initform nil
               :documentation "What triggered this thought"))
  (:documentation "A single unit of agent cognition, represented as S-expression"))

(defmethod print-object ((thought thought) stream)
  (print-unreadable-object (thought stream :type t :identity nil)
    (format stream "~a ~a"
            (thought-type thought)
            (truncate-string (prin1-to-string (thought-content thought)) 40))))

(defun make-thought (content &key (type :generic) (confidence 1.0) provenance id timestamp)
  "Create a new thought with CONTENT."
  (make-instance 'thought
                 :content content
                 :type type
                 :confidence confidence
                 :provenance provenance
                 :id (or id (make-uuid))
                 :timestamp (or timestamp (get-precise-time))))

(defun thought-to-sexpr (thought)
  "Convert THOUGHT to a pure S-expression representation."
  `(:thought
    :id ,(thought-id thought)
    :timestamp ,(thought-timestamp thought)
    :type ,(thought-type thought)
    :confidence ,(thought-confidence thought)
    :content ,(thought-content thought)
    :provenance ,(thought-provenance thought)))

(defun sexpr-to-thought (sexpr)
  "Reconstruct a THOUGHT from its S-expression representation."
  (destructuring-bind (&key id timestamp type confidence content provenance)
      (rest sexpr)
    (make-instance 'thought
                   :id id
                   :timestamp timestamp
                   :type type
                   :confidence confidence
                   :content content
                   :provenance provenance)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Decision - A choice point with alternatives
;;; ═══════════════════════════════════════════════════════════════════

(defclass decision (thought)
  ((alternatives :initarg :alternatives
                 :accessor decision-alternatives
                 :initform nil
                 :documentation "List of (option . score) pairs considered")
   (chosen :initarg :chosen
           :accessor decision-chosen
           :initform nil
           :documentation "The selected option")
   (rationale :initarg :rationale
              :accessor decision-rationale
              :initform nil
              :documentation "Why this option was chosen"))
  (:default-initargs :type :decision)
  (:documentation "A decision point where the agent chose between alternatives"))

(defun make-decision (alternatives chosen &key rationale confidence)
  "Create a decision recording the choice between ALTERNATIVES."
  (make-instance 'decision
                 :alternatives alternatives
                 :chosen chosen
                 :rationale rationale
                 :content `(:decided ,chosen :from ,(mapcar #'car alternatives))
                 :confidence (or confidence
                                 (cdr (assoc chosen alternatives :test #'equal)))))

(defun decision-unchosen (decision)
  "Return the alternatives that were NOT chosen."
  (remove (decision-chosen decision)
          (decision-alternatives decision)
          :key #'car
          :test #'equal))

;;; ═══════════════════════════════════════════════════════════════════
;;; Action - An effect on the world
;;; ═══════════════════════════════════════════════════════════════════

(defclass action (thought)
  ((capability :initarg :capability
               :accessor action-capability
               :initform nil
               :documentation "Which capability is being invoked")
   (arguments :initarg :arguments
              :accessor action-arguments
              :initform nil
              :documentation "Arguments to the capability")
   (result :initarg :result
           :accessor action-result
           :initform :pending
           :documentation "Result of the action, or :PENDING")
   (side-effects :initarg :side-effects
                 :accessor action-side-effects
                 :initform nil
                 :documentation "Observable side effects"))
  (:default-initargs :type :action)
  (:documentation "An action taken by the agent"))

(defun make-action (capability &rest arguments)
  "Create an action invoking CAPABILITY with ARGUMENTS."
  (make-instance 'action
                 :capability capability
                 :arguments arguments
                 :content `(:invoke ,capability ,@arguments)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Observation - Input from the world
;;; ═══════════════════════════════════════════════════════════════════

(defclass observation (thought)
  ((source :initarg :source
           :accessor observation-source
           :initform :external
           :documentation "Where this observation came from")
   (raw :initarg :raw
        :accessor observation-raw
        :initform nil
        :documentation "Raw unprocessed form")
   (interpreted :initarg :interpreted
                :accessor observation-interpreted
                :initform nil
                :documentation "Agent's interpretation"))
  (:default-initargs :type :observation)
  (:documentation "An observation of external state"))

(defun make-observation (raw &key source interpreted)
  "Create an observation of RAW data."
  (make-instance 'observation
                 :raw raw
                 :source source
                 :interpreted interpreted
                 :content (or interpreted raw)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Reflection - Metacognition
;;; ═══════════════════════════════════════════════════════════════════

(defclass reflection (thought)
  ((target :initarg :target
           :accessor reflection-target
           :initform nil
           :documentation "What is being reflected upon (thought ID or pattern)")
   (insight :initarg :insight
            :accessor reflection-insight
            :initform nil
            :documentation "The metacognitive insight")
   (modification :initarg :modification
                 :accessor reflection-modification
                 :initform nil
                 :documentation "Self-modification triggered by this reflection"))
  (:default-initargs :type :reflection)
  (:documentation "Agent reflecting on its own cognition"))

(defun make-reflection (target insight &key modification)
  "Create a reflection on TARGET with INSIGHT."
  (make-instance 'reflection
                 :target target
                 :insight insight
                 :modification modification
                 :content `(:reflect-on ,target :insight ,insight)))
