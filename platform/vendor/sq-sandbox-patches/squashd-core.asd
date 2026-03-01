;;;; squashd-core.asd - Library-only system (no HTTP server)
;;;;
;;;; Stripped system definition that loads the squashd container runtime
;;;; without HTTP server dependencies (clack, woo, lack, ningle, trivial-mimes).
;;;; Suitable for embedding as a library in other CL projects.

(defsystem "squashd-core"
  :description "sq-sandbox container runtime (library, no HTTP server)"
  :version "4.0.0"
  :depends-on ("cffi"
               "jonathan"
               "ironclad"
               "dexador"
               "bordeaux-threads"
               "alexandria"
               "local-time"
               "cl-ppcre"
               "log4cl")
  :pathname "src"
  :serial t
  :components ((:file "packages")
               (:file "config")
               (:file "validate")
               (:file "conditions")
               (:file "syscalls")
               (:file "mounts")
               (:file "cgroup")
               (:file "netns")
               (:file "exec")
               (:file "sandbox")
               (:file "firecracker")
               (:file "gvisor")
               (:file "manager")
               (:file "meta")
               (:file "modules")
               (:file "secrets")
               (:file "s3")
               (:file "reaper")
               (:file "init")))
