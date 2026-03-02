;;;; packages.lisp - Package definition for supervisor layer
;;;;
;;;; Provides checkpoint-and-revert supervision for high-risk agent operations.

(in-package #:cl-user)

(defpackage #:autopoiesis.supervisor
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; State
   #:*stable-root*
   #:*checkpoint-stack*
   ;; Operations
   #:with-checkpoint
   #:checkpoint-agent
   #:revert-to-stable
   #:promote-checkpoint
   #:supervisor-status))
