;;;; packages.lisp - Package definitions for Autopoiesis Core
;;;;
;;;; This file defines the package structure for the core layer.

(in-package #:cl-user)

;;; ═══════════════════════════════════════════════════════════════════
;;; Core Package - S-expression utilities and cognitive primitives
;;; ═══════════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.core
  (:use #:cl #:alexandria)
  (:export
   ;; S-expression utilities
   #:sexpr-equal
   #:sexpr-hash
   #:sexpr-serialize
   #:sexpr-deserialize
   #:sexpr-diff
   #:sexpr-patch
   #:sexpr-edit
   #:make-edit

   ;; Cognitive primitives
   #:thought
   #:thought-id
   #:thought-timestamp
   #:thought-content
   #:thought-type
   #:thought-confidence
   #:thought-provenance
   #:make-thought
   #:thought-to-sexpr
   #:sexpr-to-thought

   ;; Decision
   #:decision
   #:decision-alternatives
   #:decision-chosen
   #:decision-rationale
   #:make-decision
   #:decision-unchosen

   ;; Action
   #:action
   #:action-capability
   #:action-arguments
   #:action-result
   #:action-side-effects
   #:make-action

   ;; Observation
   #:observation
   #:observation-source
   #:observation-raw
   #:observation-interpreted
   #:make-observation

   ;; Reflection
   #:reflection
   #:reflection-target
   #:reflection-insight
   #:reflection-modification
   #:make-reflection

   ;; Thought stream
   #:thought-stream
   #:make-thought-stream
   #:stream-thoughts
   #:stream-append
   #:stream-find
   #:stream-length
   #:stream-last
   #:stream-range
   #:stream-since
   #:stream-by-type
   #:stream-to-sexpr
   #:sexpr-to-stream

   ;; Conditions
   #:autopoiesis-condition
   #:autopoiesis-error
   #:autopoiesis-warning
   #:condition-message

   ;; Extension compiler
   #:extension
   #:compile-extension
   #:install-extension
   #:uninstall-extension
   #:find-extension
   #:validate-extension-source
   ;; Sandbox configuration
   #:*allowed-packages*
   #:*forbidden-symbols*
   #:*allowed-special-forms*
   #:*sandbox-allowed-symbols*
   #:*sandbox-forbidden-patterns*

   ;; Utilities
   #:make-uuid
   #:get-precise-time
   #:truncate-string
   #:sexpr-size))
