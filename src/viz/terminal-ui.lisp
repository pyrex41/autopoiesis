(defmethod update ((ui terminal-ui))
  \"
Update UI state: resize, navigator sync, etc.\"

  (update-terminal-size ui)
  (when-let (nav (ui-navigator ui))
    ;; Sync navigator with timeline if needed
    (unless (zerop (ui-terminal-width ui))
      (calculate-layout ui))))