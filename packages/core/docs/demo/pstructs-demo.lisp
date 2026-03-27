;;;; pstructs-demo.lisp — Persistent data structures demo
(require :asdf)
(push #p"platform/" asdf:*central-registry*)
(push #p"platform/substrate/" asdf:*central-registry*)
(handler-bind ((warning #'muffle-warning)) (asdf:load-system :autopoiesis))
(use-package :autopoiesis.core)

;; Persistent maps
(let* ((m1 (pmap-put (pmap-put (pmap-empty) :name "scout") :role "analyzer"))
       (m2 (pmap-put m1 :status :active)))
  (format t "m1: ~S~%" (pmap-to-alist m1))
  (format t "m2: ~S~%" (pmap-to-alist m2))
  (format t "m1 unchanged after m2 created: ~A~%" (not (pmap-contains-p m1 :status))))

;; Persistent vectors (append-only thought log)
(let* ((v1 (pvec-push (pvec-push (pvec-empty) :thought-1) :thought-2))
       (v2 (pvec-push v1 :thought-3)))
  (format t "~%v1 length: ~D, v2 length: ~D~%" (pvec-length v1) (pvec-length v2))
  (format t "v1 contents: ~S~%" (pvec-to-list v1))
  (format t "v2 contents: ~S~%" (pvec-to-list v2)))

;; Persistent sets (capabilities)
(let* ((s1 (pset-add (pset-add (pset-empty) :search) :analyze))
       (s2 (pset-add s1 :report))
       (s3 (pset-union s1 (list-to-pset '(:summarize :report)))))
  (format t "~%s1: ~S~%" (pset-to-list s1))
  (format t "s2: ~S~%" (pset-to-list s2))
  (format t "s3 (union): ~S~%" (pset-to-list s3)))

(sb-ext:exit)
