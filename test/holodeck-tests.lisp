;;;; holodeck-tests.lisp - Tests for holodeck ECS subsystem
;;;;
;;;; Tests component definitions, entity creation helpers, and ECS systems.

(defpackage #:autopoiesis.holodeck.test
  (:use #:cl #:fiveam #:autopoiesis.holodeck)
  (:export #:run-holodeck-tests #:holodeck-tests))

(in-package #:autopoiesis.holodeck.test)

(def-suite holodeck-tests
  :description "Tests for the 3D holodeck ECS subsystem")

(defun run-holodeck-tests ()
  "Run all holodeck tests and return success status."
  (let ((results (run 'holodeck-tests)))
    (explain! results)
    (results-status results)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Component Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite component-tests
  :in holodeck-tests
  :description "Tests for ECS component definitions")

(in-suite component-tests)

(test position3d-component
  "Test position3d component creation and access."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 1.0 :y 2.0 :z 3.0)
    (is (= 1.0 (position3d-x e)))
    (is (= 2.0 (position3d-y e)))
    (is (= 3.0 (position3d-z e)))))

(test position3d-defaults
  "Test position3d defaults to origin."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e)
    (is (= 0.0 (position3d-x e)))
    (is (= 0.0 (position3d-y e)))
    (is (= 0.0 (position3d-z e)))))

(test velocity3d-component
  "Test velocity3d component creation and access."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-velocity3d e :dx 0.5 :dy -0.3 :dz 1.0)
    (is (= 0.5 (velocity3d-dx e)))
    (is (= -0.3 (velocity3d-dy e)))
    (is (= 1.0 (velocity3d-dz e)))))

(test scale3d-component
  "Test scale3d component defaults to unit scale."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-scale3d e)
    (is (= 1.0 (scale3d-sx e)))
    (is (= 1.0 (scale3d-sy e)))
    (is (= 1.0 (scale3d-sz e)))))

(test rotation3d-component
  "Test rotation3d component defaults to zero rotation."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-rotation3d e)
    (is (= 0.0 (rotation3d-rx e)))
    (is (= 0.0 (rotation3d-ry e)))
    (is (= 0.0 (rotation3d-rz e)))))

(test visual-style-component
  "Test visual-style component with custom values."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-visual-style e
                       :node-type :decision
                       :color-r 1.0 :color-g 0.8 :color-b 0.2 :color-a 0.9
                       :glow-intensity 2.0
                       :pulse-rate 3.14)
    (is (eq :decision (visual-style-node-type e)))
    (is (= 1.0 (visual-style-color-r e)))
    (is (= 0.8 (visual-style-color-g e)))
    (is (= 0.2 (visual-style-color-b e)))
    (is (= 0.9 (visual-style-color-a e)))
    (is (= 2.0 (visual-style-glow-intensity e)))
    (is (= 3.14 (visual-style-pulse-rate e)))))

(test node-label-component
  "Test node-label component."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-node-label e :text "snap-001" :visible-p t :offset-y 2.0)
    (is (string= "snap-001" (node-label-text e)))
    (is (eq t (node-label-visible-p e)))
    (is (= 2.0 (node-label-offset-y e)))))

(test snapshot-binding-component
  "Test snapshot-binding component."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-snapshot-binding e :snapshot-id "abc123" :snapshot-type :decision)
    (is (string= "abc123" (snapshot-binding-snapshot-id e)))
    (is (eq :decision (snapshot-binding-snapshot-type e)))))

(test agent-binding-component
  "Test agent-binding component."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-agent-binding e :agent-id "agent-1" :agent-name "Explorer")
    (is (string= "agent-1" (agent-binding-agent-id e)))
    (is (string= "Explorer" (agent-binding-agent-name e)))))

(test connection-component
  "Test connection component."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-connection e :from-entity 0 :to-entity 1 :kind :branch)
    (is (= 0 (connection-from-entity e)))
    (is (= 1 (connection-to-entity e)))
    (is (eq :branch (connection-kind e)))))

(test interactive-component
  "Test interactive component defaults."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-interactive e)
    (is (eq nil (interactive-hover-p e)))
    (is (eq nil (interactive-selected-p e)))))

(test detail-level-component
  "Test detail-level component."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-detail-level e :current :high :low-distance 50.0 :cull-distance 150.0)
    (is (eq :high (detail-level-current e)))
    (is (= 50.0 (detail-level-low-distance e)))
    (is (= 150.0 (detail-level-cull-distance e)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Entity Helper Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite entity-helper-tests
  :in holodeck-tests
  :description "Tests for entity creation helper functions")

(in-suite entity-helper-tests)

(test make-snapshot-entity-creates-all-components
  "Test that make-snapshot-entity creates entity with full component set."
  (init-holodeck-storage)
  (let ((e (make-snapshot-entity "snap-001" :decision :x 5.0 :y 10.0 :z 2.0)))
    ;; Position
    (is (= 5.0 (position3d-x e)))
    (is (= 10.0 (position3d-y e)))
    (is (= 2.0 (position3d-z e)))
    ;; Scale defaults to 1.0
    (is (= 1.0 (scale3d-sx e)))
    ;; Snapshot binding
    (is (string= "snap-001" (snapshot-binding-snapshot-id e)))
    (is (eq :decision (snapshot-binding-snapshot-type e)))
    ;; Visual style matches decision color
    (is (eq :decision (visual-style-node-type e)))
    (is (= 1.0 (visual-style-color-r e)))  ; gold = (1.0 0.8 0.2 0.9)
    (is (= 0.8 (visual-style-color-g e)))
    ;; Label
    (is (string= "snap-001" (node-label-text e)))
    ;; Interactive defaults
    (is (eq nil (interactive-hover-p e)))
    ;; Detail level defaults
    (is (eq :high (detail-level-current e)))))

(test make-connection-entity-links-entities
  "Test that make-connection-entity creates connection with visual."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "s1" :snapshot))
         (e2 (make-snapshot-entity "s2" :snapshot))
         (conn (make-connection-entity e1 e2 :kind :branch)))
    (is (= e1 (connection-from-entity conn)))
    (is (= e2 (connection-to-entity conn)))
    (is (eq :branch (connection-kind conn)))
    ;; Connection has position and visual
    (is (= 0.0 (position3d-x conn)))
    (is (eq :connection (visual-style-node-type conn)))))

(test snapshot-type-colors
  "Test that different snapshot types map to different colors."
  (multiple-value-bind (r1 g1 b1 a1) (snapshot-type-to-color :genesis)
    (declare (ignore a1))
    (multiple-value-bind (r2 g2 b2 a2) (snapshot-type-to-color :decision)
      (declare (ignore a2))
      ;; Genesis is green, decision is gold - they should differ
      (is (not (and (= r1 r2) (= g1 g2) (= b1 b2)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; System Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite system-tests
  :in holodeck-tests
  :description "Tests for ECS systems")

(in-suite system-tests)

(test movement-system-updates-position
  "Test that movement system applies velocity to position."
  (init-holodeck-storage)
  (let ((*delta-time* 1.0)
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 0.0 :y 0.0 :z 0.0)
    (make-velocity3d e :dx 2.0 :dy 3.0 :dz -1.0)
    ;; Need scale3d and visual-style for run-systems not to error
    ;; on other systems that may iterate
    (make-scale3d e)
    (make-visual-style e)
    (make-detail-level e)
    (cl-fast-ecs:run-systems)
    (is (= 2.0 (position3d-x e)))
    (is (= 3.0 (position3d-y e)))
    (is (= -1.0 (position3d-z e)))))

(test movement-system-respects-delta-time
  "Test that movement scales with delta-time."
  (init-holodeck-storage)
  (let ((*delta-time* 0.5)
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 10.0 :y 0.0 :z 0.0)
    (make-velocity3d e :dx 4.0 :dy 0.0 :dz 0.0)
    (make-scale3d e)
    (make-visual-style e)
    (make-detail-level e)
    (cl-fast-ecs:run-systems)
    (is (= 12.0 (position3d-x e)))))

(test pulse-system-modifies-scale
  "Test that pulse system modifies scale for entities with pulse-rate."
  (init-holodeck-storage)
  (let ((*elapsed-time* (/ pi 2.0))  ; sin(pi/2 * rate) for predictable pulse
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e)
    (make-velocity3d e)
    (make-scale3d e)
    (make-visual-style e :pulse-rate 1.0)
    (make-detail-level e)
    (cl-fast-ecs:run-systems)
    ;; With pulse-rate=1.0 and time=pi/2, sin(pi/2)=1.0
    ;; pulse = 1.0 + 0.1 * 1.0 = 1.1
    (is (< 1.09 (scale3d-sx e) 1.11))
    (is (< 1.09 (scale3d-sy e) 1.11))
    (is (< 1.09 (scale3d-sz e) 1.11))))

(test pulse-system-ignores-zero-rate
  "Test that pulse system does not modify entities with zero pulse-rate."
  (init-holodeck-storage)
  (let ((*elapsed-time* 1.0)
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e)
    (make-velocity3d e)
    (make-scale3d e :sx 2.0 :sy 2.0 :sz 2.0)
    (make-visual-style e :pulse-rate 0.0)
    (make-detail-level e)
    (cl-fast-ecs:run-systems)
    ;; Scale should remain unchanged
    (is (= 2.0 (scale3d-sx e)))
    (is (= 2.0 (scale3d-sy e)))
    (is (= 2.0 (scale3d-sz e)))))

(test lod-system-sets-high-when-close
  "Test that LOD system sets :high for nearby entities."
  (init-holodeck-storage)
  (let ((*camera-position* (3d-vectors:vec3 0.0 0.0 0.0))
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 1.0 :y 0.0 :z 0.0)  ; distance = 1.0
    (make-velocity3d e)
    (make-scale3d e)
    (make-visual-style e)
    (make-detail-level e :low-distance 50.0 :cull-distance 100.0)
    (cl-fast-ecs:run-systems)
    (is (eq :high (detail-level-current e)))))

(test lod-system-sets-low-when-medium-distance
  "Test that LOD system sets :low for medium-distance entities."
  (init-holodeck-storage)
  (let ((*camera-position* (3d-vectors:vec3 0.0 0.0 0.0))
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 75.0 :y 0.0 :z 0.0)  ; distance = 75 (between 50 and 100)
    (make-velocity3d e)
    (make-scale3d e)
    (make-visual-style e)
    (make-detail-level e :low-distance 50.0 :cull-distance 100.0)
    (cl-fast-ecs:run-systems)
    (is (eq :low (detail-level-current e)))))

(test lod-system-sets-culled-when-far
  "Test that LOD system sets :culled for far entities."
  (init-holodeck-storage)
  (let ((*camera-position* (3d-vectors:vec3 0.0 0.0 0.0))
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 200.0 :y 0.0 :z 0.0)  ; distance = 200 (beyond 100)
    (make-velocity3d e)
    (make-scale3d e)
    (make-visual-style e)
    (make-detail-level e :low-distance 50.0 :cull-distance 100.0)
    (cl-fast-ecs:run-systems)
    (is (eq :culled (detail-level-current e)))))

(test distance-to-camera-calculation
  "Test distance-to-camera utility function."
  (let ((*camera-position* (3d-vectors:vec3 0.0 0.0 0.0)))
    (is (< (abs (- (distance-to-camera 3.0 4.0 0.0) 5.0)) 0.001))
    (is (< (abs (- (distance-to-camera 0.0 0.0 0.0) 0.0)) 0.001))
    (is (< (abs (- (distance-to-camera 1.0 0.0 0.0) 1.0)) 0.001))))

(test multiple-entities-processed
  "Test that systems process multiple entities correctly."
  (init-holodeck-storage)
  (let ((*delta-time* 1.0))
    (let ((e1 (cl-fast-ecs:make-entity))
          (e2 (cl-fast-ecs:make-entity)))
      (make-position3d e1 :x 0.0 :y 0.0 :z 0.0)
      (make-velocity3d e1 :dx 1.0 :dy 0.0 :dz 0.0)
      (make-scale3d e1)
      (make-visual-style e1)
      (make-detail-level e1)
      (make-position3d e2 :x 10.0 :y 0.0 :z 0.0)
      (make-velocity3d e2 :dx -1.0 :dy 0.0 :dz 0.0)
      (make-scale3d e2)
      (make-visual-style e2)
      (make-detail-level e2)
      (cl-fast-ecs:run-systems)
      (is (= 1.0 (position3d-x e1)))
      (is (= 9.0 (position3d-x e2))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Window Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite window-tests
  :in holodeck-tests
  :description "Tests for holodeck-window class and lifecycle")

(in-suite window-tests)

(test holodeck-window-creation-defaults
  "Test that holodeck-window is created with correct defaults."
  (let ((w (make-instance 'holodeck-window)))
    (is (= *window-width* (window-width w)))
    (is (= *window-height* (window-height w)))
    (is (string= *window-title* (window-title w)))
    (is (null (holodeck-scene w)))
    (is (null (holodeck-camera w)))
    (is (null (holodeck-hud w)))
    (is (null (holodeck-running-p w)))
    (is (null (holodeck-store w)))))

(test holodeck-window-custom-initargs
  "Test that holodeck-window accepts custom initargs."
  (let ((w (make-instance 'holodeck-window
                          :width 800
                          :height 600
                          :title "Test Holodeck"
                          :store :test-store)))
    (is (= 800 (window-width w)))
    (is (= 600 (window-height w)))
    (is (string= "Test Holodeck" (window-title w)))
    (is (eq :test-store (holodeck-store w)))))

(test holodeck-window-aspect-ratio
  "Test window aspect ratio calculation."
  (let ((w (make-instance 'holodeck-window :width 1920 :height 1080)))
    (is (< (abs (- (window-aspect-ratio w) (/ 1920.0 1080.0))) 0.01)))
  (let ((w (make-instance 'holodeck-window :width 800 :height 800)))
    (is (< (abs (- (window-aspect-ratio w) 1.0)) 0.01)))
  ;; Zero height should return 1.0 (not error)
  (let ((w (make-instance 'holodeck-window :width 800 :height 0)))
    (is (= 1.0 (window-aspect-ratio w)))))

(test holodeck-window-resize
  "Test window resize updates dimensions."
  (let ((w (make-instance 'holodeck-window :width 1920 :height 1080)))
    (resize-window w 1280 720)
    (is (= 1280 (window-width w)))
    (is (= 720 (window-height w)))))

(test setup-scene-initializes-ecs
  "Test that setup-scene initializes ECS and marks window running."
  (let ((w (make-instance 'holodeck-window)))
    (is (null (holodeck-running-p w)))
    (setup-scene w)
    (is (holodeck-running-p w))))

(test launch-holodeck-creates-window
  "Test that launch-holodeck creates and initializes a window."
  (setf *holodeck* nil)
  (let ((w (launch-holodeck :width 640 :height 480 :title "Test")))
    (unwind-protect
        (progn
          (is (not (null w)))
          (is (eq w *holodeck*))
          (is (= 640 (window-width w)))
          (is (= 480 (window-height w)))
          (is (string= "Test" (window-title w)))
          (is (holodeck-running-p w)))
      (stop-holodeck))))

(test stop-holodeck-cleans-up
  "Test that stop-holodeck stops and clears the global."
  (setf *holodeck* nil)
  (launch-holodeck)
  (is (not (null *holodeck*)))
  (stop-holodeck)
  (is (null *holodeck*)))

(test launch-holodeck-replaces-existing
  "Test that launching a new holodeck replaces the existing one."
  (setf *holodeck* nil)
  (let ((w1 (launch-holodeck :title "First")))
    (declare (ignore w1))
    (let ((w2 (handler-bind ((warning #'muffle-warning))
                (launch-holodeck :title "Second"))))
      (unwind-protect
          (progn
            (is (eq w2 *holodeck*))
            (is (string= "Second" (window-title *holodeck*))))
        (stop-holodeck)))))

(test holodeck-update-advances-time
  "Test that holodeck-update advances elapsed time."
  (let ((w (make-instance 'holodeck-window))
        (initial-time *elapsed-time*))
    (setup-scene w)
    (holodeck-update w 0.016)
    (is (> *elapsed-time* initial-time))
    (stop-holodeck)))

(test shader-sources-defined
  "Test that shader source strings are defined and non-empty."
  (is (stringp *hologram-node-vertex-shader*))
  (is (> (length *hologram-node-vertex-shader*) 0))
  (is (stringp *hologram-node-fragment-shader*))
  (is (> (length *hologram-node-fragment-shader*) 0))
  (is (stringp *energy-beam-vertex-shader*))
  (is (> (length *energy-beam-vertex-shader*) 0))
  (is (stringp *energy-beam-fragment-shader*))
  (is (> (length *energy-beam-fragment-shader*) 0)))

(test shader-sources-plist-structure
  "Test that *shader-sources* plist contains expected shader programs."
  (is (listp *shader-sources*))
  (let ((hologram (getf *shader-sources* :hologram-node)))
    (is (not (null hologram)))
    (is (stringp (getf hologram :vertex)))
    (is (stringp (getf hologram :fragment))))
  (let ((beam (getf *shader-sources* :energy-beam)))
    (is (not (null beam)))
    (is (stringp (getf beam :vertex)))
    (is (stringp (getf beam :fragment)))))

;;; ===================================================================
;;; Shader Program Tests
;;; ===================================================================

(def-suite shader-tests
  :in holodeck-tests
  :description "Tests for shader programs, materials, and CPU-side computation")

(in-suite shader-tests)

;; --- Shader Program Class ---

(test shader-program-creation
  "Test that shader-program can be created with all slots."
  (let ((prog (make-hologram-node-shader)))
    (is (eq :hologram-node (shader-program-name prog)))
    (is (stringp (shader-program-vertex-source prog)))
    (is (stringp (shader-program-fragment-source prog)))
    (is (listp (shader-program-uniforms prog)))
    (is (> (length (shader-program-uniforms prog)) 0))))

(test shader-program-uniform-names-extraction
  "Test that uniform names are correctly extracted."
  (let* ((prog (make-hologram-node-shader))
         (names (shader-program-uniform-names prog)))
    (is (member "model" names :test #'string=))
    (is (member "view" names :test #'string=))
    (is (member "projection" names :test #'string=))
    (is (member "viewPos" names :test #'string=))
    (is (member "baseColor" names :test #'string=))
    (is (member "glowIntensity" names :test #'string=))
    (is (member "time" names :test #'string=))))

(test energy-beam-shader-creation
  "Test energy-beam shader program."
  (let ((prog (make-energy-beam-shader)))
    (is (eq :energy-beam (shader-program-name prog)))
    (is (stringp (shader-program-vertex-source prog)))
    (is (stringp (shader-program-fragment-source prog)))
    (let ((names (shader-program-uniform-names prog)))
      (is (member "energyFlow" names :test #'string=))
      (is (member "color" names :test #'string=)))))

(test glow-shader-creation
  "Test glow shader program."
  (let ((prog (make-glow-shader)))
    (is (eq :glow (shader-program-name prog)))
    (let ((names (shader-program-uniform-names prog)))
      (is (member "glowColor" names :test #'string=))
      (is (member "intensity" names :test #'string=))
      (is (member "falloff" names :test #'string=)))))

(test glow-shader-sources-defined
  "Test that glow shader sources are non-empty strings."
  (is (stringp *glow-vertex-shader*))
  (is (> (length *glow-vertex-shader*) 0))
  (is (stringp *glow-fragment-shader*))
  (is (> (length *glow-fragment-shader*) 0)))

;; --- Shader Registry ---

(test shader-registry-operations
  "Test register, find, list, and clear operations."
  (clear-shader-registry)
  ;; Initially empty
  (is (null (list-shader-programs)))
  (is (null (find-shader-program :hologram-node)))
  ;; Register
  (let ((prog (make-hologram-node-shader)))
    (register-shader-program prog)
    (is (eq prog (find-shader-program :hologram-node)))
    (is (member :hologram-node (list-shader-programs))))
  ;; Clear
  (clear-shader-registry)
  (is (null (find-shader-program :hologram-node))))

(test register-holodeck-shaders-registers-all
  "Test that register-holodeck-shaders registers all standard shaders."
  (clear-shader-registry)
  (let ((names (register-holodeck-shaders)))
    (is (member :hologram-node names))
    (is (member :energy-beam names))
    (is (member :glow names))
    ;; All are findable
    (is (not (null (find-shader-program :hologram-node))))
    (is (not (null (find-shader-program :energy-beam))))
    (is (not (null (find-shader-program :glow)))))
  (clear-shader-registry))

;; --- Shader Validation ---

(test validate-shader-source-valid
  "Test validation passes for well-formed shader source."
  (is (eq t (validate-shader-source *hologram-node-vertex-shader*)))
  (is (eq t (validate-shader-source *hologram-node-fragment-shader*)))
  (is (eq t (validate-shader-source *energy-beam-vertex-shader*)))
  (is (eq t (validate-shader-source *energy-beam-fragment-shader*)))
  (is (eq t (validate-shader-source *glow-vertex-shader*)))
  (is (eq t (validate-shader-source *glow-fragment-shader*))))

(test validate-shader-source-missing-version
  "Test validation fails when #version is missing."
  (signals error
    (validate-shader-source "void main() { }")))

(test validate-shader-source-missing-main
  "Test validation fails when main() is missing."
  (signals error
    (validate-shader-source "#version 330 core
out vec4 color;")))

(test validate-shader-source-not-string
  "Test validation fails for non-string input."
  (signals error
    (validate-shader-source 42)))

(test validate-shader-program-hologram
  "Test full program validation for hologram-node shader."
  (is (eq t (validate-shader-program (make-hologram-node-shader)))))

(test validate-shader-program-energy-beam
  "Test full program validation for energy-beam shader."
  (is (eq t (validate-shader-program (make-energy-beam-shader)))))

(test validate-shader-program-glow
  "Test full program validation for glow shader."
  (is (eq t (validate-shader-program (make-glow-shader)))))

;; --- Hologram Material ---

(test hologram-material-defaults
  "Test hologram-material default values."
  (let ((mat (make-instance 'hologram-material)))
    (is (listp (material-base-color mat)))
    (is (= 4 (length (material-base-color mat))))
    (is (= 1.0 (material-glow-intensity mat)))
    (is (= 3.0 (material-fresnel-power mat)))
    (is (= 50.0 (material-scanline-frequency mat)))
    (is (= 2.0 (material-scanline-speed mat)))
    (is (= 0.2 (material-scanline-intensity mat)))
    (is (eq :hologram-node (material-shader mat)))))

(test hologram-material-for-decision-type
  "Test material factory for :decision snapshot type."
  (let ((mat (make-hologram-material-for-type :decision)))
    ;; Decision should have gold-ish base color
    (is (> (first (material-base-color mat)) 0.8))
    ;; Should have higher glow intensity than default
    (is (> (material-glow-intensity mat) 1.0))
    ;; Should have higher scanline frequency
    (is (> (material-scanline-frequency mat) 50.0))))

(test hologram-material-for-genesis-type
  "Test material factory for :genesis snapshot type."
  (let ((mat (make-hologram-material-for-type :genesis)))
    ;; Genesis is green
    (is (> (second (material-base-color mat)) 0.8))
    ;; Lower fresnel power for wider glow
    (is (< (material-fresnel-power mat) 3.0))))

(test hologram-material-for-error-type
  "Test material factory for :error snapshot type."
  (let ((mat (make-hologram-material-for-type :error)))
    ;; Error is red
    (is (> (first (material-base-color mat)) 0.8))
    ;; Red glow color
    (is (> (first (material-glow-color mat)) 0.8))
    ;; High glow intensity
    (is (> (material-glow-intensity mat) 2.0))))

(test hologram-material-for-unknown-type
  "Test material factory for unknown snapshot types uses defaults."
  (let ((mat (make-hologram-material-for-type :something-unknown)))
    (is (= 1.0 (material-glow-intensity mat)))
    (is (= 3.0 (material-fresnel-power mat)))
    (is (= 50.0 (material-scanline-frequency mat)))))

(test hologram-material-types-differ
  "Test that different snapshot types produce different materials."
  (let ((decision (make-hologram-material-for-type :decision))
        (genesis (make-hologram-material-for-type :genesis))
        (fork (make-hologram-material-for-type :fork)))
    ;; All should have different base colors
    (is (not (equal (material-base-color decision)
                    (material-base-color genesis))))
    (is (not (equal (material-base-color decision)
                    (material-base-color fork))))))

;; --- CPU-Side Fresnel ---

(test compute-fresnel-face-on
  "Test Fresnel is minimal when surface faces viewer directly."
  ;; normal-dot-view = 1.0 means facing camera directly
  (is (< (compute-fresnel 1.0 3.0) 0.01)))

(test compute-fresnel-edge-on
  "Test Fresnel is maximal when surface is edge-on."
  ;; normal-dot-view = 0.0 means perpendicular to camera
  (is (> (compute-fresnel 0.0 3.0) 0.99)))

(test compute-fresnel-intermediate
  "Test Fresnel is between 0 and 1 at intermediate angles."
  (let ((f (compute-fresnel 0.5 3.0)))
    (is (> f 0.0))
    (is (< f 1.0))))

(test compute-fresnel-power-effect
  "Test that higher Fresnel power concentrates glow more at edges."
  (let ((low-power (compute-fresnel 0.5 1.0))
        (high-power (compute-fresnel 0.5 5.0)))
    ;; Higher power should produce smaller (more concentrated) values
    (is (> low-power high-power))))

(test compute-fresnel-clamps-input
  "Test Fresnel handles out-of-range inputs gracefully."
  ;; Values outside [0,1] should be clamped
  (is (< (compute-fresnel 1.5 3.0) 0.01))   ; clamped to 1.0
  (is (> (compute-fresnel -0.5 3.0) 0.99)))  ; clamped to 0.0

;; --- CPU-Side Scanline ---

(test compute-scanline-range
  "Test scanline output is in [0,1] range."
  (dotimes (i 10)
    (let ((val (compute-scanline (float i) 0.0 50.0 2.0)))
      (is (>= val 0.0))
      (is (<= val 1.0)))))

(test compute-scanline-varies-with-position
  "Test that scanline varies with Y position."
  (let ((v1 (compute-scanline 0.0 0.0 50.0 2.0))
        (v2 (compute-scanline 0.05 0.0 50.0 2.0)))
    ;; Different Y positions should give different scanline values
    ;; (unless we happen to hit the same phase, which is unlikely)
    (is (not (= v1 v2)))))

(test compute-scanline-varies-with-time
  "Test that scanline varies with time (animation)."
  (let ((v1 (compute-scanline 1.0 0.0 50.0 2.0))
        (v2 (compute-scanline 1.0 0.5 50.0 2.0)))
    (is (not (= v1 v2)))))

;; --- CPU-Side Hologram Color ---

(test compute-hologram-color-returns-four-values
  "Test that compute-hologram-color returns R G B A."
  (let ((mat (make-instance 'hologram-material)))
    (multiple-value-bind (r g b a)
        (compute-hologram-color mat 0.8 5.0 0.0)
      (is (numberp r))
      (is (numberp g))
      (is (numberp b))
      (is (numberp a)))))

(test compute-hologram-color-range
  "Test output colors are in [0,1] range."
  (let ((mat (make-instance 'hologram-material)))
    (dotimes (i 10)
      (multiple-value-bind (r g b a)
          (compute-hologram-color mat
                                  (/ (float i) 10.0)
                                  (float i)
                                  (* i 0.1))
        (is (>= r 0.0)) (is (<= r 1.0))
        (is (>= g 0.0)) (is (<= g 1.0))
        (is (>= b 0.0)) (is (<= b 1.0))
        (is (>= a 0.0)) (is (<= a 1.0))))))

(test compute-hologram-color-edge-glow
  "Test that edges (low normal-dot-view) are brighter than faces."
  (let ((mat (make-instance 'hologram-material
                            :glow-intensity 2.0)))
    (multiple-value-bind (er eg eb ea)
        (compute-hologram-color mat 0.0 5.0 0.0)  ; edge-on
      (multiple-value-bind (fr fg fb fa)
          (compute-hologram-color mat 1.0 5.0 0.0)  ; face-on
        (declare (ignore ea fa))
        ;; Edge should be brighter due to Fresnel glow
        (is (> (+ er eg eb) (+ fr fg fb)))))))

(test compute-hologram-color-with-decision-material
  "Test hologram color with a decision-type material."
  (let ((mat (make-hologram-material-for-type :decision)))
    (multiple-value-bind (r g b a)
        (compute-hologram-color mat 0.5 3.0 1.0)
      (is (numberp r))
      (is (numberp g))
      (is (numberp b))
      (is (numberp a))
      ;; Decision material has gold base, so red should dominate
      (is (> r g)))))

;;; ===================================================================
;;; Energy Beam Material Tests
;;; ===================================================================

(def-suite energy-beam-tests
  :in holodeck-tests
  :description "Tests for energy beam material, factory, and CPU-side computation")

(in-suite energy-beam-tests)

;; --- Energy Beam Material ---

(test energy-beam-material-defaults
  "Test energy-beam-material default values."
  (let ((mat (make-instance 'energy-beam-material)))
    (is (listp (beam-material-color mat)))
    (is (= 4 (length (beam-material-color mat))))
    (is (= 1.0 (beam-material-flow-speed mat)))
    (is (= 6.28 (beam-material-flow-scale mat)))
    (is (= 0.7 (beam-material-pulse-intensity mat)))
    (is (= 0.3 (beam-material-base-alpha mat)))
    (is (= 0.5 (beam-material-color-boost mat)))))

(test energy-beam-material-custom-values
  "Test energy-beam-material with custom values."
  (let ((mat (make-instance 'energy-beam-material
                            :beam-color '(1.0 0.0 0.0 0.8)
                            :flow-speed 3.0
                            :flow-scale 12.56
                            :pulse-intensity 0.9
                            :base-alpha 0.5
                            :color-boost 0.8)))
    (is (equal '(1.0 0.0 0.0 0.8) (beam-material-color mat)))
    (is (= 3.0 (beam-material-flow-speed mat)))
    (is (= 12.56 (beam-material-flow-scale mat)))
    (is (= 0.9 (beam-material-pulse-intensity mat)))
    (is (= 0.5 (beam-material-base-alpha mat)))
    (is (= 0.8 (beam-material-color-boost mat)))))

;; --- Connection Type Colors ---

(test connection-type-colors
  "Test that different connection types map to different colors."
  (multiple-value-bind (r1 g1 b1 a1) (connection-type-to-color :temporal)
    (declare (ignore a1))
    (multiple-value-bind (r2 g2 b2 a2) (connection-type-to-color :fork)
      (declare (ignore a2))
      ;; Temporal (blue) and fork (purple) should differ
      (is (not (and (= r1 r2) (= g1 g2) (= b1 b2)))))))

(test connection-type-color-parent-child
  "Test parent-child connection color matches temporal."
  (multiple-value-bind (r1 g1 b1 a1) (connection-type-to-color :temporal)
    (multiple-value-bind (r2 g2 b2 a2) (connection-type-to-color :parent-child)
      (is (= r1 r2))
      (is (= g1 g2))
      (is (= b1 b2))
      (is (= a1 a2)))))

(test connection-type-color-merge
  "Test merge connection color is green."
  (multiple-value-bind (r g b a) (connection-type-to-color :merge)
    (declare (ignore a))
    ;; Merge should be green-dominant
    (is (> g r))
    (is (> g b))))

;; --- Material Factory ---

(test energy-beam-material-for-temporal
  "Test material factory for :temporal connection type."
  (let ((mat (make-energy-beam-material-for-connection-type :temporal)))
    (is (= 1.0 (beam-material-flow-speed mat)))
    (is (= 0.3 (beam-material-base-alpha mat)))
    ;; Color should be blue-ish
    (is (> (third (beam-material-color mat))
           (first (beam-material-color mat))))))

(test energy-beam-material-for-fork
  "Test material factory for :fork connection type."
  (let ((mat (make-energy-beam-material-for-connection-type :fork)))
    ;; Fork beams are faster and more intense
    (is (> (beam-material-flow-speed mat) 1.0))
    (is (> (beam-material-pulse-intensity mat) 0.7))
    ;; Color should be purple-ish (high r and b)
    (is (> (first (beam-material-color mat)) 0.5))
    (is (> (third (beam-material-color mat)) 0.5))))

(test energy-beam-material-for-merge
  "Test material factory for :merge connection type."
  (let ((mat (make-energy-beam-material-for-connection-type :merge)))
    ;; Merge beams have moderate flow
    (is (> (beam-material-flow-speed mat) 1.0))
    ;; Color should be green-ish
    (is (> (second (beam-material-color mat))
           (first (beam-material-color mat))))))

(test energy-beam-material-for-unknown
  "Test material factory for unknown connection types uses defaults."
  (let ((mat (make-energy-beam-material-for-connection-type :some-unknown)))
    (is (= 1.0 (beam-material-flow-speed mat)))
    (is (= 0.7 (beam-material-pulse-intensity mat)))))

(test energy-beam-material-types-differ
  "Test that different connection types produce different materials."
  (let ((temporal (make-energy-beam-material-for-connection-type :temporal))
        (fork (make-energy-beam-material-for-connection-type :fork))
        (merge-mat (make-energy-beam-material-for-connection-type :merge)))
    ;; All should have different base colors
    (is (not (equal (beam-material-color temporal)
                    (beam-material-color fork))))
    (is (not (equal (beam-material-color temporal)
                    (beam-material-color merge-mat))))))

;; --- CPU-Side Energy Flow ---

(test compute-energy-flow-range
  "Test energy flow output is in [0,1] range."
  (dotimes (i 20)
    (let ((val (compute-energy-flow (/ (float i) 20.0) (* i 0.1) 1.0 6.28)))
      (is (>= val 0.0))
      (is (<= val 1.0)))))

(test compute-energy-flow-varies-with-progress
  "Test that energy flow varies along the beam."
  (let ((v1 (compute-energy-flow 0.0 0.0 1.0 6.28))
        (v2 (compute-energy-flow 0.25 0.0 1.0 6.28)))
    ;; Different progress positions should give different energy values
    (is (not (= v1 v2)))))

(test compute-energy-flow-varies-with-time
  "Test that energy flow varies with time (animation)."
  (let ((v1 (compute-energy-flow 0.5 0.0 1.0 6.28))
        (v2 (compute-energy-flow 0.5 0.5 1.0 6.28)))
    (is (not (= v1 v2)))))

(test compute-energy-flow-speed-effect
  "Test that flow speed affects the animation rate."
  ;; At different speeds, the same time offset should produce different results
  (let ((v-slow (compute-energy-flow 0.5 1.0 0.5 6.28))
        (v-fast (compute-energy-flow 0.5 1.0 2.0 6.28)))
    (is (not (= v-slow v-fast)))))

(test compute-energy-flow-scale-effect
  "Test that flow scale affects the frequency of energy pulses."
  (let ((v-low (compute-energy-flow 0.5 0.0 1.0 3.14))
        (v-high (compute-energy-flow 0.5 0.0 1.0 12.56)))
    (is (not (= v-low v-high)))))

;; --- CPU-Side Beam Color ---

(test compute-beam-color-returns-four-values
  "Test that compute-beam-color returns R G B A."
  (let ((mat (make-instance 'energy-beam-material)))
    (multiple-value-bind (r g b a)
        (compute-beam-color mat 0.5 0.0)
      (is (numberp r))
      (is (numberp g))
      (is (numberp b))
      (is (numberp a)))))

(test compute-beam-color-range
  "Test output colors are in [0,1] range."
  (let ((mat (make-instance 'energy-beam-material)))
    (dotimes (i 10)
      (multiple-value-bind (r g b a)
          (compute-beam-color mat (/ (float i) 10.0) (* i 0.3))
        (is (>= r 0.0)) (is (<= r 1.0))
        (is (>= g 0.0)) (is (<= g 1.0))
        (is (>= b 0.0)) (is (<= b 1.0))
        (is (>= a 0.0)) (is (<= a 1.0))))))

(test compute-beam-color-peak-brighter-than-trough
  "Test that energy peaks are brighter than troughs."
  (let ((mat (make-instance 'energy-beam-material
                            :beam-color '(0.5 0.5 0.8 0.6)
                            :pulse-intensity 0.8
                            :color-boost 0.5)))
    ;; Energy flow = 1.0 at peak, 0.0 at trough
    ;; Find a peak and trough by sampling
    (let ((brightest 0.0)
          (dimmest 3.0))
      (dotimes (i 100)
        (let ((progress (/ (float i) 100.0)))
          (multiple-value-bind (r g b a)
              (compute-beam-color mat progress 0.0)
            (declare (ignore a))
            (let ((brightness (+ r g b)))
              (when (> brightness brightest)
                (setf brightest brightness))
              (when (< brightness dimmest)
                (setf dimmest brightness))))))
      ;; Peak should be noticeably brighter than trough
      (is (> brightest dimmest)))))

(test compute-beam-color-alpha-modulated
  "Test that alpha varies along the beam."
  (let ((mat (make-instance 'energy-beam-material
                            :beam-color '(0.5 0.5 0.8 0.8)
                            :pulse-intensity 0.7
                            :base-alpha 0.3)))
    ;; Sample alpha at various points
    (let ((alphas nil))
      (dotimes (i 100)
        (multiple-value-bind (r g b a)
            (compute-beam-color mat (/ (float i) 100.0) 0.0)
          (declare (ignore r g b))
          (push a alphas)))
      ;; Alpha should vary (not all the same)
      (let ((min-a (apply #'min alphas))
            (max-a (apply #'max alphas)))
        (is (> max-a min-a))))))

(test compute-beam-color-with-fork-material
  "Test beam color with a fork-type material."
  (let ((mat (make-energy-beam-material-for-connection-type :fork)))
    (multiple-value-bind (r g b a)
        (compute-beam-color mat 0.5 1.0)
      (is (numberp r))
      (is (numberp g))
      (is (numberp b))
      (is (numberp a))
      ;; Fork material has purple color, so red and blue should be significant
      (is (> r 0.1))
      (is (> b 0.1)))))

;;; ===================================================================
;;; Mesh Primitive Tests
;;; ===================================================================

(def-suite mesh-tests
  :in holodeck-tests
  :description "Tests for mesh primitives (sphere, octahedron, branching-node)")

(in-suite mesh-tests)

;; --- Mesh Primitive Class ---

(test mesh-primitive-creation
  "Test that mesh-primitive can be created with all slots."
  (let ((mesh (make-sphere-mesh :lod 0)))
    (is (eq :sphere (mesh-name mesh)))
    (is (= 0 (mesh-lod mesh)))
    (is (arrayp (mesh-vertices mesh)))
    (is (arrayp (mesh-normals mesh)))
    (is (arrayp (mesh-indices mesh)))
    (is (> (mesh-vertex-count mesh) 0))
    (is (> (mesh-triangle-count mesh) 0))))

(test mesh-primitive-print-object
  "Test that mesh print-object produces readable output."
  (let* ((mesh (make-sphere-mesh :lod 2))
         (str (format nil "~A" mesh)))
    (is (search "SPHERE" str))
    (is (search "LOD=2" str))
    (is (search "verts=" str))
    (is (search "tris=" str))))

;; --- Normalize Helper ---

(test normalize-xyz-unit-vector
  "Test normalizing an already-unit vector."
  (multiple-value-bind (x y z) (normalize-xyz 1.0 0.0 0.0)
    (is (< (abs (- x 1.0)) 0.001))
    (is (< (abs y) 0.001))
    (is (< (abs z) 0.001))))

(test normalize-xyz-non-unit
  "Test normalizing a non-unit vector."
  (multiple-value-bind (x y z) (normalize-xyz 3.0 4.0 0.0)
    (is (< (abs (- x 0.6)) 0.001))
    (is (< (abs (- y 0.8)) 0.001))
    (is (< (abs z) 0.001))
    ;; Length should be 1.0
    (is (< (abs (- (sqrt (+ (* x x) (* y y) (* z z))) 1.0)) 0.001))))

(test normalize-xyz-zero-vector
  "Test normalizing a zero vector returns default up."
  (multiple-value-bind (x y z) (normalize-xyz 0.0 0.0 0.0)
    (is (= 0.0 x))
    (is (= 1.0 y))
    (is (= 0.0 z))))

;; --- Sphere Mesh ---

(test sphere-mesh-lod-0
  "Test sphere mesh at LOD 0 (minimal detail)."
  (let ((mesh (make-sphere-mesh :lod 0)))
    (is (eq :sphere (mesh-name mesh)))
    (is (= 0 (mesh-lod mesh)))
    ;; LOD 0 has 4x4 segments = (4+1)*(4+1) = 25 vertices
    (is (= 25 (mesh-vertex-count mesh)))
    ;; 4*4*2 = 32 triangles
    (is (= 32 (mesh-triangle-count mesh)))
    ;; Vertex array should have 3 floats per vertex
    (is (= (* 25 3) (length (mesh-vertices mesh))))
    ;; Normal array same size
    (is (= (* 25 3) (length (mesh-normals mesh))))
    ;; Index array has 3 indices per triangle
    (is (= (* 32 3) (length (mesh-indices mesh))))))

(test sphere-mesh-lod-increases-detail
  "Test that higher LOD levels produce more geometry."
  (let ((lod0 (make-sphere-mesh :lod 0))
        (lod1 (make-sphere-mesh :lod 1))
        (lod2 (make-sphere-mesh :lod 2))
        (lod3 (make-sphere-mesh :lod 3)))
    (is (< (mesh-vertex-count lod0) (mesh-vertex-count lod1)))
    (is (< (mesh-vertex-count lod1) (mesh-vertex-count lod2)))
    (is (< (mesh-vertex-count lod2) (mesh-vertex-count lod3)))
    (is (< (mesh-triangle-count lod0) (mesh-triangle-count lod1)))
    (is (< (mesh-triangle-count lod1) (mesh-triangle-count lod2)))
    (is (< (mesh-triangle-count lod2) (mesh-triangle-count lod3)))))

(test sphere-mesh-radius
  "Test that sphere radius scales vertices."
  (let ((small (make-sphere-mesh :lod 0 :radius 0.5))
        (large (make-sphere-mesh :lod 0 :radius 2.0)))
    ;; Max vertex extent of large should be ~4x small
    (let ((small-max (loop for i below (length (mesh-vertices small))
                           maximize (abs (aref (mesh-vertices small) i))))
          (large-max (loop for i below (length (mesh-vertices large))
                           maximize (abs (aref (mesh-vertices large) i)))))
      (is (< (abs (- (/ large-max small-max) 4.0)) 0.1)))))

(test sphere-mesh-normals-unit-length
  "Test that sphere normals are approximately unit length."
  (let ((mesh (make-sphere-mesh :lod 1)))
    (dotimes (i (mesh-vertex-count mesh))
      (let* ((ni (* i 3))
             (nx (aref (mesh-normals mesh) ni))
             (ny (aref (mesh-normals mesh) (+ ni 1)))
             (nz (aref (mesh-normals mesh) (+ ni 2)))
             (len (sqrt (+ (* nx nx) (* ny ny) (* nz nz)))))
        (is (< (abs (- len 1.0)) 0.01))))))

;; --- Octahedron Mesh ---

(test octahedron-mesh-lod-0
  "Test octahedron mesh at LOD 0 (base octahedron)."
  (let ((mesh (make-octahedron-mesh :lod 0)))
    (is (eq :octahedron (mesh-name mesh)))
    (is (= 0 (mesh-lod mesh)))
    ;; Base octahedron: 6 vertices, 8 faces
    (is (= 6 (mesh-vertex-count mesh)))
    (is (= 8 (mesh-triangle-count mesh)))))

(test octahedron-mesh-lod-increases-detail
  "Test that higher LODs subdivide the octahedron."
  (let ((lod0 (make-octahedron-mesh :lod 0))
        (lod1 (make-octahedron-mesh :lod 1))
        (lod2 (make-octahedron-mesh :lod 2)))
    ;; Each subdivision quadruples faces
    (is (= 8 (mesh-triangle-count lod0)))
    (is (= 32 (mesh-triangle-count lod1)))
    (is (= 128 (mesh-triangle-count lod2)))
    ;; Vertices should increase
    (is (< (mesh-vertex-count lod0) (mesh-vertex-count lod1)))
    (is (< (mesh-vertex-count lod1) (mesh-vertex-count lod2)))))

(test octahedron-mesh-normals-unit-length
  "Test that octahedron normals are approximately unit length."
  (let ((mesh (make-octahedron-mesh :lod 1)))
    (dotimes (i (mesh-vertex-count mesh))
      (let* ((ni (* i 3))
             (nx (aref (mesh-normals mesh) ni))
             (ny (aref (mesh-normals mesh) (+ ni 1)))
             (nz (aref (mesh-normals mesh) (+ ni 2)))
             (len (sqrt (+ (* nx nx) (* ny ny) (* nz nz)))))
        (is (< (abs (- len 1.0)) 0.01))))))

(test octahedron-mesh-vertices-on-sphere
  "Test that octahedron vertices lie on a sphere of given radius."
  (let* ((radius 1.5)
         (mesh (make-octahedron-mesh :lod 1 :radius radius)))
    ;; All vertices should be at distance ~radius from origin
    (dotimes (i (mesh-vertex-count mesh))
      (let* ((vi (* i 3))
             (x (aref (mesh-vertices mesh) vi))
             (y (aref (mesh-vertices mesh) (+ vi 1)))
             (z (aref (mesh-vertices mesh) (+ vi 2)))
             (dist (sqrt (+ (* x x) (* y y) (* z z)))))
        (is (< (abs (- dist radius)) 0.01))))))

;; --- Branching Node Mesh ---

(test branching-node-mesh-creation
  "Test branching-node mesh creation."
  (let ((mesh (make-branching-node-mesh :lod 2)))
    (is (eq :branching-node (mesh-name mesh)))
    (is (= 2 (mesh-lod mesh)))
    (is (> (mesh-vertex-count mesh) 0))
    (is (> (mesh-triangle-count mesh) 0))))

(test branching-node-mesh-more-complex-than-sphere
  "Test that branching-node has more geometry than a sphere at same LOD."
  (let ((branch (make-branching-node-mesh :lod 1))
        (sphere (make-sphere-mesh :lod 1)))
    ;; Branching node has central body + 3 prongs, so more triangles
    (is (> (mesh-triangle-count branch) (mesh-triangle-count sphere)))))

(test branching-node-mesh-lod-increases-detail
  "Test that higher LODs produce more geometry."
  (let ((lod0 (make-branching-node-mesh :lod 0))
        (lod2 (make-branching-node-mesh :lod 2)))
    (is (< (mesh-vertex-count lod0) (mesh-vertex-count lod2)))
    (is (< (mesh-triangle-count lod0) (mesh-triangle-count lod2)))))

;; --- Mesh Factory ---

(test make-mesh-for-type-sphere
  "Test factory function creates sphere."
  (let ((mesh (make-mesh-for-type :sphere :lod 1)))
    (is (eq :sphere (mesh-name mesh)))
    (is (= 1 (mesh-lod mesh)))))

(test make-mesh-for-type-octahedron
  "Test factory function creates octahedron."
  (let ((mesh (make-mesh-for-type :octahedron :lod 2)))
    (is (eq :octahedron (mesh-name mesh)))
    (is (= 2 (mesh-lod mesh)))))

(test make-mesh-for-type-branching-node
  "Test factory function creates branching-node."
  (let ((mesh (make-mesh-for-type :branching-node :lod 0)))
    (is (eq :branching-node (mesh-name mesh)))
    (is (= 0 (mesh-lod mesh)))))

(test make-mesh-for-type-unknown-signals-error
  "Test factory function signals error for unknown type."
  (signals error
    (make-mesh-for-type :nonexistent)))

;; --- Mesh Registry ---

(test mesh-registry-operations
  "Test register, find, list, and clear operations."
  (clear-mesh-registry)
  ;; Initially empty
  (is (null (list-meshes)))
  (is (null (find-mesh :sphere 2)))
  ;; Register a mesh
  (let ((mesh (make-sphere-mesh :lod 2)))
    (register-mesh mesh)
    (is (eq mesh (find-mesh :sphere 2)))
    (is (member (cons :sphere 2) (list-meshes) :test #'equal)))
  ;; Clear
  (clear-mesh-registry)
  (is (null (find-mesh :sphere 2))))

(test mesh-registry-multiple-lods
  "Test registering same mesh type at different LODs."
  (clear-mesh-registry)
  (let ((s0 (make-sphere-mesh :lod 0))
        (s1 (make-sphere-mesh :lod 1))
        (s2 (make-sphere-mesh :lod 2)))
    (register-mesh s0)
    (register-mesh s1)
    (register-mesh s2)
    (is (eq s0 (find-mesh :sphere 0)))
    (is (eq s1 (find-mesh :sphere 1)))
    (is (eq s2 (find-mesh :sphere 2)))
    (is (= 3 (length (list-meshes)))))
  (clear-mesh-registry))

(test register-holodeck-meshes-registers-all
  "Test that register-holodeck-meshes registers all standard meshes."
  (clear-mesh-registry)
  (let ((pairs (register-holodeck-meshes)))
    ;; 3 types * 4 LOD levels = 12 meshes
    (is (= 12 (length pairs)))
    ;; All types present
    (is (find-mesh :sphere 0))
    (is (find-mesh :sphere 3))
    (is (find-mesh :octahedron 0))
    (is (find-mesh :octahedron 3))
    (is (find-mesh :branching-node 0))
    (is (find-mesh :branching-node 3)))
  (clear-mesh-registry))

;; --- LOD Mesh ID ---

(test lod-mesh-id-returns-cons
  "Test that lod-mesh-id returns a (type . lod) cons."
  (let ((id (lod-mesh-id :sphere 2)))
    (is (consp id))
    (is (eq :sphere (car id)))
    (is (= 2 (cdr id)))))

;; --- Array Consistency ---

(test mesh-array-sizes-consistent
  "Test that vertex/normal/index array sizes are consistent for all types."
  (dolist (mesh-type '(:sphere :octahedron :branching-node))
    (dotimes (lod 4)
      (let ((mesh (make-mesh-for-type mesh-type :lod lod)))
        ;; Vertices: 3 floats per vertex
        (is (= (* (mesh-vertex-count mesh) 3)
               (length (mesh-vertices mesh))))
        ;; Normals: same size as vertices
        (is (= (length (mesh-vertices mesh))
               (length (mesh-normals mesh))))
        ;; Indices: 3 per triangle
        (is (= (* (mesh-triangle-count mesh) 3)
               (length (mesh-indices mesh))))
        ;; All indices should be valid vertex references
        (let ((max-idx (1- (mesh-vertex-count mesh))))
          (dotimes (i (length (mesh-indices mesh)))
            (is (>= (aref (mesh-indices mesh) i) 0))
            (is (<= (aref (mesh-indices mesh) i) max-idx))))))))

;;; ===================================================================
;;; Rendering Tests
;;; ===================================================================

(def-suite rendering-tests
  :in holodeck-tests
  :description "Tests for render-snapshot-entity with LOD support")

(in-suite rendering-tests)

;; --- Snapshot Type to Mesh Type ---

(test snapshot-type-to-mesh-type-decision
  "Test decision type maps to octahedron."
  (is (eq :octahedron (snapshot-type-to-mesh-type :decision))))

(test snapshot-type-to-mesh-type-action
  "Test action type maps to octahedron."
  (is (eq :octahedron (snapshot-type-to-mesh-type :action))))

(test snapshot-type-to-mesh-type-fork
  "Test fork type maps to branching-node."
  (is (eq :branching-node (snapshot-type-to-mesh-type :fork))))

(test snapshot-type-to-mesh-type-branch
  "Test branch type maps to branching-node."
  (is (eq :branching-node (snapshot-type-to-mesh-type :branch))))

(test snapshot-type-to-mesh-type-snapshot
  "Test default snapshot type maps to sphere."
  (is (eq :sphere (snapshot-type-to-mesh-type :snapshot))))

(test snapshot-type-to-mesh-type-genesis
  "Test genesis type maps to sphere."
  (is (eq :sphere (snapshot-type-to-mesh-type :genesis))))

;; --- Detail Level to Mesh LOD ---

(test detail-level-to-mesh-lod-high
  "Test :high detail maps to mesh LOD 2."
  (is (= 2 (detail-level-to-mesh-lod :high))))

(test detail-level-to-mesh-lod-low
  "Test :low detail maps to mesh LOD 0."
  (is (= 0 (detail-level-to-mesh-lod :low))))

(test detail-level-to-mesh-lod-culled
  "Test :culled detail maps to NIL."
  (is (null (detail-level-to-mesh-lod :culled))))

;; --- Render Snapshot Entity ---

(test render-snapshot-entity-culled-returns-nil
  "Test that culled entities return NIL render description."
  (init-holodeck-storage)
  (let ((*camera-position* (3d-vectors:vec3 0.0 0.0 0.0)))
    (let ((e (make-snapshot-entity "snap-cull" :snapshot
                                   :x 300.0 :y 0.0 :z 0.0)))
      ;; Force culled state
      (setf (detail-level-current e) :culled)
      (is (null (render-snapshot-entity e))))))

(test render-snapshot-entity-high-detail
  "Test render description at :high detail level."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-hi" :decision
                                 :x 5.0 :y 10.0 :z 2.0)))
    (setf (detail-level-current e) :high)
    (let ((desc (render-snapshot-entity e)))
      ;; Should produce a valid description
      (is (not (null desc)))
      (is (render-desc-visible-p desc))
      ;; Position should match entity
      (is (equal '(5.0 10.0 2.0) (render-desc-position desc)))
      ;; Should have a mesh (octahedron for decision)
      (is (not (null (render-desc-mesh desc))))
      (is (eq :octahedron (mesh-name (render-desc-mesh desc))))
      ;; Should have material
      (is (not (null (render-desc-material desc))))
      (is (typep (render-desc-material desc) 'hologram-material))
      ;; Glow should be on at high detail
      (is (render-desc-glow-p desc))
      ;; LOD should be :high
      (is (eq :high (render-desc-lod desc)))
      ;; Color should be a 4-element list
      (is (= 4 (length (render-desc-color desc))))))
  (clear-mesh-registry))

(test render-snapshot-entity-low-detail
  "Test render description at :low detail level."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-lo" :snapshot
                                 :x 80.0 :y 0.0 :z 0.0)))
    (setf (detail-level-current e) :low)
    (let ((desc (render-snapshot-entity e)))
      ;; Should still be visible
      (is (not (null desc)))
      (is (render-desc-visible-p desc))
      ;; Should have a mesh at LOD 0 (sphere for :snapshot)
      (is (not (null (render-desc-mesh desc))))
      (is (eq :sphere (mesh-name (render-desc-mesh desc))))
      (is (= 0 (mesh-lod (render-desc-mesh desc))))
      ;; Glow should be off at low detail
      (is (not (render-desc-glow-p desc)))
      ;; Label should be nil at low detail
      (is (null (render-desc-label-text desc)))
      ;; LOD should be :low
      (is (eq :low (render-desc-lod desc)))
      ;; Alpha should be reduced (0.5x original)
      (let ((alpha (fourth (render-desc-color desc))))
        (is (< alpha 0.5)))))
  (clear-mesh-registry))

(test render-snapshot-entity-high-detail-with-label
  "Test that high detail shows label when visible."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-label" :genesis
                                 :x 1.0 :y 0.0 :z 0.0)))
    (setf (detail-level-current e) :high)
    (setf (node-label-visible-p e) t)
    (let ((desc (render-snapshot-entity e)))
      (is (string= "snap-label" (render-desc-label-text desc)))
      (is (numberp (render-desc-label-offset desc)))))
  (clear-mesh-registry))

(test render-snapshot-entity-high-detail-hidden-label
  "Test that high detail hides label when node-label-visible-p is nil."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-nolabel" :genesis
                                 :x 1.0 :y 0.0 :z 0.0)))
    (setf (detail-level-current e) :high)
    (setf (node-label-visible-p e) nil)
    (let ((desc (render-snapshot-entity e)))
      (is (null (render-desc-label-text desc)))))
  (clear-mesh-registry))

(test render-snapshot-entity-fork-uses-branching-mesh
  "Test that fork entities use branching-node mesh."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-fork" :fork
                                 :x 1.0 :y 0.0 :z 0.0)))
    (setf (detail-level-current e) :high)
    (let ((desc (render-snapshot-entity e)))
      (is (eq :branching-node (mesh-name (render-desc-mesh desc))))))
  (clear-mesh-registry))

(test render-snapshot-entity-material-matches-type
  "Test that material is created for the correct snapshot type."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-err" :error
                                 :x 1.0 :y 0.0 :z 0.0)))
    (setf (detail-level-current e) :high)
    (let* ((desc (render-snapshot-entity e))
           (mat (render-desc-material desc)))
      ;; Error material has high glow intensity
      (is (> (material-glow-intensity mat) 2.0))
      ;; Error material glow is red
      (is (> (first (material-glow-color mat)) 0.8))))
  (clear-mesh-registry))

(test render-snapshot-entity-low-reduces-glow
  "Test that :low detail reduces material glow intensity."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-dimglow" :decision
                                 :x 80.0 :y 0.0 :z 0.0)))
    (setf (detail-level-current e) :high)
    (let* ((high-desc (render-snapshot-entity e))
           (high-glow (material-glow-intensity (render-desc-material high-desc))))
      ;; Now set to low
      (setf (detail-level-current e) :low)
      (let* ((low-desc (render-snapshot-entity e))
             (low-glow (material-glow-intensity (render-desc-material low-desc))))
        ;; Low detail should have reduced glow
        (is (< low-glow high-glow)))))
  (clear-mesh-registry))

(test render-snapshot-entity-scale-preserved
  "Test that entity scale is preserved in render description."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-scale" :snapshot
                                 :x 0.0 :y 0.0 :z 0.0)))
    (setf (scale3d-sx e) 2.0)
    (setf (scale3d-sy e) 3.0)
    (setf (scale3d-sz e) 4.0)
    (setf (detail-level-current e) :high)
    (let ((desc (render-snapshot-entity e)))
      (is (equal '(2.0 3.0 4.0) (render-desc-scale desc)))))
  (clear-mesh-registry))

;; --- Render Description Accessors ---

(test render-desc-accessors
  "Test that all render description accessors work correctly."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (let ((e (make-snapshot-entity "snap-acc" :snapshot
                                 :x 1.0 :y 2.0 :z 3.0)))
    (setf (detail-level-current e) :high)
    (let ((desc (render-snapshot-entity e)))
      (is (= e (render-desc-entity desc)))
      (is (eq t (render-desc-visible-p desc)))
      (is (listp (render-desc-position desc)))
      (is (listp (render-desc-scale desc)))
      (is (listp (render-desc-rotation desc)))
      (is (typep (render-desc-mesh desc) 'mesh-primitive))
      (is (typep (render-desc-material desc) 'hologram-material))
      (is (listp (render-desc-color desc)))
      (is (eq :high (render-desc-lod desc)))))
  (clear-mesh-registry))

;; --- CPU-Side Snapshot Color ---

(test compute-snapshot-entity-color-returns-values
  "Test that compute-snapshot-entity-color returns R G B A."
  (init-holodeck-storage)
  (let ((e (make-snapshot-entity "snap-color" :decision
                                 :x 0.0 :y 5.0 :z 0.0)))
    (multiple-value-bind (r g b a)
        (compute-snapshot-entity-color e :normal-dot-view 0.5 :time 0.0)
      (is (numberp r))
      (is (numberp g))
      (is (numberp b))
      (is (numberp a))
      ;; All in [0,1]
      (is (>= r 0.0)) (is (<= r 1.0))
      (is (>= g 0.0)) (is (<= g 1.0))
      (is (>= b 0.0)) (is (<= b 1.0))
      (is (>= a 0.0)) (is (<= a 1.0)))))

(test compute-snapshot-entity-color-type-affects-output
  "Test that different snapshot types produce different colors."
  (init-holodeck-storage)
  (let ((e-decision (make-snapshot-entity "d1" :decision :x 0.0 :y 0.0 :z 0.0))
        (e-genesis (make-snapshot-entity "g1" :genesis :x 0.0 :y 0.0 :z 0.0)))
    (multiple-value-bind (dr dg db da)
        (compute-snapshot-entity-color e-decision :normal-dot-view 0.8 :time 0.0)
      (declare (ignore da))
      (multiple-value-bind (gr gg gb ga)
          (compute-snapshot-entity-color e-genesis :normal-dot-view 0.8 :time 0.0)
        (declare (ignore ga))
        ;; Decision (gold) and genesis (green) should produce different colors
        (is (not (and (< (abs (- dr gr)) 0.01)
                      (< (abs (- dg gg)) 0.01)
                      (< (abs (- db gb)) 0.01))))))))

;; --- Collect Render Descriptions ---

(test collect-snapshot-render-descriptions-basic
  "Test that collect-snapshot-render-descriptions gathers visible entities."
  (init-holodeck-storage)
  (register-holodeck-meshes)
  (reset-snapshot-entities)
  (let ((*camera-position* (3d-vectors:vec3 0.0 0.0 0.0)))
    ;; Create some snapshot entities and track them
    (let ((e1 (make-snapshot-entity "s1" :snapshot :x 1.0 :y 0.0 :z 0.0))
          (e2 (make-snapshot-entity "s2" :decision :x 2.0 :y 0.0 :z 0.0))
          (e3 (make-snapshot-entity "s3" :fork :x 300.0 :y 0.0 :z 0.0)))
      (track-snapshot-entity e1)
      (track-snapshot-entity e2)
      (track-snapshot-entity e3)
      ;; Run LOD system to set detail levels
      (cl-fast-ecs:run-systems)
      (let ((descs (collect-snapshot-render-descriptions)))
        ;; e1 and e2 are close, should be visible
        ;; e3 is far (300 units), should be culled
        (is (>= (length descs) 2))
        ;; All returned descriptions should be visible
        (dolist (d descs)
          (is (render-desc-visible-p d))))))
  (clear-mesh-registry))
