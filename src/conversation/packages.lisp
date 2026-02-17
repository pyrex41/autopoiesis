;;;; packages.lisp - Package definitions for the conversation module
;;;;
;;;; Conversation turns and contexts stored as datom entities in the substrate.
;;;; Turns form a DAG via parent pointers. Contexts are mutable entity pointers
;;;; to branch heads.

(in-package #:cl-user)

(defpackage #:autopoiesis.conversation
  (:use #:cl #:alexandria #:autopoiesis.substrate)
  (:export
   #:append-turn
   #:turn-content
   #:make-context
   #:fork-context
   #:context-head
   #:context-history
   #:find-turns-by-role
   #:find-turns-by-time-range))
