;;;; key-bindings.lisp - Holodeck keyboard input handling and key bindings
;;;;
;;;; Defines the keyboard binding system for the 3D holodeck visualization.
;;;; Key bindings map keyboard input to actions like camera movement,
;;;; navigation through snapshots, branching operations, and UI control.
;;;;
;;;; Key categories:
;;;;   - Camera movement: WASD for fly mode, Q/E for up/down
;;;;   - Navigation: [/] for step backward/forward, Home/End for genesis/head
;;;;   - Branching: F for fork, M for merge, B for show branches
;;;;   - View modes: 1-4 for different visualization layouts
;;;;   - Focus: Tab to cycle focus, Space to toggle follow, O for overview
;;;;   - Detail: +/- for detail levels
;;;;   - Actions: Enter for human loop, Escape to exit, H for HUD, / for command
;;;;
;;;; Phase 8.5 - Input Handling (key bindings)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Key Constants
;;; ===================================================================
;;;
;;; Keyboard key identifiers as keywords.  These abstract over the
;;; specific key codes used by different windowing systems.

(defparameter *key-w* :w "W key for forward movement.")
(defparameter *key-a* :a "A key for left movement.")
(defparameter *key-s* :s "S key for backward movement.")
(defparameter *key-d* :d "D key for right movement.")
(defparameter *key-q* :q "Q key for down movement.")
(defparameter *key-e* :e "E key for up movement.")

(defparameter *key-left-bracket* :left-bracket "[ key for step backward.")
(defparameter *key-right-bracket* :right-bracket "] key for step forward.")
(defparameter *key-home* :home "Home key for goto genesis.")
(defparameter *key-end* :end "End key for goto head.")

(defparameter *key-f* :f "F key for fork operation.")
(defparameter *key-m* :m "M key for merge prompt.")
(defparameter *key-b* :b "B key for show branches.")

(defparameter *key-1* :1 "1 key for timeline view.")
(defparameter *key-2* :2 "2 key for tree view.")
(defparameter *key-3* :3 "3 key for constellation view.")
(defparameter *key-4* :4 "4 key for diff view.")

(defparameter *key-tab* :tab "Tab key for cycle focus next.")
(defparameter *key-shift-tab* :shift-tab "Shift+Tab for cycle focus prev.")
(defparameter *key-space* :space "Space key for toggle follow.")
(defparameter *key-o* :o "O key for overview.")

(defparameter *key-plus* :plus "+ key for increase detail.")
(defparameter *key-minus* :minus "- key for decrease detail.")
(defparameter *key-equals* :equals "= key (alternate for increase detail).")

(defparameter *key-return* :return "Return/Enter key for human loop interaction.")
(defparameter *key-escape* :escape "Escape key for exit visualization.")
(defparameter *key-h* :h "H key for toggle HUD.")
(defparameter *key-slash* :slash "/ key for command palette.")
(defparameter *key-question* :question "? key for help overlay.")

(defparameter *key-left-arrow* :left-arrow "Left arrow key for orbiting left.")
(defparameter *key-right-arrow* :right-arrow "Right arrow key for orbiting right.")
(defparameter *key-up-arrow* :up-arrow "Up arrow key for orbiting up.")
(defparameter *key-down-arrow* :down-arrow "Down arrow key for orbiting down.")
(defparameter *key-r* :r "R key for reset view.")

;;; ===================================================================
;;; Action Keywords
;;; ===================================================================
;;;
;;; Actions that can be triggered by key bindings.

(deftype holodeck-action ()
  "Valid holodeck action keywords."
  '(member
    ;; Camera movement
    :fly-forward :fly-backward :fly-left :fly-right :fly-up :fly-down
    :orbit-left :orbit-right :orbit-up :orbit-down :zoom-in :zoom-out :reset-view :switch-camera-mode
    ;; Navigation
    :step-backward :step-forward :goto-genesis :goto-head
    ;; Branching
    :fork-here :merge-prompt :show-branches
    ;; View modes
    :set-view-timeline :set-view-tree :set-view-constellation :set-view-diff :toggle-2d-3d
    ;; Focus
    :cycle-focus-next :cycle-focus-prev :toggle-follow :overview
    ;; Detail
    :increase-detail :decrease-detail
    ;; Actions
    :enter-human-loop :exit-visualization :toggle-hud :command-palette :show-help))

;;; ===================================================================
;;; Key Binding Structure
;;; ===================================================================

(defstruct (key-binding (:constructor make-key-binding (key action &key hold-action-p description)))
  "A binding from a key to an action.
   KEY is a keyword identifying the key.
   ACTION is a keyword identifying the action to perform.
   HOLD-ACTION-P if T means the action fires continuously while held.
   DESCRIPTION is a human-readable description of the binding."
  (key nil :type keyword :read-only t)
  (action nil :type keyword :read-only t)
  (hold-action-p nil :type boolean :read-only t)
  (description "" :type string :read-only t))

;;; ===================================================================
;;; Default Key Bindings
;;; ===================================================================

(defparameter *default-key-bindings*
  (list
   ;; Camera movement (hold actions)
   (make-key-binding :w :fly-forward
                     :hold-action-p t
                     :description "Move camera forward")
   (make-key-binding :s :fly-backward
                     :hold-action-p t
                     :description "Move camera backward")
   (make-key-binding :a :fly-left
                     :hold-action-p t
                     :description "Move camera left")
   (make-key-binding :d :fly-right
                     :hold-action-p t
                     :description "Move camera right")
   (make-key-binding :q :fly-down
                     :hold-action-p t
                     :description "Move camera down")
    (make-key-binding :e :fly-up
                      :hold-action-p t
                      :description "Move camera up")

    ;; Camera control (press actions)
    (make-key-binding :left-arrow :orbit-left
                      :hold-action-p t
                      :description "Orbit camera left")
    (make-key-binding :right-arrow :orbit-right
                      :hold-action-p t
                      :description "Orbit camera right")
    (make-key-binding :up-arrow :orbit-up
                      :hold-action-p t
                      :description "Orbit camera up")
    (make-key-binding :down-arrow :orbit-down
                      :hold-action-p t
                      :description "Orbit camera down")
    (make-key-binding :plus :zoom-in
                      :hold-action-p t
                      :description "Zoom camera in")
    (make-key-binding :equals :zoom-in
                      :hold-action-p t
                      :description "Zoom camera in")
    (make-key-binding :minus :zoom-out
                      :hold-action-p t
                      :description "Zoom camera out")
    (make-key-binding :r :reset-view
                      :hold-action-p nil
                      :description "Reset camera to default view")
    (make-key-binding :c :switch-camera-mode
                      :hold-action-p nil
                      :description "Switch between orbit and fly camera")

    ;; Navigation (press actions)
   (make-key-binding :left-bracket :step-backward
                     :hold-action-p nil
                     :description "Step to previous snapshot")
   (make-key-binding :right-bracket :step-forward
                     :hold-action-p nil
                     :description "Step to next snapshot")
   (make-key-binding :home :goto-genesis
                     :hold-action-p nil
                     :description "Jump to genesis snapshot")
   (make-key-binding :end :goto-head
                     :hold-action-p nil
                     :description "Jump to head snapshot")

   ;; Branching (press actions)
   (make-key-binding :f :fork-here
                     :hold-action-p nil
                     :description "Fork at current snapshot")
   (make-key-binding :m :merge-prompt
                     :hold-action-p nil
                     :description "Open merge dialog")
   (make-key-binding :b :show-branches
                     :hold-action-p nil
                     :description "Show branch list")

    ;; View modes (press actions)
    (make-key-binding :1 :set-view-timeline
                      :hold-action-p nil
                      :description "Timeline view")
    (make-key-binding :2 :set-view-tree
                      :hold-action-p nil
                      :description "Tree view")
    (make-key-binding :3 :set-view-constellation
                      :hold-action-p nil
                      :description "Constellation view")
    (make-key-binding :4 :set-view-diff
                      :hold-action-p nil
                      :description "Diff view")
    (make-key-binding :5 :toggle-2d-3d
                      :hold-action-p nil
                      :description "Toggle 2D/3D view mode")

   ;; Focus (press actions)
   (make-key-binding :tab :cycle-focus-next
                     :hold-action-p nil
                     :description "Focus next entity")
   (make-key-binding :shift-tab :cycle-focus-prev
                     :hold-action-p nil
                     :description "Focus previous entity")
   (make-key-binding :space :toggle-follow
                     :hold-action-p nil
                     :description "Toggle follow mode")
   (make-key-binding :o :overview
                     :hold-action-p nil
                     :description "Camera overview")

   ;; Detail (press actions)
   (make-key-binding :plus :increase-detail
                     :hold-action-p nil
                     :description "Increase detail level")
   (make-key-binding :equals :increase-detail
                     :hold-action-p nil
                     :description "Increase detail level")
   (make-key-binding :minus :decrease-detail
                     :hold-action-p nil
                     :description "Decrease detail level")

   ;; Actions (press actions)
   (make-key-binding :return :enter-human-loop
                     :hold-action-p nil
                     :description "Enter human interaction")
   (make-key-binding :escape :exit-visualization
                     :hold-action-p nil
                     :description "Exit holodeck")
   (make-key-binding :h :toggle-hud
                     :hold-action-p nil
                     :description "Toggle HUD visibility")
   (make-key-binding :slash :command-palette
                     :hold-action-p nil
                     :description "Open command palette")
   (make-key-binding :question :show-help
                     :hold-action-p nil
                     :description "Show help overlay"))
  "Default key bindings for the holodeck.")

;;; ===================================================================
;;; Key Binding Registry
;;; ===================================================================

(defclass key-binding-registry ()
  ((bindings :initarg :bindings
             :accessor registry-bindings
             :initform (make-hash-table :test 'eq)
             :documentation "Hash table mapping key keywords to key-binding structs.")
   (action-handlers :initarg :action-handlers
                    :accessor registry-action-handlers
                    :initform (make-hash-table :test 'eq)
                    :documentation "Hash table mapping action keywords to handler functions."))
  (:documentation
   "Registry of key bindings and their action handlers.
    Maintains a mapping from keys to bindings and from actions to handler functions."))

(defun make-key-binding-registry (&key (bindings *default-key-bindings*))
  "Create a new key-binding-registry initialized with BINDINGS."
  (let ((registry (make-instance 'key-binding-registry)))
    (dolist (binding bindings)
      (setf (gethash (key-binding-key binding) (registry-bindings registry))
            binding))
    registry))

;;; ===================================================================
;;; Registry Operations
;;; ===================================================================

(defgeneric get-binding (registry key)
  (:documentation "Get the key-binding for KEY from REGISTRY, or NIL if not bound."))

(defmethod get-binding ((registry key-binding-registry) key)
  "Look up the binding for KEY in the registry."
  (gethash key (registry-bindings registry)))

(defgeneric set-binding (registry key action &key hold-action-p description)
  (:documentation "Set or update a key binding in REGISTRY."))

(defmethod set-binding ((registry key-binding-registry) key action
                        &key (hold-action-p nil) (description ""))
  "Create or update a binding for KEY to ACTION."
  (setf (gethash key (registry-bindings registry))
        (make-key-binding key action
                          :hold-action-p hold-action-p
                          :description description))
  registry)

(defgeneric remove-binding (registry key)
  (:documentation "Remove the binding for KEY from REGISTRY."))

(defmethod remove-binding ((registry key-binding-registry) key)
  "Remove the binding for KEY."
  (remhash key (registry-bindings registry))
  registry)

(defgeneric list-bindings (registry)
  (:documentation "Return a list of all key-binding structs in REGISTRY."))

(defmethod list-bindings ((registry key-binding-registry))
  "Return all bindings as a list."
  (let ((result nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push v result))
             (registry-bindings registry))
    (sort result #'string< :key (lambda (b) (symbol-name (key-binding-key b))))))

(defgeneric bindings-for-action (registry action)
  (:documentation "Return all bindings that trigger ACTION."))

(defmethod bindings-for-action ((registry key-binding-registry) action)
  "Find all bindings that trigger the given ACTION."
  (let ((result nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (when (eq (key-binding-action v) action)
                 (push v result)))
             (registry-bindings registry))
    result))

;;; ===================================================================
;;; Action Handler Registration
;;; ===================================================================

(defgeneric register-action-handler (registry action handler)
  (:documentation "Register HANDLER function for ACTION in REGISTRY.
    HANDLER should be a function of no arguments."))

(defmethod register-action-handler ((registry key-binding-registry) action handler)
  "Register a handler function for an action."
  (setf (gethash action (registry-action-handlers registry)) handler)
  registry)

(defgeneric get-action-handler (registry action)
  (:documentation "Get the handler function for ACTION, or NIL if not registered."))

(defmethod get-action-handler ((registry key-binding-registry) action)
  "Look up the handler for ACTION."
  (gethash action (registry-action-handlers registry)))

;;; ===================================================================
;;; Keyboard Input Handler
;;; ===================================================================

(defclass keyboard-input-handler ()
  ((registry :initarg :registry
             :accessor handler-registry
             :initform (make-key-binding-registry)
             :documentation "The key binding registry.")
   (keys-pressed :initarg :keys-pressed
                 :accessor handler-keys-pressed
                 :initform (make-hash-table :test 'eq)
                 :documentation "Hash table of currently pressed keys (key -> T).")
   (keys-just-pressed :initarg :keys-just-pressed
                      :accessor handler-keys-just-pressed
                      :initform nil
                      :type list
                      :documentation "List of keys pressed this frame (for press actions).")
   (keys-just-released :initarg :keys-just-released
                       :accessor handler-keys-just-released
                       :initform nil
                       :type list
                       :documentation "List of keys released this frame.")
   (pending-actions :initarg :pending-actions
                    :accessor handler-pending-actions
                    :initform nil
                    :type list
                    :documentation "List of action keywords to execute this frame."))
  (:documentation
   "Handles keyboard input and translates key events to actions.
    Tracks key press/release state and dispatches to registered handlers."))

(defun make-keyboard-input-handler (&key (registry (make-key-binding-registry)))
  "Create a new keyboard-input-handler with the given REGISTRY."
  (make-instance 'keyboard-input-handler :registry registry))

;;; ===================================================================
;;; Key Event Handling
;;; ===================================================================

(defgeneric handle-key-press (handler key)
  (:documentation "Record that KEY has been pressed."))

(defmethod handle-key-press ((handler keyboard-input-handler) key)
  "Record a key press event.  Adds to just-pressed if not already held."
  (unless (gethash key (handler-keys-pressed handler))
    (push key (handler-keys-just-pressed handler)))
  (setf (gethash key (handler-keys-pressed handler)) t)
  handler)

(defgeneric handle-key-release (handler key)
  (:documentation "Record that KEY has been released."))

(defmethod handle-key-release ((handler keyboard-input-handler) key)
  "Record a key release event."
  (when (gethash key (handler-keys-pressed handler))
    (push key (handler-keys-just-released handler)))
  (remhash key (handler-keys-pressed handler))
  handler)

(defgeneric key-pressed-p (handler key)
  (:documentation "Return T if KEY is currently pressed."))

(defmethod key-pressed-p ((handler keyboard-input-handler) key)
  "Check if KEY is currently held down."
  (if (gethash key (handler-keys-pressed handler)) t nil))

(defgeneric key-just-pressed-p (handler key)
  (:documentation "Return T if KEY was pressed this frame."))

(defmethod key-just-pressed-p ((handler keyboard-input-handler) key)
  "Check if KEY was pressed this frame."
  (if (member key (handler-keys-just-pressed handler)) t nil))

;;; ===================================================================
;;; Per-Frame Processing
;;; ===================================================================

(defgeneric process-keyboard-input (handler)
  (:documentation "Process keyboard input for this frame.
    Collects actions from held keys (for hold actions) and just-pressed keys
    (for press actions).  Returns the list of actions to execute."))

(defmethod process-keyboard-input ((handler keyboard-input-handler))
  "Process all keyboard input and collect actions to execute.
   
   For hold actions: fires every frame while key is held.
   For press actions: fires once when key is pressed.
   
   Returns a list of action keywords."
  (let ((actions nil)
        (registry (handler-registry handler)))
    ;; Process hold actions for currently pressed keys
    (maphash (lambda (key pressed)
               (declare (ignore pressed))
               (let ((binding (get-binding registry key)))
                 (when (and binding (key-binding-hold-action-p binding))
                   (pushnew (key-binding-action binding) actions))))
             (handler-keys-pressed handler))
    
    ;; Process press actions for just-pressed keys
    (dolist (key (handler-keys-just-pressed handler))
      (let ((binding (get-binding registry key)))
        (when (and binding (not (key-binding-hold-action-p binding)))
          (pushnew (key-binding-action binding) actions))))
    
    ;; Store pending actions
    (setf (handler-pending-actions handler) actions)
    
    ;; Clear just-pressed/released lists for next frame
    (setf (handler-keys-just-pressed handler) nil)
    (setf (handler-keys-just-released handler) nil)
    
    actions))

(defgeneric execute-pending-actions (handler)
  (:documentation "Execute all pending actions using registered handlers.
    Returns the list of actions that were executed."))

(defmethod execute-pending-actions ((handler keyboard-input-handler))
  "Execute all pending actions by calling their registered handlers."
  (let ((executed nil)
        (registry (handler-registry handler)))
    (dolist (action (handler-pending-actions handler))
      (let ((action-handler (get-action-handler registry action)))
        (when action-handler
          (funcall action-handler)
          (push action executed))))
    (setf (handler-pending-actions handler) nil)
    (nreverse executed)))

;;; ===================================================================
;;; Convenience: Combined Process and Execute
;;; ===================================================================

(defgeneric update-keyboard-input (handler)
  (:documentation "Process keyboard input and execute all resulting actions.
    Returns the list of actions that were executed."))

(defmethod update-keyboard-input ((handler keyboard-input-handler))
  "Process input and execute actions in one call."
  (process-keyboard-input handler)
  (execute-pending-actions handler))

;;; ===================================================================
;;; Key Name Utilities
;;; ===================================================================

(defun key-display-name (key)
  "Return a human-readable display name for KEY."
  (case key
    (:w "W")
    (:a "A")
    (:s "S")
    (:d "D")
    (:q "Q")
    (:e "E")
    (:f "F")
    (:m "M")
    (:b "B")
    (:h "H")
    (:o "O")
    (:1 "1")
    (:2 "2")
    (:3 "3")
    (:4 "4")
    (:left-bracket "[")
    (:right-bracket "]")
    (:home "Home")
    (:end "End")
    (:tab "Tab")
    (:shift-tab "Shift+Tab")
    (:space "Space")
    (:plus "+")
    (:minus "-")
    (:equals "=")
    (:return "Enter")
    (:escape "Esc")
    (:slash "/")
    (:question "?")
    (:left-arrow "←")
    (:right-arrow "→")
    (:up-arrow "↑")
    (:down-arrow "↓")
    (:r "R")
    (t (string-capitalize (symbol-name key)))))

;;; ===================================================================
;;; Camera Action Handlers
;;; ===================================================================

(defgeneric register-camera-action-handlers (registry camera)
  (:documentation "Register action handlers for camera control actions.
    CAMERA should be an orbit-camera or fly-camera instance."))

(defmethod register-camera-action-handlers ((registry key-binding-registry) (camera orbit-camera))
  "Register handlers for orbit camera actions."
  ;; Orbit actions
  (register-action-handler registry :orbit-left
    (lambda () (orbit-camera-by camera -10.0 0.0)))
  (register-action-handler registry :orbit-right
    (lambda () (orbit-camera-by camera 10.0 0.0)))
  (register-action-handler registry :orbit-up
    (lambda () (orbit-camera-by camera 0.0 -10.0)))
  (register-action-handler registry :orbit-down
    (lambda () (orbit-camera-by camera 0.0 10.0)))
  ;; Zoom actions
  (register-action-handler registry :zoom-in
    (lambda () (zoom-camera-by camera -1.0)))
  (register-action-handler registry :zoom-out
    (lambda () (zoom-camera-by camera 1.0)))
  ;; Reset view
  (register-action-handler registry :reset-view
    (lambda ()
      (setf (camera-target camera) (vec3 0.0 0.0 0.0))
      (setf (camera-theta camera) 0.0)
      (setf (camera-phi camera) 0.3)
      (setf (camera-distance camera) 30.0))))

(defmethod register-camera-action-handlers ((registry key-binding-registry) (camera fly-camera))
  "Register handlers for fly camera actions."
  ;; For fly camera, orbit actions become look actions
  (register-action-handler registry :orbit-left
    (lambda () (fly-camera-look camera -0.1 0.0)))
  (register-action-handler registry :orbit-right
    (lambda () (fly-camera-look camera 0.1 0.0)))
  (register-action-handler registry :orbit-up
    (lambda () (fly-camera-look camera 0.0 -0.1)))
  (register-action-handler registry :orbit-down
    (lambda () (fly-camera-look camera 0.0 0.1)))
  ;; Zoom actions - for fly camera, zoom becomes move forward/backward
  (register-action-handler registry :zoom-in
    (lambda () (fly-camera-move camera :forward)))
  (register-action-handler registry :zoom-out
    (lambda () (fly-camera-move camera :backward)))
  ;; Reset view
  (register-action-handler registry :reset-view
    (lambda ()
      (setf (fly-camera-position-vec camera) (vec3 0.0 5.0 30.0))
      (setf (fly-camera-yaw camera) 0.0)
      (setf (fly-camera-pitch camera) 0.0))))

(defun format-binding-help (binding)
  "Format a key-binding as a help string: [KEY] Description."
  (format nil "[~A] ~A"
          (key-display-name (key-binding-key binding))
          (key-binding-description binding)))

(defun format-bindings-help (registry &key (category nil))
  "Format all bindings in REGISTRY as help text.
   If CATEGORY is provided, filter to bindings whose action starts with that prefix."
  (let ((bindings (list-bindings registry)))
    (when category
      (let ((prefix (string category)))
        (setf bindings
              (remove-if-not
               (lambda (b)
                 (let ((action-name (symbol-name (key-binding-action b))))
                   (and (>= (length action-name) (length prefix))
                        (string-equal prefix action-name :end2 (length prefix)))))
               bindings))))
    (mapcar #'format-binding-help bindings)))

;;; ===================================================================
;;; Predefined Action Categories
;;; ===================================================================

(defun camera-movement-bindings (registry)
  "Return bindings for camera movement actions."
  (remove-if-not
   (lambda (b)
     (member (key-binding-action b)
             '(:fly-forward :fly-backward :fly-left :fly-right :fly-up :fly-down)))
   (list-bindings registry)))

(defun navigation-bindings (registry)
  "Return bindings for navigation actions."
  (remove-if-not
   (lambda (b)
     (member (key-binding-action b)
             '(:step-backward :step-forward :goto-genesis :goto-head)))
   (list-bindings registry)))

(defun branching-bindings (registry)
  "Return bindings for branching actions."
  (remove-if-not
   (lambda (b)
     (member (key-binding-action b)
             '(:fork-here :merge-prompt :show-branches)))
   (list-bindings registry)))

(defun view-mode-bindings (registry)
  "Return bindings for view mode actions."
  (remove-if-not
   (lambda (b)
     (member (key-binding-action b)
             '(:set-view-timeline :set-view-tree :set-view-constellation :set-view-diff)))
   (list-bindings registry)))
