;;;; agent-capability.lisp - Agent-defined capabilities
;;;;
;;;; Enables agents to define new capabilities at runtime.
;;;; These capabilities go through validation, testing, and promotion.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Capability Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass agent-capability (capability)
  ((source-agent :initarg :source-agent
                 :accessor cap-source-agent
                 :initform nil
                 :documentation "ID of the agent that created this capability")
   (source-code :initarg :source-code
                :accessor cap-source-code
                :initform nil
                :documentation "Original source code as s-expression")
   (extension-id :initarg :extension-id
                 :accessor cap-extension-id
                 :initform nil
                 :documentation "ID of the compiled extension in the registry")
   (test-results :initarg :test-results
                 :accessor cap-test-results
                 :initform nil
                 :documentation "Results from test-agent-capability")
   (promotion-status :initarg :promotion-status
                     :accessor cap-promotion-status
                     :initform :draft
                     :documentation "Status: :draft :testing :promoted :rejected"))
  (:documentation "A capability defined by an agent at runtime.
   
   Agent capabilities extend the base capability class with metadata
   about their origin (source-agent, source-code), their compiled form
   (extension-id), testing history (test-results), and lifecycle status
   (promotion-status).
   
   Promotion workflow:
   1. :draft - Initial state when capability is created
   2. :testing - Capability is being tested with test cases
   3. :promoted - Tests passed, capability is globally available
   4. :rejected - Tests failed or capability was rejected"))

(defun make-agent-capability (name description parameters source-agent source-code
                              &key extension-id)
  "Create a new agent-defined capability.
   
   Arguments:
     name         - Keyword name for the capability
     description  - Human-readable description
     parameters   - Parameter specification list
     source-agent - ID of the creating agent
     source-code  - S-expression source code
     extension-id - Optional ID of compiled extension
   
   Returns: agent-capability instance"
  (make-instance 'agent-capability
                 :name name
                 :description description
                 :parameters parameters
                 :source-agent source-agent
                 :source-code source-code
                 :extension-id extension-id
                 :promotion-status :draft))

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Definition by Agents
;;; ═══════════════════════════════════════════════════════════════════

(defun agent-define-capability (agent name description params body)
  "Allow an agent to define a new capability.
   
   This function validates the capability code through the extension compiler,
   compiles it if valid, and creates an agent-capability instance linked to
   the agent.
   
   Arguments:
     agent       - The defining agent
     name        - Capability name (keyword)
     description - Human-readable description
     params      - Parameter specification ((name type) ...)
     body        - Implementation code (will be validated)
   
   Returns: (values agent-capability errors)
     agent-capability - The created capability, or NIL on failure
     errors           - List of validation/compilation errors
   
   Example:
     (agent-define-capability my-agent
       :calculate-sum
       \"Calculate the sum of a list of numbers\"
       '((numbers list))
       '((reduce #'+ numbers)))"
  (let* ((lambda-list (mapcar #'first params))
         (full-code `(lambda ,lambda-list ,@body)))
    ;; Validate the code first
    (multiple-value-bind (valid-p validation-errors)
        (autopoiesis.core:validate-extension-code full-code)
      (if (not valid-p)
          ;; Return nil with validation errors
          (values nil validation-errors)
          ;; Compile the lambda directly (not wrapped)
          (handler-case
              (let* ((compiled-fn (compile nil full-code))
                     ;; Also register as extension for tracking
                     (ext-id (autopoiesis.core:make-uuid))
                     (cap (make-instance 'agent-capability
                                         :name name
                                         :description description
                                         :parameters params
                                         :function compiled-fn
                                         :source-agent (agent-id agent)
                                         :source-code full-code
                                         :extension-id ext-id
                                         :promotion-status :draft)))
                ;; Add to agent's capabilities list
                (push cap (agent-capabilities agent))
                (values cap nil))
            (error (e)
              (values nil (list (format nil "Compilation error: ~a" e)))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Testing
;;; ═══════════════════════════════════════════════════════════════════

(defun test-agent-capability (capability test-cases)
  "Test an agent-defined capability with test cases.
   
   Each test case is a list of (input expected-output) where input
   is passed to the capability and the result is compared to expected-output.
   
   Arguments:
     capability - agent-capability to test
     test-cases - List of (input expected-output) pairs
   
   Returns: (values passed-p results)
     passed-p - T if all tests passed
     results  - List of test result plists
   
   Side effects:
     - Updates cap-test-results with results
     - Sets cap-promotion-status to :testing
   
   Example:
     (test-agent-capability my-cap
       '(((2 3) 6)
         ((4 5) 20)
         ((0 100) 0)))"
  ;; Mark as testing
  (setf (cap-promotion-status capability) :testing)
  
  (let ((results nil)
        (passed 0)
        (failed 0)
        (cap-fn (capability-function capability)))
    
    (dolist (test test-cases)
      (let* ((input (first test))
             (expected (second test))
             ;; Ensure input is a list for apply
             (args (if (listp input) input (list input))))
        (handler-case
            (let ((actual (apply cap-fn args)))
              (if (equal actual expected)
                  (progn
                    (incf passed)
                    (push (list :status :pass
                                :input input
                                :expected expected
                                :actual actual)
                          results))
                  (progn
                    (incf failed)
                    (push (list :status :fail
                                :input input
                                :expected expected
                                :actual actual)
                          results))))
          (error (e)
            (incf failed)
            (push (list :status :error
                        :input input
                        :expected expected
                        :error (format nil "~a" e))
                  results)))))
    
    ;; Store results
    (setf (cap-test-results capability) (nreverse results))
    
    ;; Return success status and results
    (values (zerop failed) (cap-test-results capability))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Promotion
;;; ═══════════════════════════════════════════════════════════════════

(defun promote-capability (capability)
  "Promote an agent capability to permanent/global status.
   
   A capability can only be promoted if:
   1. It is in :testing status
   2. All tests passed (no :fail or :error results)
   
   On successful promotion:
   - Sets cap-promotion-status to :promoted
   - Registers the capability in the global registry
   
   Arguments:
     capability - agent-capability to promote
   
   Returns: T if promoted, NIL if promotion failed"
  (unless (eq (cap-promotion-status capability) :testing)
    (return-from promote-capability nil))
  
  ;; Verify all tests passed
  (let ((test-results (cap-test-results capability)))
    (unless test-results
      ;; No tests run yet
      (return-from promote-capability nil))
    
    (unless (every (lambda (r) (eq (getf r :status) :pass)) test-results)
      ;; Some tests failed
      (setf (cap-promotion-status capability) :rejected)
      (return-from promote-capability nil))
    
    ;; All tests passed - promote
    (setf (cap-promotion-status capability) :promoted)

    ;; Register in global capability registry
    (register-capability capability)

    ;; Hook: crystallization engine will store promoted capabilities in DAG
    ;; when autopoiesis.crystallize is loaded

    t))

(defun reject-capability (capability &optional reason)
  "Reject an agent capability.
   
   Arguments:
     capability - agent-capability to reject
     reason     - Optional reason string (stored in test-results)
   
   Returns: T"
  (setf (cap-promotion-status capability) :rejected)
  (when reason
    (push (list :status :rejected :reason reason)
          (cap-test-results capability)))
  t)

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Queries
;;; ═══════════════════════════════════════════════════════════════════

(defun agent-capability-p (obj)
  "Return T if OBJ is an agent-capability."
  (typep obj 'agent-capability))

(defun list-agent-capabilities (agent &key (status nil))
  "List capabilities defined by an agent.
   
   Arguments:
     agent  - The agent to query
     status - Optional status filter (:draft :testing :promoted :rejected)
   
   Returns: List of agent-capability instances"
  (let ((caps (remove-if-not (lambda (c) (typep c 'agent-capability))
                             (agent-capabilities agent))))
    (if status
        (remove-if-not (lambda (c) (eq (cap-promotion-status c) status)) caps)
        caps)))

(defun find-agent-capability (agent name)
  "Find an agent-defined capability by name.
   
   Arguments:
     agent - The agent to search
     name  - Capability name (keyword)
   
   Returns: agent-capability or NIL"
  (find name (agent-capabilities agent)
        :key #'capability-name
        :test #'eq))
