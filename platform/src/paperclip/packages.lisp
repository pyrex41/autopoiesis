;;;; packages.lisp - Paperclip AI BYOA adapter package definitions
;;;;
;;;; Defines the package for the Paperclip heartbeat protocol adapter,
;;;; agent registry, budget tracking, and SKILLS.md generation.

(in-package #:cl-user)

(defpackage #:autopoiesis.paperclip
  (:use #:cl #:alexandria #:autopoiesis.core #:autopoiesis.agent)
  (:export
   ;; Heartbeat protocol
   #:normalize-heartbeat-payload
   #:handle-paperclip-heartbeat
   #:*paperclip-adapter-loaded*
   ;; Agent registry
   #:paperclip-get-or-create-agent
   #:paperclip-retire-agent
   #:paperclip-list-agents
   #:*paperclip-agents*
   ;; Budget
   #:check-paperclip-budget
   #:update-paperclip-budget
   #:*paperclip-budgets*
   ;; Skills
   #:generate-skills-md
   ;; Config
   #:*paperclip-config*))
