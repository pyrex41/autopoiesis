;;; sly-autopoiesis.el --- SLY contrib for Autopoiesis agent platform -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Autopoiesis Contributors
;; Package-Requires: ((emacs "28.1") (sly "1.0"))
;; Version: 0.2.0

;;; Commentary:

;; SLY contrib exposing the full Autopoiesis platform through Emacs.
;; Connects to a running SBCL image via Slynk for zero-overhead
;; in-image RPC.
;;
;; Features:
;;   - System lifecycle (start/stop platform and conductor)
;;   - Agent list, detail, creation, state management
;;   - Provider-aware chat shell (Jarvis sessions with rho/pi/claude/etc.)
;;   - Conductor dashboard with metrics
;;   - Agentic loop creation and prompting
;;   - Team creation, monitoring, and coordination
;;   - Swarm evolution launcher
;;   - Integration event log
;;
;; All keybindings under C-c x prefix:
;;   C-c x ?  Help (list all commands)
;;   C-c x s  System status buffer
;;   C-c x S  Start platform
;;   C-c x Q  Stop platform
;;   C-c x a  List agents
;;   C-c x A  Create agent
;;   C-c x c  Chat (provider-aware, C-u for provider selection)
;;   C-c x d  Conductor dashboard
;;   C-c x t  List teams
;;   C-c x T  Create team
;;   C-c x g  Agentic agent prompt
;;   C-c x e  Event log
;;   C-c x w  Swarm evolution

;;; Code:

(require 'sly)
(require 'comint)
(require 'cl-lib)

;;;; ────────────────────────────────────────────────────────────────────
;;;; SLY Contrib Registration
;;;; ────────────────────────────────────────────────────────────────────

(define-sly-contrib sly-autopoiesis
  "Autopoiesis agent platform integration"
  (:slynk-dependencies slynk-autopoiesis)
  (:on-load (sly-autopoiesis-mode 1)))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Minor Mode
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Help
    (define-key map (kbd "C-c x ?") #'sly-autopoiesis-help)
    ;; System
    (define-key map (kbd "C-c x s") #'sly-autopoiesis-system-status)
    (define-key map (kbd "C-c x S") #'sly-autopoiesis-start-system)
    (define-key map (kbd "C-c x Q") #'sly-autopoiesis-stop-system)
    ;; Agents
    (define-key map (kbd "C-c x a") #'sly-autopoiesis-list-agents)
    (define-key map (kbd "C-c x A") #'sly-autopoiesis-create-agent)
    ;; Chat
    (define-key map (kbd "C-c x c") #'sly-autopoiesis-chat)
    ;; Conductor
    (define-key map (kbd "C-c x d") #'sly-autopoiesis-conductor-dashboard)
    ;; Teams
    (define-key map (kbd "C-c x t") #'sly-autopoiesis-list-teams)
    (define-key map (kbd "C-c x T") #'sly-autopoiesis-create-team)
    ;; Agentic
    (define-key map (kbd "C-c x g") #'sly-autopoiesis-agentic-prompt)
    ;; Events
    (define-key map (kbd "C-c x e") #'sly-autopoiesis-events)
    ;; Swarm
    (define-key map (kbd "C-c x w") #'sly-autopoiesis-evolve)
    map)
  "Keymap for `sly-autopoiesis-mode'.")

;;;###autoload
(define-minor-mode sly-autopoiesis-mode
  "Minor mode for Autopoiesis agent platform integration via SLY."
  :lighter " AP"
  :keymap sly-autopoiesis-mode-map
  :global t)

;;;; ────────────────────────────────────────────────────────────────────
;;;; Help
;;;; ────────────────────────────────────────────────────────────────────

;;;###autoload
(defun sly-autopoiesis-help ()
  "Show Autopoiesis keybinding help."
  (interactive)
  (with-help-window "*autopoiesis-help*"
    (princ "Autopoiesis — SLY Platform Integration\n")
    (princ "═══════════════════════════════════════\n\n")
    (princ "System\n")
    (princ "  C-c x s   System status buffer\n")
    (princ "  C-c x S   Start platform (substrate + conductor + monitoring)\n")
    (princ "  C-c x Q   Stop platform\n\n")
    (princ "Agents\n")
    (princ "  C-c x a   List all agents\n")
    (princ "  C-c x A   Create a new agent\n\n")
    (princ "Chat\n")
    (princ "  C-c x c   Start chat session (auto-detect provider)\n")
    (princ "  C-u C-c x c   Start chat with provider/model selection\n\n")
    (princ "Conductor\n")
    (princ "  C-c x d   Conductor dashboard\n\n")
    (princ "Teams\n")
    (princ "  C-c x t   List all teams\n")
    (princ "  C-c x T   Create a new team\n\n")
    (princ "Agentic Loops\n")
    (princ "  C-c x g   Create and prompt an agentic agent\n\n")
    (princ "Events\n")
    (princ "  C-c x e   Show integration event log\n\n")
    (princ "Swarm\n")
    (princ "  C-c x w   Launch swarm evolution\n\n")
    (princ "Agent List Buffer Keys\n")
    (princ "  RET  Agent detail\n")
    (princ "  c    Chat with agent\n")
    (princ "  +    Create agent\n")
    (princ "  g    Refresh\n\n")
    (princ "Agent Detail Buffer Keys\n")
    (princ "  c    Chat\n")
    (princ "  t    Thoughts\n")
    (princ "  r/p/k  Start/pause/stop agent\n")
    (princ "  g    Refresh\n")
    (princ "  q    Quit\n")))

;;;; ────────────────────────────────────────────────────────────────────
;;;; System Lifecycle
;;;; ────────────────────────────────────────────────────────────────────

;;;###autoload
(defun sly-autopoiesis-system-status ()
  "Display Autopoiesis system status in a buffer."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:system-status)
    (lambda (status)
      (let ((buf (get-buffer-create "*autopoiesis-status*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (special-mode)
            (insert (propertize "Autopoiesis System Status\n" 'face 'bold))
            (insert (make-string 26 ?═) "\n\n")
            (insert (format "Version:          %s\n" (or (plist-get status :version) "?")))
            (insert (format "Health:           %s\n"
                            (let ((h (plist-get status :health-status)))
                              (if (eq h :healthy)
                                  (propertize "healthy" 'face 'success)
                                (propertize (format "%s" (or h "unknown")) 'face 'warning)))))
            (insert (format "Agents:           %d\n" (or (plist-get status :agent-count) 0)))
            (insert (format "Conductor:        %s\n"
                            (if (plist-get status :conductor-running)
                                (propertize "running" 'face 'success)
                              (propertize "stopped" 'face 'shadow))))
            (insert (format "Chat sessions:    %d\n" (or (plist-get status :active-sessions) 0)))
            (insert (format "Agentic agents:   %d\n" (or (plist-get status :agentic-agents) 0)))
            (insert "\n[S] start  [Q] stop  [g] refresh  [q] quit\n")
            (goto-char (point-min)))
          (local-set-key (kbd "S") #'sly-autopoiesis-start-system)
          (local-set-key (kbd "Q") #'sly-autopoiesis-stop-system)
          (local-set-key (kbd "g") #'sly-autopoiesis-system-status)
          (local-set-key (kbd "q") #'quit-window))
        (pop-to-buffer buf)))))

;;;###autoload
(defun sly-autopoiesis-start-system ()
  "Start the Autopoiesis platform."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:start-platform)
    (lambda (status)
      (message "Autopoiesis started: %s | %d agents | conductor %s"
               (or (plist-get status :version) "?")
               (or (plist-get status :agent-count) 0)
               (if (plist-get status :conductor-running) "running" "stopped")))))

;;;###autoload
(defun sly-autopoiesis-stop-system ()
  "Stop the Autopoiesis platform."
  (interactive)
  (when (yes-or-no-p "Stop the Autopoiesis platform? ")
    (sly-eval-async '(slynk-autopoiesis:stop-platform)
      (lambda (_) (message "Autopoiesis stopped.")))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Agent List Buffer
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis--refresh-timer nil
  "Timer for auto-refreshing the agent list buffer.")

(defvar sly-autopoiesis-refresh-interval 5
  "Seconds between auto-refresh of agent list.  Set to nil to disable.")

(defun sly-autopoiesis--agent-list-entries (agents)
  "Convert AGENTS (list of (id name state cap-count thought-count)) to tabulated-list entries."
  (mapcar (lambda (agent)
            (let ((id (nth 0 agent))
                  (name (nth 1 agent))
                  (state (nth 2 agent))
                  (caps (nth 3 agent))
                  (thoughts (nth 4 agent)))
              (list id (vector (or name "unnamed")
                               (or state "?")
                               (format "%d" (or caps 0))
                               (format "%d" (or thoughts 0))))))
          agents))

(defun sly-autopoiesis--refresh-agents ()
  "Refresh the agent list buffer if it exists."
  (when-let ((buf (get-buffer "*autopoiesis-agents*")))
    (when (buffer-live-p buf)
      (sly-eval-async '(slynk-autopoiesis:list-agents)
        (lambda (agents)
          (when (buffer-live-p buf)
            (with-current-buffer buf
              (let ((inhibit-read-only t))
                (setq tabulated-list-entries
                      (sly-autopoiesis--agent-list-entries agents))
                (tabulated-list-print t)))))))))

(defvar sly-autopoiesis-agent-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'sly-autopoiesis-agent-detail-at-point)
    (define-key map (kbd "c") #'sly-autopoiesis-chat-at-point)
    (define-key map (kbd "+") #'sly-autopoiesis-create-agent)
    (define-key map (kbd "g") #'sly-autopoiesis--refresh-agents)
    map)
  "Keymap for agent list buffer.")

(define-derived-mode sly-autopoiesis-agent-list-mode tabulated-list-mode
  "AP-Agents"
  "Major mode for viewing Autopoiesis agents."
  (setq tabulated-list-format
        [("Name" 20 t)
         ("State" 12 t)
         ("Caps" 6 t :right-align t)
         ("Thoughts" 8 t :right-align t)])
  (tabulated-list-init-header)
  (use-local-map (make-composed-keymap sly-autopoiesis-agent-list-mode-map
                                        tabulated-list-mode-map))
  (when sly-autopoiesis-refresh-interval
    (when sly-autopoiesis--refresh-timer
      (cancel-timer sly-autopoiesis--refresh-timer))
    (setq sly-autopoiesis--refresh-timer
          (run-with-timer sly-autopoiesis-refresh-interval
                          sly-autopoiesis-refresh-interval
                          #'sly-autopoiesis--refresh-agents)))
  (add-hook 'kill-buffer-hook
            (lambda ()
              (when sly-autopoiesis--refresh-timer
                (cancel-timer sly-autopoiesis--refresh-timer)
                (setq sly-autopoiesis--refresh-timer nil)))
            nil t))

;;;###autoload
(defun sly-autopoiesis-list-agents ()
  "Display all Autopoiesis agents in a tabulated list."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:list-agents)
    (lambda (agents)
      (let ((buf (get-buffer-create "*autopoiesis-agents*")))
        (with-current-buffer buf
          (sly-autopoiesis-agent-list-mode)
          (setq tabulated-list-entries
                (sly-autopoiesis--agent-list-entries agents))
          (tabulated-list-print t))
        (pop-to-buffer buf)))))

;;;###autoload
(defun sly-autopoiesis-create-agent (name)
  "Create a new agent with NAME."
  (interactive "sAgent name: ")
  (let* ((caps-str (read-string "Capabilities (comma-separated, or empty): "))
         (caps (when (not (string-empty-p caps-str))
                 (mapcar #'string-trim (split-string caps-str ",")))))
    (sly-eval-async `(slynk-autopoiesis:create-agent ,name ',caps)
      (lambda (id)
        (message "Created agent %s (id: %s)" name id)
        (sly-autopoiesis--refresh-agents)))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Agent Detail Buffer
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis-agent-detail-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'sly-autopoiesis--chat-from-detail)
    (define-key map (kbd "t") #'sly-autopoiesis--thoughts-from-detail)
    (define-key map (kbd "r") #'sly-autopoiesis--start-agent)
    (define-key map (kbd "p") #'sly-autopoiesis--pause-agent)
    (define-key map (kbd "k") #'sly-autopoiesis--stop-agent)
    (define-key map (kbd "g") #'sly-autopoiesis--refresh-detail)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for agent detail buffer.")

(define-derived-mode sly-autopoiesis-agent-detail-mode special-mode
  "AP-Agent"
  "Major mode for viewing Autopoiesis agent detail.")

(defvar-local sly-autopoiesis--detail-agent-id nil
  "Agent ID displayed in this detail buffer.")

(defun sly-autopoiesis--render-detail (info)
  "Render agent INFO plist into the current buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (format "Agent: %s\n" (plist-get info :name))
                        'face 'bold))
    (insert (make-string 40 ?─) "\n")
    (insert (format "ID:           %s\n" (plist-get info :id)))
    (insert (format "State:        %s\n" (plist-get info :state)))
    (insert (format "Thoughts:     %d\n" (or (plist-get info :thought-count) 0)))
    (insert (format "Parent:       %s\n" (or (plist-get info :parent) "none")))
    (insert (format "Children:     %s\n" (or (plist-get info :children) "none")))
    (insert "\nCapabilities:\n")
    (if (plist-get info :capabilities)
        (dolist (cap (plist-get info :capabilities))
          (insert (format "  - %s\n" cap)))
      (insert "  (none)\n"))
    (insert "\n[c] chat  [t] thoughts  [r] start  [p] pause  [k] stop  [g] refresh  [q] quit\n")
    (goto-char (point-min))))

(defun sly-autopoiesis-agent-detail-at-point ()
  "Show detail for the agent at point in the agent list."
  (interactive)
  (let ((agent-id (tabulated-list-get-id)))
    (unless agent-id (user-error "No agent at point"))
    (sly-autopoiesis-show-agent agent-id)))

(defun sly-autopoiesis-show-agent (agent-id)
  "Display detail buffer for AGENT-ID."
  (sly-eval-async `(slynk-autopoiesis:get-agent ,agent-id)
    (lambda (info)
      (let ((buf (get-buffer-create
                  (format "*autopoiesis-agent: %s*"
                          (plist-get info :name)))))
        (with-current-buffer buf
          (sly-autopoiesis-agent-detail-mode)
          (setq sly-autopoiesis--detail-agent-id agent-id)
          (sly-autopoiesis--render-detail info))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis--refresh-detail ()
  "Refresh the current agent detail buffer."
  (interactive)
  (when sly-autopoiesis--detail-agent-id
    (sly-eval-async `(slynk-autopoiesis:get-agent ,sly-autopoiesis--detail-agent-id)
      (lambda (info)
        (sly-autopoiesis--render-detail info)))))

(defun sly-autopoiesis--chat-from-detail ()
  "Open chat for the agent in this detail buffer."
  (interactive)
  (when sly-autopoiesis--detail-agent-id
    (sly-autopoiesis--open-chat sly-autopoiesis--detail-agent-id)))

(defun sly-autopoiesis--thoughts-from-detail ()
  "Show thoughts for the agent in this detail buffer."
  (interactive)
  (when sly-autopoiesis--detail-agent-id
    (sly-autopoiesis-show-thoughts sly-autopoiesis--detail-agent-id)))

(defun sly-autopoiesis--set-agent-state (state)
  "Set the current detail agent to STATE."
  (when sly-autopoiesis--detail-agent-id
    (sly-eval-async `(slynk-autopoiesis:set-agent-state
                       ,sly-autopoiesis--detail-agent-id ,state)
      (lambda (_)
        (message "Agent state set to %s" state)
        (sly-autopoiesis--refresh-detail)))))

(defun sly-autopoiesis--start-agent ()
  "Start the agent in this detail buffer."
  (interactive)
  (sly-autopoiesis--set-agent-state "running"))

(defun sly-autopoiesis--pause-agent ()
  "Pause the agent in this detail buffer."
  (interactive)
  (sly-autopoiesis--set-agent-state "paused"))

(defun sly-autopoiesis--stop-agent ()
  "Stop the agent in this detail buffer."
  (interactive)
  (sly-autopoiesis--set-agent-state "stopped"))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Thoughts Buffer
;;;; ────────────────────────────────────────────────────────────────────

(defun sly-autopoiesis-show-thoughts (agent-id &optional limit)
  "Show thoughts for AGENT-ID in a dedicated buffer."
  (sly-eval-async `(slynk-autopoiesis:agent-thoughts ,agent-id ,(or limit 50))
    (lambda (thoughts)
      (let ((buf (get-buffer-create
                  (format "*autopoiesis-thoughts: %s*" agent-id))))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (special-mode)
            (insert (propertize (format "Thoughts for %s\n\n" agent-id)
                                'face 'bold))
            (if (null thoughts)
                (insert "(no thoughts)\n")
              (dolist (th thoughts)
                (let ((type (cdr (assq :type th)))
                      (content (cdr (assq :content th)))
                      (ts (cdr (assq :timestamp th))))
                  (insert (propertize (format "[%s] " (or type "?"))
                                      'face 'font-lock-keyword-face))
                  (insert (propertize (format "%s " (or ts ""))
                                      'face 'font-lock-comment-face))
                  (insert (format "%s\n" (or content ""))))))
            (goto-char (point-min))))
        (pop-to-buffer buf)))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Chat Shell (comint-based, provider-aware)
;;;; ────────────────────────────────────────────────────────────────────

(defvar-local sly-autopoiesis--chat-session nil
  "Session name for this chat buffer.")

(defvar-local sly-autopoiesis--chat-started nil
  "Non-nil if the Jarvis session has been started.")

(defvar-local sly-autopoiesis--chat-provider nil
  "Provider type string for this chat session, or nil.")

(defun sly-autopoiesis--chat-input-sender (_proc input)
  "Send INPUT to the Jarvis session via Slynk."
  (let ((session sly-autopoiesis--chat-session)
        (provider sly-autopoiesis--chat-provider)
        (buf (current-buffer)))
    ;; Auto-start session on first message
    (unless sly-autopoiesis--chat-started
      (sly-eval-async `(slynk-autopoiesis:start-chat ,session ,provider)
        (lambda (_result)
          (when (buffer-live-p buf)
            (with-current-buffer buf
              (setq sly-autopoiesis--chat-started t))))))
    ;; Show thinking indicator
    (setq mode-line-process '(:propertize " [thinking...]" face font-lock-comment-face))
    (force-mode-line-update)
    ;; Send prompt
    (sly-eval-async `(slynk-autopoiesis:chat-prompt ,session ,input)
      (lambda (response)
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (setq mode-line-process nil)
            (force-mode-line-update)
            (let ((inhibit-read-only t))
              (goto-char (process-mark (get-buffer-process buf)))
              (insert (propertize (format "\n%s\n" (or response "[no response]"))
                                  'face 'font-lock-string-face
                                  'font-lock-face 'font-lock-string-face))
              (set-marker (process-mark (get-buffer-process buf)) (point))
              (goto-char (point-max)))))))))

(defun sly-autopoiesis--open-chat (session-name &optional provider model)
  "Open a chat shell for SESSION-NAME.
PROVIDER is an optional provider type string.
MODEL is an optional model string."
  (let* ((buf-name (format "*autopoiesis-chat: %s*" session-name))
         (existing (get-buffer buf-name)))
    (if existing
        (pop-to-buffer existing)
      (let ((buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          (comint-mode)
          (setq sly-autopoiesis--chat-session session-name)
          (setq sly-autopoiesis--chat-started nil)
          (setq sly-autopoiesis--chat-provider provider)
          (setq comint-input-sender #'sly-autopoiesis--chat-input-sender)
          (setq comint-prompt-regexp (format "^%s> " (regexp-quote session-name)))
          (setq comint-process-echoes nil)
          ;; We need a process for comint to work — use a cat process
          (let ((proc (start-process "autopoiesis-chat" buf "cat")))
            (set-process-query-on-exit-flag proc nil)
            (goto-char (point-max))
            (let ((inhibit-read-only t))
              (insert (propertize (format "Autopoiesis Chat — %s" session-name)
                                  'face 'bold))
              (when provider
                (insert (propertize (format " [%s%s]"
                                            provider
                                            (if model (format " / %s" model) ""))
                                    'face 'font-lock-type-face)))
              (insert "\nType a message and press RET to send.\n\n"))
            (set-marker (process-mark proc) (point))
            (setq comint-prompt-read-only t)
            (let ((inhibit-read-only t))
              (insert (propertize (format "%s> " session-name)
                                  'face 'comint-highlight-prompt
                                  'font-lock-face 'comint-highlight-prompt
                                  'rear-nonsticky t
                                  'read-only t)))
            (set-marker (process-mark proc) (point)))
          ;; Pre-start with provider if given
          (when provider
            (sly-eval-async `(slynk-autopoiesis:start-chat ,session-name ,provider ,model)
              (lambda (_)
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (setq sly-autopoiesis--chat-started t))))))
          ;; Clean up on buffer kill
          (add-hook 'kill-buffer-hook
                    (lambda ()
                      (when sly-autopoiesis--chat-session
                        (ignore-errors
                          (sly-eval `(slynk-autopoiesis:stop-chat
                                      ,sly-autopoiesis--chat-session)))))
                    nil t))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis-chat-at-point ()
  "Open chat for the agent at point in the agent list."
  (interactive)
  (let ((agent-id (tabulated-list-get-id)))
    (unless agent-id (user-error "No agent at point"))
    (sly-autopoiesis--open-chat agent-id)))

;;;###autoload
(defun sly-autopoiesis-chat (session-name)
  "Start a chat session named SESSION-NAME.
With prefix arg, prompt for provider and model."
  (interactive
   (list (read-string "Session name: " "default")))
  (if current-prefix-arg
      (let* ((providers (ignore-errors (sly-eval '(slynk-autopoiesis:list-providers))))
             (provider-names (append '("auto" "rho" "pi")
                                     (mapcar #'car (or providers nil))))
             (provider (completing-read "Provider: " provider-names nil nil "auto"))
             (model (read-string "Model (empty for default): ")))
        (sly-autopoiesis--open-chat session-name
                                     (unless (string= provider "auto") provider)
                                     (unless (string-empty-p model) model)))
    (sly-autopoiesis--open-chat session-name)))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Conductor Dashboard
;;;; ────────────────────────────────────────────────────────────────────

(defun sly-autopoiesis--render-conductor (info)
  "Render conductor INFO plist into the current buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (if (null info)
        (progn
          (insert (propertize "Conductor Dashboard\n" 'face 'bold))
          (insert (make-string 20 ?═) "\n\n")
          (insert (propertize "Conductor is not running.\n\n" 'face 'shadow))
          (insert "[s] start conductor  [q] quit\n"))
      (insert (propertize "Conductor Dashboard\n" 'face 'bold))
      (insert (make-string 20 ?═) "\n\n")
      (insert (format "Running:            %s\n"
                       (if (plist-get info :running)
                           (propertize "yes" 'face 'success)
                         (propertize "no" 'face 'warning))))
      (insert (format "Ticks:              %s\n" (or (plist-get info :tick-count) 0)))
      (insert (format "Events processed:   %s\n" (or (plist-get info :events-processed) 0)))
      (insert (format "Events failed:      %s\n" (or (plist-get info :events-failed) 0)))
      (insert (format "Timer errors:       %s\n" (or (plist-get info :timer-errors) 0)))
      (insert (format "Tick errors:        %s\n" (or (plist-get info :tick-errors) 0)))
      (insert (format "Task retries:       %s\n" (or (plist-get info :task-retries) 0)))
      (insert (format "Pending timers:     %s\n" (or (plist-get info :pending-timers) 0)))
      (insert (format "Active workers:     %s\n" (or (plist-get info :active-workers) 0)))
      ;; Crystallization stats if present
      (when (plist-get info :triggers-checked)
        (insert "\nCrystallization:\n")
        (insert (format "  Triggers checked:      %s\n" (plist-get info :triggers-checked)))
        (insert (format "  Crystallizations:      %s\n" (plist-get info :crystallizations-performed)))
        (insert (format "  Trigger check errors:  %s\n" (plist-get info :trigger-check-errors))))
      (insert "\n[S] stop conductor  [g] refresh  [q] quit\n"))
    (goto-char (point-min))))

;;;###autoload
(defun sly-autopoiesis-conductor-dashboard ()
  "Show the conductor status dashboard."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:conductor-info)
    (lambda (info)
      (let ((buf (get-buffer-create "*autopoiesis-conductor*")))
        (with-current-buffer buf
          (special-mode)
          (sly-autopoiesis--render-conductor info)
          (local-set-key (kbd "s") #'sly-autopoiesis--start-conductor)
          (local-set-key (kbd "S") #'sly-autopoiesis--stop-conductor)
          (local-set-key (kbd "g") #'sly-autopoiesis-conductor-dashboard)
          (local-set-key (kbd "q") #'quit-window))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis--start-conductor ()
  "Start the conductor."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:start-conductor-rpc)
    (lambda (_)
      (message "Conductor started.")
      (sly-autopoiesis-conductor-dashboard))))

(defun sly-autopoiesis--stop-conductor ()
  "Stop the conductor."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:stop-conductor-rpc)
    (lambda (_)
      (message "Conductor stopped.")
      (sly-autopoiesis-conductor-dashboard))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Team List
;;;; ────────────────────────────────────────────────────────────────────

(defun sly-autopoiesis--team-list-entries (teams)
  "Convert TEAMS to tabulated-list entries."
  (mapcar (lambda (team)
            (let ((id (nth 0 team))
                  (status (nth 1 team))
                  (strategy (nth 2 team))
                  (members (nth 3 team))
                  (task (nth 4 team)))
              (list id (vector (or status "?")
                               (or strategy "?")
                               (format "%d" (or members 0))
                               (or task "")))))
          teams))

(defvar sly-autopoiesis-team-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'sly-autopoiesis--team-detail-at-point)
    (define-key map (kbd "s") #'sly-autopoiesis--start-team-at-point)
    (define-key map (kbd "d") #'sly-autopoiesis--disband-team-at-point)
    (define-key map (kbd "+") #'sly-autopoiesis-create-team)
    (define-key map (kbd "g") #'sly-autopoiesis-list-teams)
    map)
  "Keymap for team list buffer.")

(define-derived-mode sly-autopoiesis-team-list-mode tabulated-list-mode
  "AP-Teams"
  "Major mode for viewing Autopoiesis teams."
  (setq tabulated-list-format
        [("Status" 12 t)
         ("Strategy" 30 t)
         ("Members" 8 t :right-align t)
         ("Task" 40 t)])
  (tabulated-list-init-header)
  (use-local-map (make-composed-keymap sly-autopoiesis-team-list-mode-map
                                        tabulated-list-mode-map)))

;;;###autoload
(defun sly-autopoiesis-list-teams ()
  "Display all teams in a tabulated list."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:list-teams)
    (lambda (teams)
      (let ((buf (get-buffer-create "*autopoiesis-teams*")))
        (with-current-buffer buf
          (sly-autopoiesis-team-list-mode)
          (setq tabulated-list-entries
                (sly-autopoiesis--team-list-entries teams))
          (tabulated-list-print t))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis--team-detail-at-point ()
  "Show detail for team at point."
  (interactive)
  (let ((team-id (tabulated-list-get-id)))
    (unless team-id (user-error "No team at point"))
    (sly-eval-async `(slynk-autopoiesis:query-team ,team-id)
      (lambda (info)
        (let ((buf (get-buffer-create (format "*autopoiesis-team: %s*" team-id))))
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              (erase-buffer)
              (special-mode)
              (insert (propertize "Team Detail\n" 'face 'bold))
              (insert (make-string 40 ?─) "\n")
              (cl-loop for (k v) on info by #'cddr
                       do (insert (format "%-16s %s\n"
                                          (substring (symbol-name k) 1)
                                          (if (listp v) (format "%S" v) v))))
              (insert "\n[q] quit\n")
              (goto-char (point-min)))
            (local-set-key (kbd "q") #'quit-window))
          (pop-to-buffer buf))))))

(defun sly-autopoiesis--start-team-at-point ()
  "Start team at point."
  (interactive)
  (let ((team-id (tabulated-list-get-id)))
    (unless team-id (user-error "No team at point"))
    (sly-eval-async `(slynk-autopoiesis:start-team-rpc ,team-id)
      (lambda (_)
        (message "Team started: %s" team-id)
        (sly-autopoiesis-list-teams)))))

(defun sly-autopoiesis--disband-team-at-point ()
  "Disband team at point."
  (interactive)
  (let ((team-id (tabulated-list-get-id)))
    (unless team-id (user-error "No team at point"))
    (when (yes-or-no-p (format "Disband team %s? " team-id))
      (sly-eval-async `(slynk-autopoiesis:disband-team-rpc ,team-id)
        (lambda (_)
          (message "Team disbanded: %s" team-id)
          (sly-autopoiesis-list-teams))))))

;;;###autoload
(defun sly-autopoiesis-create-team (name)
  "Create a new team with NAME."
  (interactive "sTeam name: ")
  (let* ((strategies '("leader-worker" "parallel" "pipeline" "debate" "consensus"
                        "hierarchical-leader-worker" "leader-parallel"
                        "rotating-leader" "debate-consensus"))
         (strategy (completing-read "Strategy: " strategies nil t))
         (task (read-string "Task description: "))
         (members-str (read-string "Member agent IDs (comma-separated, or empty): "))
         (members (when (not (string-empty-p members-str))
                    (mapcar #'string-trim (split-string members-str ","))))
         (leader (when members
                   (completing-read "Leader (or empty): " members nil nil))))
    (sly-eval-async `(slynk-autopoiesis:create-team-rpc
                       ,name ,strategy
                       :task ,task
                       :members ',members
                       :leader ,(if (string-empty-p leader) nil leader))
      (lambda (id)
        (message "Created team %s (id: %s)" name id)
        (sly-autopoiesis-list-teams)))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Agentic Loop
;;;; ────────────────────────────────────────────────────────────────────

;;;###autoload
(defun sly-autopoiesis-agentic-prompt ()
  "Create or reuse an agentic agent and send it a prompt."
  (interactive)
  (let* ((existing (ignore-errors (sly-eval '(slynk-autopoiesis:list-agentic-agents))))
         (choices (mapcar (lambda (a) (cons (format "%s (%s)" (cadr a) (car a)) (car a)))
                          (or existing nil)))
         (new-entry (cons "[new agent]" nil))
         (all-choices (cons new-entry choices))
         (selected (completing-read "Agentic agent: " all-choices nil t))
         (agent-id (cdr (assoc selected all-choices))))
    (unless agent-id
      ;; Create new agentic agent
      (let* ((name (read-string "Agent name: " "agentic"))
             (providers (ignore-errors (sly-eval '(slynk-autopoiesis:list-providers))))
             (provider-names (cons "none" (mapcar #'car (or providers nil))))
             (provider (completing-read "Provider: " provider-names nil nil "none"))
             (model (read-string "Model (empty for default): "))
             (sys-prompt (read-string "System prompt (empty for default): ")))
        (setq agent-id
              (sly-eval `(slynk-autopoiesis:create-agentic-agent-rpc
                           ,name
                           :provider ,(unless (string= provider "none") provider)
                           :model ,(unless (string-empty-p model) model)
                           :system-prompt ,(unless (string-empty-p sys-prompt) sys-prompt))))
        (message "Created agentic agent: %s" agent-id)))
    ;; Now prompt
    (let ((prompt (read-string "Prompt: ")))
      (message "Sending to agentic agent %s..." agent-id)
      (sly-eval-async `(slynk-autopoiesis:agentic-prompt ,agent-id ,prompt)
        (lambda (response)
          (let ((buf (get-buffer-create (format "*autopoiesis-agentic: %s*" agent-id))))
            (with-current-buffer buf
              (let ((inhibit-read-only t))
                (goto-char (point-max))
                (when (= (point-min) (point-max))
                  (insert (propertize "Agentic Agent Response\n\n" 'face 'bold)))
                (insert (propertize (format ">>> %s\n" prompt)
                                    'face 'font-lock-keyword-face))
                (insert (format "\n%s\n\n" (or response "[no response]")))
                (insert (make-string 60 ?─) "\n\n"))
              (special-mode)
              (local-set-key (kbd "q") #'quit-window)
              (goto-char (point-max)))
            (pop-to-buffer buf)))))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Events Log
;;;; ────────────────────────────────────────────────────────────────────

;;;###autoload
(defun sly-autopoiesis-events ()
  "Show recent integration events."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:recent-events 100)
    (lambda (events)
      (let ((buf (get-buffer-create "*autopoiesis-events*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (special-mode)
            (insert (propertize "Integration Events\n" 'face 'bold))
            (insert (make-string 20 ?═) "\n\n")
            ;; Stats line
            (sly-eval-async '(slynk-autopoiesis:event-stats)
              (lambda (stats)
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (let ((inhibit-read-only t))
                      (save-excursion
                        (goto-char (point-min))
                        (forward-line 2)
                        (insert (format "Total: %d  Tools: %d  Claude: %d  Providers: %d\n\n"
                                        (or (plist-get stats :total) 0)
                                        (or (plist-get stats :tool-calls) 0)
                                        (or (plist-get stats :claude-requests) 0)
                                        (or (plist-get stats :provider-requests) 0)))))))))
            (if (null events)
                (insert "(no events)\n")
              (dolist (ev events)
                (let ((type (cdr (assq :type ev)))
                      (source (cdr (assq :source ev)))
                      (ts (cdr (assq :timestamp ev))))
                  (insert (propertize (format "%-24s " (or type "?"))
                                      'face 'font-lock-keyword-face))
                  (insert (propertize (format "%-20s " (or source ""))
                                      'face 'font-lock-function-name-face))
                  (insert (propertize (format "%s\n" (or ts ""))
                                      'face 'font-lock-comment-face)))))
            (insert "\n[g] refresh  [q] quit\n")
            (goto-char (point-min)))
          (local-set-key (kbd "g") #'sly-autopoiesis-events)
          (local-set-key (kbd "q") #'quit-window))
        (pop-to-buffer buf)))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Swarm Evolution
;;;; ────────────────────────────────────────────────────────────────────

;;;###autoload
(defun sly-autopoiesis-evolve ()
  "Launch swarm evolution on selected agents."
  (interactive)
  (let* ((agents (sly-eval '(slynk-autopoiesis:list-agents)))
         (choices (mapcar (lambda (a)
                            (cons (format "%s [%s]" (or (nth 1 a) "?") (nth 0 a))
                                  (nth 0 a)))
                          agents))
         (selected (completing-read-multiple "Agents to evolve: " choices nil t))
         (agent-ids (mapcar (lambda (s) (cdr (assoc s choices))) selected)))
    (unless (>= (length agent-ids) 2)
      (user-error "Need at least 2 agents for evolution"))
    (let* ((gens (read-number "Generations: " 10))
           (rate (read-number "Mutation rate: " 0.1)))
      (message "Starting evolution with %d agents for %d generations..."
               (length agent-ids) gens)
      (sly-eval-async `(slynk-autopoiesis:start-evolution
                          ',agent-ids
                          :generations ,gens
                          :mutation-rate ,rate)
        (lambda (results)
          (let ((buf (get-buffer-create "*autopoiesis-evolution*")))
            (with-current-buffer buf
              (let ((inhibit-read-only t))
                (erase-buffer)
                (special-mode)
                (insert (propertize "Swarm Evolution Results\n" 'face 'bold))
                (insert (make-string 24 ?═) "\n\n")
                (insert (format "Generations: %d  Mutation rate: %.2f\n" gens rate))
                (insert (format "Population size: %d\n\n" (length results)))
                (insert (propertize (format "%-20s %10s %10s\n" "Name" "Fitness" "Caps")
                                    'face 'bold))
                (insert (make-string 42 ?─) "\n")
                (dolist (r results)
                  (insert (format "%-20s %10.4f %10d\n"
                                  (or (nth 0 r) "?")
                                  (or (nth 1 r) 0.0)
                                  (or (nth 2 r) 0))))
                (insert "\n[q] quit\n")
                (goto-char (point-min)))
              (local-set-key (kbd "q") #'quit-window))
            (pop-to-buffer buf)))))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Slynk load path
;;;; ────────────────────────────────────────────────────────────────────

;; Register this directory so Slynk can find slynk-autopoiesis.lisp
(when (boundp 'slynk-loader:*contrib-paths*)
  (cl-pushnew (file-name-directory (or load-file-name buffer-file-name))
              slynk-loader:*contrib-paths*
              :test #'string=))

(provide 'sly-autopoiesis)

;;; sly-autopoiesis.el ends here
