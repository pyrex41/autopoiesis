;;;; learning.lisp - Pattern extraction and heuristic generation
;;;;
;;;; Enables agents to learn from experience by extracting patterns
;;;; and generating heuristics for future decisions.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Experience Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass experience ()
  ((id :initarg :id
       :accessor experience-id
       :initform (make-uuid)
       :documentation "Unique identifier for this experience")
   (task-type :initarg :task-type
              :accessor experience-task-type
              :initform nil
              :documentation "Type of task this experience relates to")
   (context :initarg :context
            :accessor experience-context
            :initform nil
            :documentation "Context in which the experience occurred (s-expression)")
   (actions :initarg :actions
            :accessor experience-actions
            :initform nil
            :documentation "List of actions taken during this experience")
   (outcome :initarg :outcome
            :accessor experience-outcome
            :initform nil
            :documentation "Outcome of the experience: :success, :failure, or :partial")
   (timestamp :initarg :timestamp
              :accessor experience-timestamp
              :initform (get-precise-time)
              :documentation "When this experience was recorded")
   (agent-id :initarg :agent-id
             :accessor experience-agent-id
             :initform nil
             :documentation "ID of the agent that had this experience")
   (metadata :initarg :metadata
             :accessor experience-metadata
             :initform nil
             :documentation "Additional metadata about the experience"))
  (:documentation "Records an agent's experience for learning purposes.
   
   An experience captures the context, actions taken, and outcome of
   a task execution. Multiple experiences can be analyzed to extract
   patterns and generate heuristics."))

(defun make-experience (&key task-type context actions outcome agent-id metadata)
  "Create a new experience record.
   
   Arguments:
     task-type - Keyword identifying the type of task
     context   - S-expression describing the context
     actions   - List of action s-expressions
     outcome   - :success, :failure, or :partial
     agent-id  - ID of the agent
     metadata  - Additional metadata plist
   
   Returns: A new experience instance"
  (make-instance 'experience
                 :task-type task-type
                 :context context
                 :actions actions
                 :outcome outcome
                 :agent-id agent-id
                 :metadata metadata))

(defun experience-to-sexpr (experience)
  "Serialize an experience to an s-expression."
  (list :experience
        :id (experience-id experience)
        :task-type (experience-task-type experience)
        :context (experience-context experience)
        :actions (experience-actions experience)
        :outcome (experience-outcome experience)
        :timestamp (experience-timestamp experience)
        :agent-id (experience-agent-id experience)
        :metadata (experience-metadata experience)))

(defun sexpr-to-experience (sexpr)
  "Deserialize an experience from an s-expression."
  (when (and (listp sexpr) (eq (first sexpr) :experience))
    (let ((plist (rest sexpr)))
      (let ((exp (make-instance 'experience
                                :task-type (getf plist :task-type)
                                :context (getf plist :context)
                                :actions (getf plist :actions)
                                :outcome (getf plist :outcome)
                                :agent-id (getf plist :agent-id)
                                :metadata (getf plist :metadata))))
        (when (getf plist :id)
          (setf (slot-value exp 'id) (getf plist :id)))
        (when (getf plist :timestamp)
          (setf (slot-value exp 'timestamp) (getf plist :timestamp)))
        exp))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Heuristic Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass heuristic ()
  ((id :initarg :id
       :accessor heuristic-id
       :initform (make-uuid)
       :documentation "Unique identifier for this heuristic")
   (name :initarg :name
         :accessor heuristic-name
         :initform nil
         :documentation "Human-readable name for this heuristic")
   (condition :initarg :condition
              :accessor heuristic-condition
              :initform nil
              :documentation "S-expression pattern to match against context")
   (recommendation :initarg :recommendation
                   :accessor heuristic-recommendation
                   :initform nil
                   :documentation "Recommended action or preference")
   (confidence :initarg :confidence
               :accessor heuristic-confidence
               :initform 0.5
               :documentation "Confidence score between 0.0 and 1.0")
   (applications :initarg :applications
                 :accessor heuristic-applications
                 :initform 0
                 :documentation "Number of times this heuristic has been applied")
   (successes :initarg :successes
              :accessor heuristic-successes
              :initform 0
              :documentation "Number of successful applications")
   (source-pattern :initarg :source-pattern
                   :accessor heuristic-source-pattern
                   :initform nil
                   :documentation "The pattern this heuristic was derived from")
   (created :initarg :created
            :accessor heuristic-created
            :initform (get-precise-time)
            :documentation "When this heuristic was created")
   (last-applied :initarg :last-applied
                 :accessor heuristic-last-applied
                 :initform nil
                 :documentation "When this heuristic was last applied"))
  (:documentation "A learned rule for guiding agent decisions.
   
   Heuristics are generated from patterns extracted from experiences.
   They encode conditions under which certain actions are preferred
   or should be avoided. Confidence is updated based on outcomes."))

(defun make-heuristic (&key name condition recommendation (confidence 0.5) source-pattern)
  "Create a new heuristic.
   
   Arguments:
     name           - Human-readable name
     condition      - S-expression pattern to match
     recommendation - Action recommendation (s-expression)
     confidence     - Initial confidence (0.0 to 1.0)
     source-pattern - Pattern this was derived from
   
   Returns: A new heuristic instance"
  (make-instance 'heuristic
                 :name name
                 :condition condition
                 :recommendation recommendation
                 :confidence (max 0.0 (min 1.0 confidence))
                 :source-pattern source-pattern))

(defun heuristic-to-sexpr (heuristic)
  "Serialize a heuristic to an s-expression."
  (list :heuristic
        :id (heuristic-id heuristic)
        :name (heuristic-name heuristic)
        :condition (heuristic-condition heuristic)
        :recommendation (heuristic-recommendation heuristic)
        :confidence (heuristic-confidence heuristic)
        :applications (heuristic-applications heuristic)
        :successes (heuristic-successes heuristic)
        :source-pattern (heuristic-source-pattern heuristic)
        :created (heuristic-created heuristic)
        :last-applied (heuristic-last-applied heuristic)))

(defun sexpr-to-heuristic (sexpr)
  "Deserialize a heuristic from an s-expression."
  (when (and (listp sexpr) (eq (first sexpr) :heuristic))
    (let ((plist (rest sexpr)))
      (let ((heur (make-instance 'heuristic
                                 :name (getf plist :name)
                                 :condition (getf plist :condition)
                                 :recommendation (getf plist :recommendation)
                                 :confidence (or (getf plist :confidence) 0.5)
                                 :source-pattern (getf plist :source-pattern))))
        (when (getf plist :id)
          (setf (slot-value heur 'id) (getf plist :id)))
        (when (getf plist :applications)
          (setf (slot-value heur 'applications) (getf plist :applications)))
        (when (getf plist :successes)
          (setf (slot-value heur 'successes) (getf plist :successes)))
        (when (getf plist :created)
          (setf (slot-value heur 'created) (getf plist :created)))
        (when (getf plist :last-applied)
          (setf (slot-value heur 'last-applied) (getf plist :last-applied)))
        heur))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Experience Storage
;;; ═══════════════════════════════════════════════════════════════════

(defvar *experience-store* (make-hash-table :test 'equal)
  "Global store for agent experiences.")

(defvar *heuristic-store* (make-hash-table :test 'equal)
  "Global store for learned heuristics.")

(defun store-experience (experience &key (store *experience-store*))
  "Store an experience in the experience store."
  (setf (gethash (experience-id experience) store) experience)
  experience)

(defun find-experience (id &key (store *experience-store*))
  "Find an experience by ID."
  (gethash id store))

(defun list-experiences (&key (store *experience-store*) task-type agent-id outcome)
  "List experiences, optionally filtered by criteria.
   
   Arguments:
     store     - Experience store to query
     task-type - Filter by task type
     agent-id  - Filter by agent ID
     outcome   - Filter by outcome (:success, :failure, :partial)
   
   Returns: List of matching experiences"
  (let ((results nil))
    (maphash (lambda (id exp)
               (declare (ignore id))
               (when (and (or (null task-type)
                              (eq task-type (experience-task-type exp)))
                          (or (null agent-id)
                              (equal agent-id (experience-agent-id exp)))
                          (or (null outcome)
                              (eq outcome (experience-outcome exp))))
                 (push exp results)))
             store)
    (sort results #'> :key #'experience-timestamp)))

(defun clear-experiences (&key (store *experience-store*))
  "Clear all experiences from the store."
  (clrhash store))

(defun store-heuristic (heuristic &key (store *heuristic-store*))
  "Store a heuristic in the heuristic store."
  (setf (gethash (heuristic-id heuristic) store) heuristic)
  heuristic)

(defun find-heuristic (id &key (store *heuristic-store*))
  "Find a heuristic by ID."
  (gethash id store))

(defun list-heuristics (&key (store *heuristic-store*) min-confidence)
  "List heuristics, optionally filtered by minimum confidence.
   
   Arguments:
     store          - Heuristic store to query
     min-confidence - Minimum confidence threshold (0.0 to 1.0)
   
   Returns: List of matching heuristics sorted by confidence"
  (let ((results nil))
    (maphash (lambda (id heur)
               (declare (ignore id))
               (when (or (null min-confidence)
                         (>= (heuristic-confidence heur) min-confidence))
                 (push heur results)))
             store)
    (sort results #'> :key #'heuristic-confidence)))

(defun clear-heuristics (&key (store *heuristic-store*))
  "Clear all heuristics from the store."
  (clrhash store))

;;; ═══════════════════════════════════════════════════════════════════
;;; Heuristic Application Tracking
;;; ═══════════════════════════════════════════════════════════════════

(defun record-heuristic-application (heuristic &key success)
  "Record that a heuristic was applied and whether it succeeded.
   
   Arguments:
     heuristic - The heuristic that was applied
     success   - T if the application led to success, NIL otherwise
   
   Updates the heuristic's application count, success count, and
   recalculates confidence based on success rate."
  (incf (heuristic-applications heuristic))
  (when success
    (incf (heuristic-successes heuristic)))
  (setf (heuristic-last-applied heuristic) (get-precise-time))
  ;; Update confidence based on success rate
  (when (plusp (heuristic-applications heuristic))
    (setf (heuristic-confidence heuristic)
          (/ (heuristic-successes heuristic)
             (heuristic-applications heuristic))))
  heuristic)

(defun decay-heuristic-confidence (heuristic &key (factor 0.9))
  "Decay a heuristic's confidence by a factor.
   
   Used when a heuristic application fails to reduce its influence
   on future decisions.
   
   Arguments:
     heuristic - The heuristic to decay
     factor    - Multiplicative decay factor (default 0.9)
   
   Returns: The updated heuristic"
  (setf (heuristic-confidence heuristic)
        (* (heuristic-confidence heuristic) factor))
  heuristic)

;;; ═══════════════════════════════════════════════════════════════════
;;; Condition Matching
;;; ═══════════════════════════════════════════════════════════════════

(defun condition-matches-p (condition context)
  "Check if a heuristic condition matches the given context.
   
   Arguments:
     condition - S-expression condition pattern
     context   - S-expression context to match against
   
   The condition can contain:
     - Literal values that must match exactly
     - :any to match any value
     - (:type <type>) to match by type
     - (:member <list>) to match if value is in list
     - (and <cond1> <cond2> ...) for conjunction
     - (or <cond1> <cond2> ...) for disjunction
     - (not <cond>) for negation
   
   Returns: T if condition matches, NIL otherwise"
  (cond
    ;; Nil matches nil
    ((null condition) (null context))
    
    ;; :any matches anything
    ((eq condition :any) t)
    
    ;; Type check
    ((and (consp condition) (eq (car condition) :type))
     (typep context (cadr condition)))
    
    ;; Member check
    ((and (consp condition) (eq (car condition) :member))
     (member context (cadr condition) :test #'equal))
    
    ;; Conjunction
    ((and (consp condition) (eq (car condition) 'and))
     (every (lambda (c) (condition-matches-p c context)) (cdr condition)))
    
    ;; Disjunction
    ((and (consp condition) (eq (car condition) 'or))
     (some (lambda (c) (condition-matches-p c context)) (cdr condition)))
    
    ;; Negation
    ((and (consp condition) (eq (car condition) 'not))
     (not (condition-matches-p (cadr condition) context)))
    
    ;; List pattern matching
    ((and (consp condition) (consp context))
     (and (= (length condition) (length context))
          (every #'condition-matches-p condition context)))
    
    ;; Literal equality
    (t (equal condition context))))

(defun find-applicable-heuristics (context &key (store *heuristic-store*) (min-confidence 0.3))
  "Find all heuristics whose conditions match the given context.
   
   Arguments:
     context        - S-expression context to match against
     store          - Heuristic store to search
     min-confidence - Minimum confidence threshold
   
   Returns: List of applicable heuristics sorted by confidence"
  (let ((applicable nil))
    (maphash (lambda (id heur)
               (declare (ignore id))
               (when (and (>= (heuristic-confidence heur) min-confidence)
                          (condition-matches-p (heuristic-condition heur) context))
                 (push heur applicable)))
             store)
    (sort applicable #'> :key #'heuristic-confidence)))
