;;; sly-autopoiesis.el --- SLY contrib for Autopoiesis agent platform -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Autopoiesis Contributors
;; Package-Requires: ((emacs "28.1") (sly "1.0"))
;; Version: 0.1.0

;;; Commentary:

;; SLY contrib providing interactive Emacs commands for the Autopoiesis
;; agent platform.  Connects to a running SBCL image via Slynk for
;; zero-overhead in-image RPC.
;;
;; Features:
;;   - Agent list buffer (tabulated-list-mode)
;;   - Agent detail view
;;   - Chat shell (comint-mode derivative) bridging to Jarvis sessions
;;   - System status in minibuffer
;;
;; Keybindings (under C-c a prefix when sly-autopoiesis-mode is active):
;;   C-c a l  - List agents
;;   C-c a s  - System status
;;   C-c a c  - Chat with agent (prompts for agent ID)

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
    (define-key map (kbd "C-c a l") #'sly-autopoiesis-list-agents)
    (define-key map (kbd "C-c a s") #'sly-autopoiesis-system-status)
    (define-key map (kbd "C-c a c") #'sly-autopoiesis-chat)
    (define-key map (kbd "C-c x E") #'sly-autopoiesis-toggle-event-bridge)
    (define-key map (kbd "C-c x n") #'sly-autopoiesis-snapshot-browser)
    (define-key map (kbd "C-c x l") #'sly-autopoiesis-live-thoughts)
    (define-key map (kbd "C-c x B") #'sly-autopoiesis-branch-manager)
    map)
  "Keymap for `sly-autopoiesis-mode'.")

;;;###autoload
(define-minor-mode sly-autopoiesis-mode
  "Minor mode for Autopoiesis agent platform integration via SLY."
  :lighter " AP"
  :keymap sly-autopoiesis-mode-map
  :global t)

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
  ;; Set up auto-refresh
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

;;;; ────────────────────────────────────────────────────────────────────
;;;; Agent Detail Buffer
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis-agent-detail-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'sly-autopoiesis--chat-from-detail)
    (define-key map (kbd "t") #'sly-autopoiesis--thoughts-from-detail)
    (define-key map (kbd "l") #'sly-autopoiesis--live-thoughts-from-detail)
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
    (insert (format "ID:           %s\n" (plist-get info :id)))
    (insert (format "State:        %s\n" (plist-get info :state)))
    (insert (format "Thoughts:     %d\n" (or (plist-get info :thought-count) 0)))
    (insert (format "Parent:       %s\n" (or (plist-get info :parent) "none")))
    (insert (format "Children:     %s\n" (or (plist-get info :children) "none")))
    (insert "\nCapabilities:\n")
    (dolist (cap (plist-get info :capabilities))
      (insert (format "  - %s\n" cap)))
    (insert "\n[c] chat  [t] thoughts  [l] live thoughts  [g] refresh  [q] quit\n")
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

(defun sly-autopoiesis--live-thoughts-from-detail ()
  "Open live thought buffer for the agent in this detail buffer."
  (interactive)
  (when sly-autopoiesis--detail-agent-id
    (sly-autopoiesis-live-thoughts sly-autopoiesis--detail-agent-id)))

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
;;;; Live Thought Buffer
;;;; ────────────────────────────────────────────────────────────────────

(defvar-local sly-autopoiesis--live-agent-id nil
  "Agent ID for this live thought buffer.")

(defun sly-autopoiesis-live-thoughts (agent-id)
  "Open a live thought streaming buffer for AGENT-ID.
Thoughts arrive via the event bridge and are appended in real-time."
  (interactive (list (read-string "Agent ID: "
                      (when (bound-and-true-p sly-autopoiesis--detail-agent-id)
                        sly-autopoiesis--detail-agent-id))))
  ;; Buffer name uses "live" to distinguish from static
  (let* ((buf-name (format "*autopoiesis-thoughts-live: %s*" agent-id))
         (existing (get-buffer buf-name)))
    (if existing
        (pop-to-buffer existing)
      (let ((buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          (special-mode)
          (setq sly-autopoiesis--live-agent-id agent-id)
          (let ((inhibit-read-only t))
            (insert (propertize (format "Live Thoughts — %s\n\n" agent-id)
                                'face 'bold))
            ;; Load recent history first
            (insert (propertize "(loading history...)\n" 'face 'font-lock-comment-face))))
        ;; Fetch recent thoughts as initial content
        (sly-eval-async `(slynk-autopoiesis:agent-thoughts ,agent-id 50)
          (lambda (thoughts)
            (when (buffer-live-p buf)
              (with-current-buffer buf
                (let ((inhibit-read-only t))
                  ;; Remove loading message
                  (goto-char (point-min))
                  (forward-line 2)
                  (delete-region (point) (point-max))
                  ;; Insert historical thoughts
                  (dolist (th thoughts)
                    (sly-autopoiesis--insert-live-thought th))
                  (goto-char (point-max)))))))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis--insert-live-thought (thought-alist)
  "Insert a thought into the current live buffer with color coding."
  (let ((type (cdr (assq :type thought-alist)))
        (content (cdr (assq :content thought-alist)))
        (ts (cdr (assq :timestamp thought-alist))))
    (insert (propertize (format "[%s] " (or type "?"))
                        'face (sly-autopoiesis--thought-face type)))
    (insert (propertize (format "%s " (or ts ""))
                        'face 'font-lock-comment-face))
    (insert (format "%s\n" (or content "")))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Chat Shell (comint-based)
;;;; ────────────────────────────────────────────────────────────────────

(defvar-local sly-autopoiesis--chat-agent-id nil
  "Agent ID for this chat buffer.")

(defvar-local sly-autopoiesis--chat-started nil
  "Non-nil if the Jarvis session has been started.")

(defun sly-autopoiesis--chat-input-sender (_proc input)
  "Send INPUT to the Jarvis session via Slynk."
  (let ((agent-id sly-autopoiesis--chat-agent-id)
        (buf (current-buffer)))
    ;; Auto-start session on first message
    (unless sly-autopoiesis--chat-started
      (sly-eval-async `(slynk-autopoiesis:start-chat ,agent-id)
        (lambda (_result)
          (with-current-buffer buf
            (setq sly-autopoiesis--chat-started t)))))
    ;; Show thinking indicator
    (setq mode-line-process '(:propertize " [thinking...]" face font-lock-comment-face))
    (force-mode-line-update)
    ;; Send prompt
    (sly-eval-async `(slynk-autopoiesis:chat-prompt ,agent-id ,input)
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

(defun sly-autopoiesis--chat-buffer-name (agent-id)
  "Return chat buffer name for AGENT-ID."
  (format "*autopoiesis-chat: %s*" agent-id))

(defun sly-autopoiesis--open-chat (agent-id &optional provider-config)
  "Open a chat shell for AGENT-ID.
Optional PROVIDER-CONFIG is a plist passed to start-chat."
  (let* ((buf-name (sly-autopoiesis--chat-buffer-name agent-id))
         (existing (get-buffer buf-name)))
    (if existing
        (pop-to-buffer existing)
      (let ((buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          (comint-mode)
          (setq sly-autopoiesis--chat-agent-id agent-id)
          (setq sly-autopoiesis--chat-started nil)
          (setq comint-input-sender #'sly-autopoiesis--chat-input-sender)
          (setq comint-prompt-regexp (format "^%s> " (regexp-quote agent-id)))
          (setq comint-process-echoes nil)
          ;; We need a process for comint to work — use a cat process
          (let ((proc (start-process "autopoiesis-chat" buf "cat")))
            (set-process-query-on-exit-flag proc nil)
            (goto-char (point-max))
            (let ((inhibit-read-only t))
              (insert (propertize (format "Autopoiesis Chat — Agent: %s\n" agent-id)
                                  'face 'bold))
              (insert "Type a message and press RET to send.\n\n"))
            (set-marker (process-mark proc) (point))
            ;; Set up the prompt
            (setq comint-prompt-read-only t)
            (let ((inhibit-read-only t))
              (insert (propertize (format "%s> " agent-id)
                                  'face 'comint-highlight-prompt
                                  'font-lock-face 'comint-highlight-prompt
                                  'rear-nonsticky t
                                  'read-only t)))
            (set-marker (process-mark proc) (point)))
          ;; Auto-start with provider config if given
          (when provider-config
            (sly-eval-async `(slynk-autopoiesis:start-chat ,agent-id ',provider-config)
              (lambda (_)
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (setq sly-autopoiesis--chat-started t))))))
          ;; Clean up on buffer kill
          (add-hook 'kill-buffer-hook
                    (lambda ()
                      (when sly-autopoiesis--chat-agent-id
                        (ignore-errors
                          (sly-eval `(slynk-autopoiesis:stop-chat
                                      ,sly-autopoiesis--chat-agent-id)))))
                    nil t))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis-chat-at-point ()
  "Open chat for the agent at point in the agent list."
  (interactive)
  (let ((agent-id (tabulated-list-get-id)))
    (unless agent-id (user-error "No agent at point"))
    (sly-autopoiesis--open-chat agent-id)))

;;;###autoload
(defun sly-autopoiesis-chat (agent-id)
  "Start a chat session with AGENT-ID.
With prefix arg, prompt for provider model name."
  (interactive
   (list (read-string "Agent ID: "
                      (when (bound-and-true-p sly-autopoiesis--detail-agent-id)
                        sly-autopoiesis--detail-agent-id))))
  (if current-prefix-arg
      (let* ((model (read-string "Model (e.g. claude-sonnet-4-20250514): "))
             (config (when (not (string-empty-p model))
                       (list :model model))))
        (sly-autopoiesis--open-chat agent-id config))
    (sly-autopoiesis--open-chat agent-id)))

;;;; ────────────────────────────────────────────────────────────────────
;;;; System Status
;;;; ────────────────────────────────────────────────────────────────────

;;;###autoload
(defun sly-autopoiesis-system-status ()
  "Display Autopoiesis system status in the minibuffer."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:system-status)
    (lambda (status)
      (message "Autopoiesis %s | %s | %d agents"
               (or (plist-get status :version) "?")
               (let ((h (plist-get status :health-status)))
                 (if (eq h :healthy) "healthy" (format "%s" h)))
               (or (plist-get status :agent-count) 0)))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Event Bridge Receivers (called from slynk:eval-in-emacs)
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis--event-log nil
  "Ring buffer of recent events for the event bridge.")

(defvar sly-autopoiesis--event-log-max 500
  "Maximum number of events to keep in the ring buffer.")

(defun sly-autopoiesis--handle-thought (agent-id thought-alist)
  "Handle a thought event pushed from the CL event bridge.
AGENT-ID is a string, THOUGHT-ALIST has :type, :content, :timestamp."
  ;; Update live thought buffer if it exists
  (when-let ((buf (get-buffer (format "*autopoiesis-thoughts: %s*" agent-id))))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (let ((type (cdr (assq :type thought-alist)))
                (content (cdr (assq :content thought-alist)))
                (ts (cdr (assq :timestamp thought-alist))))
            (insert (propertize (format "[%s] " (or type "?"))
                                'face (sly-autopoiesis--thought-face type)))
            (insert (propertize (format "%s " (or ts ""))
                                'face 'font-lock-comment-face))
            (insert (format "%s\n" (or content ""))))))))
  ;; Update live thought buffer if it exists
  (when-let ((live-buf (get-buffer (format "*autopoiesis-thoughts-live: %s*" agent-id))))
    (when (buffer-live-p live-buf)
      (with-current-buffer live-buf
        (let ((inhibit-read-only t)
              (at-end (= (point) (point-max))))
          (save-excursion
            (goto-char (point-max))
            (sly-autopoiesis--insert-live-thought thought-alist))
          ;; Auto-scroll if point was at end
          (when at-end
            (goto-char (point-max)))))))
  ;; Also push to event log
  (push (list :thought agent-id thought-alist (current-time))
        sly-autopoiesis--event-log)
  (when (> (length sly-autopoiesis--event-log) sly-autopoiesis--event-log-max)
    (setq sly-autopoiesis--event-log
          (cl-subseq sly-autopoiesis--event-log 0 sly-autopoiesis--event-log-max))))

(defun sly-autopoiesis--thought-face (type)
  "Return face for thought TYPE string."
  (pcase type
    ("observation" 'font-lock-type-face)
    ("decision" 'font-lock-warning-face)
    ("action" 'font-lock-function-name-face)
    ("reflection" 'font-lock-constant-face)
    (_ 'font-lock-keyword-face)))

(defun sly-autopoiesis--handle-activity (agent-id event-type tool-name timestamp)
  "Handle an activity event (tool-called, tool-result, provider-response)."
  ;; Update agent list if visible
  (when-let ((buf (get-buffer "*autopoiesis-agents*")))
    (when (buffer-live-p buf)
      ;; Trigger a lightweight refresh (debounced by timer)
      (unless sly-autopoiesis--activity-refresh-timer
        (setq sly-autopoiesis--activity-refresh-timer
              (run-with-timer 1 nil #'sly-autopoiesis--activity-refresh-fire)))))
  ;; Push to event log
  (push (list :activity agent-id event-type tool-name timestamp (current-time))
        sly-autopoiesis--event-log)
  (when (> (length sly-autopoiesis--event-log) sly-autopoiesis--event-log-max)
    (setq sly-autopoiesis--event-log
          (cl-subseq sly-autopoiesis--event-log 0 sly-autopoiesis--event-log-max))))

(defvar sly-autopoiesis--activity-refresh-timer nil
  "Debounce timer for activity-triggered agent list refresh.")

(defun sly-autopoiesis--activity-refresh-fire ()
  "Fire debounced activity refresh."
  (setq sly-autopoiesis--activity-refresh-timer nil)
  (sly-autopoiesis--refresh-agents))

(defun sly-autopoiesis--handle-team-event (event-type data)
  "Handle a team coordination event."
  ;; Refresh team list if visible
  (when-let ((buf (get-buffer "*autopoiesis-teams*")))
    (when (buffer-live-p buf)
      (sly-autopoiesis-list-teams)))
  ;; Push to event log
  (push (list :team event-type data (current-time))
        sly-autopoiesis--event-log))

(defun sly-autopoiesis--handle-generic-event (event-type agent-id timestamp)
  "Handle any other event type for the event log."
  (push (list :event event-type agent-id timestamp (current-time))
        sly-autopoiesis--event-log)
  (when (> (length sly-autopoiesis--event-log) sly-autopoiesis--event-log-max)
    (setq sly-autopoiesis--event-log
          (cl-subseq sly-autopoiesis--event-log 0 sly-autopoiesis--event-log-max))))

;;;###autoload
(defun sly-autopoiesis-toggle-event-bridge ()
  "Toggle the real-time event bridge between CL and Emacs."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:*emacs-event-bridge-running*)
    (lambda (running)
      (if running
          (sly-eval-async '(slynk-autopoiesis:stop-emacs-event-bridge)
            (lambda (_) (message "Event bridge stopped")))
        (sly-eval-async '(slynk-autopoiesis:start-emacs-event-bridge)
          (lambda (_) (message "Event bridge started")))))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Snapshot Browser
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis-snapshot-browser-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'sly-autopoiesis-snapshot-detail-at-point)
    (define-key map (kbd "d") #'sly-autopoiesis-snapshot-diff-at-point)
    (define-key map (kbd "g") #'sly-autopoiesis--refresh-snapshots)
    (define-key map (kbd "q") #'quit-window)
    map))

(define-derived-mode sly-autopoiesis-snapshot-browser-mode tabulated-list-mode
  "AP-Snapshots"
  "Major mode for browsing Autopoiesis snapshots."
  (setq tabulated-list-format
        [("ID" 40 t)
         ("Timestamp" 24 t)
         ("Parent" 40 t)
         ("Hash" 16 t)])
  (tabulated-list-init-header)
  (use-local-map (make-composed-keymap sly-autopoiesis-snapshot-browser-mode-map
                                        tabulated-list-mode-map)))

(defun sly-autopoiesis--snapshot-list-entries (snapshots)
  "Convert SNAPSHOTS alists to tabulated-list entries."
  (mapcar (lambda (snap)
            (let ((id (cdr (assq :id snap)))
                  (ts (cdr (assq :timestamp snap)))
                  (parent (cdr (assq :parent snap)))
                  (hash (cdr (assq :hash snap))))
              (list id (vector (or id "?")
                               (or ts "")
                               (or parent "")
                               (or (when hash (substring hash 0 (min 16 (length hash)))) "")))))
          snapshots))

(defun sly-autopoiesis--refresh-snapshots ()
  "Refresh the snapshot browser buffer."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:list-snapshots 100)
    (lambda (snapshots)
      (when-let ((buf (get-buffer "*autopoiesis-snapshots*")))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              (setq tabulated-list-entries
                    (sly-autopoiesis--snapshot-list-entries snapshots))
              (tabulated-list-print t))))))))

;;;###autoload
(defun sly-autopoiesis-snapshot-browser ()
  "Open the Autopoiesis snapshot browser."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:list-snapshots 100)
    (lambda (snapshots)
      (let ((buf (get-buffer-create "*autopoiesis-snapshots*")))
        (with-current-buffer buf
          (sly-autopoiesis-snapshot-browser-mode)
          (setq tabulated-list-entries
                (sly-autopoiesis--snapshot-list-entries snapshots))
          (tabulated-list-print t))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis-snapshot-detail-at-point ()
  "Show detail for the snapshot at point."
  (interactive)
  (let ((snapshot-id (tabulated-list-get-id)))
    (unless snapshot-id (user-error "No snapshot at point"))
    (sly-eval-async `(slynk-autopoiesis:get-snapshot-detail ,snapshot-id)
      (lambda (info)
        (let ((buf (get-buffer-create
                    (format "*autopoiesis-snapshot: %s*"
                            (truncate-string-to-width (or (plist-get info :id) "?") 20)))))
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              (erase-buffer)
              (special-mode)
              (insert (propertize "Snapshot Detail\n\n" 'face 'bold))
              (insert (format "ID:        %s\n" (or (plist-get info :id) "?")))
              (insert (format "Timestamp: %s\n" (or (plist-get info :timestamp) "?")))
              (insert (format "Parent:    %s\n" (or (plist-get info :parent) "none")))
              (insert (format "Hash:      %s\n" (or (plist-get info :hash) "")))
              (insert (format "Metadata:  %s\n\n" (or (plist-get info :metadata) "")))
              (insert (propertize "Agent State:\n" 'face 'bold))
              (insert (or (plist-get info :agent-state) "(empty)"))
              (insert "\n\n[d] diff with parent  [q] quit\n")
              (goto-char (point-min))))
          (pop-to-buffer buf))))))

(defun sly-autopoiesis-snapshot-diff-at-point ()
  "Show diff between snapshot at point and its parent."
  (interactive)
  (let ((snapshot-id (tabulated-list-get-id)))
    (unless snapshot-id (user-error "No snapshot at point"))
    ;; First get the snapshot detail to find its parent
    (sly-eval-async `(slynk-autopoiesis:get-snapshot-detail ,snapshot-id)
      (lambda (info)
        (let ((parent (plist-get info :parent)))
          (if (or (null parent) (equal parent "none") (equal parent ""))
              (message "Snapshot has no parent to diff against")
            (sly-eval-async `(slynk-autopoiesis:snapshot-diff-report ,parent ,snapshot-id)
              (lambda (diff-text)
                (let ((buf (get-buffer-create "*autopoiesis-diff*")))
                  (with-current-buffer buf
                    (let ((inhibit-read-only t))
                      (erase-buffer)
                      (special-mode)
                      (insert (propertize (format "Diff: %s → %s\n\n"
                                                  (truncate-string-to-width parent 20)
                                                  (truncate-string-to-width snapshot-id 20))
                                          'face 'bold))
                      (insert (or diff-text "(no differences)"))
                      (insert "\n\n[q] quit\n")
                      (goto-char (point-min))))
                  (pop-to-buffer buf))))))))))

;;;; ────────────────────────────────────────────────────────────────────
;;;; Branch Manager
;;;; ────────────────────────────────────────────────────────────────────

(defvar sly-autopoiesis-branch-manager-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'sly-autopoiesis-checkout-branch-at-point)
    (define-key map (kbd "c") #'sly-autopoiesis-create-branch)
    (define-key map (kbd "d") #'sly-autopoiesis-diff-branch-at-point)
    (define-key map (kbd "g") #'sly-autopoiesis--refresh-branches)
    (define-key map (kbd "q") #'quit-window)
    map))

(define-derived-mode sly-autopoiesis-branch-manager-mode tabulated-list-mode
  "AP-Branches"
  "Major mode for managing Autopoiesis branches."
  (setq tabulated-list-format
        [("Name" 30 t)
         ("Head" 40 t)
         ("Created" 24 t)])
  (tabulated-list-init-header)
  (use-local-map (make-composed-keymap sly-autopoiesis-branch-manager-mode-map
                                        tabulated-list-mode-map)))

(defun sly-autopoiesis--branch-list-entries (branches)
  "Convert BRANCHES alists to tabulated-list entries."
  (mapcar (lambda (b)
            (let ((name (cdr (assq :name b)))
                  (head (cdr (assq :head b)))
                  (created (cdr (assq :created b))))
              (list name (vector (or name "?")
                                 (or head "")
                                 (or created "")))))
          branches))

(defun sly-autopoiesis--refresh-branches ()
  "Refresh the branch manager buffer."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:list-branches)
    (lambda (branches)
      (when-let ((buf (get-buffer "*autopoiesis-branches*")))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              (setq tabulated-list-entries
                    (sly-autopoiesis--branch-list-entries branches))
              (tabulated-list-print t))))))))

;;;###autoload
(defun sly-autopoiesis-branch-manager ()
  "Open the Autopoiesis branch manager."
  (interactive)
  (sly-eval-async '(slynk-autopoiesis:list-branches)
    (lambda (branches)
      (let ((buf (get-buffer-create "*autopoiesis-branches*")))
        (with-current-buffer buf
          (sly-autopoiesis-branch-manager-mode)
          (setq tabulated-list-entries
                (sly-autopoiesis--branch-list-entries branches))
          (tabulated-list-print t))
        (pop-to-buffer buf)))))

(defun sly-autopoiesis-checkout-branch-at-point ()
  "Checkout the branch at point."
  (interactive)
  (let ((branch-name (tabulated-list-get-id)))
    (unless branch-name (user-error "No branch at point"))
    (sly-eval-async `(slynk-autopoiesis:checkout-branch-rpc ,branch-name)
      (lambda (_result)
        (message "Switched to branch: %s" branch-name)
        (sly-autopoiesis--refresh-branches)))))

(defun sly-autopoiesis-create-branch ()
  "Create a new branch."
  (interactive)
  (let ((name (read-string "Branch name: ")))
    (when (and name (not (string-empty-p name)))
      (sly-eval-async `(slynk-autopoiesis:create-branch-rpc ,name)
        (lambda (_result)
          (message "Created branch: %s" name)
          (sly-autopoiesis--refresh-branches))))))

(defun sly-autopoiesis-diff-branch-at-point ()
  "Diff the branch at point with the current branch."
  (interactive)
  (let ((branch-name (tabulated-list-get-id)))
    (unless branch-name (user-error "No branch at point"))
    ;; Get the head snapshot of the selected branch and diff with current
    (message "Diff for branch %s (not yet implemented)" branch-name)))

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
