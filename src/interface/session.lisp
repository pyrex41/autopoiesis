;;;; session.lisp - Human interaction sessions
;;;;
;;;; Manages human-agent interaction sessions.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass session ()
  ((id :initarg :id
       :accessor session-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique session ID")
   (user :initarg :user
         :accessor session-user
         :documentation "Human user identifier")
   (agent :initarg :agent
          :accessor session-agent
          :documentation "Associated agent")
   (started :initarg :started
            :accessor session-started
            :initform (autopoiesis.core:get-precise-time)
            :documentation "When session started")
   (ended :initarg :ended
          :accessor session-ended
          :initform nil
          :documentation "When session ended")
   (navigator :initarg :navigator
              :accessor session-navigator
              :initform nil
              :documentation "Session's navigator")
   (viewport :initarg :viewport
             :accessor session-viewport
             :initform nil
             :documentation "Session's viewport"))
  (:documentation "An interactive session between human and agent"))

(defun make-session (user agent)
  "Create a new session."
  (make-instance 'session
                 :user user
                 :agent agent
                 :navigator (make-navigator)
                 :viewport (make-viewport)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Lifecycle
;;; ═══════════════════════════════════════════════════════════════════

(defvar *active-sessions* (make-hash-table :test 'equal)
  "Currently active sessions.")

(defun start-session (user agent)
  "Start a new session."
  (let ((session (make-session user agent)))
    (setf (gethash (session-id session) *active-sessions*) session)
    session))

(defun end-session (session)
  "End a session."
  (setf (session-ended session) (autopoiesis.core:get-precise-time))
  (remhash (session-id session) *active-sessions*)
  session)

(defun find-session (id)
  "Find a session by ID."
  (gethash id *active-sessions*))

(defun list-sessions ()
  "List all active sessions."
  (loop for session being the hash-values of *active-sessions*
        collect session))
