;;;; util.lisp - Terminal utility functions for Autopoiesis Visualization
;;;;
;;;; Provides low-level terminal utilities using cl-charms (ncurses bindings):
;;;; - ANSI color code constants for styled output
;;;; - Cursor movement and positioning
;;;; - Screen clearing and terminal management
;;;; - Terminal size detection

(in-package #:autopoiesis.viz)

;;; ═══════════════════════════════════════════════════════════════════
;;; ANSI Color Code Constants
;;; ═══════════════════════════════════════════════════════════════════

;;; Basic control codes
(defparameter +color-reset+ "\x1b[0m")

(defparameter +ansi-reset+ (format nil "~c[0m" #\Escape)
  "Complete ANSI reset sequence string.")

(defparameter +ansi-bold+ (format nil "~c[1m" #\Escape)
  "ANSI bold/bright sequence.")

(defparameter +ansi-dim+ (format nil "~c[2m" #\Escape)
  "ANSI dim sequence.")

;;; Foreground color codes (ANSI 256-color mode for richer palette)
;;; Format: ESC[38;5;<n>m where n is the color number

(defun make-fg-color (color-num)
  "Create ANSI escape sequence for foreground color COLOR-NUM (0-255)."
  (format nil "~c[38;5;~dm" #\Escape color-num))

(defun make-bg-color (color-num)
  "Create ANSI escape sequence for background color COLOR-NUM (0-255)."
  (format nil "~c[48;5;~dm" #\Escape color-num))

;;; Node type color constants (ANSI 256-color palette)
;;; These map to the theme colors from the spec

(defparameter +color-snapshot+ (make-fg-color 75)   ; Blue
  "Color for regular snapshot nodes.")

(defparameter +color-decision+ (make-fg-color 220)  ; Gold/Yellow
  "Color for decision nodes.")

(defparameter +color-fork+ (make-fg-color 135)      ; Purple
  "Color for fork/branch nodes.")

(defparameter +color-merge+ (make-fg-color 84)      ; Green
  "Color for merge nodes.")

(defparameter +color-current+ (make-fg-color 87)    ; Cyan
  "Color for current/active node.")

(defparameter +color-human+ (make-fg-color 208)     ; Orange
  "Color for human interaction nodes.")

(defparameter +color-error+ (make-fg-color 196)     ; Red
  "Color for error nodes.")

(defparameter +color-border+ (make-fg-color 240)    ; Gray
  "Color for borders and structural elements.")

(defparameter +color-text+ (make-fg-color 252)      ; Light gray
  "Color for general text.")

(defparameter +color-highlight+ (make-fg-color 231) ; White
  "Color for highlighted/selected items.")

(defparameter +color-dim+ (make-fg-color 242)       ; Dimmed gray
  "Color for dimmed/inactive elements.")

(defparameter +color-bold+ +ansi-bold+
  "Bold text attribute.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Glyph Constants
;;; ═══════════════════════════════════════════════════════════════════

(defparameter +glyph-snapshot+ "○"
  "Glyph for regular snapshot nodes.")

(defparameter +glyph-decision+ "◆"
  "Glyph for decision nodes.")

(defparameter +glyph-fork+ "◇"
  "Glyph for fork/branch point nodes.")

(defparameter +glyph-merge+ "◈"
  "Glyph for merge nodes.")

(defparameter +glyph-current+ "●"
  "Glyph for current/head node.")

(defparameter +glyph-genesis+ "★"
  "Glyph for genesis (initial) node.")

(defparameter +glyph-human+ "◉"
  "Glyph for human interaction nodes.")

(defparameter +glyph-action+ "□"
  "Glyph for action nodes.")

(defun snapshot-glyph (snapshot-type)
  "Return the appropriate glyph character for SNAPSHOT-TYPE."
  (ecase snapshot-type
    (:snapshot +glyph-snapshot+)
    (:decision +glyph-decision+)
    (:fork +glyph-fork+)
    (:merge +glyph-merge+)
    (:current +glyph-current+)
    (:genesis +glyph-genesis+)
    (:human +glyph-human+)
    (:action +glyph-action+)
    (:thought +glyph-snapshot+)
    (:reflection +glyph-snapshot+)
    (:observation +glyph-snapshot+)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cursor Movement Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun move-cursor (row col &optional (stream *standard-output*))
  "Move cursor to ROW, COL (1-indexed) position.
   Uses ANSI escape sequence for terminal positioning."
  (format stream "~c[~d;~dH" #\Escape row col)
  (force-output stream))

(defun move-cursor-up (n &optional (stream *standard-output*))
  "Move cursor up N lines."
  (when (plusp n)
    (format stream "~c[~dA" #\Escape n)
    (force-output stream)))

(defun move-cursor-down (n &optional (stream *standard-output*))
  "Move cursor down N lines."
  (when (plusp n)
    (format stream "~c[~dB" #\Escape n)
    (force-output stream)))

(defun move-cursor-forward (n &optional (stream *standard-output*))
  "Move cursor forward (right) N columns."
  (when (plusp n)
    (format stream "~c[~dC" #\Escape n)
    (force-output stream)))

(defun move-cursor-backward (n &optional (stream *standard-output*))
  "Move cursor backward (left) N columns."
  (when (plusp n)
    (format stream "~c[~dD" #\Escape n)
    (force-output stream)))

(defun save-cursor-position (&optional (stream *standard-output*))
  "Save current cursor position."
  (format stream "~c[s" #\Escape)
  (force-output stream))

(defun restore-cursor-position (&optional (stream *standard-output*))
  "Restore previously saved cursor position."
  (format stream "~c[u" #\Escape)
  (force-output stream))

;;; ═══════════════════════════════════════════════════════════════════
;;; Color Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun set-color (color-code &optional (stream *standard-output*))
  "Set terminal color using COLOR-CODE (an ANSI escape string)."
  (write-string color-code stream)
  (force-output stream))

(defun reset-color (&optional (stream *standard-output*))
  "Reset terminal color to default."
  (write-string +ansi-reset+ stream)
  (force-output stream))

(defun with-color-output (color-code text &optional (stream *standard-output*))
  "Output TEXT with COLOR-CODE, then reset."
  (set-color color-code stream)
  (write-string text stream)
  (reset-color stream))

(defmacro with-color ((color-code &optional (stream '*standard-output*)) &body body)
  "Execute BODY with COLOR-CODE set, resetting color afterward."
  (let ((stream-var (gensym "STREAM")))
    `(let ((,stream-var ,stream))
       (unwind-protect
            (progn
              (set-color ,color-code ,stream-var)
              ,@body)
         (reset-color ,stream-var)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Screen Management Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun clear-screen (&optional (stream *standard-output*))
  "Clear the entire terminal screen and move cursor to home."
  (format stream "~c[2J~c[H" #\Escape #\Escape)
  (force-output stream))

(defun clear-line (&optional (stream *standard-output*))
  "Clear the current line."
  (format stream "~c[2K" #\Escape)
  (force-output stream))

(defun clear-to-end-of-line (&optional (stream *standard-output*))
  "Clear from cursor to end of current line."
  (format stream "~c[K" #\Escape)
  (force-output stream))

(defun clear-to-end-of-screen (&optional (stream *standard-output*))
  "Clear from cursor to end of screen."
  (format stream "~c[J" #\Escape)
  (force-output stream))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cursor Visibility Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun hide-cursor (&optional (stream *standard-output*))
  "Hide the terminal cursor."
  (format stream "~c[?25l" #\Escape)
  (force-output stream))

(defun show-cursor (&optional (stream *standard-output*))
  "Show the terminal cursor."
  (format stream "~c[?25h" #\Escape)
  (force-output stream))

;;; ═══════════════════════════════════════════════════════════════════
;;; Terminal Size Detection
;;; ═══════════════════════════════════════════════════════════════════

(defun get-terminal-size ()
  "Get terminal dimensions as (VALUES width height).
   Tries stty size first, then environment variables, then defaults."
  (or (ignore-errors
        (let ((output (string-trim '(#\Space #\Newline #\Return)
                                   (uiop:run-program '("stty" "size")
                                                     :input :interactive
                                                     :output :string
                                                     :error-output nil))))
          (when (and output (plusp (length output)))
            (let* ((space-pos (position #\Space output))
                   (rows (parse-integer (subseq output 0 space-pos)))
                   (cols (parse-integer (subseq output (1+ space-pos)))))
              (when (and (plusp rows) (plusp cols))
                (values cols rows))))))
      ;; Fallback to environment variables or defaults
      (let ((cols (or (ignore-errors
                        (parse-integer (uiop:getenv "COLUMNS")))
                      80))
            (rows (or (ignore-errors
                        (parse-integer (uiop:getenv "LINES")))
                      24)))
        (values cols rows))))

(defun get-terminal-width ()
  "Get terminal width in columns."
  (multiple-value-bind (width height)
      (get-terminal-size)
    (declare (ignore height))
    width))

(defun get-terminal-height ()
  "Get terminal height in rows."
  (multiple-value-bind (width height)
      (get-terminal-size)
    (declare (ignore width))
    height))

;;; ═══════════════════════════════════════════════════════════════════
;;; Terminal Session Management
;;; ═══════════════════════════════════════════════════════════════════

(defvar *terminal-initialized* nil
  "Flag indicating whether terminal is in raw mode.")

(defun init-terminal ()
  "Initialize terminal for raw input mode.
   Returns T if successful, NIL otherwise."
  (unless *terminal-initialized*
    (hide-cursor)
    (clear-screen)
    (setf *terminal-initialized* t))
  *terminal-initialized*)

(defun cleanup-terminal ()
  "Restore terminal to normal mode."
  (when *terminal-initialized*
    (reset-color)
    (show-cursor)
    (clear-screen)
    (setf *terminal-initialized* nil)))

(defmacro with-terminal (&body body)
  "Execute BODY with terminal initialized, cleaning up afterward.
   Ensures terminal state is restored even if an error occurs."
  `(progn
     (init-terminal)
     (unwind-protect
          (progn ,@body)
       (cleanup-terminal))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Box Drawing Utilities
;;; ═══════════════════════════════════════════════════════════════════

;;; Unicode box drawing characters for creating panels and borders

(defparameter +box-horizontal+ "─"
  "Horizontal line character.")

(defparameter +box-vertical+ "│"
  "Vertical line character.")

(defparameter +box-top-left+ "┌"
  "Top-left corner character.")

(defparameter +box-top-right+ "┐"
  "Top-right corner character.")

(defparameter +box-bottom-left+ "└"
  "Bottom-left corner character.")

(defparameter +box-bottom-right+ "┘"
  "Bottom-right corner character.")

(defparameter +box-t-down+ "┬"
  "T-junction pointing down.")

(defparameter +box-t-up+ "┴"
  "T-junction pointing up.")

(defparameter +box-t-right+ "├"
  "T-junction pointing right.")

(defparameter +box-t-left+ "┤"
  "T-junction pointing left.")

(defparameter +box-cross+ "┼"
  "Cross junction.")

;;; Branch connection characters for timeline visualization

(defparameter +branch-horizontal+ "─"
  "Horizontal branch line.")

(defparameter +branch-vertical+ "│"
  "Vertical branch line.")

(defparameter +branch-fork-down+ "┬"
  "Fork going down from timeline.")

(defparameter +branch-fork-up+ "┴"
  "Fork going up from timeline.")

(defparameter +branch-corner-down-right+ "┌"
  "Corner: down then right.")

(defparameter +branch-corner-down-left+ "┐"
  "Corner: down then left.")

(defparameter +branch-corner-up-right+ "└"
  "Corner: up then right.")

(defparameter +branch-corner-up-left+ "┘"
  "Corner: up then left.")

(defun draw-horizontal-line (row col length &optional (stream *standard-output*))
  "Draw a horizontal line at ROW, COL of LENGTH characters."
  (move-cursor row col stream)
  (dotimes (i length)
    (write-string +box-horizontal+ stream))
  (force-output stream))

(defun draw-vertical-line (row col length &optional (stream *standard-output*))
  "Draw a vertical line starting at ROW, COL for LENGTH characters."
  (dotimes (i length)
    (move-cursor (+ row i) col stream)
    (write-string +box-vertical+ stream))
  (force-output stream))

(defun draw-box (row col width height &optional (stream *standard-output*))
  "Draw a box at ROW, COL with WIDTH and HEIGHT."
  ;; Top border
  (move-cursor row col stream)
  (write-string +box-top-left+ stream)
  (dotimes (i (- width 2))
    (write-string +box-horizontal+ stream))
  (write-string +box-top-right+ stream)

  ;; Side borders
  (dotimes (i (- height 2))
    (move-cursor (+ row i 1) col stream)
    (write-string +box-vertical+ stream)
    (move-cursor (+ row i 1) (+ col width -1) stream)
    (write-string +box-vertical+ stream))

  ;; Bottom border
  (move-cursor (+ row height -1) col stream)
  (write-string +box-bottom-left+ stream)
  (dotimes (i (- width 2))
    (write-string +box-horizontal+ stream))
  (write-string +box-bottom-right+ stream)
  (force-output stream))

;;; ═══════════════════════════════════════════════════════════════════
;;; Text Formatting Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun truncate-string (string max-length &optional (ellipsis "…"))
  "Truncate STRING to MAX-LENGTH, adding ELLIPSIS if truncated."
  (if (<= (length string) max-length)
      string
      (concatenate 'string
                   (subseq string 0 (- max-length (length ellipsis)))
                   ellipsis)))

(defun pad-string (string width &key (align :left) (pad-char #\Space))
  "Pad STRING to WIDTH characters with specified alignment.
   ALIGN can be :left, :right, or :center."
  (let ((len (length string)))
    (cond
      ((<= width len) (subseq string 0 width))
      (t (let ((padding (- width len)))
           (ecase align
             (:left (concatenate 'string string
                                 (make-string padding :initial-element pad-char)))
             (:right (concatenate 'string
                                  (make-string padding :initial-element pad-char)
                                  string))
             (:center (let* ((left-pad (floor padding 2))
                             (right-pad (- padding left-pad)))
                        (concatenate 'string
                                     (make-string left-pad :initial-element pad-char)
                                     string
                                     (make-string right-pad :initial-element pad-char))))))))))

(defun format-at (row col format-string &rest args)
  "Format output at specific ROW, COL position."
  (move-cursor row col)
  (apply #'format t format-string args))

;;; ═══════════════════════════════════════════════════════════════════
;;; Color Mapping Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-type-color (snapshot-type)
  "Return the color code for SNAPSHOT-TYPE."
  (ecase snapshot-type
    (:snapshot +color-snapshot+)
    (:decision +color-decision+)
    (:fork +color-fork+)
    (:merge +color-merge+)
    (:current +color-current+)
    (:genesis +color-snapshot+)
    (:human +color-human+)
    (:action +color-snapshot+)
    (:thought +color-snapshot+)
    (:reflection +color-snapshot+)
    (:observation +color-snapshot+)
    (:error +color-error+)))
