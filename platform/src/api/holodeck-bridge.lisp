;;;; holodeck-bridge.lisp - Frame Serializer for Holodeck ECS data
;;;;
;;;; Converts holodeck-frame render descriptions (plists with CLOS instances)
;;;; into JSON-serializable string-keyed plists for WebSocket transmission.
;;;;
;;;; The holodeck is an optional dependency (separate ASDF system), so all
;;;; access to holodeck symbols uses find-symbol + handler-case to degrade
;;;; gracefully when holodeck is not loaded.
;;;;
;;;; Wire format: These plists are consumed by encode-json (text frames)
;;;; or encode-msgpack (binary frames) via the existing wire-format machinery.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Vector Conversion Utilities
;;; ===================================================================

(defun vec3-to-list (v)
  "Convert a 3d-vectors:vec3 to a plain list, or pass through if already a list.
Returns NIL on error or if V is NIL."
  (when v
    (handler-case
        (if (listp v) v
            (let ((pkg (find-package :3d-vectors)))
              (when pkg
                (let ((vx (find-symbol "VX" pkg))
                      (vy (find-symbol "VY" pkg))
                      (vz (find-symbol "VZ" pkg)))
                  (when (and vx vy vz (fboundp vx) (fboundp vy) (fboundp vz))
                    (list (funcall vx v) (funcall vy v) (funcall vz v)))))))
      (error () nil))))

(defun matrix-to-list (m)
  "Convert a 3d-matrices matrix to a flat list of floats, or pass through.
Returns NIL on error or if M is NIL."
  (when m
    (handler-case
        (if (listp m) m
            (let ((pkg (find-package :3d-matrices)))
              (when pkg
                (let ((marr-fn (find-symbol "MARR" pkg)))
                  (when (and marr-fn (fboundp marr-fn))
                    (coerce (funcall marr-fn m) 'list))))))
      (error () nil))))

;;; ===================================================================
;;; Mesh Type Serialization
;;; ===================================================================

(defun serialize-mesh-type (mesh)
  "Extract mesh type string from a mesh-primitive CLOS instance.
Returns a lowercase string like \"sphere\", \"octahedron\", etc."
  (handler-case
      (let ((type-fn (find-symbol "MESH-PRIMITIVE-TYPE" :autopoiesis.holodeck)))
        (when (and type-fn (fboundp type-fn))
          (let ((type-val (funcall type-fn mesh)))
            (when type-val
              (string-downcase (symbol-name type-val))))))
    (error () "unknown")))

;;; ===================================================================
;;; Material Serialization
;;; ===================================================================

(defun serialize-material (material)
  "Extract numeric material properties as a string-keyed plist.
Accesses hologram-material / energy-beam-material slots via find-symbol
to avoid hard dependency on the holodeck package."
  (handler-case
      (let ((pkg (find-package :autopoiesis.holodeck)))
        (when pkg
          (flet ((slot-val (name)
                   (let ((fn (find-symbol name pkg)))
                     (when (and fn (fboundp fn))
                       (ignore-errors (funcall fn material))))))
            (let ((base-color (slot-val "MATERIAL-BASE-COLOR"))
                  (emissive-color (slot-val "MATERIAL-EMISSIVE-COLOR"))
                  (glow-intensity (slot-val "MATERIAL-GLOW-INTENSITY"))
                  (fresnel-power (slot-val "MATERIAL-FRESNEL-POWER"))
                  (scanline-speed (slot-val "MATERIAL-SCANLINE-SPEED"))
                  (opacity (slot-val "MATERIAL-OPACITY")))
              (list "baseColor" base-color
                    "emissiveColor" emissive-color
                    "glowIntensity" glow-intensity
                    "fresnelPower" fresnel-power
                    "scanlineSpeed" scanline-speed
                    "opacity" opacity)))))
    (error () nil)))

;;; ===================================================================
;;; Entity Description Serialization
;;; ===================================================================

(defun serialize-entity-desc (desc)
  "Convert a snapshot render description plist to a JSON-friendly string-keyed plist.

Input is a keyword plist from rendering.lisp with :entity, :visible-p, :position,
:scale, :rotation, :mesh, :material, :color, :glow-p, :label-text, :label-offset, :lod.

Output is a string-keyed plist suitable for jzon/msgpack encoding."
  (let ((mesh (getf desc :mesh))
        (material (getf desc :material)))
    (list "id" (getf desc :entity)
          "visible" (if (getf desc :visible-p) t 'null)
          "position" (getf desc :position)
          "scale" (getf desc :scale)
          "rotation" (getf desc :rotation)
          "meshType" (when mesh (serialize-mesh-type mesh))
          "material" (when material (serialize-material material))
          "color" (getf desc :color)
          "glow" (if (getf desc :glow-p) t 'null)
          "label" (getf desc :label-text)
          "labelOffset" (getf desc :label-offset)
          "lod" (when (getf desc :lod)
                  (string-downcase (symbol-name (getf desc :lod)))))))

;;; ===================================================================
;;; Connection Description Serialization
;;; ===================================================================

(defun serialize-connection-desc (desc)
  "Convert a connection render description plist to a JSON-friendly string-keyed plist.

Input is a keyword plist from rendering.lisp with :entity, :visible-p, :from-position,
:to-position, :midpoint, :connection-kind, :material, :color, :energy-flow.

Output is a string-keyed plist suitable for jzon/msgpack encoding."
  (list "id" (getf desc :entity)
        "visible" (if (getf desc :visible-p) t 'null)
        "from" (getf desc :from-position)
        "to" (getf desc :to-position)
        "midpoint" (getf desc :midpoint)
        "kind" (when (getf desc :connection-kind)
                 (string-downcase (symbol-name (getf desc :connection-kind))))
        "material" (when (getf desc :material)
                     (serialize-material (getf desc :material)))
        "color" (getf desc :color)
        "energyFlow" (getf desc :energy-flow)))

;;; ===================================================================
;;; Camera Serialization
;;; ===================================================================

(defun serialize-camera (frame-result)
  "Extract camera data from a holodeck-frame result plist.
Handles 3d-vectors:vec3 camera position by converting to a plain list."
  (let ((pos (getf frame-result :camera-position))
        (view (getf frame-result :view-matrix))
        (proj (getf frame-result :projection-matrix)))
    (list "position" (vec3-to-list pos)
          "viewMatrix" (matrix-to-list view)
          "projectionMatrix" (matrix-to-list proj))))

;;; ===================================================================
;;; HUD Command Serialization
;;; ===================================================================

(defun serialize-hud-command (cmd)
  "Serialize a HUD command for JSON transmission.
HUD commands are typically plists or strings from the holodeck HUD system."
  (typecase cmd
    (string cmd)
    (list (list "type" (when (keywordp (first cmd))
                         (string-downcase (symbol-name (first cmd))))
                "data" (format nil "~S" cmd)))
    (t (format nil "~S" cmd))))

;;; ===================================================================
;;; Full Frame Serialization
;;; ===================================================================

(defun serialize-holodeck-frame (frame-result)
  "Convert a holodeck-frame result plist into a JSON-serializable string-keyed plist.

Input FRAME-RESULT is the plist returned by holodeck-frame, containing:
  :dt, :camera-position, :view-matrix, :projection-matrix,
  :snapshot-descriptions, :connection-descriptions,
  :hud-commands, :hud-visible-p

Returns a string-keyed plist with keys: type, dt, entities, connections,
camera, hud, frameId. This plist can be passed directly to encode-json
or encode-msgpack via the wire-format layer."
  (list "type" "holodeck_frame"
        "dt" (getf frame-result :dt)
        "entities" (or (mapcar #'serialize-entity-desc
                               (getf frame-result :snapshot-descriptions))
                       #())
        "connections" (or (mapcar #'serialize-connection-desc
                                  (getf frame-result :connection-descriptions))
                          #())
        "camera" (serialize-camera frame-result)
        "hud" (when (getf frame-result :hud-visible-p)
                (list "visible" t
                      "commands" (or (mapcar #'serialize-hud-command
                                            (getf frame-result :hud-commands))
                                     #())))
        "frameId" (get-universal-time)))

;;; ===================================================================
;;; Convenience: Single Frame Capture
;;; ===================================================================

(defun holodeck-single-frame ()
  "Run one holodeck frame and return the serialized result.
Useful for REPL testing and one-shot frame capture from the API layer.
Returns a serialized string-keyed plist, or an error plist if the holodeck
is not running or not loaded."
  (handler-case
      (let* ((window-sym (find-symbol "*HOLODECK*" :autopoiesis.holodeck))
             (frame-fn (find-symbol "HOLODECK-FRAME" :autopoiesis.holodeck))
             (window (when (and window-sym (boundp window-sym))
                       (symbol-value window-sym))))
        (if (and window frame-fn (fboundp frame-fn))
            (serialize-holodeck-frame (funcall frame-fn window 0.016))
            (list "error" "holodeck not running")))
    (error (e)
      (list "error" (format nil "~a" e)))))
