;;;; query-tools.lisp - Jarvis query tools for DAG/substrate inspection
;;;;
;;;; These capabilities let Jarvis answer natural language questions
;;;; about sandbox state, snapshots, filesystem trees, and events
;;;; by querying the substrate datoms and snapshot DAG.
;;;;
;;;; Tool results include :blocks for generative UI rendering:
;;;; the frontend renders typed blocks (diff-view, file-tree, etc.)
;;;; as rich SolidJS components alongside the text response.

(in-package #:autopoiesis.jarvis)

;;; ═══════════════════════════════════════════════════════════════════
;;; Block Result Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun make-block (type data &key title)
  "Create a generative UI block for the frontend to render."
  (let ((block (list :type type :data data)))
    (when title (setf (getf block :title) title))
    block))

(defun result-with-blocks (text blocks)
  "Create a tool result with text and generative UI blocks.
   The chat handler extracts :blocks and passes them to the frontend."
  (list :text text :blocks blocks))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Query Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability query-snapshots (&key sandbox-id limit label)
  "List snapshots, optionally filtered by sandbox ID or label.
   Returns a timeline showing snapshot history.

   Parameters:
     sandbox-id - Filter by sandbox (optional)
     limit - Max number of results (default 20)
     label - Filter by label substring (optional)"
  :permissions (:file-read)
  :body
  (let* ((max-results (or limit 20))
         (all-snapshots (when (find-package :autopoiesis.snapshot)
                          (ignore-errors
                            (funcall (find-symbol "LIST-SNAPSHOTS"
                                                  :autopoiesis.snapshot)))))
         (filtered (if all-snapshots
                       (let ((results all-snapshots))
                         (when label
                           (setf results
                                 (remove-if-not
                                  (lambda (s)
                                    (let ((meta (funcall (find-symbol "SNAPSHOT-METADATA"
                                                                     :autopoiesis.snapshot) s)))
                                      (and meta (search label
                                                        (or (getf meta :label) "")
                                                        :test #'char-equal))))
                                  results)))
                         (when sandbox-id
                           (setf results
                                 (remove-if-not
                                  (lambda (s)
                                    (let ((meta (funcall (find-symbol "SNAPSHOT-METADATA"
                                                                     :autopoiesis.snapshot) s)))
                                      (and meta (equal sandbox-id
                                                       (getf meta :sandbox-id)))))
                                  results)))
                         (subseq results 0 (min max-results (length results))))
                       '())))
    (if filtered
        (let ((entries (mapcar (lambda (s)
                                 (let ((snap-id (funcall (find-symbol "SNAPSHOT-ID"
                                                                     :autopoiesis.snapshot) s))
                                       (ts (funcall (find-symbol "SNAPSHOT-TIMESTAMP"
                                                                 :autopoiesis.snapshot) s))
                                       (meta (funcall (find-symbol "SNAPSHOT-METADATA"
                                                                   :autopoiesis.snapshot) s))
                                       (tree-root (funcall (find-symbol "SNAPSHOT-TREE-ROOT"
                                                                        :autopoiesis.snapshot) s)))
                                   (list :id snap-id
                                         :timestamp ts
                                         :type "snapshot"
                                         :label (getf meta :label)
                                         :snapshot_id snap-id
                                         :details (if tree-root
                                                      (format nil "tree: ~A..." (subseq tree-root 0 (min 12 (length tree-root))))
                                                      "no filesystem state"))))
                               filtered)))
          (result-with-blocks
           (format nil "Found ~D snapshot~:P." (length entries))
           (list (make-block "timeline-slice"
                             (list :entries entries)
                             :title "Snapshot History"))))
        "No snapshots found.")))

(autopoiesis.agent:defcapability diff-snapshots (&key snapshot-a snapshot-b)
  "Compare two snapshots and show filesystem differences.
   Returns a diff view showing added, removed, and modified files.

   Parameters:
     snapshot-a - First snapshot ID
     snapshot-b - Second snapshot ID"
  :permissions (:file-read)
  :body
  (unless (and snapshot-a snapshot-b)
    (return-from diff-snapshots "Error: Both snapshot-a and snapshot-b are required."))
  ;; Look up snapshots and diff their trees
  (let* ((snap-pkg (find-package :autopoiesis.snapshot))
         (load-fn (when snap-pkg (find-symbol "LOAD-SNAPSHOT" snap-pkg)))
         (tree-entries-fn (when snap-pkg (find-symbol "SNAPSHOT-TREE-ENTRIES" snap-pkg)))
         (tree-diff-fn (when snap-pkg (find-symbol "TREE-DIFF" snap-pkg))))
    (unless (and load-fn tree-entries-fn tree-diff-fn)
      (return-from diff-snapshots "Error: Snapshot system not available."))
    (let ((snap-a (ignore-errors (funcall load-fn snapshot-a)))
          (snap-b (ignore-errors (funcall load-fn snapshot-b))))
      (unless (and snap-a snap-b)
        (return-from diff-snapshots
          (format nil "Error: Could not load snapshot~A~A."
                  (if snap-a "" (format nil " ~A" snapshot-a))
                  (if snap-b "" (format nil " ~A" snapshot-b)))))
      (let* ((tree-a (funcall tree-entries-fn snap-a))
             (tree-b (funcall tree-entries-fn snap-b))
             (diff (when (and tree-a tree-b) (funcall tree-diff-fn tree-a tree-b))))
        (if diff
            (let* ((added (count :added diff :key #'first))
                   (removed (count :removed diff :key #'first))
                   (modified (count :modified diff :key #'first))
                   (files (mapcar (lambda (change)
                                    (let ((entry (if (eq (first change) :modified)
                                                     (third change) (second change))))
                                      (list :path (funcall (find-symbol "ENTRY-PATH" snap-pkg)
                                                           entry)
                                            :type (string-downcase
                                                   (symbol-name (first change))))))
                                  diff)))
              (result-with-blocks
               (format nil "~D change~:P: +~D added, -~D removed, ~D modified."
                       (length diff) added removed modified)
               (list (make-block "diff-view"
                                 (list :added added :removed removed
                                       :modified modified :files files)
                                 :title (format nil "Diff: ~A vs ~A"
                                                (subseq snapshot-a 0 (min 8 (length snapshot-a)))
                                                (subseq snapshot-b 0 (min 8 (length snapshot-b))))))))
            "No filesystem differences found (or snapshots have no tree data).")))))

(autopoiesis.agent:defcapability sandbox-file-tree (&key sandbox-id)
  "Show the filesystem tree of an active sandbox.
   Returns a file tree visualization.

   Parameters:
     sandbox-id - The sandbox to inspect"
  :permissions (:file-read)
  :body
  (unless sandbox-id
    (return-from sandbox-file-tree "Error: sandbox-id is required."))
  ;; Use the sandbox REST API or manager
  (handler-case
      (let* ((api-pkg (find-package :autopoiesis.api))
             (manager (when api-pkg
                        (symbol-value (find-symbol "*API-SANDBOX-MANAGER*" api-pkg)))))
        (if manager
            (let* ((sandbox-pkg (find-package :autopoiesis.sandbox))
                   (backend (funcall (find-symbol "MANAGER-BACKEND" sandbox-pkg) manager))
                   (store (funcall (find-symbol "MANAGER-CONTENT-STORE" sandbox-pkg) manager))
                   (tree (funcall (find-symbol "BACKEND-SNAPSHOT" sandbox-pkg)
                                  backend sandbox-id store))
                   (snap-pkg (find-package :autopoiesis.snapshot))
                   (file-count (funcall (find-symbol "TREE-FILE-COUNT" snap-pkg) tree))
                   (total-size (funcall (find-symbol "TREE-TOTAL-SIZE" snap-pkg) tree))
                   (tree-hash (funcall (find-symbol "TREE-HASH" snap-pkg) tree)))
              (let ((entries (mapcar (lambda (e)
                                       (list :type (string-downcase
                                                    (symbol-name
                                                     (funcall (find-symbol "ENTRY-TYPE" snap-pkg) e)))
                                             :path (funcall (find-symbol "ENTRY-PATH" snap-pkg) e)
                                             :size (funcall (find-symbol "ENTRY-SIZE" snap-pkg) e)))
                                     tree)))
                (result-with-blocks
                 (format nil "Sandbox ~A: ~D files, ~A total."
                         sandbox-id file-count (format-bytes total-size))
                 (list (make-block "file-tree"
                                   (list :root (format nil "/sandbox/~A" sandbox-id)
                                         :entries entries
                                         :file_count file-count
                                         :total_size total-size
                                         :tree_hash tree-hash)
                                   :title sandbox-id)))))
            (format nil "No sandbox manager available.")))
    (error (e) (format nil "Error inspecting sandbox: ~A" e))))

(autopoiesis.agent:defcapability list-sandboxes ()
  "List all active sandboxes with their status.
   Returns sandbox status cards."
  :permissions (:file-read)
  :body
  (handler-case
      (let* ((api-pkg (find-package :autopoiesis.api))
             (manager (when api-pkg
                        (symbol-value (find-symbol "*API-SANDBOX-MANAGER*" api-pkg)))))
        (if manager
            (let* ((sandbox-pkg (find-package :autopoiesis.sandbox))
                   (sandboxes (funcall (find-symbol "MANAGER-LIST-SANDBOXES" sandbox-pkg)
                                       manager)))
              (if sandboxes
                  (result-with-blocks
                   (format nil "~D active sandbox~:P." (length sandboxes))
                   (mapcar (lambda (info)
                             (make-block "sandbox-status"
                                         (list :id (getf info :sandbox-id)
                                               :status (string-downcase
                                                        (symbol-name (getf info :status)))
                                               :snapshot_count (getf info :snapshot-count)
                                               :last_tree_hash (getf info :last-tree-hash))))
                           sandboxes))
                  "No active sandboxes."))
            "No sandbox manager available."))
    (error (e) (format nil "Error listing sandboxes: ~A" e))))

(autopoiesis.agent:defcapability rollback-sandbox (&key sandbox-id snapshot-id)
  "Restore a sandbox to a previous snapshot state.
   Returns the new sandbox status after rollback.

   Parameters:
     sandbox-id  - The sandbox to restore
     snapshot-id - The snapshot to restore to"
  :permissions (:file-write)
  :body
  (unless (and sandbox-id snapshot-id)
    (return-from rollback-sandbox
      "Error: Both sandbox-id and snapshot-id are required."))
  (handler-case
      (let* ((api-pkg (find-package :autopoiesis.api))
             (manager (when api-pkg
                        (symbol-value (find-symbol "*API-SANDBOX-MANAGER*" api-pkg)))))
        (if manager
            (let* ((sandbox-pkg (find-package :autopoiesis.sandbox))
                   (ops (funcall (find-symbol "MANAGER-RESTORE" sandbox-pkg)
                                 manager sandbox-id nil :incremental t))
                   (info (funcall (find-symbol "MANAGER-SANDBOX-INFO" sandbox-pkg)
                                  manager sandbox-id)))
              (result-with-blocks
               (format nil "Rolled back sandbox ~A (~D operations)." sandbox-id ops)
               (list (make-block "sandbox-status"
                                 (list :id sandbox-id
                                       :status (when info
                                                 (string-downcase
                                                  (symbol-name (getf info :status))))
                                       :snapshot_count (when info (getf info :snapshot-count)))
                                 :title "Rollback Complete"))))
            "No sandbox manager available."))
    (error (e) (format nil "Error during rollback: ~A" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Query Tools
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability query-events (&key event-type sandbox-id limit)
  "Search substrate events, optionally filtered by type or sandbox.
   Returns a timeline of matching events.

   Parameters:
     event-type - Filter by event type (optional)
     sandbox-id - Filter by sandbox (optional)
     limit - Max results (default 20)"
  :permissions (:file-read)
  :body
  (let ((max-results (or limit 20)))
    (handler-case
        (let ((events '()))
          ;; Query substrate for sandbox events
          (when (and (find-package :autopoiesis.substrate)
                     (boundp (find-symbol "*STORE*" :autopoiesis.substrate))
                     (symbol-value (find-symbol "*STORE*" :autopoiesis.substrate)))
            (let ((entities (funcall (find-symbol "FIND-ENTITIES" :autopoiesis.substrate)
                                     :sandbox-event/type
                                     (if event-type event-type t))))
              (dolist (eid (subseq entities 0 (min max-results (length entities))))
                (let ((state (funcall (find-symbol "ENTITY-STATE" :autopoiesis.substrate)
                                      eid)))
                  (push (list :id (princ-to-string eid)
                              :timestamp (or (getf state :sandbox-event/timestamp) 0)
                              :type (string-downcase
                                     (princ-to-string
                                      (or (getf state :sandbox-event/type) "event")))
                              :sandbox_id (getf state :sandbox-event/sandbox-id)
                              :details (let ((data (getf state :sandbox-event/data)))
                                         (when data (format nil "~A" data))))
                        events)))))
          (if events
              (result-with-blocks
               (format nil "Found ~D event~:P." (length events))
               (list (make-block "timeline-slice"
                                 (list :entries (nreverse events))
                                 :title "Sandbox Events")))
              "No matching events found."))
      (error (e) (format nil "Error querying events: ~A" e)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun format-bytes (bytes)
  "Format byte count as human-readable string."
  (cond
    ((null bytes) "0B")
    ((< bytes 1024) (format nil "~DB" bytes))
    ((< bytes (* 1024 1024)) (format nil "~,1FKB" (/ bytes 1024.0)))
    (t (format nil "~,1FMB" (/ bytes (* 1024.0 1024.0))))))
