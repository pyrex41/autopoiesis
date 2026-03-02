;;;; packages.lisp - Crystallization engine package definitions
;;;;
;;;; Defines package for emitting live runtime changes as .lisp source,
;;;; stored in the snapshot DAG with Git export on demand.

(in-package #:cl-user)

(defpackage #:autopoiesis.crystallize
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Core emitter
   #:emit-to-file

   ;; Crystallizers
   #:crystallize-capabilities
   #:crystallize-heuristics
   #:crystallize-genome
   #:crystallize-genomes

   ;; Snapshot integration
   #:store-crystallized-snapshot
   #:crystallize-all

   ;; ASDF fragment
   #:emit-asdf-fragment

   ;; Git export
   #:export-to-git))
