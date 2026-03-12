;;;; team-handlers.lisp - WebSocket handlers for team management
;;;;
;;;; Provides WS message handlers for team CRUD, member management,
;;;; and lifecycle operations via the define-handler macro.
;;;; Uses find-package/find-symbol pattern since the team package
;;;; (autopoiesis.team) is an optional extension that may not be loaded.
;;;;
;;;; REST endpoints for teams live in routes.lisp (base system).
;;;; This file is loaded only by the autopoiesis/api (WebSocket) system.
;;;; The helper functions (%team-package-loaded-p, %call-team, etc.)
;;;; and team-to-json-alist are defined in routes.lisp and available
;;;; because autopoiesis/api depends on autopoiesis (which loads routes.lisp).

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Team Serialization (WS format - string-keyed plists for jzon)
;;; ===================================================================

(defun team-to-json-plist (team)
  "Convert a team object to a JSON-friendly plist (string keys for WS/jzon)."
  (list "id" (%team-slot team "TEAM-ID")
        "status" (string-downcase
                  (symbol-name (%team-slot team "TEAM-STATUS")))
        "task" (or (%team-slot team "TEAM-TASK") 'null)
        "leader" (or (%team-slot team "TEAM-LEADER") 'null)
        "members" (or (%team-slot team "TEAM-MEMBERS") #())
        "memberCount" (length (or (%team-slot team "TEAM-MEMBERS") nil))
        "workspaceId" (or (%team-slot team "TEAM-WORKSPACE-ID") 'null)
        "strategy" (let ((strat (%team-slot team "TEAM-STRATEGY")))
                     (if strat
                         (string-downcase (symbol-name (type-of strat)))
                         'null))
        "config" (or (%team-slot team "TEAM-CONFIG") 'null)
        "createdAt" (%team-slot team "TEAM-CREATED-AT")))

;;; ===================================================================
;;; Team Not Loaded Error Helper
;;; ===================================================================

(defun team-not-loaded-ws-error ()
  "Return a WS error response indicating the team extension is not loaded."
  (error-response "not_available"
                  "Team extension (autopoiesis/team) is not loaded"))

;;; ===================================================================
;;; WebSocket Handlers
;;; ===================================================================

(define-handler handle-ws-list-teams "list_teams" (msg conn)
  (declare (ignore msg conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-list-teams (team-not-loaded-ws-error)))
  (let ((teams (%call-team "LIST-TEAMS")))
    (ok-response "teams"
                 "teams" (mapcar #'team-to-json-plist teams))))

(define-handler handle-ws-create-team "create_team" (msg conn)
  (declare (ignore conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-create-team (team-not-loaded-ws-error)))
  (let* ((name (gethash "name" msg))
         (strategy-str (gethash "strategy" msg))
         (members (gethash "members" msg))
         (leader (gethash "leader" msg))
         (task (gethash "task" msg)))
    (unless name
      (return-from handle-ws-create-team
        (error-response "missing_field" "create_team requires 'name'")))
    (let ((strategy-kw (when strategy-str
                         (string-to-strategy-keyword strategy-str))))
      (handler-case
          (let ((team (%call-team "CREATE-TEAM" name
                                  :strategy strategy-kw
                                  :members (or members nil)
                                  :leader leader
                                  :task task)))
            ;; Broadcast to teams subscribers
            (broadcast-stream-data (ok-response "team_created"
                                                "team" (team-to-json-plist team))
                                   :subscription-type "teams")
            (ok-response "team_created"
                         "team" (team-to-json-plist team)))
        (error (e)
          (error-response "create_failed"
                          (format nil "Failed to create team: ~A" e)))))))

(define-handler handle-ws-start-team "start_team" (msg conn)
  (declare (ignore conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-start-team (team-not-loaded-ws-error)))
  (let ((team-id (gethash "teamId" msg)))
    (unless team-id
      (return-from handle-ws-start-team
        (error-response "missing_field" "start_team requires 'teamId'")))
    (let ((team (%call-team "FIND-TEAM" team-id)))
      (unless team
        (return-from handle-ws-start-team
          (error-response "not_found"
                          (format nil "Team not found: ~A" team-id))))
      (handler-case
          (progn
            (%call-team "START-TEAM" team)
            (broadcast-stream-data (ok-response "team_started"
                                                "teamId" team-id)
                                   :subscription-type "teams")
            (ok-response "team_started"
                         "team" (team-to-json-plist team)))
        (error (e)
          (error-response "start_failed"
                          (format nil "Failed to start team: ~A" e)))))))

(define-handler handle-ws-disband-team "disband_team" (msg conn)
  (declare (ignore conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-disband-team (team-not-loaded-ws-error)))
  (let ((team-id (gethash "teamId" msg)))
    (unless team-id
      (return-from handle-ws-disband-team
        (error-response "missing_field" "disband_team requires 'teamId'")))
    (let ((team (%call-team "FIND-TEAM" team-id)))
      (unless team
        (return-from handle-ws-disband-team
          (error-response "not_found"
                          (format nil "Team not found: ~A" team-id))))
      (handler-case
          (progn
            (%call-team "DISBAND-TEAM" team)
            (broadcast-stream-data (ok-response "team_disbanded"
                                                "teamId" team-id)
                                   :subscription-type "teams")
            (ok-response "team_disbanded"
                         "teamId" team-id))
        (error (e)
          (error-response "disband_failed"
                          (format nil "Failed to disband team: ~A" e)))))))

(define-handler handle-ws-query-team "query_team" (msg conn)
  (declare (ignore conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-query-team (team-not-loaded-ws-error)))
  (let ((team-id (gethash "teamId" msg)))
    (unless team-id
      (return-from handle-ws-query-team
        (error-response "missing_field" "query_team requires 'teamId'")))
    (let ((team (%call-team "FIND-TEAM" team-id)))
      (unless team
        (return-from handle-ws-query-team
          (error-response "not_found"
                          (format nil "Team not found: ~A" team-id))))
      (let ((status (%call-team "QUERY-TEAM-STATUS" team)))
        (ok-response "team_detail"
                     "team" (team-to-json-plist team)
                     "status" (loop for (k v) on status by #'cddr
                                    collect (string-downcase (symbol-name k))
                                    collect (typecase v
                                              (symbol (string-downcase
                                                       (symbol-name v)))
                                              (t v))))))))

(define-handler handle-ws-add-team-member "add_team_member" (msg conn)
  (declare (ignore conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-add-team-member (team-not-loaded-ws-error)))
  (let ((team-id (gethash "teamId" msg))
        (agent-name (gethash "agentName" msg)))
    (unless team-id
      (return-from handle-ws-add-team-member
        (error-response "missing_field" "add_team_member requires 'teamId'")))
    (unless agent-name
      (return-from handle-ws-add-team-member
        (error-response "missing_field" "add_team_member requires 'agentName'")))
    (let ((team (%call-team "FIND-TEAM" team-id)))
      (unless team
        (return-from handle-ws-add-team-member
          (error-response "not_found"
                          (format nil "Team not found: ~A" team-id))))
      (%call-team "ADD-TEAM-MEMBER" team agent-name)
      (broadcast-stream-data (ok-response "team_member_added"
                                          "teamId" team-id
                                          "agentName" agent-name)
                             :subscription-type "teams")
      (ok-response "team_member_added"
                   "teamId" team-id
                   "agentName" agent-name
                   "team" (team-to-json-plist team)))))

(define-handler handle-ws-remove-team-member "remove_team_member" (msg conn)
  (declare (ignore conn))
  (unless (%team-package-loaded-p)
    (return-from handle-ws-remove-team-member (team-not-loaded-ws-error)))
  (let ((team-id (gethash "teamId" msg))
        (agent-name (gethash "agentName" msg)))
    (unless team-id
      (return-from handle-ws-remove-team-member
        (error-response "missing_field" "remove_team_member requires 'teamId'")))
    (unless agent-name
      (return-from handle-ws-remove-team-member
        (error-response "missing_field" "remove_team_member requires 'agentName'")))
    (let ((team (%call-team "FIND-TEAM" team-id)))
      (unless team
        (return-from handle-ws-remove-team-member
          (error-response "not_found"
                          (format nil "Team not found: ~A" team-id))))
      (%call-team "REMOVE-TEAM-MEMBER" team agent-name)
      (broadcast-stream-data (ok-response "team_member_removed"
                                          "teamId" team-id
                                          "agentName" agent-name)
                             :subscription-type "teams")
      (ok-response "team_member_removed"
                   "teamId" team-id
                   "agentName" agent-name
                   "team" (team-to-json-plist team)))))
