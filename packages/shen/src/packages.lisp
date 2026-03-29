;;;; packages.lisp - Package definition for Shen Prolog integration

(defpackage #:autopoiesis.shen
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads))
  (:export
   ;; Bridge — CL↔Shen interface
   #:shen-available-p
   #:ensure-shen-loaded
   #:shen-eval
   #:shen-eval-string
   #:shen-query
   #:*shen-lock*

   ;; Rules — define and query Prolog rules as data
   #:define-rule
   #:remove-rule
   #:query-rules
   #:list-rules
   #:clear-rules
   #:*rule-store*
   #:rules-to-sexpr
   #:sexpr-to-rules

   ;; Eval verifier — :prolog-query and :prolog-check
   #:register-shen-verifiers

   ;; Agent reasoning — mixin for Prolog-powered reasoning phase
   #:shen-reasoning-mixin
   #:agent-knowledge-base
   #:add-knowledge
   #:remove-knowledge
   #:clear-knowledge
   #:save-knowledge-to-pmap
   #:load-knowledge-from-pmap))
