;;;; serializers.lisp - JSON serialization for API objects
;;;;
;;;; Converts Lisp objects to JSON-friendly plists that jzon can encode.
;;;; These are the canonical wire representations for all objects sent
;;;; to connected frontends.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun agent-to-json-plist (agent)
  "Convert an agent to a JSON-serializable plist."
  (let ((stream (agent-thought-stream agent)))
    (list "id" (agent-id agent)
          "name" (agent-name agent)
          "state" (string-downcase (symbol-name (agent-state agent)))
          "capabilities" (mapcar (lambda (c)
                                   (string-downcase (symbol-name c)))
                                 (agent-capabilities agent))
          "parent" (agent-parent agent)
          "children" (agent-children agent)
          "thoughtCount" (stream-length stream))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun thought-to-json-plist (thought)
  "Convert a thought to a JSON-serializable plist."
  (let ((base (list "id" (thought-id thought)
                    "timestamp" (thought-timestamp thought)
                    "type" (string-downcase (symbol-name (thought-type thought)))
                    "confidence" (thought-confidence thought)
                    "content" (format nil "~S" (thought-content thought))
                    "provenance" (when (thought-provenance thought)
                                   (format nil "~S" (thought-provenance thought))))))
    ;; Add subclass-specific fields
    (typecase thought
      (decision
       (nconc base
              (list "alternatives" (mapcar (lambda (alt)
                                            (list "option" (format nil "~S" (car alt))
                                                  "score" (cdr alt)))
                                          (decision-alternatives thought))
                    "chosen" (format nil "~S" (decision-chosen thought))
                    "rationale" (decision-rationale thought))))
      (action
       (nconc base
              (list "capability" (when (action-capability thought)
                                   (string-downcase
                                    (symbol-name (action-capability thought))))
                    "result" (format nil "~S" (action-result thought)))))
      (observation
       (nconc base
              (list "source" (when (observation-source thought)
                               (string-downcase
                                (symbol-name (observation-source thought))))
                    "raw" (format nil "~S" (observation-raw thought)))))
      (reflection
       (nconc base
              (list "target" (when (reflection-target thought)
                               (format nil "~S" (reflection-target thought)))
                    "insight" (when (reflection-insight thought)
                                (format nil "~S" (reflection-insight thought)))))))
    base))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-to-json-plist (snapshot)
  "Convert a snapshot to a JSON-serializable plist."
  (list "id" (snapshot-id snapshot)
        "timestamp" (snapshot-timestamp snapshot)
        "parent" (snapshot-parent snapshot)
        "hash" (snapshot-hash snapshot)
        "metadata" (when (snapshot-metadata snapshot)
                     (format nil "~S" (snapshot-metadata snapshot)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun branch-to-json-plist (branch)
  "Convert a branch to a JSON-serializable plist."
  (list "name" (branch-name branch)
        "head" (branch-head branch)
        "created" (branch-created branch)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun event-to-json-plist (event)
  "Convert an integration event to a JSON-serializable plist."
  (list "id" (integration-event-id event)
        "type" (string-downcase (symbol-name (integration-event-kind event)))
        "source" (format nil "~A" (integration-event-source event))
        "agentId" (integration-event-agent-id event)
        "data" (format-event-data (integration-event-data event))
        "timestamp" (integration-event-timestamp event)))

(defun format-event-data (data)
  "Convert event data plist to a JSON-friendly alist."
  (when data
    (loop for (key val) on data by #'cddr
          collect (list (string-downcase (symbol-name key))
                        (format nil "~A" val)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Request Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun blocking-request-to-json-plist (request)
  "Convert a blocking request to a JSON-serializable plist."
  (list "id" (blocking-request-id request)
        "prompt" (blocking-request-prompt request)
        "context" (blocking-request-context request)
        "options" (blocking-request-options request)
        "default" (blocking-request-default request)
        "status" (string-downcase (symbol-name (blocking-request-status request)))
        "createdAt" (blocking-request-created request)))
