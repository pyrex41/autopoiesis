;;;; entity-types.lisp - Substrate entity types for sandbox tracking
;;;;
;;;; Defines :sandbox-instance and :sandbox-exec entity types for
;;;; tracking sandbox lifecycle and individual exec calls in the substrate.

(in-package #:autopoiesis.sandbox)

;;; Entity type for tracking sandbox lifecycle in the substrate
(autopoiesis.substrate:define-entity-type :sandbox-instance
  (:sandbox-instance/sandbox-id    :type string   :required t)
  (:sandbox-instance/status        :type keyword  :required t)
  (:sandbox-instance/created-at    :type integer  :required t)
  (:sandbox-instance/layers        :type t)
  (:sandbox-instance/owner         :type (or null string))
  (:sandbox-instance/task          :type (or null string))
  (:sandbox-instance/destroyed-at  :type (or null integer))
  (:sandbox-instance/exec-count    :type (or null integer))
  (:sandbox-instance/error         :type (or null string)))

;;; Entity type for tracking individual exec calls
(autopoiesis.substrate:define-entity-type :sandbox-exec
  (:sandbox-exec/sandbox-id  :type string   :required t)
  (:sandbox-exec/command     :type string   :required t)
  (:sandbox-exec/exit-code   :type integer  :required t)
  (:sandbox-exec/started-at  :type integer  :required t)
  (:sandbox-exec/finished-at :type (or null integer))
  (:sandbox-exec/duration-ms :type (or null integer))
  (:sandbox-exec/stdout      :type (or null string))
  (:sandbox-exec/stderr      :type (or null string))
  (:sandbox-exec/workdir     :type (or null string))
  (:sandbox-exec/timeout     :type (or null integer))
  (:sandbox-exec/seq         :type (or null integer)))
