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
;;; Team Data Serialization
;;; ===================================================================

(defun serialize-team-data ()
  "Serialize team topology data from holodeck ECS for JSON transmission.
   Returns a list of team plists, each containing id, arrangement, members,
   and center position.  Returns NIL if holodeck is not loaded."
  (handler-case
      (let ((pkg (find-package :autopoiesis.holodeck)))
        (when pkg
          (let ((team-map-sym (find-symbol "*TEAM-ENTITY-MAP*" pkg))
                (member-map-sym (find-symbol "*TEAM-MEMBER-BINDINGS*" pkg))
                (layout-center-x (find-symbol "TEAM-LAYOUT-CENTER-X" pkg))
                (layout-center-y (find-symbol "TEAM-LAYOUT-CENTER-Y" pkg))
                (layout-center-z (find-symbol "TEAM-LAYOUT-CENTER-Z" pkg))
                (layout-arrangement (find-symbol "TEAM-LAYOUT-ARRANGEMENT" pkg))
                (layout-radius (find-symbol "TEAM-LAYOUT-RADIUS" pkg))
                (entity-valid-fn (find-symbol "ENTITY-VALID-P" pkg)))
            (when (and team-map-sym (boundp team-map-sym)
                       member-map-sym (boundp member-map-sym))
              (let ((team-map (symbol-value team-map-sym))
                    (member-map (symbol-value member-map-sym))
                    (result nil))
                (maphash
                 (lambda (tid anchor)
                   (when (and (funcall entity-valid-fn anchor)
                              (fboundp layout-center-x))
                     (let ((members (gethash tid member-map))
                           (cx (ignore-errors (funcall layout-center-x anchor)))
                           (cy (ignore-errors (funcall layout-center-y anchor)))
                           (cz (ignore-errors (funcall layout-center-z anchor)))
                           (arr (ignore-errors (funcall layout-arrangement anchor)))
                           (rad (ignore-errors (funcall layout-radius anchor))))
                       (push (list "id" tid
                                   "arrangement" (when arr
                                                    (string-downcase (symbol-name arr)))
                                   "radius" rad
                                   "center" (list cx cy cz)
                                   "memberCount" (length members)
                                   "memberIds" (mapcar (lambda (eid) eid) members))
                             result))))
                 team-map)
                result)))))
    (error () nil)))

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
        "teams" (or (serialize-team-data) #())
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

;;; ===================================================================
;;; Holodeck Availability Check
;;; ===================================================================

(defun holodeck-available-p ()
  "Return the holodeck window instance if holodeck is loaded and active, or NIL."
  (let ((pkg (find-package :autopoiesis.holodeck)))
    (when pkg
      (let ((holodeck-sym (find-symbol "*HOLODECK*" pkg)))
        (when (and holodeck-sym (boundp holodeck-sym))
          (symbol-value holodeck-sym))))))

;;; ===================================================================
;;; Broadcast Loop
;;; ===================================================================

(defvar *holodeck-bridge-thread* nil
  "Background thread streaming holodeck frames to WebSocket subscribers.")

(defvar *holodeck-bridge-running* nil
  "Flag for cooperative shutdown of the holodeck bridge thread.")

(defun start-holodeck-bridge ()
  "Start the holodeck frame broadcast loop.
   Spawns a background thread that calls holodeck-single-frame at 10fps
   and broadcasts the result to all connections subscribed to \"holodeck\"."
  (when *holodeck-bridge-thread*
    (stop-holodeck-bridge))
  (setf *holodeck-bridge-running* t)
  (setf *holodeck-bridge-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (loop while *holodeck-bridge-running*
                 do (handler-case
                        (when (holodeck-available-p)
                          (let ((frame (holodeck-single-frame)))
                            (when (and frame (not (getf frame "error")))
                              (broadcast-stream-data frame
                                                     :subscription-type "holodeck"))))
                      (error (e)
                        (log:warn "Holodeck bridge error: ~a" e)))
                    (sleep 0.1)))  ; 10fps
         :name "holodeck-bridge"))
  (log:info "Holodeck bridge started (10fps)"))

(defun stop-holodeck-bridge ()
  "Stop the holodeck frame broadcast loop and join the thread."
  (setf *holodeck-bridge-running* nil)
  (when (and *holodeck-bridge-thread*
             (bordeaux-threads:thread-alive-p *holodeck-bridge-thread*))
    (ignore-errors (bordeaux-threads:join-thread *holodeck-bridge-thread*)))
  (setf *holodeck-bridge-thread* nil)
  (log:info "Holodeck bridge stopped"))

;;; ===================================================================
;;; Holodeck Interaction Helpers
;;; ===================================================================

(defun holodeck-execute-action (action-keyword)
  "Execute a holodeck action by dispatching through the key-binding registry.
   ACTION-KEYWORD should be a keyword like :ORBIT-LEFT."
  (let ((holodeck-val (holodeck-available-p)))
    (unless holodeck-val
      (return-from holodeck-execute-action nil))
    (let* ((pkg (find-package :autopoiesis.holodeck))
           (get-handler-fn (when pkg (find-symbol "GET-ACTION-HANDLER" pkg))))
      (when (and get-handler-fn (fboundp get-handler-fn))
        (let* ((handler-fn (find-symbol "HOLODECK-KEYBOARD-HANDLER" pkg))
               (registry-fn (find-symbol "HANDLER-REGISTRY" pkg)))
          (when (and handler-fn (fboundp handler-fn)
                     registry-fn (fboundp registry-fn))
            (let* ((input-handler (funcall handler-fn holodeck-val))
                   (registry (when input-handler (funcall registry-fn input-handler)))
                   (action-handler (when registry (funcall get-handler-fn registry action-keyword))))
              (when action-handler
                (funcall action-handler)
                t))))))))
