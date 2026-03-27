;;;; entity-types.lisp - Substrate entity types for the eval module
;;;;
;;;; Defines four entity types: eval-scenario, eval-run, eval-trial,
;;;; and eval-comparison.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Eval Scenario — a reusable task definition
;;; ===================================================================

(define-entity-type :eval-scenario
  (:eval-scenario/name        :type string   :required t)
  (:eval-scenario/description :type string   :required t)
  (:eval-scenario/prompt      :type string   :required t)
  (:eval-scenario/domain      :type keyword)
  (:eval-scenario/tags        :type t)
  (:eval-scenario/verifier    :type t)
  (:eval-scenario/rubric      :type t)
  (:eval-scenario/expected    :type t)
  (:eval-scenario/timeout     :type (or null integer))
  (:eval-scenario/created-at  :type integer  :required t))

;;; ===================================================================
;;; Eval Run — a configured execution batch
;;; ===================================================================

(define-entity-type :eval-run
  (:eval-run/name         :type string   :required t)
  (:eval-run/status       :type keyword  :required t)
  (:eval-run/scenarios    :type t        :required t)
  (:eval-run/harnesses    :type t        :required t)
  (:eval-run/trials       :type integer  :required t)
  (:eval-run/config       :type t)
  (:eval-run/created-at   :type integer  :required t)
  (:eval-run/completed-at :type (or null integer)))

;;; ===================================================================
;;; Eval Trial — one execution of one scenario on one harness
;;; ===================================================================

(define-entity-type :eval-trial
  (:eval-trial/run             :type integer  :required t)
  (:eval-trial/scenario        :type integer  :required t)
  (:eval-trial/harness         :type string   :required t)
  (:eval-trial/trial-num       :type integer  :required t)
  (:eval-trial/status          :type keyword  :required t)
  (:eval-trial/started-at      :type (or null integer))
  (:eval-trial/completed-at    :type (or null integer))
  ;; Hard metrics
  (:eval-trial/duration        :type (or null number))
  (:eval-trial/cost            :type (or null number))
  (:eval-trial/turns           :type (or null integer))
  (:eval-trial/exit-code       :type (or null integer))
  (:eval-trial/passed          :type (or null keyword))
  ;; Outputs
  (:eval-trial/output          :type t)
  (:eval-trial/tool-calls      :type t)
  (:eval-trial/raw-result      :type t)
  ;; Squishy metrics
  (:eval-trial/judge-scores    :type t)
  (:eval-trial/judge-reasoning :type t))

;;; ===================================================================
;;; Eval Comparison — stored comparison between runs/harnesses
;;; ===================================================================

(define-entity-type :eval-comparison
  (:eval-comparison/name       :type string   :required t)
  (:eval-comparison/run-ids    :type t        :required t)
  (:eval-comparison/results    :type t)
  (:eval-comparison/created-at :type integer  :required t))
