(require :asdf)
(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(dolist (dir '("packages/core/" "packages/substrate/" "packages/api-server/"
              "packages/eval/" "packages/shen/" "packages/swarm/"
              "packages/team/" "packages/supervisor/" "packages/crystallize/"
              "packages/jarvis/" "packages/paperclip/"
              "packages/sandbox/" "packages/research/"
              "vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))
(dolist (asd '("packages/api-server/api-server.asd"
              "packages/eval/eval.asd"
              "packages/shen/autopoiesis-shen.asd"
              "packages/swarm/swarm.asd"
              "packages/team/team.asd"
              "packages/supervisor/supervisor.asd"))
  (when (probe-file asd)
    (handler-case (asdf:load-asd (truename asd)) (error () nil))))

(handler-bind ((warning #'muffle-warning))
  (ql:quickload :autopoiesis :silent t))

(format t "~%~%========================================~%")
(format t "DEMO 1: Persistent Agents~%")
(format t "========================================~%~%")

(let* ((agent (autopoiesis.agent:make-persistent-agent
               :name "scout"
               :capabilities '(:search :analyze :report))))
  (format t "Created: ~A~%" (autopoiesis.agent:persistent-agent-name agent))
  (format t "Capabilities: ~S~%" (autopoiesis.core:pset-to-list
                                   (autopoiesis.agent:persistent-agent-capabilities agent)))
  (format t "Thoughts: ~D~%~%" (autopoiesis.core:pvec-length
                                (autopoiesis.agent:persistent-agent-thoughts agent)))

  ;; Perceive
  (let* ((after-perceive (autopoiesis.agent:persistent-perceive agent '(:input "analyze auth module")))
         (after-reason (autopoiesis.agent:persistent-reason after-perceive)))
    (format t "After perceive — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                   (autopoiesis.agent:persistent-agent-thoughts after-perceive)))
    (format t "After reason  — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                  (autopoiesis.agent:persistent-agent-thoughts after-reason)))
    (format t "Original unchanged — thoughts: ~D~%~%" (autopoiesis.core:pvec-length
                                                        (autopoiesis.agent:persistent-agent-thoughts agent)))

    ;; Fork
    (multiple-value-bind (child updated-parent)
        (autopoiesis.agent:persistent-fork after-reason :name "scout-alpha")
      (format t "Forked child: ~A~%" (autopoiesis.agent:persistent-agent-name child))
      (format t "Thoughts shared (eq): ~A~%" (eq (autopoiesis.agent:persistent-agent-thoughts child)
                                                   (autopoiesis.agent:persistent-agent-thoughts after-reason)))
      (format t "Parent tracks child: ~A~%~%" (not (null (autopoiesis.agent:persistent-agent-children updated-parent))))

      ;; Independent evolution
      (let ((child2 (autopoiesis.agent:persistent-perceive child '(:input "found vulnerability in JWT"))))
        (format t "Child after work — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                         (autopoiesis.agent:persistent-agent-thoughts child2)))
        (format t "Original child unchanged — thoughts: ~D~%" (autopoiesis.core:pvec-length
                                                                 (autopoiesis.agent:persistent-agent-thoughts child)))
        (format t "Parent unchanged — thoughts: ~D~%~%" (autopoiesis.core:pvec-length
                                                           (autopoiesis.agent:persistent-agent-thoughts after-reason)))

        ;; Serialize to S-expression
        (format t "Agent as S-expression (first 500 chars):~%")
        (let ((sexpr (autopoiesis.agent:persistent-agent-to-sexpr child2)))
          (format t "~A~%~%" (subseq (format nil "~S" sexpr) 0 (min 500 (length (format nil "~S" sexpr))))))))))

(format t "~%========================================~%")
(format t "DEMO 2: Persistent Data Structures~%")
(format t "========================================~%~%")

(let* ((m1 (autopoiesis.core:pmap-empty))
       (m2 (autopoiesis.core:pmap-put m1 :name "scout"))
       (m3 (autopoiesis.core:pmap-put m2 :role "analyzer"))
       (m4 (autopoiesis.core:pmap-put m3 :status "active")))
  (format t "m1 (empty): ~A entries~%" (autopoiesis.core:pmap-count m1))
  (format t "m4 (3 puts): ~A entries~%" (autopoiesis.core:pmap-count m4))
  (format t "m4[:name] = ~A~%" (autopoiesis.core:pmap-get m4 :name))
  (format t "m4[:role] = ~A~%" (autopoiesis.core:pmap-get m4 :role))
  (format t "m2 still has only 1: ~A~%~%" (autopoiesis.core:pmap-count m2)))

(let* ((v1 (autopoiesis.core:pvec-empty))
       (v2 (autopoiesis.core:pvec-push v1 "thought-1"))
       (v3 (autopoiesis.core:pvec-push v2 "thought-2"))
       (v4 (autopoiesis.core:pvec-push v3 "thought-3")))
  (format t "v1 length: ~D~%" (autopoiesis.core:pvec-length v1))
  (format t "v4 length: ~D~%" (autopoiesis.core:pvec-length v4))
  (format t "v4[0] = ~A~%" (autopoiesis.core:pvec-ref v4 0))
  (format t "v4[2] = ~A~%" (autopoiesis.core:pvec-ref v4 2))
  (format t "v1 still empty: ~D~%~%" (autopoiesis.core:pvec-length v1)))

(format t "~%========================================~%")
(format t "DEMO 3: Shen Prolog~%")
(format t "========================================~%~%")

(handler-bind ((warning #'muffle-warning))
  (ql:quickload :autopoiesis-shen :silent t))

(handler-case
    (progn
      (autopoiesis.shen:ensure-shen-loaded)
      (format t "Shen loaded: ~A~%~%" (autopoiesis.shen:shen-available-p))

      (format t "--- Basic eval ---~%")
      (format t "(+ 1 2) = ~A~%" (autopoiesis.shen:shen-eval '(+ 1 2)))
      (format t "(* 6 7) = ~A~%" (autopoiesis.shen:shen-eval '(* 6 7)))
      (format t "(+ 100 200) = ~A~%~%" (autopoiesis.shen:shen-eval '(+ 100 200)))

      (format t "--- Rule definition ---~%")
      (autopoiesis.shen:define-rule :quality-check
        '((quality-check Tree) <--
          (has-file Tree "README.md")
          (has-file Tree "src/")
          (has-file Tree "tests/")))

      (autopoiesis.shen:define-rule :deploy-safe
        '((deploy-safe Module) <--
          (tested Module)
          (all-deps-tested Module)))

      (autopoiesis.shen:define-rule :code-review
        '((code-review File) <--
          (has-tests File)
          (no-lint-errors File)
          (documented File)))

      (format t "Rules defined: ~A~%~%" (autopoiesis.shen:list-rules))

      (format t "--- Serialization roundtrip ---~%")
      (let ((serialized (autopoiesis.shen:rules-to-sexpr)))
        (format t "Serialized: ~S~%~%" serialized)
        (autopoiesis.shen:clear-rules)
        (format t "After clear: ~A rules~%" (length (autopoiesis.shen:list-rules)))
        (autopoiesis.shen:sexpr-to-rules serialized)
        (format t "After restore: ~A rules~%~%" (length (autopoiesis.shen:list-rules))))

      (format t "--- CL fallback verification ---~%")
      (let* ((result-pass (autopoiesis.shen::cl-check-verify
                           '(:files-exist ("README.md" "src/main.py"))
                           "test output"
                           (list :metadata
                                 (list :after-tree
                                       '((:file "README.md" :hash "abc")
                                         (:file "src/main.py" :hash "def")
                                         (:file "test.py" :hash "ghi"))))))
             (result-fail (autopoiesis.shen::cl-check-verify
                           '(:files-exist ("README.md" "MISSING.txt"))
                           "test output"
                           (list :metadata
                                 (list :after-tree
                                       '((:file "README.md" :hash "abc")))))))
        (format t ":files-exist [README.md, src/main.py] with matching tree: ~A~%" result-pass)
        (format t ":files-exist [README.md, MISSING.txt] with partial tree: ~A~%~%" result-fail))

      (let ((result (autopoiesis.shen::cl-check-verify
                     '(:output-contains "All tests passed")
                     "Build complete. All tests passed. 42 assertions."
                     (list :metadata nil))))
        (format t ":output-contains 'All tests passed': ~A~%~%" result))

      (let ((result (autopoiesis.shen::cl-check-verify
                     '(:all (:files-exist ("src/" "README.md"))
                            (:output-contains "OK"))
                     "Status: OK"
                     (list :metadata
                           (list :after-tree
                                 '((:file "src/" :hash "a")
                                   (:file "README.md" :hash "b")))))))
        (format t ":all combinator (files + output): ~A~%~%" result)))
  (error (e) (format t "Shen error: ~A~%" e)))

(format t "~%========================================~%")
(format t "DEMO 4: Eval System~%")
(format t "========================================~%~%")

(handler-case
    (progn
      (handler-bind ((warning #'muffle-warning))
        (ql:quickload :autopoiesis/eval :silent t))
      (let ((pkg (find-package :autopoiesis.eval)))
        (when pkg
          ;; Eval operations need a substrate store
          (autopoiesis.substrate:with-store ()
            (let ((load-fn (find-symbol "LOAD-BUILTIN-SCENARIOS" pkg)))
              (when (and load-fn (fboundp load-fn))
                (funcall load-fn)))
            (let ((scenarios (funcall (find-symbol "LIST-SCENARIOS" pkg))))
              (format t "Builtin scenarios loaded: ~D~%~%" (length scenarios))
              ;; Show first 5
              (format t "Sample scenarios:~%")
              (loop for s in (subseq scenarios 0 (min 5 (length scenarios)))
                    do (format t "  ~A (~A) — ~A~%"
                               (getf s :name)
                               (getf s :domain)
                               (subseq (or (getf s :description) "") 0
                                       (min 60 (length (or (getf s :description) ""))))))
              (format t "~%")

              ;; Show verifier types
              (format t "Verifier types in use:~%")
              (let ((verifiers (remove-duplicates
                                (mapcar (lambda (s) (getf s :verifier)) scenarios))))
                (dolist (v verifiers)
                  (format t "  ~S~%" v)))
              (format t "~%")

              ;; Show domains
              (format t "Domains:~%")
              (let ((domains (remove-duplicates
                              (mapcar (lambda (s) (getf s :domain)) scenarios))))
                (dolist (d domains)
                  (let ((count (count d scenarios :key (lambda (s) (getf s :domain)))))
                    (format t "  ~A: ~D scenarios~%" d count)))))))))
  (error (e) (format t "Eval error: ~A~%" e)))

(format t "~%========================================~%")
(format t "DEMO 5: Full Prolog Pipeline~%")
(format t "========================================~%~%")

(handler-case
    (let ((pkg (find-package :autopoiesis.shen)))
      (when pkg
        (let ((define-fn (find-symbol "DEFINE-RULE" pkg))
              (query-fn (find-symbol "QUERY-RULES" pkg))
              (ensure-fn (find-symbol "ENSURE-SHEN-LOADED" pkg))
              (avail-fn (find-symbol "SHEN-AVAILABLE-P" pkg)))
          (when (and define-fn query-fn ensure-fn avail-fn
                     (fboundp define-fn) (fboundp query-fn)
                     (fboundp ensure-fn) (fboundp avail-fn))
            ;; Ensure Shen is loaded
            (funcall ensure-fn)
            (format t "Shen available: ~A~%~%" (funcall avail-fn))

            ;; Step 1: Define a fact-based rule (member predicate)
            (format t "--- Step 1: Define Prolog rules ---~%")
            (funcall define-fn :member
                     '(((member X (cons X _)) <--)
                       ((member X (cons _ REST)) <-- (member X REST))))
            (format t "Defined :member — recursive list membership~%")

            (funcall define-fn :append
                     '(((append nil X X) <--)
                       ((append (cons H T) L2 (cons H T2)) <-- (append T L2 T2))))
            (format t "Defined :append — list concatenation~%~%")

            ;; Step 2: Query the rules (auto-compiles into Shen Prolog)
            (format t "--- Step 2: Query rules (auto-compiles) ---~%")
            (let ((result (funcall query-fn :member :context '(b (cons a (cons b (cons c nil)))))))
              (format t "(member b [a b c]) => ~A~%" result))

            (let ((result (funcall query-fn :member :context '(z (cons a (cons b nil))))))
              (format t "(member z [a b])   => ~A  (correctly fails)~%~%" result))

            (format t "--- Step 3: Rules survive serialization ---~%")
            (let* ((ser-fn (find-symbol "RULES-TO-SEXPR" pkg))
                   (sexpr (when (and ser-fn (fboundp ser-fn)) (funcall ser-fn))))
              (format t "Serialized rules: ~S~%~%" sexpr))

            (format t "Full pipeline: define -> compile -> query -> serialize works!~%")))))
  (error (e) (format t "Prolog pipeline error: ~A~%" e)))

(format t "~%========================================~%")
(format t "ALL DEMOS COMPLETE~%")
(format t "========================================~%")

(sb-ext:exit)
