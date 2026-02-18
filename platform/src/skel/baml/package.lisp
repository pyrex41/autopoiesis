;;;; package.lisp - Package definition for BAML import system

(defpackage #:autopoiesis.skel.baml
  (:use #:cl)
  (:local-nicknames (#:skel #:autopoiesis.skel))
  (:export
   ;; Import functions
   #:import-baml-file
   #:import-baml-directory
   #:import-baml-string
   #:baml->skel
   #:preview-baml-import
   #:baml-file-info

   ;; Client registry
   #:register-baml-client
   #:resolve-baml-client
   #:clear-baml-clients
   #:list-baml-clients
   #:*baml-clients*

   ;; Tokenizer
   #:tokenize-baml
   #:baml-token
   #:make-baml-token
   #:token-type
   #:token-value
   #:token-line
   #:token-column

   ;; Parser structures - class
   #:baml-class
   #:baml-class-p
   #:make-baml-class
   #:baml-class-name
   #:baml-class-fields
   #:baml-class-documentation

   ;; Parser structures - field
   #:baml-field
   #:baml-field-p
   #:make-baml-field
   #:baml-field-name
   #:baml-field-type
   #:baml-field-description
   #:baml-field-required
   #:baml-field-default
   #:baml-field-alias

   ;; Parser structures - function
   #:baml-function
   #:baml-function-p
   #:make-baml-function
   #:baml-function-name
   #:baml-function-params
   #:baml-function-return-type
   #:baml-function-client
   #:baml-function-prompt
   #:baml-function-config

   ;; Parser structures - enum
   #:baml-enum
   #:baml-enum-p
   #:make-baml-enum
   #:baml-enum-name
   #:baml-enum-values
   #:baml-enum-documentation
   #:baml-enum-value
   #:baml-enum-value-p
   #:make-baml-enum-value
   #:baml-enum-value-name
   #:baml-enum-value-description
   #:baml-enum-value-alias

   ;; Parser structures - client
   #:baml-client-def
   #:baml-client-def-p
   #:make-baml-client-def
   #:baml-client-def-name
   #:baml-client-def-provider
   #:baml-client-def-options

   ;; Parser structures - param
   #:baml-param
   #:baml-param-p
   #:make-baml-param
   #:baml-param-name
   #:baml-param-type

   ;; Parser
   #:parse-baml-content
   #:parse-baml-class
   #:parse-baml-function
   #:parse-baml-enum
   #:parse-baml-client

   ;; Type converter
   #:baml-type->skel-type

   ;; BAML->SKEL converters
   #:baml-class->skel-class
   #:baml-function->skel-function
   #:baml-enum->skel-enum
   #:baml-field->skel-slot
   #:baml-param->skel-param
   #:convert-baml-prompt

   ;; Utilities
   #:kebab-case
   #:lisp-symbol-name
   #:parse-shorthand-client

   ;; Conditions
   #:baml-error
   #:baml-error-message
   #:baml-parse-error
   #:baml-parse-error-expected
   #:baml-parse-error-found
   #:baml-parse-error-context
   #:baml-tokenize-error
   #:baml-tokenize-error-line
   #:baml-tokenize-error-column
   #:baml-tokenize-error-content
   #:baml-type-error
   #:baml-type-error-baml-type
   #:baml-type-error-reason
   #:baml-import-error
   #:baml-import-error-path
   #:baml-import-error-cause))
