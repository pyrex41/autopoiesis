;;;; structures.lisp - BAML syntax structures

(in-package #:autopoiesis.skel.baml)

;;; ============================================================================
;;; Token Structure
;;; ============================================================================

(defstruct (baml-token (:conc-name token-))
  "Represents a single token from BAML source."
  (type nil :type keyword)
  (value nil)
  (line 1 :type fixnum)
  (column 1 :type fixnum))

;;; ============================================================================
;;; BAML Class Definition
;;; ============================================================================

(defstruct (baml-class (:conc-name baml-class-))
  "Represents a BAML class definition."
  (name nil :type (or string null))
  (fields nil :type list)
  (documentation nil :type (or string null)))

(defstruct (baml-field (:conc-name baml-field-))
  "Represents a field within a BAML class."
  (name nil :type (or string null))
  (type nil :type (or string null))
  (description nil :type (or string null))
  (required t :type boolean)
  (default nil)
  (alias nil :type (or string null)))

;;; ============================================================================
;;; BAML Function Definition
;;; ============================================================================

(defstruct (baml-function (:conc-name baml-function-))
  "Represents a BAML function definition."
  (name nil :type (or string null))
  (params nil :type list)
  (return-type nil :type (or string null))
  (client nil :type (or string null))
  (prompt nil :type (or string null))
  (config nil :type list))

(defstruct (baml-param (:conc-name baml-param-))
  "Represents a parameter in a BAML function signature."
  (name nil :type (or string null))
  (type nil :type (or string null)))

;;; ============================================================================
;;; BAML Enum Definition
;;; ============================================================================

(defstruct (baml-enum (:conc-name baml-enum-))
  "Represents a BAML enum definition."
  (name nil :type (or string null))
  (values nil :type list)
  (documentation nil :type (or string null)))

(defstruct (baml-enum-value (:conc-name baml-enum-value-))
  "Represents a value within a BAML enum."
  (name nil :type (or string null))
  (description nil :type (or string null))
  (alias nil :type (or string null)))

;;; ============================================================================
;;; BAML Client Definition
;;; ============================================================================

(defstruct (baml-client-def (:conc-name baml-client-def-))
  "Represents a BAML client definition."
  (name nil :type (or string null))
  (provider nil :type (or string null))
  (options nil :type list))

;;; ============================================================================
;;; Utility Functions for Structures
;;; ============================================================================

(defun make-baml-field-from-plist (plist)
  "Create a baml-field from a property list."
  (make-baml-field
   :name (getf plist :name)
   :type (getf plist :type)
   :description (getf plist :description)
   :required (getf plist :required t)
   :default (getf plist :default)
   :alias (getf plist :alias)))

(defun baml-class-field-names (class)
  "Return list of field names for a BAML class."
  (mapcar #'baml-field-name (baml-class-fields class)))

(defun baml-function-param-names (func)
  "Return list of parameter names for a BAML function."
  (mapcar #'baml-param-name (baml-function-params func)))

(defun baml-enum-value-names (enum)
  "Return list of value names for a BAML enum."
  (mapcar #'baml-enum-value-name (baml-enum-values enum)))
