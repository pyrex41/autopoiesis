;;;; packages.lisp - Package definition for SKEL typed LLM functions
;;;; Ported from LLMisp into the Autopoiesis platform

(defpackage #:autopoiesis.skel
  (:use #:cl)
  (:local-nicknames (#:ppcre #:cl-ppcre))
  (:import-from #:alexandria #:remove-from-plist)
  (:export
   ;; Core macros
   #:define-skel-class
   #:define-skel-function
   #:define-skel-enum

   ;; Class system
   #:skel-class-metadata
   #:skel-class-name
   #:skel-class-slots
   #:skel-class-documentation
   #:skel-class-superclasses
   #:get-skel-class
   #:skel-class-p
   #:list-skel-classes

   ;; Slot metadata
   #:skel-slot-definition
   #:skel-slot-name
   #:skel-slot-type
   #:skel-slot-description
   #:skel-slot-required-p
   #:skel-slot-default-value
   #:skel-slot-json-key
   #:skel-slot-effective-json-key
   #:get-skel-slot
   #:skel-class-required-slots
   #:skel-class-slot-names

   ;; Instance utilities
   #:make-skel-instance
   #:skel-instance-to-plist
   #:lisp-name-to-json-key

   ;; Type validation and coercion
   #:validate-slot-value
   #:coerce-slot-value
   #:primitive-type-p

   ;; Prompt generation utilities
   #:format-type-for-prompt
   #:format-slot-for-prompt
   #:format-class-schema

   ;; Advanced introspection
   #:skel-class-slots-of-type
   #:skel-class-slots-with-description
   #:skel-class-optional-slots
   #:skel-class-slots-with-defaults
   #:skel-slot-metadata
   #:skel-class-metadata-plist
   #:type-matches-p

   ;; JSON Schema generation
   #:type-to-json-schema
   #:skel-class-to-json-schema

   ;; Type system
   #:skel-type
   #:type-name
   #:type-parser
   #:type-validator
   #:type-description
   #:define-skel-type
   #:get-skel-type

   ;; Built-in type constructors
   #:list-of
   #:one-of
   #:optional

   ;; Function metadata (core.lisp)
   #:skel-function
   #:make-skel-function
   #:skel-function-name
   #:skel-function-prompt
   #:skel-function-return-type
   #:skel-function-parameters
   #:skel-function-config
   #:skel-function-documentation
   #:get-skel-function
   #:register-skel-function
   #:list-skel-functions
   #:clear-skel-functions

   ;; Function parameters (core.lisp)
   #:skel-parameter
   #:make-skel-parameter
   #:skel-parameter-name
   #:skel-parameter-type
   #:skel-parameter-description
   #:skel-parameter-required
   #:skel-parameter-default

   ;; Configuration
   #:skel-config
   #:make-skel-config
   #:config-model
   #:config-max-tokens
   #:config-temperature
   #:config-timeout
   #:config-system-prompt

   ;; Invocation (core.lisp)
   #:invoke-skel-function
   #:skel-call
   #:parse-llm-response
   #:*current-llm-client*
   #:call-with-retries

   ;; Prompt utilities (core.lisp)
   #:interpolate-prompt
   #:build-skel-prompt
   #:format-type-hint
   #:validate-skel-arguments

   ;; SAP Preprocessor
   #:sap-preprocess
   #:extract-structured-portion
   #:strip-markdown-fences

   ;; JSON Normalizer
   #:normalize-json-ish
   #:fix-unquoted-keys
   #:fix-single-quotes
   #:fix-trailing-commas

   ;; Type Coercer
   #:coerce-to-type
   #:parse-integer-lenient
   #:parse-float-lenient
   #:parse-boolean-lenient
   #:ensure-string
   #:ensure-list
   #:sap-coercion-error
   #:sap-coercion-expected-type
   #:sap-coercion-actual-value

   ;; SAP Extractor
   #:sap-extract
   #:sap-extract-lenient
   #:sap-extract-with-schema
   #:sap-extract-slot
   #:sap-try-extract
   #:json-key-to-lisp-name
   #:find-json-value
   #:sap-extraction-error
   #:sap-extraction-schema
   #:sap-extraction-missing-fields

   ;; Partial types
   #:define-partial-class
   #:partial-class-metadata
   #:partial-original-class
   #:partial-class-name
   #:partial-class-slots
   #:partial-class-documentation
   #:get-partial-class
   #:partial-class-p
   #:list-partial-classes
   #:make-partial-class-name
   #:ensure-partial-class
   #:get-partial-type
   #:make-partial-instance
   #:partial-instance-p
   #:partial-to-full
   #:partial-complete-p
   #:partial-fields-received
   #:update-partial-field
   #:partial-field-received-p
   #:partial-coverage
   #:mark-partial-complete

   ;; Streaming API
   #:skel-stream
   #:stream-skel-call
   #:skel-stream-collect

   ;; Stream state class
   #:skel-stream
   #:skel-stream-status
   #:skel-stream-accumulated
   #:skel-stream-partial-result
   #:skel-stream-final-result
   #:skel-stream-return-type
   #:skel-stream-function-name
   #:skel-stream-coverage

   ;; Stream control
   #:skel-stream-wait
   #:skel-stream-cancel

   ;; Stream status predicates
   #:skel-stream-pending-p
   #:skel-stream-streaming-p
   #:skel-stream-complete-p
   #:skel-stream-error-p
   #:skel-stream-cancelled-p
   #:skel-stream-done-p

   ;; Incremental parser (for advanced usage)
   #:incremental-parser
   #:make-incremental-parser
   #:parser-feed
   #:parser-balanced-p
   #:parser-try-extract-partial
   #:fix-incomplete-json

   ;; LLM adapter
   #:skel-llm-rate-limit-error
   #:skel-llm-server-error
   #:skel-llm-connection-error
   #:skel-llm-retry-after
   #:skel-send-message
   #:skel-stream-message
   #:skel-stream-cancel-llm
   #:make-skel-llm-client

   ;; Conditions
   #:skel-error
   #:skel-error-message
   #:skel-class-error
   #:skel-type-error
   #:skel-parse-error
   #:skel-validation-error
   #:skel-stream-error
   #:skel-stream-parse-error
   #:sap-error
   #:sap-preprocessing-error
   #:sap-error-input
   #:sap-error-reason))
