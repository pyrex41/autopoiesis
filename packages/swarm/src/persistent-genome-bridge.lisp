;;;; persistent-genome-bridge.lisp - Bridge persistent agents to swarm genomes
;;;;
;;;; Converts between persistent-agent structs and the swarm genome class,
;;;; enabling persistent agents to participate in evolutionary runs.

(in-package #:autopoiesis.swarm)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Agent → Genome
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-agent-to-genome (agent)
  "Convert a persistent-agent struct to a swarm genome.
   Maps capabilities (pset → list), heuristics → heuristic-weights,
   and metadata → parameters."
  (make-genome
   :capabilities (autopoiesis.core:pset-to-list
                  (autopoiesis.agent:persistent-agent-capabilities agent))
   :heuristic-weights (mapcar (lambda (h)
                                (cons (or (getf h :id) (getf h :name) "unknown")
                                      (or (getf h :confidence) 1.0)))
                              (autopoiesis.agent:persistent-agent-heuristics agent))
   :parameters (autopoiesis.core:pmap-to-alist
                (autopoiesis.agent:persistent-agent-metadata agent))
   :lineage (when (autopoiesis.agent:persistent-agent-parent-root agent)
              (list (autopoiesis.agent:persistent-agent-parent-root agent)))
   :generation (autopoiesis.agent:persistent-agent-version agent)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Genome → Persistent Agent Patch
;;; ═══════════════════════════════════════════════════════════════════

(defun genome-to-persistent-agent-patch (genome original)
  "Apply an evolved genome's traits back to the original persistent-agent.
   Returns a new persistent-agent with updated capabilities, heuristics,
   and metadata from the genome. Preserves thoughts, membrane, etc."
  (autopoiesis.agent:copy-persistent-agent
   original
   :capabilities (autopoiesis.core:list-to-pset (genome-capabilities genome))
   :heuristics (mapcar (lambda (pair)
                         (list :id (car pair)
                               :confidence (cdr pair)))
                       (genome-heuristic-weights genome))
   :metadata (autopoiesis.core:alist-to-pmap (genome-parameters genome))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Round-Trip Verification
;;; ═══════════════════════════════════════════════════════════════════

(defun pa-genome-round-trip-p (agent)
  "Test that converting a persistent-agent to genome and back preserves
   capabilities and heuristic structure. Returns T if round-trip is faithful."
  (let* ((genome (persistent-agent-to-genome agent))
         (patched (genome-to-persistent-agent-patch genome agent)))
    (and (autopoiesis.core:pset-equal
          (autopoiesis.agent:persistent-agent-capabilities agent)
          (autopoiesis.agent:persistent-agent-capabilities patched))
         (= (length (autopoiesis.agent:persistent-agent-heuristics agent))
            (length (autopoiesis.agent:persistent-agent-heuristics patched))))))
