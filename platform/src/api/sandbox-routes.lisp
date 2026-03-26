;;;; sandbox-routes.lisp - REST API endpoints for sandbox operations
;;;;
;;;; Provides HTTP endpoints for the content-addressed sandbox:
;;;; - POST   /api/sandboxes                    - create sandbox
;;;; - GET    /api/sandboxes                    - list sandboxes
;;;; - GET    /api/sandboxes/:id                - get sandbox info
;;;; - DELETE /api/sandboxes/:id                - destroy sandbox
;;;; - POST   /api/sandboxes/:id/exec           - execute command
;;;; - POST   /api/sandboxes/:id/snapshot        - create snapshot
;;;; - POST   /api/sandboxes/:id/fork            - fork sandbox
;;;; - POST   /api/sandboxes/:id/restore/:snap   - restore to snapshot
;;;; - GET    /api/sandboxes/:id/tree            - current filesystem tree
;;;;
;;;; Uses dynamic resolution for autopoiesis.sandbox so this compiles
;;;; without autopoiesis/sandbox-backends loaded.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Dynamic Resolution
;;; ═══════════════════════════════════════════════════════════════════

(defun %sbx (fn-name &rest args)
  "Call a function from autopoiesis.sandbox dynamically."
  (let* ((pkg (find-package :autopoiesis.sandbox))
         (fn (when pkg (find-symbol fn-name pkg))))
    (if (and fn (fboundp fn))
        (apply fn args)
        (error "Sandbox function ~A not available." fn-name))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Manager Reference
;;; ═══════════════════════════════════════════════════════════════════

(defvar *api-sandbox-manager* nil
  "The sandbox manager used by API endpoints.
   Set via (setf *api-sandbox-manager* (make-sandbox-manager backend)).")

;;; ═══════════════════════════════════════════════════════════════════
;;; Route Dispatcher
;;; ═══════════════════════════════════════════════════════════════════

(defun rest-handle-sandboxes (request)
  "Dispatch /api/sandboxes requests."
  (unless *api-sandbox-manager*
    (return-from rest-handle-sandboxes
      (json-error "Sandbox manager not initialized" :status 503)))
  (let ((method (hunchentoot:request-method request))
        (sandbox-id (extract-path-segment request "/api/sandboxes/")))
    (cond
      ;; GET /api/sandboxes - list all
      ((and (eq method :get) (null sandbox-id))
       (rest-list-sandboxes))
      ;; POST /api/sandboxes - create
      ((and (eq method :post) (null sandbox-id))
       (rest-create-sandbox))
      ;; GET /api/sandboxes/:id - info
      ((and (eq method :get) sandbox-id)
       (let ((sub-path (path-after-segment request "/api/sandboxes/" sandbox-id)))
         (cond
           ((or (null sub-path) (string= sub-path ""))
            (rest-get-sandbox sandbox-id))
           ((string= sub-path "/tree")
            (rest-sandbox-tree sandbox-id))
           (t (json-not-found "Sandbox route" sub-path)))))
      ;; DELETE /api/sandboxes/:id - destroy
      ((and (eq method :delete) sandbox-id)
       (rest-destroy-sandbox sandbox-id))
      ;; POST /api/sandboxes/:id/... - operations
      ((and (eq method :post) sandbox-id)
       (let ((sub-path (path-after-segment request "/api/sandboxes/" sandbox-id)))
         (cond
           ((string= sub-path "/exec")
            (rest-sandbox-exec sandbox-id))
           ((string= sub-path "/snapshot")
            (rest-sandbox-snapshot sandbox-id))
           ((string= sub-path "/fork")
            (rest-sandbox-fork sandbox-id))
           ((and sub-path (> (length sub-path) 9)
                 (string= "/restore/" (subseq sub-path 0 9)))
            (rest-sandbox-restore sandbox-id (subseq sub-path 9)))
           (t (json-not-found "Sandbox operation" sub-path)))))
      (t (json-error "Method not allowed" :status 405)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Endpoint Implementations
;;; ═══════════════════════════════════════════════════════════════════

(defun rest-list-sandboxes ()
  "GET /api/sandboxes - List all active sandboxes."
  (let ((sandboxes (%sbx "MANAGER-LIST-SANDBOXES" *api-sandbox-manager*)))
    (json-ok (mapcar #'sandbox-info-to-json sandboxes))))

(defun rest-create-sandbox ()
  "POST /api/sandboxes - Create a new sandbox."
  (let* ((body (parse-json-body))
         (sandbox-id (or (cdr (assoc :id body))
                         (format nil "sb-~A" (autopoiesis.core:make-uuid))))
         (config (list :memory-mb (cdr (assoc :memory--mb body))
                       :image (cdr (assoc :image body)))))
    (%sbx "MANAGER-CREATE-SANDBOX" *api-sandbox-manager* sandbox-id :config config)
    (json-ok `((:id . ,sandbox-id)
               (:status . "ready")
               (:created . t)))))

(defun rest-get-sandbox (sandbox-id)
  "GET /api/sandboxes/:id - Get sandbox info."
  (let ((info (%sbx "MANAGER-SANDBOX-INFO" *api-sandbox-manager* sandbox-id)))
    (if info
        (json-ok (sandbox-info-to-json info))
        (json-not-found "Sandbox" sandbox-id))))

(defun rest-destroy-sandbox (sandbox-id)
  "DELETE /api/sandboxes/:id - Destroy a sandbox."
  (%sbx "MANAGER-DESTROY-SANDBOX" *api-sandbox-manager* sandbox-id)
  (json-ok `((:id . ,sandbox-id) (:destroyed . t))))

(defun rest-sandbox-exec (sandbox-id)
  "POST /api/sandboxes/:id/exec - Execute a command."
  (let* ((body (parse-json-body))
         (command (cdr (assoc :command body)))
         (timeout (or (cdr (assoc :timeout body)) 300))
         (workdir (cdr (assoc :workdir body))))
    (unless command
      (return-from rest-sandbox-exec
        (json-error "Missing 'command' field")))
    (let ((result (%sbx "MANAGER-EXEC" *api-sandbox-manager* sandbox-id command
                        :timeout timeout :workdir workdir)))
      (json-ok `((:exit--code . ,(%sbx "EXEC-RESULT-EXIT-CODE" result))
                 (:stdout . ,(%sbx "EXEC-RESULT-STDOUT" result))
                 (:stderr . ,(%sbx "EXEC-RESULT-STDERR" result))
                 (:duration--ms . ,(%sbx "EXEC-RESULT-DURATION-MS" result)))))))

(defun rest-sandbox-snapshot (sandbox-id)
  "POST /api/sandboxes/:id/snapshot - Create a snapshot."
  (let* ((body (parse-json-body))
         (label (cdr (assoc :label body)))
         (snapshot (%sbx "MANAGER-SNAPSHOT" *api-sandbox-manager* sandbox-id
                         :label label)))
    (json-ok `((:snapshot--id . ,(autopoiesis.snapshot:snapshot-id snapshot))
               (:tree--hash . ,(autopoiesis.snapshot:snapshot-tree-root snapshot))
               (:file--count . ,(when (autopoiesis.snapshot:snapshot-tree-entries snapshot)
                                  (autopoiesis.snapshot:tree-file-count
                                   (autopoiesis.snapshot:snapshot-tree-entries snapshot))))
               (:label . ,label)))))

(defun rest-sandbox-fork (sandbox-id)
  "POST /api/sandboxes/:id/fork - Fork a sandbox."
  (let* ((body (parse-json-body))
         (new-id (or (cdr (assoc :new--id body))
                     (format nil "fork-~A" (autopoiesis.core:make-uuid))))
         (label (cdr (assoc :label body)))
         (result (%sbx "MANAGER-FORK" *api-sandbox-manager* sandbox-id new-id
                        :label label)))
    (json-ok `((:source--id . ,sandbox-id)
               (:new--id . ,result)
               (:label . ,label)))))

(defun rest-sandbox-restore (sandbox-id snapshot-ref)
  "POST /api/sandboxes/:id/restore/:snapshot - Restore to snapshot."
  (handler-case
      (let* ((snapshot (autopoiesis.snapshot:load-snapshot snapshot-ref))
             (ops (%sbx "MANAGER-RESTORE" *api-sandbox-manager* sandbox-id
                        snapshot :incremental t)))
        (json-ok `((:sandbox--id . ,sandbox-id)
                   (:snapshot--ref . ,snapshot-ref)
                   (:operations . ,ops))))
    (error (e)
      (json-error (format nil "Failed to restore snapshot ~A: ~A"
                          snapshot-ref e)))))

(defun rest-sandbox-tree (sandbox-id)
  "GET /api/sandboxes/:id/tree - Get current filesystem tree."
  (let* ((backend (%sbx "MANAGER-BACKEND" *api-sandbox-manager*))
         (store (%sbx "MANAGER-CONTENT-STORE" *api-sandbox-manager*))
         (tree (%sbx "BACKEND-SNAPSHOT" backend sandbox-id store)))
    (json-ok `((:sandbox--id . ,sandbox-id)
               (:file--count . ,(autopoiesis.snapshot:tree-file-count tree))
               (:total--size . ,(autopoiesis.snapshot:tree-total-size tree))
               (:tree--hash . ,(autopoiesis.snapshot:tree-hash tree))
               (:entries . ,(mapcar #'tree-entry-to-json tree))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; JSON Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun sandbox-info-to-json (info)
  "Convert a sandbox info plist to JSON-friendly alist."
  `((:id . ,(getf info :sandbox-id))
    (:branch . ,(getf info :branch-name))
    (:status . ,(string-downcase (symbol-name (getf info :status))))
    (:created--at . ,(getf info :created-at))
    (:snapshot--count . ,(getf info :snapshot-count))
    (:last--snapshot--id . ,(getf info :last-snapshot-id))
    (:last--tree--hash . ,(getf info :last-tree-hash))))

(defun tree-entry-to-json (entry)
  "Convert a tree entry to JSON-friendly alist."
  (let ((type (autopoiesis.snapshot:entry-type entry)))
    `((:type . ,(string-downcase (symbol-name type)))
      (:path . ,(autopoiesis.snapshot:entry-path entry))
      ,@(when (eq type :file)
          `((:hash . ,(autopoiesis.snapshot:entry-hash entry))
            (:size . ,(autopoiesis.snapshot:entry-size entry))
            (:mode . ,(autopoiesis.snapshot:entry-mode entry))))
      ,@(when (eq type :symlink)
          `((:target . ,(autopoiesis.snapshot:entry-target entry)))))))
