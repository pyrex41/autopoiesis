;;;; serializers.lisp - JSON serialization for API objects
;;;;
;;;; Converts Lisp objects to hash-tables that jzon encodes as JSON objects.
;;;; These are the canonical wire representations for all objects sent
;;;; to connected frontends.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Hash-table Builder
;;; ═══════════════════════════════════════════════════════════════════

(defun json-object (&rest pairs)
  "Build a string-keyed hash-table from alternating key-value PAIRS.
   Keys must be strings. jzon encodes hash-tables as JSON objects."
  (let ((ht (make-hash-table :test 'equal :size (ceiling (length pairs) 2))))
    (loop for (key val) on pairs by #'cddr
          do (setf (gethash key ht) val))
    ht))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun agent-to-json-plist (agent)
  "Convert an agent to a JSON-serializable hash-table."
  (let* ((tstream (agent-thought-stream agent))
         (ht (json-object "id" (agent-id agent)
                          "name" (agent-name agent)
                          "state" (string-downcase (symbol-name (agent-state agent)))
                          "capabilities" (or (mapcar (lambda (c)
                                                      (string-downcase (symbol-name c)))
                                                    (agent-capabilities agent))
                                            #())
                          "parent" (or (agent-parent agent) 'null)
                          "children" (or (agent-children agent) #())
                          "thoughtCount" (stream-length tstream))))
    ;; Add persistent agent fields if applicable
    (when (typep agent 'autopoiesis.agent:dual-agent)
      (let ((root (autopoiesis.agent:dual-agent-root agent)))
        (when root
          (setf (gethash "persistent" ht) t
                (gethash "version" ht) (autopoiesis.agent:persistent-agent-version root)
                (gethash "lineageHash" ht) (autopoiesis.agent:persistent-agent-hash root)
                (gethash "parentRoot" ht) (or (autopoiesis.agent:persistent-agent-parent-root root) 'null)
                (gethash "children" ht) (or (autopoiesis.agent:persistent-agent-children root) #())))))
    ht))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun thought-to-json-plist (thought)
  "Convert a thought to a JSON-serializable hash-table."
  (let ((ht (json-object "id" (thought-id thought)
                         "timestamp" (thought-timestamp thought)
                         "type" (string-downcase (symbol-name (thought-type thought)))
                         "confidence" (thought-confidence thought)
                         "content" (format nil "~S" (thought-content thought))
                         "provenance" (when (thought-provenance thought)
                                       (format nil "~S" (thought-provenance thought))))))
    ;; Add subclass-specific fields
    (typecase thought
      (decision
       (setf (gethash "alternatives" ht) (mapcar (lambda (alt)
                                                   (json-object "option" (format nil "~S" (car alt))
                                                                "score" (cdr alt)))
                                                 (decision-alternatives thought))
             (gethash "chosen" ht) (format nil "~S" (decision-chosen thought))
             (gethash "rationale" ht) (decision-rationale thought)))
      (action
       (setf (gethash "capability" ht) (when (action-capability thought)
                                         (string-downcase
                                          (symbol-name (action-capability thought))))
             (gethash "result" ht) (format nil "~S" (action-result thought))))
      (observation
       (setf (gethash "source" ht) (when (observation-source thought)
                                     (string-downcase
                                      (symbol-name (observation-source thought))))
             (gethash "raw" ht) (format nil "~S" (observation-raw thought))))
      (reflection
       (setf (gethash "target" ht) (when (reflection-target thought)
                                     (format nil "~S" (reflection-target thought)))
             (gethash "insight" ht) (when (reflection-insight thought)
                                     (format nil "~S" (reflection-insight thought))))))
    ht))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-to-json-plist (snapshot)
  "Convert a snapshot to a JSON-serializable hash-table."
  (json-object "id" (snapshot-id snapshot)
               "timestamp" (snapshot-timestamp snapshot)
               "parent" (snapshot-parent snapshot)
               "hash" (snapshot-hash snapshot)
               "metadata" (when (snapshot-metadata snapshot)
                            (format nil "~S" (snapshot-metadata snapshot)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun branch-to-json-plist (branch)
  "Convert a branch to a JSON-serializable hash-table."
  (json-object "name" (branch-name branch)
               "head" (branch-head branch)
               "created" (branch-created branch)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun event-to-json-plist (event)
  "Convert an integration event to a JSON-serializable hash-table."
  (json-object "id" (integration-event-id event)
               "type" (string-downcase (symbol-name (integration-event-kind event)))
               "source" (format nil "~A" (integration-event-source event))
               "agentId" (integration-event-agent-id event)
               "data" (format-event-data (integration-event-data event))
               "timestamp" (integration-event-timestamp event)))

(defun format-event-data (data)
  "Convert event data keyword plist to a string-keyed hash-table for JSON encoding."
  (when data
    (let ((ht (make-hash-table :test 'equal :size (ceiling (length data) 2))))
      (loop for (key val) on data by #'cddr
            do (setf (gethash (string-downcase (symbol-name key)) ht)
                     (format nil "~A" val)))
      ht)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Request Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun blocking-request-to-json-plist (request)
  "Convert a blocking request to a JSON-serializable hash-table."
  (json-object "id" (blocking-request-id request)
               "prompt" (blocking-request-prompt request)
               "context" (blocking-request-context request)
               "options" (blocking-request-options request)
               "default" (blocking-request-default request)
               "status" (string-downcase (symbol-name (blocking-request-status request)))
               "createdAt" (blocking-request-created request)))
