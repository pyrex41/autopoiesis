;;;; packages.lisp - Human interface layer package definitions
;;;;
;;;; Defines packages for human-in-the-loop interaction.

(in-package #:cl-user)

(defpackage #:autopoiesis.interface
  (:use #:cl #:alexandria #:autopoiesis.core #:autopoiesis.agent #:autopoiesis.snapshot)
  (:export
   ;; Navigator
   #:navigator
   #:make-navigator
   #:navigator-position
   #:navigate-to
   #:navigate-forward
   #:navigate-back
   #:navigate-to-branch
   #:navigator-history

   ;; Viewport
   #:viewport
   #:make-viewport
   #:viewport-focus
   #:viewport-filter
   #:viewport-render
   #:set-focus
   #:apply-filter
   #:expand-detail
   #:collapse-detail

   ;; Annotations
   #:annotation
   #:make-annotation
   #:annotation-target
   #:annotation-content
   #:annotation-author
   #:add-annotation
   #:remove-annotation
   #:find-annotations

   ;; Human entry points
   #:request-human-input
   #:await-human-response
   #:human-override
   #:human-approve
   #:human-reject
   #:human-modify

   ;; Session management
   #:session
   #:make-session
   #:session-user
   #:session-agent
   #:session-id
   #:session-navigator
   #:session-viewport
   #:session-command-history
   #:start-session
   #:end-session
   #:find-session
   #:list-sessions
   #:*current-session*
   #:*active-sessions*

   ;; CLI session
   #:cli-command
   #:parse-cli-command
   #:command-name
   #:command-args
   #:execute-cli-command
   #:run-cli-session
   #:cli-interact
   #:cli-display-header
   #:cli-display-state
   #:cli-display-help
   #:session-to-sexpr
   #:session-summary))
