;;;; dual-demo.lisp — Dual-agent bridge with auto-sync and undo
(require :asdf)
(push #p"platform/" asdf:*central-registry*)
(push #p"platform/substrate/" asdf:*central-registry*)
(handler-bind ((warning #'muffle-warning)) (asdf:load-system :autopoiesis))

(format t "=== Upgrade mutable agent to dual-agent ===~%")
(let* ((agent (autopoiesis.agent:make-agent :name "worker" :capabilities '(:read :write)))
       (dual (autopoiesis.agent:upgrade-to-dual agent)))
  (format t "Type: ~A~%" (type-of dual))
  (format t "Has persistent root: ~A~%" (not (null (autopoiesis.agent:dual-agent-root dual))))
  (format t "Root name: ~A~%~%" (autopoiesis.agent:persistent-agent-name
                                   (autopoiesis.agent:dual-agent-root dual)))

  (format t "=== Auto-sync on mutation ===~%")
  (setf (autopoiesis.agent:agent-name dual) "worker-v2")
  (format t "Mutable name: ~A~%" (autopoiesis.agent:agent-name dual))
  (format t "Persistent root name: ~A~%" (autopoiesis.agent:persistent-agent-name
                                            (autopoiesis.agent:dual-agent-root dual)))
  (format t "Version history depth: ~D~%~%" (length (autopoiesis.agent:dual-agent-history dual)))

  (setf (autopoiesis.agent:agent-name dual) "worker-v3")
  (format t "After second rename — name: ~A, history: ~D~%~%"
          (autopoiesis.agent:persistent-agent-name (autopoiesis.agent:dual-agent-root dual))
          (length (autopoiesis.agent:dual-agent-history dual)))

  (format t "=== Undo ===~%")
  (autopoiesis.agent:dual-agent-undo dual)
  (format t "After undo — name: ~A~%" (autopoiesis.agent:persistent-agent-name
                                          (autopoiesis.agent:dual-agent-root dual))))

(sb-ext:exit)
