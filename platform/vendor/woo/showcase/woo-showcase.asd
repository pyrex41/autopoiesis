(defsystem "woo-showcase"
  :version "0.1.0"
  :author "Woo Team"
  :license "MIT"
  :depends-on ("woo"
               "ningle"
               "lack"
               "lack-middleware-static"
               "djula"
               "jonathan"
               "trivial-utf-8"
               "cl-ppcre")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "benchmark-data" :depends-on ("package"))
                 (:file "app" :depends-on ("package" "benchmark-data")))))
  :description "Web app showcasing Woo's performance")
