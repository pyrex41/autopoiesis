;;;; meshes.lisp - Mesh primitives for holodeck 3D visualization
;;;;
;;;; Defines CPU-side mesh data structures and factory functions for the
;;;; geometric primitives used to represent snapshot nodes and connections
;;;; in the 3D holodeck.  Mesh data is stored as vertex/normal/index arrays
;;;; ready for upload to a GPU when a rendering backend is available.
;;;;
;;;; Mesh types:
;;;;   :sphere         - Default snapshot node (smooth, approachable)
;;;;   :octahedron     - Decision nodes (sharp, angular, decisive)
;;;;   :branching-node - Fork/branch points (extends base with prongs)
;;;;
;;;; Each mesh type supports multiple LOD levels:
;;;;   LOD 0 (minimal)  - Very low poly for distant rendering
;;;;   LOD 1 (low)      - Reduced detail
;;;;   LOD 2 (medium)   - Standard detail
;;;;   LOD 3 (high)     - Full detail for close-up viewing
;;;;
;;;; Phase 8.2 - Rendering (mesh primitives)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Mesh Primitive Class
;;; ===================================================================

(defclass mesh-primitive ()
  ((name :initarg :name
         :accessor mesh-name
         :type keyword
         :documentation "Unique name identifying this mesh (e.g. :sphere, :octahedron).")
   (vertices :initarg :vertices
             :accessor mesh-vertices
             :initform #()
             :type (simple-array single-float (*))
             :documentation "Flat array of vertex positions: x0 y0 z0 x1 y1 z1 ...")
   (normals :initarg :normals
            :accessor mesh-normals
            :initform #()
            :type (simple-array single-float (*))
            :documentation "Flat array of vertex normals: nx0 ny0 nz0 nx1 ny1 nz1 ...")
   (indices :initarg :indices
            :accessor mesh-indices
            :initform #()
            :type (simple-array fixnum (*))
            :documentation "Flat array of triangle indices: i0 i1 i2 i3 i4 i5 ...")
   (lod :initarg :lod
        :accessor mesh-lod
        :initform 2
        :type fixnum
        :documentation "Level of detail for this mesh variant (0=minimal, 3=high).")
   (vertex-count :initarg :vertex-count
                 :accessor mesh-vertex-count
                 :initform 0
                 :type fixnum
                 :documentation "Number of vertices in the mesh.")
   (triangle-count :initarg :triangle-count
                   :accessor mesh-triangle-count
                   :initform 0
                   :type fixnum
                   :documentation "Number of triangles in the mesh."))
  (:documentation
   "CPU-side mesh data for a 3D primitive.
    Stores vertex positions, normals, and triangle indices in flat arrays
    suitable for direct upload to GPU vertex buffers.  Each mesh has a LOD
    level indicating its geometric complexity."))

(defmethod print-object ((mesh mesh-primitive) stream)
  (print-unreadable-object (mesh stream :type t)
    (format stream "~A LOD=~D verts=~D tris=~D"
            (mesh-name mesh)
            (mesh-lod mesh)
            (mesh-vertex-count mesh)
            (mesh-triangle-count mesh))))

;;; ===================================================================
;;; Mesh Registry
;;; ===================================================================

(defvar *mesh-registry* (make-hash-table :test 'equal)
  "Registry of mesh primitives keyed by (name . lod) pairs.")

(defun register-mesh (mesh)
  "Register MESH in the global mesh registry.
   Keyed by (name . lod) pair for LOD-based lookup."
  (setf (gethash (cons (mesh-name mesh) (mesh-lod mesh))
                 *mesh-registry*)
        mesh))

(defun find-mesh (name &optional (lod 2))
  "Look up mesh by NAME (keyword) and LOD level in the registry.
   Returns NIL if not found."
  (gethash (cons name lod) *mesh-registry*))

(defun list-meshes ()
  "Return a list of (name . lod) pairs for all registered meshes."
  (let (keys)
    (maphash (lambda (k v) (declare (ignore v)) (push k keys))
             *mesh-registry*)
    (sort keys (lambda (a b)
                 (if (eq (car a) (car b))
                     (< (cdr a) (cdr b))
                     (string< (symbol-name (car a))
                              (symbol-name (car b))))))))

(defun clear-mesh-registry ()
  "Remove all meshes from the registry."
  (clrhash *mesh-registry*))

;;; ===================================================================
;;; Helper: Normalize a 3D vector (as three values)
;;; ===================================================================

(defun normalize-xyz (x y z)
  "Normalize vector (X Y Z) to unit length.  Returns three values.
   Returns (0.0 1.0 0.0) for zero-length vectors."
  (let ((len (sqrt (+ (* x x) (* y y) (* z z)))))
    (if (< len 1.0e-7)
        (values 0.0 1.0 0.0)
        (values (/ x len) (/ y len) (/ z len)))))

;;; ===================================================================
;;; Sphere Mesh Generation
;;; ===================================================================

(defun make-sphere-mesh (&key (name :sphere) (lod 2) (radius 1.0))
  "Generate a UV-sphere mesh at the given LOD level.
   LOD controls the number of latitude/longitude segments:
     LOD 0: 4x4 (minimal), LOD 1: 8x8, LOD 2: 16x16, LOD 3: 32x32."
  (let* ((segments (case lod (0 4) (1 8) (2 16) (3 32) (otherwise 16)))
         (rings segments)
         (r (coerce radius 'single-float))
         (vert-count (* (1+ rings) (1+ segments)))
         (tri-count (* rings segments 2))
         (vertices (make-array (* vert-count 3)
                               :element-type 'single-float
                               :initial-element 0.0))
         (normals (make-array (* vert-count 3)
                              :element-type 'single-float
                              :initial-element 0.0))
         (indices (make-array (* tri-count 3)
                              :element-type 'fixnum
                              :initial-element 0))
         (vi 0)   ; vertex array index
         (ii 0))  ; index array index
    ;; Generate vertices
    (dotimes (ring (1+ rings))
      (let* ((phi (* pi (/ (float ring) (float rings))))
             (sp (sin phi))
             (cp (cos phi)))
        (dotimes (seg (1+ segments))
          (let* ((theta (* 2.0 pi (/ (float seg) (float segments))))
                 (st (sin theta))
                 (ct (cos theta))
                 (nx (coerce (* sp ct) 'single-float))
                 (ny (coerce cp 'single-float))
                 (nz (coerce (* sp st) 'single-float)))
            (setf (aref vertices vi) (* nx r))
            (setf (aref normals vi) nx)
            (incf vi)
            (setf (aref vertices vi) (* ny r))
            (setf (aref normals vi) ny)
            (incf vi)
            (setf (aref vertices vi) (* nz r))
            (setf (aref normals vi) nz)
            (incf vi)))))
    ;; Generate indices
    (dotimes (ring rings)
      (dotimes (seg segments)
        (let ((curr (+ (* ring (1+ segments)) seg))
              (next (+ (* (1+ ring) (1+ segments)) seg)))
          ;; First triangle
          (setf (aref indices ii) curr) (incf ii)
          (setf (aref indices ii) next) (incf ii)
          (setf (aref indices ii) (1+ next)) (incf ii)
          ;; Second triangle
          (setf (aref indices ii) curr) (incf ii)
          (setf (aref indices ii) (1+ next)) (incf ii)
          (setf (aref indices ii) (1+ curr)) (incf ii))))
    ;; Create mesh
    (make-instance 'mesh-primitive
                   :name name
                   :lod lod
                   :vertices vertices
                   :normals normals
                   :indices indices
                   :vertex-count vert-count
                   :triangle-count tri-count)))

;;; ===================================================================
;;; Octahedron Mesh Generation
;;; ===================================================================

(defun make-octahedron-mesh (&key (name :octahedron) (lod 2) (radius 1.0))
  "Generate an octahedron mesh at the given LOD level.
   The octahedron has 6 vertices and 8 triangular faces at LOD 0.
   Higher LODs subdivide the faces for smoother rendering:
     LOD 0: 8 tris, LOD 1: 32 tris, LOD 2: 128 tris, LOD 3: 512 tris."
  (let* ((subdivisions (case lod (0 0) (1 1) (2 2) (3 3) (otherwise 2)))
         (r (coerce radius 'single-float)))
    ;; Start with the 6 base octahedron vertices
    (let ((base-verts (list (list 0.0  r    0.0)     ; top
                            (list r    0.0  0.0)     ; +x
                            (list 0.0  0.0  r)       ; +z
                            (list (- r) 0.0 0.0)     ; -x
                            (list 0.0  0.0  (- r))   ; -z
                            (list 0.0  (- r) 0.0)))  ; bottom
          ;; 8 faces as vertex index triples
          (base-faces (list '(0 1 2)   ; top-front-right
                            '(0 2 3)   ; top-front-left
                            '(0 3 4)   ; top-back-left
                            '(0 4 1)   ; top-back-right
                            '(5 2 1)   ; bottom-front-right
                            '(5 3 2)   ; bottom-front-left
                            '(5 4 3)   ; bottom-back-left
                            '(5 1 4))));bottom-back-right
      ;; Subdivide faces
      (let ((verts (copy-list base-verts))
            (faces (copy-list base-faces)))
        (dotimes (sub subdivisions)
          (let ((new-faces nil)
                (edge-midpoints (make-hash-table :test 'equal)))
            ;; For each face, subdivide into 4 smaller triangles
            (dolist (face faces)
              (let* ((i0 (first face))
                     (i1 (second face))
                     (i2 (third face))
                     ;; Get or create midpoint vertices
                     (m01 (get-or-create-midpoint i0 i1 verts r edge-midpoints))
                     (m12 (get-or-create-midpoint i1 i2 verts r edge-midpoints))
                     (m20 (get-or-create-midpoint i2 i0 verts r edge-midpoints)))
                ;; Replace face with 4 sub-faces
                (push (list i0 m01 m20) new-faces)
                (push (list m01 i1 m12) new-faces)
                (push (list m20 m12 i2) new-faces)
                (push (list m01 m12 m20) new-faces)))
            (setf faces (nreverse new-faces))))
        ;; Pack into arrays
        (let* ((vert-count (length verts))
               (tri-count (length faces))
               (vertices (make-array (* vert-count 3)
                                     :element-type 'single-float
                                     :initial-element 0.0))
               (normals (make-array (* vert-count 3)
                                    :element-type 'single-float
                                    :initial-element 0.0))
               (indices (make-array (* tri-count 3)
                                    :element-type 'fixnum
                                    :initial-element 0)))
          ;; Fill vertex and normal arrays
          (loop for v in verts
                for i from 0
                do (let ((vi (* i 3))
                         (x (coerce (first v) 'single-float))
                         (y (coerce (second v) 'single-float))
                         (z (coerce (third v) 'single-float)))
                     (setf (aref vertices vi) x)
                     (setf (aref vertices (+ vi 1)) y)
                     (setf (aref vertices (+ vi 2)) z)
                     ;; For an octahedron, normals point outward from center
                     (multiple-value-bind (nx ny nz) (normalize-xyz x y z)
                       (setf (aref normals vi) nx)
                       (setf (aref normals (+ vi 1)) ny)
                       (setf (aref normals (+ vi 2)) nz))))
          ;; Fill index array
          (loop for face in faces
                for i from 0
                do (let ((ii (* i 3)))
                     (setf (aref indices ii) (first face))
                     (setf (aref indices (+ ii 1)) (second face))
                     (setf (aref indices (+ ii 2)) (third face))))
          ;; Create mesh
          (make-instance 'mesh-primitive
                         :name name
                         :lod lod
                         :vertices vertices
                         :normals normals
                         :indices indices
                         :vertex-count vert-count
                         :triangle-count tri-count))))))

(defun get-or-create-midpoint (i0 i1 verts radius edge-midpoints)
  "Get or create the midpoint vertex between vertices I0 and I1.
   Projects the midpoint onto a sphere of RADIUS.
   Uses EDGE-MIDPOINTS hash table for deduplication."
  (let ((key (if (< i0 i1) (cons i0 i1) (cons i1 i0))))
    (or (gethash key edge-midpoints)
        (let* ((v0 (nth i0 verts))
               (v1 (nth i1 verts))
               (mx (/ (+ (first v0) (first v1)) 2.0))
               (my (/ (+ (second v0) (second v1)) 2.0))
               (mz (/ (+ (third v0) (third v1)) 2.0)))
          ;; Project onto sphere of given radius
          (multiple-value-bind (nx ny nz) (normalize-xyz mx my mz)
            (let ((new-idx (length verts)))
              (nconc verts (list (list (* nx (coerce radius 'single-float))
                                      (* ny (coerce radius 'single-float))
                                      (* nz (coerce radius 'single-float)))))
              (setf (gethash key edge-midpoints) new-idx)
              new-idx))))))

;;; ===================================================================
;;; Branching Node Mesh Generation
;;; ===================================================================

(defun make-branching-node-mesh (&key (name :branching-node) (lod 2) (radius 1.0))
  "Generate a branching-node mesh for fork/branch visualization.
   A branching node is a central sphere with three prongs extending outward
   at 120-degree intervals in the XZ plane, representing diverging paths.
   LOD controls the detail of both the central body and prongs."
  (let* ((r (coerce radius 'single-float))
         (prong-length (* r 0.8))
         (prong-radius (* r 0.2))
         (prong-segments (case lod (0 3) (1 4) (2 6) (3 8) (otherwise 6)))
         ;; Central body is a low-detail sphere
         (body-segments (case lod (0 4) (1 6) (2 8) (3 12) (otherwise 8)))
         (body-rings body-segments))
    ;; Build the mesh by combining a central sphere with 3 cylindrical prongs
    (let ((all-verts nil)
          (all-normals nil)
          (all-indices nil)
          (vertex-offset 0))
      ;; 1. Central sphere body
      (multiple-value-bind (bv bn bi-list bc)
          (generate-sphere-data body-rings body-segments (* r 0.6))
        (setf all-verts (append all-verts bv))
        (setf all-normals (append all-normals bn))
        (setf all-indices (append all-indices bi-list))
        (setf vertex-offset bc))
      ;; 2. Three prongs at 120-degree intervals
      (dotimes (prong-idx 3)
        (let* ((angle (* prong-idx (/ (* 2.0 pi) 3.0)))
               (dir-x (coerce (cos angle) 'single-float))
               (dir-z (coerce (sin angle) 'single-float))
               ;; Prong base is at the surface of the central sphere
               (base-x (* dir-x r 0.5))
               (base-z (* dir-z r 0.5))
               ;; Prong tip extends outward
               (tip-x (* dir-x (+ (* r 0.5) prong-length)))
               (tip-z (* dir-z (+ (* r 0.5) prong-length))))
          (multiple-value-bind (pv pn pi-list pc)
              (generate-prong-data base-x 0.0 base-z
                                   tip-x 0.0 tip-z
                                   prong-radius prong-segments
                                   vertex-offset)
            (setf all-verts (append all-verts pv))
            (setf all-normals (append all-normals pn))
            (setf all-indices (append all-indices pi-list))
            (incf vertex-offset pc))))
      ;; Pack into arrays
      (let* ((vert-count (/ (length all-verts) 3))
             (tri-count (/ (length all-indices) 3))
             (vertices (make-array (length all-verts)
                                   :element-type 'single-float
                                   :initial-element 0.0))
             (normals (make-array (length all-normals)
                                  :element-type 'single-float
                                  :initial-element 0.0))
             (indices (make-array (length all-indices)
                                  :element-type 'fixnum
                                  :initial-element 0)))
        (loop for v in all-verts for i from 0
              do (setf (aref vertices i) (coerce v 'single-float)))
        (loop for n in all-normals for i from 0
              do (setf (aref normals i) (coerce n 'single-float)))
        (loop for idx in all-indices for i from 0
              do (setf (aref indices i) idx))
        (make-instance 'mesh-primitive
                       :name name
                       :lod lod
                       :vertices vertices
                       :normals normals
                       :indices indices
                       :vertex-count vert-count
                       :triangle-count tri-count)))))

;;; ===================================================================
;;; Helper: Generate sphere vertex data as lists
;;; ===================================================================

(defun generate-sphere-data (rings segments radius)
  "Generate sphere vertex/normal/index data as flat lists.
   Returns four values: vertices normals indices vertex-count."
  (let ((verts nil)
        (norms nil)
        (idxs nil)
        (r (coerce radius 'single-float)))
    ;; Generate vertices
    (dotimes (ring (1+ rings))
      (let* ((phi (* pi (/ (float ring) (float rings))))
             (sp (sin phi))
             (cp (cos phi)))
        (dotimes (seg (1+ segments))
          (let* ((theta (* 2.0 pi (/ (float seg) (float segments))))
                 (st (sin theta))
                 (ct (cos theta))
                 (nx (coerce (* sp ct) 'single-float))
                 (ny (coerce cp 'single-float))
                 (nz (coerce (* sp st) 'single-float)))
            (push (* nx r) verts)
            (push (* ny r) verts)
            (push (* nz r) verts)
            (push nx norms)
            (push ny norms)
            (push nz norms)))))
    ;; Generate indices
    (dotimes (ring rings)
      (dotimes (seg segments)
        (let ((curr (+ (* ring (1+ segments)) seg))
              (next (+ (* (1+ ring) (1+ segments)) seg)))
          (push curr idxs)
          (push next idxs)
          (push (1+ next) idxs)
          (push curr idxs)
          (push (1+ next) idxs)
          (push (1+ curr) idxs))))
    (values (nreverse verts)
            (nreverse norms)
            (nreverse idxs)
            (* (1+ rings) (1+ segments)))))

;;; ===================================================================
;;; Helper: Generate cylindrical prong data
;;; ===================================================================

(defun generate-prong-data (bx by bz tx ty tz prong-radius segments vertex-offset)
  "Generate a cylindrical prong from base (BX BY BZ) to tip (TX TY TZ).
   PRONG-RADIUS is the cylinder radius.  SEGMENTS is the number of facets.
   VERTEX-OFFSET is added to all indices for combining with other geometry.
   Returns four values: vertices normals indices vertex-count."
  (let ((verts nil)
        (norms nil)
        (idxs nil)
        (pr (coerce prong-radius 'single-float)))
    ;; Compute orthonormal basis perpendicular to prong axis
    (multiple-value-bind (ax ay az) (normalize-xyz (- tx bx) (- ty by) (- tz bz))
      ;; Choose up vector not parallel to axis
      (let* ((up-x (if (> (abs ay) 0.99) 1.0 0.0))
             (up-y (if (> (abs ay) 0.99) 0.0 1.0))
             (up-z 0.0))
        ;; right = normalize(axis x up)
        (multiple-value-bind (rrx rry rrz)
            (normalize-xyz (- (* ay up-z) (* az up-y))
                           (- (* az up-x) (* ax up-z))
                           (- (* ax up-y) (* ay up-x)))
          ;; up2 = normalize(right x axis)
          (multiple-value-bind (uux uuy uuz)
              (normalize-xyz (- (* rry az) (* rrz ay))
                             (- (* rrz ax) (* rrx az))
                             (- (* rrx ay) (* rry ax)))
            ;; Generate ring vertices at base and tip
            (dotimes (seg-i (1+ segments))
              (let* ((angle (* 2.0 pi (/ (float seg-i) (float segments))))
                     (ca (cos angle))
                     (sa (sin angle))
                     (nx (coerce (+ (* rrx ca) (* uux sa)) 'single-float))
                     (ny (coerce (+ (* rry ca) (* uuy sa)) 'single-float))
                     (nz (coerce (+ (* rrz ca) (* uuz sa)) 'single-float)))
                ;; Base ring vertex
                (push (coerce (+ bx (* nx pr)) 'single-float) verts)
                (push (coerce (+ by (* ny pr)) 'single-float) verts)
                (push (coerce (+ bz (* nz pr)) 'single-float) verts)
                (push nx norms) (push ny norms) (push nz norms)
                ;; Tip ring vertex (tapered)
                (let ((taper 0.3))
                  (push (coerce (+ tx (* nx pr taper)) 'single-float) verts)
                  (push (coerce (+ ty (* ny pr taper)) 'single-float) verts)
                  (push (coerce (+ tz (* nz pr taper)) 'single-float) verts)
                  (push nx norms) (push ny norms) (push nz norms))) ;; close taper-let, let*, dotimes
            ;; Generate indices for the cylinder wall
            (dotimes (seg-i segments)
              (let ((b0 (+ vertex-offset (* seg-i 2)))
                    (t0 (+ vertex-offset (* seg-i 2) 1))
                    (b1 (+ vertex-offset (* (1+ seg-i) 2)))
                    (t1 (+ vertex-offset (* (1+ seg-i) 2) 1)))
                (push b0 idxs) (push t0 idxs) (push t1 idxs)
                (push b0 idxs) (push t1 idxs) (push b1 idxs)))))))  ;; let,dotimes,uux-mvb,rrx-mvb,let*,ax-mvb
    (values (nreverse verts)
            (nreverse norms)
            (nreverse idxs)
            (* 2 (1+ segments))))))  ;; values,let,defun


;;; ===================================================================
;;; Mesh Factory Function
;;; ===================================================================

(defun make-mesh-for-type (mesh-type &key (lod 2) (radius 1.0))
  "Create a mesh primitive for the given MESH-TYPE keyword.
   Supported types: :sphere, :octahedron, :branching-node.
   LOD controls geometric detail (0=minimal, 3=high).
   RADIUS scales the mesh."
  (ecase mesh-type
    (:sphere (make-sphere-mesh :lod lod :radius radius))
    (:octahedron (make-octahedron-mesh :lod lod :radius radius))
    (:branching-node (make-branching-node-mesh :lod lod :radius radius))))

;;; ===================================================================
;;; LOD Mesh ID Mapping
;;; ===================================================================

(defun lod-mesh-id (mesh-type lod-level)
  "Return the mesh registry key for MESH-TYPE at LOD-LEVEL.
   Used by the LOD system to select appropriate mesh detail."
  (cons mesh-type lod-level))

;;; ===================================================================
;;; Standard Mesh Registration
;;; ===================================================================

(defun register-holodeck-meshes ()
  "Register all standard holodeck mesh primitives at all LOD levels.
   Returns a list of registered (name . lod) pairs."
  (clear-mesh-registry)
  (dolist (mesh-type '(:sphere :octahedron :branching-node))
    (dotimes (lod 4)
      (register-mesh (make-mesh-for-type mesh-type :lod lod))))
  (list-meshes))
