# Autopoiesis: Snapshot System

## Specification Document 03: Snapshot System

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

The Snapshot System provides the foundation for time-travel debugging, branching exploration, and complete auditability of agent cognition. Every significant moment in an agent's cognitive process is captured as an immutable snapshot, forming a directed acyclic graph (DAG) of cognitive states.

---

## Conceptual Model

```
                                    ┌─────────────┐
                                    │  Current    │
                                    │  (HEAD)     │
                                    └──────┬──────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
              ▼                            ▼                            ▼
        ┌───────────┐              ┌───────────┐              ┌───────────┐
        │ Snapshot  │              │ Snapshot  │              │ Snapshot  │
        │   S-7     │              │   S-8     │              │   S-9     │
        │ (branch A)│              │ (branch B)│              │ (branch C)│
        └─────┬─────┘              └─────┬─────┘              └─────┬─────┘
              │                          │                          │
              │                          └────────────┬─────────────┘
              │                                       │
              ▼                                       ▼
        ┌───────────┐                          ┌───────────┐
        │ Snapshot  │                          │ Snapshot  │
        │   S-5     │                          │   S-6     │
        └─────┬─────┘                          └─────┬─────┘
              │                                      │
              └──────────────────┬───────────────────┘
                                 │
                                 ▼
                          ┌───────────┐
                          │ Snapshot  │
                          │   S-4     │
                          │ (decision)│
                          └─────┬─────┘
                                │
                                ▼
                          ┌───────────┐
                          │ Snapshot  │
                          │   S-3     │
                          └─────┬─────┘
                                │
                                ▼
                          ┌───────────┐
                          │ Snapshot  │
                          │   S-2     │
                          └─────┬─────┘
                                │
                                ▼
                          ┌───────────┐
                          │ Snapshot  │
                          │   S-1     │
                          └─────┬─────┘
                                │
                                ▼
                          ┌───────────┐
                          │ Genesis   │
                          │   S-0     │
                          └───────────┘
```

---

## Snapshot Data Structure

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; snapshot.lisp - Snapshot data structure
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

;;; ─────────────────────────────────────────────────────────────────
;;; Snapshot Class
;;; ─────────────────────────────────────────────────────────────────

(defclass snapshot ()
  (;; Identity
   (id :initarg :id
       :accessor snapshot-id
       :initform (make-snapshot-id)
       :documentation "Content-addressable hash ID")
   (sequence-number :initarg :sequence-number
                    :accessor snapshot-sequence
                    :documentation "Monotonic sequence for ordering")
   (timestamp :initarg :timestamp
              :accessor snapshot-timestamp
              :initform (get-precise-time)
              :documentation "High-precision timestamp")

   ;; Lineage
   (parent-id :initarg :parent-id
              :accessor snapshot-parent-id
              :initform nil
              :documentation "ID of parent snapshot")
   (branch :initarg :branch
           :accessor snapshot-branch
           :initform "main"
           :documentation "Branch name")
   (children-ids :initarg :children-ids
                 :accessor snapshot-children-ids
                 :initform nil
                 :documentation "IDs of child snapshots")

   ;; Agent State
   (agent-id :initarg :agent-id
             :accessor snapshot-agent-id
             :documentation "ID of the agent this snapshot captures")
   (agent-state :initarg :agent-state
                :accessor snapshot-agent-state
                :documentation "Complete agent state as S-expression")

   ;; Cognitive State
   (thought-stream-snapshot :initarg :thought-stream
                            :accessor snapshot-thought-stream
                            :documentation "Thoughts up to this point")
   (context-snapshot :initarg :context
                     :accessor snapshot-context
                     :documentation "Context window state")
   (pending-continuation :initarg :pending
                         :accessor snapshot-pending
                         :documentation "What was about to happen")

   ;; Decision Information (if decision point)
   (decision :initarg :decision
             :accessor snapshot-decision
             :initform nil
             :documentation "The decision made at this point")
   (alternatives :initarg :alternatives
                 :accessor snapshot-alternatives
                 :initform nil
                 :documentation "Options not taken")

   ;; Metadata
   (type :initarg :type
         :accessor snapshot-type
         :initform :action
         :documentation ":genesis :thought :decision :action :fork :merge :human")
   (trigger :initarg :trigger
            :accessor snapshot-trigger
            :initform nil
            :documentation "What caused this snapshot")

   ;; Human annotations (mutable)
   (tags :initarg :tags
         :accessor snapshot-tags
         :initform nil)
   (notes :initarg :notes
          :accessor snapshot-notes
          :initform nil)
   (bookmarked :initarg :bookmarked
               :accessor snapshot-bookmarked-p
               :initform nil))

  (:documentation "An immutable snapshot of agent cognitive state"))

;;; ─────────────────────────────────────────────────────────────────
;;; Snapshot ID Generation
;;; ─────────────────────────────────────────────────────────────────

(defun make-snapshot-id (&optional content)
  "Generate a content-addressable ID.
   If CONTENT is provided, hash it. Otherwise, use UUID."
  (if content
      (let ((hash (sexpr-hash content)))
        (format nil "snap-~a" (subseq hash 0 12)))
      (format nil "snap-~a" (subseq (make-uuid) 0 12))))

(defun compute-snapshot-id (snapshot)
  "Compute the content-based ID for SNAPSHOT."
  (make-snapshot-id
   `(,(snapshot-agent-id snapshot)
     ,(snapshot-parent-id snapshot)
     ,(snapshot-agent-state snapshot)
     ,(snapshot-timestamp snapshot))))

;;; ─────────────────────────────────────────────────────────────────
;;; Snapshot Creation
;;; ─────────────────────────────────────────────────────────────────

(defvar *snapshot-sequence* 0
  "Global sequence counter for snapshot ordering.")

(defun create-snapshot (agent &key (type :action) trigger decision alternatives)
  "Create a snapshot of AGENT's current state."
  (let* ((parent (current-snapshot agent))
         (snapshot (make-instance 'snapshot
                     :sequence-number (incf *snapshot-sequence*)
                     :parent-id (when parent (snapshot-id parent))
                     :branch (current-branch agent)
                     :agent-id (agent-id agent)
                     :agent-state (agent-to-sexpr agent)
                     :thought-stream (stream-to-sexpr (agent-thought-stream agent))
                     :context (context-to-sexpr (agent-context-window agent))
                     :pending (capture-pending-continuation agent)
                     :type type
                     :trigger trigger
                     :decision decision
                     :alternatives alternatives)))

    ;; Compute content-based ID
    (setf (snapshot-id snapshot) (compute-snapshot-id snapshot))

    ;; Update parent's children
    (when parent
      (push (snapshot-id snapshot) (snapshot-children-ids parent))
      (save-snapshot parent))  ; Re-save with updated children

    ;; Store
    (save-snapshot snapshot)

    ;; Update agent's current snapshot reference
    (setf (agent-current-snapshot agent) snapshot)

    snapshot))

(defun maybe-create-snapshot (agent trigger)
  "Create snapshot based on configuration and TRIGGER type."
  (let ((freq (config-snapshot-frequency *autopoiesis-config*)))
    (when (should-snapshot-p freq trigger)
      (create-snapshot agent :trigger trigger))))

(defun should-snapshot-p (frequency trigger)
  "Determine if a snapshot should be created."
  (ecase frequency
    (:every-thought t)
    (:every-action (member trigger '(:action :decision :fork :human)))
    (:on-decision (member trigger '(:decision :fork :human)))
    (:manual nil)))

;;; ─────────────────────────────────────────────────────────────────
;;; Capturing Continuation
;;; ─────────────────────────────────────────────────────────────────

(defun capture-pending-continuation (agent)
  "Capture what the agent was about to do.
   Returns an S-expression representing the pending computation."
  (let ((pending (agent-pending-actions agent)))
    (when pending
      `(pending-actions ,@pending))))

(defun restore-pending-continuation (agent continuation-sexpr)
  "Restore agent's pending actions from CONTINUATION-SEXPR."
  (when continuation-sexpr
    (setf (agent-pending-actions agent)
          (rest continuation-sexpr))))  ; Skip 'pending-actions symbol
```

---

## Snapshot Store

Content-addressable storage for snapshots with efficient retrieval.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; store.lisp - Snapshot persistence
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

;;; ─────────────────────────────────────────────────────────────────
;;; Store Protocol
;;; ─────────────────────────────────────────────────────────────────

(defclass snapshot-store ()
  ((backend :initarg :backend
            :accessor store-backend
            :documentation "Storage backend: :memory :sqlite :filesystem")
   (path :initarg :path
         :accessor store-path
         :documentation "Base path for storage")
   (cache :initarg :cache
          :accessor store-cache
          :initform (make-lru-cache 1000)
          :documentation "LRU cache of recently accessed snapshots")
   (index :initarg :index
          :accessor store-index
          :documentation "Index for fast lookups"))
  (:documentation "Persistent storage for snapshots"))

(defvar *snapshot-store* nil
  "Global snapshot store instance.")

(defun initialize-store (path &key (backend :sqlite))
  "Initialize the global snapshot store."
  (setf *snapshot-store*
        (make-instance 'snapshot-store
                       :backend backend
                       :path path
                       :index (make-snapshot-index)))
  (ensure-directories-exist path)
  (load-or-create-index *snapshot-store*)
  *snapshot-store*)

;;; ─────────────────────────────────────────────────────────────────
;;; Core Operations
;;; ─────────────────────────────────────────────────────────────────

(defgeneric save-snapshot (snapshot &optional store)
  (:documentation "Persist SNAPSHOT to STORE"))

(defgeneric load-snapshot (id &optional store)
  (:documentation "Load snapshot with ID from STORE"))

(defgeneric delete-snapshot (id &optional store)
  (:documentation "Delete snapshot with ID from STORE"))

(defgeneric list-snapshots (&key agent-id branch type start end store)
  (:documentation "List snapshots matching criteria"))

;; SQLite Backend Implementation

(defmethod save-snapshot (snapshot &optional (store *snapshot-store*))
  "Save snapshot to SQLite store."
  (let ((sexpr (snapshot-to-sexpr snapshot)))
    ;; Store in cache
    (cache-put (store-cache store) (snapshot-id snapshot) snapshot)

    ;; Store in database
    (ecase (store-backend store)
      (:sqlite
       (execute-sql store
         "INSERT OR REPLACE INTO snapshots (id, parent_id, agent_id, branch, type, timestamp, data)
          VALUES (?, ?, ?, ?, ?, ?, ?)"
         (snapshot-id snapshot)
         (snapshot-parent-id snapshot)
         (snapshot-agent-id snapshot)
         (snapshot-branch snapshot)
         (string (snapshot-type snapshot))
         (snapshot-timestamp snapshot)
         (sexpr-serialize sexpr)))

      (:filesystem
       (let ((path (snapshot-file-path store (snapshot-id snapshot))))
         (ensure-directories-exist path)
         (with-open-file (out path :direction :output :if-exists :supersede)
           (print sexpr out))))

      (:memory
       (setf (gethash (snapshot-id snapshot) (store-memory store)) snapshot)))

    ;; Update index
    (index-snapshot (store-index store) snapshot)

    snapshot))

(defmethod load-snapshot (id &optional (store *snapshot-store*))
  "Load snapshot from store."
  ;; Check cache first
  (or (cache-get (store-cache store) id)

      ;; Load from backend
      (let ((snapshot
              (ecase (store-backend store)
                (:sqlite
                 (let ((row (query-single store
                              "SELECT data FROM snapshots WHERE id = ?"
                              id)))
                   (when row
                     (sexpr-to-snapshot (sexpr-deserialize (first row))))))

                (:filesystem
                 (let ((path (snapshot-file-path store id)))
                   (when (probe-file path)
                     (with-open-file (in path)
                       (sexpr-to-snapshot (read in))))))

                (:memory
                 (gethash id (store-memory store))))))

        ;; Add to cache
        (when snapshot
          (cache-put (store-cache store) id snapshot))

        snapshot)))

;;; ─────────────────────────────────────────────────────────────────
;;; Snapshot Index
;;; ─────────────────────────────────────────────────────────────────

(defclass snapshot-index ()
  ((by-agent :initform (make-hash-table :test 'equal)
             :accessor index-by-agent
             :documentation "agent-id -> list of snapshot-ids")
   (by-branch :initform (make-hash-table :test 'equal)
              :accessor index-by-branch
              :documentation "branch-name -> list of snapshot-ids")
   (by-type :initform (make-hash-table :test 'eq)
            :accessor index-by-type
            :documentation "type -> list of snapshot-ids")
   (by-timestamp :initform (make-sorted-index)
                 :accessor index-by-timestamp
                 :documentation "Sorted by timestamp for range queries")
   (branch-heads :initform (make-hash-table :test 'equal)
                 :accessor index-branch-heads
                 :documentation "branch-name -> head snapshot-id")
   (decision-points :initform nil
                    :accessor index-decision-points
                    :documentation "List of decision snapshot IDs"))
  (:documentation "Index for fast snapshot queries"))

(defun make-snapshot-index ()
  (make-instance 'snapshot-index))

(defun index-snapshot (index snapshot)
  "Add SNAPSHOT to INDEX."
  (let ((id (snapshot-id snapshot)))
    ;; By agent
    (push id (gethash (snapshot-agent-id snapshot) (index-by-agent index)))

    ;; By branch
    (push id (gethash (snapshot-branch snapshot) (index-by-branch index)))
    (setf (gethash (snapshot-branch snapshot) (index-branch-heads index)) id)

    ;; By type
    (push id (gethash (snapshot-type snapshot) (index-by-type index)))

    ;; By timestamp
    (sorted-index-insert (index-by-timestamp index)
                         (snapshot-timestamp snapshot)
                         id)

    ;; Track decision points
    (when (eq (snapshot-type snapshot) :decision)
      (push id (index-decision-points index)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Query Operations
;;; ─────────────────────────────────────────────────────────────────

(defmethod list-snapshots (&key agent-id branch type (start 0) (end most-positive-fixnum)
                                (store *snapshot-store*))
  "List snapshots matching criteria."
  (let ((candidates nil))
    (cond
      ;; Filter by agent
      (agent-id
       (setf candidates (gethash agent-id (index-by-agent (store-index store)))))

      ;; Filter by branch
      (branch
       (setf candidates (gethash branch (index-by-branch (store-index store)))))

      ;; Filter by type
      (type
       (setf candidates (gethash type (index-by-type (store-index store)))))

      ;; All snapshots in time range
      (t
       (setf candidates (sorted-index-range (index-by-timestamp (store-index store))
                                            start end))))

    ;; Apply additional filters
    (when (and agent-id branch)
      (setf candidates (intersection candidates
                                      (gethash branch (index-by-branch (store-index store)))
                                      :test #'equal)))

    ;; Load actual snapshots
    (mapcar (lambda (id) (load-snapshot id store)) candidates)))

(defun find-decision-points (agent-id &key (store *snapshot-store*))
  "Find all decision point snapshots for AGENT-ID."
  (let ((agent-snaps (gethash agent-id (index-by-agent (store-index store))))
        (decisions (index-decision-points (store-index store))))
    (mapcar (lambda (id) (load-snapshot id store))
            (intersection agent-snaps decisions :test #'equal))))

(defun find-branch-point (snapshot-id &key (store *snapshot-store*))
  "Find the snapshot where SNAPSHOT-ID's branch diverged."
  (let ((snapshot (load-snapshot snapshot-id store)))
    (loop for current = snapshot then (load-snapshot (snapshot-parent-id current) store)
          while current
          when (> (length (snapshot-children-ids current)) 1)
          return current)))
```

---

## Branching System

Git-like branching for exploring alternative cognitive paths.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; branch.lisp - Branching and merging
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

;;; ─────────────────────────────────────────────────────────────────
;;; Branch Class
;;; ─────────────────────────────────────────────────────────────────

(defclass branch ()
  ((name :initarg :name
         :accessor branch-name
         :documentation "Unique branch name")
   (head :initarg :head
         :accessor branch-head
         :documentation "Current head snapshot ID")
   (base :initarg :base
         :accessor branch-base
         :documentation "Snapshot where branch was created")
   (created-at :initarg :created-at
               :accessor branch-created-at
               :initform (get-universal-time))
   (created-by :initarg :created-by
               :accessor branch-created-by
               :documentation "Agent or human that created branch")
   (description :initarg :description
                :accessor branch-description
                :initform nil)
   (status :initarg :status
           :accessor branch-status
           :initform :active
           :documentation ":active :merged :abandoned"))
  (:documentation "A named branch in the snapshot DAG"))

(defvar *branches* (make-hash-table :test 'equal)
  "Registry of all branches.")

(defvar *current-branch* "main"
  "Currently active branch name.")

;;; ─────────────────────────────────────────────────────────────────
;;; Branch Operations
;;; ─────────────────────────────────────────────────────────────────

(defun create-branch (name &key (from *current-branch*) description created-by)
  "Create a new branch starting from FROM."
  (when (gethash name *branches*)
    (error 'autopoiesis-error :message (format nil "Branch ~a already exists" name)))

  (let* ((base-snapshot (if (typep from 'snapshot)
                            from
                            (branch-head (find-branch from))))
         (branch (make-instance 'branch
                                :name name
                                :head (snapshot-id base-snapshot)
                                :base (snapshot-id base-snapshot)
                                :description description
                                :created-by created-by)))
    (setf (gethash name *branches*) branch)
    branch))

(defun find-branch (name)
  "Find branch by NAME."
  (or (gethash name *branches*)
      (error 'autopoiesis-error :message (format nil "Branch ~a not found" name))))

(defun switch-branch (name)
  "Switch to branch NAME."
  (find-branch name)  ; Ensure exists
  (setf *current-branch* name))

(defun current-branch (&optional agent)
  "Get current branch name."
  (declare (ignore agent))
  *current-branch*)

(defun list-branches (&key status)
  "List all branches, optionally filtered by STATUS."
  (let ((branches nil))
    (maphash (lambda (name branch)
               (declare (ignore name))
               (when (or (null status) (eq (branch-status branch) status))
                 (push branch branches)))
             *branches*)
    branches))

(defun delete-branch (name &key force)
  "Delete branch NAME. Requires FORCE if branch has unmerged work."
  (let ((branch (find-branch name)))
    (when (and (not force)
               (eq (branch-status branch) :active)
               (not (branch-merged-p branch)))
      (error 'autopoiesis-error :message "Branch has unmerged work. Use :force t"))
    (remhash name *branches*)))

;;; ─────────────────────────────────────────────────────────────────
;;; Forking (Creating Branch at Decision Point)
;;; ─────────────────────────────────────────────────────────────────

(defun fork-from-snapshot (snapshot-id &key name explore-alternative)
  "Create a fork (new branch) from SNAPSHOT-ID.
   If EXPLORE-ALTERNATIVE is provided, start from that unchosen path."
  (let* ((snapshot (load-snapshot snapshot-id))
         (branch-name (or name (generate-branch-name snapshot)))
         (branch (create-branch branch-name :from snapshot)))

    ;; If exploring an alternative, set up the agent to take that path
    (when explore-alternative
      (let* ((agent (restore-agent-from-snapshot snapshot))
             (alt (find explore-alternative (snapshot-alternatives snapshot)
                        :key #'car)))
        (when alt
          ;; Modify the pending continuation to take this alternative
          (setf (agent-pending-actions agent)
                (list (car alt)))
          ;; Create new snapshot on this branch
          (let ((*current-branch* branch-name))
            (create-snapshot agent
                             :type :fork
                             :trigger `(:exploring-alternative ,explore-alternative))))))

    branch))

(defun fork-here (&optional name)
  "Fork at current position."
  (let ((current (current-snapshot *current-agent*)))
    (fork-from-snapshot (snapshot-id current) :name name)))

(defun generate-branch-name (snapshot)
  "Generate a descriptive branch name from SNAPSHOT."
  (format nil "~a-~a-~a"
          (snapshot-branch snapshot)
          (string-downcase (string (snapshot-type snapshot)))
          (subseq (snapshot-id snapshot) 5 9)))

;;; ─────────────────────────────────────────────────────────────────
;;; Merging
;;; ─────────────────────────────────────────────────────────────────

(defun merge-branches (source-name target-name &key conflict-resolution)
  "Merge SOURCE-NAME branch into TARGET-NAME.
   CONFLICT-RESOLUTION: :prefer-source :prefer-target :manual"
  (let ((source (find-branch source-name))
        (target (find-branch target-name)))

    ;; Find common ancestor
    (let ((ancestor (find-common-ancestor (branch-head source)
                                          (branch-head target))))
      (unless ancestor
        (error 'autopoiesis-error :message "Branches have no common ancestor"))

      ;; Compute changes from ancestor to each head
      (let ((source-changes (compute-branch-changes ancestor (branch-head source)))
            (target-changes (compute-branch-changes ancestor (branch-head target))))

        ;; Detect conflicts
        (let ((conflicts (find-merge-conflicts source-changes target-changes)))
          (when (and conflicts (not conflict-resolution))
            (error 'branch-conflict
                   :branch-a source-name
                   :branch-b target-name
                   :conflicts conflicts))

          ;; Resolve conflicts
          (let ((resolved-changes
                  (if conflicts
                      (resolve-conflicts source-changes target-changes
                                         conflicts conflict-resolution)
                      (merge-change-sets source-changes target-changes))))

            ;; Apply merged changes to target
            (let* ((target-head-snapshot (load-snapshot (branch-head target)))
                   (merged-snapshot (apply-changes target-head-snapshot
                                                   resolved-changes)))
              (setf (snapshot-type merged-snapshot) :merge
                    (snapshot-trigger merged-snapshot) `(:merged-from ,source-name))

              ;; Save and update target head
              (let ((*current-branch* target-name))
                (save-snapshot merged-snapshot))
              (setf (branch-head target) (snapshot-id merged-snapshot))

              ;; Mark source as merged
              (setf (branch-status source) :merged)

              merged-snapshot)))))))

(defun find-common-ancestor (snapshot-id-a snapshot-id-b)
  "Find the most recent common ancestor of two snapshots."
  (let ((ancestors-a (collect-ancestors snapshot-id-a)))
    (loop for id = snapshot-id-b then (snapshot-parent-id (load-snapshot id))
          while id
          when (member id ancestors-a :test #'equal)
          return (load-snapshot id))))

(defun collect-ancestors (snapshot-id)
  "Collect all ancestor IDs of SNAPSHOT-ID."
  (loop for id = snapshot-id then (snapshot-parent-id (load-snapshot id))
        while id
        collect id))

(defun compute-branch-changes (ancestor-id head-id)
  "Compute the set of changes from ANCESTOR-ID to HEAD-ID."
  (let ((changes nil))
    (loop for id = head-id then (snapshot-parent-id snapshot)
          for snapshot = (load-snapshot id)
          until (equal id ancestor-id)
          do (push (snapshot-to-change snapshot) changes))
    changes))

(defun find-merge-conflicts (changes-a changes-b)
  "Find conflicts between two change sets."
  (let ((conflicts nil))
    ;; Check for conflicting modifications to same state
    (dolist (change-a changes-a)
      (dolist (change-b changes-b)
        (when (changes-conflict-p change-a change-b)
          (push (list change-a change-b) conflicts))))
    conflicts))

(defun resolve-conflicts (changes-a changes-b conflicts resolution)
  "Resolve CONFLICTS between change sets according to RESOLUTION strategy."
  (ecase resolution
    (:prefer-source
     (merge-change-sets changes-a changes-b :prefer :a))
    (:prefer-target
     (merge-change-sets changes-a changes-b :prefer :b))
    (:manual
     (resolve-conflicts-manually changes-a changes-b conflicts))))
```

---

## Time Travel Navigation

Moving through the snapshot DAG.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; navigation.lisp - Time travel through snapshots
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

;;; ─────────────────────────────────────────────────────────────────
;;; Navigation State
;;; ─────────────────────────────────────────────────────────────────

(defclass navigator ()
  ((current-snapshot :initarg :current
                     :accessor nav-current
                     :documentation "Currently viewed snapshot")
   (agent :initarg :agent
          :accessor nav-agent
          :documentation "Agent being navigated")
   (history :initarg :history
            :accessor nav-history
            :initform nil
            :documentation "Navigation history for back/forward")
   (history-position :initarg :position
                     :accessor nav-position
                     :initform 0)
   (bookmarks :initarg :bookmarks
              :accessor nav-bookmarks
              :initform nil
              :documentation "User-set bookmarks"))
  (:documentation "State for navigating through snapshots"))

(defvar *navigator* nil
  "Current navigator instance.")

;;; ─────────────────────────────────────────────────────────────────
;;; Basic Navigation
;;; ─────────────────────────────────────────────────────────────────

(defun jump-to (snapshot-id &optional (navigator *navigator*))
  "Jump to SNAPSHOT-ID."
  (let ((snapshot (load-snapshot snapshot-id)))
    (unless snapshot
      (error 'snapshot-not-found :snapshot-id snapshot-id))

    ;; Record in history
    (push (nav-current navigator) (nav-history navigator))
    (setf (nav-position navigator) 0)

    ;; Update current
    (setf (nav-current navigator) snapshot)

    ;; Restore agent to this state if requested
    (when (nav-agent navigator)
      (restore-agent-to-snapshot (nav-agent navigator) snapshot))

    snapshot))

(defun step-forward (&optional (n 1) (navigator *navigator*))
  "Move forward N snapshots on current branch."
  (let ((current (nav-current navigator)))
    (dotimes (i n)
      (let ((children (snapshot-children-ids current)))
        (cond
          ;; No children - at head
          ((null children)
           (return-from step-forward current))
          ;; One child - follow it
          ((= (length children) 1)
           (setf current (load-snapshot (first children))))
          ;; Multiple children - stay on same branch
          (t
           (let ((same-branch (find-if (lambda (id)
                                         (equal (snapshot-branch (load-snapshot id))
                                                (snapshot-branch current)))
                                       children)))
             (setf current (load-snapshot (or same-branch (first children)))))))))
    (jump-to (snapshot-id current) navigator)))

(defun step-backward (&optional (n 1) (navigator *navigator*))
  "Move backward N snapshots."
  (let ((current (nav-current navigator)))
    (dotimes (i n)
      (let ((parent-id (snapshot-parent-id current)))
        (unless parent-id
          (return-from step-backward current))
        (setf current (load-snapshot parent-id))))
    (jump-to (snapshot-id current) navigator)))

(defun go-to-genesis (&optional (navigator *navigator*))
  "Jump to the genesis (first) snapshot."
  (let ((current (nav-current navigator)))
    (loop for snapshot = current then (load-snapshot (snapshot-parent-id snapshot))
          while (snapshot-parent-id snapshot)
          finally (return (jump-to (snapshot-id snapshot) navigator)))))

(defun go-to-head (&optional branch (navigator *navigator*))
  "Jump to the head of BRANCH (default: current branch)."
  (let* ((branch-name (or branch (snapshot-branch (nav-current navigator))))
         (branch-obj (find-branch branch-name)))
    (jump-to (branch-head branch-obj) navigator)))

;;; ─────────────────────────────────────────────────────────────────
;;; History Navigation
;;; ─────────────────────────────────────────────────────────────────

(defun nav-back (&optional (navigator *navigator*))
  "Go back in navigation history."
  (when (nav-history navigator)
    (let ((prev (pop (nav-history navigator))))
      (incf (nav-position navigator))
      (setf (nav-current navigator) prev)
      prev)))

(defun nav-forward (&optional (navigator *navigator*))
  "Go forward in navigation history."
  (when (> (nav-position navigator) 0)
    (decf (nav-position navigator))
    ;; Reconstruct forward by re-navigating
    ))

;;; ─────────────────────────────────────────────────────────────────
;;; Semantic Navigation
;;; ─────────────────────────────────────────────────────────────────

(defun jump-to-decision (direction &optional (navigator *navigator*))
  "Jump to next/previous decision point.
   DIRECTION: :next or :previous"
  (let ((current (nav-current navigator))
        (decisions (index-decision-points (store-index *snapshot-store*))))
    (ecase direction
      (:next
       (let ((future-decisions
               (remove-if (lambda (id)
                            (<= (snapshot-sequence (load-snapshot id))
                                (snapshot-sequence current)))
                          decisions)))
         (when future-decisions
           (jump-to (first (sort future-decisions #'<
                                 :key (lambda (id)
                                        (snapshot-sequence (load-snapshot id)))))
                    navigator))))
      (:previous
       (let ((past-decisions
               (remove-if (lambda (id)
                            (>= (snapshot-sequence (load-snapshot id))
                                (snapshot-sequence current)))
                          decisions)))
         (when past-decisions
           (jump-to (first (sort past-decisions #'>
                                 :key (lambda (id)
                                        (snapshot-sequence (load-snapshot id)))))
                    navigator)))))))

(defun jump-to-branch-point (&optional (navigator *navigator*))
  "Jump to where current branch diverged."
  (let* ((current (nav-current navigator))
         (branch-point (find-branch-point (snapshot-id current))))
    (when branch-point
      (jump-to (snapshot-id branch-point) navigator))))

(defun jump-to-tagged (tag &optional (navigator *navigator*))
  "Jump to first snapshot with TAG."
  (let ((tagged (find-if (lambda (s) (member tag (snapshot-tags s)))
                         (list-snapshots :agent-id (snapshot-agent-id
                                                    (nav-current navigator))))))
    (when tagged
      (jump-to (snapshot-id tagged) navigator))))

;;; ─────────────────────────────────────────────────────────────────
;;; Bookmarks
;;; ─────────────────────────────────────────────────────────────────

(defun bookmark-current (name &optional (navigator *navigator*))
  "Bookmark current snapshot as NAME."
  (push (cons name (snapshot-id (nav-current navigator)))
        (nav-bookmarks navigator)))

(defun jump-to-bookmark (name &optional (navigator *navigator*))
  "Jump to bookmark NAME."
  (let ((bookmark (assoc name (nav-bookmarks navigator) :test #'equal)))
    (when bookmark
      (jump-to (cdr bookmark) navigator))))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent State Restoration
;;; ─────────────────────────────────────────────────────────────────

(defun restore-agent-to-snapshot (agent snapshot)
  "Restore AGENT to the state captured in SNAPSHOT."
  ;; Pause agent if running
  (when (eq (agent-status agent) :running)
    (pause-agent agent))

  ;; Restore from serialized state
  (let ((restored (sexpr-to-agent (snapshot-agent-state snapshot))))
    ;; Copy state to existing agent (preserving identity)
    (setf (agent-thought-stream agent) (agent-thought-stream restored)
          (agent-context-window agent) (agent-context-window restored)
          (agent-bindings agent) (agent-bindings restored)
          (agent-pending-actions agent) nil)

    ;; Restore pending continuation
    (restore-pending-continuation agent (snapshot-pending snapshot))

    ;; Update agent's snapshot reference
    (setf (agent-current-snapshot agent) snapshot))

  agent)

(defun restore-agent-from-snapshot (snapshot)
  "Create a new agent instance from SNAPSHOT state."
  (let ((agent (sexpr-to-agent (snapshot-agent-state snapshot))))
    (restore-pending-continuation agent (snapshot-pending snapshot))
    (setf (agent-current-snapshot agent) snapshot)
    agent))
```

---

## Diffing System

Comparing snapshots to understand changes.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; diff.lisp - Snapshot comparison
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

;;; ─────────────────────────────────────────────────────────────────
;;; Diff Structure
;;; ─────────────────────────────────────────────────────────────────

(defclass snapshot-diff ()
  ((from-id :initarg :from
            :accessor diff-from)
   (to-id :initarg :to
          :accessor diff-to)
   (context-delta :initarg :context-delta
                  :accessor diff-context-delta
                  :documentation "Changes to context window")
   (thoughts-added :initarg :thoughts-added
                   :accessor diff-thoughts-added
                   :documentation "New thoughts")
   (bindings-changed :initarg :bindings-changed
                     :accessor diff-bindings-changed
                     :documentation "Changed variable bindings")
   (capabilities-changed :initarg :capabilities-changed
                         :accessor diff-capabilities-changed
                         :documentation "Added/removed capabilities")
   (decision-made :initarg :decision-made
                  :accessor diff-decision
                  :documentation "Decision if one was made")
   (summary :initarg :summary
            :accessor diff-summary
            :documentation "Human-readable summary"))
  (:documentation "Difference between two snapshots"))

;;; ─────────────────────────────────────────────────────────────────
;;; Computing Diffs
;;; ─────────────────────────────────────────────────────────────────

(defun diff-snapshots (snapshot-a snapshot-b)
  "Compute the difference between SNAPSHOT-A and SNAPSHOT-B."
  (let ((state-a (snapshot-agent-state snapshot-a))
        (state-b (snapshot-agent-state snapshot-b)))
    (make-instance 'snapshot-diff
      :from (snapshot-id snapshot-a)
      :to (snapshot-id snapshot-b)
      :context-delta (diff-contexts (snapshot-context snapshot-a)
                                    (snapshot-context snapshot-b))
      :thoughts-added (diff-thought-streams (snapshot-thought-stream snapshot-a)
                                            (snapshot-thought-stream snapshot-b))
      :bindings-changed (diff-bindings state-a state-b)
      :capabilities-changed (diff-capabilities state-a state-b)
      :decision-made (snapshot-decision snapshot-b)
      :summary (generate-diff-summary snapshot-a snapshot-b))))

(defun diff-contexts (context-a context-b)
  "Compute changes between context states."
  (let ((added nil)
        (removed nil)
        (modified nil))
    ;; Find items in B not in A (added)
    (dolist (item-b context-b)
      (unless (find item-b context-a :test #'sexpr-equal)
        (push item-b added)))
    ;; Find items in A not in B (removed)
    (dolist (item-a context-a)
      (unless (find item-a context-b :test #'sexpr-equal)
        (push item-a removed)))
    `(:added ,added :removed ,removed :modified ,modified)))

(defun diff-thought-streams (stream-a stream-b)
  "Find thoughts in B that aren't in A."
  (let ((ids-a (mapcar #'thought-id (parse-thought-stream stream-a))))
    (remove-if (lambda (thought)
                 (member (thought-id thought) ids-a :test #'equal))
               (parse-thought-stream stream-b))))

(defun diff-bindings (state-a state-b)
  "Compare binding changes between states."
  (let ((bindings-a (getf state-a :bindings))
        (bindings-b (getf state-b :bindings))
        (changes nil))
    (dolist (binding-b bindings-b)
      (let ((binding-a (assoc (car binding-b) bindings-a)))
        (cond
          ((null binding-a)
           (push `(:added ,(car binding-b) ,(cdr binding-b)) changes))
          ((not (sexpr-equal (cdr binding-a) (cdr binding-b)))
           (push `(:changed ,(car binding-b)
                           :from ,(cdr binding-a)
                           :to ,(cdr binding-b))
                 changes)))))
    (dolist (binding-a bindings-a)
      (unless (assoc (car binding-a) bindings-b)
        (push `(:removed ,(car binding-a)) changes)))
    changes))

(defun generate-diff-summary (snapshot-a snapshot-b)
  "Generate human-readable summary of changes."
  (with-output-to-string (s)
    (format s "From ~a to ~a:~%"
            (snapshot-id snapshot-a)
            (snapshot-id snapshot-b))
    (format s "  Time elapsed: ~a seconds~%"
            (- (snapshot-timestamp snapshot-b)
               (snapshot-timestamp snapshot-a)))
    (when (snapshot-decision snapshot-b)
      (format s "  Decision made: ~a~%"
              (decision-chosen (snapshot-decision snapshot-b))))
    (format s "  Type: ~a~%" (snapshot-type snapshot-b))))

;;; ─────────────────────────────────────────────────────────────────
;;; Range Diffs
;;; ─────────────────────────────────────────────────────────────────

(defun diff-range (start-id end-id)
  "Get all diffs in the path from START-ID to END-ID."
  (let ((path (find-path start-id end-id))
        (diffs nil))
    (loop for (a b) on path
          while b
          do (push (diff-snapshots (load-snapshot a)
                                   (load-snapshot b))
                   diffs))
    (nreverse diffs)))

(defun find-path (from-id to-id)
  "Find the path of snapshot IDs from FROM-ID to TO-ID."
  (let ((to-snapshot (load-snapshot to-id)))
    (if (equal from-id to-id)
        (list from-id)
        (let ((path nil))
          (loop for id = to-id then (snapshot-parent-id (load-snapshot id))
                while id
                do (push id path)
                until (equal id from-id))
          path))))

;;; ─────────────────────────────────────────────────────────────────
;;; Diff Visualization
;;; ─────────────────────────────────────────────────────────────────

(defun format-diff (diff &key (stream *standard-output*) (style :detailed))
  "Format DIFF for display."
  (ecase style
    (:summary
     (format stream "~a" (diff-summary diff)))

    (:detailed
     (format stream "~&═══ Snapshot Diff ═══~%")
     (format stream "From: ~a~%" (diff-from diff))
     (format stream "To:   ~a~%~%" (diff-to diff))

     (when (diff-context-delta diff)
       (format stream "Context Changes:~%")
       (let ((delta (diff-context-delta diff)))
         (when (getf delta :added)
           (format stream "  Added:~%")
           (dolist (item (getf delta :added))
             (format stream "    + ~a~%" (truncate-sexpr item 60))))
         (when (getf delta :removed)
           (format stream "  Removed:~%")
           (dolist (item (getf delta :removed))
             (format stream "    - ~a~%" (truncate-sexpr item 60))))))

     (when (diff-thoughts-added diff)
       (format stream "~%New Thoughts:~%")
       (dolist (thought (diff-thoughts-added diff))
         (format stream "  • [~a] ~a~%"
                 (thought-type thought)
                 (truncate-sexpr (thought-content thought) 50))))

     (when (diff-bindings-changed diff)
       (format stream "~%Binding Changes:~%")
       (dolist (change (diff-bindings-changed diff))
         (ecase (first change)
           (:added (format stream "  + ~a = ~a~%"
                           (second change) (third change)))
           (:removed (format stream "  - ~a~%" (second change)))
           (:changed (format stream "  ~ ~a: ~a → ~a~%"
                             (second change)
                             (getf change :from)
                             (getf change :to))))))

     (when (diff-decision diff)
       (format stream "~%Decision:~%")
       (format stream "  Chose: ~a~%" (decision-chosen (diff-decision diff)))
       (format stream "  Rationale: ~a~%"
               (decision-rationale (diff-decision diff)))))))
```

---

## Serialization

Converting snapshots to and from S-expressions.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; serialization.lisp - Snapshot serialization
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

(defun snapshot-to-sexpr (snapshot)
  "Convert SNAPSHOT to S-expression for storage."
  `(snapshot
    :id ,(snapshot-id snapshot)
    :sequence ,(snapshot-sequence snapshot)
    :timestamp ,(snapshot-timestamp snapshot)
    :parent-id ,(snapshot-parent-id snapshot)
    :branch ,(snapshot-branch snapshot)
    :children-ids ,(snapshot-children-ids snapshot)
    :agent-id ,(snapshot-agent-id snapshot)
    :agent-state ,(snapshot-agent-state snapshot)
    :thought-stream ,(snapshot-thought-stream snapshot)
    :context ,(snapshot-context snapshot)
    :pending ,(snapshot-pending snapshot)
    :type ,(snapshot-type snapshot)
    :trigger ,(snapshot-trigger snapshot)
    :decision ,(when (snapshot-decision snapshot)
                 (thought-to-sexpr (snapshot-decision snapshot)))
    :alternatives ,(snapshot-alternatives snapshot)
    :tags ,(snapshot-tags snapshot)
    :notes ,(snapshot-notes snapshot)
    :bookmarked ,(snapshot-bookmarked-p snapshot)))

(defun sexpr-to-snapshot (sexpr)
  "Reconstruct SNAPSHOT from S-expression."
  (destructuring-bind (&key id sequence timestamp parent-id branch children-ids
                            agent-id agent-state thought-stream context pending
                            type trigger decision alternatives
                            tags notes bookmarked)
      (rest sexpr)
    (make-instance 'snapshot
      :id id
      :sequence-number sequence
      :timestamp timestamp
      :parent-id parent-id
      :branch branch
      :children-ids children-ids
      :agent-id agent-id
      :agent-state agent-state
      :thought-stream thought-stream
      :context context
      :pending pending
      :type type
      :trigger trigger
      :decision (when decision (sexpr-to-thought decision))
      :alternatives alternatives
      :tags tags
      :notes notes
      :bookmarked bookmarked)))
```

---

## Next Document

Continue to [04-human-interface.md](./04-human-interface.md) for the human-in-the-loop interaction protocol.
