;;;; autopoiesis.lisp - Main package reexporting all symbols
;;;;
;;;; This is the top-level package that users should USE.

(in-package #:cl-user)

(defpackage #:autopoiesis
  (:use #:cl)
  (:use #:autopoiesis.core)
  (:use #:autopoiesis.agent)
  (:use #:autopoiesis.snapshot)
  (:use #:autopoiesis.interface)
  (:use #:autopoiesis.integration)
  (:use #:autopoiesis.viz)

  ;; Reexport core
  (:export
   #:sexpr-equal #:sexpr-hash #:sexpr-serialize #:sexpr-deserialize
   #:sexpr-diff #:sexpr-patch
   #:thought #:make-thought #:thought-id #:thought-content #:thought-type
   #:thought-confidence #:thought-timestamp #:thought-provenance
   #:thought-to-sexpr #:sexpr-to-thought
   #:decision #:make-decision #:decision-alternatives #:decision-chosen
   #:action #:make-action #:action-capability #:action-result
   #:observation #:make-observation #:observation-source
   #:reflection #:make-reflection #:reflection-insight
   #:thought-stream #:make-thought-stream
   #:stream-append #:stream-find #:stream-length #:stream-last
   #:extension #:compile-extension #:install-extension #:execute-extension)

  ;; Reexport agent
  (:export
   #:agent #:make-agent #:agent-id #:agent-name #:agent-state
   #:start-agent #:stop-agent #:pause-agent #:resume-agent #:agent-running-p
   #:cognitive-cycle
   #:capability #:make-capability #:register-capability #:invoke-capability
   #:spawn-agent)

  ;; Reexport snapshot
  (:export
   #:snapshot #:make-snapshot #:snapshot-id #:snapshot-hash
   #:content-store #:make-content-store #:store-put #:store-get
   #:branch #:create-branch #:switch-branch #:current-branch
   #:checkout-snapshot #:snapshot-diff #:snapshot-patch
   #:event #:make-event #:append-event #:replay-events)

  ;; Reexport interface
  (:export
   #:navigator #:make-navigator #:navigate-to #:navigate-back
   #:viewport #:make-viewport #:viewport-render
   #:annotation #:make-annotation #:add-annotation #:find-annotations
   #:request-human-input #:await-human-response
   #:session #:start-session #:end-session)

  ;; Reexport integration
  (:export
   #:claude-client #:make-claude-client #:claude-complete
   #:mcp-server #:make-mcp-server #:mcp-connect
   #:external-tool #:make-external-tool #:register-external-tool)

  ;; Reexport viz
  (:export
   #:timeline #:make-timeline #:render-timeline
   #:timeline-viewport #:make-timeline-viewport
   #:timeline-navigator #:make-timeline-navigator
   #:terminal-ui #:run-terminal-ui #:stop-terminal-ui
   #:snapshot-glyph #:render-snapshot-node
   #:session-to-timeline #:launch-session-viz))

(in-package #:autopoiesis)

(defun initialize ()
  "Initialize the Autopoiesis system."
  (autopoiesis.integration::initialize-integrations)
  (format t "~&Autopoiesis initialized.~%")
  t)

(defun version ()
  "Return the Autopoiesis version."
  "0.1.0-bootstrap")
