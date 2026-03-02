;;;; genome.lisp - Genome representation for evolutionary agents
;;;;
;;;; A genome encodes the heritable traits of an agent: capabilities,
;;;; heuristic weights, and tunable parameters. Genomes form lineages
;;;; through crossover and mutation operators.

(in-package #:autopoiesis.swarm)

;;; ===================================================================
;;; Genome Class
;;; ===================================================================

(defclass genome ()
  ((id :initarg :id
       :accessor genome-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique identifier for this genome")
   (capabilities :initarg :capabilities
                 :accessor genome-capabilities
                 :initform nil
                 :documentation "List of capability name keywords")
   (heuristic-weights :initarg :heuristic-weights
                      :accessor genome-heuristic-weights
                      :initform nil
                      :documentation "Alist of (heuristic-id . weight)")
   (parameters :initarg :parameters
               :accessor genome-parameters
               :initform nil
               :documentation "Plist of tunable parameters")
   (lineage :initarg :lineage
            :accessor genome-lineage
            :initform nil
            :documentation "List of parent genome IDs")
   (fitness :initarg :fitness
            :accessor genome-fitness
            :initform 0.0
            :documentation "Current fitness score")
   (generation :initarg :generation
               :accessor genome-generation
               :initform 0
               :documentation "Generation number"))
  (:documentation "Heritable trait encoding for an evolutionary agent."))

(defun make-genome (&key capabilities heuristic-weights parameters lineage (generation 0))
  "Create a new genome with the given traits."
  (make-instance 'genome
                 :capabilities capabilities
                 :heuristic-weights heuristic-weights
                 :parameters parameters
                 :lineage lineage
                 :generation generation))

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defun genome-to-sexpr (genome)
  "Convert GENOME to a pure S-expression representation."
  `(:genome
    :id ,(genome-id genome)
    :capabilities ,(genome-capabilities genome)
    :heuristic-weights ,(genome-heuristic-weights genome)
    :parameters ,(genome-parameters genome)
    :lineage ,(genome-lineage genome)
    :fitness ,(genome-fitness genome)
    :generation ,(genome-generation genome)))

(defun sexpr-to-genome (sexpr)
  "Reconstruct a GENOME from its S-expression representation."
  (when (and (listp sexpr) (eq (first sexpr) :genome))
    (let ((plist (rest sexpr)))
      (let ((genome (make-instance 'genome
                                   :capabilities (getf plist :capabilities)
                                   :heuristic-weights (getf plist :heuristic-weights)
                                   :parameters (getf plist :parameters)
                                   :lineage (getf plist :lineage)
                                   :fitness (or (getf plist :fitness) 0.0)
                                   :generation (or (getf plist :generation) 0))))
        (when (getf plist :id)
          (setf (slot-value genome 'id) (getf plist :id)))
        genome))))

;;; ===================================================================
;;; Agent Instantiation
;;; ===================================================================

(defun instantiate-agent-from-genome (genome)
  "Create an agent from GENOME, applying its capabilities."
  (autopoiesis.agent:make-agent
   :name (format nil "genome-~A" (genome-id genome))
   :capabilities (genome-capabilities genome)))
