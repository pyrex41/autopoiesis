(in-package #:autopoiesis.viz)

(defparameter *viz-config*
  '(:colors (:snapshot 75
            :decision 220
            :fork 135
            :merge 84
            :current 87
            :human 208
            :error 196
            :border 240
            :text 252
            :highlight 231
            :dim 242)
    :symbols (:snapshot \"○\"
              :decision \"◆\"
              :fork \"◇\"
              :merge \"◈\"
              :current \"●\"
              :genesis \"★\"
              :human \"◉\"
              :action \"□\")
    :dimensions (:timeline-width 80
                  :detail-panel-width 40
                  :status-bar-height 3
                  :max-timeline-height 20
                  :border-padding 1
                  :legend-width 20)))

(defun viz-config ()
  \"Return the current visualization configuration plist.\"
  *viz-config*)

(defun (setf viz-config) (new-config)
  \"Set the visualization configuration to NEW-CONFIG.\"
  (setf *viz-config* new-config))

(defun config-colors ()
  \"Return the colors configuration plist.\"
  (getf *viz-config* :colors))

(defun config-symbols ()
  \"Return the symbols configuration plist.\"
  (getf *viz-config* :symbols))

(defun config-dimensions ()
  \"Return the dimensions configuration plist.\"
  (getf *viz-config* :dimensions))
