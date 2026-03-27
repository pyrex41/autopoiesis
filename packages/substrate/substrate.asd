;;;; substrate.asd - Standalone substrate system definition
;;;;
;;;; The substrate is a datom store with transact!, hooks, indexes,
;;;; Linda coordination primitives, Datalog queries, and LMDB persistence.
;;;; It can be used independently of the autopoiesis agent platform.

(asdf:defsystem #:substrate
  :description "Datom store with transact!, hooks, indexes, Linda, Datalog, LMDB"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:alexandria
               #:bordeaux-threads
               #:ironclad
               #:flexi-streams
               #:babel
               #:lmdb)
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "conditions")
     (:file "context")
     (:file "intern")
     (:file "encoding")
     (:file "datom")
     (:file "entity")
     (:file "query")
     (:file "store")
     (:file "linda")
     (:file "datalog")
     (:file "entity-type")
     (:file "system")
     (:file "lmdb-backend")
     (:file "blob")))))
