;;;; packages.lisp - Research campaign package
;;;;
;;;; Provides sandbox-backed parallel research campaigns:
;;;; question → approach generation → parallel sandbox trials → result aggregation.
;;;;
;;;; Two execution modes:
;;;;   :tool-backed   - Agent runs in AP, executes commands in sandbox via capabilities
;;;;   :fully-sandboxed - Agent (e.g., Claude Code CLI) runs entirely inside the sandbox

(in-package #:cl-user)

(defpackage #:autopoiesis.research
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads))
  (:export
   ;; Top-level API
   #:run-research
   #:campaign-report
   #:rerun-trial

   ;; Campaign class
   #:research-campaign
   #:campaign-id
   #:campaign-question
   #:campaign-approaches
   #:campaign-trials
   #:campaign-summary
   #:campaign-status
   #:campaign-mode

   ;; Trial sandbox binding
   #:*trial-sandbox-id*

   ;; Tool capabilities (for :tool-backed mode)
   #:sandbox-exec
   #:sandbox-write-file
   #:sandbox-read-file
   #:sandbox-install
   #:research-tool-capabilities

   ;; Fully-sandboxed agent support
   #:run-sandboxed-agent
   #:*sandboxed-agent-command*))
