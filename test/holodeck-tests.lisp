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
