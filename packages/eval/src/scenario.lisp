;;;; scenario.lisp - Scenario CRUD operations
;;;;
;;;; Create, read, list, and delete eval scenarios stored as substrate entities.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Create
;;; ===================================================================

(defun create-scenario (&key name description prompt domain tags
                           verifier rubric expected timeout)
  "Create an eval scenario as a substrate entity.
   NAME, DESCRIPTION, and PROMPT are required strings.
   DOMAIN is an optional keyword (e.g., :coding, :research, :refactoring).
   TAGS is an optional list of keyword tags.
   VERIFIER is a serialized verifier designator (keyword, plist, or symbol).
   RUBRIC is a string or plist for the LLM judge rubric.
   EXPECTED is the expected output (string or structured data).
   TIMEOUT is an optional per-scenario timeout in seconds.
   Returns the entity ID."
  (unless (and name description prompt)
    (error 'autopoiesis-error
           :message "create-scenario requires :name, :description, and :prompt"))
  (let ((eid (intern-id (format nil "eval-scenario-~a" (make-uuid))))
        (now (get-universal-time)))
    (let ((datoms (list (make-datom eid :entity/type :eval-scenario)
                        (make-datom eid :eval-scenario/name name)
                        (make-datom eid :eval-scenario/description description)
                        (make-datom eid :eval-scenario/prompt prompt)
                        (make-datom eid :eval-scenario/created-at now))))
      (when domain
        (push (make-datom eid :eval-scenario/domain domain) datoms))
      (when tags
        (push (make-datom eid :eval-scenario/tags tags) datoms))
      (when verifier
        (push (make-datom eid :eval-scenario/verifier verifier) datoms))
      (when rubric
        (push (make-datom eid :eval-scenario/rubric rubric) datoms))
      (when expected
        (push (make-datom eid :eval-scenario/expected expected) datoms))
      (when timeout
        (push (make-datom eid :eval-scenario/timeout timeout) datoms))
      (transact! datoms)
      eid)))

;;; ===================================================================
;;; Read
;;; ===================================================================

(defun get-scenario (scenario-id)
  "Get scenario as a plist from substrate. Returns nil if not found."
  (let ((name (entity-attr scenario-id :eval-scenario/name)))
    (when name
      (entity-state scenario-id))))

(defun scenario-prompt (scenario-id)
  "Get just the prompt text for a scenario."
  (entity-attr scenario-id :eval-scenario/prompt))

;;; ===================================================================
;;; List
;;; ===================================================================

(defun list-scenarios (&key domain tag)
  "List all scenario entity IDs, optionally filtered by DOMAIN or TAG."
  (let ((all (find-entities-by-type :eval-scenario)))
    (when domain
      (setf all (remove-if-not
                 (lambda (eid)
                   (eq domain (entity-attr eid :eval-scenario/domain)))
                 all)))
    (when tag
      (setf all (remove-if-not
                 (lambda (eid)
                   (let ((tags (entity-attr eid :eval-scenario/tags)))
                     (and tags (member tag tags :test #'eq))))
                 all)))
    all))

;;; ===================================================================
;;; Delete (soft)
;;; ===================================================================

(defun delete-scenario (scenario-id)
  "Soft-delete a scenario by setting its type to :eval-scenario-deleted."
  (transact! (list (make-datom scenario-id :entity/type :eval-scenario-deleted)))
  t)

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defun scenario-to-alist (scenario-id)
  "Convert a scenario entity to a JSON-friendly alist."
  (let ((state (entity-state scenario-id)))
    (when (getf state :eval-scenario/name)
      `((:id . ,scenario-id)
        (:name . ,(getf state :eval-scenario/name))
        (:description . ,(getf state :eval-scenario/description))
        (:prompt . ,(getf state :eval-scenario/prompt))
        (:domain . ,(let ((d (getf state :eval-scenario/domain)))
                      (when d (string-downcase (symbol-name d)))))
        (:tags . ,(mapcar (lambda (tag) (string-downcase (symbol-name tag)))
                          (or (getf state :eval-scenario/tags) nil)))
        (:has-verifier . ,(if (getf state :eval-scenario/verifier) t nil))
        (:has-rubric . ,(if (getf state :eval-scenario/rubric) t nil))
        (:timeout . ,(getf state :eval-scenario/timeout))
        (:created-at . ,(getf state :eval-scenario/created-at))))))
