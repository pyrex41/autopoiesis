;;;; test-demo.lisp — Run persistent agent test suites
(require :asdf)
(push #p"platform/" asdf:*central-registry*)
(push #p"platform/substrate/" asdf:*central-registry*)
(handler-bind ((warning #'muffle-warning))
  (asdf:load-system :autopoiesis)
  (ql:quickload :fiveam))

(load "platform/test/packages.lisp")
(load "platform/test/persistent-agent-tests.lisp")
(load "platform/test/swarm-integration-tests.lisp")

(format t "=== Persistent Agent Tests ===~%")
(5am:run! 'autopoiesis.test::persistent-agent-tests)
(format t "~%=== Swarm Integration Tests ===~%")
(5am:run! 'autopoiesis.test::swarm-integration-tests)

(sb-ext:exit)
