;;;; aether-seed.lisp - Synthetic lineage generator for AETHER Week-1
;;;;
;;;; Builds a populated snapshot store full of persistent-agents with varied
;;;; lineages, divergence, and cognitive activity. Output is meant to be
;;;; served by `(autopoiesis.api:start-rest-server)` so the AETHER frontend
;;;; can render a believable DAG without needing a live agentic loop.
;;;;
;;;; Public entry point:
;;;;   (aether-seed:populate :path #P"/tmp/aether-seed/" :n 60 :seed 42)
;;;;
;;;; - Idempotent: the same SEED + N produces the same store. The store
;;;;   directory is wiped before regeneration so partial state never bleeds in.
;;;; - Uses only existing primitives: make-persistent-agent, persistent-fork,
;;;;   pvec-push, pset-add, pmap-put, make-snapshot, save-snapshot.
;;;; - Variance is deliberate. Three "moods" of lineage drive different
;;;;   branching factors, cognitive activity rates, and diff magnitudes so
;;;;   the spectral classification function has signal to work with.

(in-package #:cl-user)

(unless (find-package :aether-seed)
  (defpackage #:aether-seed
    (:use #:cl)
    (:export #:populate)))

(in-package #:aether-seed)

;;; ════════════════════════════════════════════════════════════════════
;;; Seeded RNG (linear-congruential, intentionally trivial)
;;; ════════════════════════════════════════════════════════════════════

(defvar *rng-state* 42)

(defun rng-reset (seed)
  (setf *rng-state* (logand seed #xFFFFFFFF))
  (when (zerop *rng-state*)
    (setf *rng-state* 1)))

(defun rng-next ()
  "Glibc-style LCG. Returns a fixnum in [0, 2^31)."
  (setf *rng-state*
        (logand (+ (* *rng-state* 1103515245) 12345) #x7FFFFFFF))
  *rng-state*)

(defun rng-int (n)
  "Uniform integer in [0, n)."
  (mod (rng-next) n))

(defun rng-float ()
  "Uniform float in [0, 1)."
  (/ (rng-next) #x80000000))

(defun rng-choice (seq)
  (elt seq (rng-int (length seq))))

(defun rng-chance (p)
  (< (rng-float) p))

;;; ════════════════════════════════════════════════════════════════════
;;; Vocabulary — varied so the underlying S-exprs actually diverge
;;; ════════════════════════════════════════════════════════════════════

(defparameter *root-names*
  '("nimbus" "cassiopeia" "orion" "vega" "polaris"))

(defparameter *capabilities-pool*
  '(:perceive :reason :decide :reflect :plan :remember
    :critique :synthesize :explore :exploit :compress :evolve
    :diff :merge :fork :crystallize :delegate :verify))

(defparameter *thought-topics*
  '("light cone" "branching factor" "self model" "constraint"
    "objective" "heuristic" "observation" "hypothesis"
    "spectral class" "proper motion" "diff magnitude" "membrane"
    "stellar nursery" "lineage" "cognition" "reflection"
    "compression" "alignment" "ambiguity" "novelty"))

(defparameter *heuristics-pool*
  '("prefer high-confidence decisions"
    "minimize divergence from genome"
    "fork on novelty above threshold"
    "compress redundant thoughts after 10 steps"
    "promote stable capabilities to membrane"
    "discard heuristics with confidence below 0.2"
    "merge children with sibling on cosine > 0.9"
    "boost exploration when entropy is low"
    "crystallize after 3 successful applications"))

(defun random-thought ()
  (list :type :observation
        :content (list :topic (rng-choice *thought-topics*)
                       :weight (+ 0.1 (rng-float))
                       :tick (rng-int 1000))))

(defun random-heuristic ()
  (list :rule (rng-choice *heuristics-pool*)
        :confidence (+ 0.3 (* 0.7 (rng-float)))))

;;; ════════════════════════════════════════════════════════════════════
;;; Lineage moods — control variance
;;; ════════════════════════════════════════════════════════════════════
;;;
;;;   :linear    — wide tail, few children, calm cognition
;;;   :explorer  — high branching factor, heavy thought churn
;;;   :reflector — long-lived, accumulates heuristics + capabilities
;;;
;;; Each mood yields a different distribution of fork rate, thought
;;; bursts, and capability/heuristic growth — which is the only way the
;;; downstream spectral function can produce visible spread.

(defstruct mood
  name
  fork-prob
  thoughts-per-step-min
  thoughts-per-step-max
  cap-add-prob
  heur-add-prob)

(defparameter *moods*
  (list (make-mood :name :linear     :fork-prob 0.08
                   :thoughts-per-step-min 1 :thoughts-per-step-max 3
                   :cap-add-prob 0.05 :heur-add-prob 0.05)
        (make-mood :name :explorer   :fork-prob 0.45
                   :thoughts-per-step-min 2 :thoughts-per-step-max 7
                   :cap-add-prob 0.30 :heur-add-prob 0.10)
        (make-mood :name :reflector  :fork-prob 0.18
                   :thoughts-per-step-min 1 :thoughts-per-step-max 4
                   :cap-add-prob 0.15 :heur-add-prob 0.45)))

;;; ════════════════════════════════════════════════════════════════════
;;; Persistent-agent cognitive step
;;; ════════════════════════════════════════════════════════════════════

(defun grow-agent (agent mood)
  "Apply one mood-flavored 'tick' of cognition to AGENT.
   Returns a new persistent-agent (the original is untouched)."
  (let* ((thoughts (autopoiesis.agent:persistent-agent-thoughts agent))
         (capabilities (autopoiesis.agent:persistent-agent-capabilities agent))
         (heuristics (autopoiesis.agent:persistent-agent-heuristics agent))
         (n-thoughts (+ (mood-thoughts-per-step-min mood)
                        (rng-int (1+ (- (mood-thoughts-per-step-max mood)
                                        (mood-thoughts-per-step-min mood))))))
         (new-thoughts thoughts))
    (dotimes (_ n-thoughts)
      (setf new-thoughts
            (autopoiesis.core:pvec-push new-thoughts (random-thought))))
    (let ((new-caps
            (if (rng-chance (mood-cap-add-prob mood))
                (autopoiesis.core:pset-add capabilities
                                           (rng-choice *capabilities-pool*))
                capabilities))
          (new-heurs
            (if (rng-chance (mood-heur-add-prob mood))
                (cons (random-heuristic) heuristics)
                heuristics)))
      (autopoiesis.agent:copy-persistent-agent
       agent
       :thoughts new-thoughts
       :capabilities new-caps
       :heuristics new-heurs))))

;;; ════════════════════════════════════════════════════════════════════
;;; Snapshot helpers
;;; ════════════════════════════════════════════════════════════════════

(defun agent-to-snapshot-state (agent)
  "Snapshot payload — same shape used elsewhere in the codebase, just
   inlining the persistent-agent S-expression so diff/structural-hash work."
  (list :persistent-agent-snapshot
        :sexpr (autopoiesis.agent:persistent-agent-to-sexpr agent)))

(defun snap-and-save (agent parent-id metadata)
  (let ((snap (autopoiesis.snapshot:make-snapshot
               (agent-to-snapshot-state agent)
               :parent parent-id
               :metadata metadata)))
    (autopoiesis.snapshot:save-snapshot snap)
    snap))

;;; ════════════════════════════════════════════════════════════════════
;;; Lineage construction
;;; ════════════════════════════════════════════════════════════════════

(defun build-lineage (root-name mood remaining-budget)
  "Build one tree of snapshots rooted at a fresh persistent-agent. Returns
   the number of snapshots produced (so the caller can stop near N)."
  (when (<= remaining-budget 0)
    (return-from build-lineage 0))
  (let* ((root (autopoiesis.agent:make-persistent-agent
                :name root-name
                :capabilities (list :perceive :reason :decide)
                :heuristics (list (random-heuristic))
                :membrane (list (cons :origin root-name)
                                (cons :mood (mood-name mood)))))
         (root-snap (snap-and-save root nil
                                   (list :lineage root-name
                                         :mood (mood-name mood)
                                         :depth 0
                                         :root t)))
         (count 1)
         (work (list (cons root (autopoiesis.snapshot:snapshot-id root-snap)))))
    ;; BFS-ish growth so depth stays bounded but each lineage gets a real shape
    (loop while (and work (< count remaining-budget))
          do (let* ((pair (pop work))
                    (agent (car pair))
                    (parent-snap-id (cdr pair))
                    ;; 1 to 4 children per node, biased by mood. Always
                    ;; emit at least 1 child so the lineage keeps growing
                    ;; up to its budget — without this, calm "linear"
                    ;; moods exhaust the work list well before N.
                    (n-children
                      (cond
                        ((rng-chance (mood-fork-prob mood))
                         (1+ (rng-int 3)))   ; 1..3 — visible branching
                        (t 1))))             ; otherwise extend chain by 1
               (dotimes (_ n-children)
                 (when (>= count remaining-budget)
                   (return))
                 (multiple-value-bind (child _updated-parent)
                     (autopoiesis.agent:persistent-fork agent)
                   (declare (ignore _updated-parent))
                   ;; Apply 1..6 growth ticks before snapshotting — varies
                   ;; diff magnitude across edges, which is what the
                   ;; force-directed layout uses for spring rest-length.
                   (let* ((steps (1+ (rng-int 6)))
                          (grown child))
                     (dotimes (_ steps)
                       (setf grown (grow-agent grown mood)))
                     (let ((child-snap
                             (snap-and-save
                              grown
                              parent-snap-id
                              (list :lineage root-name
                                    :mood (mood-name mood)
                                    :ticks steps))))
                       (incf count)
                       ;; 85% chance the child continues the line. Higher
                       ;; than fork-prob — keeps depth meaningful so
                       ;; we don't end up with a flat hub-and-spoke.
                       (when (rng-chance 0.85)
                         (push (cons grown (autopoiesis.snapshot:snapshot-id child-snap))
                               work))))))))
    count))

;;; ════════════════════════════════════════════════════════════════════
;;; Public API
;;; ════════════════════════════════════════════════════════════════════

(defun wipe-directory (path)
  "Remove PATH and everything inside it if it exists, then recreate it."
  (let ((dir (uiop:ensure-directory-pathname path)))
    (when (uiop:directory-exists-p dir)
      (uiop:delete-directory-tree dir :validate t))
    (ensure-directories-exist dir)
    dir))

(defun populate (&key (path #P"/tmp/aether-seed/")
                      (n 60)
                      (seed 42)
                      (roots 4))
  "Populate a snapshot store at PATH with ~N persistent-agent snapshots
   spread across ROOTS root lineages, using SEED for the RNG.
   Returns the number of snapshots saved."
  (let ((dir (wipe-directory path)))
    (rng-reset seed)
    (autopoiesis.snapshot:initialize-store dir)
    (let* ((per-lineage-budget (max 5 (floor n roots)))
           (names (loop for i below roots
                        collect (format nil "~a-~a"
                                        (or (nth (mod i (length *root-names*))
                                                 *root-names*)
                                            "lineage")
                                        i)))
           (total 0))
      (loop for name in names
            for idx from 0
            ;; Rotate through moods deterministically so a single run
            ;; never ends up with 4 explorers (which would produce a
            ;; hairball) or 4 linears (which would produce 4 lines).
            for mood = (nth (mod idx (length *moods*)) *moods*)
            for built = (build-lineage name mood per-lineage-budget)
            do (incf total built))
      (autopoiesis.snapshot:save-store-index autopoiesis.snapshot:*snapshot-store*)
      (format t "~&aether-seed: wrote ~D snapshots into ~A (seed=~A, roots=~A)~%"
              total dir seed roots)
      total)))
