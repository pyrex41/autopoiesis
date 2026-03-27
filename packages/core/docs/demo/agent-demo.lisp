;;;; agent-demo.lisp — Persistent agent creation, cognition, fork
(require :asdf)
(push #p"platform/" asdf:*central-registry*)
(push #p"platform/substrate/" asdf:*central-registry*)
(handler-bind ((warning #'muffle-warning)) (asdf:load-system :autopoiesis))

(format t "=== Create a persistent agent ===~%")
(let* ((agent (autopoiesis.agent:make-persistent-agent
               :name "scout"
               :capabilities '(:search :analyze :report))))
  (format t "Name: ~A~%" (autopoiesis.agent:persistent-agent-name agent))
  (format t "Capabilities: ~S~%" (autopoiesis.core:pset-to-list
                                   (autopoiesis.agent:persistent-agent-capabilities agent)))
  (format t "Thoughts: ~D~%~%" (autopoiesis.core:pvec-length
                                (autopoiesis.agent:persistent-agent-thoughts agent)))

  (format t "=== Cognitive cycle (perceive -> reason) ===~%")
  (let* ((after-perceive (autopoiesis.agent:persistent-perceive agent '(:input "analyze auth module")))
         (after-reason (autopoiesis.agent:persistent-reason after-perceive)))
    (format t "After perceive — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                   (autopoiesis.agent:persistent-agent-thoughts after-perceive)))
    (format t "After reason  — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                  (autopoiesis.agent:persistent-agent-thoughts after-reason)))
    (format t "Original unchanged — thoughts: ~D~%~%" (autopoiesis.core:pvec-length
                                                        (autopoiesis.agent:persistent-agent-thoughts agent)))

    (format t "=== O(1) Fork ===~%")
    (multiple-value-bind (child updated-parent)
        (autopoiesis.agent:persistent-fork after-reason :name "scout-alpha")
      (format t "Child name: ~A~%" (autopoiesis.agent:persistent-agent-name child))
      (format t "Thoughts shared (eq): ~A~%" (eq (autopoiesis.agent:persistent-agent-thoughts child)
                                                   (autopoiesis.agent:persistent-agent-thoughts after-reason)))
      (format t "Parent tracks child: ~A~%~%" (not (null (autopoiesis.agent:persistent-agent-children updated-parent))))

      (format t "=== Independent evolution ===~%")
      (let ((child2 (autopoiesis.agent:persistent-perceive child '(:input "found vulnerability"))))
        (format t "Child after work — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                         (autopoiesis.agent:persistent-agent-thoughts child2)))
        (format t "Original child unchanged — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                                 (autopoiesis.agent:persistent-agent-thoughts child)))
        (format t "Parent still unchanged — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                               (autopoiesis.agent:persistent-agent-thoughts after-reason)))))))

(sb-ext:exit)
