;;;; holodeck-sync.lisp - Sync agent registry to holodeck entity stream
;;;;
;;;; Generates holodeck_frame messages from the agent registry so the
;;;; 3D holodeck view shows real agents. Runs as a periodic broadcast
;;;; thread that pushes entity data to holodeck subscribers.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Agent -> Holodeck Entity Conversion
;;; ===================================================================

(defun agent-to-holodeck-entity (agent index)
  "Convert an agent to a holodeck entity data hash-table.
   INDEX controls spatial positioning."
  (let* ((state (agent-state agent))
         (running-p (eq state :running))
         (paused-p (eq state :paused))
         ;; Position agents in a circle
         (angle (* index (/ (* 2 pi) (max 1 (length (list-agents))))))
         (radius 8.0)
         (x (* radius (cos angle)))
         (z (* radius (sin angle)))
         (y (if running-p 2.0 0.5)))
    (json-object
     "id" index
     "kind" "agent"
     "position" (vector x y z)
     "scale" (if running-p
                 (vector 1.5 1.5 1.5)
                 (vector 1.0 1.0 1.0))
     "rotation" (vector 0.0 (- angle) 0.0)
     "color" (cond
               (running-p (vector 0.2 0.8 0.4 1.0))   ; green
               (paused-p  (vector 0.9 0.7 0.1 1.0))   ; yellow
               (t         (vector 0.4 0.4 0.5 0.6)))   ; gray
     "glow" running-p
     "glowIntensity" (if running-p 0.8 0.0)
     "label" (agent-name agent)
     "labelOffset" 2.0
     "meshType" "sphere"
     "lod" "high"
     "agentId" (agent-id agent)
     "cognitivePhase" (string-downcase (symbol-name state))
     "selected" :false
     "hovered" :false)))

(defun agents-to-holodeck-frame ()
  "Generate a complete holodeck_frame from the agent registry."
  (let* ((agents (list-agents))
         (entities (loop for agent in agents
                         for i from 1
                         collect (agent-to-holodeck-entity agent i)))
         ;; Generate connections between parent-child agents
         (connections (loop for agent in agents
                           for i from 1
                           when (agent-parent agent)
                           collect (let* ((parent (find-agent (agent-parent agent)))
                                         (parent-idx (when parent
                                                       (1+ (position parent agents)))))
                                    (when parent-idx
                                      (json-object
                                       "id" (+ 1000 i)
                                       "kind" "lineage"
                                       "from" (vector 0.0 1.0 0.0)
                                       "to" (vector 0.0 1.0 0.0)
                                       "color" (vector 0.3 0.6 0.9 0.5)
                                       "energyFlow" 0.5)))))
         (frame (json-object
                 "type" "holodeck_frame"
                 "dt" 0.016
                 "camera" (json-object
                           "position" (vector 0.0 10.0 15.0)
                           "view" (vector 1 0 0 0  0 1 0 0  0 0 1 0  0 -10 -15 1)
                           "projection" (vector 1 0 0 0  0 1 0 0  0 0 -1 -1  0 0 -1 0))
                 "entities" (or entities #())
                 "connections" (remove nil (or connections #()))
                 "hud" (json-object
                        "visible" t
                        "panels" #()))))
    frame))

;;; ===================================================================
;;; Holodeck Sync Handler — Push on Request
;;; ===================================================================

(define-handler handle-holodeck-entities "holodeck_entities" (msg conn)
  "Push current agent entities as a holodeck frame to the requesting connection."
  (declare (ignore msg))
  (let ((frame (agents-to-holodeck-frame)))
    (send-to-connection conn (encode-message frame))
    (ok-response "holodeck_entities_sent"
                 "entityCount" (length (list-agents)))))

;;; ===================================================================
;;; Periodic Holodeck Broadcast
;;; ===================================================================

(defvar *holodeck-sync-thread* nil
  "Background thread that periodically pushes holodeck frames.")

(defvar *holodeck-sync-running* nil
  "Flag to control holodeck sync thread lifecycle.")

(defun start-holodeck-sync (&key (interval 2))
  "Start periodic holodeck entity sync. Pushes agent state as holodeck frames
   every INTERVAL seconds to all holodeck subscribers."
  (when *holodeck-sync-thread*
    (return-from start-holodeck-sync nil))
  (setf *holodeck-sync-running* t)
  (setf *holodeck-sync-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while *holodeck-sync-running*
                 do (handler-case
                        (when (> (length (list-agents)) 0)
                          (let ((frame (agents-to-holodeck-frame)))
                            (broadcast-stream-data frame
                                                   :subscription-type "holodeck")))
                      (error (e)
                        (log:error "Holodeck sync error: ~a" e)))
                    (sleep interval))
           (log:info "Holodeck sync thread stopped"))
         :name "holodeck-sync")))

(defun stop-holodeck-sync ()
  "Stop the periodic holodeck sync thread."
  (setf *holodeck-sync-running* nil)
  (when *holodeck-sync-thread*
    (ignore-errors
      (bordeaux-threads:join-thread *holodeck-sync-thread*
                                    :timeout 5))
    (setf *holodeck-sync-thread* nil)))
