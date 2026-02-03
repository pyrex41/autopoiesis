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

;;; ===================================================================
;;; Connection Rendering Tests
;;; ===================================================================

(def-suite connection-rendering-tests
  :in holodeck-tests
  :description "Tests for render-connection-entity with energy beams")

(in-suite connection-rendering-tests)

;; --- Basic Connection Rendering ---

(test render-connection-entity-basic
  "Test that render-connection-entity produces a valid description."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :decision :x 10.0 :y 5.0 :z 0.0)))
    (let* ((conn (make-connection-entity e1 e2 :kind :parent-child))
           (desc (render-connection-entity conn)))
      ;; Should produce a valid description
      (is (not (null desc)))
      (is (conn-desc-visible-p desc))
      ;; From position should match e1
      (is (equal '(0.0 0.0 0.0) (conn-desc-from-position desc)))
      ;; To position should match e2
      (is (equal '(10.0 5.0 0.0) (conn-desc-to-position desc)))
      ;; Midpoint should be halfway
      (is (equal '(5.0 2.5 0.0) (conn-desc-midpoint desc)))
      ;; Connection kind preserved
      (is (eq :parent-child (conn-desc-connection-kind desc))))))

(test render-connection-entity-has-material
  "Test that connection render description includes energy-beam-material."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let* ((conn (make-connection-entity e1 e2 :kind :temporal))
           (desc (render-connection-entity conn)))
      (is (not (null (conn-desc-material desc))))
      (is (typep (conn-desc-material desc) 'energy-beam-material)))))

(test render-connection-entity-has-color
  "Test that connection render description includes color."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let* ((conn (make-connection-entity e1 e2))
           (desc (render-connection-entity conn))
           (color (conn-desc-color desc)))
      (is (= 4 (length color)))
      ;; All color components in [0,1]
      (dolist (c color)
        (is (>= c 0.0))
        (is (<= c 1.0))))))

(test render-connection-entity-has-energy-flow
  "Test that connection render description includes energy flow value."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let* ((conn (make-connection-entity e1 e2))
           (desc (render-connection-entity conn))
           (flow (conn-desc-energy-flow desc)))
      (is (numberp flow))
      (is (>= flow 0.0))
      (is (<= flow 1.0)))))

(test render-connection-entity-invalid-endpoint
  "Test that connections with invalid endpoints return NIL."
  (init-holodeck-storage)
  (let ((entity (cl-fast-ecs:make-entity)))
    (make-connection entity :from-entity -1 :to-entity -1 :kind :parent-child)
    (make-position3d entity)
    (make-visual-style entity)
    (is (null (render-connection-entity entity)))))

;; --- Connection Kind Affects Material ---

(test render-connection-entity-fork-kind
  "Test that fork connections get fork-type energy beam material."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :fork :x 10.0 :y 0.0 :z 5.0)))
    (let* ((conn (make-connection-entity e1 e2 :kind :fork))
           (desc (render-connection-entity conn))
           (mat (conn-desc-material desc)))
      ;; Fork material should have faster flow
      (is (> (beam-material-flow-speed mat) 1.0))
      ;; Fork material should have higher pulse intensity
      (is (> (beam-material-pulse-intensity mat) 0.7)))))

(test render-connection-entity-merge-kind
  "Test that merge connections get merge-type energy beam material."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let* ((conn (make-connection-entity e1 e2 :kind :merge))
           (desc (render-connection-entity conn))
           (mat (conn-desc-material desc))
           (color (beam-material-color mat)))
      ;; Merge material should have green-dominant color
      (is (> (second color) (first color))))))

(test render-connection-entity-kinds-produce-different-colors
  "Test that different connection kinds produce different beam colors."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let* ((conn-pc (make-connection-entity e1 e2 :kind :parent-child))
           (conn-fk (make-connection-entity e1 e2 :kind :fork))
           (desc-pc (render-connection-entity conn-pc))
           (desc-fk (render-connection-entity conn-fk)))
      ;; Different kinds should give different colors
      (is (not (equal (conn-desc-color desc-pc)
                      (conn-desc-color desc-fk)))))))

;; --- Midpoint Updates Entity Position ---

(test render-connection-entity-updates-position
  "Test that rendering updates the connection entity's position to midpoint."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 20.0 :y 10.0 :z 6.0)))
    (let ((conn (make-connection-entity e1 e2)))
      ;; Position starts at 0,0,0 (from make-connection-entity default)
      (is (= 0.0 (position3d-x conn)))
      ;; After rendering, position should be updated to midpoint
      (render-connection-entity conn)
      (is (= 10.0 (position3d-x conn)))
      (is (= 5.0 (position3d-y conn)))
      (is (= 3.0 (position3d-z conn))))))

;; --- Time Affects Energy Flow ---

(test render-connection-entity-time-affects-flow
  "Test that different times produce different energy flow values."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let ((conn (make-connection-entity e1 e2)))
      (let* ((desc1 (render-connection-entity conn :time 0.0))
             (desc2 (render-connection-entity conn :time 0.5)))
        ;; Different times should produce different energy flow
        (is (not (= (conn-desc-energy-flow desc1)
                    (conn-desc-energy-flow desc2))))))))

;; --- Connection Description Accessors ---

(test conn-desc-accessors-complete
  "Test that all connection render description accessors work."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 1.0 :y 2.0 :z 3.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 4.0 :y 5.0 :z 6.0)))
    (let* ((conn (make-connection-entity e1 e2 :kind :branch))
           (desc (render-connection-entity conn)))
      (is (= conn (conn-desc-entity desc)))
      (is (eq t (conn-desc-visible-p desc)))
      (is (listp (conn-desc-from-position desc)))
      (is (= 3 (length (conn-desc-from-position desc))))
      (is (listp (conn-desc-to-position desc)))
      (is (= 3 (length (conn-desc-to-position desc))))
      (is (listp (conn-desc-midpoint desc)))
      (is (= 3 (length (conn-desc-midpoint desc))))
      (is (eq :branch (conn-desc-connection-kind desc)))
      (is (typep (conn-desc-material desc) 'energy-beam-material))
      (is (listp (conn-desc-color desc)))
      (is (= 4 (length (conn-desc-color desc))))
      (is (numberp (conn-desc-energy-flow desc))))))

;; --- Connection Entity Tracking ---

(test connection-entity-tracking
  "Test tracking and collecting connection entity render descriptions."
  (init-holodeck-storage)
  (reset-connection-entities)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0))
        (e3 (make-snapshot-entity "s3" :decision :x 10.0 :y 0.0 :z 0.0)))
    (let ((c1 (make-connection-entity e1 e2 :kind :parent-child))
          (c2 (make-connection-entity e2 e3 :kind :parent-child)))
      (track-connection-entity c1)
      (track-connection-entity c2)
      (let ((descs (collect-connection-render-descriptions)))
        (is (= 2 (length descs)))
        (dolist (d descs)
          (is (conn-desc-visible-p d)))))))

(test reset-connection-entities-clears-list
  "Test that reset-connection-entities clears the tracking list."
  (init-holodeck-storage)
  (reset-connection-entities)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (track-connection-entity (make-connection-entity e1 e2))
    (is (= 1 (length *connection-entities*)))
    (reset-connection-entities)
    (is (null *connection-entities*))))

;; --- CPU-Side Connection Beam Color ---

(test compute-connection-beam-color-returns-values
  "Test that compute-connection-beam-color returns R G B A."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let ((conn (make-connection-entity e1 e2 :kind :temporal)))
      (multiple-value-bind (r g b a)
          (compute-connection-beam-color conn 0.5 :time 0.0)
        (is (numberp r))
        (is (numberp g))
        (is (numberp b))
        (is (numberp a))
        ;; All in [0,1]
        (is (>= r 0.0)) (is (<= r 1.0))
        (is (>= g 0.0)) (is (<= g 1.0))
        (is (>= b 0.0)) (is (<= b 1.0))
        (is (>= a 0.0)) (is (<= a 1.0))))))

(test compute-connection-beam-color-varies-with-progress
  "Test that beam color varies along the connection."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let ((conn (make-connection-entity e1 e2)))
      (multiple-value-bind (r1 g1 b1 a1)
          (compute-connection-beam-color conn 0.0 :time 0.0)
        (declare (ignore r1 g1 b1))
        (multiple-value-bind (r2 g2 b2 a2)
            (compute-connection-beam-color conn 0.5 :time 0.0)
          (declare (ignore r2 g2 b2))
          ;; Different progress should give different alpha at least
          (is (not (= a1 a2))))))))

(test compute-connection-beam-color-kind-affects-output
  "Test that different connection kinds produce different beam colors."
  (init-holodeck-storage)
  (let ((e1 (make-snapshot-entity "s1" :snapshot :x 0.0 :y 0.0 :z 0.0))
        (e2 (make-snapshot-entity "s2" :snapshot :x 5.0 :y 0.0 :z 0.0)))
    (let ((conn-temporal (make-connection-entity e1 e2 :kind :temporal))
          (conn-fork (make-connection-entity e1 e2 :kind :fork)))
      (multiple-value-bind (tr tg tb ta)
          (compute-connection-beam-color conn-temporal 0.5 :time 0.0)
        (declare (ignore ta))
        (multiple-value-bind (fr fg fb fa)
            (compute-connection-beam-color conn-fork 0.5 :time 0.0)
          (declare (ignore fa))
          ;; Temporal (blue) and fork (purple) should differ
          (is (not (and (< (abs (- tr fr)) 0.01)
                        (< (abs (- tg fg)) 0.01)
                        (< (abs (- tb fb)) 0.01)))))))))

;;; ===================================================================
;;; Orbit Camera Tests
;;; ===================================================================

(def-suite camera-tests
  :in holodeck-tests
  :description "Tests for orbit-camera class and operations")

(in-suite camera-tests)

;; --- Construction ---

(test orbit-camera-creation-defaults
  "Test that orbit-camera is created with correct defaults."
  (let ((cam (make-orbit-camera)))
    (is (= 0.0 (camera-theta cam)))
    (is (< (abs (- (camera-phi cam) 0.3)) 0.001))
    (is (= 30.0 (camera-distance cam)))
    (is (= 60.0 (camera-fov cam)))
    (is (< (abs (- (camera-near-plane cam) 0.1)) 0.001))
    (is (= 1000.0 (camera-far-plane cam)))
    (is (= 5.0 (camera-min-distance cam)))
    (is (= 200.0 (camera-max-distance cam)))))

(test orbit-camera-creation-custom
  "Test that orbit-camera accepts custom parameters."
  (let ((cam (make-orbit-camera :theta 1.0 :phi 0.5 :distance 50.0
                                :fov 45.0 :near 1.0 :far 500.0
                                :min-distance 10.0 :max-distance 100.0)))
    (is (= 1.0 (camera-theta cam)))
    (is (= 0.5 (camera-phi cam)))
    (is (= 50.0 (camera-distance cam)))
    (is (= 45.0 (camera-fov cam)))
    (is (= 1.0 (camera-near-plane cam)))
    (is (= 500.0 (camera-far-plane cam)))
    (is (= 10.0 (camera-min-distance cam)))
    (is (= 100.0 (camera-max-distance cam)))))

;; --- Position Computation ---

(test camera-position-at-origin-target
  "Test camera position with theta=0, phi=0 orbits along +Z axis."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 10.0))
         (pos (camera-position cam)))
    ;; At theta=0, phi=0: offset is (0, 0, distance), so position is (0, 0, 10)
    (is (< (abs (3d-vectors:vx pos)) 0.001))
    (is (< (abs (3d-vectors:vy pos)) 0.001))
    (is (< (abs (- (3d-vectors:vz pos) 10.0)) 0.001))))

(test camera-position-theta-pi-half
  "Test camera position at theta=pi/2 orbits along +X axis."
  (let* ((cam (make-orbit-camera :theta (coerce (/ pi 2) 'single-float)
                                 :phi 0.0 :distance 10.0))
         (pos (camera-position cam)))
    ;; At theta=pi/2, phi=0: offset is (distance, 0, 0)
    (is (< (abs (- (3d-vectors:vx pos) 10.0)) 0.01))
    (is (< (abs (3d-vectors:vy pos)) 0.01))
    (is (< (abs (3d-vectors:vz pos)) 0.01))))

(test camera-position-phi-positive
  "Test that positive phi elevates camera above XZ plane."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.5 :distance 10.0))
         (pos (camera-position cam)))
    ;; Positive phi should put camera above XZ plane
    (is (> (3d-vectors:vy pos) 0.0))))

(test camera-position-with-target-offset
  "Test camera position is offset from non-origin target."
  (let* ((target (3d-vectors:vec3 10.0 5.0 3.0))
         (cam (make-orbit-camera :target target :theta 0.0 :phi 0.0 :distance 20.0))
         (pos (camera-position cam)))
    ;; Position should be target + offset
    (is (< (abs (- (3d-vectors:vx pos) 10.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy pos) 5.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz pos) 23.0)) 0.001))))

(test camera-position-distance-matches
  "Test that distance from position to target equals camera-distance."
  (let* ((cam (make-orbit-camera :theta 0.7 :phi 0.4 :distance 25.0))
         (pos (camera-position cam))
         (diff (3d-vectors:v- pos (camera-target cam)))
         (dist (3d-vectors:vlength diff)))
    (is (< (abs (- dist 25.0)) 0.01))))

;; --- Direction Vectors ---

(test camera-forward-points-at-target
  "Test that forward vector points from camera toward target."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 10.0))
         (fwd (camera-forward cam)))
    ;; Forward should point toward target (origin), so in -Z direction
    (is (< (3d-vectors:vz fwd) 0.0))
    ;; Should be unit length
    (is (< (abs (- (3d-vectors:vlength fwd) 1.0)) 0.001))))

(test camera-right-perpendicular-to-forward
  "Test that right vector is perpendicular to forward."
  (let* ((cam (make-orbit-camera :theta 0.5 :phi 0.3 :distance 20.0))
         (fwd (camera-forward cam))
         (right (camera-right cam))
         (dot (+ (* (3d-vectors:vx fwd) (3d-vectors:vx right))
                 (* (3d-vectors:vy fwd) (3d-vectors:vy right))
                 (* (3d-vectors:vz fwd) (3d-vectors:vz right)))))
    ;; Dot product should be ~0 (perpendicular)
    (is (< (abs dot) 0.01))))

;; --- Orbit Operation ---

(test orbit-changes-theta
  "Test that orbit-camera-by changes theta angle."
  (let ((cam (make-orbit-camera :theta 0.0 :orbit-speed 0.01)))
    (orbit-camera-by cam 100.0 0.0)
    ;; theta should have increased by 100 * 0.01 = 1.0
    (is (< (abs (- (camera-theta cam) 1.0)) 0.001))))

(test orbit-changes-phi
  "Test that orbit-camera-by changes phi angle."
  (let ((cam (make-orbit-camera :phi 0.0 :orbit-speed 0.01)))
    (orbit-camera-by cam 0.0 50.0)
    ;; phi should have increased by 50 * 0.01 = 0.5
    (is (< (abs (- (camera-phi cam) 0.5)) 0.001))))

(test orbit-clamps-phi
  "Test that phi is clamped to avoid gimbal lock."
  (let ((cam (make-orbit-camera :phi 0.0 :orbit-speed 1.0)))
    ;; Large positive delta should clamp to *phi-max*
    (orbit-camera-by cam 0.0 100.0)
    (is (<= (camera-phi cam) *phi-max*))
    ;; Large negative delta should clamp to *phi-min*
    (orbit-camera-by cam 0.0 -200.0)
    (is (>= (camera-phi cam) *phi-min*))))

(test orbit-preserves-distance
  "Test that orbiting does not change distance from target."
  (let ((cam (make-orbit-camera :distance 25.0)))
    (orbit-camera-by cam 50.0 30.0)
    (is (= 25.0 (camera-distance cam)))))

;; --- Zoom Operation ---

(test zoom-in-decreases-distance
  "Test that positive zoom delta decreases distance."
  (let ((cam (make-orbit-camera :distance 30.0 :zoom-speed 1.0)))
    (zoom-camera-by cam 5.0)
    (is (< (camera-distance cam) 30.0))))

(test zoom-out-increases-distance
  "Test that negative zoom delta increases distance."
  (let ((cam (make-orbit-camera :distance 30.0 :zoom-speed 1.0)))
    (zoom-camera-by cam -5.0)
    (is (> (camera-distance cam) 30.0))))

(test zoom-clamps-min-distance
  "Test that zoom cannot go below min-distance."
  (let ((cam (make-orbit-camera :distance 10.0 :min-distance 5.0 :zoom-speed 1.0)))
    (zoom-camera-by cam 100.0)  ; Try to zoom way in
    (is (>= (camera-distance cam) 5.0))))

(test zoom-clamps-max-distance
  "Test that zoom cannot exceed max-distance."
  (let ((cam (make-orbit-camera :distance 100.0 :max-distance 200.0 :zoom-speed 1.0)))
    (zoom-camera-by cam -500.0)  ; Try to zoom way out
    (is (<= (camera-distance cam) 200.0))))

(test zoom-preserves-angles
  "Test that zooming does not change theta or phi."
  (let ((cam (make-orbit-camera :theta 0.5 :phi 0.3)))
    (zoom-camera-by cam 5.0)
    (is (= 0.5 (camera-theta cam)))
    (is (< (abs (- (camera-phi cam) 0.3)) 0.001))))

;; --- Pan Operation ---

(test pan-moves-target
  "Test that panning moves the target point."
  (let* ((cam (make-orbit-camera :pan-speed 0.1))
         (old-target (3d-vectors:vcopy (camera-target cam))))
    (pan-camera-by cam 10.0 10.0)
    ;; Target should have moved
    (let ((diff (3d-vectors:v- (camera-target cam) old-target)))
      (is (> (3d-vectors:vlength diff) 0.01)))))

(test pan-preserves-distance
  "Test that panning preserves distance from target."
  (let ((cam (make-orbit-camera :distance 25.0)))
    (pan-camera-by cam 20.0 15.0)
    ;; Distance should still be 25.0
    (is (= 25.0 (camera-distance cam)))))

(test pan-preserves-angles
  "Test that panning preserves theta and phi."
  (let ((cam (make-orbit-camera :theta 0.7 :phi 0.4)))
    (pan-camera-by cam 10.0 5.0)
    (is (= 0.7 (camera-theta cam)))
    (is (< (abs (- (camera-phi cam) 0.4)) 0.001))))

;; --- View Matrix ---

(test view-matrix-produces-mat4
  "Test that camera-view-matrix-data returns a mat4."
  (let* ((cam (make-orbit-camera))
         (mat (camera-view-matrix-data cam)))
    (is (typep mat '3d-matrices:mat4))))

(test view-matrix-identity-like-at-default
  "Test view matrix has reasonable values at default camera position."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 10.0))
         (mat (camera-view-matrix-data cam)))
    ;; Matrix should exist and be non-zero
    (is (not (null mat)))
    ;; Bottom-right element (flat index 15) of a valid view matrix is 1.0
    (is (< (abs (- (3d-matrices:miref mat 15) 1.0)) 0.001))))

;; --- Projection Matrix ---

(test projection-matrix-produces-mat4
  "Test that camera-projection-matrix-data returns a mat4."
  (let* ((cam (make-orbit-camera))
         (mat (camera-projection-matrix-data cam (/ 16.0 9.0))))
    (is (typep mat '3d-matrices:mat4))))

(test projection-matrix-bottom-right-element
  "Test projection matrix has expected bottom-right value."
  (let* ((cam (make-orbit-camera :fov 60.0 :near 0.1 :far 1000.0))
         (mat (camera-projection-matrix-data cam 1.0)))
    ;; For a perspective matrix, element [3][3] (flat index 15) should be 0.0
    (is (< (abs (3d-matrices:miref mat 15)) 0.001))))

;; --- Sync Camera State ---

(test sync-camera-state-updates-global
  "Test that sync-camera-state updates *camera-position*."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 20.0))
         (old-pos (3d-vectors:vcopy *camera-position*)))
    (sync-camera-state cam)
    ;; *camera-position* should now match the camera's computed position
    (let ((cam-pos (camera-position cam)))
      (is (< (abs (- (3d-vectors:vx *camera-position*) (3d-vectors:vx cam-pos))) 0.001))
      (is (< (abs (- (3d-vectors:vy *camera-position*) (3d-vectors:vy cam-pos))) 0.001))
      (is (< (abs (- (3d-vectors:vz *camera-position*) (3d-vectors:vz cam-pos))) 0.001)))))

;; --- Combined Operations ---

(test orbit-then-zoom-preserves-target
  "Test that orbit followed by zoom keeps the same target."
  (let* ((target (3d-vectors:vec3 5.0 3.0 1.0))
         (cam (make-orbit-camera :target target)))
    (orbit-camera-by cam 30.0 15.0)
    (zoom-camera-by cam 3.0)
    ;; Target should be unchanged
    (is (< (abs (- (3d-vectors:vx (camera-target cam)) 5.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy (camera-target cam)) 3.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz (camera-target cam)) 1.0)) 0.001))))

(test full-orbit-returns-to-start
  "Test that orbiting 2*pi in theta returns to approximately same position."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 10.0 :orbit-speed 1.0))
         (start-pos (camera-position cam)))
    ;; Orbit by 2*pi in theta
    (orbit-camera-by cam (coerce (* 2 pi) 'single-float) 0.0)
    (let ((end-pos (camera-position cam)))
      ;; Should be back to approximately the same position
      (is (< (abs (- (3d-vectors:vx end-pos) (3d-vectors:vx start-pos))) 0.1))
      (is (< (abs (- (3d-vectors:vy end-pos) (3d-vectors:vy start-pos))) 0.1))
      (is (< (abs (- (3d-vectors:vz end-pos) (3d-vectors:vz start-pos))) 0.1)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Fly Camera Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite fly-camera-tests
  :in holodeck-tests
  :description "Tests for fly-camera class and operations")

(in-suite fly-camera-tests)

;; --- Construction ---

(test fly-camera-creation-defaults
  "Test that fly-camera is created with correct defaults."
  (let ((cam (make-fly-camera)))
    (is (= 0.0 (fly-camera-yaw cam)))
    (is (= 0.0 (fly-camera-pitch cam)))
    (is (= 20.0 (fly-camera-speed cam)))
    (is (< (abs (- (fly-camera-sensitivity cam) 0.003)) 0.0001))
    (is (< (abs (- (fly-camera-damping cam) 0.9)) 0.001))
    (is (= 60.0 (fly-camera-fov cam)))
    (is (< (abs (- (fly-camera-near-plane cam) 0.1)) 0.001))
    (is (= 1000.0 (fly-camera-far-plane cam)))))

(test fly-camera-creation-custom
  "Test that fly-camera accepts custom parameters."
  (let ((cam (make-fly-camera :position (3d-vectors:vec3 1.0 2.0 3.0)
                              :yaw 1.0 :pitch 0.5
                              :speed 10.0 :sensitivity 0.01
                              :damping 0.8 :fov 45.0
                              :near 1.0 :far 500.0)))
    (is (= 1.0 (fly-camera-yaw cam)))
    (is (= 0.5 (fly-camera-pitch cam)))
    (is (= 10.0 (fly-camera-speed cam)))
    (is (< (abs (- (fly-camera-sensitivity cam) 0.01)) 0.0001))
    (is (< (abs (- (fly-camera-damping cam) 0.8)) 0.001))
    (is (= 45.0 (fly-camera-fov cam)))
    (is (= 1.0 (fly-camera-near-plane cam)))
    (is (= 500.0 (fly-camera-far-plane cam)))
    ;; Check position
    (let ((pos (fly-camera-position-vec cam)))
      (is (< (abs (- (3d-vectors:vx pos) 1.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy pos) 2.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz pos) 3.0)) 0.001)))))

;; --- Position ---

(test fly-camera-position-returns-stored-position
  "Test that camera-position returns the fly camera's position."
  (let* ((pos (3d-vectors:vec3 5.0 10.0 15.0))
         (cam (make-fly-camera :position pos))
         (result (camera-position cam)))
    (is (< (abs (- (3d-vectors:vx result) 5.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy result) 10.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz result) 15.0)) 0.001))))

;; --- Direction Vectors ---

(test fly-camera-forward-default-looks-negative-z
  "Test that default yaw=0, pitch=0 looks along -Z."
  (let* ((cam (make-fly-camera :yaw 0.0 :pitch 0.0))
         (fwd (camera-forward cam)))
    (is (< (abs (3d-vectors:vx fwd)) 0.001))
    (is (< (abs (3d-vectors:vy fwd)) 0.001))
    (is (< (3d-vectors:vz fwd) -0.9))))

(test fly-camera-forward-is-unit-length
  "Test that forward vector is normalized."
  (let* ((cam (make-fly-camera :yaw 0.7 :pitch 0.3))
         (fwd (camera-forward cam)))
    (is (< (abs (- (3d-vectors:vlength fwd) 1.0)) 0.001))))

(test fly-camera-forward-yaw-rotates
  "Test that yaw=pi/2 rotates forward toward -X."
  (let* ((cam (make-fly-camera :yaw (coerce (/ pi 2) 'single-float) :pitch 0.0))
         (fwd (camera-forward cam)))
    ;; sin(pi/2)=1, so forward X component should be -1
    (is (< (3d-vectors:vx fwd) -0.9))
    (is (< (abs (3d-vectors:vy fwd)) 0.01))
    (is (< (abs (3d-vectors:vz fwd)) 0.01))))

(test fly-camera-forward-pitch-up
  "Test that positive pitch tilts forward upward."
  (let* ((cam (make-fly-camera :yaw 0.0 :pitch 0.5))
         (fwd (camera-forward cam)))
    (is (> (3d-vectors:vy fwd) 0.0))))

(test fly-camera-right-perpendicular-to-forward
  "Test that right vector is perpendicular to forward."
  (let* ((cam (make-fly-camera :yaw 0.5 :pitch 0.3))
         (fwd (camera-forward cam))
         (right (camera-right cam))
         (dot (+ (* (3d-vectors:vx fwd) (3d-vectors:vx right))
                 (* (3d-vectors:vy fwd) (3d-vectors:vy right))
                 (* (3d-vectors:vz fwd) (3d-vectors:vz right)))))
    (is (< (abs dot) 0.01))))

(test fly-camera-right-is-unit-length
  "Test that right vector is normalized."
  (let* ((cam (make-fly-camera :yaw 0.5 :pitch 0.3))
         (right (camera-right cam)))
    (is (< (abs (- (3d-vectors:vlength right) 1.0)) 0.001))))

;; --- Look Operation ---

(test fly-camera-look-changes-yaw
  "Test that fly-camera-look changes yaw angle."
  (let ((cam (make-fly-camera :yaw 0.0 :sensitivity 0.01)))
    (fly-camera-look cam 100.0 0.0)
    ;; yaw should increase by 100 * 0.01 = 1.0
    (is (< (abs (- (fly-camera-yaw cam) 1.0)) 0.001))))

(test fly-camera-look-changes-pitch
  "Test that fly-camera-look changes pitch angle."
  (let ((cam (make-fly-camera :pitch 0.0 :sensitivity 0.01)))
    (fly-camera-look cam 0.0 50.0)
    ;; pitch should increase by 50 * 0.01 = 0.5
    (is (< (abs (- (fly-camera-pitch cam) 0.5)) 0.001))))

(test fly-camera-look-clamps-pitch
  "Test that pitch is clamped to avoid flipping."
  (let ((cam (make-fly-camera :pitch 0.0 :sensitivity 1.0)))
    (fly-camera-look cam 0.0 100.0)
    (is (<= (fly-camera-pitch cam) *pitch-max*))
    (fly-camera-look cam 0.0 -200.0)
    (is (>= (fly-camera-pitch cam) *pitch-min*))))

;; --- Movement ---

(test fly-camera-move-forward-adds-velocity
  "Test that moving forward adds velocity in forward direction."
  (let ((cam (make-fly-camera :speed 10.0)))
    (fly-camera-move cam :forward)
    (let ((vel (fly-camera-velocity cam)))
      (is (> (3d-vectors:vlength vel) 0.0)))))

(test fly-camera-move-backward-adds-negative-velocity
  "Test that moving backward adds velocity opposite to forward."
  (let ((cam (make-fly-camera :yaw 0.0 :pitch 0.0 :speed 10.0)))
    (fly-camera-move cam :backward)
    (let ((vel (fly-camera-velocity cam)))
      ;; Forward is -Z at default yaw/pitch, so backward should be +Z
      (is (> (3d-vectors:vz vel) 0.0)))))

(test fly-camera-move-all-directions
  "Test that all six directions produce non-zero velocity."
  (dolist (dir '(:forward :backward :left :right :up :down))
    (let ((cam (make-fly-camera :speed 10.0)))
      (fly-camera-move cam dir)
      (is (> (3d-vectors:vlength (fly-camera-velocity cam)) 0.0)
          "Direction ~a should produce velocity" dir))))

;; --- Update ---

(test fly-camera-update-moves-position
  "Test that update moves position by velocity * dt."
  (let ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 0.0 0.0)
                              :speed 10.0 :damping 1.0)))
    ;; Set velocity directly
    (setf (fly-camera-velocity cam) (3d-vectors:vec3 10.0 0.0 0.0))
    (fly-camera-update cam 1.0)
    ;; Position should have moved by (10, 0, 0) * 1.0 = (10, 0, 0)
    (let ((pos (fly-camera-position-vec cam)))
      (is (< (abs (- (3d-vectors:vx pos) 10.0)) 0.01)))))

(test fly-camera-update-applies-damping
  "Test that update reduces velocity by damping factor."
  (let ((cam (make-fly-camera :damping 0.5)))
    (setf (fly-camera-velocity cam) (3d-vectors:vec3 10.0 0.0 0.0))
    (fly-camera-update cam 0.01)
    ;; Velocity should be halved after damping
    (let ((vel (fly-camera-velocity cam)))
      (is (< (abs (- (3d-vectors:vx vel) 5.0)) 0.01)))))

(test fly-camera-update-zero-dt-no-movement
  "Test that zero dt produces no position change."
  (let ((cam (make-fly-camera :position (3d-vectors:vec3 5.0 5.0 5.0))))
    (setf (fly-camera-velocity cam) (3d-vectors:vec3 100.0 0.0 0.0))
    (fly-camera-update cam 0.0)
    (let ((pos (fly-camera-position-vec cam)))
      (is (< (abs (- (3d-vectors:vx pos) 5.0)) 0.001)))))

;; --- Stop ---

(test fly-camera-stop-zeroes-velocity
  "Test that fly-camera-stop sets velocity to zero."
  (let ((cam (make-fly-camera)))
    (setf (fly-camera-velocity cam) (3d-vectors:vec3 10.0 5.0 3.0))
    (fly-camera-stop cam)
    (let ((vel (fly-camera-velocity cam)))
      (is (< (3d-vectors:vlength vel) 0.001)))))

;; --- View Matrix ---

(test fly-camera-view-matrix-produces-mat4
  "Test that camera-view-matrix-data returns a mat4."
  (let* ((cam (make-fly-camera))
         (mat (camera-view-matrix-data cam)))
    (is (typep mat '3d-matrices:mat4))))

(test fly-camera-view-matrix-bottom-right-element
  "Test that fly camera view matrix has 1.0 at bottom-right."
  (let* ((cam (make-fly-camera))
         (mat (camera-view-matrix-data cam)))
    (is (< (abs (- (3d-matrices:miref mat 15) 1.0)) 0.001))))

;; --- Projection Matrix ---

(test fly-camera-projection-matrix-produces-mat4
  "Test that camera-projection-matrix-data returns a mat4."
  (let* ((cam (make-fly-camera))
         (mat (camera-projection-matrix-data cam (/ 16.0 9.0))))
    (is (typep mat '3d-matrices:mat4))))

;; --- Sync Camera State ---

(test fly-camera-sync-state-updates-global
  "Test that sync-camera-state updates *camera-position*."
  (let* ((cam (make-fly-camera :position (3d-vectors:vec3 7.0 8.0 9.0))))
    (sync-camera-state cam)
    (is (< (abs (- (3d-vectors:vx *camera-position*) 7.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy *camera-position*) 8.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz *camera-position*) 9.0)) 0.001))))

;; --- Integration ---

(test fly-camera-move-then-update
  "Test that move + update moves the camera in the right direction."
  (let ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 0.0 0.0)
                              :yaw 0.0 :pitch 0.0
                              :speed 10.0 :damping 1.0)))
    (fly-camera-move cam :forward)
    (fly-camera-update cam 1.0)
    ;; At yaw=0, pitch=0, forward is -Z, so position Z should decrease
    (let ((pos (fly-camera-position-vec cam)))
      (is (< (3d-vectors:vz pos) 0.0)))))

(test fly-camera-look-then-move-forward
  "Test that looking right then moving forward changes direction."
  (let ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 0.0 0.0)
                              :yaw 0.0 :pitch 0.0
                              :speed 10.0 :sensitivity 1.0 :damping 1.0)))
    ;; Look right (increase yaw by pi/2)
    (fly-camera-look cam (coerce (/ pi 2) 'single-float) 0.0)
    (fly-camera-move cam :forward)
    (fly-camera-update cam 1.0)
    ;; After yaw=pi/2, forward is -X direction, so X should decrease
    (let ((pos (fly-camera-position-vec cam)))
      (is (< (3d-vectors:vx pos) -1.0)))))

;;; ===================================================================
;;; Easing Function Tests
;;; ===================================================================

(def-suite easing-tests
  :in holodeck-tests
  :description "Tests for easing functions used in camera transitions")

(in-suite easing-tests)

(test ease-linear-endpoints
  "Test linear easing returns 0 at t=0 and 1 at t=1."
  (is (< (abs (ease-linear 0.0)) 0.001))
  (is (< (abs (- (ease-linear 1.0) 1.0)) 0.001)))

(test ease-linear-midpoint
  "Test linear easing returns 0.5 at t=0.5."
  (is (< (abs (- (ease-linear 0.5) 0.5)) 0.001)))

(test ease-linear-clamping
  "Test linear easing clamps out-of-range values."
  (is (< (abs (ease-linear -0.5)) 0.001))
  (is (< (abs (- (ease-linear 1.5) 1.0)) 0.001)))

(test ease-in-quad-endpoints
  "Test quadratic ease-in at endpoints."
  (is (< (abs (ease-in-quad 0.0)) 0.001))
  (is (< (abs (- (ease-in-quad 1.0) 1.0)) 0.001)))

(test ease-in-quad-slow-start
  "Test quadratic ease-in is slow at the beginning."
  ;; At t=0.25, output should be 0.0625 (much less than 0.25)
  (is (< (ease-in-quad 0.25) 0.1)))

(test ease-out-quad-endpoints
  "Test quadratic ease-out at endpoints."
  (is (< (abs (ease-out-quad 0.0)) 0.001))
  (is (< (abs (- (ease-out-quad 1.0) 1.0)) 0.001)))

(test ease-out-quad-fast-start
  "Test quadratic ease-out is fast at the beginning."
  ;; At t=0.25, output should be 0.4375 (more than 0.25)
  (is (> (ease-out-quad 0.25) 0.3)))

(test ease-in-out-quad-endpoints
  "Test quadratic ease-in-out at endpoints."
  (is (< (abs (ease-in-out-quad 0.0)) 0.001))
  (is (< (abs (- (ease-in-out-quad 1.0) 1.0)) 0.001)))

(test ease-in-out-quad-symmetry
  "Test quadratic ease-in-out passes through 0.5 at t=0.5."
  (is (< (abs (- (ease-in-out-quad 0.5) 0.5)) 0.001)))

(test ease-in-cubic-endpoints
  "Test cubic ease-in at endpoints."
  (is (< (abs (ease-in-cubic 0.0)) 0.001))
  (is (< (abs (- (ease-in-cubic 1.0) 1.0)) 0.001)))

(test ease-out-cubic-endpoints
  "Test cubic ease-out at endpoints."
  (is (< (abs (ease-out-cubic 0.0)) 0.001))
  (is (< (abs (- (ease-out-cubic 1.0) 1.0)) 0.001)))

(test ease-out-cubic-fast-start
  "Test cubic ease-out is faster at the beginning than linear."
  (is (> (ease-out-cubic 0.25) 0.4)))

(test ease-in-out-cubic-endpoints
  "Test cubic ease-in-out at endpoints."
  (is (< (abs (ease-in-out-cubic 0.0)) 0.001))
  (is (< (abs (- (ease-in-out-cubic 1.0) 1.0)) 0.001)))

(test ease-in-out-cubic-symmetry
  "Test cubic ease-in-out passes through 0.5 at t=0.5."
  (is (< (abs (- (ease-in-out-cubic 0.5) 0.5)) 0.001)))

(test apply-easing-dispatches
  "Test that apply-easing dispatches to the correct function."
  (is (< (abs (- (apply-easing :linear 0.5) 0.5)) 0.001))
  (is (< (abs (- (apply-easing :ease-out-cubic 0.0) 0.0)) 0.001))
  (is (< (abs (- (apply-easing :ease-in-quad 1.0) 1.0)) 0.001)))

(test apply-easing-monotonic
  "Test that all easing functions are monotonically increasing."
  (dolist (easing '(:linear :ease-in-quad :ease-out-quad :ease-in-out-quad
                    :ease-in-cubic :ease-out-cubic :ease-in-out-cubic))
    (let ((prev 0.0))
      (dotimes (i 100)
        (let* ((tt (/ (float (1+ i)) 100.0))
               (val (apply-easing easing tt)))
          (is (>= val prev)
              (format nil "~a not monotonic at t=~f: ~f < ~f" easing tt val prev))
          (setf prev val))))))

;;; ===================================================================
;;; Vec3-Lerp Tests
;;; ===================================================================

(def-suite vec3-lerp-tests
  :in holodeck-tests
  :description "Tests for vec3 linear interpolation")

(in-suite vec3-lerp-tests)

(test vec3-lerp-at-zero
  "Test vec3-lerp returns A when t=0."
  (let* ((a (3d-vectors:vec3 1.0 2.0 3.0))
         (b (3d-vectors:vec3 4.0 5.0 6.0))
         (result (vec3-lerp a b 0.0)))
    (is (< (abs (- (3d-vectors:vx result) 1.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy result) 2.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz result) 3.0)) 0.001))))

(test vec3-lerp-at-one
  "Test vec3-lerp returns B when t=1."
  (let* ((a (3d-vectors:vec3 1.0 2.0 3.0))
         (b (3d-vectors:vec3 4.0 5.0 6.0))
         (result (vec3-lerp a b 1.0)))
    (is (< (abs (- (3d-vectors:vx result) 4.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy result) 5.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz result) 6.0)) 0.001))))

(test vec3-lerp-at-half
  "Test vec3-lerp returns midpoint at t=0.5."
  (let* ((a (3d-vectors:vec3 0.0 0.0 0.0))
         (b (3d-vectors:vec3 10.0 20.0 30.0))
         (result (vec3-lerp a b 0.5)))
    (is (< (abs (- (3d-vectors:vx result) 5.0)) 0.001))
    (is (< (abs (- (3d-vectors:vy result) 10.0)) 0.001))
    (is (< (abs (- (3d-vectors:vz result) 15.0)) 0.001))))

;;; ===================================================================
;;; Camera Transition Tests
;;; ===================================================================

(def-suite camera-transition-tests
  :in holodeck-tests
  :description "Tests for smooth camera transitions with easing")

(in-suite camera-transition-tests)

;; --- Camera Transition Class ---

(test camera-transition-creation
  "Test that camera-transition is created with correct values."
  (let* ((start-pos (3d-vectors:vec3 0.0 5.0 30.0))
         (end-pos (3d-vectors:vec3 10.0 3.0 10.0))
         (start-tgt (3d-vectors:vec3 0.0 0.0 0.0))
         (end-tgt (3d-vectors:vec3 10.0 0.0 0.0))
         (trans (make-camera-transition
                 :start-position start-pos
                 :end-position end-pos
                 :start-target start-tgt
                 :end-target end-tgt
                 :duration 2.0
                 :easing :ease-in-quad)))
    (is (= 2.0 (transition-duration trans)))
    (is (= 0.0 (transition-elapsed trans)))
    (is (eq :ease-in-quad (transition-easing trans)))))

(test camera-transition-not-complete-initially
  "Test that a new transition is not complete."
  (let ((trans (make-camera-transition :duration 1.0)))
    (is (not (camera-transition-complete-p trans)))))

(test camera-transition-progress-zero-initially
  "Test that progress is 0 for a new transition."
  (let ((trans (make-camera-transition :duration 1.0)))
    (is (< (abs (camera-transition-progress trans)) 0.001))))

(test camera-transition-completes-after-duration
  "Test that transition completes after enough time."
  (let ((trans (make-camera-transition :duration 1.0)))
    (advance-camera-transition trans 1.0)
    (is (camera-transition-complete-p trans))))

(test camera-transition-progress-at-half
  "Test progress is ~0.5 at half the duration."
  (let ((trans (make-camera-transition :duration 2.0)))
    (advance-camera-transition trans 1.0)
    (is (< (abs (- (camera-transition-progress trans) 0.5)) 0.001))))

(test camera-transition-minimum-duration
  "Test that duration is clamped to a minimum positive value."
  (let ((trans (make-camera-transition :duration 0.0)))
    ;; Should not be zero to avoid division by zero
    (is (> (transition-duration trans) 0.0))))

;; --- Advance Transition ---

(test advance-transition-interpolates-position
  "Test that advancing a transition interpolates position."
  (let* ((start (3d-vectors:vec3 0.0 0.0 0.0))
         (end (3d-vectors:vec3 10.0 0.0 0.0))
         (trans (make-camera-transition
                 :start-position start
                 :end-position end
                 :duration 1.0
                 :easing :linear)))
    (multiple-value-bind (pos tgt)
        (advance-camera-transition trans 0.5)
      (declare (ignore tgt))
      ;; With linear easing at 50%, should be at 5.0
      (is (< (abs (- (3d-vectors:vx pos) 5.0)) 0.001)))))

(test advance-transition-interpolates-target
  "Test that advancing a transition interpolates target."
  (let* ((start-tgt (3d-vectors:vec3 0.0 0.0 0.0))
         (end-tgt (3d-vectors:vec3 0.0 10.0 0.0))
         (trans (make-camera-transition
                 :start-target start-tgt
                 :end-target end-tgt
                 :duration 1.0
                 :easing :linear)))
    (multiple-value-bind (pos tgt)
        (advance-camera-transition trans 0.5)
      (declare (ignore pos))
      (is (< (abs (- (3d-vectors:vy tgt) 5.0)) 0.001)))))

(test advance-transition-reaches-end
  "Test that a completed transition returns the end values."
  (let* ((end-pos (3d-vectors:vec3 10.0 20.0 30.0))
         (end-tgt (3d-vectors:vec3 5.0 5.0 5.0))
         (trans (make-camera-transition
                 :end-position end-pos
                 :end-target end-tgt
                 :duration 1.0
                 :easing :linear)))
    (multiple-value-bind (pos tgt)
        (advance-camera-transition trans 2.0)
      (is (< (abs (- (3d-vectors:vx pos) 10.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy pos) 20.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz pos) 30.0)) 0.001))
      (is (< (abs (- (3d-vectors:vx tgt) 5.0)) 0.001)))))

(test advance-transition-uses-easing
  "Test that non-linear easing produces different results than linear."
  (let* ((start (3d-vectors:vec3 0.0 0.0 0.0))
         (end (3d-vectors:vec3 100.0 0.0 0.0))
         (trans-linear (make-camera-transition
                        :start-position start :end-position end
                        :duration 1.0 :easing :linear))
         (trans-eased (make-camera-transition
                       :start-position start :end-position end
                       :duration 1.0 :easing :ease-in-cubic)))
    (multiple-value-bind (pos-l tgt-l)
        (advance-camera-transition trans-linear 0.5)
      (declare (ignore tgt-l))
      (multiple-value-bind (pos-e tgt-e)
          (advance-camera-transition trans-eased 0.5)
        (declare (ignore tgt-e))
        ;; Ease-in-cubic at t=0.5 should be 0.125 * 100 = 12.5, not 50.0
        (is (not (< (abs (- (3d-vectors:vx pos-l) (3d-vectors:vx pos-e))) 0.1)))))))

;; --- Animate Camera To ---

(test animate-orbit-camera-to-creates-transition
  "Test that animate-camera-to creates a valid transition for orbit camera."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 30.0))
         (end-pos (3d-vectors:vec3 5.0 3.0 10.0))
         (end-tgt (3d-vectors:vec3 5.0 0.0 0.0))
         (trans (animate-camera-to cam end-pos end-tgt :duration 1.5)))
    (is (typep trans 'camera-transition))
    (is (= 1.5 (transition-duration trans)))
    ;; Start position should match camera's current position
    (let ((cam-pos (camera-position cam))
          (start-pos (transition-start-position trans)))
      (is (< (abs (- (3d-vectors:vx cam-pos) (3d-vectors:vx start-pos))) 0.001)))
    ;; Start target should match camera's current target
    (let ((cam-tgt (camera-target cam))
          (start-tgt (transition-start-target trans)))
      (is (< (abs (- (3d-vectors:vx cam-tgt) (3d-vectors:vx start-tgt))) 0.001)))))

(test animate-fly-camera-to-creates-transition
  "Test that animate-camera-to creates a valid transition for fly camera."
  (let* ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 5.0 30.0)))
         (end-pos (3d-vectors:vec3 10.0 3.0 10.0))
         (end-tgt (3d-vectors:vec3 10.0 0.0 0.0))
         (trans (animate-camera-to cam end-pos end-tgt :duration 2.0)))
    (is (typep trans 'camera-transition))
    (is (= 2.0 (transition-duration trans)))
    ;; Start position should match fly camera's current position
    (let ((start-pos (transition-start-position trans)))
      (is (< (abs (- (3d-vectors:vx start-pos) 0.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy start-pos) 5.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz start-pos) 30.0)) 0.001)))))

;; --- Apply Camera Transition ---

(test apply-transition-to-orbit-camera
  "Test applying a transition updates orbit camera state."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 30.0))
         (end-pos (3d-vectors:vec3 5.0 3.0 10.0))
         (end-tgt (3d-vectors:vec3 5.0 0.0 0.0))
         (trans (animate-camera-to cam end-pos end-tgt
                                   :duration 1.0 :easing :linear)))
    ;; Apply half the transition
    (let ((active (apply-camera-transition cam trans 0.5)))
      (is (eq t active))  ; Should still be active
      ;; Camera target should have moved toward end-tgt
      (let ((tgt (camera-target cam)))
        (is (> (3d-vectors:vx tgt) 0.1))))))

(test apply-transition-to-orbit-camera-completes
  "Test that orbit camera transition completes and returns NIL."
  (let* ((cam (make-orbit-camera))
         (end-pos (3d-vectors:vec3 5.0 3.0 10.0))
         (end-tgt (3d-vectors:vec3 5.0 0.0 0.0))
         (trans (animate-camera-to cam end-pos end-tgt :duration 0.5)))
    (let ((active (apply-camera-transition cam trans 1.0)))
      (is (null active)))))

(test apply-transition-to-fly-camera
  "Test applying a transition updates fly camera state."
  (let* ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 0.0 0.0)))
         (end-pos (3d-vectors:vec3 10.0 0.0 0.0))
         (end-tgt (3d-vectors:vec3 20.0 0.0 0.0))
         (trans (animate-camera-to cam end-pos end-tgt
                                   :duration 1.0 :easing :linear)))
    (apply-camera-transition cam trans 1.0)
    ;; Position should now be at end-pos
    (let ((pos (fly-camera-position-vec cam)))
      (is (< (abs (- (3d-vectors:vx pos) 10.0)) 0.01)))))

(test apply-transition-stops-fly-camera-velocity
  "Test that fly camera velocity is zeroed during transition."
  (let* ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 0.0 0.0)
                                :speed 10.0 :damping 1.0))
         (trans (animate-camera-to cam
                                   (3d-vectors:vec3 10.0 0.0 0.0)
                                   (3d-vectors:vec3 10.0 0.0 -10.0)
                                   :duration 1.0)))
    ;; Give camera some velocity first
    (fly-camera-move cam :forward)
    (apply-camera-transition cam trans 0.5)
    ;; Velocity should be zero
    (let ((vel (fly-camera-velocity cam)))
      (is (< (3d-vectors:vlength vel) 0.001)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Camera Focus Function Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite camera-focus-tests
  :in holodeck-tests
  :description "Tests for focus-on-snapshot, focus-on-agent, camera-overview")

(in-suite camera-focus-tests)

;;; --- entity-position-vec3 ---

(test entity-position-vec3-extracts-position
  "Test that entity-position-vec3 extracts position3d as vec3."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 10.0 :y 20.0 :z 30.0)
    (let ((pos (entity-position-vec3 e)))
      (is (< (abs (- (3d-vectors:vx pos) 10.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy pos) 20.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz pos) 30.0)) 0.001)))))

;;; --- focus-on-snapshot ---

(test focus-on-snapshot-orbit-returns-transition
  "Test that focus-on-snapshot with orbit camera returns a camera-transition."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera))
        (e (make-snapshot-entity "snap-1" :decision :x 10.0 :y 5.0 :z 0.0)))
    (let ((trans (focus-on-snapshot cam e)))
      (is (typep trans 'camera-transition))
      (is (not (camera-transition-complete-p trans))))))

(test focus-on-snapshot-orbit-targets-entity-position
  "Test that focus-on-snapshot transition targets the entity position."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera))
        (e (make-snapshot-entity "snap-2" :action :x 15.0 :y 3.0 :z 7.0)))
    (let ((trans (focus-on-snapshot cam e)))
      ;; End target should be the entity position
      (let ((end-target (transition-end-target trans)))
        (is (< (abs (- (3d-vectors:vx end-target) 15.0)) 0.001))
        (is (< (abs (- (3d-vectors:vy end-target) 3.0)) 0.001))
        (is (< (abs (- (3d-vectors:vz end-target) 7.0)) 0.001))))))

(test focus-on-snapshot-orbit-end-position-offset
  "Test that focus-on-snapshot end position is entity + offset."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera))
        (e (make-snapshot-entity "snap-3" :genesis :x 0.0 :y 0.0 :z 0.0)))
    (let* ((trans (focus-on-snapshot cam e))
           (end-pos (transition-end-position trans))
           (offset *focus-camera-offset*))
      ;; End position should be entity position + default offset
      (is (< (abs (- (3d-vectors:vx end-pos) (3d-vectors:vx offset))) 0.001))
      (is (< (abs (- (3d-vectors:vy end-pos) (3d-vectors:vy offset))) 0.001))
      (is (< (abs (- (3d-vectors:vz end-pos) (3d-vectors:vz offset))) 0.001)))))

(test focus-on-snapshot-fly-returns-transition
  "Test that focus-on-snapshot with fly camera returns a camera-transition."
  (init-holodeck-storage)
  (let ((cam (make-fly-camera))
        (e (make-snapshot-entity "snap-4" :fork :x 20.0 :y 10.0 :z 5.0)))
    (let ((trans (focus-on-snapshot cam e)))
      (is (typep trans 'camera-transition))
      (is (not (camera-transition-complete-p trans))))))

(test focus-on-snapshot-custom-offset
  "Test that focus-on-snapshot respects custom offset."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera))
        (e (make-snapshot-entity "snap-5" :action :x 5.0 :y 5.0 :z 5.0))
        (custom-offset (3d-vectors:vec3 0.0 10.0 0.0)))
    (let* ((trans (focus-on-snapshot cam e :offset custom-offset))
           (end-pos (transition-end-position trans)))
      ;; End position should be (5, 15, 5) = entity + custom offset
      (is (< (abs (- (3d-vectors:vx end-pos) 5.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy end-pos) 15.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz end-pos) 5.0)) 0.001)))))

(test focus-on-snapshot-custom-duration
  "Test that focus-on-snapshot respects custom duration."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera))
        (e (make-snapshot-entity "snap-6" :action :x 0.0 :y 0.0 :z 0.0)))
    (let ((trans (focus-on-snapshot cam e :duration 3.0)))
      (is (< (abs (- (transition-duration trans) 3.0)) 0.001)))))

;;; --- focus-on-agent ---

(test focus-on-agent-orbit-returns-transition
  "Test that focus-on-agent with orbit camera returns a camera-transition."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera))
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 8.0 :y 4.0 :z 2.0)
    (make-agent-binding e :agent-id "agent-1" :agent-name "Test Agent")
    (let ((trans (focus-on-agent cam e)))
      (is (typep trans 'camera-transition)))))

(test focus-on-agent-targets-agent-position
  "Test that focus-on-agent transition targets the agent entity position."
  (init-holodeck-storage)
  (let ((cam (make-fly-camera))
        (e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 12.0 :y 6.0 :z 3.0)
    (make-agent-binding e :agent-id "agent-2" :agent-name "Agent Two")
    (let* ((trans (focus-on-agent cam e))
           (end-target (transition-end-target trans)))
      (is (< (abs (- (3d-vectors:vx end-target) 12.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy end-target) 6.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz end-target) 3.0)) 0.001)))))

;;; --- compute-scene-bounds ---

(test compute-scene-bounds-empty-scene
  "Test that compute-scene-bounds returns origin for empty entity list."
  (init-holodeck-storage)
  (multiple-value-bind (min-c max-c)
      (compute-scene-bounds nil)
    (is (< (3d-vectors:vlength min-c) 0.001))
    (is (< (3d-vectors:vlength max-c) 0.001))))

(test compute-scene-bounds-single-entity
  "Test scene bounds with a single entity."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 5.0 :y 10.0 :z 15.0)
    (multiple-value-bind (min-c max-c)
        (compute-scene-bounds (list e))
      (is (< (abs (- (3d-vectors:vx min-c) 5.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy min-c) 10.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz min-c) 15.0)) 0.001))
      (is (< (abs (- (3d-vectors:vx max-c) 5.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy max-c) 10.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz max-c) 15.0)) 0.001)))))

(test compute-scene-bounds-multiple-entities
  "Test scene bounds encompasses all entities."
  (init-holodeck-storage)
  (let ((e1 (cl-fast-ecs:make-entity))
        (e2 (cl-fast-ecs:make-entity))
        (e3 (cl-fast-ecs:make-entity)))
    (make-position3d e1 :x -10.0 :y 0.0 :z 5.0)
    (make-position3d e2 :x 20.0 :y 15.0 :z -5.0)
    (make-position3d e3 :x 5.0 :y 8.0 :z 25.0)
    (multiple-value-bind (min-c max-c)
        (compute-scene-bounds (list e1 e2 e3))
      (is (< (abs (- (3d-vectors:vx min-c) -10.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy min-c) 0.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz min-c) -5.0)) 0.001))
      (is (< (abs (- (3d-vectors:vx max-c) 20.0)) 0.001))
      (is (< (abs (- (3d-vectors:vy max-c) 15.0)) 0.001))
      (is (< (abs (- (3d-vectors:vz max-c) 25.0)) 0.001)))))

;;; --- camera-overview ---

(test camera-overview-orbit-returns-transition
  "Test that camera-overview with orbit camera returns a transition."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera)))
    ;; Create some entities to define a scene
    (let ((e1 (make-snapshot-entity "ov-1" :decision :x 0.0 :y 0.0 :z 0.0))
          (e2 (make-snapshot-entity "ov-2" :action :x 10.0 :y 10.0 :z 10.0)))
      (reset-snapshot-entities)
      (track-snapshot-entity e1)
      (track-snapshot-entity e2)
      (let ((trans (camera-overview cam)))
        (is (typep trans 'camera-transition))
        (is (not (camera-transition-complete-p trans)))))))

(test camera-overview-fly-returns-transition
  "Test that camera-overview with fly camera returns a transition."
  (init-holodeck-storage)
  (let ((cam (make-fly-camera)))
    (let ((e1 (make-snapshot-entity "ov-3" :genesis :x -5.0 :y 0.0 :z -5.0))
          (e2 (make-snapshot-entity "ov-4" :fork :x 5.0 :y 5.0 :z 5.0)))
      (reset-snapshot-entities)
      (track-snapshot-entity e1)
      (track-snapshot-entity e2)
      (let ((trans (camera-overview cam)))
        (is (typep trans 'camera-transition))))))

(test camera-overview-targets-scene-center
  "Test that camera-overview transition targets the center of the scene."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera)))
    (let ((e1 (make-snapshot-entity "ov-5" :genesis :x 0.0 :y 0.0 :z 0.0))
          (e2 (make-snapshot-entity "ov-6" :action :x 20.0 :y 10.0 :z 30.0)))
      (reset-snapshot-entities)
      (track-snapshot-entity e1)
      (track-snapshot-entity e2)
      (let* ((trans (camera-overview cam))
             (end-target (transition-end-target trans)))
        ;; Center should be midpoint: (10, 5, 15)
        (is (< (abs (- (3d-vectors:vx end-target) 10.0)) 0.001))
        (is (< (abs (- (3d-vectors:vy end-target) 5.0)) 0.001))
        (is (< (abs (- (3d-vectors:vz end-target) 15.0)) 0.001))))))

(test camera-overview-positions-above-scene
  "Test that camera-overview positions camera above and behind the center."
  (init-holodeck-storage)
  (let ((cam (make-orbit-camera)))
    (let ((e1 (make-snapshot-entity "ov-7" :genesis :x 0.0 :y 0.0 :z 0.0))
          (e2 (make-snapshot-entity "ov-8" :action :x 20.0 :y 10.0 :z 30.0)))
      (reset-snapshot-entities)
      (track-snapshot-entity e1)
      (track-snapshot-entity e2)
      (let* ((trans (camera-overview cam))
             (end-pos (transition-end-position trans)))
        ;; Camera should be above center (y > center-y)
        (is (> (3d-vectors:vy end-pos) 5.0))
        ;; Camera should be behind center (z > center-z)
        (is (> (3d-vectors:vz end-pos) 15.0))))))

(test camera-overview-empty-scene-still-works
  "Test that camera-overview handles empty scene without error."
  (init-holodeck-storage)
  (reset-snapshot-entities)
  (let ((cam (make-orbit-camera)))
    (let ((trans (camera-overview cam)))
      (is (typep trans 'camera-transition)))))

;;; ===================================================================
;;; Camera Input Handler Tests
;;; ===================================================================

(def-suite input-handler-tests
  :in holodeck-tests
  :description "Tests for camera-input-handler class and input processing")

(in-suite input-handler-tests)

;; --- Construction ---

(test input-handler-creation
  "Test that camera-input-handler is created with correct defaults."
  (let ((handler (make-camera-input-handler)))
    (is (null (input-handler-camera handler)))
    (is (= 0.0 (input-handler-mouse-x handler)))
    (is (= 0.0 (input-handler-mouse-y handler)))
    (is (= 0.0 (input-handler-prev-mouse-x handler)))
    (is (= 0.0 (input-handler-prev-mouse-y handler)))
    (is (null (input-handler-buttons-pressed handler)))
    (is (= 0.0 (input-handler-scroll-accumulator handler)))))

(test input-handler-creation-with-camera
  "Test that camera-input-handler can be created with an attached camera."
  (let* ((cam (make-orbit-camera))
         (handler (make-camera-input-handler :camera cam)))
    (is (eq cam (input-handler-camera handler)))))

;; --- Mouse Position ---

(test handle-mouse-move-updates-position
  "Test that handle-mouse-move updates current mouse position."
  (let ((handler (make-camera-input-handler)))
    (handle-mouse-move handler 100.0 200.0)
    (is (= 100.0 (input-handler-mouse-x handler)))
    (is (= 200.0 (input-handler-mouse-y handler)))))

(test handle-mouse-move-does-not-update-prev
  "Test that handle-mouse-move does not immediately update prev position."
  (let ((handler (make-camera-input-handler)))
    (handle-mouse-move handler 100.0 200.0)
    ;; prev should still be 0 (initial value)
    (is (= 0.0 (input-handler-prev-mouse-x handler)))
    (is (= 0.0 (input-handler-prev-mouse-y handler)))))

;; --- Mouse Button State ---

(test button-press-and-release
  "Test that button press/release correctly updates state."
  (let ((handler (make-camera-input-handler)))
    (is (not (button-pressed-p handler :right)))
    (handle-mouse-button-press handler :right)
    (is (button-pressed-p handler :right))
    (handle-mouse-button-release handler :right)
    (is (not (button-pressed-p handler :right)))))

(test multiple-buttons-pressed
  "Test that multiple buttons can be pressed simultaneously."
  (let ((handler (make-camera-input-handler)))
    (handle-mouse-button-press handler :left)
    (handle-mouse-button-press handler :right)
    (is (button-pressed-p handler :left))
    (is (button-pressed-p handler :right))
    (is (not (button-pressed-p handler :middle)))
    (handle-mouse-button-release handler :left)
    (is (not (button-pressed-p handler :left)))
    (is (button-pressed-p handler :right))))

(test duplicate-press-does-not-double-add
  "Test that pressing the same button twice doesn't add duplicate entries."
  (let ((handler (make-camera-input-handler)))
    (handle-mouse-button-press handler :right)
    (handle-mouse-button-press handler :right)
    (is (= 1 (length (input-handler-buttons-pressed handler))))))

(test button-press-snaps-prev-mouse
  "Test that pressing a button snaps prev-mouse to current position."
  (let ((handler (make-camera-input-handler)))
    (handle-mouse-move handler 150.0 250.0)
    (handle-mouse-button-press handler :right)
    ;; prev should now match current to avoid a delta spike
    (is (= 150.0 (input-handler-prev-mouse-x handler)))
    (is (= 250.0 (input-handler-prev-mouse-y handler)))))

;; --- Scroll Input ---

(test handle-scroll-accumulates
  "Test that scroll events accumulate."
  (let ((handler (make-camera-input-handler)))
    (handle-scroll handler 1.0)
    (is (< (abs (- (input-handler-scroll-accumulator handler) 1.0)) 0.001))
    (handle-scroll handler 2.0)
    (is (< (abs (- (input-handler-scroll-accumulator handler) 3.0)) 0.001))
    (handle-scroll handler -1.5)
    (is (< (abs (- (input-handler-scroll-accumulator handler) 1.5)) 0.001))))

;; --- Mouse Delta ---

(test mouse-delta-computation
  "Test that mouse-delta returns correct dx, dy."
  (let ((handler (make-camera-input-handler)))
    ;; Set prev to (100, 200), current to (110, 195)
    (setf (input-handler-prev-mouse-x handler) 100.0)
    (setf (input-handler-prev-mouse-y handler) 200.0)
    (handle-mouse-move handler 110.0 195.0)
    (multiple-value-bind (dx dy) (mouse-delta handler)
      (is (< (abs (- dx 10.0)) 0.001))
      (is (< (abs (- dy -5.0)) 0.001)))))

;; --- Right-Drag Orbits ---

(test right-drag-orbits-camera
  "Test that right-drag causes the camera to orbit."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :orbit-speed 0.01))
         (handler (make-camera-input-handler :camera cam)))
    ;; Start drag at (100, 100)
    (handle-mouse-move handler 100.0 100.0)
    (handle-mouse-button-press handler :right)
    ;; Move to (200, 150) - delta is (100, 50)
    (handle-mouse-move handler 200.0 150.0)
    (process-camera-input handler)
    ;; theta should have changed by 100 * 0.01 = 1.0
    (is (< (abs (- (camera-theta cam) 1.0)) 0.01))
    ;; phi should have changed by 50 * 0.01 = 0.5
    (is (< (abs (- (camera-phi cam) 0.5)) 0.01))))

(test right-drag-no-orbit-when-released
  "Test that releasing right button stops orbiting."
  (let* ((cam (make-orbit-camera :theta 0.0 :orbit-speed 0.01))
         (handler (make-camera-input-handler :camera cam)))
    (handle-mouse-move handler 100.0 100.0)
    (handle-mouse-button-press handler :right)
    (handle-mouse-move handler 200.0 100.0)
    (process-camera-input handler)
    (let ((theta-after-drag (camera-theta cam)))
      ;; Release and move again
      (handle-mouse-button-release handler :right)
      (handle-mouse-move handler 300.0 100.0)
      (process-camera-input handler)
      ;; theta should not have changed further
      (is (= theta-after-drag (camera-theta cam))))))

;; --- Scroll Zooms ---

(test scroll-zooms-camera-in
  "Test that positive scroll zooms the camera in (decreases distance)."
  (let* ((cam (make-orbit-camera :distance 30.0 :zoom-speed 1.0))
         (handler (make-camera-input-handler :camera cam)))
    (handle-scroll handler 5.0)
    (process-camera-input handler)
    (is (< (camera-distance cam) 30.0))))

(test scroll-zooms-camera-out
  "Test that negative scroll zooms the camera out (increases distance)."
  (let* ((cam (make-orbit-camera :distance 30.0 :zoom-speed 1.0))
         (handler (make-camera-input-handler :camera cam)))
    (handle-scroll handler -5.0)
    (process-camera-input handler)
    (is (> (camera-distance cam) 30.0))))

(test scroll-accumulator-resets-after-process
  "Test that scroll accumulator is reset to zero after processing."
  (let* ((cam (make-orbit-camera))
         (handler (make-camera-input-handler :camera cam)))
    (handle-scroll handler 3.0)
    (process-camera-input handler)
    (is (< (abs (input-handler-scroll-accumulator handler)) 0.001))))

(test zero-scroll-does-not-affect-camera
  "Test that zero scroll delta does not modify camera distance."
  (let* ((cam (make-orbit-camera :distance 30.0))
         (handler (make-camera-input-handler :camera cam)))
    (process-camera-input handler)
    (is (= 30.0 (camera-distance cam)))))

;; --- Middle-Drag Pans ---

(test middle-drag-pans-camera
  "Test that middle-drag pans the camera target."
  (let* ((cam (make-orbit-camera :pan-speed 0.1))
         (handler (make-camera-input-handler :camera cam))
         (old-target (3d-vectors:vcopy (camera-target cam))))
    (handle-mouse-move handler 100.0 100.0)
    (handle-mouse-button-press handler :middle)
    (handle-mouse-move handler 120.0 110.0)
    (process-camera-input handler)
    ;; Target should have moved
    (let ((diff (3d-vectors:v- (camera-target cam) old-target)))
      (is (> (3d-vectors:vlength diff) 0.01)))))

;; --- No Camera Attached ---

(test process-input-no-camera-does-not-error
  "Test that process-camera-input with nil camera does not signal an error."
  (let ((handler (make-camera-input-handler)))
    (handle-mouse-move handler 100.0 100.0)
    (handle-mouse-button-press handler :right)
    (handle-mouse-move handler 200.0 200.0)
    (handle-scroll handler 5.0)
    ;; Should not signal an error
    (finishes (process-camera-input handler))))

;; --- Combined Input ---

(test combined-orbit-and-zoom
  "Test that orbit and zoom can happen in the same frame."
  (let* ((cam (make-orbit-camera :theta 0.0 :distance 30.0
                                 :orbit-speed 0.01 :zoom-speed 1.0))
         (handler (make-camera-input-handler :camera cam)))
    (handle-mouse-move handler 100.0 100.0)
    (handle-mouse-button-press handler :right)
    (handle-mouse-move handler 200.0 100.0)
    (handle-scroll handler 5.0)
    (process-camera-input handler)
    ;; Both should have been applied
    (is (> (abs (camera-theta cam)) 0.01))
    (is (< (camera-distance cam) 30.0))))

(test prev-mouse-updates-after-process
  "Test that prev-mouse position is updated after process-camera-input."
  (let* ((cam (make-orbit-camera))
         (handler (make-camera-input-handler :camera cam)))
    (handle-mouse-move handler 100.0 200.0)
    (process-camera-input handler)
    ;; prev should now equal current
    (is (= 100.0 (input-handler-prev-mouse-x handler)))
    (is (= 200.0 (input-handler-prev-mouse-y handler)))))

;;; ===================================================================
;;; Ray Picking Tests
;;; ===================================================================

(def-suite ray-picking-tests
  :in holodeck-tests
  :description "Tests for ray picking and entity selection")

(in-suite ray-picking-tests)

;;; --- Pick Ray Structure ---

(test pick-ray-creation
  "Test that pick-ray can be created with origin and direction."
  (let ((ray (make-pick-ray :origin (3d-vectors:vec3 1.0 2.0 3.0)
                            :direction (3d-vectors:vec3 0.0 0.0 -1.0))))
    (is (typep ray 'pick-ray))
    (is (= 1.0 (3d-vectors:vx (pick-ray-origin ray))))
    (is (= 2.0 (3d-vectors:vy (pick-ray-origin ray))))
    (is (= 3.0 (3d-vectors:vz (pick-ray-origin ray))))
    (is (= 0.0 (3d-vectors:vx (pick-ray-direction ray))))
    (is (= 0.0 (3d-vectors:vy (pick-ray-direction ray))))
    (is (= -1.0 (3d-vectors:vz (pick-ray-direction ray))))))

;;; --- Ray-Sphere Intersection ---

(test ray-sphere-hit-direct
  "Test ray-sphere intersection when ray passes through center."
  (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 10.0)
                            :direction (3d-vectors:vec3 0.0 0.0 -1.0)))
        (center (3d-vectors:vec3 0.0 0.0 0.0))
        (radius 1.0))
    (multiple-value-bind (hit-p distance)
        (ray-sphere-intersect-p ray center radius)
      (is (eq t hit-p))
      ;; Distance should be 10 - 1 = 9 (ray origin to near intersection)
      (is (< (abs (- distance 9.0)) 0.001)))))

(test ray-sphere-hit-offset
  "Test ray-sphere intersection when ray grazes sphere edge."
  (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.5 0.0 10.0)
                            :direction (3d-vectors:vec3 0.0 0.0 -1.0)))
        (center (3d-vectors:vec3 0.0 0.0 0.0))
        (radius 1.0))
    (multiple-value-bind (hit-p distance)
        (ray-sphere-intersect-p ray center radius)
      (is (eq t hit-p))
      (is (numberp distance)))))

(test ray-sphere-miss
  "Test ray-sphere intersection when ray misses sphere."
  (let ((ray (make-pick-ray :origin (3d-vectors:vec3 5.0 0.0 10.0)
                            :direction (3d-vectors:vec3 0.0 0.0 -1.0)))
        (center (3d-vectors:vec3 0.0 0.0 0.0))
        (radius 1.0))
    (multiple-value-bind (hit-p distance)
        (ray-sphere-intersect-p ray center radius)
      (is (not hit-p))
      (is (null distance)))))

(test ray-sphere-behind-origin
  "Test ray-sphere intersection when sphere is behind ray origin."
  (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 10.0)
                            :direction (3d-vectors:vec3 0.0 0.0 1.0)))  ; pointing away
        (center (3d-vectors:vec3 0.0 0.0 0.0))
        (radius 1.0))
    (multiple-value-bind (hit-p distance)
        (ray-sphere-intersect-p ray center radius)
      (is (not hit-p))
      (is (null distance)))))

(test ray-sphere-origin-inside
  "Test ray-sphere intersection when ray origin is inside sphere."
  (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 0.0)
                            :direction (3d-vectors:vec3 0.0 0.0 -1.0)))
        (center (3d-vectors:vec3 0.0 0.0 0.0))
        (radius 5.0))
    (multiple-value-bind (hit-p distance)
        (ray-sphere-intersect-p ray center radius)
      (is (eq t hit-p))
      ;; Distance should be 5 (to far intersection, since near is behind)
      (is (< (abs (- distance 5.0)) 0.001)))))

;;; --- Screen to World Ray ---

(test screen-to-world-ray-orbit-camera-center
  "Test screen-to-world-ray for orbit camera at screen center."
  (let* ((cam (make-orbit-camera :theta 0.0 :phi 0.0 :distance 30.0))
         (ray (screen-to-world-ray cam 400.0 300.0 800 600)))
    (is (typep ray 'pick-ray))
    ;; Ray origin should be at camera position
    (let ((cam-pos (camera-position cam))
          (ray-origin (pick-ray-origin ray)))
      (is (< (abs (- (3d-vectors:vx ray-origin) (3d-vectors:vx cam-pos))) 0.001))
      (is (< (abs (- (3d-vectors:vy ray-origin) (3d-vectors:vy cam-pos))) 0.001))
      (is (< (abs (- (3d-vectors:vz ray-origin) (3d-vectors:vz cam-pos))) 0.001)))
    ;; Direction should be roughly toward target (negative Z when theta=0, phi=0)
    (let ((dir (pick-ray-direction ray)))
      (is (< (3d-vectors:vz dir) 0.0)))))

(test screen-to-world-ray-fly-camera-center
  "Test screen-to-world-ray for fly camera at screen center."
  (let* ((cam (make-fly-camera :position (3d-vectors:vec3 0.0 5.0 30.0)
                               :yaw 0.0 :pitch 0.0))
         (ray (screen-to-world-ray cam 400.0 300.0 800 600)))
    (is (typep ray 'pick-ray))
    ;; Ray origin should be at camera position
    (let ((cam-pos (fly-camera-position-vec cam))
          (ray-origin (pick-ray-origin ray)))
      (is (< (abs (- (3d-vectors:vx ray-origin) (3d-vectors:vx cam-pos))) 0.001))
      (is (< (abs (- (3d-vectors:vy ray-origin) (3d-vectors:vy cam-pos))) 0.001))
      (is (< (abs (- (3d-vectors:vz ray-origin) (3d-vectors:vz cam-pos))) 0.001)))))

;;; --- Entity Picking ---

(test entity-pick-center-with-position
  "Test entity-pick-center returns position3d values."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 5.0 :y 10.0 :z 15.0)
    (let ((center (entity-pick-center e)))
      (is (= 5.0 (3d-vectors:vx center)))
      (is (= 10.0 (3d-vectors:vy center)))
      (is (= 15.0 (3d-vectors:vz center))))))

(test entity-pick-radius-with-scale
  "Test entity-pick-radius uses scale3d."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-scale3d e :sx 2.0 :sy 3.0 :sz 1.0)
    ;; Should use max of scales (3.0) times default radius (1.0)
    (is (= 3.0 (entity-pick-radius e)))))

(test entity-pick-radius-default
  "Test entity-pick-radius returns default when no scale."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    ;; No scale3d component, should return default
    (is (= *default-pick-radius* (entity-pick-radius e)))))

(test ray-intersects-entity-p-hit
  "Test ray-intersects-entity-p when ray hits entity."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 0.0 :y 0.0 :z 0.0)
    (make-scale3d e :sx 1.0 :sy 1.0 :sz 1.0)
    (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 10.0)
                              :direction (3d-vectors:vec3 0.0 0.0 -1.0))))
      (multiple-value-bind (hit-p distance)
          (ray-intersects-entity-p ray e)
        (is (eq t hit-p))
        (is (numberp distance))))))

(test ray-intersects-entity-p-miss
  "Test ray-intersects-entity-p when ray misses entity."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 100.0 :y 0.0 :z 0.0)
    (make-scale3d e :sx 1.0 :sy 1.0 :sz 1.0)
    (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 10.0)
                              :direction (3d-vectors:vec3 0.0 0.0 -1.0))))
      (multiple-value-bind (hit-p distance)
          (ray-intersects-entity-p ray e)
        (is (not hit-p))
        (is (null distance))))))

(test pick-entity-nearest
  "Test pick-entity returns nearest entity when multiple hit."
  (init-holodeck-storage)
  (let ((e1 (cl-fast-ecs:make-entity))
        (e2 (cl-fast-ecs:make-entity)))
    ;; e1 at z=0, e2 at z=5 (closer to ray origin at z=10)
    (make-position3d e1 :x 0.0 :y 0.0 :z 0.0)
    (make-scale3d e1 :sx 1.0 :sy 1.0 :sz 1.0)
    (make-interactive e1)
    (make-position3d e2 :x 0.0 :y 0.0 :z 5.0)
    (make-scale3d e2 :sx 1.0 :sy 1.0 :sz 1.0)
    (make-interactive e2)
    (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 10.0)
                              :direction (3d-vectors:vec3 0.0 0.0 -1.0))))
      (multiple-value-bind (picked distance)
          (pick-entity ray (list e1 e2))
        ;; e2 is closer (at z=5), should be picked
        (is (= e2 picked))
        (is (< distance 6.0))))))  ; distance to e2 is about 5-1=4

(test pick-entity-no-hit
  "Test pick-entity returns NIL when no entities hit."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-position3d e :x 100.0 :y 0.0 :z 0.0)
    (make-scale3d e :sx 1.0 :sy 1.0 :sz 1.0)
    (make-interactive e)
    (let ((ray (make-pick-ray :origin (3d-vectors:vec3 0.0 0.0 10.0)
                              :direction (3d-vectors:vec3 0.0 0.0 -1.0))))
      (multiple-value-bind (picked distance)
          (pick-entity ray (list e))
        (is (null picked))
        (is (null distance))))))

;;; --- Selection State ---

(test select-entity-sets-state
  "Test select-entity updates interactive component and global."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-interactive e)
    (select-entity e)
    (is (eq e (selected-entity)))
    (is (interactive-selected-p e))))

(test select-entity-deselects-previous
  "Test select-entity deselects previously selected entity."
  (init-holodeck-storage)
  (let ((e1 (cl-fast-ecs:make-entity))
        (e2 (cl-fast-ecs:make-entity)))
    (make-interactive e1)
    (make-interactive e2)
    (select-entity e1)
    (is (interactive-selected-p e1))
    (select-entity e2)
    (is (not (interactive-selected-p e1)))
    (is (interactive-selected-p e2))
    (is (eq e2 (selected-entity)))))

(test deselect-entity-clears-state
  "Test deselect-entity clears selection."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-interactive e)
    (select-entity e)
    (deselect-entity)
    (is (null (selected-entity)))
    (is (not (interactive-selected-p e)))))

;;; --- Hover State ---

(test set-hovered-entity-updates-state
  "Test set-hovered-entity updates interactive component."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-interactive e)
    (set-hovered-entity e)
    (is (eq e (hovered-entity)))
    (is (interactive-hover-p e))))

(test set-hovered-entity-clears-previous
  "Test set-hovered-entity clears previous hover."
  (init-holodeck-storage)
  (let ((e1 (cl-fast-ecs:make-entity))
        (e2 (cl-fast-ecs:make-entity)))
    (make-interactive e1)
    (make-interactive e2)
    (set-hovered-entity e1)
    (is (interactive-hover-p e1))
    (set-hovered-entity e2)
    (is (not (interactive-hover-p e1)))
    (is (interactive-hover-p e2))))

(test set-hovered-entity-nil-clears
  "Test set-hovered-entity with NIL clears hover."
  (init-holodeck-storage)
  (let ((e (cl-fast-ecs:make-entity)))
    (make-interactive e)
    (set-hovered-entity e)
    (set-hovered-entity nil)
    (is (null (hovered-entity)))
    (is (not (interactive-hover-p e)))))

;;; ===================================================================
;;; HUD Panel System Tests
;;; ===================================================================

(def-suite hud-tests
  :in holodeck-tests
  :description "Tests for the HUD panel system")

(in-suite hud-tests)

;;; --- HUD Panel Class ---

(test hud-panel-creation-defaults
  "Test hud-panel default slot values."
  (let ((p (make-instance 'hud-panel)))
    (is (= 0 (panel-x p)))
    (is (= 0 (panel-y p)))
    (is (= 200 (panel-width p)))
    (is (= 100 (panel-height p)))
    (is (null (panel-title p)))
    (is (null (panel-content p)))
    (is (eq t (panel-visible-p p)))
    (is (= 0.7 (panel-alpha p)))))

(test hud-panel-creation-custom
  "Test hud-panel with custom initargs."
  (let ((p (make-instance 'hud-panel
                           :x 50 :y 100
                           :width 300 :height 200
                           :title "TEST"
                           :content '("line1" "line2")
                           :visible-p nil
                           :alpha 0.5)))
    (is (= 50 (panel-x p)))
    (is (= 100 (panel-y p)))
    (is (= 300 (panel-width p)))
    (is (= 200 (panel-height p)))
    (is (string= "TEST" (panel-title p)))
    (is (equal '("line1" "line2") (panel-content p)))
    (is (null (panel-visible-p p)))
    (is (= 0.5 (panel-alpha p)))))

;;; --- HUD Class ---

(test hud-creation-defaults
  "Test hud default slot values."
  (let ((h (make-instance 'hud)))
    (is (eq t (hud-visible-p h)))
    (is (= 0.8 (hud-opacity h)))
    (is (= 0 (hud-panel-count h)))
    (is (null (hud-panel-names h)))))

;;; --- make-hud Standard Panels ---

(test make-hud-creates-four-panels
  "Test that make-hud creates exactly four standard panels."
  (let ((hud (make-hud)))
    (is (= 4 (hud-panel-count hud)))
    (is (not (null (hud-panel hud :position))))
    (is (not (null (hud-panel hud :agent))))
    (is (not (null (hud-panel hud :timeline))))
    (is (not (null (hud-panel hud :hints))))))

(test make-hud-position-panel-placement
  "Test position panel is placed at top-left."
  (let* ((hud (make-hud :window-width 1920 :window-height 1080))
         (p (hud-panel hud :position)))
    (is (= 20 (panel-x p)))
    (is (= 20 (panel-y p)))
    (is (= 250 (panel-width p)))
    (is (= 100 (panel-height p)))
    (is (string= "LOCATION" (panel-title p)))
    (is (eq t (panel-visible-p p)))))

(test make-hud-agent-panel-placement
  "Test agent panel is placed at top-right and starts hidden."
  (let* ((hud (make-hud :window-width 1920 :window-height 1080))
         (p (hud-panel hud :agent)))
    (is (= (- 1920 270) (panel-x p)))
    (is (= 20 (panel-y p)))
    (is (= 250 (panel-width p)))
    (is (= 150 (panel-height p)))
    (is (string= "AGENT" (panel-title p)))
    (is (null (panel-visible-p p)))))

(test make-hud-timeline-panel-placement
  "Test timeline panel is placed at bottom."
  (let* ((hud (make-hud :window-width 1920 :window-height 1080))
         (p (hud-panel hud :timeline)))
    (is (= 20 (panel-x p)))
    (is (= (- 1080 80) (panel-y p)))
    (is (= (- 1920 40) (panel-width p)))
    (is (= 60 (panel-height p)))))

(test make-hud-hints-panel-placement
  "Test hints panel is placed at bottom-right with pre-filled content."
  (let* ((hud (make-hud :window-width 1920 :window-height 1080))
         (p (hud-panel hud :hints)))
    (is (= (- 1920 220) (panel-x p)))
    (is (= (- 1080 150) (panel-y p)))
    (is (= 200 (panel-width p)))
    (is (= 130 (panel-height p)))
    (is (= 0.5 (panel-alpha p)))
    (is (= 6 (length (panel-content p))))))

(test make-hud-custom-dimensions
  "Test that make-hud adapts panel positions to custom window size."
  (let* ((hud (make-hud :window-width 800 :window-height 600))
         (agent-p (hud-panel hud :agent))
         (timeline-p (hud-panel hud :timeline))
         (hints-p (hud-panel hud :hints)))
    (is (= (- 800 270) (panel-x agent-p)))
    (is (= (- 600 80) (panel-y timeline-p)))
    (is (= (- 800 40) (panel-width timeline-p)))
    (is (= (- 800 220) (panel-x hints-p)))
    (is (= (- 600 150) (panel-y hints-p)))))

;;; --- HUD Panel Access ---

(test hud-panel-accessor
  "Test getting and setting panels by name."
  (let ((hud (make-instance 'hud))
        (panel (make-instance 'hud-panel :x 10 :y 20)))
    (is (null (hud-panel hud :test)))
    (setf (hud-panel hud :test) panel)
    (is (eq panel (hud-panel hud :test)))
    (is (= 1 (hud-panel-count hud)))
    (is (equal '(:test) (hud-panel-names hud)))))

;;; --- Visibility Toggles ---

(test toggle-hud-visibility
  "Test toggling master HUD visibility."
  (let ((hud (make-hud)))
    (is (eq t (hud-visible-p hud)))
    (toggle-hud-visibility hud)
    (is (null (hud-visible-p hud)))
    (toggle-hud-visibility hud)
    (is (eq t (hud-visible-p hud)))))

(test toggle-panel-visibility
  "Test toggling individual panel visibility."
  (let ((hud (make-hud)))
    (is (eq t (panel-visible-p (hud-panel hud :position))))
    (toggle-panel-visibility hud :position)
    (is (null (panel-visible-p (hud-panel hud :position))))
    (toggle-panel-visibility hud :position)
    (is (eq t (panel-visible-p (hud-panel hud :position))))
    ;; Non-existent panel returns NIL
    (is (null (toggle-panel-visibility hud :nonexistent)))))

;;; --- Content Updates ---

(test update-position-panel-content
  "Test updating position panel with navigation state."
  (let ((hud (make-hud)))
    (update-position-panel hud
                           :branch "main"
                           :snapshot-id "abc123def456ghi789"
                           :snapshot-type :decision)
    (let ((content (panel-content (hud-panel hud :position))))
      (is (= 3 (length content)))
      (is (search "main" (first content)))
      (is (search "abc123" (second content)))
      (is (search "DECISION" (third content))))))

(test update-agent-panel-shows-and-hides
  "Test that updating agent panel controls visibility."
  (let ((hud (make-hud)))
    ;; Agent panel starts hidden
    (is (null (panel-visible-p (hud-panel hud :agent))))
    ;; Providing agent-name makes it visible
    (update-agent-panel hud :agent-name "Watson"
                            :agent-status :running
                            :agent-task "Analyzing data")
    (is (eq t (panel-visible-p (hud-panel hud :agent))))
    (let ((content (panel-content (hud-panel hud :agent))))
      (is (= 3 (length content)))
      (is (search "Watson" (first content))))
    ;; Clearing agent-name hides it
    (update-agent-panel hud :agent-name nil)
    (is (null (panel-visible-p (hud-panel hud :agent))))))

(test update-timeline-panel-content
  "Test updating timeline panel populates scrubber data."
  (let ((hud (make-hud)))
    (update-timeline-panel hud :total-snapshots 42
                               :current-index 15
                               :branch-count 3)
    ;; Panel text content is cleared (scrubber renders its own label)
    (is (null (panel-content (hud-panel hud :timeline))))
    ;; Scrubber data should be populated
    (let ((scrubber (hud-timeline-scrubber hud)))
      (is (not (null scrubber)))
      (is (= 42 (scrubber-total-snapshots scrubber)))
      (is (= 15 (scrubber-current-index scrubber)))
      (is (= 3 (scrubber-branch-count scrubber)))
      (is (= 42 (length (scrubber-snapshot-entries scrubber)))))))

;;; --- Render Descriptions ---

(test collect-visible-panels-respects-visibility
  "Test that collect-visible-panels filters hidden panels."
  (let ((hud (make-hud)))
    ;; Agent panel starts hidden, so 3 visible panels
    (let ((visible (collect-visible-panels hud)))
      (is (= 3 (length visible))))
    ;; Show agent panel -> 4 visible
    (setf (panel-visible-p (hud-panel hud :agent)) t)
    (is (= 4 (length (collect-visible-panels hud))))
    ;; Hide entire HUD -> NIL
    (setf (hud-visible-p hud) nil)
    (is (null (collect-visible-panels hud)))))

(test panel-render-description-structure
  "Test that panel render descriptions contain expected keys."
  (let* ((panel (make-instance 'hud-panel
                                :x 10 :y 20 :width 300 :height 100
                                :title "TEST" :alpha 0.7
                                :content '("Hello" "World")))
         (desc (panel-render-description panel 0.8)))
    (is (= 10 (getf desc :x)))
    (is (= 20 (getf desc :y)))
    (is (= 300 (getf desc :width)))
    (is (= 100 (getf desc :height)))
    ;; Alpha = panel alpha * global opacity = 0.7 * 0.8 = 0.56
    (is (< (abs (- 0.56 (getf desc :alpha))) 0.01))
    (is (string= "TEST" (getf desc :title)))
    (is (equal '("Hello" "World") (getf desc :lines)))
    (is (listp (getf desc :border-color)))
    (is (listp (getf desc :text-color)))
    (is (listp (getf desc :bg-color)))))

(test collect-hud-render-descriptions-count
  "Test that collect-hud-render-descriptions returns correct count."
  (let ((hud (make-hud)))
    ;; 3 visible by default (agent hidden)
    (is (= 3 (length (collect-hud-render-descriptions hud))))
    ;; Show agent panel
    (setf (panel-visible-p (hud-panel hud :agent)) t)
    (is (= 4 (length (collect-hud-render-descriptions hud))))))

;;; --- Utility ---

(test truncate-id-short-string
  "Test that short strings are returned unchanged."
  (is (string= "hello" (truncate-id "hello" 10))))

(test truncate-id-exact-length
  "Test that strings at exact max length are returned unchanged."
  (is (string= "hello" (truncate-id "hello" 5))))

(test truncate-id-long-string
  "Test that long strings are truncated with ellipsis marker."
  (let ((result (truncate-id "abcdefghij" 5)))
    (is (= 5 (length result)))
    (is (char= #\~ (char result 4)))))

;;; ===================================================================
;;; update-hud Tests
;;; ===================================================================

(def-suite update-hud-tests
  :in hud-tests
  :description "Tests for update-hud and its helper functions")

(in-suite update-hud-tests)

;;; --- Helper function tests ---

(test find-selected-snapshot-entity-none
  "Test find-selected-snapshot-entity returns NIL when nothing selected."
  (init-holodeck-storage)
  (let ((*snapshot-entities* nil))
    (is (null (find-selected-snapshot-entity)))))

(test find-selected-snapshot-entity-with-selection
  "Test find-selected-snapshot-entity finds selected entity."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "snap-1" :action :x 0.0 :y 0.0 :z 0.0))
         (e2 (make-snapshot-entity "snap-2" :decision :x 1.0 :y 0.0 :z 0.0))
         (*snapshot-entities* (list e1 e2)))
    ;; Nothing selected yet
    (is (null (find-selected-snapshot-entity)))
    ;; Select e2
    (setf (interactive-selected-p e2) t)
    (is (eql e2 (find-selected-snapshot-entity)))))

(test find-focused-agent-entity-none
  "Test find-focused-agent-entity returns NIL when no agent bound."
  (init-holodeck-storage)
  (let ((*snapshot-entities* nil))
    (is (null (find-focused-agent-entity)))))

(test find-focused-agent-entity-with-agent
  "Test find-focused-agent-entity finds entity with agent-binding."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "snap-1" :action))
         (e2 (make-snapshot-entity "snap-2" :decision))
         (*snapshot-entities* (list e1 e2)))
    ;; No agents bound -> nil
    (is (null (find-focused-agent-entity)))
    ;; Add agent binding to e2
    (make-agent-binding e2 :agent-id "agent-42" :agent-name "Watson")
    (is (eql e2 (find-focused-agent-entity)))))

(test count-unique-branches-empty
  "Test count-unique-branches with no entities."
  (init-holodeck-storage)
  (let ((*snapshot-entities* nil))
    (is (= 0 (count-unique-branches)))))

(test count-unique-branches-counts-types
  "Test count-unique-branches counts distinct snapshot types."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "s1" :action))
         (e2 (make-snapshot-entity "s2" :decision))
         (e3 (make-snapshot-entity "s3" :action))
         (*snapshot-entities* (list e1 e2 e3)))
    (is (= 2 (count-unique-branches)))))

(test selected-entity-index-not-found
  "Test selected-entity-index returns 0 for unknown entity."
  (init-holodeck-storage)
  (let ((*snapshot-entities* nil))
    (is (= 0 (selected-entity-index 999)))))

(test selected-entity-index-found
  "Test selected-entity-index returns 1-based index."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "s1" :action))
         (e2 (make-snapshot-entity "s2" :decision))
         (*snapshot-entities* (list e1 e2)))
    (is (= 1 (selected-entity-index e1)))
    (is (= 2 (selected-entity-index e2)))))

;;; --- Main update-hud tests ---

(test update-hud-no-entities
  "Test update-hud works with no snapshot entities."
  (init-holodeck-storage)
  (let* ((*snapshot-entities* nil)
         (hud (make-hud)))
    ;; Should not error
    (update-hud hud)
    ;; Position panel should show dashes
    (let ((content (panel-content (hud-panel hud :position))))
      (is (= 3 (length content)))
      (is (search "—" (first content))))
    ;; Agent panel should be hidden
    (is (null (panel-visible-p (hud-panel hud :agent))))
    ;; Timeline scrubber should show 0 snapshots
    (let ((scrubber (hud-timeline-scrubber hud)))
      (is (not (null scrubber)))
      (is (= 0 (scrubber-total-snapshots scrubber)))
      (is (= 0 (scrubber-current-index scrubber))))))

(test update-hud-with-selected-snapshot
  "Test update-hud populates position panel from selected entity."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "snap-abc123" :decision))
         (*snapshot-entities* (list e1))
         (hud (make-hud)))
    (setf (interactive-selected-p e1) t)
    (update-hud hud)
    ;; Position panel should have snapshot info
    (let ((content (panel-content (hud-panel hud :position))))
      (is (search "DECISION" (first content)))
      (is (search "snap-abc123" (second content)))
      (is (search "DECISION" (third content))))
    ;; Timeline scrubber should show 1/1
    (let ((scrubber (hud-timeline-scrubber hud)))
      (is (not (null scrubber)))
      (is (= 1 (scrubber-total-snapshots scrubber)))
      (is (= 1 (scrubber-current-index scrubber))))))

(test update-hud-with-agent
  "Test update-hud shows agent panel when agent is bound."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "s1" :action))
         (*snapshot-entities* (list e1))
         (hud (make-hud)))
    (make-agent-binding e1 :agent-id "agent-1" :agent-name "Sherlock")
    (update-hud hud)
    ;; Agent panel should be visible
    (is (eq t (panel-visible-p (hud-panel hud :agent))))
    ;; Content should mention agent name
    (let ((content (panel-content (hud-panel hud :agent))))
      (is (search "Sherlock" (first content))))))

(test update-hud-without-agent
  "Test update-hud hides agent panel when no agent is bound."
  (init-holodeck-storage)
  (let* ((e1 (make-snapshot-entity "s1" :action))
         (*snapshot-entities* (list e1))
         (hud (make-hud)))
    (update-hud hud)
    ;; Agent panel should be hidden
    (is (null (panel-visible-p (hud-panel hud :agent))))))

;;; ===================================================================
;;; render-hud Tests
;;; ===================================================================

(def-suite render-hud-tests
  :in hud-tests
  :description "Tests for render-hud, border geometry, text layout, and panel commands")

(in-suite render-hud-tests)

;;; --- Border Geometry ---

(test make-border-segments-count
  "Test that make-border-segments produces 12 segments (4 corners + 4 edges)."
  (let ((segs (make-border-segments 0 0 200 100 8)))
    (is (= 12 (length segs)))))

(test make-border-segments-structure
  "Test that each border segment has x1 y1 x2 y2 keys."
  (let ((segs (make-border-segments 10 20 300 150 8)))
    (dolist (seg segs)
      (is (not (null (getf seg :x1))))
      (is (not (null (getf seg :y1))))
      (is (not (null (getf seg :x2))))
      (is (not (null (getf seg :y2)))))))

(test make-border-segments-bounds
  "Test that border segments stay within panel bounds."
  (let ((segs (make-border-segments 10 20 300 150 8)))
    (dolist (seg segs)
      (is (<= 10 (getf seg :x1) 310))
      (is (<= 20 (getf seg :y1) 170))
      (is (<= 10 (getf seg :x2) 310))
      (is (<= 20 (getf seg :y2) 170)))))

(test make-corner-brackets-count
  "Test that make-corner-brackets produces 8 segments (2 per corner)."
  (let ((segs (make-corner-brackets 0 0 200 100 8)))
    (is (= 8 (length segs)))))

(test make-corner-brackets-structure
  "Test that each corner bracket has x1 y1 x2 y2 keys."
  (let ((segs (make-corner-brackets 50 50 400 300 10)))
    (dolist (seg segs)
      (is (not (null (getf seg :x1))))
      (is (not (null (getf seg :y1))))
      (is (not (null (getf seg :x2))))
      (is (not (null (getf seg :y2)))))))

;;; --- Text Layout ---

(test layout-panel-text-with-title
  "Test text layout includes title and content lines."
  (let* ((desc (list :x 10 :y 20 :width 200 :height 100
                     :title "TEST" :lines '("Line 1" "Line 2")
                     :text-color '(0.8 0.9 1.0 1.0)))
         (texts (layout-panel-text desc)))
    ;; Should have title + 2 content lines = 3 text commands
    (is (= 3 (length texts)))
    ;; First should be the title
    (is (string= "TEST" (getf (first texts) :text)))
    (is (eq :bold (getf (first texts) :style)))
    ;; Content lines
    (is (string= "Line 1" (getf (second texts) :text)))
    (is (string= "Line 2" (getf (third texts) :text)))))

(test layout-panel-text-without-title
  "Test text layout with no title starts content at padding offset."
  (let* ((desc (list :x 10 :y 20 :width 200 :height 100
                     :title nil :lines '("Only line")
                     :text-color '(0.8 0.9 1.0 1.0)))
         (texts (layout-panel-text desc)))
    (is (= 1 (length texts)))
    (is (string= "Only line" (getf (first texts) :text)))
    ;; Y should be near top with just padding (no title bar offset)
    (is (< (getf (first texts) :y) 50))))

(test layout-panel-text-empty-content
  "Test text layout with title but no content lines."
  (let* ((desc (list :x 10 :y 20 :width 200 :height 100
                     :title "EMPTY" :lines nil
                     :text-color '(0.8 0.9 1.0 1.0)))
         (texts (layout-panel-text desc)))
    ;; Should have just the title
    (is (= 1 (length texts)))
    (is (string= "EMPTY" (getf (first texts) :text)))))

;;; --- Panel Render Commands ---

(test render-panel-commands-types
  "Test that render-panel-commands produces expected command types."
  (let* ((desc (list :x 10 :y 20 :width 200 :height 100
                     :alpha 0.7 :title "TEST"
                     :lines '("Hello") :text-color '(0.8 0.9 1.0 1.0)
                     :border-color '(0.3 0.6 1.0 0.8)
                     :bg-color '(0.0 0.0 0.0 0.7)))
         (cmds (render-panel-commands desc))
         (types (mapcar (lambda (c) (getf c :type)) cmds)))
    ;; Should have fill-rect, line, text, and title-bar commands
    (is (member :fill-rect types))
    (is (member :line types))
    (is (member :text types))
    (is (member :title-bar types))))

(test render-panel-commands-has-background
  "Test that first command is a fill-rect for the background."
  (let* ((desc (list :x 10 :y 20 :width 200 :height 100
                     :alpha 0.5 :title nil :lines nil
                     :text-color '(0.8 0.9 1.0 1.0)
                     :border-color '(0.3 0.6 1.0 0.8)
                     :bg-color '(0.0 0.0 0.0 0.5)))
         (cmds (render-panel-commands desc)))
    (is (eq :fill-rect (getf (first cmds) :type)))
    (is (= 10 (getf (first cmds) :x)))
    (is (= 20 (getf (first cmds) :y)))
    (is (= 200 (getf (first cmds) :width)))
    (is (= 100 (getf (first cmds) :height)))))

(test render-panel-commands-alpha-applied
  "Test that alpha is properly applied to background color."
  (let* ((desc (list :x 0 :y 0 :width 100 :height 50
                     :alpha 0.5 :title nil :lines nil
                     :text-color '(0.8 0.9 1.0 1.0)
                     :border-color '(0.3 0.6 1.0 0.8)
                     :bg-color '(0.0 0.0 0.0 0.5)))
         (cmds (render-panel-commands desc))
         (bg-cmd (first cmds))
         (bg-alpha (fourth (getf bg-cmd :color))))
    ;; Background alpha should be the panel alpha (0.5)
    (is (< (abs (- 0.5 bg-alpha)) 0.01))))

(test render-panel-commands-no-title-bar-without-title
  "Test that no title-bar command is generated when title is nil."
  (let* ((desc (list :x 0 :y 0 :width 100 :height 50
                     :alpha 0.7 :title nil :lines nil
                     :text-color '(0.8 0.9 1.0 1.0)
                     :border-color '(0.3 0.6 1.0 0.8)
                     :bg-color '(0.0 0.0 0.0 0.7)))
         (cmds (render-panel-commands desc))
         (types (mapcar (lambda (c) (getf c :type)) cmds)))
    (is (not (member :title-bar types)))))

(test render-panel-commands-border-line-count
  "Test that border generates the expected number of line commands."
  (let* ((desc (list :x 0 :y 0 :width 200 :height 100
                     :alpha 0.8 :title nil :lines nil
                     :text-color '(0.8 0.9 1.0 1.0)
                     :border-color '(0.3 0.6 1.0 0.8)
                     :bg-color '(0.0 0.0 0.0 0.8)))
         (cmds (render-panel-commands desc))
         (line-cmds (remove-if-not (lambda (c) (eq :line (getf c :type))) cmds)))
    ;; 12 glow border + 12 inner border + 8 corner brackets = 32 lines
    (is (= 32 (length line-cmds)))))

;;; --- Main render-hud ---

(test render-hud-hidden
  "Test render-hud returns empty when HUD is hidden."
  (let ((hud (make-hud)))
    (setf (hud-visible-p hud) nil)
    (let ((result (render-hud hud)))
      (is (null (getf result :visible-p)))
      (is (null (getf result :commands)))
      (is (= 0 (getf result :panel-count))))))

(test render-hud-visible-structure
  "Test render-hud returns expected structure when visible."
  (let ((hud (make-hud)))
    (let ((result (render-hud hud)))
      (is (eq t (getf result :visible-p)))
      (is (listp (getf result :commands)))
      ;; 3 visible panels by default (agent hidden)
      (is (= 3 (getf result :panel-count))))))

(test render-hud-all-panels-visible
  "Test render-hud with all four panels visible."
  (let ((hud (make-hud)))
    (setf (panel-visible-p (hud-panel hud :agent)) t)
    (let ((result (render-hud hud)))
      (is (= 4 (getf result :panel-count))))))

(test render-hud-commands-are-plists
  "Test that all commands from render-hud are valid plists with :type."
  (let* ((hud (make-hud))
         (result (render-hud hud))
         (commands (getf result :commands)))
    (dolist (cmd commands)
      (is (not (null (getf cmd :type))))
      (is (member (getf cmd :type)
                  '(:fill-rect :line :text :title-bar
                    :scrubber-track :scrubber-marker :scrubber-current))))))

(test render-hud-command-ordering
  "Test that fill-rect commands precede line and text commands per panel."
  (let* ((hud (make-hud))
         (result (render-hud hud))
         (commands (getf result :commands)))
    ;; First command should be a fill-rect (background of first panel)
    (is (eq :fill-rect (getf (first commands) :type)))))

(test render-hud-with-content
  "Test render-hud includes text commands from panel content."
  (let ((hud (make-hud)))
    (update-position-panel hud :branch "main"
                               :snapshot-id "abc123"
                               :snapshot-type :decision)
    (let* ((result (render-hud hud))
           (commands (getf result :commands))
           (text-cmds (remove-if-not
                       (lambda (c) (eq :text (getf c :type)))
                       commands))
           (texts (mapcar (lambda (c) (getf c :text)) text-cmds)))
      ;; Should contain the position panel's title and content
      (is (some (lambda (txt) (search "LOCATION" txt)) texts))
      (is (some (lambda (txt) (search "Branch" txt)) texts)))))

;;; ===================================================================
;;; Timeline Scrubber Tests
;;; ===================================================================

(def-suite scrubber-tests
  :in hud-tests
  :description "Tests for the timeline scrubber bar")

(in-suite scrubber-tests)

;;; --- Scrubber Class ---

(test timeline-scrubber-creation-defaults
  "Test timeline-scrubber default values."
  (let ((s (make-timeline-scrubber)))
    (is (= 0 (scrubber-total-snapshots s)))
    (is (= 0 (scrubber-current-index s)))
    (is (= 1 (scrubber-branch-count s)))
    (is (null (scrubber-snapshot-entries s)))))

(test timeline-scrubber-creation-custom
  "Test timeline-scrubber with custom values."
  (let ((s (make-timeline-scrubber :total-snapshots 10
                                    :current-index 5
                                    :branch-count 3
                                    :snapshot-entries '((:index 1 :type :snapshot :selected-p nil)))))
    (is (= 10 (scrubber-total-snapshots s)))
    (is (= 5 (scrubber-current-index s)))
    (is (= 3 (scrubber-branch-count s)))
    (is (= 1 (length (scrubber-snapshot-entries s))))))

;;; --- Build Scrubber Entries ---

(test build-scrubber-entries-empty
  "Test build-scrubber-entries with zero snapshots."
  (let ((entries (build-scrubber-entries 0 0)))
    (is (null entries))))

(test build-scrubber-entries-marks-selected
  "Test build-scrubber-entries marks the current index as selected."
  (let ((entries (build-scrubber-entries 5 3)))
    (is (= 5 (length entries)))
    ;; Entry at index 3 should be selected
    (is (eq t (getf (third entries) :selected-p)))
    ;; Others should not be selected
    (is (null (getf (first entries) :selected-p)))
    (is (null (getf (second entries) :selected-p)))
    (is (null (getf (fourth entries) :selected-p)))
    (is (null (getf (fifth entries) :selected-p)))))

(test build-scrubber-entries-indices
  "Test build-scrubber-entries produces correct 1-based indices."
  (let ((entries (build-scrubber-entries 3 1)))
    (is (= 1 (getf (first entries) :index)))
    (is (= 2 (getf (second entries) :index)))
    (is (= 3 (getf (third entries) :index)))))

;;; --- Index to X Mapping ---

(test scrubber-index-to-x-single-snapshot
  "Test scrubber-index-to-x with a single snapshot maps to start."
  (let ((x (scrubber-index-to-x 1 1 100 500)))
    (is (= 100 x))))

(test scrubber-index-to-x-first-and-last
  "Test scrubber-index-to-x maps first to start and last to end."
  (let ((x-first (scrubber-index-to-x 1 10 100 500))
        (x-last (scrubber-index-to-x 10 10 100 500)))
    (is (= 100 x-first))
    (is (< (abs (- 500 x-last)) 0.01))))

(test scrubber-index-to-x-middle
  "Test scrubber-index-to-x maps middle index to midpoint."
  ;; With 3 snapshots, index 2 should be at midpoint
  (let ((x (scrubber-index-to-x 2 3 0 100)))
    (is (< (abs (- 50.0 x)) 0.01))))

(test scrubber-index-to-x-zero-total
  "Test scrubber-index-to-x with zero total returns start."
  (is (= 100 (scrubber-index-to-x 0 0 100 500))))

;;; --- Track X Range ---

(test scrubber-track-x-range-computation
  "Test scrubber-track-x-range computes correct range from panel."
  (let* ((panel (make-instance 'hud-panel :x 20 :width 960))
         (range (scrubber-track-x-range panel)))
    (is (= (+ 20 *scrubber-track-margin*) (car range)))
    (is (= (- (+ 20 960) *scrubber-track-margin*) (cdr range)))))

;;; --- Render Scrubber Commands ---

(test render-scrubber-commands-empty
  "Test render-scrubber-commands with no snapshots produces track and text."
  (let* ((scrubber (make-timeline-scrubber))
         (panel (make-instance 'hud-panel :x 20 :y 900 :width 960 :height 60))
         (cmds (render-scrubber-commands scrubber panel 1.0))
         (types (mapcar (lambda (c) (getf c :type)) cmds)))
    ;; Should have track and text label, no markers or current
    (is (member :scrubber-track types))
    (is (member :text types))
    (is (not (member :scrubber-current types)))
    (is (not (member :scrubber-marker types)))))

(test render-scrubber-commands-with-snapshots
  "Test render-scrubber-commands generates markers for each snapshot."
  (let* ((entries (build-scrubber-entries 5 3))
         (scrubber (make-timeline-scrubber :total-snapshots 5
                                            :current-index 3
                                            :branch-count 2
                                            :snapshot-entries entries))
         (panel (make-instance 'hud-panel :x 20 :y 900 :width 960 :height 60))
         (cmds (render-scrubber-commands scrubber panel 1.0))
         (types (mapcar (lambda (c) (getf c :type)) cmds)))
    ;; Should have: track, 5 markers, current indicator, text
    (is (member :scrubber-track types))
    (is (= 5 (count :scrubber-marker types)))
    (is (member :scrubber-current types))
    (is (member :text types))))

(test render-scrubber-commands-text-label
  "Test render-scrubber-commands text label contains count info."
  (let* ((scrubber (make-timeline-scrubber :total-snapshots 42
                                            :current-index 15
                                            :branch-count 3))
         (panel (make-instance 'hud-panel :x 20 :y 900 :width 960 :height 60))
         (cmds (render-scrubber-commands scrubber panel 1.0))
         (text-cmds (remove-if-not (lambda (c) (eq :text (getf c :type))) cmds)))
    (is (= 1 (length text-cmds)))
    (let ((label (getf (first text-cmds) :text)))
      (is (search "15" label))
      (is (search "42" label))
      (is (search "3" label)))))

(test render-scrubber-commands-alpha-scaling
  "Test render-scrubber-commands applies global alpha to colors."
  (let* ((scrubber (make-timeline-scrubber :total-snapshots 1
                                            :current-index 1
                                            :snapshot-entries (build-scrubber-entries 1 1)))
         (panel (make-instance 'hud-panel :x 0 :y 0 :width 200 :height 60))
         (cmds (render-scrubber-commands scrubber panel 0.5))
         (track-cmd (find :scrubber-track cmds :key (lambda (c) (getf c :type)))))
    ;; Track alpha should be original * 0.5
    (let ((track-alpha (fourth (getf track-cmd :color))))
      (is (< track-alpha (fourth *scrubber-track-color*))))))

;;; --- Scrubber Integration with HUD ---

(test update-timeline-scrubber-creates-data
  "Test update-timeline-scrubber stores scrubber in HUD."
  (let ((hud (make-hud)))
    (update-timeline-scrubber hud :total-snapshots 10
                                   :current-index 5
                                   :branch-count 2)
    (let ((scrubber (hud-timeline-scrubber hud)))
      (is (not (null scrubber)))
      (is (typep scrubber 'timeline-scrubber))
      (is (= 10 (scrubber-total-snapshots scrubber)))
      (is (= 5 (scrubber-current-index scrubber)))
      (is (= 2 (scrubber-branch-count scrubber)))
      (is (= 10 (length (scrubber-snapshot-entries scrubber)))))))

(test render-hud-includes-scrubber-commands
  "Test render-hud includes scrubber commands when scrubber data exists."
  (let ((hud (make-hud)))
    (update-timeline-panel hud :total-snapshots 5
                                :current-index 2
                                :branch-count 1)
    (let* ((result (render-hud hud))
           (commands (getf result :commands))
           (types (mapcar (lambda (c) (getf c :type)) commands)))
      ;; Should have scrubber commands in addition to panel commands
      (is (member :scrubber-track types))
      (is (member :scrubber-marker types))
      (is (member :scrubber-current types)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Key Binding Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite key-binding-tests
  :in holodeck-tests
  :description "Tests for keyboard input handling and key bindings")

(in-suite key-binding-tests)

;;; --- Key Binding Structure Tests ---

(test make-key-binding-basic
  "Test creating a key binding with all fields."
  (let ((binding (make-key-binding :w :fly-forward
                                   :hold-action-p t
                                   :description "Move forward")))
    (is (eq :w (key-binding-key binding)))
    (is (eq :fly-forward (key-binding-action binding)))
    (is (eq t (key-binding-hold-action-p binding)))
    (is (string= "Move forward" (key-binding-description binding)))))

(test make-key-binding-defaults
  "Test key binding defaults."
  (let ((binding (make-key-binding :f :fork-here)))
    (is (eq :f (key-binding-key binding)))
    (is (eq :fork-here (key-binding-action binding)))
    (is (eq nil (key-binding-hold-action-p binding)))
    (is (string= "" (key-binding-description binding)))))

;;; --- Default Key Bindings Tests ---

(test default-key-bindings-exist
  "Test that default key bindings are defined."
  (is (listp *default-key-bindings*))
  (is (> (length *default-key-bindings*) 0)))

(test default-key-bindings-have-wasd
  "Test that WASD camera movement bindings exist."
  (let ((keys (mapcar #'key-binding-key *default-key-bindings*)))
    (is (member :w keys))
    (is (member :a keys))
    (is (member :s keys))
    (is (member :d keys))))

(test default-key-bindings-wasd-are-hold-actions
  "Test that WASD bindings are hold actions."
  (dolist (binding *default-key-bindings*)
    (when (member (key-binding-key binding) '(:w :a :s :d :q :e))
      (is (eq t (key-binding-hold-action-p binding))
          "Key ~A should be a hold action" (key-binding-key binding)))))

(test default-key-bindings-navigation
  "Test that navigation bindings exist."
  (let ((keys (mapcar #'key-binding-key *default-key-bindings*)))
    (is (member :left-bracket keys))
    (is (member :right-bracket keys))
    (is (member :home keys))
    (is (member :end keys))))

(test default-key-bindings-branching
  "Test that branching bindings exist."
  (let ((keys (mapcar #'key-binding-key *default-key-bindings*)))
    (is (member :f keys))
    (is (member :m keys))
    (is (member :b keys))))

;;; --- Key Binding Registry Tests ---

(test make-key-binding-registry-default
  "Test creating a registry with default bindings."
  (let ((registry (make-key-binding-registry)))
    (is (typep registry 'key-binding-registry))
    (is (> (hash-table-count (registry-bindings registry)) 0))))

(test make-key-binding-registry-custom
  "Test creating a registry with custom bindings."
  (let* ((custom (list (make-key-binding :x :test-action)))
         (registry (make-key-binding-registry :bindings custom)))
    (is (= 1 (hash-table-count (registry-bindings registry))))
    (is (not (null (get-binding registry :x))))))

(test get-binding-found
  "Test getting an existing binding."
  (let ((registry (make-key-binding-registry)))
    (let ((binding (get-binding registry :w)))
      (is (not (null binding)))
      (is (eq :w (key-binding-key binding)))
      (is (eq :fly-forward (key-binding-action binding))))))

(test get-binding-not-found
  "Test getting a non-existent binding returns NIL."
  (let ((registry (make-key-binding-registry)))
    (is (null (get-binding registry :nonexistent-key)))))

(test set-binding-new
  "Test adding a new binding."
  (let ((registry (make-key-binding-registry)))
    (set-binding registry :x :test-action
                 :hold-action-p t
                 :description "Test")
    (let ((binding (get-binding registry :x)))
      (is (not (null binding)))
      (is (eq :test-action (key-binding-action binding)))
      (is (eq t (key-binding-hold-action-p binding))))))

(test set-binding-override
  "Test overriding an existing binding."
  (let ((registry (make-key-binding-registry)))
    (set-binding registry :w :new-action)
    (let ((binding (get-binding registry :w)))
      (is (eq :new-action (key-binding-action binding))))))

(test remove-binding-existing
  "Test removing an existing binding."
  (let ((registry (make-key-binding-registry)))
    (is (not (null (get-binding registry :w))))
    (remove-binding registry :w)
    (is (null (get-binding registry :w)))))

(test list-bindings-returns-all
  "Test list-bindings returns all bindings."
  (let* ((registry (make-key-binding-registry))
         (bindings (list-bindings registry)))
    (is (listp bindings))
    (is (= (hash-table-count (registry-bindings registry))
           (length bindings)))))

(test bindings-for-action-found
  "Test finding bindings for an action."
  (let* ((registry (make-key-binding-registry))
         (bindings (bindings-for-action registry :fly-forward)))
    (is (listp bindings))
    (is (= 1 (length bindings)))
    (is (eq :w (key-binding-key (first bindings))))))

(test bindings-for-action-multiple
  "Test finding multiple bindings for same action."
  (let ((registry (make-key-binding-registry)))
    ;; :increase-detail has both :plus and :equals bound
    (let ((bindings (bindings-for-action registry :increase-detail)))
      (is (= 2 (length bindings))))))

;;; --- Action Handler Tests ---

(test register-action-handler
  "Test registering an action handler."
  (let ((registry (make-key-binding-registry))
        (called nil))
    (register-action-handler registry :test-action
                             (lambda () (setf called t)))
    (let ((handler (get-action-handler registry :test-action)))
      (is (functionp handler))
      (funcall handler)
      (is (eq t called)))))

(test get-action-handler-not-found
  "Test getting non-existent handler returns NIL."
  (let ((registry (make-key-binding-registry)))
    (is (null (get-action-handler registry :nonexistent)))))

;;; --- Keyboard Input Handler Tests ---

(test make-keyboard-input-handler
  "Test creating a keyboard input handler."
  (let ((handler (make-keyboard-input-handler)))
    (is (typep handler 'keyboard-input-handler))
    (is (typep (handler-registry handler) 'key-binding-registry))))

(test make-keyboard-input-handler-custom-registry
  "Test creating handler with custom registry."
  (let* ((registry (make-key-binding-registry :bindings nil))
         (handler (make-keyboard-input-handler :registry registry)))
    (is (eq registry (handler-registry handler)))))

(test handle-key-press-tracks-state
  "Test that key press is tracked."
  (let ((handler (make-keyboard-input-handler)))
    (handle-key-press handler :w)
    (is (key-pressed-p handler :w))
    (is (key-just-pressed-p handler :w))))

(test handle-key-press-only-just-pressed-once
  "Test that key is only 'just pressed' on first press."
  (let ((handler (make-keyboard-input-handler)))
    (handle-key-press handler :w)
    (is (key-just-pressed-p handler :w))
    ;; Process to clear just-pressed
    (process-keyboard-input handler)
    ;; Press again while held - should not be just-pressed
    (handle-key-press handler :w)
    (is (key-pressed-p handler :w))
    (is (not (key-just-pressed-p handler :w)))))

(test handle-key-release-clears-state
  "Test that key release clears pressed state."
  (let ((handler (make-keyboard-input-handler)))
    (handle-key-press handler :w)
    (is (key-pressed-p handler :w))
    (handle-key-release handler :w)
    (is (not (key-pressed-p handler :w)))))

(test process-keyboard-input-hold-actions
  "Test that hold actions fire every frame while held."
  (let ((handler (make-keyboard-input-handler)))
    (handle-key-press handler :w)
    ;; First process
    (let ((actions (process-keyboard-input handler)))
      (is (member :fly-forward actions)))
    ;; Second process (key still held)
    (let ((actions (process-keyboard-input handler)))
      (is (member :fly-forward actions)))))

(test process-keyboard-input-press-actions
  "Test that press actions fire only once."
  (let ((handler (make-keyboard-input-handler)))
    (handle-key-press handler :f)
    ;; First process - should have action
    (let ((actions (process-keyboard-input handler)))
      (is (member :fork-here actions)))
    ;; Second process - should not have action (key still held but not just pressed)
    (let ((actions (process-keyboard-input handler)))
      (is (not (member :fork-here actions))))))

(test process-keyboard-input-multiple-keys
  "Test processing multiple keys at once."
  (let ((handler (make-keyboard-input-handler)))
    (handle-key-press handler :w)
    (handle-key-press handler :d)
    (let ((actions (process-keyboard-input handler)))
      (is (member :fly-forward actions))
      (is (member :fly-right actions)))))

(test execute-pending-actions-calls-handlers
  "Test that execute-pending-actions calls registered handlers."
  (let ((handler (make-keyboard-input-handler))
        (forward-called nil)
        (fork-called nil))
    (register-action-handler (handler-registry handler) :fly-forward
                             (lambda () (setf forward-called t)))
    (register-action-handler (handler-registry handler) :fork-here
                             (lambda () (setf fork-called t)))
    (handle-key-press handler :w)
    (handle-key-press handler :f)
    (process-keyboard-input handler)
    (execute-pending-actions handler)
    (is (eq t forward-called))
    (is (eq t fork-called))))

(test update-keyboard-input-combined
  "Test update-keyboard-input processes and executes."
  (let ((handler (make-keyboard-input-handler))
        (called nil))
    (register-action-handler (handler-registry handler) :fly-forward
                             (lambda () (setf called t)))
    (handle-key-press handler :w)
    (let ((executed (update-keyboard-input handler)))
      (is (member :fly-forward executed))
      (is (eq t called)))))

;;; --- Key Name Utility Tests ---

(test key-display-name-letters
  "Test display names for letter keys."
  (is (string= "W" (key-display-name :w)))
  (is (string= "A" (key-display-name :a)))
  (is (string= "F" (key-display-name :f))))

(test key-display-name-special
  "Test display names for special keys."
  (is (string= "[" (key-display-name :left-bracket)))
  (is (string= "]" (key-display-name :right-bracket)))
  (is (string= "Space" (key-display-name :space)))
  (is (string= "Enter" (key-display-name :return)))
  (is (string= "Esc" (key-display-name :escape))))

(test format-binding-help
  "Test formatting a binding as help text."
  (let ((binding (make-key-binding :w :fly-forward
                                   :description "Move forward")))
    (let ((help (format-binding-help binding)))
      (is (search "[W]" help))
      (is (search "Move forward" help)))))

(test format-bindings-help-all
  "Test formatting all bindings as help."
  (let* ((registry (make-key-binding-registry))
         (help-lines (format-bindings-help registry)))
    (is (listp help-lines))
    (is (= (length (list-bindings registry))
           (length help-lines)))))

;;; --- Category Filter Tests ---

(test camera-movement-bindings-filter
  "Test filtering camera movement bindings."
  (let* ((registry (make-key-binding-registry))
         (bindings (camera-movement-bindings registry)))
    (is (= 6 (length bindings)))  ; W A S D Q E
    (dolist (b bindings)
      (is (member (key-binding-action b)
                  '(:fly-forward :fly-backward :fly-left :fly-right
                    :fly-up :fly-down))))))

(test navigation-bindings-filter
  "Test filtering navigation bindings."
  (let* ((registry (make-key-binding-registry))
         (bindings (navigation-bindings registry)))
    (is (= 4 (length bindings)))  ; [ ] Home End
    (dolist (b bindings)
      (is (member (key-binding-action b)
                  '(:step-backward :step-forward :goto-genesis :goto-head))))))

(test branching-bindings-filter
  "Test filtering branching bindings."
  (let* ((registry (make-key-binding-registry))
         (bindings (branching-bindings registry)))
    (is (= 3 (length bindings)))  ; F M B
    (dolist (b bindings)
      (is (member (key-binding-action b)
                  '(:fork-here :merge-prompt :show-branches))))))

(test view-mode-bindings-filter
  "Test filtering view mode bindings."
  (let* ((registry (make-key-binding-registry))
         (bindings (view-mode-bindings registry)))
    (is (= 4 (length bindings)))  ; 1 2 3 4
    (dolist (b bindings)
      (is (member (key-binding-action b)
                  '(:set-view-timeline :set-view-tree
                    :set-view-constellation :set-view-diff))))))


;;; ═══════════════════════════════════════════════════════════════════
;;; Event Handling Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite event-handling-tests
  :in holodeck-tests
  :description "Tests for holodeck event types and event dispatching")

(in-suite event-handling-tests)

;;; --- Event Structure Tests ---

(test key-event-creation
  "Test creating a key event."
  (let ((event (make-key-event :key :w :action :press :modifiers (list :shift))))
    (is (typep event 'key-event))
    (is (eq :w (key-event-key event)))
    (is (eq :press (key-event-action event)))
    (is (equal (list :shift) (key-event-modifiers event)))))

(test key-event-defaults
  "Test key event default values."
  (let ((event (make-key-event :key :escape :action :release)))
    (is (eq :escape (key-event-key event)))
    (is (eq :release (key-event-action event)))
    (is (null (key-event-modifiers event)))
    (is (= 0.0 (holodeck-event-timestamp event)))))

(test mouse-move-event-creation
  "Test creating a mouse move event."
  (let ((event (make-mouse-move-event :x 100.0 :y 200.0 :timestamp 1.5)))
    (is (typep event 'mouse-move-event))
    (is (= 100.0 (mouse-move-event-x event)))
    (is (= 200.0 (mouse-move-event-y event)))
    (is (= 1.5 (holodeck-event-timestamp event)))))

(test mouse-button-event-creation
  "Test creating a mouse button event."
  (let ((event (make-mouse-button-event :button :right :action :press :x 50.0 :y 75.0)))
    (is (typep event 'mouse-button-event))
    (is (eq :right (mouse-button-event-button event)))
    (is (eq :press (mouse-button-event-action event)))
    (is (= 50.0 (mouse-button-event-x event)))
    (is (= 75.0 (mouse-button-event-y event)))))

(test scroll-event-creation
  "Test creating a scroll event."
  (let ((event (make-scroll-event :delta-x 0.0 :delta-y 3.0)))
    (is (typep event 'scroll-event))
    (is (= 0.0 (scroll-event-delta-x event)))
    (is (= 3.0 (scroll-event-delta-y event)))))

(test resize-event-creation
  "Test creating a resize event."
  (let ((event (make-resize-event :width 1280 :height 720)))
    (is (typep event 'resize-event))
    (is (= 1280 (resize-event-width event)))
    (is (= 720 (resize-event-height event)))))

;;; --- Window Setup Tests ---

(test window-setup-creates-handlers
  "Test that setup-scene creates input handlers."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (is (not (null (holodeck-keyboard-handler window))))
    (is (not (null (holodeck-camera-input-handler window))))
    (is (not (null (holodeck-camera window))))
    (is (typep (holodeck-keyboard-handler window) 'keyboard-input-handler))
    (is (typep (holodeck-camera-input-handler window) 'camera-input-handler))))

(test window-setup-links-camera-to-input-handler
  "Test that camera input handler is linked to the window camera."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (is (eq (holodeck-camera window)
            (input-handler-camera (holodeck-camera-input-handler window))))))

;;; --- Event Dispatch Tests ---

(test handle-key-press-event
  "Test that key press events are dispatched to keyboard handler."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let ((event (make-key-event :key :w :action :press)))
      (handle-holodeck-event window event)
      (is (key-pressed-p (holodeck-keyboard-handler window) :w)))))

(test handle-key-release-event
  "Test that key release events are dispatched to keyboard handler."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    ;; Press first
    (handle-holodeck-event window (make-key-event :key :w :action :press))
    (is (key-pressed-p (holodeck-keyboard-handler window) :w))
    ;; Then release
    (handle-holodeck-event window (make-key-event :key :w :action :release))
    (is (not (key-pressed-p (holodeck-keyboard-handler window) :w)))))

(test handle-mouse-move-event
  "Test that mouse move events update camera input handler position."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let ((event (make-mouse-move-event :x 150.0 :y 250.0)))
      (handle-holodeck-event window event)
      (let ((handler (holodeck-camera-input-handler window)))
        (is (= 150.0 (input-handler-mouse-x handler)))
        (is (= 250.0 (input-handler-mouse-y handler)))))))

(test handle-mouse-button-press-event
  "Test that mouse button press events update camera input handler."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let ((event (make-mouse-button-event :button :right :action :press :x 100.0 :y 100.0)))
      (handle-holodeck-event window event)
      (let ((handler (holodeck-camera-input-handler window)))
        (is (button-pressed-p handler :right))))))

(test handle-mouse-button-release-event
  "Test that mouse button release events update camera input handler."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    ;; Press first
    (handle-holodeck-event window (make-mouse-button-event :button :right :action :press :x 100.0 :y 100.0))
    (is (button-pressed-p (holodeck-camera-input-handler window) :right))
    ;; Then release
    (handle-holodeck-event window (make-mouse-button-event :button :right :action :release :x 100.0 :y 100.0))
    (is (not (button-pressed-p (holodeck-camera-input-handler window) :right)))))

(test handle-scroll-event
  "Test that scroll events accumulate in camera input handler."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let ((event (make-scroll-event :delta-y 5.0)))
      (handle-holodeck-event window event)
      (let ((handler (holodeck-camera-input-handler window)))
        (is (< (abs (- (input-handler-scroll-accumulator handler) 5.0)) 0.001))))))

(test handle-resize-event
  "Test that resize events update window dimensions."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window :width 1920 :height 1080)))
    (setup-scene window)
    (let ((event (make-resize-event :width 1280 :height 720)))
      (handle-holodeck-event window event)
      (is (= 1280 (window-width window)))
      (is (= 720 (window-height window))))))

;;; --- Process Input Tests ---

(test process-holodeck-input-executes-keyboard-actions
  "Test that process-holodeck-input executes pending keyboard actions."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window))
        (action-called nil))
    (setup-scene window)
    ;; Register a handler for fly-forward
    (register-action-handler
     (handler-registry (holodeck-keyboard-handler window))
     :fly-forward
     (lambda () (setf action-called t)))
    ;; Press W key
    (handle-holodeck-event window (make-key-event :key :w :action :press))
    ;; Process input
    (process-holodeck-input window)
    (is (eq t action-called))))

(test process-holodeck-input-applies-camera-orbit
  "Test that process-holodeck-input applies camera orbit from mouse drag."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let ((cam (holodeck-camera window))
          (initial-theta nil))
      ;; Set orbit speed for predictable test
      (setf (camera-orbit-speed cam) 0.01)
      (setf initial-theta (camera-theta cam))
      ;; Start right-drag
      (handle-holodeck-event window (make-mouse-move-event :x 100.0 :y 100.0))
      (handle-holodeck-event window (make-mouse-button-event :button :right :action :press :x 100.0 :y 100.0))
      ;; Move mouse
      (handle-holodeck-event window (make-mouse-move-event :x 200.0 :y 100.0))
      ;; Process input
      (process-holodeck-input window)
      ;; Camera should have orbited
      (is (not (= initial-theta (camera-theta cam)))))))

(test process-holodeck-input-applies-camera-zoom
  "Test that process-holodeck-input applies camera zoom from scroll."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let* ((cam (holodeck-camera window))
           (initial-distance (camera-distance cam)))
      ;; Scroll to zoom in
      (handle-holodeck-event window (make-scroll-event :delta-y 5.0))
      ;; Process input
      (process-holodeck-input window)
      ;; Camera should have zoomed in (distance decreased)
      (is (< (camera-distance cam) initial-distance)))))

;;; --- Combined Event Flow Tests ---

(test full-event-flow-keyboard
  "Test complete keyboard event flow from event to action execution."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window))
        (fork-called nil))
    (setup-scene window)
    ;; Register handler for fork action
    (register-action-handler
     (handler-registry (holodeck-keyboard-handler window))
     :fork-here
     (lambda () (setf fork-called t)))
    ;; Press F key (fork)
    (handle-holodeck-event window (make-key-event :key :f :action :press))
    ;; Process input
    (process-holodeck-input window)
    ;; Action should have been called
    (is (eq t fork-called))))

(test full-event-flow-camera-pan
  "Test complete camera pan flow from middle-drag events."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (let* ((cam (holodeck-camera window))
           (initial-target (3d-vectors:vcopy (camera-target cam))))
      ;; Set pan speed for predictable test
      (setf (camera-pan-speed cam) 0.1)
      ;; Start middle-drag
      (handle-holodeck-event window (make-mouse-move-event :x 100.0 :y 100.0))
      (handle-holodeck-event window (make-mouse-button-event :button :middle :action :press :x 100.0 :y 100.0))
      ;; Move mouse
      (handle-holodeck-event window (make-mouse-move-event :x 150.0 :y 120.0))
      ;; Process input
      (process-holodeck-input window)
      ;; Camera target should have moved
      (let ((diff (3d-vectors:v- (camera-target cam) initial-target)))
        (is (> (3d-vectors:vlength diff) 0.01))))))

(test event-dispatch-returns-t-for-handled-events
  "Test that handle-holodeck-event returns T for handled events."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    (is (eq t (handle-holodeck-event window (make-key-event :key :w :action :press))))
    (is (eq t (handle-holodeck-event window (make-mouse-move-event :x 100.0 :y 100.0))))
    (is (eq t (handle-holodeck-event window (make-mouse-button-event :button :left :action :press :x 100.0 :y 100.0))))
    (is (eq t (handle-holodeck-event window (make-scroll-event :delta-y 1.0))))
    (is (eq t (handle-holodeck-event window (make-resize-event :width 800 :height 600))))))

(test event-dispatch-returns-nil-for-unknown-events
  "Test that handle-holodeck-event returns NIL for unknown event types."
  (init-holodeck-storage)
  (let ((window (make-instance 'holodeck-window)))
    (setup-scene window)
    ;; Pass a non-event object
    (is (null (handle-holodeck-event window "not an event")))
    (is (null (handle-holodeck-event window 42)))
    (is (null (handle-holodeck-event window nil)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Live Agent Synchronization Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite live-agent-sync-tests
  :in holodeck-tests
  :description "Tests for live agent synchronization")

(in-suite live-agent-sync-tests)

(test agent-entity-map-operations
  "Test basic agent-entity map operations."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  ;; Initially empty
  (is (= 0 (sync-live-agents-count)))
  ;; Register an agent entity
  (let ((entity (cl-fast-ecs:make-entity)))
    (register-agent-entity "agent-1" entity)
    (is (= 1 (sync-live-agents-count)))
    (is (= entity (find-agent-entity "agent-1")))
    (is (null (find-agent-entity "agent-2"))))
  ;; Unregister
  (unregister-agent-entity "agent-1")
  (is (= 0 (sync-live-agents-count)))
  (is (null (find-agent-entity "agent-1")))
  ;; Clear all
  (register-agent-entity "a1" 1)
  (register-agent-entity "a2" 2)
  (is (= 2 (sync-live-agents-count)))
  (clear-agent-entity-map)
  (is (= 0 (sync-live-agents-count))))

(test should-sync-p-respects-interval
  "Test that should-sync-p respects the sync interval."
  (init-holodeck-storage)
  (let ((autopoiesis.holodeck::*last-sync-time* 0.0)
        (autopoiesis.holodeck::*elapsed-time* 0.0)
        (autopoiesis.holodeck::*sync-interval* 0.1))
    ;; At time 0, should not sync (just synced)
    (is (not (should-sync-p)))
    ;; After interval passes, should sync
    (setf autopoiesis.holodeck::*elapsed-time* 0.15)
    (is (should-sync-p))
    ;; After sync, should not sync again immediately
    (setf autopoiesis.holodeck::*last-sync-time* 0.15)
    (is (not (should-sync-p)))))

(test compute-agent-position-returns-valid-coords
  "Test that compute-agent-position returns valid 3D coordinates."
  (init-holodeck-storage)
  ;; Create a test agent
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (autopoiesis.agent:start-agent agent)
    (multiple-value-bind (x y z) (compute-agent-position agent)
      ;; X should be positive (time axis)
      (is (> x 0.0))
      ;; Y should be positive (abstraction level)
      (is (>= y 0.0))
      ;; Z should be non-negative (branch spread)
      (is (>= z 0.0))
      ;; All should be single-floats
      (is (typep x 'single-float))
      (is (typep y 'single-float))
      (is (typep z 'single-float)))))

(test compute-agent-position-varies-by-state
  "Test that compute-agent-position Y varies by agent state."
  (init-holodeck-storage)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    ;; Running state
    (autopoiesis.agent:start-agent agent)
    (multiple-value-bind (x1 y1 z1) (compute-agent-position agent)
      (declare (ignore x1 z1))
      ;; Pause agent
      (autopoiesis.agent:pause-agent agent)
      (multiple-value-bind (x2 y2 z2) (compute-agent-position agent)
        (declare (ignore x2 z2))
        ;; Y should be different for different states
        (is (not (= y1 y2)))))))

(test create-agent-marker-entity-has-all-components
  "Test that create-agent-marker-entity creates a complete entity."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  (reset-snapshot-entities)
  (let* ((agent (autopoiesis.agent:make-agent :name "marker-test"))
         (entity (create-agent-marker-entity agent)))
    ;; Entity should be valid
    (is (integerp entity))
    ;; Should have position
    (is (typep (position3d-x entity) 'single-float))
    ;; Should have scale (larger than default)
    (is (= 1.5 (scale3d-sx entity)))
    ;; Should have agent binding
    (is (string= "marker-test" (agent-binding-agent-name entity)))
    ;; Should have visual style for agent type
    (is (eq :agent (visual-style-node-type entity)))
    ;; Should have pulse rate for animation
    (is (> (visual-style-pulse-rate entity) 0.0))
    ;; Should be tracked
    (is (member entity *snapshot-entities*))
    ;; Should be in agent-entity map
    (is (= entity (find-agent-entity (autopoiesis.agent:agent-id agent))))))

(test sync-live-agents-creates-entities-for-running-agents
  "Test that sync-live-agents creates entities for running agents."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  (reset-snapshot-entities)
  ;; Clear agent registry for clean test
  (clrhash autopoiesis.agent::*agent-registry*)
  ;; Create and register a running agent
  (let ((agent (autopoiesis.agent:make-agent :name "sync-test")))
    (autopoiesis.agent:register-agent agent)
    (autopoiesis.agent:start-agent agent)
    ;; Initially no agent entities
    (is (= 0 (sync-live-agents-count)))
    ;; Sync
    (sync-live-agents)
    ;; Should have created entity
    (is (= 1 (sync-live-agents-count)))
    (let ((entity (find-agent-entity (autopoiesis.agent:agent-id agent))))
      (is (not (null entity)))
      ;; Entity should have correct agent binding
      (is (string= "sync-test" (agent-binding-agent-name entity))))
    ;; Clean up
    (autopoiesis.agent:unregister-agent agent)))

(test sync-live-agents-removes-entities-for-stopped-agents
  "Test that sync-live-agents removes entities for stopped agents."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  (reset-snapshot-entities)
  (clrhash autopoiesis.agent::*agent-registry*)
  ;; Create and register a running agent
  (let ((agent (autopoiesis.agent:make-agent :name "stop-test")))
    (autopoiesis.agent:register-agent agent)
    (autopoiesis.agent:start-agent agent)
    ;; Sync to create entity
    (sync-live-agents)
    (is (= 1 (sync-live-agents-count)))
    ;; Stop the agent
    (autopoiesis.agent:stop-agent agent)
    ;; Sync again
    (sync-live-agents)
    ;; Entity should be removed
    (is (= 0 (sync-live-agents-count)))
    ;; Clean up
    (autopoiesis.agent:unregister-agent agent)))

(test sync-live-agents-updates-existing-entity-positions
  "Test that sync-live-agents updates positions of existing entities."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  (reset-snapshot-entities)
  (clrhash autopoiesis.agent::*agent-registry*)
  ;; Set up delta time for position updates
  (let ((autopoiesis.holodeck::*delta-time* 0.5))
    (let ((agent (autopoiesis.agent:make-agent :name "update-test")))
      (autopoiesis.agent:register-agent agent)
      (autopoiesis.agent:start-agent agent)
      ;; Initial sync
      (sync-live-agents)
      (let* ((entity (find-agent-entity (autopoiesis.agent:agent-id agent)))
             (initial-x (position3d-x entity)))
        ;; Add a thought to change the position
        (autopoiesis.core:stream-append
         (autopoiesis.agent:agent-thought-stream agent)
         (autopoiesis.core:make-thought "test thought"))
        ;; Sync again with time for lerp
        (sync-live-agents)
        ;; Position should have moved toward new target
        ;; (may not be exactly at target due to lerp)
        (let ((new-x (position3d-x entity)))
          ;; X should have increased (more thoughts = further in time)
          (is (>= new-x initial-x))))
      ;; Clean up
      (autopoiesis.agent:unregister-agent agent))))

(test sync-live-agents-handles-multiple-agents
  "Test that sync-live-agents handles multiple agents correctly."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  (reset-snapshot-entities)
  (clrhash autopoiesis.agent::*agent-registry*)
  (let ((agent1 (autopoiesis.agent:make-agent :name "multi-1"))
        (agent2 (autopoiesis.agent:make-agent :name "multi-2"))
        (agent3 (autopoiesis.agent:make-agent :name "multi-3")))
    ;; Register all
    (autopoiesis.agent:register-agent agent1)
    (autopoiesis.agent:register-agent agent2)
    (autopoiesis.agent:register-agent agent3)
    ;; Start only two
    (autopoiesis.agent:start-agent agent1)
    (autopoiesis.agent:start-agent agent2)
    ;; Sync
    (sync-live-agents)
    ;; Should have 2 entities (only running agents)
    (is (= 2 (sync-live-agents-count)))
    (is (not (null (find-agent-entity (autopoiesis.agent:agent-id agent1)))))
    (is (not (null (find-agent-entity (autopoiesis.agent:agent-id agent2)))))
    (is (null (find-agent-entity (autopoiesis.agent:agent-id agent3))))
    ;; Start third agent
    (autopoiesis.agent:start-agent agent3)
    (sync-live-agents)
    (is (= 3 (sync-live-agents-count)))
    ;; Stop first agent
    (autopoiesis.agent:stop-agent agent1)
    (sync-live-agents)
    (is (= 2 (sync-live-agents-count)))
    (is (null (find-agent-entity (autopoiesis.agent:agent-id agent1))))
    ;; Clean up
    (autopoiesis.agent:unregister-agent agent1)
    (autopoiesis.agent:unregister-agent agent2)
    (autopoiesis.agent:unregister-agent agent3)))

(test sync-live-agents-idempotent
  "Test that calling sync-live-agents multiple times is idempotent."
  (init-holodeck-storage)
  (clear-agent-entity-map)
  (reset-snapshot-entities)
  (clrhash autopoiesis.agent::*agent-registry*)
  (let ((agent (autopoiesis.agent:make-agent :name "idempotent-test")))
    (autopoiesis.agent:register-agent agent)
    (autopoiesis.agent:start-agent agent)
    ;; Sync multiple times
    (sync-live-agents)
    (is (= 1 (sync-live-agents-count)))
    (let ((entity1 (find-agent-entity (autopoiesis.agent:agent-id agent))))
      (sync-live-agents)
      (is (= 1 (sync-live-agents-count)))
      ;; Should be the same entity
      (is (= entity1 (find-agent-entity (autopoiesis.agent:agent-id agent))))
      (sync-live-agents)
      (is (= 1 (sync-live-agents-count)))
      (is (= entity1 (find-agent-entity (autopoiesis.agent:agent-id agent)))))
    ;; Clean up
    (autopoiesis.agent:unregister-agent agent)))

