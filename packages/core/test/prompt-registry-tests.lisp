;;;; prompt-registry-tests.lisp - Tests for the prompt registry
;;;;
;;;; Tests versioned prompts, templating, substrate persistence,
;;;; serialization, and built-in prompt seeding.

(in-package #:autopoiesis.test)

(def-suite prompt-registry-tests
  :description "Tests for the prompt registry system")

(in-suite prompt-registry-tests)

;;; ===================================================================
;;; Helpers
;;; ===================================================================

(defun reset-prompt-registry ()
  "Clear registry and history between tests."
  (clrhash autopoiesis.integration:*prompt-registry*)
  (clrhash autopoiesis.integration:*prompt-history*))

;;; ===================================================================
;;; Constructor Tests
;;; ===================================================================

(test make-prompt-template-basic
  "make-prompt-template creates instance with correct slots and non-nil content-hash"
  (reset-prompt-registry)
  (let ((p (autopoiesis.integration:make-prompt-template
            :name "test" :body "hello world" :category :custom)))
    (is (equal "test" (autopoiesis.integration:prompt-name p)))
    (is (equal "hello world" (autopoiesis.integration:prompt-body p)))
    (is (eq :custom (autopoiesis.integration:prompt-category p)))
    (is (= 1 (autopoiesis.integration:prompt-version p)))
    (is (not (null (autopoiesis.integration:prompt-content-hash p))))
    (is (stringp (autopoiesis.integration:prompt-content-hash p)))
    (is (equal "system" (autopoiesis.integration:prompt-author p)))
    (is (null (autopoiesis.integration:prompt-parent p)))))

(test content-hash-changes-with-body
  "Content-hash changes when body changes"
  (reset-prompt-registry)
  (let ((p1 (autopoiesis.integration:make-prompt-template
             :name "a" :body "body one"))
        (p2 (autopoiesis.integration:make-prompt-template
             :name "b" :body "body two")))
    (is (not (equal (autopoiesis.integration:prompt-content-hash p1)
                    (autopoiesis.integration:prompt-content-hash p2))))))

(test make-prompt-template-validates-name
  "make-prompt-template signals error for invalid name"
  (reset-prompt-registry)
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:make-prompt-template :name "" :body "x"))
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:make-prompt-template :name nil :body "x")))

(test make-prompt-template-validates-body
  "make-prompt-template signals error for nil body"
  (reset-prompt-registry)
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:make-prompt-template :name "test" :body nil)))

;;; ===================================================================
;;; Registry API Tests
;;; ===================================================================

(test register-prompt-stores
  "register-prompt stores prompt in registry"
  (reset-prompt-registry)
  (let ((p (autopoiesis.integration:make-prompt-template
            :name "my-prompt" :body "hello")))
    (autopoiesis.integration:register-prompt p)
    (is (eq p (gethash "my-prompt" autopoiesis.integration:*prompt-registry*)))))

(test find-prompt-retrieves
  "find-prompt retrieves a registered prompt"
  (reset-prompt-registry)
  (let ((p (autopoiesis.integration:make-prompt-template
            :name "findme" :body "found")))
    (autopoiesis.integration:register-prompt p)
    (let ((found (autopoiesis.integration:find-prompt "findme")))
      (is (not (null found)))
      (is (equal "found" (autopoiesis.integration:prompt-body found))))))

(test find-prompt-nil-for-unknown
  "find-prompt returns NIL for unknown name"
  (reset-prompt-registry)
  (is (null (autopoiesis.integration:find-prompt "nonexistent"))))

(test list-prompts-returns-all
  "list-prompts returns all registered prompts"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "alpha" :body "a"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "beta" :body "b"))
  (let ((all (autopoiesis.integration:list-prompts)))
    (is (= 2 (length all)))
    ;; Sorted by name
    (is (equal "alpha" (autopoiesis.integration:prompt-name (first all))))
    (is (equal "beta" (autopoiesis.integration:prompt-name (second all))))))

(test list-prompts-filters-by-category
  "list-prompts filters by category"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "cat-a" :body "x" :category :cognitive-base))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "cat-b" :body "y" :category :self-extension))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "cat-c" :body "z" :category :cognitive-base))
  (let ((filtered (autopoiesis.integration:list-prompts :category :cognitive-base)))
    (is (= 2 (length filtered)))
    (is (every (lambda (p) (eq :cognitive-base (autopoiesis.integration:prompt-category p)))
               filtered))))

(test unregister-prompt-removes
  "unregister-prompt removes and returns T"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "doomed" :body "bye"))
  (is-true (autopoiesis.integration:unregister-prompt "doomed"))
  (is (null (autopoiesis.integration:find-prompt "doomed"))))

(test unregister-prompt-nil-for-unknown
  "unregister-prompt returns NIL for unknown name"
  (reset-prompt-registry)
  (is (null (autopoiesis.integration:unregister-prompt "ghost"))))

;;; ===================================================================
;;; Versioning Tests
;;; ===================================================================

(test re-register-auto-increments-version
  "Re-registering a prompt auto-increments version"
  (reset-prompt-registry)
  (let ((v1 (autopoiesis.integration:make-prompt-template
             :name "evolving" :body "version one")))
    (autopoiesis.integration:register-prompt v1)
    (let ((v2 (autopoiesis.integration:make-prompt-template
               :name "evolving" :body "version two")))
      (autopoiesis.integration:register-prompt v2)
      (let ((current (autopoiesis.integration:find-prompt "evolving")))
        (is (= 2 (autopoiesis.integration:prompt-version current)))
        (is (equal "version two" (autopoiesis.integration:prompt-body current)))))))

(test re-register-links-parent
  "Re-registering links parent to previous content-hash"
  (reset-prompt-registry)
  (let ((v1 (autopoiesis.integration:make-prompt-template
             :name "chain" :body "first")))
    (autopoiesis.integration:register-prompt v1)
    (let* ((v1-hash (autopoiesis.integration:prompt-content-hash v1))
           (v2 (autopoiesis.integration:make-prompt-template
                :name "chain" :body "second")))
      (autopoiesis.integration:register-prompt v2)
      (let ((current (autopoiesis.integration:find-prompt "chain")))
        (is (equal v1-hash (autopoiesis.integration:prompt-parent current)))))))

(test prompt-history-newest-first
  "prompt-history returns versions newest first"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "hist" :body "v1"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "hist" :body "v2"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "hist" :body "v3"))
  (let ((history (autopoiesis.integration:prompt-history "hist")))
    (is (= 3 (length history)))
    (is (= 3 (autopoiesis.integration:prompt-version (first history))))
    (is (= 2 (autopoiesis.integration:prompt-version (second history))))
    (is (= 1 (autopoiesis.integration:prompt-version (third history))))))

(test find-prompt-specific-version
  "find-prompt with :version returns that specific version"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "versioned" :body "first"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "versioned" :body "second"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template :name "versioned" :body "third"))
  (let ((v1 (autopoiesis.integration:find-prompt "versioned" :version 1))
        (v2 (autopoiesis.integration:find-prompt "versioned" :version 2)))
    (is (not (null v1)))
    (is (equal "first" (autopoiesis.integration:prompt-body v1)))
    (is (not (null v2)))
    (is (equal "second" (autopoiesis.integration:prompt-body v2)))))

;;; ===================================================================
;;; Fork Tests
;;; ===================================================================

(test fork-prompt-creates-derived
  "fork-prompt creates derived prompt with parent link"
  (reset-prompt-registry)
  (let ((original (autopoiesis.integration:make-prompt-template
                   :name "base" :body "original body" :category :custom)))
    (autopoiesis.integration:register-prompt original)
    (let ((forked (autopoiesis.integration:fork-prompt
                   "base" :new-body "modified body" :author "agent-1")))
      (is (equal "base" (autopoiesis.integration:prompt-name forked)))
      (is (equal "modified body" (autopoiesis.integration:prompt-body forked)))
      (is (equal "agent-1" (autopoiesis.integration:prompt-author forked)))
      (is (equal (autopoiesis.integration:prompt-content-hash original)
                 (autopoiesis.integration:prompt-parent forked)))
      ;; Version was bumped
      (is (= 2 (autopoiesis.integration:prompt-version forked))))))

(test fork-prompt-with-new-name
  "fork-prompt with new-name creates separate registry entry"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "source" :body "source body" :category :cognitive-base))
  (let ((forked (autopoiesis.integration:fork-prompt
                 "source" :new-name "derived" :new-body "derived body")))
    (is (equal "derived" (autopoiesis.integration:prompt-name forked)))
    ;; Both exist
    (is (not (null (autopoiesis.integration:find-prompt "source"))))
    (is (not (null (autopoiesis.integration:find-prompt "derived"))))
    ;; Inherits category
    (is (eq :cognitive-base (autopoiesis.integration:prompt-category forked)))))

(test fork-prompt-errors-on-unknown
  "fork-prompt signals error for unknown prompt name"
  (reset-prompt-registry)
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:fork-prompt "does-not-exist")))

;;; ===================================================================
;;; Templating Tests
;;; ===================================================================

(test substitute-variables-replaces
  "substitute-variables replaces bound variables"
  (let ((result (autopoiesis.integration:substitute-variables
                 "Hello {{name}}, welcome to {{place}}"
                 '(("name" . "World") ("place" . "Autopoiesis")))))
    (is (equal "Hello World, welcome to Autopoiesis" result))))

(test substitute-variables-leaves-unbound
  "substitute-variables leaves unbound variables as-is"
  (let ((result (autopoiesis.integration:substitute-variables
                 "Hello {{name}}, from {{unknown}}"
                 '(("name" . "Alice")))))
    (is (equal "Hello Alice, from {{unknown}}" result))))

(test resolve-includes-replaces-body
  "resolve-includes replaces {{include:name}} with included prompt body"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "greeting" :body "Hello there!"))
  (let ((result (autopoiesis.integration:resolve-includes
                 "Start: {{include:greeting}} End.")))
    (is (equal "Start: Hello there! End." result))))

(test resolve-includes-nested
  "resolve-includes handles nested includes"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "inner" :body "INNER"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "outer" :body "OUTER({{include:inner}})"))
  (let ((result (autopoiesis.integration:resolve-includes
                 "{{include:outer}}")))
    (is (equal "OUTER(INNER)" result))))

(test resolve-includes-circular-detection
  "resolve-includes detects circular includes and signals error"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "cycle-a" :body "A includes {{include:cycle-b}}"))
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "cycle-b" :body "B includes {{include:cycle-a}}"))
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:resolve-includes "{{include:cycle-a}}")))

(test render-prompt-combines
  "render-prompt resolves includes then substitutes variables"
  (reset-prompt-registry)
  (autopoiesis.integration:register-prompt
   (autopoiesis.integration:make-prompt-template
    :name "footer" :body "Best regards, {{sender}}"))
  (let ((p (autopoiesis.integration:make-prompt-template
            :name "email" :body "Dear {{recipient}}, {{include:footer}}")))
    (autopoiesis.integration:register-prompt p)
    (let ((result (autopoiesis.integration:render-prompt
                   p (list (cons "recipient" "Bob") (cons "sender" "Alice")))))
      (is (equal "Dear Bob, Best regards, Alice" result)))))

;;; ===================================================================
;;; defprompt Macro Tests
;;; ===================================================================

(test defprompt-macro-registers
  "defprompt macro defines and registers a prompt"
  (reset-prompt-registry)
  (autopoiesis.integration:defprompt "macro-test"
    (:category :custom :variables ("x"))
    "body with {{x}}")
  (let ((p (autopoiesis.integration:find-prompt "macro-test")))
    (is (not (null p)))
    (is (equal "body with {{x}}" (autopoiesis.integration:prompt-body p)))
    (is (eq :custom (autopoiesis.integration:prompt-category p)))
    (is (equal '("x") (autopoiesis.integration:prompt-variables p)))))

;;; ===================================================================
;;; Built-in Prompts Tests
;;; ===================================================================

(test builtin-prompts-loaded
  "seed-builtin-prompts registers all expected built-in prompts"
  (reset-prompt-registry)
  (autopoiesis.integration:seed-builtin-prompts)
  (let ((names '("cognitive-base" "agent-guidelines" "self-extension"
                 "provider-bridge" "orchestration")))
    (dolist (name names)
      (is (not (null (autopoiesis.integration:find-prompt name)))
          "Expected built-in prompt ~a to be registered" name))
    ;; cognitive-base has variables and includes
    (let ((cb (autopoiesis.integration:find-prompt "cognitive-base")))
      (is (member "agent-name" (autopoiesis.integration:prompt-variables cb)
                  :test #'string=))
      (is (member "agent-guidelines" (autopoiesis.integration:prompt-includes cb)
                  :test #'string=)))))

;;; ===================================================================
;;; Serialization Tests
;;; ===================================================================

(test prompt-to-sexpr-round-trip
  "prompt-to-sexpr / sexpr-to-prompt round-trip preserves fields"
  (reset-prompt-registry)
  (let* ((original (autopoiesis.integration:make-prompt-template
                    :name "serial" :body "test body"
                    :category :custom :variables '("a" "b")
                    :includes '("other") :author "tester"))
         (sexpr (autopoiesis.integration:prompt-to-sexpr original))
         (restored (autopoiesis.integration:sexpr-to-prompt sexpr)))
    (is (equal (autopoiesis.integration:prompt-name original)
               (autopoiesis.integration:prompt-name restored)))
    (is (equal (autopoiesis.integration:prompt-body original)
               (autopoiesis.integration:prompt-body restored)))
    (is (eq (autopoiesis.integration:prompt-category original)
            (autopoiesis.integration:prompt-category restored)))
    (is (equal (autopoiesis.integration:prompt-version original)
               (autopoiesis.integration:prompt-version restored)))
    (is (equal (autopoiesis.integration:prompt-content-hash original)
               (autopoiesis.integration:prompt-content-hash restored)))
    (is (equal (autopoiesis.integration:prompt-author original)
               (autopoiesis.integration:prompt-author restored)))
    (is (equal (autopoiesis.integration:prompt-variables original)
               (autopoiesis.integration:prompt-variables restored)))
    (is (equal (autopoiesis.integration:prompt-includes original)
               (autopoiesis.integration:prompt-includes restored)))))

(test sexpr-to-prompt-rejects-invalid
  "sexpr-to-prompt signals error for invalid input"
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:sexpr-to-prompt '(:not-a-prompt :name "x")))
  (signals autopoiesis.core:autopoiesis-error
    (autopoiesis.integration:sexpr-to-prompt "not a list")))

;;; ===================================================================
;;; Substrate Persistence Tests
;;; ===================================================================

(test persist-and-load-round-trip
  "persist-prompt / load-prompts-from-substrate round-trip via substrate"
  (reset-prompt-registry)
  (autopoiesis.substrate:with-store ()
    (let ((p (autopoiesis.integration:make-prompt-template
              :name "persist-test" :body "persistent body"
              :category :custom :author "tester")))
      (autopoiesis.integration:register-prompt p)
      (let ((eid (autopoiesis.integration:persist-prompt p)))
        (is (integerp eid))
        ;; Verify entity-type datom
        (is (eq :prompt (autopoiesis.substrate:entity-attr eid :entity/type)))
        ;; Clear registry, reload from substrate
        (reset-prompt-registry)
        (let ((count (autopoiesis.integration:load-prompts-from-substrate)))
          (is (= 1 count))
          (let ((loaded (autopoiesis.integration:find-prompt "persist-test")))
            (is (not (null loaded)))
            (is (equal "persistent body" (autopoiesis.integration:prompt-body loaded)))
            (is (eq :custom (autopoiesis.integration:prompt-category loaded)))
            (is (equal "tester" (autopoiesis.integration:prompt-author loaded)))))))))

;;; ===================================================================
;;; Entity Type Registration Test
;;; ===================================================================

(test prompt-entity-type-registered
  "Entity type :prompt is registered in the entity-type-registry"
  (is (not (null (gethash :prompt autopoiesis.substrate:*entity-type-registry*)))))

;;; ===================================================================
;;; generate-system-prompt Integration Test
;;; ===================================================================

(test generate-system-prompt-uses-registry
  "generate-system-prompt uses registry when cognitive-base is registered"
  (reset-prompt-registry)
  (autopoiesis.integration:seed-builtin-prompts)
  (let* ((agent (autopoiesis.agent:make-agent :name "test-agent"))
         (prompt (autopoiesis.integration:generate-system-prompt agent)))
    (is (stringp prompt))
    (is (not (null (search "test-agent" prompt))))
    ;; Should contain the included agent-guidelines text
    (is (not (null (search "Guidelines" prompt))))))
