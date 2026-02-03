;;;; packages.lisp - Package definitions for Autopoiesis Visualization
;;;;
;;;; Defines packages for the 2D terminal visualization system (Phase 7).
;;;; The 3D holodeck visualization (Phase 8) will extend these packages.

(in-package #:cl-user)

;;; ═══════════════════════════════════════════════════════════════════
;;; Main Visualization Package
;;; ═══════════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.viz
  (:use #:cl #:alexandria #:autopoiesis.core #:autopoiesis.snapshot)
  (:export
   ;; Configuration
   #:*viz-config*
   #:viz-config
   #:config-colors
   #:config-symbols
   #:config-dimensions

   ;; Terminal utilities
   #:with-terminal
   #:clear-screen
   #:move-cursor
   #:set-color
   #:reset-color
    #:with-color
   #:hide-cursor
   #:show-cursor
   #:get-terminal-size

   ;; Color codes
   #:+color-reset+
   #:+color-bold+
   #:+color-dim+
   #:+color-snapshot+
   #:+color-decision+
   #:+color-fork+
   #:+color-merge+
   #:+color-current+
   #:+color-human+
   #:+color-error+
   #:+color-border+
   #:+color-text+
   #:+color-highlight+

   ;; Snapshot symbols
   #:snapshot-glyph
    #:snapshot-type-color
   #:+glyph-snapshot+
   #:+glyph-decision+
   #:+glyph-fork+
   #:+glyph-merge+
   #:+glyph-current+
   #:+glyph-genesis+
   #:+glyph-human+
   #:+glyph-action+

   ;; Timeline
   #:timeline
   #:make-timeline
   #:timeline-snapshots
   #:timeline-branches
   #:timeline-current
   #:timeline-viewport-start
   #:timeline-viewport-width

   ;; Timeline viewport
   #:timeline-viewport
   #:make-timeline-viewport
   #:viewport-start
   #:viewport-end
   #:viewport-width
   #:viewport-height
   #:viewport-scroll

   ;; Timeline rendering
   #:render-timeline
   #:render-timeline-row
   #:render-branch-connections
   #:render-snapshot-node
   #:render-legend

   ;; Detail panel
   #:detail-panel
   #:make-detail-panel
   #:panel-width
   #:panel-height
   #:panel-content
   #:render-detail-panel
   #:render-snapshot-summary
   #:render-thought-preview

   ;; Navigation
   #:timeline-navigator
   #:make-timeline-navigator
   #:navigator-timeline
   #:navigator-cursor
   #:cursor-left
   #:cursor-right
   #:cursor-up-branch
   #:cursor-down-branch
   #:jump-to-snapshot
   #:search-snapshots

   ;; Terminal UI
   #:terminal-ui
   #:make-terminal-ui
   #:ui-timeline
   #:ui-detail-panel
   #:ui-status-bar
   #:ui-running-p
   #:run-terminal-ui
   #:stop-terminal-ui
   #:handle-input
   #:refresh-display

   ;; Branch visualization
   #:compute-branch-layout
   #:render-branch-labels
   #:branch-y-position

   ;; Status bar
   #:render-status-bar
   #:status-bar-message

   ;; Help overlay
   #:render-help-overlay
   #:toggle-help))
