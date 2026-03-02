;;;; swarm-tests.lisp - Tests for swarm layer
;;;;
;;;; Tests genome, fitness, selection, operators, population, and production rules.

(in-package #:autopoiesis.test)

(def-suite swarm-tests
  :description "Swarm primitives and production rules tests"
  :in all-tests)

(in-suite swarm-tests)

;;; ===================================================================
;;; Genome Tests
;;; ===================================================================

(test genome-creation
  "Test basic genome creation"
  (let ((g (autopoiesis.swarm:make-genome
            :capabilities '(:read :write)
            :heuristic-weights '((:h1 . 0.5) (:h2 . 0.8))
            :parameters '(:threshold 0.7 :max-depth 10))))
    (is (not (null (autopoiesis.swarm:genome-id g))))
    (is (equal '(:read :write) (autopoiesis.swarm:genome-capabilities g)))
    (is (= 2 (length (autopoiesis.swarm:genome-heuristic-weights g))))
    (is (= 0.7 (getf (autopoiesis.swarm:genome-parameters g) :threshold)))
    (is (= 10 (getf (autopoiesis.swarm:genome-parameters g) :max-depth)))
    (is (null (autopoiesis.swarm:genome-lineage g)))
    (is (= 0.0 (autopoiesis.swarm:genome-fitness g)))
    (is (= 0 (autopoiesis.swarm:genome-generation g)))))

(test genome-default-creation
  "Test genome creation with defaults"
  (let ((g (autopoiesis.swarm:make-genome)))
    (is (not (null (autopoiesis.swarm:genome-id g))))
    (is (null (autopoiesis.swarm:genome-capabilities g)))
    (is (null (autopoiesis.swarm:genome-heuristic-weights g)))
    (is (null (autopoiesis.swarm:genome-parameters g)))
    (is (= 0.0 (autopoiesis.swarm:genome-fitness g)))
    (is (= 0 (autopoiesis.swarm:genome-generation g)))))

(test genome-serialization-roundtrip
  "Test genome serialization and deserialization"
  (let* ((g (autopoiesis.swarm:make-genome
             :capabilities '(:read :write :execute)
             :heuristic-weights '((:h1 . 0.5) (:h2 . 0.8))
             :parameters '(:threshold 0.7 :max-depth 10)
             :lineage '("parent-1" "parent-2")
             :generation 3))
         (sexpr (autopoiesis.swarm:genome-to-sexpr g))
         (restored (autopoiesis.swarm:sexpr-to-genome sexpr)))
    ;; Check sexpr format
    (is (eq :genome (first sexpr)))
    (is (not (null restored)))
    ;; Check all fields round-trip
    (is (equal (autopoiesis.swarm:genome-id g)
               (autopoiesis.swarm:genome-id restored)))
    (is (equal (autopoiesis.swarm:genome-capabilities g)
               (autopoiesis.swarm:genome-capabilities restored)))
    (is (equal (autopoiesis.swarm:genome-heuristic-weights g)
               (autopoiesis.swarm:genome-heuristic-weights restored)))
    (is (equal (autopoiesis.swarm:genome-parameters g)
               (autopoiesis.swarm:genome-parameters restored)))
    (is (equal (autopoiesis.swarm:genome-lineage g)
               (autopoiesis.swarm:genome-lineage restored)))
    (is (= (autopoiesis.swarm:genome-fitness g)
            (autopoiesis.swarm:genome-fitness restored)))
    (is (= (autopoiesis.swarm:genome-generation g)
            (autopoiesis.swarm:genome-generation restored)))))

(test genome-serialization-nil-input
  "Test sexpr-to-genome with invalid input returns nil"
  (is (null (autopoiesis.swarm:sexpr-to-genome nil)))
  (is (null (autopoiesis.swarm:sexpr-to-genome '(:not-a-genome))))
  (is (null (autopoiesis.swarm:sexpr-to-genome "not a list"))))

(test genome-fitness-slot
  "Test setting fitness on a genome"
  (let ((g (autopoiesis.swarm:make-genome)))
    (setf (autopoiesis.swarm:genome-fitness g) 42.0)
    (is (= 42.0 (autopoiesis.swarm:genome-fitness g)))
    ;; Verify serialization preserves fitness
    (let ((restored (autopoiesis.swarm:sexpr-to-genome
                     (autopoiesis.swarm:genome-to-sexpr g))))
      (is (= 42.0 (autopoiesis.swarm:genome-fitness restored))))))

(test genome-instantiate-agent
  "Test creating an agent from a genome"
  (let* ((g (autopoiesis.swarm:make-genome
             :capabilities '(:read :write)))
         (agent (autopoiesis.swarm:instantiate-agent-from-genome g)))
    (is (not (null agent)))
    (is (stringp (autopoiesis.agent:agent-name agent)))
    (is (search "genome-" (autopoiesis.agent:agent-name agent)))
    (is (equal '(:read :write) (autopoiesis.agent:agent-capabilities agent)))))

;;; ===================================================================
;;; Fitness Evaluation Tests
;;; ===================================================================

(test fitness-evaluator-creation
  "Test fitness evaluator creation"
  (let ((eval (autopoiesis.swarm:make-fitness-evaluator
               :name "test-eval"
               :eval-fn (lambda (g env)
                          (declare (ignore env))
                          (length (autopoiesis.swarm:genome-capabilities g))))))
    (is (string= "test-eval" (autopoiesis.swarm:evaluator-name eval)))
    (is (not (null (autopoiesis.swarm:evaluator-fn eval))))))

(test fitness-evaluate-single
  "Test evaluating a single genome's fitness"
  (let ((eval (autopoiesis.swarm:make-fitness-evaluator
               :name "cap-count"
               :eval-fn (lambda (g env)
                          (declare (ignore env))
                          (length (autopoiesis.swarm:genome-capabilities g)))))
        (g (autopoiesis.swarm:make-genome :capabilities '(:read :write :execute))))
    (let ((score (autopoiesis.swarm:evaluate-fitness eval g nil)))
      (is (= 3 score))
      (is (= 3 (autopoiesis.swarm:genome-fitness g))))))

(test fitness-evaluate-population
  "Test evaluating an entire population"
  (let* ((eval (autopoiesis.swarm:make-fitness-evaluator
                :name "cap-count"
                :eval-fn (lambda (g env)
                           (declare (ignore env))
                           (length (autopoiesis.swarm:genome-capabilities g)))))
         (genomes (list
                   (autopoiesis.swarm:make-genome :capabilities '(:read))
                   (autopoiesis.swarm:make-genome :capabilities '(:read :write))
                   (autopoiesis.swarm:make-genome :capabilities '(:read :write :execute))))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    (let ((result (autopoiesis.swarm:evaluate-population eval pop nil)))
      (is (= 3 (length result)))
      (is (= 1 (autopoiesis.swarm:genome-fitness (first result))))
      (is (= 2 (autopoiesis.swarm:genome-fitness (second result))))
      (is (= 3 (autopoiesis.swarm:genome-fitness (third result)))))))

(test fitness-evaluate-population-sequential
  "Test that sequential fallback works when parallel requested but no lparallel"
  (let* ((eval (autopoiesis.swarm:make-fitness-evaluator
                :name "simple"
                :eval-fn (lambda (g env)
                           (declare (ignore env))
                           (float (length (autopoiesis.swarm:genome-capabilities g))))))
         (pop (autopoiesis.swarm:make-population
               :genomes (list (autopoiesis.swarm:make-genome :capabilities '(:a :b))))))
    ;; Should fall back to sequential if lparallel not loaded
    (let ((result (autopoiesis.swarm:evaluate-population eval pop nil :parallel t)))
      (is (= 1 (length result)))
      (is (= 2.0 (autopoiesis.swarm:genome-fitness (first result)))))))

;;; ===================================================================
;;; Selection Tests
;;; ===================================================================

(test tournament-selection
  "Test tournament selection picks high-fitness genomes"
  (let* ((genomes (loop for i from 1 to 10
                        collect (let ((g (autopoiesis.swarm:make-genome
                                         :capabilities (make-list i :initial-element :cap))))
                                  (setf (autopoiesis.swarm:genome-fitness g) (float i))
                                  g)))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    ;; With tournament of full population, should always get the best
    (let ((selected (autopoiesis.swarm:tournament-select pop :tournament-size 10)))
      (is (= 10.0 (autopoiesis.swarm:genome-fitness selected))))
    ;; Tournament of 1 should still return a valid genome
    (let ((selected (autopoiesis.swarm:tournament-select pop :tournament-size 1)))
      (is (not (null selected)))
      (is (typep selected 'autopoiesis.swarm:genome)))))

(test roulette-selection
  "Test roulette selection returns a valid genome"
  (let* ((genomes (loop for i from 1 to 5
                        collect (let ((g (autopoiesis.swarm:make-genome)))
                                  (setf (autopoiesis.swarm:genome-fitness g) (float i))
                                  g)))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    ;; Run many selections and verify all are valid genomes
    (dotimes (i 20)
      (declare (ignore i))
      (let ((selected (autopoiesis.swarm:roulette-select pop)))
        (is (not (null selected)))
        (is (typep selected 'autopoiesis.swarm:genome))))))

(test roulette-selection-zero-fitness
  "Test roulette selection handles all-zero fitness"
  (let* ((genomes (loop for i from 1 to 5
                        collect (autopoiesis.swarm:make-genome)))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    ;; All have fitness 0.0, should still return a valid genome
    (let ((selected (autopoiesis.swarm:roulette-select pop)))
      (is (not (null selected)))
      (is (typep selected 'autopoiesis.swarm:genome)))))

(test elitism-selection
  "Test elitism selects the top genomes"
  (let* ((genomes (loop for i from 1 to 10
                        collect (let ((g (autopoiesis.swarm:make-genome)))
                                  (setf (autopoiesis.swarm:genome-fitness g) (float i))
                                  g)))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    (let ((elites (autopoiesis.swarm:elitism-select pop :count 3)))
      (is (= 3 (length elites)))
      (is (= 10.0 (autopoiesis.swarm:genome-fitness (first elites))))
      (is (= 9.0 (autopoiesis.swarm:genome-fitness (second elites))))
      (is (= 8.0 (autopoiesis.swarm:genome-fitness (third elites)))))))

(test elitism-select-more-than-population
  "Test elitism with count larger than population"
  (let* ((genomes (list (autopoiesis.swarm:make-genome)
                        (autopoiesis.swarm:make-genome)))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    (let ((elites (autopoiesis.swarm:elitism-select pop :count 5)))
      (is (= 2 (length elites))))))

;;; ===================================================================
;;; Genetic Operator Tests
;;; ===================================================================

(test crossover-produces-valid-genome
  "Test crossover creates a valid child genome"
  (let* ((parent-a (autopoiesis.swarm:make-genome
                    :capabilities '(:read :write)
                    :heuristic-weights '((:h1 . 0.3) (:h2 . 0.7))
                    :parameters '(:threshold 0.5 :depth 5)
                    :generation 2))
         (parent-b (autopoiesis.swarm:make-genome
                    :capabilities '(:write :execute)
                    :heuristic-weights '((:h2 . 0.9) (:h3 . 0.4))
                    :parameters '(:threshold 0.9 :width 10)
                    :generation 3))
         (child (autopoiesis.swarm:crossover-genomes parent-a parent-b)))
    ;; Child should be a genome
    (is (typep child 'autopoiesis.swarm:genome))
    ;; Lineage should contain both parents
    (is (= 2 (length (autopoiesis.swarm:genome-lineage child))))
    (is (member (autopoiesis.swarm:genome-id parent-a)
                (autopoiesis.swarm:genome-lineage child) :test #'equal))
    (is (member (autopoiesis.swarm:genome-id parent-b)
                (autopoiesis.swarm:genome-lineage child) :test #'equal))
    ;; Generation should be max + 1
    (is (= 4 (autopoiesis.swarm:genome-generation child)))
    ;; Should have a unique ID
    (is (not (equal (autopoiesis.swarm:genome-id parent-a)
                    (autopoiesis.swarm:genome-id child))))
    (is (not (equal (autopoiesis.swarm:genome-id parent-b)
                    (autopoiesis.swarm:genome-id child))))))

(test crossover-capabilities-deduped
  "Test crossover deduplicates capabilities"
  ;; Run many times to account for randomness
  (dotimes (i 20)
    (declare (ignore i))
    (let* ((parent-a (autopoiesis.swarm:make-genome :capabilities '(:read :write)))
           (parent-b (autopoiesis.swarm:make-genome :capabilities '(:write :execute)))
           (child (autopoiesis.swarm:crossover-genomes parent-a parent-b))
           (caps (autopoiesis.swarm:genome-capabilities child)))
      ;; No duplicates
      (is (= (length caps) (length (remove-duplicates caps :test #'equal)))))))

(test crossover-heuristic-weights-averaged
  "Test crossover averages shared heuristic weights"
  ;; Many trials to verify averaging (not randomness)
  (let ((found-average nil))
    (dotimes (i 50)
      (declare (ignore i))
      (let* ((parent-a (autopoiesis.swarm:make-genome
                        :heuristic-weights '((:shared . 0.4))))
             (parent-b (autopoiesis.swarm:make-genome
                        :heuristic-weights '((:shared . 0.8))))
             (child (autopoiesis.swarm:crossover-genomes parent-a parent-b))
             (w (cdr (assoc :shared (autopoiesis.swarm:genome-heuristic-weights child)))))
        (when (and w (< (abs (- w 0.6)) 0.01))
          (setf found-average t))))
    (is (eq t found-average))))

(test mutation-does-not-modify-original
  "Test mutation returns a new genome without modifying the original"
  (let* ((original (autopoiesis.swarm:make-genome
                    :capabilities '(:read :write)
                    :heuristic-weights '((:h1 . 0.5))
                    :parameters '(:threshold 0.7)))
         (orig-caps (copy-list (autopoiesis.swarm:genome-capabilities original)))
         (orig-id (autopoiesis.swarm:genome-id original))
         (mutated (autopoiesis.swarm:mutate-genome original :mutation-rate 1.0)))
    ;; Original unchanged
    (is (equal orig-caps (autopoiesis.swarm:genome-capabilities original)))
    (is (equal orig-id (autopoiesis.swarm:genome-id original)))
    ;; Mutated is a different object
    (is (not (eq original mutated)))
    (is (not (equal (autopoiesis.swarm:genome-id original)
                    (autopoiesis.swarm:genome-id mutated))))))

(test mutation-with-zero-rate
  "Test mutation with rate 0 produces near-identical copy"
  (let* ((original (autopoiesis.swarm:make-genome
                    :capabilities '(:read)
                    :heuristic-weights '((:h1 . 0.5))
                    :parameters '(:threshold 0.7)))
         (mutated (autopoiesis.swarm:mutate-genome original :mutation-rate 0.0)))
    ;; Should preserve capabilities, weights, params
    (is (equal '(:read) (autopoiesis.swarm:genome-capabilities mutated)))
    (is (= 0.5 (cdr (first (autopoiesis.swarm:genome-heuristic-weights mutated)))))
    (is (= 0.7 (getf (autopoiesis.swarm:genome-parameters mutated) :threshold)))))

(test mutation-lineage-tracking
  "Test mutation records parent in lineage"
  (let* ((original (autopoiesis.swarm:make-genome))
         (mutated (autopoiesis.swarm:mutate-genome original)))
    (is (= 1 (length (autopoiesis.swarm:genome-lineage mutated))))
    (is (equal (autopoiesis.swarm:genome-id original)
               (first (autopoiesis.swarm:genome-lineage mutated))))))

;;; ===================================================================
;;; Population Tests
;;; ===================================================================

(test population-creation-default
  "Test population creation with default genomes"
  (let ((pop (autopoiesis.swarm:make-population :size 10)))
    (is (= 10 (length (autopoiesis.swarm:population-genomes pop))))
    (is (= 10 (autopoiesis.swarm:population-size pop)))
    (is (= 0 (autopoiesis.swarm:population-generation pop)))
    (is (null (autopoiesis.swarm:population-history pop)))))

(test population-creation-with-genomes
  "Test population creation with provided genomes"
  (let* ((genomes (list (autopoiesis.swarm:make-genome :capabilities '(:a))
                        (autopoiesis.swarm:make-genome :capabilities '(:b))))
         (pop (autopoiesis.swarm:make-population :genomes genomes)))
    (is (= 2 (length (autopoiesis.swarm:population-genomes pop))))
    (is (equal '(:a) (autopoiesis.swarm:genome-capabilities
                      (first (autopoiesis.swarm:population-genomes pop)))))))

(test evolve-generation-basic
  "Test single generation evolution"
  (let* ((eval (autopoiesis.swarm:make-fitness-evaluator
                :name "cap-count"
                :eval-fn (lambda (g env)
                           (declare (ignore env))
                           (float (length (autopoiesis.swarm:genome-capabilities g))))))
         (genomes (loop for i from 1 to 10
                        collect (autopoiesis.swarm:make-genome
                                 :capabilities (make-list i :initial-element :cap))))
         (pop (autopoiesis.swarm:make-population :genomes genomes))
         (new-pop (autopoiesis.swarm:evolve-generation eval pop nil)))
    ;; Generation incremented
    (is (= 1 (autopoiesis.swarm:population-generation new-pop)))
    ;; Size preserved
    (is (= 10 (length (autopoiesis.swarm:population-genomes new-pop))))
    ;; History recorded
    (is (= 1 (length (autopoiesis.swarm:population-history new-pop))))
    (let ((entry (first (autopoiesis.swarm:population-history new-pop))))
      (is (= 0 (first entry)))        ; generation 0
      (is (= 10.0 (second entry)))    ; best fitness
      (is (= 5.5 (third entry))))))   ; avg fitness

(test evolve-fitness-improves
  "Test that evolution improves fitness over generations"
  (let* ((eval (autopoiesis.swarm:make-fitness-evaluator
                :name "cap-count"
                :eval-fn (lambda (g env)
                           (declare (ignore env))
                           (float (length (autopoiesis.swarm:genome-capabilities g))))))
         ;; Start with genomes having 0-3 capabilities
         (genomes (loop for i from 0 to 9
                        collect (autopoiesis.swarm:make-genome
                                 :capabilities (make-list (mod i 4) :initial-element :cap))))
         (pop (autopoiesis.swarm:make-population :genomes genomes))
         (final (autopoiesis.swarm:run-evolution eval pop nil :generations 5)))
    ;; Should have evolved for 5 generations
    (is (= 5 (autopoiesis.swarm:population-generation final)))
    ;; History should have 5 entries
    (is (= 5 (length (autopoiesis.swarm:population-history final))))))

(test evolution-early-termination
  "Test evolution stops early when target fitness reached"
  (let* ((eval (autopoiesis.swarm:make-fitness-evaluator
                :name "cap-count"
                :eval-fn (lambda (g env)
                           (declare (ignore env))
                           (float (length (autopoiesis.swarm:genome-capabilities g))))))
         (genomes (loop for i from 1 to 10
                        collect (autopoiesis.swarm:make-genome
                                 :capabilities (make-list i :initial-element :cap))))
         (pop (autopoiesis.swarm:make-population :genomes genomes))
         (final (autopoiesis.swarm:run-evolution eval pop nil
                                                 :generations 100
                                                 :target-fitness 5.0)))
    ;; Should terminate well before 100 generations (the initial pop has fitness up to 10)
    (is (< (autopoiesis.swarm:population-generation final) 100))
    ;; Best fitness should meet target
    (let ((best (reduce #'max (autopoiesis.swarm:population-genomes final)
                        :key #'autopoiesis.swarm:genome-fitness)))
      (is (>= (autopoiesis.swarm:genome-fitness best) 5.0)))))

(test evolution-preserves-population-size
  "Test evolution maintains consistent population size"
  (let* ((eval (autopoiesis.swarm:make-fitness-evaluator
                :name "simple"
                :eval-fn (lambda (g env)
                           (declare (ignore env))
                           (float (length (autopoiesis.swarm:genome-capabilities g))))))
         (pop (autopoiesis.swarm:make-population :size 15))
         (final (autopoiesis.swarm:run-evolution eval pop nil :generations 3)))
    (is (= 15 (length (autopoiesis.swarm:population-genomes final))))))

;;; ===================================================================
;;; Production Rule Tests
;;; ===================================================================

(test production-rule-creation
  "Test production rule creation"
  (let ((rule (autopoiesis.swarm:make-production-rule
               :condition '(:task-type :analysis)
               :action (lambda (g) g)
               :priority 50
               :source :manual)))
    (is (equal '(:task-type :analysis) (autopoiesis.swarm:rule-condition rule)))
    (is (functionp (autopoiesis.swarm:rule-action rule)))
    (is (= 50 (autopoiesis.swarm:rule-priority rule)))
    (is (eq :manual (autopoiesis.swarm:rule-source rule)))))

(test production-rule-default-values
  "Test production rule default values"
  (let ((rule (autopoiesis.swarm:make-production-rule
               :condition t
               :action #'identity)))
    (is (= 0 (autopoiesis.swarm:rule-priority rule)))
    (is (eq :manual (autopoiesis.swarm:rule-source rule)))))

(test extract-rules-from-heuristics
  "Test extracting production rules from high-confidence heuristics"
  (let* ((h1 (autopoiesis.agent:make-heuristic
              :name "good-heuristic"
              :condition '(:task-type :analysis)
              :recommendation '(:prefer :deep-analysis)
              :confidence 0.9))
         (h2 (autopoiesis.agent:make-heuristic
              :name "weak-heuristic"
              :condition '(:task-type :simple)
              :recommendation '(:prefer :quick)
              :confidence 0.3))
         (h3 (autopoiesis.agent:make-heuristic
              :name "moderate-heuristic"
              :condition '(:task-type :mixed)
              :recommendation '(:prefer :balanced)
              :confidence 0.8))
         (rules (autopoiesis.swarm:extract-production-rules
                 (list h1 h2 h3) :min-confidence 0.7)))
    ;; Should only get 2 rules (h1 and h3 pass confidence threshold)
    (is (= 2 (length rules)))
    ;; Both should be :learned source
    (is (every (lambda (r) (eq :learned (autopoiesis.swarm:rule-source r))) rules))
    ;; Priorities should be based on confidence
    (is (= 90 (autopoiesis.swarm:rule-priority (first rules))))
    (is (= 80 (autopoiesis.swarm:rule-priority (second rules))))))

(test extract-rules-none-qualify
  "Test extraction when no heuristics meet confidence threshold"
  (let* ((h (autopoiesis.agent:make-heuristic
             :name "weak"
             :condition t
             :recommendation '(:noop)
             :confidence 0.1))
         (rules (autopoiesis.swarm:extract-production-rules (list h))))
    (is (null rules))))

(test apply-rules-unconditional
  "Test applying an unconditional (condition T) rule"
  (let* ((genome (autopoiesis.swarm:make-genome :parameters '(:x 1)))
         (rule (autopoiesis.swarm:make-production-rule
                :condition t
                :action (lambda (g)
                          (autopoiesis.swarm:make-genome
                           :capabilities (autopoiesis.swarm:genome-capabilities g)
                           :heuristic-weights (autopoiesis.swarm:genome-heuristic-weights g)
                           :parameters (list* :applied t (autopoiesis.swarm:genome-parameters g))
                           :lineage (autopoiesis.swarm:genome-lineage g)
                           :generation (autopoiesis.swarm:genome-generation g)))))
         (result (autopoiesis.swarm:apply-production-rules genome (list rule))))
    (is (not (null result)))
    (is (eq t (getf (autopoiesis.swarm:genome-parameters result) :applied)))
    (is (= 1 (getf (autopoiesis.swarm:genome-parameters result) :x)))))

(test apply-rules-priority-order
  "Test that rules are applied in priority order (highest first)"
  (let* ((genome (autopoiesis.swarm:make-genome :parameters '(:order nil)))
         (rule-low (autopoiesis.swarm:make-production-rule
                    :condition t
                    :priority 10
                    :action (lambda (g)
                              (autopoiesis.swarm:make-genome
                               :capabilities (autopoiesis.swarm:genome-capabilities g)
                               :parameters (let ((p (copy-list (autopoiesis.swarm:genome-parameters g))))
                                             (setf (getf p :order)
                                                   (append (getf p :order) '(:low)))
                                             p)
                               :lineage (autopoiesis.swarm:genome-lineage g)
                               :generation (autopoiesis.swarm:genome-generation g)))))
         (rule-high (autopoiesis.swarm:make-production-rule
                     :condition t
                     :priority 90
                     :action (lambda (g)
                               (autopoiesis.swarm:make-genome
                                :capabilities (autopoiesis.swarm:genome-capabilities g)
                                :parameters (let ((p (copy-list (autopoiesis.swarm:genome-parameters g))))
                                              (setf (getf p :order)
                                                    (append (getf p :order) '(:high)))
                                              p)
                                :lineage (autopoiesis.swarm:genome-lineage g)
                                :generation (autopoiesis.swarm:genome-generation g)))))
         (result (autopoiesis.swarm:apply-production-rules
                  genome (list rule-low rule-high))))
    ;; High priority should have been applied first
    (is (equal '(:high :low) (getf (autopoiesis.swarm:genome-parameters result) :order)))))

(test apply-rules-condition-matching
  "Test that rules with non-matching conditions are skipped"
  (let* ((genome (autopoiesis.swarm:make-genome
                  :capabilities '(:read)
                  :parameters '(:x 1)))
         (matching-rule (autopoiesis.swarm:make-production-rule
                         :condition :read  ; matches a capability
                         :action (lambda (g)
                                   (autopoiesis.swarm:make-genome
                                    :capabilities (autopoiesis.swarm:genome-capabilities g)
                                    :parameters (list* :matched t
                                                       (autopoiesis.swarm:genome-parameters g))
                                    :lineage (autopoiesis.swarm:genome-lineage g)
                                    :generation (autopoiesis.swarm:genome-generation g)))))
         (non-matching-rule (autopoiesis.swarm:make-production-rule
                             :condition :nonexistent
                             :action (lambda (g)
                                       (autopoiesis.swarm:make-genome
                                        :capabilities (autopoiesis.swarm:genome-capabilities g)
                                        :parameters (list* :should-not-match t
                                                           (autopoiesis.swarm:genome-parameters g))
                                        :lineage (autopoiesis.swarm:genome-lineage g)
                                        :generation (autopoiesis.swarm:genome-generation g)))))
         (result (autopoiesis.swarm:apply-production-rules
                  genome (list matching-rule non-matching-rule))))
    (is (eq t (getf (autopoiesis.swarm:genome-parameters result) :matched)))
    (is (null (getf (autopoiesis.swarm:genome-parameters result) :should-not-match)))))

(test apply-rules-empty-rules
  "Test applying empty rule set returns original genome"
  (let* ((genome (autopoiesis.swarm:make-genome :capabilities '(:read)))
         (result (autopoiesis.swarm:apply-production-rules genome nil)))
    (is (eq genome result))))

(test extracted-rules-modify-genome
  "Test that extracted production rules actually transform genomes"
  (let* ((h (autopoiesis.agent:make-heuristic
             :name "test-h"
             :condition t
             :recommendation '(:use-caching t)
             :confidence 0.95))
         (rules (autopoiesis.swarm:extract-production-rules (list h)))
         (genome (autopoiesis.swarm:make-genome :parameters '(:speed 1.0)))
         (result (autopoiesis.swarm:apply-production-rules genome rules)))
    (is (not (null result)))
    (is (equal '(:use-caching t)
               (getf (autopoiesis.swarm:genome-parameters result) :learned-recommendation)))
    ;; Original param preserved
    (is (= 1.0 (getf (autopoiesis.swarm:genome-parameters result) :speed)))))
