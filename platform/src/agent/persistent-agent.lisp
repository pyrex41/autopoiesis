;;;; persistent-agent.lisp - Immutable persistent agent struct
;;;;
;;;; Defines a defstruct-based agent where all state is stored in persistent
;;;; data structures (pmap, pvec, pset). Every mutation returns a new struct;
;;;; the original is never modified.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Agent Struct
;;; ═══════════════════════════════════════════════════════════════════

(defstruct (persistent-agent (:constructor %make-persistent-agent)
                             (:copier nil))
  "An immutable agent whose state is entirely persistent data structures.
   Every slot update produces a new struct via COPY-PERSISTENT-AGENT."
  (id          (make-uuid)        :type string   :read-only t)
  (name        "unnamed"          :type string)
  (version     0                  :type integer)
  (timestamp   (get-precise-time) :type number)
  (membrane    (pmap-empty))
  (genome      nil                :type list)
  (thoughts    (pvec-empty))
  (capabilities (pset-empty))
  (heuristics  nil                :type list)
  (children    nil                :type list)
  (parent-root nil)
  (metadata    (pmap-empty)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Constructor
;;; ═══════════════════════════════════════════════════════════════════

(defun make-persistent-agent (&key name capabilities genome heuristics
                                   membrane metadata)
  "Create a new persistent agent with version 0 and a fresh UUID.
   CAPABILITIES may be a list (converted to pset) or a pset.
   MEMBRANE and METADATA may be alists (converted to pmap) or pmaps."
  (%make-persistent-agent
   :id          (make-uuid)
   :name        (or name "unnamed")
   :version     0
   :timestamp   (get-precise-time)
   :membrane    (cond ((null membrane)  (pmap-empty))
                      ((listp membrane) (alist-to-pmap membrane))
                      (t                membrane))
   :genome      (or genome nil)
   :thoughts    (pvec-empty)
   :capabilities (cond ((null capabilities) (pset-empty))
                       ((listp capabilities) (list-to-pset capabilities))
                       (t                    capabilities))
   :heuristics  (or heuristics nil)
   :children    nil
   :parent-root nil
   :metadata    (cond ((null metadata)  (pmap-empty))
                      ((listp metadata) (alist-to-pmap metadata))
                      (t                metadata))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-agent-to-sexpr (agent)
  "Serialize AGENT to a pure S-expression plist.
   Persistent maps become alists, vectors become lists, sets become lists."
  (list :persistent-agent
        :id           (persistent-agent-id agent)
        :name         (persistent-agent-name agent)
        :version      (persistent-agent-version agent)
        :timestamp    (persistent-agent-timestamp agent)
        :membrane     (pmap-to-alist (persistent-agent-membrane agent))
        :genome       (persistent-agent-genome agent)
        :thoughts     (pvec-to-list (persistent-agent-thoughts agent))
        :capabilities (pset-to-list (persistent-agent-capabilities agent))
        :heuristics   (persistent-agent-heuristics agent)
        :children     (persistent-agent-children agent)
        :parent-root  (persistent-agent-parent-root agent)
        :metadata     (pmap-to-alist (persistent-agent-metadata agent))))

(defun sexpr-to-persistent-agent (sexpr)
  "Deserialize a persistent agent from its S-expression plist representation.
   Alists are converted to pmaps, lists to pvecs/psets as appropriate."
  (let ((plist (if (eq (first sexpr) :persistent-agent)
                   (rest sexpr)
                   sexpr)))
    (%make-persistent-agent
     :id           (or (getf plist :id) (make-uuid))
     :name         (or (getf plist :name) "unnamed")
     :version      (or (getf plist :version) 0)
     :timestamp    (or (getf plist :timestamp) (get-precise-time))
     :membrane     (let ((m (getf plist :membrane)))
                     (if (listp m) (alist-to-pmap m) (or m (pmap-empty))))
     :genome       (getf plist :genome)
     :thoughts     (let ((t* (getf plist :thoughts)))
                     (if (listp t*) (list-to-pvec t*) (or t* (pvec-empty))))
     :capabilities (let ((c (getf plist :capabilities)))
                     (if (listp c) (list-to-pset c) (or c (pset-empty))))
     :heuristics   (getf plist :heuristics)
     :children     (getf plist :children)
     :parent-root  (getf plist :parent-root)
     :metadata     (let ((m (getf plist :metadata)))
                     (if (listp m) (alist-to-pmap m) (or m (pmap-empty)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Hashing
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-agent-hash (agent)
  "Return a content-addressable hash of AGENT's full state."
  (sexpr-hash (persistent-agent-to-sexpr agent)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Functional Copy
;;; ═══════════════════════════════════════════════════════════════════

(defun copy-persistent-agent (agent &key (name nil name-p)
                                         (version nil version-p)
                                         (membrane nil membrane-p)
                                         (genome nil genome-p)
                                         (thoughts nil thoughts-p)
                                         (capabilities nil capabilities-p)
                                         (heuristics nil heuristics-p)
                                         (children nil children-p)
                                         (parent-root nil parent-root-p)
                                         (metadata nil metadata-p))
  "Return a new persistent-agent with specified slots updated, others copied.
   Automatically increments version and updates timestamp."
  (%make-persistent-agent
   :id           (persistent-agent-id agent)
   :name         (if name-p name (persistent-agent-name agent))
   :version      (if version-p version (1+ (persistent-agent-version agent)))
   :timestamp    (get-precise-time)
   :membrane     (if membrane-p membrane (persistent-agent-membrane agent))
   :genome       (if genome-p genome (persistent-agent-genome agent))
   :thoughts     (if thoughts-p thoughts (persistent-agent-thoughts agent))
   :capabilities (if capabilities-p capabilities (persistent-agent-capabilities agent))
   :heuristics   (if heuristics-p heuristics (persistent-agent-heuristics agent))
   :children     (if children-p children (persistent-agent-children agent))
   :parent-root  (if parent-root-p parent-root (persistent-agent-parent-root agent))
   :metadata     (if metadata-p metadata (persistent-agent-metadata agent))))
