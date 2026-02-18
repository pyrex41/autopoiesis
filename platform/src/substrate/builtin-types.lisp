;;;; builtin-types.lisp - Pre-defined entity types for the substrate
;;;;
;;;; These are declarations only - they don't create any entities.
;;;; Actual entity creation happens in later phases when the conductor,
;;;; conversations, etc. write datoms.

(in-package #:autopoiesis.substrate)

(define-entity-type :event
  (:event/type       :type keyword  :required t)
  (:event/data       :type t)
  (:event/status     :type keyword  :required t)
  (:event/created-at :type integer  :required t)
  (:event/error      :type (or null string)))

(define-entity-type :worker
  (:worker/task-id    :type string  :required t)
  (:worker/status     :type keyword :required t)
  (:worker/thread     :type t)
  (:worker/started-at :type integer :required t))

(define-entity-type :agent
  (:agent/name       :type string   :required t)
  (:agent/task       :type string)
  (:agent/status     :type keyword  :required t)
  (:agent/started-at :type integer)
  (:agent/result     :type (or null string))
  (:agent/error      :type (or null string)))

(define-entity-type :session
  (:session/name       :type string  :required t)
  (:session/state-hash :type string)
  (:session/saved-at   :type integer))

(define-entity-type :snapshot
  (:snapshot/content-hash :type string  :required t)
  (:snapshot/timestamp    :type integer :required t)
  (:snapshot/agent-id     :type t)
  (:snapshot/parent       :type (or null integer)))

;; Turn and Context types -- fully used in Phase 6
(define-entity-type :turn
  (:turn/role         :type keyword  :required t)
  (:turn/content-hash :type string   :required t)
  (:turn/parent       :type (or null integer))
  (:turn/context      :type integer)
  (:turn/timestamp    :type integer  :required t)
  (:turn/model        :type (or null keyword))
  (:turn/tokens       :type (or null integer))
  (:turn/tool-use     :type (or null string))
  (:turn/metadata     :type t))

(define-entity-type :context
  (:context/name       :type string   :required t)
  (:context/head       :type (or null integer))
  (:context/agent      :type (or null integer))
  (:context/forked-from :type (or null integer))
  (:context/created-at :type integer  :required t))

(define-entity-type :prompt
  (:prompt/name         :type string   :required t)
  (:prompt/category     :type keyword  :required t)
  (:prompt/body         :type string   :required t)
  (:prompt/version      :type integer  :required t)
  (:prompt/content-hash :type string   :required t)
  (:prompt/parent       :type (or null integer))
  (:prompt/author       :type (or null string))
  (:prompt/created-at   :type integer  :required t)
  (:prompt/variables    :type t)
  (:prompt/includes     :type t))
