;;;; skel-tests.lisp - Tests for SKEL typed LLM function framework
;;;; Uses FiveAM testing framework

(defpackage #:autopoiesis.test.skel
  (:use #:cl #:autopoiesis.skel #:fiveam)
  (:export #:skel-tests))

(in-package #:autopoiesis.test.skel)

(def-suite skel-tests
  :description "Tests for SKEL class system")

(in-suite skel-tests)

;;; ============================================================================
;;; Helper to clear registry between tests
;;; ============================================================================

(defun clear-skel-registry ()
  "Clear the SKEL class registry for test isolation."
  (clrhash autopoiesis.skel::*skel-classes*)
  (clrhash autopoiesis.skel::*skel-client-registry*))

;;; ============================================================================
;;; define-skel-class Macro Tests
;;; ============================================================================

(test define-skel-class-basic
  "Test basic SKEL class definition"
  (clear-skel-registry)

  ;; Define a simple SKEL class
  (eval '(define-skel-class test-person ()
          ((name :type string
                 :description "Person's full name"
                 :required t)
           (age :type integer
                :description "Person's age in years"))))

  ;; Check class was created
  (is (find-class 'test-person))

  ;; Check metadata was registered
  (is (skel-class-p 'test-person))

  (let ((metadata (get-skel-class 'test-person)))
    (is (not (null metadata)))
    (is (eq 'test-person (skel-class-name metadata)))
    (is (= 2 (length (skel-class-slots metadata))))))

(test define-skel-class-slots-metadata
  "Test that slot metadata is correctly captured"
  (clear-skel-registry)

  (eval '(define-skel-class test-experience ()
          ((role :type string
                 :description "Job title"
                 :required t)
           (company :type string
                    :description "Company name"
                    :required t)
           (start-date :type string
                       :description "Start date (YYYY-MM format)")
           (end-date :type (or string null)
                     :description "End date or null if current"
                     :default nil))))

  (let ((metadata (get-skel-class 'test-experience)))
    ;; Check slot count
    (is (= 4 (length (skel-class-slots metadata))))

    ;; Check role slot
    (let ((role-slot (get-skel-slot 'test-experience 'role)))
      (is (not (null role-slot)))
      (is (eq 'string (skel-slot-type role-slot)))
      (is (string= "Job title" (skel-slot-description role-slot)))
      (is (skel-slot-required-p role-slot)))

    ;; Check end-date slot with default
    (let ((end-slot (get-skel-slot 'test-experience 'end-date)))
      (is (equal '(or string null) (skel-slot-type end-slot)))
      (is (null (skel-slot-required-p end-slot)))
      (is (null (skel-slot-default-value end-slot))))))

(test define-skel-class-documentation
  "Test class documentation is captured"
  (clear-skel-registry)

  (eval '(define-skel-class test-resume ()
          ((name :type string :required t))
          (:documentation "A resume document")))

  (let ((metadata (get-skel-class 'test-resume)))
    (is (string= "A resume document" (skel-class-documentation metadata)))))

(test define-skel-class-creates-accessors
  "Test that CLOS accessors are created for slots"
  (clear-skel-registry)

  (eval '(define-skel-class test-item ()
          ((title :type string)
           (quantity :type integer))))

  ;; Create an instance
  (let ((item (make-instance 'test-item :title "Test" :quantity 42)))
    ;; Check slot accessors work
    (is (string= "Test" (title item)))
    (is (= 42 (quantity item)))

    ;; Check setf works
    (setf (title item) "Updated")
    (is (string= "Updated" (title item)))))

;;; ============================================================================
;;; Slot Introspection Tests
;;; ============================================================================

(test skel-class-required-slots-function
  "Test skel-class-required-slots returns correct slots"
  (clear-skel-registry)

  (eval '(define-skel-class test-required ()
          ((req1 :type string :required t)
           (opt1 :type string)
           (req2 :type integer :required t)
           (opt2 :type integer))))

  (let ((required (skel-class-required-slots 'test-required)))
    (is (= 2 (length required)))
    (is (member 'req1 required))
    (is (member 'req2 required))
    (is (not (member 'opt1 required)))
    (is (not (member 'opt2 required)))))

(test skel-class-slot-names-function
  "Test skel-class-slot-names returns all slot names"
  (clear-skel-registry)

  (eval '(define-skel-class test-slots ()
          ((alpha :type string)
           (beta :type integer)
           (gamma :type boolean))))

  (let ((names (skel-class-slot-names 'test-slots)))
    (is (= 3 (length names)))
    (is (member 'alpha names))
    (is (member 'beta names))
    (is (member 'gamma names))))

;;; ============================================================================
;;; JSON Key Conversion Tests
;;; ============================================================================

(test lisp-name-to-json-key-conversion
  "Test Lisp name to JSON key conversion"
  ;; Simple names
  (is (string= "name" (lisp-name-to-json-key 'name)))
  (is (string= "age" (lisp-name-to-json-key 'age)))

  ;; Hyphenated names should become camelCase
  (is (string= "startDate" (lisp-name-to-json-key 'start-date)))
  (is (string= "endDate" (lisp-name-to-json-key 'end-date)))
  (is (string= "firstName" (lisp-name-to-json-key 'first-name)))

  ;; Multiple hyphens
  (is (string= "myLongVariableName" (lisp-name-to-json-key 'my-long-variable-name))))

(test skel-slot-effective-json-key-default
  "Test default JSON key derivation from slot name"
  (clear-skel-registry)

  (eval '(define-skel-class test-json-keys ()
          ((start-date :type string)
           (end-date :type string))))

  (let ((start-slot (get-skel-slot 'test-json-keys 'start-date))
        (end-slot (get-skel-slot 'test-json-keys 'end-date)))
    (is (string= "startDate" (skel-slot-effective-json-key start-slot)))
    (is (string= "endDate" (skel-slot-effective-json-key end-slot)))))

(test skel-slot-explicit-json-key
  "Test explicit JSON key override"
  (clear-skel-registry)

  (eval '(define-skel-class test-explicit-key ()
          ((start-date :type string :json-key "start_date")
           (end-date :type string))))

  (let ((start-slot (get-skel-slot 'test-explicit-key 'start-date))
        (end-slot (get-skel-slot 'test-explicit-key 'end-date)))
    ;; Explicit key should be used
    (is (string= "start_date" (skel-slot-effective-json-key start-slot)))
    ;; Default camelCase for non-explicit
    (is (string= "endDate" (skel-slot-effective-json-key end-slot)))))

;;; ============================================================================
;;; Instance Creation Tests
;;; ============================================================================

(test make-skel-instance-basic
  "Test make-skel-instance creates instances correctly"
  (clear-skel-registry)

  (eval '(define-skel-class test-make ()
          ((name :type string :required t)
           (value :type integer))))

  (let ((instance (make-skel-instance 'test-make :name "Test" :value 42)))
    (is (typep instance 'test-make))
    (is (string= "Test" (name instance)))
    (is (= 42 (value instance)))))

(test make-skel-instance-validates-required
  "Test make-skel-instance signals error for missing required slots"
  (clear-skel-registry)

  (eval '(define-skel-class test-required-validation ()
          ((required-field :type string :required t)
           (optional-field :type string))))

  ;; Missing required field should signal error
  (signals skel-class-error
    (make-skel-instance 'test-required-validation :optional-field "test"))

  ;; With required field should succeed
  (finishes
    (make-skel-instance 'test-required-validation :required-field "test")))

(test make-skel-instance-non-skel-class-error
  "Test make-skel-instance signals error for non-SKEL classes"
  (signals skel-class-error
    (make-skel-instance 'not-a-skel-class :foo "bar")))

;;; ============================================================================
;;; Instance to Plist Conversion Tests
;;; ============================================================================

(test skel-instance-to-plist-basic
  "Test converting SKEL instance to property list"
  (clear-skel-registry)

  (eval '(define-skel-class test-plist ()
          ((name :type string)
           (start-date :type string)
           (quantity :type integer))))

  (let* ((instance (make-instance 'test-plist
                                  :name "Test"
                                  :start-date "2024-01"
                                  :quantity 42))
         (plist (skel-instance-to-plist instance)))
    ;; Check keys are JSON style
    (is (not (null (getf plist :|name|))))
    (is (not (null (getf plist :|startDate|))))
    (is (not (null (getf plist :|quantity|))))

    ;; Check values
    (is (string= "Test" (getf plist :|name|)))
    (is (string= "2024-01" (getf plist :|startDate|)))
    (is (= 42 (getf plist :|quantity|)))))

;;; ============================================================================
;;; Registry Tests
;;; ============================================================================

(test list-skel-classes-function
  "Test listing all registered SKEL classes"
  (clear-skel-registry)

  (eval '(define-skel-class test-class-a () ((x :type string))))
  (eval '(define-skel-class test-class-b () ((y :type integer))))
  (eval '(define-skel-class test-class-c () ((z :type boolean))))

  (let ((classes (list-skel-classes)))
    (is (= 3 (length classes)))
    (is (member 'test-class-a classes))
    (is (member 'test-class-b classes))
    (is (member 'test-class-c classes))))

(test skel-class-p-predicate
  "Test skel-class-p predicate"
  (clear-skel-registry)

  (eval '(define-skel-class test-is-skel () ((x :type string))))

  (is (skel-class-p 'test-is-skel))
  (is (not (skel-class-p 'not-a-skel-class)))
  (is (not (skel-class-p 'standard-class))))

;;; ============================================================================
;;; Complex Type Tests
;;; ============================================================================

(test define-skel-class-complex-types
  "Test SKEL class with complex type specifiers"
  (clear-skel-registry)

  (eval '(define-skel-class test-complex-types ()
          ((strings :type (list-of string)
                    :description "A list of strings")
           (optional-int :type (or integer null)
                         :description "Optional integer")
           (nested :type test-nested
                   :description "Nested SKEL class reference"))))

  (let ((metadata (get-skel-class 'test-complex-types)))
    (is (= 3 (length (skel-class-slots metadata))))

    (let ((strings-slot (get-skel-slot 'test-complex-types 'strings)))
      (is (equal '(list-of string) (skel-slot-type strings-slot))))

    (let ((optional-slot (get-skel-slot 'test-complex-types 'optional-int)))
      (is (equal '(or integer null) (skel-slot-type optional-slot))))))

;;; ============================================================================
;;; PRD Example: Resume Schema
;;; ============================================================================

(test prd-example-resume-schema
  "Test the resume schema example from the PRD"
  (clear-skel-registry)

  ;; Define experience class
  (eval '(define-skel-class experience ()
          ((role :type string
                 :description "Job title"
                 :required t)
           (company :type string
                    :description "Company name"
                    :required t)
           (start-date :type string
                       :description "Start date (YYYY-MM format)")
           (end-date :type (or string null)
                     :description "End date or null if current"
                     :default nil))
          (:documentation "A work experience entry")))

  ;; Define resume class
  (eval '(define-skel-class resume ()
          ((name :type string
                 :description "Full name of the candidate"
                 :required t)
           (email :type (or string null)
                  :description "Email address")
           (experiences :type (list-of experience)
                        :description "Work history, newest first"
                        :default nil)
           (skills :type (list-of string)
                   :description "Technical skills"
                   :default nil))
          (:documentation "Extracted resume information")))

  ;; Verify experience class
  (is (skel-class-p 'experience))
  (let ((exp-meta (get-skel-class 'experience)))
    (is (string= "A work experience entry" (skel-class-documentation exp-meta)))
    (is (= 4 (length (skel-class-slots exp-meta))))
    (is (equal '(role company) (skel-class-required-slots 'experience))))

  ;; Verify resume class
  (is (skel-class-p 'resume))
  (let ((res-meta (get-skel-class 'resume)))
    (is (string= "Extracted resume information" (skel-class-documentation res-meta)))
    (is (= 4 (length (skel-class-slots res-meta))))
    (is (equal '(name) (skel-class-required-slots 'resume))))

  ;; Create instances
  (let ((exp (make-instance 'experience
                            :role "Software Engineer"
                            :company "Acme Corp"
                            :start-date "2020-01"
                            :end-date nil)))
    (is (string= "Software Engineer" (role exp)))
    (is (string= "Acme Corp" (company exp))))

  (let ((resume (make-instance 'resume
                               :name "John Doe"
                               :email "john@example.com"
                               :skills '("Python" "JavaScript"))))
    (is (string= "John Doe" (name resume)))
    (is (equal '("Python" "JavaScript") (skills resume)))))

;;; ============================================================================
;;; SAP Preprocessor Tests
;;; ============================================================================

(test strip-markdown-fences-basic
  "Test basic markdown fence stripping"
  ;; Simple JSON fence
  (is (string= "{\"key\": \"value\"}"
               (strip-markdown-fences "```json
{\"key\": \"value\"}
```")))

  ;; Fence without language specifier
  (is (string= "{\"a\": 1}"
               (strip-markdown-fences "```
{\"a\": 1}
```")))

  ;; Fence with different language
  (is (string= "(list 1 2 3)"
               (strip-markdown-fences "```lisp
(list 1 2 3)
```"))))

(test strip-markdown-fences-multiple
  "Test stripping multiple markdown fences"
  (let ((input "```json
{\"first\": 1}
```

Some text in between.

```json
{\"second\": 2}
```"))
    ;; Should strip all fences
    (let ((result (strip-markdown-fences input)))
      (is (search "{\"first\": 1}" result))
      (is (search "{\"second\": 2}" result))
      (is (not (search "```" result))))))

(test strip-markdown-fences-no-fences
  "Test that text without fences is returned unchanged (trimmed)"
  (is (string= "{\"key\": \"value\"}"
               (strip-markdown-fences "  {\"key\": \"value\"}  ")))
  (is (string= "plain text"
               (strip-markdown-fences "plain text"))))

(test strip-markdown-fences-edge-cases
  "Test edge cases for markdown fence stripping"
  ;; Empty string
  (is (string= "" (strip-markdown-fences "")))
  ;; Nil
  (is (string= "" (strip-markdown-fences nil)))
  ;; Only whitespace
  (is (string= "" (strip-markdown-fences "   "))))

(test extract-structured-portion-basic
  "Test extracting structured JSON from preamble"
  ;; Simple case - preamble followed by JSON
  (is (string= "{\"name\": \"John\"}"
               (extract-structured-portion "Here is the result:
{\"name\": \"John\"}")))

  ;; JSON with array
  (is (string= "[1, 2, 3]"
               (extract-structured-portion "Let me provide the list:
[1, 2, 3]"))))

(test extract-structured-portion-chain-of-thought
  "Test stripping chain-of-thought preamble"
  ;; Common COT patterns
  (is (char= #\{
             (char (extract-structured-portion
                    "Let me analyze this request. Based on the input, here is the result:
{\"answer\": 42}") 0)))

  (is (char= #\[
             (char (extract-structured-portion
                    "I'll process the data. Looking at the requirements:
[\"item1\", \"item2\"]") 0))))

(test extract-structured-portion-no-preamble
  "Test extraction when structured data is at the start"
  ;; Already structured - should return as-is
  (is (string= "{\"key\": \"value\"}"
               (extract-structured-portion "{\"key\": \"value\"}")))
  (is (string= "[1, 2, 3]"
               (extract-structured-portion "[1, 2, 3]")))
  (is (string= "(defun foo () t)"
               (extract-structured-portion "(defun foo () t)"))))

(test extract-structured-portion-edge-cases
  "Test edge cases for structured extraction"
  ;; Empty string
  (is (string= "" (extract-structured-portion "")))
  ;; Nil
  (is (string= "" (extract-structured-portion nil)))
  ;; No structural characters
  (is (string= "just plain text"
               (extract-structured-portion "just plain text"))))

;;; ============================================================================
;;; JSON Normalizer Tests
;;; ============================================================================

(test fix-unquoted-keys-basic
  "Test fixing unquoted JSON keys"
  ;; Single key
  (is (string= "{\"name\": \"John\"}"
               (fix-unquoted-keys "{name: \"John\"}")))

  ;; Multiple keys
  (is (string= "{\"name\": \"John\", \"age\": 30}"
               (fix-unquoted-keys "{name: \"John\", age: 30}")))

  ;; Nested object with unquoted keys
  (is (string= "{\"person\": {\"name\": \"John\"}}"
               (fix-unquoted-keys "{person: {name: \"John\"}}"))))

(test fix-unquoted-keys-already-quoted
  "Test that already quoted keys are preserved"
  (is (string= "{\"name\": \"John\"}"
               (fix-unquoted-keys "{\"name\": \"John\"}")))

  (is (string= "{\"first_name\": \"John\", \"lastName\": \"Doe\"}"
               (fix-unquoted-keys "{\"first_name\": \"John\", \"lastName\": \"Doe\"}"))))

(test fix-unquoted-keys-with-underscores
  "Test fixing keys with underscores"
  (is (string= "{\"first_name\": \"John\"}"
               (fix-unquoted-keys "{first_name: \"John\"}"))))

(test fix-single-quotes-basic
  "Test converting single quotes to double quotes"
  ;; Simple string
  (is (string= "{\"key\": \"value\"}"
               (fix-single-quotes "{'key': 'value'}")))

  ;; Mixed - double should stay, single should convert
  (is (string= "{\"key\": \"value\"}"
               (fix-single-quotes "{\"key\": 'value'}"))))

(test fix-single-quotes-edge-cases
  "Test edge cases for single quote conversion"
  ;; Empty string
  (is (string= "" (fix-single-quotes "")))
  ;; Nil
  (is (string= "" (fix-single-quotes nil)))
  ;; No quotes at all
  (is (string= "{key: 123}"
               (fix-single-quotes "{key: 123}"))))

(test fix-trailing-commas-basic
  "Test removing trailing commas"
  ;; Array
  (is (string= "[1, 2, 3]"
               (fix-trailing-commas "[1, 2, 3,]")))

  ;; Object
  (is (string= "{\"a\": 1, \"b\": 2}"
               (fix-trailing-commas "{\"a\": 1, \"b\": 2,}")))

  ;; Nested
  (is (string= "{\"arr\": [1, 2, 3], \"obj\": {\"x\": 1}}"
               (fix-trailing-commas "{\"arr\": [1, 2, 3,], \"obj\": {\"x\": 1,},}"))))

(test fix-trailing-commas-with-whitespace
  "Test removing trailing commas with various whitespace"
  (is (string= "[1, 2, 3]"
               (fix-trailing-commas "[1, 2, 3,  ]")))
  (is (string= "{\"a\": 1}"
               (fix-trailing-commas "{\"a\": 1,
}"))))

(test normalize-json-ish-combined
  "Test combined JSON normalization"
  ;; All fixes at once
  (is (string= "{\"name\": \"John\", \"age\": 30}"
               (normalize-json-ish "{name: 'John', age: 30,}")))

  ;; Nested with all issues
  (is (string= "{\"person\": {\"name\": \"John\", \"active\": true}}"
               (normalize-json-ish "{person: {name: 'John', active: true,},}"))))

(test normalize-json-ish-edge-cases
  "Test edge cases for combined normalization"
  ;; Empty
  (is (string= "" (normalize-json-ish "")))
  ;; Nil
  (is (string= "" (normalize-json-ish nil)))
  ;; Already valid JSON
  (is (string= "{\"key\": \"value\"}"
               (normalize-json-ish "{\"key\": \"value\"}"))))

;;; ============================================================================
;;; Main sap-preprocess Tests
;;; ============================================================================

(test sap-preprocess-full-pipeline
  "Test the complete SAP preprocessing pipeline"
  ;; Full example with markdown fence, preamble, and JSON issues
  (let ((input "Here's the extracted data:

```json
{name: 'John', age: 30, skills: ['Python', 'Lisp',],}
```"))
    (let ((result (sap-preprocess input)))
      ;; Fences should be removed
      (is (not (search "```" result)))
      ;; Keys should be quoted
      (is (search "\"name\"" result))
      (is (search "\"age\"" result))
      ;; Single quotes should be double quotes
      (is (search "\"John\"" result))
      ;; Trailing commas should be removed
      (is (not (search ",]" result)))
      (is (not (search ",}" result))))))

(test sap-preprocess-simple-json
  "Test SAP preprocessing with already valid JSON"
  (let ((input "{\"key\": \"value\"}"))
    (is (string= input (sap-preprocess input)))))

(test sap-preprocess-edge-cases
  "Test SAP preprocessing edge cases"
  ;; Empty
  (is (string= "" (sap-preprocess "")))
  ;; Nil
  (is (string= "" (sap-preprocess nil)))
  ;; Whitespace only
  (is (string= "" (sap-preprocess "   "))))

(test sap-preprocess-signals-error-for-non-string
  "Test that non-string input signals an error"
  (signals sap-preprocessing-error
    (sap-preprocess 123))
  (signals sap-preprocessing-error
    (sap-preprocess '(list 1 2 3))))

(test sap-preprocess-realistic-llm-output
  "Test with realistic LLM output patterns"
  ;; Pattern 1: Chain of thought + JSON
  (let ((output1 "Let me analyze this resume and extract the relevant information.

Based on the text provided, here is the structured data:

```json
{
  name: 'John Doe',
  email: 'john@example.com',
  skills: ['Python', 'JavaScript', 'Common Lisp',],
}
```"))
    (let ((result (sap-preprocess output1)))
      (is (search "\"name\"" result))
      (is (search "\"John Doe\"" result))
      (is (not (search "```" result)))
      (is (not (search "Let me" result)))))

  ;; Pattern 2: Just the JSON with fence
  (let ((output2 "```json
{\"answer\": 42}
```"))
    (is (string= "{\"answer\": 42}" (sap-preprocess output2))))

  ;; Pattern 3: Mixed quotes and issues
  (let ((output3 "{firstName: 'Jane', lastName: \"Doe\", active: true,}"))
    (let ((result (sap-preprocess output3)))
      (is (search "\"firstName\"" result))
      (is (search "\"Jane\"" result))
      (is (search "\"lastName\"" result))
      (is (not (search ",}" result))))))

;;; ============================================================================
;;; Partial Type Generation Tests
;;; ============================================================================

(defun clear-partial-registry ()
  "Clear the partial class registry for test isolation."
  (clrhash autopoiesis.skel::*partial-classes*))

(test partial-class-name-generation
  "Test generating partial class names"
  (is (eq 'partial-resume (make-partial-class-name 'resume)))
  (is (eq 'partial-experience (make-partial-class-name 'experience)))
  (is (eq 'partial-test-class (make-partial-class-name 'test-class))))

(test ensure-partial-class-basic
  "Test ensuring partial class exists for a SKEL class"
  (clear-skel-registry)
  (clear-partial-registry)

  ;; Define a simple SKEL class
  (eval '(define-skel-class test-simple ()
          ((name :type string :required t)
           (value :type integer))))

  ;; Ensure partial class
  (let ((partial-name (ensure-partial-class 'test-simple)))
    (is (eq 'partial-test-simple partial-name))
    (is (find-class 'partial-test-simple))
    (is (partial-class-p 'test-simple))))

(test ensure-partial-class-all-fields-optional
  "Test that all fields in partial class are optional (can be nil)"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-required ()
          ((required-field :type string :required t)
           (optional-field :type string))))

  (ensure-partial-class 'test-required)

  ;; Should be able to create partial with all nil values
  (finishes
    (make-instance 'partial-test-required))

  ;; All slots should accept nil
  (let ((partial (make-instance 'partial-test-required)))
    (is (null (required-field partial)))
    (is (null (optional-field partial)))))

(test ensure-partial-class-non-skel-error
  "Test that ensure-partial-class signals error for non-SKEL classes"
  (signals skel-class-error
    (ensure-partial-class 'not-a-skel-class)))

(test partial-metadata-slots
  "Test that partial classes have metadata slots"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-meta ()
          ((name :type string))))

  (ensure-partial-class 'test-meta)

  (let ((partial (make-instance 'partial-test-meta)))
    ;; Should have %complete-p slot
    (is (not (partial-complete-p partial)))
    (setf (partial-complete-p partial) t)
    (is (partial-complete-p partial))

    ;; Should have %fields-received slot
    (is (null (partial-fields-received partial)))
    (setf (partial-fields-received partial) '(name))
    (is (equal '(name) (partial-fields-received partial)))))

(test make-partial-instance-function
  "Test make-partial-instance creates partial instances"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-partial-make ()
          ((name :type string :required t)
           (value :type integer))))

  (let ((partial (make-partial-instance 'test-partial-make :name "Test")))
    (is (string= "Test" (name partial)))
    (is (null (value partial)))
    (is (typep partial 'partial-test-partial-make))))

(test partial-instance-p-predicate
  "Test partial-instance-p predicate"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-partial-pred ()
          ((x :type string))))

  (ensure-partial-class 'test-partial-pred)

  (let ((full-instance (make-instance 'test-partial-pred :x "test"))
        (partial-instance (make-instance 'partial-test-partial-pred :x "test")))
    (is (not (partial-instance-p full-instance)))
    (is (partial-instance-p partial-instance))))

(test update-partial-field-function
  "Test updating fields in partial instance"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-update ()
          ((name :type string)
           (age :type integer))))

  (let ((partial (make-partial-instance 'test-update)))
    ;; Initially empty
    (is (null (name partial)))
    (is (null (partial-fields-received partial)))

    ;; Update name
    (update-partial-field partial 'name "John")
    (is (string= "John" (name partial)))
    (is (member 'name (partial-fields-received partial)))

    ;; Update age
    (update-partial-field partial 'age 30)
    (is (= 30 (age partial)))
    (is (member 'age (partial-fields-received partial)))
    (is (= 2 (length (partial-fields-received partial))))))

(test partial-field-received-p-function
  "Test checking if field was received"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-received ()
          ((a :type string)
           (b :type integer))))

  (let ((partial (make-partial-instance 'test-received)))
    (is (not (partial-field-received-p partial 'a)))
    (is (not (partial-field-received-p partial 'b)))

    (update-partial-field partial 'a "value")
    (is (partial-field-received-p partial 'a))
    (is (not (partial-field-received-p partial 'b)))))

(test partial-coverage-function
  "Test calculating field coverage"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-coverage ()
          ((a :type string)
           (b :type string)
           (c :type string)
           (d :type string))))

  (let ((partial (make-partial-instance 'test-coverage)))
    ;; Initially 0% coverage
    (is (= 0.0 (partial-coverage partial)))

    ;; Update 1 field -> 25%
    (update-partial-field partial 'a "v1")
    (is (= 0.25 (partial-coverage partial)))

    ;; Update 2 fields -> 50%
    (update-partial-field partial 'b "v2")
    (is (= 0.5 (partial-coverage partial)))

    ;; Update all fields -> 100%
    (update-partial-field partial 'c "v3")
    (update-partial-field partial 'd "v4")
    (is (= 1.0 (partial-coverage partial)))))

(test partial-to-full-conversion
  "Test converting partial instance to full instance"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-convert ()
          ((name :type string :required t)
           (value :type integer))))

  (let ((partial (make-partial-instance 'test-convert)))
    ;; Missing required field should fail
    (update-partial-field partial 'value 42)
    (signals skel-class-error
      (partial-to-full partial))

    ;; With required field should succeed
    (update-partial-field partial 'name "Test")
    (let ((full (partial-to-full partial)))
      (is (typep full 'test-convert))
      (is (string= "Test" (name full)))
      (is (= 42 (value full))))))

(test mark-partial-complete-function
  "Test marking partial as complete"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-complete ()
          ((x :type string))))

  (let ((partial (make-partial-instance 'test-complete)))
    (is (not (partial-complete-p partial)))
    (mark-partial-complete partial)
    (is (partial-complete-p partial))))

(test get-partial-type-skel-class
  "Test get-partial-type for SKEL classes"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-get-partial ()
          ((x :type string))))

  (let ((partial-type (get-partial-type 'test-get-partial)))
    (is (eq 'partial-test-get-partial partial-type))))

(test get-partial-type-list-of
  "Test get-partial-type for list-of SKEL classes"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-list-item ()
          ((value :type string))))

  (let ((partial-type (get-partial-type '(list-of test-list-item))))
    (is (consp partial-type))
    (is (eq 'list-of (car partial-type)))
    (is (eq 'partial-test-list-item (cadr partial-type)))))

(test get-partial-type-non-skel
  "Test get-partial-type for non-SKEL types"
  ;; Primitive types should be returned as-is
  (is (eq 'string (get-partial-type 'string)))
  (is (eq 'integer (get-partial-type 'integer)))
  (is (equal '(or string null) (get-partial-type '(or string null)))))

(test partial-class-metadata-retrieval
  "Test retrieving partial class metadata"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-meta-retrieve ()
          ((a :type string :description "Field A")
           (b :type integer :description "Field B"))))

  (ensure-partial-class 'test-meta-retrieve)

  (let ((meta (get-partial-class 'test-meta-retrieve)))
    (is (not (null meta)))
    (is (eq 'test-meta-retrieve (partial-original-class meta)))
    (is (eq 'partial-test-meta-retrieve (partial-class-name meta)))
    (is (= 2 (length (partial-class-slots meta))))))

(test list-partial-classes-function
  "Test listing all partial classes"
  (clear-skel-registry)
  (clear-partial-registry)

  (eval '(define-skel-class test-list-a () ((x :type string))))
  (eval '(define-skel-class test-list-b () ((y :type integer))))

  (ensure-partial-class 'test-list-a)
  (ensure-partial-class 'test-list-b)

  (let ((partials (list-partial-classes)))
    (is (= 2 (length partials)))
    (is (member 'test-list-a partials))
    (is (member 'test-list-b partials))))

(test prd-example-partial-resume
  "Test partial types with the resume example from PRD"
  (clear-skel-registry)
  (clear-partial-registry)

  ;; Define the SKEL classes as in PRD
  (eval '(define-skel-class prd-experience ()
          ((role :type string :required t)
           (company :type string :required t)
           (start-date :type string)
           (end-date :type (or string null) :default nil))))

  (eval '(define-skel-class prd-resume ()
          ((name :type string :required t)
           (email :type (or string null))
           (experiences :type (list-of prd-experience) :default nil)
           (skills :type (list-of string) :default nil))))

  ;; Generate partial types
  (ensure-partial-class 'prd-resume)
  (ensure-partial-class 'prd-experience)

  ;; Verify partial-resume exists
  (is (find-class 'partial-prd-resume))
  (is (find-class 'partial-prd-experience))

  ;; Create a partial resume as if from streaming
  (let ((partial (make-instance 'partial-prd-resume)))
    ;; All fields are nil initially
    (is (null (name partial)))
    (is (null (email partial)))
    (is (null (experiences partial)))
    (is (null (skills partial)))

    ;; Simulate streaming updates
    (update-partial-field partial 'name "John Doe")
    (is (string= "John Doe" (name partial)))
    (is (= 0.25 (partial-coverage partial)))

    (update-partial-field partial 'skills '("Python" "Lisp"))
    (is (= 0.5 (partial-coverage partial)))

    ;; Check fields received
    (is (partial-field-received-p partial 'name))
    (is (partial-field-received-p partial 'skills))
    (is (not (partial-field-received-p partial 'email)))
    (is (not (partial-field-received-p partial 'experiences)))))

;;; ============================================================================
;;; Core Synchronous API Tests
;;; ============================================================================

(defun clear-function-registry ()
  "Clear the SKEL function registry for test isolation."
  (clear-skel-functions))

;;; ----------------------------------------------------------------------------
;;; Function Definition Tests
;;; ----------------------------------------------------------------------------

(test define-skel-function-basic
  "Test basic SKEL function definition"
  (clear-function-registry)

  (eval '(define-skel-function test-greet
             ((name :string :description "Name to greet"))
           :prompt "Say hello to {{ name }}"
           :return-type :string))

  ;; Function should be registered
  (let ((func (get-skel-function 'test-greet)))
    (is (not (null func)))
    (is (eq 'test-greet (skel-function-name func)))
    (is (string= "Say hello to {{ name }}" (skel-function-prompt func)))
    (is (eq :string (skel-function-return-type func)))))

(test define-skel-function-parameters
  "Test SKEL function parameter definitions"
  (clear-function-registry)

  (eval '(define-skel-function test-params
             ((required-param :string :description "A required param")
              (optional-param :integer :required nil :default 42))
           :prompt "Test: {{ required-param }} {{ optional-param }}"
           :return-type :string))

  (let* ((func (get-skel-function 'test-params))
         (params (skel-function-parameters func)))
    (is (= 2 (length params)))

    ;; First param: required
    (let ((p1 (first params)))
      (is (eq 'required-param (skel-parameter-name p1)))
      (is (eq :string (skel-parameter-type p1)))
      (is (skel-parameter-required p1)))

    ;; Second param: optional with default
    (let ((p2 (second params)))
      (is (eq 'optional-param (skel-parameter-name p2)))
      (is (eq :integer (skel-parameter-type p2)))
      (is (not (skel-parameter-required p2)))
      (is (= 42 (skel-parameter-default p2))))))

(test define-skel-function-with-config
  "Test SKEL function with custom configuration"
  (clear-function-registry)

  (eval '(define-skel-function test-configured
             ((text :string))
           :prompt "Process: {{ text }}"
           :return-type :string
           :config (make-skel-config :temperature 0.2 :max-tokens 100)))

  (let* ((func (get-skel-function 'test-configured))
         (config (skel-function-config func)))
    (is (not (null config)))
    (is (= 0.2 (config-temperature config)))
    (is (= 100 (config-max-tokens config)))))

;;; ----------------------------------------------------------------------------
;;; Function Registry Tests
;;; ----------------------------------------------------------------------------

(test list-skel-functions-test
  "Test listing all registered SKEL functions"
  (clear-function-registry)

  (eval '(define-skel-function func-a ((x :string)) :prompt "{{ x }}"))
  (eval '(define-skel-function func-b ((y :integer)) :prompt "{{ y }}"))

  (let ((funcs (list-skel-functions)))
    (is (= 2 (length funcs)))
    (is (member 'func-a funcs))
    (is (member 'func-b funcs))))

(test clear-skel-functions-test
  "Test clearing the function registry"
  (clear-function-registry)

  (eval '(define-skel-function temp-func ((x :string)) :prompt "{{ x }}"))
  (is (not (null (get-skel-function 'temp-func))))

  (clear-skel-functions)
  (is (null (get-skel-function 'temp-func)))
  (is (null (list-skel-functions))))

;;; ----------------------------------------------------------------------------
;;; Prompt Interpolation Tests
;;; ----------------------------------------------------------------------------

(test interpolate-prompt-basic
  "Test basic template interpolation"
  (is (string= "Hello World!"
               (interpolate-prompt "Hello {{ name }}!" '(:name "World"))))

  (is (string= "Value: 42"
               (interpolate-prompt "Value: {{ x }}" '(:x 42)))))

(test interpolate-prompt-multiple-vars
  "Test interpolation with multiple variables"
  (is (string= "Name: John, Age: 30"
               (interpolate-prompt "Name: {{ name }}, Age: {{ age }}"
                                   '(:name "John" :age 30)))))

(test interpolate-prompt-missing-var
  "Test interpolation with missing variable"
  ;; Missing variables should be left as-is (for debugging)
  (let ((result (interpolate-prompt "Hello {{ name }}" '())))
    ;; The placeholder remains if no value provided
    (is (search "{{" result))))

(test interpolate-prompt-whitespace-in-placeholder
  "Test interpolation handles whitespace in placeholders"
  (is (string= "Hello World!"
               (interpolate-prompt "Hello {{  name  }}!" '(:name "World"))))
  (is (string= "Value: 42"
               (interpolate-prompt "Value: {{name}}" '(:name 42)))))

(test interpolate-prompt-function
  "Test interpolation with function template"
  (let ((template (lambda (&key name)
                    (format nil "Hello ~A!" name))))
    (is (string= "Hello World!"
                 (interpolate-prompt template '(:name "World"))))))

;;; ----------------------------------------------------------------------------
;;; Argument Validation Tests
;;; ----------------------------------------------------------------------------

(test validate-skel-arguments-basic
  "Test basic argument validation"
  (clear-function-registry)

  (eval '(define-skel-function test-validate
             ((name :string)
              (age :integer :required nil :default 0))
           :prompt "{{ name }} {{ age }}"))

  (let ((func (get-skel-function 'test-validate)))
    ;; Valid args
    (let ((validated (validate-skel-arguments func '(:name "John" :age 30))))
      (is (string= "John" (getf validated :name)))
      (is (= 30 (getf validated :age))))

    ;; Optional arg uses default
    (let ((validated (validate-skel-arguments func '(:name "Jane"))))
      (is (string= "Jane" (getf validated :name)))
      (is (= 0 (getf validated :age))))))

(test validate-skel-arguments-missing-required
  "Test validation signals error for missing required args"
  (clear-function-registry)

  (eval '(define-skel-function test-required
             ((name :string :description "Required name"))
           :prompt "{{ name }}"))

  (let ((func (get-skel-function 'test-required)))
    (signals skel-validation-error
      (validate-skel-arguments func '()))))

;;; ----------------------------------------------------------------------------
;;; Response Parsing Tests
;;; ----------------------------------------------------------------------------

(test parse-llm-response-string
  "Test parsing string response"
  (is (string= "Hello World"
               (parse-llm-response "  Hello World  " :string))))

(test parse-llm-response-integer
  "Test parsing integer response"
  (is (= 42 (parse-llm-response "42" :integer)))
  (is (= 42 (parse-llm-response "  42  " :integer))))

(test parse-llm-response-boolean
  "Test parsing boolean response"
  (is (eq t (parse-llm-response "true" :boolean)))
  (is (eq nil (parse-llm-response "false" :boolean)))
  (is (eq t (parse-llm-response "yes" :boolean)))
  (is (eq nil (parse-llm-response "no" :boolean))))

(test parse-llm-response-json
  "Test parsing JSON response"
  (let ((result (parse-llm-response "{\"key\": \"value\"}" :json)))
    (is (listp result))
    (is (equal "value" (cdr (assoc :key result))))))

(test parse-llm-response-with-markdown-fence
  "Test parsing response with markdown fence"
  (let ((result (parse-llm-response "```json
{\"key\": \"value\"}
```" :json)))
    (is (listp result))
    (is (equal "value" (cdr (assoc :key result))))))

(test parse-llm-response-with-preamble
  "Test parsing response with chain-of-thought preamble"
  (let ((result (parse-llm-response "Let me analyze this.
Here is the result:
{\"answer\": 42}" :json)))
    (is (listp result))
    (is (= 42 (cdr (assoc :answer result))))))

(test parse-llm-response-normalize-json
  "Test parsing normalizes JSON-ish syntax"
  (let ((result (parse-llm-response "{name: 'John', age: 30,}" :json)))
    (is (listp result))
    (is (equal "John" (cdr (assoc :name result))))
    (is (= 30 (cdr (assoc :age result))))))

;;; ----------------------------------------------------------------------------
;;; Type Hint Formatting Tests
;;; ----------------------------------------------------------------------------

(test format-type-hint-primitives
  "Test type hint formatting for primitive types"
  (is (string= "Respond with plain text." (format-type-hint :string)))
  (is (string= "Respond with only an integer number." (format-type-hint :integer)))
  (is (string= "Respond with only a number." (format-type-hint :float)))
  (is (string= "Respond with only 'true' or 'false'." (format-type-hint :boolean)))
  (is (string= "Respond with valid JSON." (format-type-hint :json))))

(test format-type-hint-list-of
  "Test type hint formatting for list-of types"
  (is (string= "Respond with a JSON array of string values."
               (format-type-hint '(list-of :string)))))

(test format-type-hint-nil-for-unknown
  "Test type hint returns nil for unknown types"
  (is (null (format-type-hint :unknown-type)))
  (is (null (format-type-hint 'custom-class))))

;;; ----------------------------------------------------------------------------
;;; Build Prompt Tests
;;; ----------------------------------------------------------------------------

(test build-skel-prompt-basic
  "Test building a complete prompt"
  (clear-function-registry)

  (eval '(define-skel-function test-build
             ((text :string))
           :prompt "Process this: {{ text }}"
           :return-type :string))

  (let* ((func (get-skel-function 'test-build))
         (prompt (build-skel-prompt func '(:text "hello"))))
    (is (search "Process this: hello" prompt))
    ;; Should have type hint appended
    (is (search "Respond with plain text." prompt))))

(test build-skel-prompt-json-type
  "Test building prompt with JSON return type"
  (clear-function-registry)

  (eval '(define-skel-function test-json-build
             ((data :string))
           :prompt "Extract from: {{ data }}"
           :return-type :json))

  (let* ((func (get-skel-function 'test-json-build))
         (prompt (build-skel-prompt func '(:data "text"))))
    (is (search "Extract from: text" prompt))
    (is (search "Respond with valid JSON." prompt))))

;;; ----------------------------------------------------------------------------
;;; Error Handling Tests
;;; ----------------------------------------------------------------------------

(test invoke-unknown-function-error
  "Test invoking unknown function signals error"
  (clear-function-registry)
  (signals skel-error
    (invoke-skel-function 'nonexistent-function)))

(test invoke-without-client-error
  "Test invoking without client signals error"
  (clear-function-registry)

  (eval '(define-skel-function test-no-client
             ((x :string))
           :prompt "{{ x }}"))

  (let ((*current-llm-client* nil))
    (signals skel-error
      (invoke-skel-function 'test-no-client :x "test"))))

;;; ----------------------------------------------------------------------------
;;; Retry Logic Tests
;;; ----------------------------------------------------------------------------

(test call-with-retries-success
  "Test call-with-retries returns result on success"
  (let ((call-count 0))
    (let ((result (call-with-retries
                   (lambda ()
                     (incf call-count)
                     "success")
                   :count 3)))
      (is (string= "success" result))
      (is (= 1 call-count)))))

(test call-with-retries-retry-on-parse-error
  "Test call-with-retries retries on parse error"
  (let ((call-count 0))
    (handler-case
        (call-with-retries
         (lambda ()
           (incf call-count)
           (error 'skel-parse-error :message "test" :raw-response "bad"))
         :count 2
         :delay 0)  ; No delay in tests
      (skel-parse-error ()
        ;; Should have tried 3 times (1 initial + 2 retries)
        (is (= 3 call-count))))))

(test call-with-retries-eventual-success
  "Test call-with-retries succeeds after retry"
  (let ((call-count 0))
    (let ((result (call-with-retries
                   (lambda ()
                     (incf call-count)
                     (if (< call-count 2)
                         (error 'skel-parse-error :message "temp" :raw-response "x")
                         "success"))
                   :count 3
                   :delay 0)))
      (is (string= "success" result))
      (is (= 2 call-count)))))

;;; ============================================================================
;;; Type Validation Tests
;;; ============================================================================

(test validate-slot-value-primitives
  "Test validation of primitive types"
  ;; String
  (is (validate-slot-value "hello" 'string))
  (signals skel-class-error (validate-slot-value 123 'string))

  ;; Integer
  (is (validate-slot-value 42 'integer))
  (signals skel-class-error (validate-slot-value "42" 'integer))

  ;; Float
  (is (validate-slot-value 3.14 'float))
  (signals skel-class-error (validate-slot-value 42 'float))

  ;; Boolean
  (is (validate-slot-value t 'boolean))
  (is (validate-slot-value nil 'boolean))
  (signals skel-class-error (validate-slot-value "true" 'boolean))

  ;; Type T accepts anything
  (is (validate-slot-value "anything" t))
  (is (validate-slot-value 123 t))
  (is (validate-slot-value nil t)))

(test validate-slot-value-nil-handling
  "Test nil handling in validation"
  ;; Nil allowed by default
  (is (validate-slot-value nil 'string))
  (is (validate-slot-value nil 'integer))

  ;; Nil disallowed with :allow-nil nil
  (signals skel-class-error
    (validate-slot-value nil 'string :allow-nil nil)))

(test validate-slot-value-compound-types
  "Test validation of compound types"
  ;; Or type
  (is (validate-slot-value "hello" '(or string null)))
  (is (validate-slot-value nil '(or string null)))
  (signals skel-class-error (validate-slot-value 123 '(or string null)))

  ;; List-of type
  (is (validate-slot-value '("a" "b" "c") '(list-of string)))
  (is (validate-slot-value '(1 2 3) '(list-of integer)))
  (signals skel-class-error (validate-slot-value '("a" 1 "c") '(list-of string)))
  (signals skel-class-error (validate-slot-value "not-a-list" '(list-of string))))

(test validate-slot-value-skel-class-type
  "Test validation of SKEL class types"
  (clear-skel-registry)

  (eval '(define-skel-class test-validate-class ()
          ((name :type string))))

  (let ((instance (make-instance 'test-validate-class :name "test")))
    (is (validate-slot-value instance 'test-validate-class)))

  (signals skel-class-error
    (validate-slot-value "not-an-instance" 'test-validate-class)))

;;; ============================================================================
;;; Type Coercion Tests
;;; ============================================================================

(test coerce-slot-value-string
  "Test string coercion"
  (is (string= "hello" (coerce-slot-value "hello" 'string)))
  (is (string= "42" (coerce-slot-value 42 'string)))
  (is (string= "3.14" (coerce-slot-value 3.14 'string))))

(test coerce-slot-value-integer
  "Test integer coercion"
  (is (= 42 (coerce-slot-value 42 'integer)))
  (is (= 42 (coerce-slot-value "42" 'integer)))
  (is (= 4 (coerce-slot-value 3.7 'integer))))  ; round rounds to nearest even

(test coerce-slot-value-float
  "Test float coercion"
  (is (= 3.14 (coerce-slot-value 3.14 'float)))
  (is (= 42.0 (coerce-slot-value 42 'float))))

(test coerce-slot-value-boolean
  "Test boolean coercion"
  (is (eq t (coerce-slot-value t 'boolean)))
  (is (eq nil (coerce-slot-value nil 'boolean)))
  (is (eq t (coerce-slot-value "true" 'boolean)))
  (is (eq nil (coerce-slot-value "false" 'boolean)))
  (is (eq t (coerce-slot-value "yes" 'boolean)))
  (is (eq nil (coerce-slot-value "no" 'boolean))))

(test coerce-slot-value-nil
  "Test nil coercion"
  (is (null (coerce-slot-value nil 'string)))
  (is (null (coerce-slot-value nil 'integer))))

;;; ============================================================================
;;; Prompt Generation Tests
;;; ============================================================================

(test format-type-for-prompt-primitives
  "Test type formatting for prompt generation"
  (is (string= "string" (format-type-for-prompt 'string)))
  (is (string= "integer" (format-type-for-prompt 'integer)))
  (is (string= "number" (format-type-for-prompt 'float)))
  (is (string= "boolean" (format-type-for-prompt 'boolean)))
  (is (string= "any" (format-type-for-prompt t))))

(test format-type-for-prompt-compound
  "Test type formatting for compound types"
  (is (string= "string or null" (format-type-for-prompt '(or string null))))
  (is (string= "array of string" (format-type-for-prompt '(list-of string))))
  (is (string= "array of integer" (format-type-for-prompt '(list-of integer)))))

(test format-type-for-prompt-skel-class
  "Test type formatting for SKEL class types"
  (clear-skel-registry)

  (eval '(define-skel-class test-format-class ()
          ((x :type string))))

  (is (string= "test-format-class object"
               (format-type-for-prompt 'test-format-class))))

(test format-slot-for-prompt-function
  "Test slot formatting for prompt generation"
  (clear-skel-registry)

  (eval '(define-skel-class test-slot-prompt ()
          ((user-name :type string
                      :description "The user's display name"
                      :required t))))

  (let ((slot (get-skel-slot 'test-slot-prompt 'user-name)))
    (let ((formatted (format-slot-for-prompt slot)))
      (is (search "userName" formatted))
      (is (search "string" formatted))
      (is (search "[required]" formatted))
      (is (search "display name" formatted))))

  ;; Test without type
  (let* ((slot (get-skel-slot 'test-slot-prompt 'user-name))
         (formatted (format-slot-for-prompt slot :include-type nil)))
    (is (search "userName" formatted))
    (is (not (search "string" formatted)))))

(test format-class-schema-text
  "Test schema formatting in text mode"
  (clear-skel-registry)

  (eval '(define-skel-class test-schema-text ()
          ((name :type string :description "Name" :required t)
           (age :type integer :description "Age"))
          (:documentation "Test class")))

  (let ((schema (format-class-schema 'test-schema-text :style :text)))
    (is (search "test-schema-text" schema))
    (is (search "Test class" schema))
    (is (search "name" schema))
    (is (search "[required]" schema))))

(test format-class-schema-json
  "Test schema formatting in JSON mode"
  (clear-skel-registry)

  (eval '(define-skel-class test-schema-json ()
          ((first-name :type string :description "First name"))))

  (let ((schema (format-class-schema 'test-schema-json :style :json)))
    (is (search "firstName" schema))
    (is (search "<string>" schema))
    (is (search "First name" schema))))

(test format-class-schema-brief
  "Test schema formatting in brief mode"
  (clear-skel-registry)

  (eval '(define-skel-class test-schema-brief ()
          ((a :type string)
           (b :type integer))))

  (let ((schema (format-class-schema 'test-schema-brief :style :brief)))
    (is (search "test-schema-brief:" schema))
    (is (search "a:string" schema))
    (is (search "b:integer" schema))))

;;; ============================================================================
;;; Advanced Introspection Tests
;;; ============================================================================

(test skel-class-slots-of-type-function
  "Test finding slots by type"
  (clear-skel-registry)

  (eval '(define-skel-class test-slots-type ()
          ((name :type string)
           (quantity :type integer)
           (value :type integer)
           (active :type boolean))))

  ;; Find all integer slots
  (let ((int-slots (skel-class-slots-of-type 'test-slots-type 'integer)))
    (is (= 2 (length int-slots)))
    (is (member 'quantity (mapcar #'skel-slot-name int-slots)))
    (is (member 'value (mapcar #'skel-slot-name int-slots))))

  ;; Find string slots
  (let ((str-slots (skel-class-slots-of-type 'test-slots-type 'string)))
    (is (= 1 (length str-slots)))
    (is (eq 'name (skel-slot-name (first str-slots))))))

(test skel-class-slots-of-type-compound
  "Test finding slots by compound type"
  (clear-skel-registry)

  (eval '(define-skel-class test-compound-slots ()
          ((required-str :type string)
           (optional-str :type (or string null))
           (strings :type (list-of string)))))

  ;; Exact match for compound type
  (let ((or-slots (skel-class-slots-of-type 'test-compound-slots '(or string null) :exact t)))
    (is (= 1 (length or-slots)))
    (is (eq 'optional-str (skel-slot-name (first or-slots)))))

  ;; Non-exact match finds slots containing the type
  (let ((str-slots (skel-class-slots-of-type 'test-compound-slots 'string)))
    (is (= 3 (length str-slots)))))

(test skel-class-slots-with-description-function
  "Test finding slots with descriptions"
  (clear-skel-registry)

  (eval '(define-skel-class test-desc-slots ()
          ((with-desc :type string :description "Has a description")
           (no-desc :type integer)
           (date-field :type string :description "A date field"))))

  ;; All slots with descriptions
  (let ((desc-slots (skel-class-slots-with-description 'test-desc-slots)))
    (is (= 2 (length desc-slots)))
    (is (not (member 'no-desc (mapcar #'skel-slot-name desc-slots)))))

  ;; Pattern matching
  (let ((date-slots (skel-class-slots-with-description 'test-desc-slots :pattern "date")))
    (is (= 1 (length date-slots)))
    (is (eq 'date-field (skel-slot-name (first date-slots))))))

(test skel-class-optional-slots-function
  "Test finding optional slots"
  (clear-skel-registry)

  (eval '(define-skel-class test-optional ()
          ((req :type string :required t)
           (opt1 :type integer)
           (opt2 :type boolean))))

  (let ((optional (skel-class-optional-slots 'test-optional)))
    (is (= 2 (length optional)))
    (is (member 'opt1 optional))
    (is (member 'opt2 optional))
    (is (not (member 'req optional)))))

(test skel-class-slots-with-defaults-function
  "Test finding slots with defaults"
  (clear-skel-registry)

  (eval '(define-skel-class test-defaults ()
          ((no-default :type string)
           (with-default :type integer :default 42)
           (nil-default :type string :default nil))))

  (let ((default-slots (skel-class-slots-with-defaults 'test-defaults)))
    ;; Only explicit non-nil defaults
    (is (= 1 (length default-slots)))
    (is (eq 'with-default (skel-slot-name (first default-slots))))))

(test skel-slot-metadata-function
  "Test retrieving slot metadata as plist"
  (clear-skel-registry)

  (eval '(define-skel-class test-meta-plist ()
          ((test-slot :type string
                      :description "A test slot"
                      :required t
                      :default "default"
                      :json-key "customKey"))))

  (let ((meta (skel-slot-metadata 'test-meta-plist 'test-slot)))
    (is (eq 'test-slot (getf meta :name)))
    (is (eq 'string (getf meta :type)))
    (is (string= "A test slot" (getf meta :description)))
    (is (eq t (getf meta :required)))
    (is (string= "default" (getf meta :default)))
    (is (string= "customKey" (getf meta :json-key)))))

(test skel-class-metadata-plist-function
  "Test retrieving class metadata as plist"
  (clear-skel-registry)

  (eval '(define-skel-class test-class-plist ()
          ((a :type string :description "Slot A")
           (b :type integer))
          (:documentation "Test class documentation")))

  (let ((meta (skel-class-metadata-plist 'test-class-plist)))
    (is (eq 'test-class-plist (getf meta :name)))
    (is (string= "Test class documentation" (getf meta :documentation)))
    (is (= 2 (length (getf meta :slots))))
    (let ((slot-a (first (getf meta :slots))))
      (is (eq 'a (getf slot-a :name)))
      (is (eq 'string (getf slot-a :type))))))

;;; ============================================================================
;;; JSON Schema Generation Tests
;;; ============================================================================

(test type-to-json-schema-primitives
  "Test JSON Schema generation for primitive types"
  (is (equal '(("type" . "string")) (type-to-json-schema 'string)))
  (is (equal '(("type" . "integer")) (type-to-json-schema 'integer)))
  (is (equal '(("type" . "number")) (type-to-json-schema 'float)))
  (is (equal '(("type" . "boolean")) (type-to-json-schema 'boolean)))
  (is (equal '(("type" . "null")) (type-to-json-schema 'null))))

(test type-to-json-schema-compound
  "Test JSON Schema generation for compound types"
  ;; Or type -> oneOf
  (let ((schema (type-to-json-schema '(or string null))))
    (is (assoc "oneOf" schema :test #'string=))
    (is (= 2 (length (cdr (assoc "oneOf" schema :test #'string=))))))

  ;; List-of -> array with items
  (let ((schema (type-to-json-schema '(list-of string))))
    (is (string= "array" (cdr (assoc "type" schema :test #'string=))))
    (is (assoc "items" schema :test #'string=))))

(test skel-class-to-json-schema-function
  "Test JSON Schema generation for SKEL class"
  (clear-skel-registry)

  (eval '(define-skel-class test-json-schema ()
          ((name :type string
                 :description "The name"
                 :required t)
           (age :type integer
                :default 0)
           (tags :type (list-of string)))
          (:documentation "A test schema")))

  (let ((schema (skel-class-to-json-schema 'test-json-schema)))
    ;; Type should be object
    (is (string= "object" (cdr (assoc "type" schema :test #'string=))))

    ;; Check properties exist
    (let ((props (cdr (assoc "properties" schema :test #'string=))))
      (is (= 3 (length props)))
      ;; Name property
      (let ((name-prop (cdr (assoc "name" props :test #'string=))))
        (is (string= "string" (cdr (assoc "type" name-prop :test #'string=))))
        (is (string= "The name" (cdr (assoc "description" name-prop :test #'string=)))))
      ;; Age property with default
      (let ((age-prop (cdr (assoc "age" props :test #'string=))))
        (is (= 0 (cdr (assoc "default" age-prop :test #'string=))))))

    ;; Check required array
    (let ((required (cdr (assoc "required" schema :test #'string=))))
      (is (= 1 (length required)))
      (is (string= "name" (first required))))

    ;; Check class documentation
    (is (string= "A test schema"
                 (cdr (assoc "description" schema :test #'string=))))))

;;; ----------------------------------------------------------------------------
;;; Convenience Wrapper Test
;;; ----------------------------------------------------------------------------

(test skel-call-wrapper
  "Test skel-call is equivalent to invoke-skel-function"
  (clear-function-registry)

  (eval '(define-skel-function test-wrapper
             ((x :string))
           :prompt "{{ x }}"))

  ;; Both should fail the same way without a client
  (let ((*current-llm-client* nil))
    (signals skel-error (skel-call 'test-wrapper :x "test"))
    (signals skel-error (invoke-skel-function 'test-wrapper :x "test"))))

;;; ============================================================================
;;; SAP Type Coercer Tests
;;; ============================================================================

(test parse-integer-lenient-basic
  "Test basic integer parsing"
  ;; Direct integers
  (is (= 42 (parse-integer-lenient 42)))
  (is (= -10 (parse-integer-lenient -10)))
  (is (= 0 (parse-integer-lenient 0)))

  ;; String integers
  (is (= 123 (parse-integer-lenient "123")))
  (is (= -456 (parse-integer-lenient "-456")))
  (is (= 0 (parse-integer-lenient "0")))

  ;; Whitespace handling
  (is (= 42 (parse-integer-lenient "  42  ")))
  (is (= 42 (parse-integer-lenient "
42
"))))

(test parse-integer-lenient-coercion
  "Test integer coercion from other types"
  ;; Float to integer (truncation)
  (is (= 3 (parse-integer-lenient 3.7)))
  (is (= 3 (parse-integer-lenient "3.7")))
  (is (= -3 (parse-integer-lenient -3.2)))

  ;; Ratio to integer
  (is (= 1 (parse-integer-lenient 7/5)))

  ;; Nil handling
  (is (null (parse-integer-lenient nil)))
  (is (null (parse-integer-lenient "")))
  (is (null (parse-integer-lenient "  "))))

(test parse-integer-lenient-errors
  "Test integer parsing error cases"
  (signals sap-coercion-error
    (parse-integer-lenient "not a number"))
  (signals sap-coercion-error
    (parse-integer-lenient "123abc")))

(test parse-float-lenient-basic
  "Test basic float parsing"
  ;; Direct floats
  (is (= 3.14 (parse-float-lenient 3.14)))
  (is (= -2.5 (parse-float-lenient -2.5)))

  ;; Integer to float
  (is (= 42.0 (parse-float-lenient 42)))

  ;; String floats
  (is (= 3.14 (parse-float-lenient "3.14")))
  (is (= -2.5 (parse-float-lenient "-2.5")))

  ;; Nil handling
  (is (null (parse-float-lenient nil)))
  (is (null (parse-float-lenient ""))))

(test parse-boolean-lenient-sap-basic
  "Test SAP boolean parsing"
  ;; Direct booleans
  (is (eq t (parse-boolean-lenient t)))
  (is (eq nil (parse-boolean-lenient nil)))

  ;; String true values
  (is (eq t (parse-boolean-lenient "true")))
  (is (eq t (parse-boolean-lenient "True")))
  (is (eq t (parse-boolean-lenient "TRUE")))
  (is (eq t (parse-boolean-lenient "yes")))
  (is (eq t (parse-boolean-lenient "1")))
  (is (eq t (parse-boolean-lenient "t")))
  (is (eq t (parse-boolean-lenient "on")))

  ;; String false values
  (is (eq nil (parse-boolean-lenient "false")))
  (is (eq nil (parse-boolean-lenient "False")))
  (is (eq nil (parse-boolean-lenient "no")))
  (is (eq nil (parse-boolean-lenient "0")))
  (is (eq nil (parse-boolean-lenient "nil")))
  (is (eq nil (parse-boolean-lenient "null")))
  (is (eq nil (parse-boolean-lenient "off")))

  ;; Numeric booleans
  (is (eq t (parse-boolean-lenient 1)))
  (is (eq t (parse-boolean-lenient 42)))
  (is (eq nil (parse-boolean-lenient 0)))

  ;; Keyword booleans
  (is (eq t (parse-boolean-lenient :true)))
  (is (eq nil (parse-boolean-lenient :false))))

(test parse-boolean-lenient-sap-errors
  "Test SAP boolean parsing error cases"
  (signals sap-coercion-error
    (parse-boolean-lenient "maybe"))
  (signals sap-coercion-error
    (parse-boolean-lenient "unknown")))

(test ensure-string-sap-function
  "Test ensure-string utility"
  (is (string= "hello" (ensure-string "hello")))
  (is (string= "" (ensure-string nil)))
  (is (string= "42" (ensure-string 42)))
  (is (string= "3.14" (ensure-string 3.14)))
  (is (string= "SYMBOL" (ensure-string 'symbol))))

(test ensure-list-sap-function
  "Test ensure-list utility"
  (is (equal '(1 2 3) (ensure-list '(1 2 3))))
  (is (equal '() (ensure-list nil)))
  (is (equal '(42) (ensure-list 42)))
  (is (equal '("hello") (ensure-list "hello"))))

(test coerce-to-type-primitives
  "Test coerce-to-type for primitive types"
  ;; String coercion
  (is (string= "hello" (coerce-to-type "hello" :string)))
  (is (string= "42" (coerce-to-type 42 :string)))

  ;; Integer coercion (PRD acceptance: "123" -> 123)
  (is (= 123 (coerce-to-type "123" :integer)))
  (is (= 123 (coerce-to-type 123 :integer)))
  (is (= 3 (coerce-to-type 3.7 :integer)))

  ;; Float coercion
  (is (= 3.14 (coerce-to-type "3.14" :float)))
  (is (= 42.0 (coerce-to-type 42 :float)))

  ;; Boolean coercion
  (is (eq t (coerce-to-type "true" :boolean)))
  (is (eq nil (coerce-to-type "false" :boolean)))
  (is (eq t (coerce-to-type 1 :boolean)))
  (is (eq nil (coerce-to-type 0 :boolean))))

(test coerce-to-type-list-of
  "Test coerce-to-type for list-of types"
  ;; List of strings
  (is (equal '("a" "b" "c")
             (coerce-to-type '("a" "b" "c") '(list-of :string))))

  ;; List of integers (with coercion)
  (is (equal '(1 2 3)
             (coerce-to-type '("1" "2" "3") '(list-of :integer))))
  (is (equal '(1 2 3)
             (coerce-to-type '(1 2 3) '(list-of :integer))))

  ;; Mixed types coerced
  (is (equal '(1 2 3)
             (coerce-to-type '("1" 2 "3") '(list-of :integer))))

  ;; Single value wrapped
  (is (equal '(42)
             (coerce-to-type 42 '(list-of :integer))))

  ;; Nil becomes empty list
  (is (equal '()
             (coerce-to-type nil '(list-of :string)))))

(test coerce-to-type-one-of
  "Test coerce-to-type for enumeration types"
  (let ((enum-type '(one-of "red" "green" "blue")))
    (is (string= "red" (coerce-to-type "red" enum-type)))
    (is (string= "GREEN" (coerce-to-type "GREEN" enum-type)))  ; returns as-is when matched case-insensitively

    ;; Invalid value in strict mode
    (signals sap-coercion-error
      (coerce-to-type "yellow" enum-type :strict t))))

(test coerce-to-type-optional
  "Test coerce-to-type for optional types"
  ;; Nil returns default
  (is (= 0 (coerce-to-type nil '(optional :integer 0))))
  (is (string= "default" (coerce-to-type nil '(optional :string "default"))))

  ;; Empty string returns default
  (is (= 42 (coerce-to-type "" '(optional :integer 42))))
  (is (= 42 (coerce-to-type "  " '(optional :integer 42))))

  ;; "null" and "nil" strings return default
  (is (= 0 (coerce-to-type "null" '(optional :integer 0))))
  (is (= 0 (coerce-to-type "nil" '(optional :integer 0))))

  ;; Present value is coerced
  (is (= 123 (coerce-to-type "123" '(optional :integer 0))))
  (is (string= "hello" (coerce-to-type "hello" '(optional :string "default")))))

(test coerce-to-type-union
  "Test coerce-to-type for union (or) types"
  ;; (or string null) - common pattern
  (is (string= "hello" (coerce-to-type "hello" '(or string null))))
  (is (null (coerce-to-type nil '(or string null))))

  ;; (or integer null) with string coercion
  (is (= 42 (coerce-to-type "42" '(or integer null))))
  (is (null (coerce-to-type nil '(or integer null))))

  ;; Try types in order
  (is (= 42 (coerce-to-type "42" '(or integer string)))))

(test coerce-to-type-nil-handling
  "Test nil handling in coercion"
  ;; Nil to optional
  (is (null (coerce-to-type nil '(optional :string))))

  ;; Nil to union with null
  (is (null (coerce-to-type nil '(or string null))))

  ;; Nil to primitives
  (is (null (coerce-to-type nil :integer))))

(test coerce-to-type-prd-example
  "Test the PRD acceptance criterion: '123' -> 123 for integer slots"
  ;; This is the key acceptance criterion from the PRD
  (is (= 123 (coerce-to-type "123" :integer)))
  (is (= 123 (coerce-to-type "123" 'integer)))

  ;; Also with other common patterns
  (is (= 30 (coerce-to-type "30" :integer)))  ; age as string
  (is (eq t (coerce-to-type "true" :boolean)))  ; boolean as string
  (is (= 3.14 (coerce-to-type "3.14" :float))))  ; float as string

;;; ============================================================================
;;; SAP Extractor Tests
;;; ============================================================================

(test json-key-to-lisp-name-function
  "Test JSON key to Lisp name conversion"
  ;; camelCase
  (is (eq 'FIRST-NAME (json-key-to-lisp-name "firstName")))
  (is (eq 'START-DATE (json-key-to-lisp-name "startDate")))
  (is (eq 'MY-LONG-NAME (json-key-to-lisp-name "myLongName")))

  ;; snake_case
  (is (eq 'FIRST-NAME (json-key-to-lisp-name "first_name")))
  (is (eq 'START-DATE (json-key-to-lisp-name "start_date")))

  ;; Simple names
  (is (eq 'NAME (json-key-to-lisp-name "name")))
  (is (eq 'AGE (json-key-to-lisp-name "age")))

  ;; Keywords (already uppercase, no camelCase splitting)
  (is (eq 'FIRSTNAME (json-key-to-lisp-name :firstName))))

(test find-json-value-function
  "Test JSON value lookup with various key formats"
  (let ((alist '((:NAME . "John") (:AGE . 30) (:START-DATE . "2020-01"))))
    ;; Direct lookup
    (is (string= "John" (find-json-value alist 'name)))
    (is (= 30 (find-json-value alist 'age)))
    (is (string= "2020-01" (find-json-value alist 'start-date)))))

(test sap-extract-slot-basic
  "Test extracting single slots with coercion"
  (clear-skel-registry)

  (eval '(define-skel-class test-slot-extract ()
          ((name :type string)
           (age :type integer)
           (active :type boolean :default nil))))

  (let ((metadata (get-skel-class 'test-slot-extract)))
    (let ((slots (skel-class-slots metadata)))
      ;; Extract name slot
      (multiple-value-bind (value found-p)
          (sap-extract-slot '((:NAME . "John")) (first slots))
        (is (string= "John" value))
        (is-true found-p))

      ;; Extract age slot with coercion
      (multiple-value-bind (value found-p)
          (sap-extract-slot '((:AGE . "30")) (second slots))
        (is (= 30 value))  ; Coerced from string
        (is-true found-p))

      ;; Missing slot returns default
      (multiple-value-bind (value found-p)
          (sap-extract-slot '() (third slots))
        (is (null value))  ; Default is nil
        (is-false found-p)))))

(test sap-extract-with-schema-basic
  "Test schema-based extraction"
  (clear-skel-registry)

  (eval '(define-skel-class test-schema-extract ()
          ((name :type string :required t)
           (age :type integer)
           (email :type (or string null) :default nil))))

  (let ((alist '((:NAME . "John Doe") (:AGE . "25") (:EMAIL . "john@example.com"))))
    (let ((result (sap-extract-with-schema alist 'test-schema-extract)))
      (is (string= "John Doe" (getf result :name)))
      (is (= 25 (getf result :age)))  ; Coerced from string
      (is (string= "john@example.com" (getf result :email))))))

(test sap-extract-with-schema-defaults
  "Test extraction with default values"
  (clear-skel-registry)

  (eval '(define-skel-class test-defaults-extract ()
          ((name :type string :required t)
           (quantity :type integer :default 0)
           (active :type boolean :default t))))

  (let ((alist '((:NAME . "Test"))))  ; Only name provided
    (let ((result (sap-extract-with-schema alist 'test-defaults-extract)))
      (is (string= "Test" (getf result :name)))
      (is (= 0 (getf result :quantity)))  ; Default
      (is (eq t (getf result :active))))))  ; Default

(test sap-extract-with-schema-missing-required
  "Test extraction signals error for missing required fields"
  (clear-skel-registry)

  (eval '(define-skel-class test-required-extract ()
          ((name :type string :required t)
           (email :type string :required t))))

  ;; Missing required field should signal error
  (signals sap-extraction-error
    (sap-extract-with-schema '((:NAME . "John")) 'test-required-extract)))

(test sap-extract-full-pipeline
  "Test full SAP extraction pipeline with malformed LLM output"
  (clear-skel-registry)

  (eval '(define-skel-class test-pipeline ()
          ((name :type string :required t)
           (age :type integer)
           (skills :type (list-of string) :default nil))))

  ;; Malformed LLM output with all issues
  (let ((raw "Let me analyze this request.

```json
{name: 'John Doe', age: '30', skills: ['Python', 'Lisp',],}
```"))
    (let ((result (sap-extract raw 'test-pipeline)))
      (is (string= "John Doe" (getf result :name)))
      (is (= 30 (getf result :age)))
      (is (equal '("Python" "Lisp") (getf result :skills))))))

(test sap-extract-lenient-partial
  "Test lenient extraction allows partial results"
  (clear-skel-registry)

  (eval '(define-skel-class test-lenient ()
          ((name :type string :required t)
           (age :type integer :required t))))

  ;; Missing required field but lenient mode
  (let ((raw "{\"name\": \"John\"}"))
    (let ((result (sap-extract-lenient raw 'test-lenient)))
      (is (string= "John" (getf result :name)))
      (is (null (getf result :age))))))  ; Missing but no error

(test sap-try-extract-function
  "Test sap-try-extract returns success/failure status"
  (clear-skel-registry)

  (eval '(define-skel-class test-try ()
          ((name :type string :required t))))

  ;; Successful extraction
  (multiple-value-bind (result success-p error-msg)
      (sap-try-extract "{\"name\": \"John\"}" 'test-try)
    (is-true success-p)
    (is (null error-msg))
    (is (string= "John" (getf result :name))))

  ;; Failed extraction (missing required)
  (multiple-value-bind (result success-p error-msg)
      (sap-try-extract "{}" 'test-try)
    (is-false success-p)
    (is (stringp error-msg))
    (is (null result))))

(test sap-extract-prd-resume-example
  "Test extraction with the PRD resume example"
  (clear-skel-registry)

  ;; Define experience and resume classes as in PRD
  (eval '(define-skel-class sap-experience ()
          ((role :type string :required t)
           (company :type string :required t)
           (start-date :type string)
           (end-date :type (or string null) :default nil))))

  (eval '(define-skel-class sap-resume ()
          ((name :type string :required t)
           (email :type (or string null))
           (skills :type (list-of string) :default nil))))

  ;; Typical LLM output
  (let ((raw "Based on my analysis, here is the extracted resume:

```json
{
  \"name\": \"Jane Doe\",
  \"email\": \"jane@example.com\",
  \"skills\": [\"Python\", \"Common Lisp\", \"Machine Learning\"]
}
```"))
    (let ((result (sap-extract raw 'sap-resume)))
      (is (string= "Jane Doe" (getf result :name)))
      (is (string= "jane@example.com" (getf result :email)))
      (is (= 3 (length (getf result :skills))))
      (is (member "Common Lisp" (getf result :skills) :test #'string=)))))

(test sap-extract-type-coercion-real-world
  "Test type coercion with realistic LLM output patterns"
  (clear-skel-registry)

  (eval '(define-skel-class real-world-test ()
          ((quantity :type integer)
           (price :type float)
           (active :type boolean)
           (rating :type integer))))  ; Often returned as "4.5" for rating

  ;; LLMs often return numbers as strings
  (let ((raw "{\"quantity\": \"42\", \"price\": \"19.99\", \"active\": \"yes\", \"rating\": \"4.5\"}"))
    (let ((result (sap-extract raw 'real-world-test)))
      (is (= 42 (getf result :quantity)))  ; String -> integer
      (is (= 19.99 (getf result :price)))  ; String -> float
      (is (eq t (getf result :active)))  ; "yes" -> t
      (is (= 4 (getf result :rating))))))  ; "4.5" -> 4 (truncated)

(test sap-extract-camel-case-keys
  "Test extraction handles camelCase JSON keys"
  (clear-skel-registry)

  (eval '(define-skel-class camel-case-test ()
          ((first-name :type string)
           (last-name :type string)
           (start-date :type string))))

  ;; LLMs typically output camelCase
  (let ((raw "{\"firstName\": \"John\", \"lastName\": \"Doe\", \"startDate\": \"2020-01-01\"}"))
    (let ((result (sap-extract raw 'camel-case-test)))
      (is (string= "John" (getf result :first-name)))
      (is (string= "Doe" (getf result :last-name)))
      (is (string= "2020-01-01" (getf result :start-date))))))

(test sap-extract-unknown-class-error
  "Test extraction signals error for unknown class"
  (signals sap-extraction-error
    (sap-extract "{}" 'nonexistent-class)))

(test sap-extract-invalid-json-error
  "Test extraction signals error for invalid JSON"
  (clear-skel-registry)

  (eval '(define-skel-class json-error-test ()
          ((name :type string))))

  (signals skel-parse-error
    (sap-extract "this is not json at all" 'json-error-test)))

;;; ============================================================================
;;; SAP >85% Success Rate Validation Tests
;;; ============================================================================

(test sap-malformed-json-recovery
  "Test SAP handles common LLM JSON mistakes"
  (clear-skel-registry)

  (eval '(define-skel-class malformed-test ()
          ((value :type string))))

  ;; Unquoted keys
  (let ((result (sap-extract "{value: \"test\"}" 'malformed-test)))
    (is (string= "test" (getf result :value))))

  ;; Single quotes
  (let ((result (sap-extract "{'value': 'test'}" 'malformed-test)))
    (is (string= "test" (getf result :value))))

  ;; Trailing comma
  (let ((result (sap-extract "{\"value\": \"test\",}" 'malformed-test)))
    (is (string= "test" (getf result :value))))

  ;; All issues combined
  (let ((result (sap-extract "{value: 'test',}" 'malformed-test)))
    (is (string= "test" (getf result :value)))))

(test sap-markdown-fence-recovery
  "Test SAP handles markdown code fences"
  (clear-skel-registry)

  (eval '(define-skel-class fence-test ()
          ((data :type string))))

  ;; json fence
  (let ((result (sap-extract "```json
{\"data\": \"value\"}
```" 'fence-test)))
    (is (string= "value" (getf result :data))))

  ;; No language specifier
  (let ((result (sap-extract "```
{\"data\": \"value\"}
```" 'fence-test)))
    (is (string= "value" (getf result :data)))))

(test sap-chain-of-thought-recovery
  "Test SAP strips chain-of-thought preamble"
  (clear-skel-registry)

  (eval '(define-skel-class cot-test ()
          ((answer :type string))))

  ;; Various preamble patterns
  (let ((result (sap-extract "Let me think about this...
{\"answer\": \"42\"}" 'cot-test)))
    (is (string= "42" (getf result :answer))))

  (let ((result (sap-extract "I'll analyze the data. Based on my analysis:
{\"answer\": \"result\"}" 'cot-test)))
    (is (string= "result" (getf result :answer))))

  (let ((result (sap-extract "Here is the answer:
{\"answer\": \"found\"}" 'cot-test)))
    (is (string= "found" (getf result :answer)))))

;;; ============================================================================
;;; Template Expansion Edge Cases
;;; ============================================================================

(test interpolate-prompt-empty-template
  "Test interpolation handles empty template"
  (is (string= "" (interpolate-prompt "" '(:name "World"))))
  (is (string= "" (interpolate-prompt "" '()))))

(test interpolate-prompt-nil-template
  "Test interpolation handles nil template gracefully"
  (is (null (interpolate-prompt nil '(:name "World")))))

(test interpolate-prompt-special-chars-in-value
  "Test interpolation with special characters in values"
  ;; Curly braces in value should not be interpreted as placeholders
  (is (string= "Result: {{ not a var }}"
               (interpolate-prompt "Result: {{ value }}"
                                   '(:value "{{ not a var }}"))))
  ;; Newlines in values
  (is (search "line1" (interpolate-prompt "Text: {{ text }}"
                                          '(:text "line1
line2"))))
  ;; Backslashes
  (is (search "path\\to\\file"
               (interpolate-prompt "Path: {{ path }}"
                                   '(:path "path\\to\\file")))))

(test interpolate-prompt-unicode
  "Test interpolation handles Unicode characters"
  ;; Unicode in value
  (is (search "こんにちは"
               (interpolate-prompt "Greeting: {{ greeting }}"
                                   '(:greeting "こんにちは"))))
  ;; Unicode in template
  (is (search "日本語"
               (interpolate-prompt "日本語テスト: {{ value }}"
                                   '(:value "test"))))
  ;; Emoji
  (is (search "🎉"
               (interpolate-prompt "Status: {{ status }}"
                                   '(:status "🎉 Success!")))))

(test interpolate-prompt-case-sensitivity
  "Test that placeholder names are case-insensitive"
  (is (string= "Hello World!"
               (interpolate-prompt "Hello {{ NAME }}!" '(:name "World"))))
  (is (string= "Value: 42"
               (interpolate-prompt "Value: {{ VALUE }}" '(:value 42)))))

(test interpolate-prompt-repeated-placeholders
  "Test interpolation with repeated placeholder names"
  (is (string= "Name: John, again: John"
               (interpolate-prompt "Name: {{ name }}, again: {{ name }}"
                                   '(:name "John")))))

(test interpolate-prompt-complex-values
  "Test interpolation coerces complex values to strings"
  ;; List value
  (is (search "1 2 3"
               (interpolate-prompt "List: {{ items }}"
                                   '(:items (1 2 3)))))
  ;; Symbol value
  (is (search "HELLO"
               (interpolate-prompt "Symbol: {{ sym }}"
                                   '(:sym hello))))
  ;; Float value
  (is (search "3.14"
               (interpolate-prompt "Pi: {{ pi }}"
                                   '(:pi 3.14)))))

(test interpolate-prompt-no-placeholders
  "Test template without placeholders returns unchanged"
  (is (string= "Hello World!"
               (interpolate-prompt "Hello World!" '(:name "ignored"))))
  (is (string= "No vars here"
               (interpolate-prompt "No vars here" '()))))

(test interpolate-prompt-malformed-placeholders
  "Test handling of malformed placeholder patterns"
  ;; Unclosed brace
  (let ((result (interpolate-prompt "Hello {{ name" '(:name "World"))))
    (is (search "{{ name" result)))
  ;; Extra braces
  (let ((result (interpolate-prompt "Hello {{{ name }}}" '(:name "World"))))
    ;; Should still match the inner {{ name }}
    (is (or (search "World" result)
            (search "{{{ name }}}" result)))))

(test interpolate-prompt-very-long-value
  "Test interpolation handles very long values"
  (let* ((long-value (make-string 10000 :initial-element #\x))
         (result (interpolate-prompt "Data: {{ data }}"
                                     `(:data ,long-value))))
    (is (> (length result) 10000))
    (is (search "Data: x" result))))

;;; ============================================================================
;;; Template Expansion Error Handling
;;; ============================================================================

(test interpolate-prompt-function-error-handling
  "Test that function templates propagate errors"
  (let ((bad-template (lambda (&key name)
                        (declare (ignore name))
                        (error "Template generation failed"))))
    (signals error
      (interpolate-prompt bad-template '(:name "World")))))

(test interpolate-prompt-nil-value-handling
  "Test interpolation with explicit nil values"
  (let ((result (interpolate-prompt "Value: {{ value }}" '(:value nil))))
    (is (search "{{ value }}" result))))

(test validate-skel-arguments-type-coercion
  "Test argument validation doesn't reject valid type variations"
  (clear-function-registry)

  (eval '(define-skel-function test-type-flex
             ((quantity :integer :required nil :default 0)
              (name :string :required nil :default ""))
           :prompt "{{ quantity }} {{ name }}"))

  (let ((func (get-skel-function 'test-type-flex)))
    ;; Should accept integer
    (finishes (validate-skel-arguments func '(:quantity 42)))
    ;; Should accept string
    (finishes (validate-skel-arguments func '(:name "test")))))

;;; ============================================================================
;;; Response Parsing Error Handling
;;; ============================================================================

(test parse-llm-response-invalid-integer
  "Test parsing invalid integer signals error"
  (signals skel-type-error
    (parse-llm-response "not a number" :integer)))

(test parse-llm-response-invalid-boolean
  "Test parsing invalid boolean signals error"
  (signals skel-type-error
    (parse-llm-response "maybe" :boolean)))

(test parse-llm-response-invalid-json
  "Test parsing invalid JSON signals error"
  (signals skel-type-error
    (parse-llm-response "{invalid json" :json)))

(test parse-llm-response-empty-string
  "Test parsing empty string for different types"
  ;; Empty string is valid for :string type
  (is (string= "" (parse-llm-response "" :string)))
  ;; Empty string should error for :integer
  (signals skel-type-error
    (parse-llm-response "" :integer))
  ;; Empty string should error for :json
  (signals skel-type-error
    (parse-llm-response "" :json)))

(test parse-llm-response-skel-class
  "Test parse-llm-response handles SKEL class return types"
  (clear-skel-registry)
  (eval '(define-skel-class test-parse-person ()
           ((name :type string :required t)
            (age :type integer))))
  (let ((result (parse-llm-response
                 "{\"name\": \"Alice\", \"age\": 30}"
                 'test-parse-person)))
    (is (listp result))
    (is (string= "Alice" (getf result :name)))
    (is (= 30 (getf result :age)))))

(test parse-llm-response-skel-class-with-preamble
  "Test parse-llm-response handles SKEL class with markdown fence"
  (clear-skel-registry)
  (eval '(define-skel-class test-parse-item ()
           ((title :type string :required t)
            (quantity :type integer))))
  (let ((result (parse-llm-response
                 "Here is the result:
```json
{\"title\": \"Widget\", \"quantity\": 5}
```"
                 'test-parse-item)))
    (is (listp result))
    (is (string= "Widget" (getf result :title)))
    (is (= 5 (getf result :quantity)))))

;;; ============================================================================
;;; Phase 1: Class Schema Type Hints
;;; ============================================================================

(test format-type-hint-skel-class
  "Test type hint for SKEL class return types"
  (clear-skel-registry)
  (eval '(define-skel-class test-hint-class ()
           ((name :type string :required t :description "Person name")
            (age :type integer :description "Age in years"))))
  (let ((hint (format-type-hint 'test-hint-class)))
    (is (not (null hint)))
    (is (search "JSON object" hint))
    (is (search "name" hint))
    (is (search "age" hint))
    (is (search "<string>" hint))
    (is (search "<integer>" hint))))

(test format-type-hint-non-skel-class-unchanged
  "Test type hint returns nil for unknown symbols"
  (is (null (format-type-hint 'not-a-skel-class-at-all))))

(test build-skel-prompt-class-type
  "Test building prompt with SKEL class return type"
  (clear-skel-registry)
  (clrhash autopoiesis.skel::*skel-functions*)
  (eval '(define-skel-class test-prompt-result ()
           ((title :type string :required t)
            (score :type float))))
  (eval '(define-skel-function test-class-build
             ((text :string))
           :prompt "Extract from: {{ text }}"
           :return-type test-prompt-result))
  (let* ((func (get-skel-function 'test-class-build))
         (prompt (build-skel-prompt func '(:text "data"))))
    (is (search "Extract from: data" prompt))
    (is (search "JSON object" prompt))
    (is (search "title" prompt))
    (is (search "score" prompt))))

;;; ============================================================================
;;; Phase 2: Field-Level Constraints
;;; ============================================================================

(test define-skel-class-with-constraints
  "Test defining a class with check and assert constraints"
  (clear-skel-registry)
  (eval `(define-skel-class test-constrained ()
           ((age :type integer
                 :check ("reasonable" ,(lambda (v) (and (> v 0) (< v 150))))
                 :assert ("positive" ,(lambda (v) (> v 0)))
                 :description "Age in years")
            (name :type string :required t))))
  (let* ((meta (get-skel-class 'test-constrained))
         (age-slot (find 'age (skel-class-slots meta) :key #'skel-slot-name)))
    (is (not (null (skel-slot-check age-slot))))
    (is (not (null (skel-slot-assert-constraint age-slot))))))

(test validate-slot-constraints-check
  "Test non-blocking check constraint"
  (clear-skel-registry)
  (eval `(define-skel-class test-check ()
           ((score :type integer
                   :check ("in-range" ,(lambda (v) (<= 0 v 100)))))))
  (let* ((meta (get-skel-class 'test-check))
         (slot (first (skel-class-slots meta))))
    ;; Valid value — no warnings
    (multiple-value-bind (val warnings)
        (validate-slot-constraints 50 slot)
      (is (= val 50))
      (is (null warnings)))
    ;; Invalid value — warning but no error
    (multiple-value-bind (val warnings)
        (validate-slot-constraints 200 slot)
      (is (= val 200))
      (is (= 1 (length warnings))))))

(test validate-slot-constraints-assert
  "Test blocking assert constraint"
  (clear-skel-registry)
  (eval `(define-skel-class test-assert ()
           ((quantity :type integer
                      :assert ("positive" ,(lambda (v) (> v 0)))))))
  (let* ((meta (get-skel-class 'test-assert))
         (slot (first (skel-class-slots meta))))
    ;; Valid — passes
    (is (= 5 (validate-slot-constraints 5 slot)))
    ;; Invalid — signals error
    (signals skel-validation-error
      (validate-slot-constraints -1 slot))))

(test validate-slot-constraints-nil-skipped
  "Test that constraints are skipped for nil values"
  (clear-skel-registry)
  (eval `(define-skel-class test-nil-constraint ()
           ((value :type integer
                   :assert ("positive" ,(lambda (v) (> v 0)))))))
  (let* ((meta (get-skel-class 'test-nil-constraint))
         (slot (first (skel-class-slots meta))))
    ;; nil should pass through without triggering assert
    (multiple-value-bind (val warnings)
        (validate-slot-constraints nil slot)
      (is (null val))
      (is (null warnings)))))

(test format-slot-for-prompt-with-constraints
  "Test that constraint names appear in prompt formatting"
  (clear-skel-registry)
  (eval `(define-skel-class test-prompt-constraints ()
           ((age :type integer
                 :check ("reasonable" ,(lambda (v) (< v 150)))
                 :assert ("positive" ,(lambda (v) (> v 0)))))))
  (let* ((meta (get-skel-class 'test-prompt-constraints))
         (slot (first (skel-class-slots meta)))
         (formatted (format-slot-for-prompt slot)))
    (is (search "check: reasonable" formatted))
    (is (search "assert: positive" formatted))))

;;; ============================================================================
;;; Phase 3: Named Client Registry
;;; ============================================================================

(test skel-client-registry-basic
  "Test client registration and lookup"
  (clrhash autopoiesis.skel::*skel-client-registry*)
  (let ((client (make-skel-llm-client :api-key "test" :model "test-model")))
    (register-skel-client :test-client client)
    (is (eq client (find-skel-client :test-client)))
    (is (eq client (find-skel-client "test-client")))
    (is (member :test-client (list-skel-clients)))))

(test skel-client-registry-not-found
  "Test client lookup returns nil for unknown names"
  (clrhash autopoiesis.skel::*skel-client-registry*)
  (is (null (find-skel-client :nonexistent))))

(test ensure-llm-client-resolves-names
  "Test that ensure-llm-client resolves named clients"
  (clrhash autopoiesis.skel::*skel-client-registry*)
  (let ((client (make-skel-llm-client :api-key "test" :model "test-model")))
    (register-skel-client :named client)
    (is (eq client (autopoiesis.skel::ensure-llm-client :named)))))

(test ensure-llm-client-falls-back
  "Test that ensure-llm-client falls back to *current-llm-client*"
  (clrhash autopoiesis.skel::*skel-client-registry*)
  (let* ((client (make-skel-llm-client :api-key "test" :model "test-model"))
         (*current-llm-client* client))
    ;; Unknown named client falls back to *current-llm-client*
    (is (eq client (autopoiesis.skel::ensure-llm-client :unknown-client)))))
