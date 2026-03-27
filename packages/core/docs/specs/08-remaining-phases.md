# Autopoiesis: Remaining Phases Specification

## Specification Document 08: Phases 7-10 Detailed Implementation

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

This document provides detailed specifications for completing Phase 7 (2D Visualization) and implementing Phases 8-10. It builds on the existing work and fills gaps in the original roadmap.

---

## Current State Summary

| Phase | Status | Completion |
|-------|--------|------------|
| 7.1 | Package and Foundation | Complete |
| 7.2 | Terminal Timeline Core | Complete |
| 7.3 | Timeline Renderer | Complete |
| 7.4 | Snapshot Detail Panel | Partial (missing thought preview) |
| 7.5 | Navigation Integration | Not Started |
| 7.6 | Interactive Terminal UI | Not Started |
| 7.7 | Branch Visualization | Not Started |
| 7.8 | Tests | Partial |
| 7.9 | Integration and Polish | Not Started |

---

# Phase 7: 2D Visualization (Completion)

## 7.4 Complete: Thought Preview

### render-thought-preview Function

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; detail-panel.lisp additions
;;;; ═══════════════════════════════════════════════════════════════

(defclass thought-preview-state ()
  ((expanded :initarg :expanded
             :accessor preview-expanded-p
             :initform nil
             :documentation "Whether preview is expanded")
   (max-collapsed-lines :initarg :max-collapsed-lines
                        :accessor preview-max-collapsed
                        :initform 3
                        :documentation "Lines to show when collapsed")
   (max-expanded-lines :initarg :max-expanded-lines
                       :accessor preview-max-expanded
                       :initform 20
                       :documentation "Lines to show when expanded")))

(defun make-thought-preview-state (&key expanded (max-collapsed 3) (max-expanded 20))
  "Create thought preview state."
  (make-instance 'thought-preview-state
                 :expanded expanded
                 :max-collapsed-lines max-collapsed
                 :max-expanded-lines max-expanded))

(defun render-thought-preview (snapshot &key (state nil) (width 40))
  "Render thought content from SNAPSHOT with truncation and expand/collapse.

   Arguments:
     snapshot - The snapshot containing agent state
     state    - thought-preview-state for expand/collapse (nil = collapsed)
     width    - Maximum line width for wrapping

   Returns: List of formatted strings for display"
  (let* ((agent-state (snapshot-agent-state snapshot))
         (thoughts (extract-thoughts-from-state agent-state))
         (expanded (and state (preview-expanded-p state)))
         (max-lines (if expanded
                        (and state (preview-max-expanded state))
                        (if state (preview-max-collapsed state) 3))))
    (render-thoughts-truncated thoughts max-lines width)))

(defun extract-thoughts-from-state (agent-state)
  "Extract thought list from serialized agent state.
   Agent state is an s-expression with structure:
   (agent :thought-stream (thought ...) (thought ...) ...)"
  (let ((stream-expr (getf (rest agent-state) :thought-stream)))
    (when (listp stream-expr)
      stream-expr)))

(defun render-thoughts-truncated (thoughts max-lines width)
  "Render THOUGHTS list truncated to MAX-LINES with WIDTH wrapping."
  (let ((lines nil)
        (count 0))
    (dolist (thought thoughts)
      (when (and max-lines (>= count max-lines))
        (push (format nil "... (~d more)" (- (length thoughts) count)) lines)
        (return))
      (let ((thought-lines (format-single-thought thought width)))
        (dolist (line thought-lines)
          (when (and max-lines (>= count max-lines))
            (push "..." lines)
            (return))
          (push line lines)
          (incf count))))
    (nreverse lines)))

(defun format-single-thought (thought width)
  "Format a single thought s-expression for display."
  (let* ((type (or (getf (rest thought) :type) :thought))
         (content (getf (rest thought) :content))
         (content-str (prin1-to-string content))
         (type-prefix (format nil "[~a] " (string-downcase type))))
    (wrap-text (concatenate 'string type-prefix content-str) width)))

(defun wrap-text (text width)
  "Wrap TEXT to WIDTH characters, returning list of lines."
  (let ((lines nil)
        (current-line "")
        (words (split-into-words text)))
    (dolist (word words)
      (cond
        ;; First word on line
        ((zerop (length current-line))
         (setf current-line word))
        ;; Word fits on current line
        ((<= (+ (length current-line) 1 (length word)) width)
         (setf current-line (concatenate 'string current-line " " word)))
        ;; Start new line
        (t
         (push current-line lines)
         (setf current-line (if (> (length word) width)
                                (subseq word 0 (min (length word) width))
                                word)))))
    (when (plusp (length current-line))
      (push current-line lines))
    (nreverse lines)))

(defun split-into-words (text)
  "Split TEXT into words on whitespace."
  (let ((words nil)
        (current-word ""))
    (loop for char across text
          if (member char '(#\Space #\Tab #\Newline))
            do (when (plusp (length current-word))
                 (push current-word words)
                 (setf current-word ""))
          else
            do (setf current-word (concatenate 'string current-word (string char))))
    (when (plusp (length current-word))
      (push current-word words))
    (nreverse words)))
```

---

## 7.5 Navigation Integration

### timeline-navigator Class

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; navigator.lisp - Timeline navigation wrapper
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Navigator Class
;;; ─────────────────────────────────────────────────────────────────

(defclass timeline-navigator ()
  ((timeline :initarg :timeline
             :accessor navigator-timeline
             :documentation "The timeline being navigated")
   (cursor :initarg :cursor
           :accessor navigator-cursor
           :initform 0
           :documentation "Current cursor position (snapshot index)")
   (cursor-branch :initarg :cursor-branch
                  :accessor navigator-cursor-branch
                  :initform "main"
                  :documentation "Current branch name")
   (interface-navigator :initarg :interface-navigator
                        :accessor navigator-interface
                        :initform nil
                        :documentation "Underlying interface layer navigator")
   (store :initarg :store
          :accessor navigator-store
          :initform nil
          :documentation "Snapshot store for loading data"))
  (:documentation "Navigation wrapper for timeline visualization."))

(defun make-timeline-navigator (&key timeline store)
  "Create a timeline navigator."
  (let ((nav (make-instance 'timeline-navigator
                            :timeline (or timeline (make-timeline))
                            :store store
                            :interface-navigator (autopoiesis.interface:make-navigator))))
    (when store
      (sync-timeline-from-store nav))
    nav))

;;; ─────────────────────────────────────────────────────────────────
;;; Cursor Movement
;;; ─────────────────────────────────────────────────────────────────

(defun cursor-left (navigator)
  "Move cursor one snapshot earlier in time."
  (let* ((timeline (navigator-timeline navigator))
         (snaps (get-branch-snapshots timeline (navigator-cursor-branch navigator)))
         (current-idx (navigator-cursor navigator)))
    (when (> current-idx 0)
      (setf (navigator-cursor navigator) (1- current-idx))
      (update-timeline-current navigator)
      t)))

(defun cursor-right (navigator)
  "Move cursor one snapshot later in time."
  (let* ((timeline (navigator-timeline navigator))
         (snaps (get-branch-snapshots timeline (navigator-cursor-branch navigator)))
         (current-idx (navigator-cursor navigator)))
    (when (< current-idx (1- (length snaps)))
      (setf (navigator-cursor navigator) (1+ current-idx))
      (update-timeline-current navigator)
      t)))

(defun cursor-up-branch (navigator)
  "Move cursor to parent branch (if current snapshot is on a child branch)."
  (let* ((timeline (navigator-timeline navigator))
         (branches (get-branch-names timeline))
         (current-branch (navigator-cursor-branch navigator))
         (current-idx (position current-branch branches :test #'string=)))
    (when (and current-idx (> current-idx 0))
      (let ((new-branch (nth (1- current-idx) branches)))
        (setf (navigator-cursor-branch navigator) new-branch)
        (setf (navigator-cursor navigator) 0)
        (update-timeline-current navigator)
        t))))

(defun cursor-down-branch (navigator)
  "Move cursor to child branch (if one exists at current position)."
  (let* ((timeline (navigator-timeline navigator))
         (branches (get-branch-names timeline))
         (current-branch (navigator-cursor-branch navigator))
         (current-idx (position current-branch branches :test #'string=)))
    (when (and current-idx (< current-idx (1- (length branches))))
      (let ((new-branch (nth (1+ current-idx) branches)))
        (setf (navigator-cursor-branch navigator) new-branch)
        (setf (navigator-cursor navigator) 0)
        (update-timeline-current navigator)
        t))))

(defun get-branch-snapshots (timeline branch-name)
  "Get snapshots for a branch, sorted by timestamp."
  (let ((snap-ids (gethash branch-name (timeline-branches timeline))))
    (sort (mapcar (lambda (id) (find-snapshot timeline id)) snap-ids)
          #'< :key #'snapshot-timestamp)))

(defun get-branch-names (timeline)
  "Get sorted list of branch names."
  (let ((names nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             (timeline-branches timeline))
    (sort names #'string<)))

(defun update-timeline-current (navigator)
  "Update timeline-current to match cursor position."
  (let* ((timeline (navigator-timeline navigator))
         (snaps (get-branch-snapshots timeline (navigator-cursor-branch navigator)))
         (snap (nth (navigator-cursor navigator) snaps)))
    (when snap
      (setf (timeline-current timeline) (snapshot-id snap))
      ;; Also update interface navigator
      (when (navigator-interface navigator)
        (autopoiesis.interface:navigate-to
         (navigator-interface navigator)
         (snapshot-id snap))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Jump Navigation
;;; ─────────────────────────────────────────────────────────────────

(defun jump-to-snapshot (navigator snapshot-id)
  "Jump directly to a snapshot by ID."
  (let* ((timeline (navigator-timeline navigator))
         (snap (find-snapshot timeline snapshot-id)))
    (when snap
      ;; Find which branch contains this snapshot
      (maphash (lambda (branch-name snap-ids)
                 (when (member snapshot-id snap-ids :test #'string=)
                   (setf (navigator-cursor-branch navigator) branch-name)
                   (let ((snaps (get-branch-snapshots timeline branch-name)))
                     (setf (navigator-cursor navigator)
                           (position snapshot-id snaps
                                     :key #'snapshot-id :test #'string=)))))
               (timeline-branches timeline))
      (update-timeline-current navigator)
      t)))

(defun jump-to-genesis (navigator)
  "Jump to the genesis (first) snapshot."
  (setf (navigator-cursor navigator) 0)
  (setf (navigator-cursor-branch navigator) "main")
  (update-timeline-current navigator))

(defun jump-to-head (navigator)
  "Jump to the head (latest) snapshot on current branch."
  (let* ((timeline (navigator-timeline navigator))
         (snaps (get-branch-snapshots timeline (navigator-cursor-branch navigator))))
    (setf (navigator-cursor navigator) (1- (length snaps)))
    (update-timeline-current navigator)))

;;; ─────────────────────────────────────────────────────────────────
;;; Search
;;; ─────────────────────────────────────────────────────────────────

(defun search-snapshots (navigator query &key (type nil) (direction :forward))
  "Search for snapshots matching QUERY.

   Arguments:
     navigator - The timeline navigator
     query     - String to search in snapshot content
     type      - Optional snapshot type filter (:decision, :action, etc.)
     direction - :forward or :backward from current position

   Returns: List of matching snapshot IDs"
  (let* ((timeline (navigator-timeline navigator))
         (all-snaps (timeline-snapshots timeline))
         (results nil))
    (dolist (snap all-snaps)
      (when (snapshot-matches-p snap query type)
        (push (snapshot-id snap) results)))
    (if (eq direction :backward)
        results
        (nreverse results))))

(defun snapshot-matches-p (snapshot query type)
  "Check if SNAPSHOT matches search criteria."
  (let ((meta-type (getf (snapshot-metadata snapshot) :type)))
    (and (or (null type) (eq type meta-type))
         (or (null query)
             (search query (prin1-to-string (snapshot-agent-state snapshot))
                     :test #'char-equal)))))

(defun search-next (navigator query &key type)
  "Find and jump to next matching snapshot."
  (let* ((matches (search-snapshots navigator query :type type :direction :forward))
         (current-id (timeline-current (navigator-timeline navigator)))
         (found-current nil))
    (dolist (id matches)
      (when found-current
        (jump-to-snapshot navigator id)
        (return-from search-next t))
      (when (string= id current-id)
        (setf found-current t)))
    nil))

(defun search-previous (navigator query &key type)
  "Find and jump to previous matching snapshot."
  (let* ((matches (search-snapshots navigator query :type type :direction :backward))
         (current-id (timeline-current (navigator-timeline navigator)))
         (found-current nil))
    (dolist (id matches)
      (when found-current
        (jump-to-snapshot navigator id)
        (return-from search-previous t))
      (when (string= id current-id)
        (setf found-current t)))
    nil))

;;; ─────────────────────────────────────────────────────────────────
;;; Store Synchronization
;;; ─────────────────────────────────────────────────────────────────

(defun sync-timeline-from-store (navigator)
  "Load timeline data from snapshot store."
  (let ((store (navigator-store navigator))
        (timeline (navigator-timeline navigator)))
    (when store
      ;; Load all snapshots
      (let ((snap-ids (autopoiesis.snapshot:list-snapshots :store store)))
        (setf (timeline-snapshots timeline)
              (mapcar (lambda (id)
                        (autopoiesis.snapshot:load-snapshot id store))
                      snap-ids)))
      ;; Build branch map
      (rebuild-branch-map timeline)
      ;; Set current to head of main branch
      (let ((main-snaps (get-branch-snapshots timeline "main")))
        (when main-snaps
          (setf (timeline-current timeline)
                (snapshot-id (car (last main-snaps)))))))))

(defun rebuild-branch-map (timeline)
  "Rebuild the branches hash table from snapshot parent relationships."
  (let ((branches (make-hash-table :test #'equal)))
    ;; Start with all root snapshots on "main"
    (dolist (snap (timeline-snapshots timeline))
      (unless (snapshot-parent snap)
        (push (snapshot-id snap) (gethash "main" branches))))
    ;; Add children to appropriate branches
    ;; (simplified - full implementation would track branch metadata)
    (dolist (snap (timeline-snapshots timeline))
      (when (snapshot-parent snap)
        ;; For now, add all to main branch
        ;; TODO: Track actual branch assignments from metadata
        (push (snapshot-id snap) (gethash "main" branches))))
    (setf (timeline-branches timeline) branches)))
```

---

## 7.6 Interactive Terminal UI

### terminal-ui Class and Main Loop

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; terminal-ui.lisp - Interactive terminal interface
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Terminal UI Class
;;; ─────────────────────────────────────────────────────────────────

(defclass terminal-ui ()
  ((navigator :initarg :navigator
              :accessor ui-navigator
              :documentation "Timeline navigator")
   (timeline :initarg :timeline
             :accessor ui-timeline
             :documentation "Timeline being displayed")
   (detail-panel :initarg :detail-panel
                 :accessor ui-detail-panel
                 :initform nil
                 :documentation "Detail panel for selected snapshot")
   (status-message :initarg :status-message
                   :accessor ui-status-message
                   :initform ""
                   :documentation "Status bar message")
   (running-p :initarg :running-p
              :accessor ui-running-p
              :initform nil
              :documentation "Whether UI is running")
   (mode :initarg :mode
         :accessor ui-mode
         :initform :normal
         :documentation ":normal :search :help")
   (search-query :initarg :search-query
                 :accessor ui-search-query
                 :initform ""
                 :documentation "Current search query")
   (input-buffer :initarg :input-buffer
                 :accessor ui-input-buffer
                 :initform ""
                 :documentation "Input buffer for commands")
   (refresh-needed :initarg :refresh-needed
                   :accessor ui-refresh-needed
                   :initform t
                   :documentation "Flag for screen refresh"))
  (:documentation "Interactive terminal UI for timeline visualization."))

(defun make-terminal-ui (&key navigator timeline store)
  "Create a terminal UI instance."
  (let* ((tl (or timeline (make-timeline)))
         (nav (or navigator (make-timeline-navigator :timeline tl :store store))))
    (make-instance 'terminal-ui
                   :navigator nav
                   :timeline tl
                   :detail-panel (make-detail-panel))))

;;; ─────────────────────────────────────────────────────────────────
;;; Input Handling
;;; ─────────────────────────────────────────────────────────────────

(defparameter *key-bindings*
  '(;; Navigation
    (#\h . :cursor-left)
    (#\l . :cursor-right)
    (#\j . :cursor-down-branch)
    (#\k . :cursor-up-branch)
    (#\g . :jump-to-genesis)
    (#\G . :jump-to-head)
    ;; View control
    (#\+ . :expand-detail)
    (#\- . :collapse-detail)
    (#\Return . :select-snapshot)
    ;; Search
    (#\/ . :enter-search)
    (#\n . :search-next)
    (#\N . :search-previous)
    ;; Help and quit
    (#\? . :toggle-help)
    (#\q . :quit))
  "Default key bindings for terminal UI.")

(defun handle-input (ui char)
  "Handle a single character input."
  (case (ui-mode ui)
    (:normal (handle-normal-input ui char))
    (:search (handle-search-input ui char))
    (:help (handle-help-input ui char))))

(defun handle-normal-input (ui char)
  "Handle input in normal mode."
  (let ((action (cdr (assoc char *key-bindings*))))
    (case action
      (:cursor-left
       (cursor-left (ui-navigator ui))
       (setf (ui-refresh-needed ui) t))
      (:cursor-right
       (cursor-right (ui-navigator ui))
       (setf (ui-refresh-needed ui) t))
      (:cursor-down-branch
       (cursor-down-branch (ui-navigator ui))
       (setf (ui-refresh-needed ui) t))
      (:cursor-up-branch
       (cursor-up-branch (ui-navigator ui))
       (setf (ui-refresh-needed ui) t))
      (:jump-to-genesis
       (jump-to-genesis (ui-navigator ui))
       (setf (ui-refresh-needed ui) t))
      (:jump-to-head
       (jump-to-head (ui-navigator ui))
       (setf (ui-refresh-needed ui) t))
      (:expand-detail
       (when (ui-detail-panel ui)
         ;; Expand detail level
         ))
      (:collapse-detail
       (when (ui-detail-panel ui)
         ;; Collapse detail level
         ))
      (:select-snapshot
       (setf (ui-status-message ui)
             (format nil "Selected: ~a"
                     (timeline-current (ui-timeline ui)))))
      (:enter-search
       (setf (ui-mode ui) :search)
       (setf (ui-search-query ui) "")
       (setf (ui-status-message ui) "Search: "))
      (:search-next
       (search-next (ui-navigator ui) (ui-search-query ui))
       (setf (ui-refresh-needed ui) t))
      (:search-previous
       (search-previous (ui-navigator ui) (ui-search-query ui))
       (setf (ui-refresh-needed ui) t))
      (:toggle-help
       (setf (ui-mode ui) :help)
       (setf (ui-refresh-needed ui) t))
      (:quit
       (setf (ui-running-p ui) nil)))))

(defun handle-search-input (ui char)
  "Handle input in search mode."
  (cond
    ((char= char #\Return)
     ;; Execute search
     (search-next (ui-navigator ui) (ui-search-query ui))
     (setf (ui-mode ui) :normal)
     (setf (ui-refresh-needed ui) t))
    ((char= char #\Escape)
     ;; Cancel search
     (setf (ui-mode ui) :normal)
     (setf (ui-search-query ui) "")
     (setf (ui-status-message ui) ""))
    ((char= char #\Backspace)
     ;; Delete character
     (when (plusp (length (ui-search-query ui)))
       (setf (ui-search-query ui)
             (subseq (ui-search-query ui) 0 (1- (length (ui-search-query ui)))))
       (setf (ui-status-message ui)
             (format nil "Search: ~a" (ui-search-query ui)))))
    ((graphic-char-p char)
     ;; Add character to query
     (setf (ui-search-query ui)
           (concatenate 'string (ui-search-query ui) (string char)))
     (setf (ui-status-message ui)
           (format nil "Search: ~a" (ui-search-query ui))))))

(defun handle-help-input (ui char)
  "Handle input in help mode."
  (declare (ignore char))
  ;; Any key exits help
  (setf (ui-mode ui) :normal)
  (setf (ui-refresh-needed ui) t))

;;; ─────────────────────────────────────────────────────────────────
;;; Display Rendering
;;; ─────────────────────────────────────────────────────────────────

(defun refresh-display (ui)
  "Refresh the entire terminal display."
  (clear-screen)

  (case (ui-mode ui)
    (:help
     (render-help-overlay))
    (t
     ;; Normal display
     (render-header ui)
     (render-timeline (ui-timeline ui))
     (render-detail-section ui)
     (render-status-bar ui)))

  (force-output)
  (setf (ui-refresh-needed ui) nil))

(defun render-header (ui)
  "Render the header bar."
  (move-cursor 1 1)
  (with-color (+color-border+)
    (format t "AUTOPOIESIS TIMELINE"))
  (let* ((branch (navigator-cursor-branch (ui-navigator ui)))
         (branch-str (format nil "Branch: ~a" branch)))
    (move-cursor 1 (- (get-terminal-width) (length branch-str)))
    (format t "~a" branch-str)))

(defun render-detail-section (ui)
  "Render the detail panel for selected snapshot."
  (let* ((timeline (ui-timeline ui))
         (current-id (timeline-current timeline))
         (snap (when current-id (find-snapshot timeline current-id))))
    (when snap
      (let ((summary-lines (render-snapshot-summary snap))
            (start-row 15))
        (move-cursor start-row 1)
        (with-color (+color-border+)
          (draw-horizontal-line start-row 1 (get-terminal-width)))
        (loop for line in summary-lines
              for row from (1+ start-row)
              do (move-cursor row 2)
                 (princ line))))))

(defun render-status-bar (ui)
  "Render the status bar at bottom of screen."
  (let ((row (get-terminal-height)))
    (move-cursor row 1)
    (with-color (+color-dim+)
      ;; Clear line
      (format t "~v@a" (get-terminal-width) ""))
    (move-cursor row 1)

    ;; Mode indicator
    (with-color (+color-highlight+)
      (format t "[~a]" (string-upcase (ui-mode ui))))

    ;; Status message
    (format t " ~a" (ui-status-message ui))

    ;; Help hint (right aligned)
    (let ((hint "Press ? for help"))
      (move-cursor row (- (get-terminal-width) (length hint)))
      (with-color (+color-dim+)
        (princ hint)))))

(defun render-help-overlay ()
  "Render the help overlay."
  (clear-screen)
  (move-cursor 2 2)
  (with-color (+color-highlight+)
    (princ "KEYBOARD SHORTCUTS"))

  (let ((help-items
         '(("Navigation" . (("h/l" . "Move left/right")
                            ("j/k" . "Move down/up branch")
                            ("g" . "Go to beginning")
                            ("G" . "Go to end")))
           ("View" . (("+" . "Expand detail")
                      ("-" . "Collapse detail")
                      ("Enter" . "Select snapshot")))
           ("Search" . (("/" . "Start search")
                        ("n" . "Next match")
                        ("N" . "Previous match")))
           ("Other" . (("?" . "Toggle help")
                       ("q" . "Quit"))))))
    (let ((row 4))
      (dolist (section help-items)
        (move-cursor row 2)
        (with-color (+color-text+)
          (format t "~a:" (car section)))
        (incf row)
        (dolist (item (cdr section))
          (move-cursor row 4)
          (with-color (+color-highlight+)
            (format t "~6a" (car item)))
          (format t " ~a" (cdr item))
          (incf row))
        (incf row))))

  (move-cursor (- (get-terminal-height) 2) 2)
  (with-color (+color-dim+)
    (princ "Press any key to continue...")))

;;; ─────────────────────────────────────────────────────────────────
;;; Main Loop
;;; ─────────────────────────────────────────────────────────────────

(defun run-terminal-ui (ui)
  "Run the interactive terminal UI main loop."
  (setf (ui-running-p ui) t)
  (with-terminal
    (hide-cursor)
    (refresh-display ui)

    (loop while (ui-running-p ui)
          do (let ((char (read-char-no-hang *standard-input* nil nil)))
               (when char
                 (handle-input ui char))
               (when (ui-refresh-needed ui)
                 (refresh-display ui))
               ;; Small sleep to prevent CPU spinning
               (sleep 0.01)))

    (show-cursor)
    (clear-screen)))

(defun stop-terminal-ui (ui)
  "Stop the terminal UI."
  (setf (ui-running-p ui) nil))

;;; ─────────────────────────────────────────────────────────────────
;;; Entry Point
;;; ─────────────────────────────────────────────────────────────────

(defun visualize-timeline (&key store)
  "Launch the interactive timeline visualization.

   Arguments:
     store - Optional snapshot store to load from

   Example:
     (visualize-timeline :store *snapshot-store*)"
  (let ((ui (make-terminal-ui :store store)))
    (run-terminal-ui ui)))
```

---

## 7.7 Branch Visualization

### Branch Layout Algorithm

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; branch-layout.lisp - Branch positioning and labels
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Branch Layout
;;; ─────────────────────────────────────────────────────────────────

(defclass branch-layout ()
  ((branch-name :initarg :branch-name
                :accessor layout-branch-name)
   (y-position :initarg :y-position
               :accessor layout-y-position
               :documentation "Row number for this branch")
   (fork-col :initarg :fork-col
             :accessor layout-fork-col
             :documentation "Column where branch forks from parent")
   (parent-branch :initarg :parent-branch
                  :accessor layout-parent-branch
                  :initform nil
                  :documentation "Name of parent branch")))

(defun compute-branch-layout (timeline)
  "Compute y-positions for all branches.

   Returns: Hash table mapping branch-name -> branch-layout object

   Algorithm:
   1. Main branch gets y-position 0 (topmost)
   2. Child branches get incrementing y-positions
   3. Fork columns are computed from parent snapshot positions"
  (let ((layouts (make-hash-table :test #'equal))
        (y-pos 0))

    ;; Main branch first
    (setf (gethash "main" layouts)
          (make-instance 'branch-layout
                         :branch-name "main"
                         :y-position y-pos
                         :fork-col 0
                         :parent-branch nil))
    (incf y-pos)

    ;; Other branches
    (maphash (lambda (branch-name snap-ids)
               (unless (string= branch-name "main")
                 (let* ((first-snap-id (first snap-ids))
                        (first-snap (find-snapshot timeline first-snap-id))
                        (parent-id (when first-snap (snapshot-parent first-snap)))
                        (fork-col (when parent-id
                                    (compute-snapshot-column timeline parent-id))))
                   (setf (gethash branch-name layouts)
                         (make-instance 'branch-layout
                                        :branch-name branch-name
                                        :y-position y-pos
                                        :fork-col (or fork-col 0)
                                        :parent-branch "main")) ; simplified
                   (incf y-pos))))
             (timeline-branches timeline))

    layouts))

(defun compute-snapshot-column (timeline snapshot-id)
  "Compute the display column for a snapshot."
  (let* ((snaps (timeline-snapshots timeline))
         (sorted (sort (copy-seq snaps) #'< :key #'snapshot-timestamp))
         (snap (find snapshot-id sorted :key #'snapshot-id :test #'string=))
         (idx (position snap sorted)))
    (when idx
      ;; Same calculation as render-timeline-row
      (let ((num-slots 20)
            (slot-width 4))
        (+ 2 (* (floor (* idx (/ num-slots (max 1 (1- (length sorted))))))
                slot-width))))))

(defun branch-y-position (branch-name layouts)
  "Get the y-position (row offset) for a branch."
  (let ((layout (gethash branch-name layouts)))
    (if layout
        (layout-y-position layout)
        0)))

;;; ─────────────────────────────────────────────────────────────────
;;; Branch Labels
;;; ─────────────────────────────────────────────────────────────────

(defun render-branch-labels (timeline layouts &key (start-row 5))
  "Render branch name labels at fork points."
  (maphash (lambda (branch-name layout)
             (unless (string= branch-name "main")
               (let ((row (+ start-row (layout-y-position layout) 1))
                     (col (+ (layout-fork-col layout) 3)))
                 (move-cursor row col)
                 (with-color (+color-dim+)
                   (format t "(~a)" (truncate-string branch-name 12))))))
           layouts))

(defun render-timeline-with-branches (timeline)
  "Render full timeline with branch layout."
  (let ((layouts (compute-branch-layout timeline)))
    ;; Render legend
    (render-legend 1)

    ;; Render main branch
    (render-timeline-row timeline 5)

    ;; Render branch connections and labels
    (render-branch-connections timeline 6)
    (render-branch-labels timeline layouts :start-row 5)

    ;; Render child branch rows
    (maphash (lambda (branch-name layout)
               (unless (string= branch-name "main")
                 (let ((row (+ 6 (layout-y-position layout))))
                   (render-branch-row timeline branch-name row
                                      (layout-fork-col layout)))))
             layouts)))

(defun render-branch-row (timeline branch-name row start-col)
  "Render a child branch starting at START-COL."
  (let* ((snap-ids (gethash branch-name (timeline-branches timeline)))
         (snaps (mapcar (lambda (id) (find-snapshot timeline id)) snap-ids))
         (sorted (sort snaps #'< :key #'snapshot-timestamp))
         (num-snaps (length sorted)))

    ;; Draw branch line
    (move-cursor row start-col)
    (with-color (+color-border+)
      (princ +branch-corner-down-right+)
      (loop repeat (min 40 (* 4 num-snaps))
            do (princ +branch-horizontal+)))

    ;; Draw snapshot nodes
    (loop for snap in sorted
          for i from 0
          for col = (+ start-col 1 (* i 4))
          do (render-snapshot-node timeline row col snap))))
```

---

## 7.8 Tests (Completion)

### Navigation Tests

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; viz-tests.lisp additions - Navigation tests
;;;; ═══════════════════════════════════════════════════════════════

(in-suite viz-tests)

;;; Navigation Tests

(test timeline-navigator-creation
  "Test timeline navigator creation"
  (let* ((timeline (autopoiesis.viz:make-timeline))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))
    (is-true nav)
    (is (= 0 (autopoiesis.viz::navigator-cursor nav)))
    (is (string= "main" (autopoiesis.viz::navigator-cursor-branch nav)))))

(test cursor-movement-left-right
  "Test cursor left/right movement"
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-001"
                               :timestamp 1.0
                               :metadata '(:type :snapshot)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-002"
                               :timestamp 2.0
                               :parent "snap-001"
                               :metadata '(:type :decision)))
         (snap3 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-003"
                               :timestamp 3.0
                               :parent "snap-002"
                               :metadata '(:type :action)))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap1 snap2 snap3)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))

    ;; Setup branches
    (setf (gethash "main" (autopoiesis.viz:timeline-branches timeline))
          '("snap-001" "snap-002" "snap-003"))

    ;; Start at position 0
    (is (= 0 (autopoiesis.viz::navigator-cursor nav)))

    ;; Move right
    (autopoiesis.viz:cursor-right nav)
    (is (= 1 (autopoiesis.viz::navigator-cursor nav)))

    ;; Move right again
    (autopoiesis.viz:cursor-right nav)
    (is (= 2 (autopoiesis.viz::navigator-cursor nav)))

    ;; Can't move past end
    (autopoiesis.viz:cursor-right nav)
    (is (= 2 (autopoiesis.viz::navigator-cursor nav)))

    ;; Move left
    (autopoiesis.viz:cursor-left nav)
    (is (= 1 (autopoiesis.viz::navigator-cursor nav)))))

(test jump-to-snapshot
  "Test jumping to specific snapshot"
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-111"
                               :timestamp 1.0))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-222"
                               :timestamp 2.0
                               :parent "snap-111"))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap1 snap2)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))

    (setf (gethash "main" (autopoiesis.viz:timeline-branches timeline))
          '("snap-111" "snap-222"))

    ;; Jump to second snapshot
    (autopoiesis.viz:jump-to-snapshot nav "snap-222")
    (is (= 1 (autopoiesis.viz::navigator-cursor nav)))
    (is (string= "snap-222"
                 (autopoiesis.viz:timeline-current timeline)))))

(test search-snapshots
  "Test snapshot search functionality"
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-a"
                               :timestamp 1.0
                               :agent-state '(task "fix bug")
                               :metadata '(:type :action)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap-b"
                               :timestamp 2.0
                               :agent-state '(task "add feature")
                               :metadata '(:type :decision)))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap1 snap2)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))

    (setf (gethash "main" (autopoiesis.viz:timeline-branches timeline))
          '("snap-a" "snap-b"))

    ;; Search for "bug"
    (let ((results (autopoiesis.viz:search-snapshots nav "bug")))
      (is (= 1 (length results)))
      (is (string= "snap-a" (first results))))

    ;; Search by type
    (let ((results (autopoiesis.viz:search-snapshots nav nil :type :decision)))
      (is (= 1 (length results)))
      (is (string= "snap-b" (first results))))))

(test branch-layout-computation
  "Test branch layout algorithm"
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "main-1" :timestamp 1.0))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "main-2" :timestamp 2.0 :parent "main-1"))
         (snap3 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "branch-1" :timestamp 2.5 :parent "main-1"))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap1 snap2 snap3))))

    (setf (gethash "main" (autopoiesis.viz:timeline-branches timeline))
          '("main-1" "main-2"))
    (setf (gethash "feature" (autopoiesis.viz:timeline-branches timeline))
          '("branch-1"))

    (let ((layouts (autopoiesis.viz::compute-branch-layout timeline)))
      ;; Main branch at y=0
      (is (= 0 (autopoiesis.viz::branch-y-position "main" layouts)))
      ;; Feature branch at y=1
      (is (= 1 (autopoiesis.viz::branch-y-position "feature" layouts))))))
```

---

## 7.9 Integration and Polish

### Integration with Session System

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; viz-integration.lisp - Integration with interface/session
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Session Integration
;;; ─────────────────────────────────────────────────────────────────

(defun start-visual-session (session)
  "Start visual timeline mode for an existing session."
  (let* ((store (or autopoiesis.snapshot:*snapshot-store*
                    (autopoiesis.snapshot:make-content-store
                     (uiop:merge-pathnames* "snapshots/"
                                            (user-homedir-pathname)))))
         (ui (make-terminal-ui :store store)))
    ;; Link session navigator to UI navigator
    (when (autopoiesis.interface:session-navigator session)
      (setf (navigator-interface (ui-navigator ui))
            (autopoiesis.interface:session-navigator session)))
    (run-terminal-ui ui)))

;;; ─────────────────────────────────────────────────────────────────
;;; Resize Handling
;;; ─────────────────────────────────────────────────────────────────

(defvar *previous-terminal-size* nil)

(defun check-terminal-resize (ui)
  "Check if terminal was resized and trigger refresh."
  (let ((current-size (multiple-value-list (get-terminal-size))))
    (unless (equal current-size *previous-terminal-size*)
      (setf *previous-terminal-size* current-size)
      (setf (ui-refresh-needed ui) t)
      ;; Update viewport dimensions
      (let ((vp (timeline-viewport (ui-timeline ui))))
        (setf (viewport-width vp) (first current-size))
        (setf (viewport-height vp) (second current-size))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Help Overlay
;;; ─────────────────────────────────────────────────────────────────

(defun toggle-help (ui)
  "Toggle help overlay visibility."
  (setf (ui-mode ui)
        (if (eq (ui-mode ui) :help) :normal :help))
  (setf (ui-refresh-needed ui) t))

;;; ─────────────────────────────────────────────────────────────────
;;; ASDF Integration
;;; ─────────────────────────────────────────────────────────────────

;; Add to autopoiesis.asd under viz module:
;; (:file "branch-layout")
;; (:file "navigator")
;; (:file "terminal-ui")
;; (:file "viz-integration")
```

---

# Phase 8: 3D Holodeck

## Overview

Phase 8 implements the full 3D "Jarvis-style" visualization as specified in `docs/specs/05-visualization.md`. This phase depends on Phase 7 completion.

## Technology Selection

### Graphics Engine

**Recommended: Trial Engine**

Trial is a modern OpenGL-based game engine written in Common Lisp.

```lisp
;; Add to autopoiesis.asd
:depends-on (...
             trial
             3d-matrices
             3d-vectors)
```

**Alternative: cl-raylib**

Raylib bindings for simpler 3D rendering.

### ECS Library

**Recommended: cl-fast-ecs**

```lisp
:depends-on (...
             cl-fast-ecs)
```

## 8.1 ECS Setup

### Component Definitions

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; ecs/components.lisp - ECS component definitions
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz.ecs)

(ecs:defcomponent position
  "Position in 3D cognitive space"
  (x 0.0 :type single-float)
  (y 0.0 :type single-float)
  (z 0.0 :type single-float))

(ecs:defcomponent velocity
  "Movement velocity for animated entities"
  (dx 0.0 :type single-float)
  (dy 0.0 :type single-float)
  (dz 0.0 :type single-float))

(ecs:defcomponent scale
  "Size scaling"
  (sx 1.0 :type single-float)
  (sy 1.0 :type single-float)
  (sz 1.0 :type single-float))

(ecs:defcomponent snapshot-binding
  "Links entity to snapshot data"
  (snapshot-id "" :type string)
  (snapshot-type :snapshot :type keyword))

(ecs:defcomponent visual-style
  "Visual appearance properties"
  (node-type :snapshot :type keyword)
  (base-color #(0.3 0.6 1.0 0.8) :type vector)
  (glow-intensity 1.0 :type single-float)
  (pulse-rate 0.0 :type single-float))

(ecs:defcomponent connection
  "Connection between two entities"
  (from-entity 0 :type fixnum)
  (to-entity 0 :type fixnum)
  (connection-type :parent-child :type keyword))

(ecs:defcomponent interactive
  "Entity can be interacted with"
  (hover-p nil :type boolean)
  (selected-p nil :type boolean)
  (click-action nil :type (or null function)))

(ecs:defcomponent label
  "Text label for entity"
  (text "" :type string)
  (visible-p t :type boolean)
  (offset-y 1.5 :type single-float))

(ecs:defcomponent lod
  "Level of detail control"
  (current-level :high :type keyword)
  (low-distance 100.0 :type single-float)
  (cull-distance 200.0 :type single-float))
```

### System Definitions

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; ecs/systems.lisp - ECS system definitions
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz.ecs)

;;; Layout System - positions entities based on snapshot data
(ecs:defsystem layout-system
  (:components (position snapshot-binding))
  (let* ((snap-id (snapshot-binding-snapshot-id entity))
         (snap (load-snapshot-for-viz snap-id))
         (pos (snapshot-to-position snap)))
    (setf (position-x entity) (vec3-x pos))
    (setf (position-y entity) (vec3-y pos))
    (setf (position-z entity) (vec3-z pos))))

;;; Movement System - updates positions based on velocity
(ecs:defsystem movement-system
  (:components (position velocity))
  (incf (position-x entity) (* (velocity-dx entity) *delta-time*))
  (incf (position-y entity) (* (velocity-dy entity) *delta-time*))
  (incf (position-z entity) (* (velocity-dz entity) *delta-time*)))

;;; Pulse System - animated pulsing effect
(ecs:defsystem pulse-system
  (:components (visual-style scale))
  (when (plusp (visual-style-pulse-rate entity))
    (let ((pulse (+ 1.0 (* 0.1 (sin (* *time* (visual-style-pulse-rate entity)))))))
      (setf (scale-sx entity) pulse)
      (setf (scale-sy entity) pulse)
      (setf (scale-sz entity) pulse))))

;;; LOD System - level of detail based on camera distance
(ecs:defsystem lod-system
  (:components (position lod))
  (let ((dist (distance-to-camera (position-x entity)
                                  (position-y entity)
                                  (position-z entity))))
    (setf (lod-current-level entity)
          (cond
            ((> dist (lod-cull-distance entity)) :culled)
            ((> dist (lod-low-distance entity)) :low)
            (t :high)))))

;;; Interaction System - handles hover and selection
(ecs:defsystem interaction-system
  (:components (position interactive))
  (let ((mouse-ray (get-mouse-ray)))
    (when (ray-intersects-entity-p mouse-ray entity)
      (setf (interactive-hover-p entity) t)
      (when (mouse-clicked-p)
        (setf (interactive-selected-p entity) t)
        (when (interactive-click-action entity)
          (funcall (interactive-click-action entity) entity))))))
```

## 8.2 Rendering

### Window and Scene Setup

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; render/window.lisp - Window and OpenGL setup
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz.render)

(defparameter *window-width* 1920)
(defparameter *window-height* 1080)
(defparameter *window-title* "Autopoiesis Holodeck")

(defclass holodeck-window (trial:main)
  ((scene :initform nil :accessor holodeck-scene)
   (camera :initform nil :accessor holodeck-camera)
   (hud :initform nil :accessor holodeck-hud))
  (:default-initargs
   :width *window-width*
   :height *window-height*
   :title *window-title*))

(defmethod trial:setup-scene ((window holodeck-window))
  ;; Initialize scene
  (setf (holodeck-scene window) (make-instance 'trial:scene))

  ;; Initialize camera
  (setf (holodeck-camera window)
        (make-instance 'orbit-camera
                       :location (vec3 0 10 50)
                       :target (vec3 0 0 0)))

  ;; Load shaders
  (load-holodeck-shaders)

  ;; Initialize HUD
  (setf (holodeck-hud window) (make-hud)))

(defun load-holodeck-shaders ()
  "Load holographic shader programs."
  (trial:define-shader-program hologram-node
    (:vertex-shader "
      #version 330 core
      layout(location = 0) in vec3 position;
      layout(location = 1) in vec3 normal;
      uniform mat4 model;
      uniform mat4 view;
      uniform mat4 projection;
      out vec3 fragNormal;
      out vec3 fragPosition;
      void main() {
        fragPosition = vec3(model * vec4(position, 1.0));
        fragNormal = mat3(transpose(inverse(model))) * normal;
        gl_Position = projection * view * vec4(fragPosition, 1.0);
      }")
    (:fragment-shader "
      #version 330 core
      in vec3 fragNormal;
      in vec3 fragPosition;
      uniform vec3 viewPos;
      uniform vec4 baseColor;
      uniform float glowIntensity;
      uniform float time;
      out vec4 fragColor;

      void main() {
        // Fresnel effect for holographic edge glow
        vec3 viewDir = normalize(viewPos - fragPosition);
        float fresnel = pow(1.0 - max(dot(normalize(fragNormal), viewDir), 0.0), 3.0);

        // Scanline effect
        float scanline = sin(fragPosition.y * 50.0 + time * 2.0) * 0.5 + 0.5;
        scanline = mix(0.8, 1.0, scanline);

        // Combine effects
        vec3 color = baseColor.rgb * scanline;
        color += vec3(0.3, 0.6, 1.0) * fresnel * glowIntensity;

        fragColor = vec4(color, baseColor.a + fresnel * 0.3);
      }")))
```

### Entity Rendering

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; render/entities.lisp - Entity rendering
;;;; ═══════════════════════════════════════════════════════════════

(defun render-snapshot-entity (entity)
  "Render a snapshot node entity."
  (when (not (eq (lod-current-level entity) :culled))
    (let* ((pos (entity-position entity))
           (scale (entity-scale entity))
           (style (entity-visual-style entity))
           (model-matrix (compute-model-matrix pos scale)))

      ;; Use hologram shader
      (trial:with-shader-program 'hologram-node
        (trial:uniform "model" model-matrix)
        (trial:uniform "baseColor" (visual-style-base-color style))
        (trial:uniform "glowIntensity" (visual-style-glow-intensity style))
        (trial:uniform "time" *time*)

        ;; Draw appropriate mesh based on node type
        (case (visual-style-node-type style)
          (:snapshot (draw-sphere-mesh))
          (:decision (draw-octahedron-mesh))
          (:fork (draw-branching-mesh))
          (:merge (draw-merge-mesh))
          (:human (draw-human-icon-mesh))
          (t (draw-sphere-mesh)))))))

(defun render-connection-entity (entity)
  "Render a connection beam between entities."
  (let* ((conn (entity-connection entity))
         (from-pos (entity-position (ecs:get-entity (connection-from-entity conn))))
         (to-pos (entity-position (ecs:get-entity (connection-to-entity conn)))))

    (trial:with-shader-program 'energy-beam
      (trial:uniform "startPos" from-pos)
      (trial:uniform "endPos" to-pos)
      (trial:uniform "time" *time*)
      (trial:uniform "flowSpeed" 2.0)
      (draw-beam-quad from-pos to-pos))))
```

## 8.3 Camera System

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; camera.lisp - Camera modes and control
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

(defclass camera ()
  ((position :initarg :position :accessor camera-position
             :initform (vec3 0 10 50))
   (target :initarg :target :accessor camera-target
           :initform (vec3 0 0 0))
   (up :initarg :up :accessor camera-up
       :initform (vec3 0 1 0))
   (fov :initarg :fov :accessor camera-fov
        :initform 60.0)
   (near :initarg :near :accessor camera-near
         :initform 0.1)
   (far :initarg :far :accessor camera-far
        :initform 1000.0)))

(defclass orbit-camera (camera)
  ((distance :initarg :distance :accessor orbit-distance
             :initform 50.0)
   (azimuth :initarg :azimuth :accessor orbit-azimuth
            :initform 0.0)
   (elevation :initarg :elevation :accessor orbit-elevation
              :initform 30.0)
   (min-distance :initarg :min-distance :accessor orbit-min-distance
                 :initform 5.0)
   (max-distance :initarg :max-distance :accessor orbit-max-distance
                 :initform 500.0)))

(defclass fly-camera (camera)
  ((velocity :initform (vec3 0 0 0) :accessor fly-velocity)
   (speed :initform 10.0 :accessor fly-speed)
   (sensitivity :initform 0.1 :accessor fly-sensitivity)))

(defgeneric update-camera (camera dt)
  (:documentation "Update camera state for delta-time DT."))

(defmethod update-camera ((camera orbit-camera) dt)
  "Update orbit camera position from spherical coordinates."
  (let* ((az (orbit-azimuth camera))
         (el (orbit-elevation camera))
         (dist (orbit-distance camera))
         (rad-az (radians az))
         (rad-el (radians el)))
    (setf (camera-position camera)
          (vec3+ (camera-target camera)
                 (vec3 (* dist (cos rad-el) (sin rad-az))
                       (* dist (sin rad-el))
                       (* dist (cos rad-el) (cos rad-az)))))))

(defmethod update-camera ((camera fly-camera) dt)
  "Update fly camera based on velocity."
  (setf (camera-position camera)
        (vec3+ (camera-position camera)
               (vec3-scale (fly-velocity camera) dt))))

(defun orbit-rotate (camera delta-azimuth delta-elevation)
  "Rotate orbit camera by deltas."
  (incf (orbit-azimuth camera) delta-azimuth)
  (setf (orbit-elevation camera)
        (clamp (+ (orbit-elevation camera) delta-elevation)
               -89.0 89.0)))

(defun orbit-zoom (camera delta)
  "Zoom orbit camera by delta distance."
  (setf (orbit-distance camera)
        (clamp (+ (orbit-distance camera) delta)
               (orbit-min-distance camera)
               (orbit-max-distance camera))))

(defun camera-smooth-transition (camera target-pos duration &key (easing :ease-out-cubic))
  "Smoothly transition camera to target position."
  (let ((start-pos (camera-target camera))
        (start-time *time*))
    (lambda (current-time)
      (let* ((elapsed (- current-time start-time))
             (t-normalized (min 1.0 (/ elapsed duration)))
             (t-eased (apply-easing easing t-normalized)))
        (setf (camera-target camera)
              (vec3-lerp start-pos target-pos t-eased))
        (>= t-normalized 1.0)))))

(defun focus-on-snapshot (camera snapshot-id)
  "Focus camera on a specific snapshot."
  (let* ((entity (find-entity-by-snapshot-id snapshot-id))
         (pos (when entity (entity-position entity))))
    (when pos
      (camera-smooth-transition camera pos 0.5))))

(defun focus-on-agent (camera agent-id)
  "Focus camera on a live agent's current position."
  (let* ((current-snap (get-agent-current-snapshot agent-id))
         (entity (when current-snap
                   (find-entity-by-snapshot-id (snapshot-id current-snap)))))
    (when entity
      (setf (camera-target camera) (entity-position entity)))))

(defun camera-overview (camera timeline)
  "Position camera for full timeline overview."
  (let* ((bounds (compute-timeline-bounds timeline))
         (center (bounds-center bounds))
         (size (bounds-size bounds))
         (distance (* 1.5 (max (vec3-x size) (vec3-y size) (vec3-z size)))))
    (setf (camera-target camera) center)
    (when (typep camera 'orbit-camera)
      (setf (orbit-distance camera) distance)
      (setf (orbit-elevation camera) 45.0))))
```

## 8.4 HUD System

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; hud.lisp - Heads-up display
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

(defclass hud ()
  ((panels :initform (make-hash-table) :accessor hud-panels)
   (visible-p :initform t :accessor hud-visible-p)
   (font :initform nil :accessor hud-font)))

(defclass hud-panel ()
  ((x :initarg :x :accessor panel-x)
   (y :initarg :y :accessor panel-y)
   (width :initarg :width :accessor panel-width)
   (height :initarg :height :accessor panel-height)
   (content :initform nil :accessor panel-content)
   (visible-p :initform t :accessor panel-visible-p)
   (alpha :initform 0.7 :accessor panel-alpha)))

(defun make-hud ()
  "Create HUD with standard panels."
  (let ((hud (make-instance 'hud)))
    ;; Position panel (top-left)
    (setf (gethash :position (hud-panels hud))
          (make-instance 'hud-panel
                         :x 20 :y 20
                         :width 250 :height 100))
    ;; Agent panel (top-right)
    (setf (gethash :agent (hud-panels hud))
          (make-instance 'hud-panel
                         :x (- *window-width* 270) :y 20
                         :width 250 :height 150))
    ;; Timeline scrubber (bottom)
    (setf (gethash :timeline (hud-panels hud))
          (make-instance 'hud-panel
                         :x 20 :y (- *window-height* 80)
                         :width (- *window-width* 40) :height 60))
    ;; Action hints (bottom-right)
    (setf (gethash :hints (hud-panels hud))
          (make-instance 'hud-panel
                         :x (- *window-width* 220) :y (- *window-height* 150)
                         :width 200 :height 70))
    hud))

(defun update-hud (hud state)
  "Update HUD content from current state."
  ;; Position panel
  (let ((pos-panel (gethash :position (hud-panels hud))))
    (setf (panel-content pos-panel)
          (list (format nil "Branch: ~a" (state-current-branch state))
                (format nil "Snapshot: ~a"
                        (truncate-string (state-current-snapshot-id state) 20))
                (format nil "Type: ~a" (state-current-type state)))))

  ;; Agent panel (if agent is live)
  (when (state-live-agent state)
    (let ((agent-panel (gethash :agent (hud-panels hud))))
      (setf (panel-content agent-panel)
            (list (format nil "Agent: ~a" (agent-name (state-live-agent state)))
                  (format nil "Status: ~a" (agent-state (state-live-agent state)))
                  (format nil "Task: ~a"
                          (truncate-string (agent-current-task state) 30)))))))

(defun render-hud (hud)
  "Render all visible HUD panels."
  (when (hud-visible-p hud)
    (maphash (lambda (name panel)
               (declare (ignore name))
               (when (panel-visible-p panel)
                 (render-hud-panel panel)))
             (hud-panels hud))))

(defun render-hud-panel (panel)
  "Render a single HUD panel."
  ;; Background
  (draw-rect-2d (panel-x panel) (panel-y panel)
                (panel-width panel) (panel-height panel)
                :color (vec4 0.0 0.0 0.0 (panel-alpha panel))
                :border-color (vec4 0.3 0.6 1.0 0.8)
                :border-width 1)
  ;; Content
  (let ((y (+ (panel-y panel) 20)))
    (dolist (line (panel-content panel))
      (draw-text-2d line (+ (panel-x panel) 10) y
                    :color (vec4 0.8 0.9 1.0 1.0)
                    :size 14)
      (incf y 18))))
```

## 8.5 Input Handling

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; input.lisp - Keyboard and mouse input
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

(defparameter *holodeck-key-bindings*
  '(;; Camera
    (:w . :fly-forward)
    (:s . :fly-backward)
    (:a . :fly-left)
    (:d . :fly-right)
    (:q . :fly-up)
    (:e . :fly-down)
    ;; Navigation
    (:left-bracket . :step-backward)
    (:right-bracket . :step-forward)
    (:f . :fork-here)
    (:m . :merge-prompt)
    ;; View modes
    (:1 . :view-timeline)
    (:2 . :view-tree)
    (:3 . :view-constellation)
    (:4 . :view-diff)
    ;; Focus
    (:tab . :cycle-focus)
    (:space . :toggle-follow)
    (:o . :overview)
    ;; UI
    (:return . :enter-human-loop)
    (:h . :toggle-hud)
    (:slash . :toggle-help)
    (:escape . :exit)))

(defun handle-holodeck-input (window event)
  "Handle input events for holodeck."
  (etypecase event
    (trial:key-event
     (let ((action (cdr (assoc (trial:key event) *holodeck-key-bindings*))))
       (when action
         (execute-holodeck-action window action))))

    (trial:mouse-move-event
     (when (trial:mouse-button-held-p :right)
       ;; Orbit camera
       (orbit-rotate (holodeck-camera window)
                     (* (trial:dx event) 0.3)
                     (* (trial:dy event) -0.3))))

    (trial:mouse-scroll-event
     ;; Zoom
     (orbit-zoom (holodeck-camera window)
                 (* (trial:delta event) -5.0)))

    (trial:mouse-button-event
     (when (and (eq (trial:button event) :left)
                (eq (trial:action event) :press))
       ;; Entity selection
       (let ((entity (pick-entity-at-mouse window)))
         (when entity
           (select-entity entity)))))))

(defun execute-holodeck-action (window action)
  "Execute a holodeck action."
  (case action
    (:step-backward
     (navigate-step (holodeck-navigator window) :backward))
    (:step-forward
     (navigate-step (holodeck-navigator window) :forward))
    (:fork-here
     (fork-at-current-snapshot window))
    (:overview
     (camera-overview (holodeck-camera window)
                      (holodeck-timeline window)))
    (:toggle-hud
     (setf (hud-visible-p (holodeck-hud window))
           (not (hud-visible-p (holodeck-hud window)))))
    (:exit
     (trial:quit window))))

(defun pick-entity-at-mouse (window)
  "Pick entity under mouse cursor using ray casting."
  (let* ((mouse-pos (trial:mouse-position window))
         (ray (screen-to-world-ray (holodeck-camera window) mouse-pos)))
    (find-closest-intersecting-entity ray)))

(defun screen-to-world-ray (camera screen-pos)
  "Convert screen position to world-space ray."
  (let* ((view (camera-view-matrix camera))
         (proj (camera-projection-matrix camera))
         (inv-vp (mat4-inverse (mat4* proj view)))
         (ndc-x (- (* 2.0 (/ (vec2-x screen-pos) *window-width*)) 1.0))
         (ndc-y (- 1.0 (* 2.0 (/ (vec2-y screen-pos) *window-height*))))
         (near-point (mat4-transform-point inv-vp (vec3 ndc-x ndc-y -1.0)))
         (far-point (mat4-transform-point inv-vp (vec3 ndc-x ndc-y 1.0))))
    (make-ray :origin near-point
              :direction (vec3-normalize (vec3- far-point near-point)))))
```

## 8.6 Main Loop

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; holodeck.lisp - Main holodeck loop
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

(defvar *holodeck* nil "Current holodeck instance.")

(defun launch-holodeck (&key store)
  "Launch the 3D holodeck visualization."
  (trial:launch 'holodeck-window
                :store store))

(defmethod trial:render ((window holodeck-window))
  "Main render loop."
  (let ((dt (trial:dt window)))
    ;; Update systems
    (ecs:run-system 'movement-system dt)
    (ecs:run-system 'pulse-system dt)
    (ecs:run-system 'lod-system dt)
    (ecs:run-system 'interaction-system dt)

    ;; Update camera
    (update-camera (holodeck-camera window) dt)

    ;; Clear and setup
    (gl:clear :color-buffer :depth-buffer)
    (setup-camera-matrices (holodeck-camera window))

    ;; Render grid
    (render-reference-grid)

    ;; Render entities
    (ecs:do-entities (entity :components (position visual-style))
      (render-snapshot-entity entity))

    ;; Render connections
    (ecs:do-entities (entity :components (connection))
      (render-connection-entity entity))

    ;; Render labels (distance-based)
    (ecs:do-entities (entity :components (position label))
      (when (< (distance-to-camera entity) 50.0)
        (render-entity-label entity)))

    ;; Render HUD (2D overlay)
    (update-hud (holodeck-hud window) (get-current-state window))
    (render-hud (holodeck-hud window))

    ;; Sync with live agents
    (sync-live-agents window)))

(defun sync-live-agents (window)
  "Synchronize visualization with live agent states."
  (dolist (agent (list-active-agents))
    (let* ((current-snap (agent-current-snapshot agent))
           (entity (find-entity-by-snapshot-id (snapshot-id current-snap))))
      (when entity
        ;; Pulse live agents
        (setf (visual-style-pulse-rate entity) 2.0)
        ;; Update position if snapshot changed
        (unless (string= (snapshot-binding-snapshot-id entity)
                         (snapshot-id current-snap))
          (update-entity-snapshot-binding entity current-snap))))))
```

---

# Phase 9: Self-Extension

## Overview

Phase 9 enables agents to write their own code, safely compile and execute it, and learn from experience. This requires careful sandboxing to prevent agents from breaking the system.

## 9.1 Extension Compiler

### Safe Compilation Framework

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; extension-compiler.lisp - Safe code compilation
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.core)

;;; ─────────────────────────────────────────────────────────────────
;;; Sandbox Definition
;;; ─────────────────────────────────────────────────────────────────

(defparameter *allowed-packages*
  '(:cl :autopoiesis.core :autopoiesis.agent :alexandria)
  "Packages agents are allowed to reference.")

(defparameter *forbidden-symbols*
  '(eval compile load require
    open delete-file rename-file
    run-program
    setf defvar defparameter
    defclass defmethod defgeneric
    intern export)
  "Symbols agents are NOT allowed to use.")

(defparameter *allowed-special-forms*
  '(if when unless cond case
    let let* flet labels lambda
    progn prog1 block return-from
    tagbody go
    multiple-value-bind values
    the declare)
  "Special forms agents CAN use.")

;;; ─────────────────────────────────────────────────────────────────
;;; Code Validation
;;; ─────────────────────────────────────────────────────────────────

(defun validate-extension-code (code)
  "Validate agent-written code for safety.

   Returns: (values valid-p errors)
     valid-p - T if code passes validation
     errors  - List of validation error strings"
  (let ((errors nil))
    ;; Walk the code tree
    (labels ((check-form (form)
               (cond
                 ((null form) nil)
                 ((atom form)
                  (check-symbol form))
                 ((listp form)
                  (check-list form))))

             (check-symbol (sym)
               (when (symbolp sym)
                 ;; Check package
                 (let ((pkg (symbol-package sym)))
                   (when (and pkg
                              (not (member (package-name pkg)
                                           *allowed-packages*
                                           :test #'string=)))
                     (push (format nil "Symbol ~s from forbidden package ~a"
                                   sym (package-name pkg))
                           errors)))
                 ;; Check forbidden symbols
                 (when (member sym *forbidden-symbols*)
                   (push (format nil "Forbidden symbol: ~s" sym)
                         errors))))

             (check-list (form)
               (let ((head (first form)))
                 ;; Check for macro/function calls
                 (check-symbol head)
                 ;; Recursively check arguments
                 (dolist (subform (rest form))
                   (check-form subform)))))

      (check-form code))

    (values (null errors) (nreverse errors))))

;;; ─────────────────────────────────────────────────────────────────
;;; Safe Compilation
;;; ─────────────────────────────────────────────────────────────────

(defun compile-extension (code &key (name (gensym "EXTENSION-")))
  "Safely compile agent-written code.

   Returns: (values compiled-fn errors)
     compiled-fn - Compiled function, or NIL if validation failed
     errors      - List of validation/compilation errors"
  (multiple-value-bind (valid-p validation-errors)
      (validate-extension-code code)
    (if (not valid-p)
        (values nil validation-errors)
        (handler-case
            (let* ((fn-code `(lambda () ,code))
                   (compiled (compile nil fn-code)))
              (values compiled nil))
          (error (e)
            (values nil (list (format nil "Compilation error: ~a" e))))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Extension Registry
;;; ─────────────────────────────────────────────────────────────────

(defvar *extension-registry* (make-hash-table :test 'equal)
  "Registry of compiled agent extensions.")

(defclass extension ()
  ((id :initarg :id :accessor extension-id)
   (author-agent :initarg :author :accessor extension-author)
   (code :initarg :code :accessor extension-code)
   (compiled :initarg :compiled :accessor extension-compiled)
   (created :initarg :created :accessor extension-created
            :initform (get-precise-time))
   (invocations :initform 0 :accessor extension-invocations)
   (errors :initform 0 :accessor extension-errors)
   (status :initform :pending :accessor extension-status
           :documentation ":pending :validated :rejected :promoted")))

(defun register-extension (agent code)
  "Register a new extension from an agent."
  (let ((ext (make-instance 'extension
                            :id (make-uuid)
                            :author (agent-id agent)
                            :code code)))
    ;; Validate
    (multiple-value-bind (compiled errors)
        (compile-extension code)
      (if compiled
          (progn
            (setf (extension-compiled ext) compiled)
            (setf (extension-status ext) :validated)
            (setf (gethash (extension-id ext) *extension-registry*) ext)
            ext)
          (progn
            (setf (extension-status ext) :rejected)
            (values nil errors))))))

(defun invoke-extension (extension-id &rest args)
  "Safely invoke a registered extension."
  (let ((ext (gethash extension-id *extension-registry*)))
    (when (and ext (eq (extension-status ext) :validated))
      (incf (extension-invocations ext))
      (handler-case
          (apply (extension-compiled ext) args)
        (error (e)
          (incf (extension-errors ext))
          (when (> (extension-errors ext) 3)
            ;; Auto-disable broken extensions
            (setf (extension-status ext) :rejected))
          (error 'extension-error :extension ext :condition e))))))
```

## 9.2 Agent-Written Capabilities

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; agent-capabilities.lisp - Agent-defined capabilities
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Capability Generation
;;; ─────────────────────────────────────────────────────────────────

(defclass agent-capability (capability)
  ((source-agent :initarg :source-agent :accessor cap-source-agent)
   (source-code :initarg :source-code :accessor cap-source-code)
   (extension-id :initarg :extension-id :accessor cap-extension-id)
   (test-results :initform nil :accessor cap-test-results)
   (promotion-status :initform :draft :accessor cap-promotion-status
                     :documentation ":draft :testing :promoted :rejected"))
  (:documentation "A capability defined by an agent at runtime."))

(defun agent-define-capability (agent name description params body)
  "Allow an agent to define a new capability.

   Arguments:
     agent       - The defining agent
     name        - Capability name (keyword)
     description - Human-readable description
     params      - Parameter specification ((name type) ...)
     body        - Implementation code (will be validated)

   Returns: agent-capability instance or NIL on validation failure"
  (let* ((full-code `(lambda ,params ,@body))
         (ext (register-extension agent full-code)))
    (when ext
      (let ((cap (make-instance 'agent-capability
                                :name name
                                :description description
                                :parameters params
                                :source-agent (agent-id agent)
                                :source-code full-code
                                :extension-id (extension-id ext))))
        ;; Register but don't promote yet
        (push cap (agent-capabilities agent))
        cap))))

(defun test-agent-capability (capability test-cases)
  "Test an agent-defined capability.

   Arguments:
     capability - agent-capability to test
     test-cases - List of (input expected-output) pairs

   Returns: (values passed-p results)"
  (let ((results nil)
        (passed 0)
        (failed 0))
    (dolist (test test-cases)
      (let* ((input (first test))
             (expected (second test)))
        (handler-case
            (let ((actual (invoke-extension
                           (cap-extension-id capability)
                           input)))
              (if (equal actual expected)
                  (progn
                    (incf passed)
                    (push (list :pass input expected actual) results))
                  (progn
                    (incf failed)
                    (push (list :fail input expected actual) results))))
          (error (e)
            (incf failed)
            (push (list :error input expected e) results)))))

    (setf (cap-test-results capability) (nreverse results))
    (values (zerop failed) results)))

(defun promote-capability (capability)
  "Promote an agent capability to permanent status."
  (when (eq (cap-promotion-status capability) :testing)
    ;; Verify tests passed
    (let ((test-results (cap-test-results capability)))
      (when (every (lambda (r) (eq (first r) :pass)) test-results)
        (setf (cap-promotion-status capability) :promoted)
        ;; Register globally
        (register-capability capability)
        t))))
```

## 9.3 Learning System

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; learning.lisp - Pattern extraction and heuristic generation
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.agent)

;;; ─────────────────────────────────────────────────────────────────
;;; Experience Storage
;;; ─────────────────────────────────────────────────────────────────

(defclass experience ()
  ((task-type :initarg :task-type :accessor exp-task-type)
   (context :initarg :context :accessor exp-context)
   (actions :initarg :actions :accessor exp-actions)
   (outcome :initarg :outcome :accessor exp-outcome
            :documentation ":success :failure :partial")
   (timestamp :initform (get-precise-time) :accessor exp-timestamp)))

(defclass heuristic ()
  ((condition :initarg :condition :accessor heur-condition
              :documentation "S-expression pattern to match")
   (recommendation :initarg :recommendation :accessor heur-recommendation)
   (confidence :initarg :confidence :accessor heur-confidence
               :initform 0.5)
   (applications :initform 0 :accessor heur-applications)
   (successes :initform 0 :accessor heur-successes)))

;;; ─────────────────────────────────────────────────────────────────
;;; Pattern Extraction
;;; ─────────────────────────────────────────────────────────────────

(defun extract-patterns (experiences)
  "Extract common patterns from experiences.

   Looks for:
   - Repeated action sequences that led to success
   - Context patterns that predict good outcomes
   - Anti-patterns that led to failure"
  (let ((success-exps (remove-if-not
                       (lambda (e) (eq (exp-outcome e) :success))
                       experiences))
        (failure-exps (remove-if-not
                       (lambda (e) (eq (exp-outcome e) :failure))
                       experiences)))

    (append
     ;; Success patterns
     (extract-action-sequences success-exps :outcome :success)
     ;; Failure anti-patterns
     (extract-action-sequences failure-exps :outcome :failure))))

(defun extract-action-sequences (experiences &key outcome)
  "Find common action sequences in experiences."
  (let ((sequences (mapcar #'exp-actions experiences))
        (common nil))
    ;; Find n-grams that appear multiple times
    (dolist (n '(2 3 4))
      (let ((ngrams (make-hash-table :test 'equal)))
        (dolist (seq sequences)
          (loop for i from 0 to (- (length seq) n)
                do (incf (gethash (subseq seq i (+ i n)) ngrams 0))))
        ;; Keep patterns that appear in >20% of experiences
        (maphash (lambda (pattern count)
                   (when (> (/ count (length experiences)) 0.2)
                     (push (list :pattern pattern
                                 :outcome outcome
                                 :frequency (/ count (length experiences)))
                           common)))
                 ngrams)))
    common))

;;; ─────────────────────────────────────────────────────────────────
;;; Heuristic Generation
;;; ─────────────────────────────────────────────────────────────────

(defun generate-heuristic (pattern)
  "Generate a heuristic from an extracted pattern."
  (let* ((actions (getf pattern :pattern))
         (outcome (getf pattern :outcome))
         (frequency (getf pattern :frequency)))
    (make-instance 'heuristic
                   :condition (pattern-to-condition actions)
                   :recommendation (if (eq outcome :success)
                                       `(:prefer-actions ,actions)
                                       `(:avoid-actions ,actions))
                   :confidence (* frequency
                                  (if (eq outcome :success) 1.0 -1.0)))))

(defun pattern-to-condition (actions)
  "Convert action pattern to matching condition."
  `(and (task-has-type ,(guess-task-type actions))
        (context-matches ,(extract-context-pattern actions))))

(defun apply-heuristics (agent decision)
  "Apply learned heuristics to a decision."
  (let ((applicable (find-applicable-heuristics agent decision)))
    (dolist (heur applicable)
      (incf (heur-applications heur))
      ;; Adjust decision weights based on heuristics
      (adjust-decision-weights decision (heur-recommendation heur)
                               (heur-confidence heur)))
    decision))

(defun update-heuristic-confidence (heuristic outcome)
  "Update heuristic confidence based on outcome."
  (if (eq outcome :success)
      (progn
        (incf (heur-successes heuristic))
        (setf (heur-confidence heuristic)
              (/ (heur-successes heuristic)
                 (heur-applications heuristic))))
      (setf (heur-confidence heuristic)
            (* (heur-confidence heuristic) 0.9))))
```

---

# Phase 10: Production

## Overview

Phase 10 focuses on making Autopoiesis production-ready: performance optimization, security hardening, reliability improvements, and deployment infrastructure.

## 10.1 Performance Optimization

### Snapshot Store Optimization

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; optimization/snapshot-cache.lisp - Optimized snapshot storage
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.snapshot)

;;; LRU Cache for hot snapshots
(defclass lru-cache ()
  ((capacity :initarg :capacity :accessor cache-capacity)
   (table :initform (make-hash-table :test 'equal) :accessor cache-table)
   (order :initform nil :accessor cache-order)
   (hits :initform 0 :accessor cache-hits)
   (misses :initform 0 :accessor cache-misses)))

(defun make-lru-cache (&key (capacity 1000))
  (make-instance 'lru-cache :capacity capacity))

(defun cache-get (cache key)
  "Get value from cache, updating LRU order."
  (let ((value (gethash key (cache-table cache))))
    (if value
        (progn
          (incf (cache-hits cache))
          (setf (cache-order cache)
                (cons key (remove key (cache-order cache) :test #'equal)))
          value)
        (progn
          (incf (cache-misses cache))
          nil))))

(defun cache-put (cache key value)
  "Put value in cache, evicting if necessary."
  (when (>= (hash-table-count (cache-table cache)) (cache-capacity cache))
    ;; Evict least recently used
    (let ((lru (car (last (cache-order cache)))))
      (remhash lru (cache-table cache))
      (setf (cache-order cache) (butlast (cache-order cache)))))
  (setf (gethash key (cache-table cache)) value)
  (push key (cache-order cache)))

;;; ─────────────────────────────────────────────────────────────────
;;; Parallel System Execution
;;; ─────────────────────────────────────────────────────────────────

(defun parallel-ecs-update (systems dt)
  "Execute independent ECS systems in parallel."
  (let ((threads nil))
    (dolist (system systems)
      (push (bordeaux-threads:make-thread
             (lambda () (ecs:run-system system dt))
             :name (format nil "ecs-~a" system))
            threads))
    ;; Wait for all to complete
    (dolist (thread threads)
      (bordeaux-threads:join-thread thread))))

;;; ─────────────────────────────────────────────────────────────────
;;; Memory Usage Reduction
;;; ─────────────────────────────────────────────────────────────────

(defun compact-thought-stream (stream &key (keep-last 100))
  "Compact old thoughts to reduce memory."
  (when (> (stream-length stream) (* keep-last 2))
    (let* ((all-thoughts (stream-thoughts stream))
           (to-archive (subseq all-thoughts 0 (- (length all-thoughts) keep-last)))
           (to-keep (subseq all-thoughts (- (length all-thoughts) keep-last))))
      ;; Archive to disk
      (archive-thoughts to-archive)
      ;; Update stream
      (setf (stream-thoughts stream) (coerce to-keep 'vector)))))
```

## 10.2 Security Hardening

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; security/sandbox.lisp - Enhanced sandboxing
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.security)

;;; ─────────────────────────────────────────────────────────────────
;;; Capability Permissions
;;; ─────────────────────────────────────────────────────────────────

(defclass permission ()
  ((name :initarg :name :accessor perm-name)
   (resource :initarg :resource :accessor perm-resource)
   (actions :initarg :actions :accessor perm-actions
            :documentation "List of allowed actions: :read :write :execute :delete")))

(defvar *agent-permissions* (make-hash-table :test 'equal)
  "Map agent-id -> list of permissions")

(defun check-permission (agent-id resource action)
  "Check if agent has permission for action on resource."
  (let ((perms (gethash agent-id *agent-permissions*)))
    (some (lambda (perm)
            (and (permission-matches-p perm resource)
                 (member action (perm-actions perm))))
          perms)))

(defmacro with-permission-check ((agent resource action) &body body)
  "Execute body only if agent has permission."
  `(if (check-permission (agent-id ,agent) ,resource ,action)
       (progn ,@body)
       (error 'permission-denied
              :agent ,agent :resource ,resource :action ,action)))

;;; ─────────────────────────────────────────────────────────────────
;;; Audit Logging
;;; ─────────────────────────────────────────────────────────────────

(defvar *audit-log* nil "Current audit log stream")

(defstruct audit-entry
  timestamp
  agent-id
  action
  resource
  result
  details)

(defun audit-log (agent-id action resource result &optional details)
  "Log an action to the audit trail."
  (when *audit-log*
    (let ((entry (make-audit-entry
                  :timestamp (get-precise-time)
                  :agent-id agent-id
                  :action action
                  :resource resource
                  :result result
                  :details details)))
      (write-line (serialize-audit-entry entry) *audit-log*)
      (force-output *audit-log*))))

(defmacro with-audit ((agent action resource) &body body)
  "Execute body with audit logging."
  (let ((result-var (gensym "RESULT")))
    `(let ((,result-var nil))
       (unwind-protect
            (setf ,result-var
                  (handler-case
                      (progn ,@body :success)
                    (error (e) (list :error e))))
            (audit-log (agent-id ,agent) ,action ,resource ,result-var))
       (if (eq ,result-var :success)
           ,result-var
           (error (second ,result-var))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Input Validation
;;; ─────────────────────────────────────────────────────────────────

(defun validate-input (input spec)
  "Validate INPUT against SPEC.

   Spec format:
     (:string :max-length 1000)
     (:integer :min 0 :max 100)
     (:list :element-type :string)
     (:one-of :options (:a :b :c))"
  (let ((type (first spec)))
    (case type
      (:string
       (and (stringp input)
            (<= (length input) (or (getf (rest spec) :max-length) 10000))))
      (:integer
       (and (integerp input)
            (>= input (or (getf (rest spec) :min) most-negative-fixnum))
            (<= input (or (getf (rest spec) :max) most-positive-fixnum))))
      (:list
       (and (listp input)
            (every (lambda (el)
                     (validate-input el (list (getf (rest spec) :element-type))))
                   input)))
      (:one-of
       (member input (getf (rest spec) :options)))
      (t t))))
```

## 10.3 Deployment

### Docker Configuration

```dockerfile
# Dockerfile for Autopoiesis

FROM clfoundation/sbcl:2.4.0

# Install dependencies
RUN apt-get update && apt-get install -y \
    libsqlite3-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Setup Quicklisp
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --load quicklisp.lisp \
            --eval "(quicklisp-quickstart:install)" \
            --eval "(ql:add-to-init-file)" \
            --quit

# Copy application
WORKDIR /app
COPY . .

# Load dependencies
RUN sbcl --eval "(ql:quickload :autopoiesis)" --quit

# Build executable
RUN sbcl --load build.lisp --eval "(build)" --quit

# Runtime configuration
ENV AUTOPOIESIS_DATA_DIR=/data
ENV AUTOPOIESIS_LOG_LEVEL=info

VOLUME /data
EXPOSE 8080

CMD ["./autopoiesis-server"]
```

### Configuration Management

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; config.lisp - Production configuration
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis)

(defparameter *default-config*
  '(:server (:host "0.0.0.0"
             :port 8080
             :max-connections 100)
    :storage (:type :sqlite
              :path "/data/autopoiesis.db"
              :cache-size 1000)
    :logging (:level :info
              :file "/data/logs/autopoiesis.log"
              :rotate-size 10485760)  ; 10MB
    :security (:sandbox-level :strict
               :audit-enabled t
               :max-extension-size 10000)
    :performance (:parallel-systems t
                  :gc-threshold 100000000)
    :claude (:model "claude-sonnet-4-20250514"
             :max-tokens 4096
             :timeout 30)))

(defun load-config (&optional (path "/etc/autopoiesis/config.lisp"))
  "Load configuration from file, merging with defaults."
  (let ((file-config (if (probe-file path)
                         (with-open-file (in path)
                           (read in))
                         nil)))
    (merge-configs *default-config* file-config)))

(defun get-config (path &optional default)
  "Get configuration value by path.

   Example: (get-config '(:server :port)) => 8080"
  (let ((config *current-config*)
        (value nil))
    (dolist (key path)
      (setf value (getf config key))
      (setf config value))
    (or value default)))
```

### Monitoring Integration

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; monitoring.lisp - Metrics and health checks
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis)

;;; ─────────────────────────────────────────────────────────────────
;;; Metrics Collection
;;; ─────────────────────────────────────────────────────────────────

(defvar *metrics* (make-hash-table :test 'equal))

(defun record-metric (name value &key (type :gauge))
  "Record a metric value."
  (let ((metric (gethash name *metrics*)))
    (unless metric
      (setf metric (make-metric name type))
      (setf (gethash name *metrics*) metric))
    (update-metric metric value)))

(defstruct metric
  name
  type
  value
  count
  sum
  min
  max
  last-updated)

(defun update-metric (metric value)
  (setf (metric-value metric) value)
  (setf (metric-last-updated metric) (get-precise-time))
  (case (metric-type metric)
    (:counter (incf (metric-value metric) value))
    (:gauge (setf (metric-value metric) value))
    (:histogram
     (incf (metric-count metric))
     (incf (metric-sum metric) value)
     (setf (metric-min metric) (min (or (metric-min metric) value) value))
     (setf (metric-max metric) (max (or (metric-max metric) value) value)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Health Checks
;;; ─────────────────────────────────────────────────────────────────

(defun health-check ()
  "Perform system health check."
  (let ((checks nil))
    ;; Check snapshot store
    (push (list :snapshot-store (check-snapshot-store)) checks)
    ;; Check Claude connection
    (push (list :claude-api (check-claude-connection)) checks)
    ;; Check memory usage
    (push (list :memory (check-memory-usage)) checks)
    ;; Overall status
    (let ((all-ok (every (lambda (c) (eq (second c) :ok)) checks)))
      (list :status (if all-ok :healthy :unhealthy)
            :checks checks
            :timestamp (get-precise-time)))))

(defun check-snapshot-store ()
  (handler-case
      (progn
        (list-snapshots :limit 1)
        :ok)
    (error () :error)))

(defun check-claude-connection ()
  (handler-case
      (progn
        ;; Lightweight API check
        :ok)
    (error () :error)))

(defun check-memory-usage ()
  (let ((usage (sb-kernel:dynamic-usage)))
    (if (< usage (* 1024 1024 1024))  ; 1GB threshold
        :ok
        :warning)))
```

---

## Test Requirements Summary

### Phase 7 Tests
- Navigation: Cursor movement, jump, search
- Branch layout computation
- Terminal UI input handling
- Integration with session system

### Phase 8 Tests
- ECS entity creation and component access
- System execution and ordering
- Camera transitions
- Ray picking accuracy
- HUD rendering

### Phase 9 Tests
- Code validation (allowed/forbidden constructs)
- Safe compilation and execution
- Extension registry
- Capability generation and testing
- Heuristic learning

### Phase 10 Tests
- Load testing (concurrent agents, large snapshot DAGs)
- Security testing (sandbox escape attempts)
- Permission system
- Configuration loading
- Health check endpoints

---

## Dependencies Summary

| Phase | New Dependencies |
|-------|------------------|
| 7 | None (uses existing) |
| 8 | trial, 3d-matrices, 3d-vectors, cl-fast-ecs |
| 9 | None (pure Lisp) |
| 10 | hunchentoot (HTTP), sqlite (storage) |

---

## Timeline Estimate

| Phase | Estimated Effort |
|-------|------------------|
| 7 Completion | 2-3 weeks |
| 8 (3D Holodeck) | 6-8 weeks |
| 9 (Self-Extension) | 4-5 weeks |
| 10 (Production) | 4-6 weeks |

**Total: 16-22 weeks for full completion**

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Trial engine compatibility issues | Medium | High | Have Raylib fallback |
| Sandbox escape vulnerabilities | Low | Critical | Extensive testing, code review |
| Performance issues with large DAGs | Medium | Medium | Implement pagination, caching |
| Claude API changes | Low | Medium | Abstract API layer |

---

## Next Steps

1. Complete Phase 7.4 (thought preview)
2. Implement Phase 7.5 (navigation)
3. Implement Phase 7.6 (interactive UI)
4. Complete Phase 7 tests
5. Begin Phase 8 with graphics engine evaluation
