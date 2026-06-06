;;;; aether-runtime.lisp - Run a live agent from the AETHER spatial canvas.
;;;;
;;;; Spawns `rho --output-format stream-json -p <prompt>` as a subprocess,
;;;; parses its stream-json events, writes each into the snapshot store as
;;;; a new child snapshot, and broadcasts each new snapshot to subscribers
;;;; of the WebSocket channel "aether:snapshots".
;;;;
;;;; The minimum "this is a real tool" round-trip:
;;;;   POST /api/aether/spawn  → returns {session_id, initial_snapshot_id}
;;;;   WS subscribe "aether:snapshots" → receives aether_snapshot frames
;;;;
;;;; Text-delta events from rho are buffered and flushed as one snapshot
;;;; per ~800ms (or per ~80 chars, or on any non-delta event) so we don't
;;;; create one snapshot per token.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Session table
;;; ===================================================================

(defvar *aether-sessions* (make-hash-table :test 'equal)
  "session-id (string) → aether-session struct")

(defvar *aether-sessions-lock* (bordeaux-threads:make-lock "aether-sessions"))

;;; ===================================================================
;;; Filesystem capture
;;; ===================================================================

(defvar *aether-content-store* nil
  "Single shared content-store for AETHER snapshot filesystem blobs.
   The in-memory hash-table is the fast path; aether-blob-store.lisp
   mirrors every captured blob out to an LMDB env at
   *aether-blob-store-path* so checkouts survive SBCL restart.")

(defun ensure-aether-content-store ()
  (or *aether-content-store*
      (setf *aether-content-store*
            (autopoiesis.snapshot:make-content-store))))

(defparameter *fs-scan-exclude*
  '(".git" "node_modules" "__pycache__" ".venv" "venv" "dist" "build"
    "target" ".next" ".cache" ".DS_Store")
  "Directory prefixes excluded from working-dir scans. Skip the things
   nobody actually wants to checkpoint.")

(defun should-capture-fs-p (event-type)
  "Re-scan only on events that could plausibly have changed disk state.
   Everything else inherits the previous scan's entries on this session
   — same Merkle root, blob-store unchanged."
  (or (string= event-type "prompt")
      (string= event-type "tool_result")
      (string= event-type "complete")
      (string= event-type "error")))

(defun capture-tree-entries (session event-type)
  "Either re-scan the session's cwd (returning fresh entries) or hand back
   the entries from the previous capture. nil if no cwd is configured."
  (let ((cwd (aether-session-cwd session)))
    (cond
      ((or (null cwd) (zerop (length cwd))) nil)
      ((not (should-capture-fs-p event-type))
       (aether-session-last-tree-entries session))
      ((not (probe-file (uiop:ensure-directory-pathname cwd)))
       (aether-session-last-tree-entries session))
      (t
       (handler-case
           (let* ((store (ensure-aether-content-store))
                  (entries (autopoiesis.snapshot:scan-directory-flat
                            (uiop:ensure-directory-pathname cwd)
                            store
                            :exclude *fs-scan-exclude*)))
             (setf (aether-session-last-tree-entries session) entries)
             ;; Mirror any newly-stored blobs out to LMDB so they survive
             ;; SBCL restart. Cheap when nothing changed (already-persisted
             ;; hashes are skipped by persist-content-store-blobs).
             (ignore-errors (persist-content-store-blobs store))
             entries)
         (error (e)
           (log:warn "aether: FS scan failed for ~A: ~A" cwd e)
           (aether-session-last-tree-entries session)))))))

(defstruct aether-session
  id                          ; "ses-XXXXXXXX"
  prompt
  model
  cwd                         ; working directory for rho (-C); nil = inherit
  lineage-name                ; consistent across all snapshots of this session
  parent-snapshot-id          ; nil for fresh sessions, set for forks
  current-snapshot-id         ; latest snapshot in this session (next parent)
  event-count                 ; monotonic counter, drives `ticks` metadata
  thread                      ; the bt:thread running the subprocess
  started-at                  ; universal-time when spawned
  status                      ; :running | :complete | :error
  error-message               ; populated when status = :error
  ;; Text-delta buffer
  delta-buffer                ; string accumulator
  delta-last-flush            ; internal-real-time of last flush
  ;; Filesystem capture — sticky across events; only re-scanned when an
  ;; event could have changed disk state (prompt, tool_result, complete).
  last-tree-entries)          ; sorted list of tree entries from last scan

;;; ===================================================================
;;; Utilities
;;; ===================================================================

(defun find-rho-executable ()
  "Find the rho binary in PATH. Falls back to ~/.local/bin/rho then 'rho'."
  (or (handler-case
          (let ((p (uiop:run-program "which rho"
                                     :output '(:string :stripped t)
                                     :ignore-error-status t)))
            (when (and p (not (string= "" p))) p))
        (error () nil))
      (when (probe-file (merge-pathnames ".local/bin/rho" (user-homedir-pathname)))
        (namestring (merge-pathnames ".local/bin/rho" (user-homedir-pathname))))
      "rho"))

(defun new-aether-session-id ()
  (format nil "ses-~(~A~)"
          (subseq (autopoiesis.core:make-uuid) 0 8)))

(defun lineage-name-from-session (session-id)
  (format nil "live-~A" (subseq session-id 4)))

(defun truncate-text (text max-len)
  (if (and text (> (length text) max-len))
      (concatenate 'string (subseq text 0 max-len) "…")
      (or text "")))

(defun event-mood (event-type has-text-p)
  "Map a rho event-type to a spectral mood.
   rho emits: session / text_delta / tool_start / tool_result / complete / error."
  (cond
    ((string= event-type "session")     "explorer")  ; birth event
    ((string= event-type "text_delta")  "linear")    ; ongoing thought
    ((string= event-type "tool_start")  "explorer")  ; reaching out
    ((string= event-type "tool_result") "reflector") ; what came back
    ((string= event-type "complete")    "reflector") ; settled
    ((string= event-type "error")       "reflector")
    (has-text-p                          "linear")
    (t                                   "linear")))

;;; ===================================================================
;;; Snapshot creation + broadcast
;;; ===================================================================

(defun aether-snapshot (session event-type text)
  "Create + save + broadcast one snapshot for SESSION. Returns the snapshot."
  (let* ((depth (aether-session-event-count session))
         (lineage (aether-session-lineage-name session))
         (tree-entries (capture-tree-entries session event-type))
         (file-count (length (or tree-entries '())))
         (metadata (list :lineage lineage
                         :mood (event-mood event-type (and text (> (length text) 0)))
                         :event-type event-type
                         :session (aether-session-id session)
                         :ticks depth
                         :depth depth
                         :text (truncate-text text 240)
                         :cwd (or (aether-session-cwd session) "")
                         :files file-count))
         (state (list :aether-event
                      :event-type event-type
                      :text text
                      :session (aether-session-id session)
                      :tick depth))
         (parent (aether-session-current-snapshot-id session))
         (snap (autopoiesis.snapshot:make-snapshot
                state
                :parent parent
                :metadata metadata
                :tree-entries tree-entries)))
    (autopoiesis.snapshot:save-snapshot snap)
    (setf (aether-session-current-snapshot-id session)
          (autopoiesis.snapshot:snapshot-id snap))
    (incf (aether-session-event-count session))
    (broadcast-aether-snapshot snap)
    snap))

(defun broadcast-aether-snapshot (snap)
  "Push a new-snapshot frame to all WS subscribers of channel aether:snapshots.
   Uses cl-json (same encoder as REST responses) so the frontend sees an
   identical shape between GET /api/snapshots and a live WS push."
  (handler-case
      (let ((payload (cl-json:encode-json-to-string
                      `((:type . "aether_snapshot")
                        (:snapshot . ,(snapshot-summary-alist snap))))))
        (broadcast-message payload :subscription-type "aether:snapshots"))
    (error (e)
      (log:warn "aether: broadcast failed: ~A" e))))

;;; ===================================================================
;;; Text-delta buffer / flush
;;; ===================================================================

(defconstant +delta-flush-interval-internal+
  (* internal-time-units-per-second 8/10)
  "Flush the delta buffer after this many internal-time units.")

(defconstant +delta-flush-chars+ 80
  "Flush the delta buffer once it grows past this many characters.")

(defun flush-delta-buffer (session &key (force nil))
  "If the buffer has content, emit a text_delta snapshot and clear."
  (let ((buf (aether-session-delta-buffer session)))
    (when (and (or force (> (length buf) 0)) (> (length buf) 0))
      (aether-snapshot session "text_delta" buf)
      (setf (aether-session-delta-buffer session) "")
      (setf (aether-session-delta-last-flush session)
            (get-internal-real-time)))))

(defun maybe-flush-delta-buffer (session)
  (let* ((buf (aether-session-delta-buffer session))
         (since (- (get-internal-real-time)
                   (aether-session-delta-last-flush session))))
    (when (or (>= (length buf) +delta-flush-chars+)
              (>= since +delta-flush-interval-internal+))
      (flush-delta-buffer session))))

;;; ===================================================================
;;; rho subprocess + stream-json loop
;;; ===================================================================

(defun handle-rho-event (session event)
  "Dispatch one parsed rho event (a hash-table) into the snapshot stream."
  (let* ((event-type (gethash "type" event))
         (text (gethash "text" event)))
    (cond
      ;; Stream tokens — buffer
      ((string= event-type "text_delta")
       (when text
         (setf (aether-session-delta-buffer session)
               (concatenate 'string
                            (aether-session-delta-buffer session)
                            text)))
       (maybe-flush-delta-buffer session))
      ;; All other events flush any buffered text first, then snapshot.
      (t
       (flush-delta-buffer session :force t)
       (let ((payload
               (cond
                 (text text)
                 ;; rho session start: {session_id, type}
                 ((string= event-type "session")
                  (format nil "rho session ~A"
                          (or (gethash "session_id" event) "?")))
                 ;; rho tool invocation: {tool_name, input_summary, tool_id, type}
                 ((string= event-type "tool_start")
                  (format nil "~A(~A)"
                          (or (gethash "tool_name" event) "tool")
                          (truncate-text (or (gethash "input_summary" event) "") 120)))
                 ;; rho tool return: {tool_name, success, tool_id, type}
                 ((string= event-type "tool_result")
                  (format nil "~A → ~A"
                          (or (gethash "tool_name" event) "tool")
                          (if (gethash "success" event) "ok" "failed")))
                 ;; rho completion: {session_id, success, type}
                 ((string= event-type "complete")
                  (if (gethash "success" event) "completed" "failed"))
                 ;; Unknown event type — show the type at least.
                 (t (format nil "[~A]" event-type)))))
         (aether-snapshot session event-type payload))))))

(defun run-rho-thread (session)
  "Body of the subprocess thread. Reads stream-json line by line."
  (let* ((exe (find-rho-executable))
         ;; rho-cli uses positional or -p; positional is safer with embedded args
         (base-args (list "-p" (aether-session-prompt session)
                          "--output-format" "stream-json"
                          "--model" (aether-session-model session)))
         (args (let ((cwd (aether-session-cwd session)))
                 (if (and cwd (> (length cwd) 0))
                     (append (list "-C" cwd) base-args)
                     base-args)))
         (cmd (format nil "~A ~{~A~^ ~}"
                      exe
                      (mapcar (lambda (s) (format nil "'~A'"
                                                   (with-output-to-string (out)
                                                     (loop for c across s
                                                           do (if (char= c #\')
                                                                  (write-string "'\\''" out)
                                                                  (write-char c out))))))
                              args))))
    (handler-case
        (let ((process (sb-ext:run-program "/bin/sh"
                                           (list "-c" (format nil "~A </dev/null" cmd))
                                           :output :stream
                                           :error :output
                                           :wait nil)))
          (unwind-protect
              (let ((stdout (sb-ext:process-output process)))
                (loop for line = (read-line stdout nil :eof)
                      until (eq line :eof)
                      when (and line (> (length line) 0) (char= (char line 0) #\{))
                      do (handler-case
                             (let ((event (com.inuoe.jzon:parse line)))
                               (handle-rho-event session event))
                           (error (e)
                             (log:warn "aether: bad event line '~A': ~A" line e))))
                (flush-delta-buffer session :force t)
                (setf (aether-session-status session) :complete))
            (when process
              (sb-ext:process-wait process)
              (sb-ext:process-close process))))
      (error (e)
        (setf (aether-session-status session) :error)
        (setf (aether-session-error-message session) (format nil "~A" e))
        (flush-delta-buffer session :force t)
        (handler-case (aether-snapshot session "error" (format nil "~A" e))
          (error () nil))
        (log:warn "aether: rho thread error: ~A" e)))))

;;; ===================================================================
;;; Public entry — spawn
;;; ===================================================================

(defvar *aether-workspace-root*
  (namestring (merge-pathnames "aether-workspace/" (user-homedir-pathname)))
  "Base directory under which UI-spawned agents get a per-session working
   directory. Each session writes to <root>/<lineage>/ so files are always
   in a known, findable place — and so FS capture / checkout actually work.")

(defun default-cwd-for-session (lineage)
  "A known, findable per-session working dir under *aether-workspace-root*.
   Created eagerly so rho has somewhere to write."
  (let ((dir (namestring
              (merge-pathnames (format nil "~A/" lineage)
                               (uiop:ensure-directory-pathname *aether-workspace-root*)))))
    (ensure-directories-exist (uiop:ensure-directory-pathname dir))
    dir))

(defun spawn-aether-session (&key prompt parent model cwd)
  "Spawn a new live agent session. Returns (values session initial-snapshot).
   PROMPT is required. PARENT is an optional parent snapshot id. MODEL
   defaults to claude-haiku. CWD is the agent's working directory (rho -C).
   When omitted it defaults to ~/aether-workspace/<lineage>/ so files always
   land somewhere known and FS capture / checkout work — never silently in
   the caller's tree."
  (unless (and prompt (> (length prompt) 0))
    (error "spawn-aether-session: prompt is required"))
  (let* ((session-id (new-aether-session-id))
         (lineage (lineage-name-from-session session-id))
         (effective-cwd (if (and cwd (> (length cwd) 0))
                            cwd
                            (default-cwd-for-session lineage)))
         (session (make-aether-session
                   :id session-id
                   :prompt prompt
                   :model (or model "claude-haiku")
                   :cwd effective-cwd
                   :lineage-name lineage
                   :parent-snapshot-id parent
                   :current-snapshot-id parent
                   :event-count 0
                   :started-at (get-universal-time)
                   :status :running
                   :delta-buffer ""
                   :delta-last-flush (get-internal-real-time))))
    ;; Record this session in the table immediately so callers / listings
    ;; can see it before the first snapshot writes.
    (bordeaux-threads:with-lock-held (*aether-sessions-lock*)
      (setf (gethash session-id *aether-sessions*) session))
    ;; Initial "prompt" snapshot — root of this session's lineage on the map.
    (let ((initial (aether-snapshot session "prompt" prompt)))
      ;; Spawn the rho thread; it writes subsequent snapshots as events arrive.
      (setf (aether-session-thread session)
            (bordeaux-threads:make-thread
             (lambda () (run-rho-thread session))
             :name (format nil "aether-rho-~A" session-id)))
      (values session initial))))

(defun list-aether-sessions ()
  "Return a snapshot of current sessions as a list of plists."
  (bordeaux-threads:with-lock-held (*aether-sessions-lock*)
    (loop for s being the hash-values of *aether-sessions*
          collect (list :id (aether-session-id s)
                        :prompt (truncate-text (aether-session-prompt s) 100)
                        :model (aether-session-model s)
                        :status (string-downcase (symbol-name (aether-session-status s)))
                        :started-at (aether-session-started-at s)
                        :event-count (aether-session-event-count s)
                        :current-snapshot-id (aether-session-current-snapshot-id s)))))

;;; ===================================================================
;;; REST route handler
;;; ===================================================================

(defun snapshot-cwd (snap)
  "Read the captured cwd from a snapshot's metadata, or nil."
  (let* ((md (autopoiesis.snapshot:snapshot-metadata snap))
         (cwd (getf md :cwd)))
    (when (and cwd (> (length cwd) 0)) cwd)))

(defun snapshot-full-text (snap)
  "The FULL (untruncated) event text from agent-state. Metadata's :text is
   capped at 240 chars for display; this returns what the agent actually
   produced — file content for a write, the command for a bash, the agent's
   narration for thinking/complete."
  (let ((state (autopoiesis.snapshot:snapshot-agent-state snap)))
    (if (and (listp state) (eq (car state) :aether-event))
        (or (getf (cdr state) :text) "")
        "")))

(defun content-alist-for (snap)
  "Readable content payload for a snapshot: full text + event type + cwd.
   For a tool_result the useful content is the tool's INPUT (the file
   content for a write, the command for a bash) — that lives on the parent
   tool_start snapshot — so we surface that instead of the bare 'name → ok'."
  (let* ((md (autopoiesis.snapshot:snapshot-metadata snap))
         (event-type (or (getf md :event-type) ""))
         (display-text (snapshot-full-text snap)))
    (when (string= event-type "tool_result")
      (let* ((parent-id (autopoiesis.snapshot:snapshot-parent snap))
             (parent (and parent-id (autopoiesis.snapshot:load-snapshot parent-id))))
        (when parent
          (let ((ptext (snapshot-full-text parent)))
            (when (> (length ptext) 0) (setf display-text ptext))))))
    `((:snapshot_id . ,(autopoiesis.snapshot:snapshot-id snap))
      (:event_type . ,event-type)
      (:cwd . ,(or (snapshot-cwd snap) ""))
      (:text . ,display-text))))

(defun reveal-path (path)
  "Open PATH in the OS file browser (macOS `open`, Linux `xdg-open`).
   Returns T on a clean spawn. Best-effort; errors are swallowed."
  (let ((opener #+darwin "open" #-darwin "xdg-open"))
    (handler-case
        (progn
          (uiop:launch-program (list opener path))
          t)
      (error (e)
        (log:warn "aether: reveal failed for ~A: ~A" path e)
        nil))))

(defun files-listing-for (snap)
  "Build a JSON-friendly summary of the FS tree captured at SNAP."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap)))
    `((:snapshot_id . ,(autopoiesis.snapshot:snapshot-id snap))
      (:tree_root . ,(or (autopoiesis.snapshot:snapshot-tree-root snap) ""))
      (:cwd . ,(or (snapshot-cwd snap) ""))
      (:count . ,(length (or entries '())))
      (:files . ,(loop for e in (or entries '())
                       when (eq (autopoiesis.snapshot:entry-type e) :file)
                       collect `((:path . ,(autopoiesis.snapshot:entry-path e))
                                 (:size . ,(or (autopoiesis.snapshot:entry-size e) 0))
                                 (:hash . ,(or (autopoiesis.snapshot:entry-hash e) ""))))))))

(defun checkout-snapshot-to (snap target-dir)
  "Materialize SNAP's tree-entries into TARGET-DIR. Returns the count of
   entries written. Destructive — clears TARGET-DIR contents first (but
   does NOT delete the directory itself; .git etc. are left alone).
   nil tree-entries is valid and means 'clear the directory'.

   Hydrates missing blobs from LMDB into the in-memory content-store first,
   so checkouts of pre-restart snapshots still find their file contents."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap))
        (target (uiop:ensure-directory-pathname target-dir))
        (store (ensure-aether-content-store)))
    (when entries
      (ignore-errors
        (hydrate-content-store-blobs store (tree-entry-hashes entries))))
    (ensure-directories-exist target)
    ;; Clear existing files/dirs in target (mirrors local-backend approach).
    (dolist (f (uiop:directory-files target))
      (ignore-errors (delete-file f)))
    (dolist (d (uiop:subdirectories target))
      (let ((name (car (last (pathname-directory d)))))
        ;; Don't recurse into excluded dirs — leave .git etc. alone.
        (unless (member name *fs-scan-exclude* :test #'string=)
          (ignore-errors (uiop:delete-directory-tree d :validate t)))))
    (if entries
        (autopoiesis.snapshot:materialize-tree entries target store)
        0)))

;;; ===================================================================
;;; Per-line file blame (aether-blame)
;;; ===================================================================
;;;
;;; For any file at any snapshot, walk back through the same lineage and
;;; attribute each line to the EARLIEST ancestor whose tree contained that
;;; exact line. Think `git blame` over cognitive ancestry — clicking a
;;; line tells you which agent reasoning event (= which star) introduced it.

(defun blob-as-string (content-store hash)
  "Fetch BLOB at HASH from CONTENT-STORE and decode as UTF-8.
   Returns nil if the blob is missing. Returns the decoded string otherwise
   (or, on a decode error, an empty string — we never crash blame on binary)."
  (let ((bytes (autopoiesis.snapshot:store-get-blob content-store hash)))
    (when bytes
      (handler-case (babel:octets-to-string bytes :encoding :utf-8)
        (error () "")))))

(defun split-lines (text)
  "Split TEXT on #\\Newline, preserving order. The last element is empty
   when TEXT ends with a newline — that matches how we want to display
   line counts (one entry per actual line in the file)."
  (when text
    (let ((lines '())
          (start 0)
          (len (length text)))
      (loop for i from 0 below len
            when (char= (char text i) #\Newline)
              do (push (subseq text start i) lines)
                 (setf start (1+ i)))
      (push (subseq text start len) lines)
      (nreverse lines))))

(defun file-lines-from-snapshot (snap path)
  "Return the list of UTF-8-decoded lines for PATH at SNAP, or nil if PATH
   is not present in SNAP's tree (or SNAP has no tree-entries at all)."
  (let ((entries (autopoiesis.snapshot:snapshot-tree-entries snap)))
    (when entries
      (let ((entry (find-if (lambda (e)
                              (and (eq (autopoiesis.snapshot:entry-type e) :file)
                                   (string= (autopoiesis.snapshot:entry-path e) path)))
                            entries)))
        (when entry
          (let ((text (blob-as-string (ensure-aether-content-store)
                                       (autopoiesis.snapshot:entry-hash entry))))
            (and text (split-lines text))))))))

(defun snapshot-lineage (snap)
  "Return the :lineage metadata value (string) for SNAP, or nil."
  (let ((md (autopoiesis.snapshot:snapshot-metadata snap)))
    (and md (getf md :lineage))))

(defun walk-lineage-ancestors (snap)
  "Walk from SNAP back along parent pointers, collecting snapshots that
   share SNAP's :lineage metadata. Returns the list ordered oldest → newest
   (so [0] is the lineage root and [last] is SNAP itself). Snapshots from
   other lineages are not included — blame stays meaningful by staying
   inside one lineage chain."
  (let ((target-lineage (snapshot-lineage snap))
        (chain '())
        (cur snap)
        (max-walk 10000))
    (loop for n from 0 below max-walk
          while cur
          do (let ((lin (snapshot-lineage cur)))
               (if (or (null target-lineage)
                       (and lin (string= lin target-lineage)))
                   (push cur chain)
                   ;; Different lineage — stop walking. The DAG can fork
                   ;; into a new live-XXX session and that's a hard boundary
                   ;; for attribution.
                   (return)))
             (let ((pid (autopoiesis.snapshot:snapshot-parent cur)))
               (setf cur (and pid (autopoiesis.snapshot:load-snapshot pid)))))
    chain))

(defun compute-blame (snap path)
  "For each line of PATH at SNAP, find the earliest ancestor whose copy of
   PATH already contained that exact line. Returns a list of plists, one
   per line, each with keys :line :text :origin-snapshot :origin-event-type
   :origin-timestamp :origin-lineage. Returns nil if PATH is not in SNAP.

   Algorithm: collect the lineage chain oldest→newest, hash each ancestor's
   line set, then for each current line find the first ancestor that
   already contained it. If no ancestor had it, the origin is SNAP itself."
  (let ((current-lines (file-lines-from-snapshot snap path)))
    (unless current-lines
      (return-from compute-blame nil))
    (let* ((chain (walk-lineage-ancestors snap))
           ;; Precompute (ancestor . line-set) pairs, skipping ancestors
           ;; that don't include PATH in their tree.
           (ancestor-line-sets
             (loop for a in chain
                   for lines = (file-lines-from-snapshot a path)
                   when lines
                   collect (let ((set (make-hash-table :test 'equal)))
                             (dolist (l lines) (setf (gethash l set) t))
                             (cons a set)))))
      (loop for line in current-lines
            for idx from 1
            for origin = (or (loop for (anc . line-set) in ancestor-line-sets
                                   when (gethash line line-set)
                                   return anc)
                             ;; Fallback: SNAP itself is the origin.
                             snap)
            collect (let ((md (autopoiesis.snapshot:snapshot-metadata origin)))
                      (list :line idx
                            :text line
                            :origin-snapshot (autopoiesis.snapshot:snapshot-id origin)
                            :origin-event-type (or (getf md :event-type) "")
                            :origin-timestamp (or (autopoiesis.snapshot:snapshot-timestamp origin) 0)
                            :origin-lineage (or (getf md :lineage) "")))))))

(defun blame-result-alist (snap path blames)
  "Build the JSON response body for /blame."
  `((:snapshot_id . ,(autopoiesis.snapshot:snapshot-id snap))
    (:path . ,path)
    (:line_count . ,(length blames))
    (:blames . ,(coerce
                 (loop for b in blames
                       collect `((:line . ,(getf b :line))
                                 (:text . ,(getf b :text))
                                 (:origin_snapshot . ,(getf b :origin-snapshot))
                                 (:origin_event_type . ,(getf b :origin-event-type))
                                 (:origin_timestamp . ,(getf b :origin-timestamp))
                                 (:origin_lineage . ,(getf b :origin-lineage))))
                 'vector))))

;;; ===================================================================
;;; Discharge-report history (the iteration lineage)
;;; ===================================================================
;;;
;;; `sb` accumulates one discharge_report.json per gate run in a
;;; project's .sb/history/, named <ISO-timestamp>Z-<git-short-sha>.json.
;;; The cadence is per-run, many-to-one against commits (a SHA can recur
;;; across several runs), so lineage is ordered by the filename timestamp
;;; with the SHA carried along as a secondary badge.

(defparameter +sb-history-filename-re+
  "^(\\d{4}-\\d{2}-\\d{2}T\\d{6}Z)-(.+)\\.json$"
  "Shen-Backpressure history filename: <ISO-timestamp>Z-<git-short-sha>.json.")

(defun sb-summary-status (summary)
  "Derive a single status string from a decoded discharge SUMMARY alist:
   \"violated\" if any rule is violated, else \"unproven\" if any is
   unproven, else \"discharged\". Coloring comes from the report's own
   summary — distinct from the (deferred) per-gate pass/fail."
  (let ((violated (or (cdr (assoc :rules--violated summary)) 0))
        (unproven (or (cdr (assoc :rules--unproven summary)) 0)))
    (cond ((and (numberp violated) (> violated 0)) "violated")
          ((and (numberp unproven) (> unproven 0)) "unproven")
          (t "discharged"))))

(defun discharge-history-entry (path)
  "Build a lightweight lineage entry for one discharge report PATH.
   Pulls only generated_at + the summary block (re-emitted verbatim so it
   re-encodes to the same snake_case the frontend expects) and a derived
   status. On read/parse failure, returns an entry with status
   \"unreadable\" rather than signalling, so one bad file can't fail the
   whole list."
  (let ((fname (file-namestring path)))
    (cl-ppcre:register-groups-bind (timestamp sha)
        (+sb-history-filename-re+ fname)
      (handler-case
          (let* ((report (cl-json:decode-json-from-string
                          (uiop:read-file-string path)))
                 (summary (cdr (assoc :summary report))))
            (list (cons :path (namestring path))
                  (cons :timestamp timestamp)
                  (cons :git--sha sha)
                  (cons :generated--at (cdr (assoc :generated--at report)))
                  (cons :status (sb-summary-status summary))
                  (cons :summary summary)))
        (error ()
          (list (cons :path (namestring path))
                (cons :timestamp timestamp)
                (cons :git--sha sha)
                (cons :status "unreadable")
                (cons :summary nil)))))))

(defun discharge-history-entries (dir)
  "List discharge-report entries in DIR (a .sb/history directory), newest
   first. Only files matching the SB history filename pattern are included
   (filters stray files; the ISO prefix sorts lexically)."
  (let* ((files (remove-if-not
                 (lambda (f)
                   (cl-ppcre:scan +sb-history-filename-re+ (file-namestring f)))
                 (uiop:directory-files (uiop:ensure-directory-pathname dir))))
         (sorted (sort (copy-list files) #'string> :key #'file-namestring)))
    (mapcar #'discharge-history-entry sorted)))

;;; ===================================================================
;;; Project discovery (the cockpit home / project picker)
;;; ===================================================================
;;;
;;; A "project" is any directory containing a .sb/history/ dir — i.e. a
;;; repo `sb` has run against. The cockpit lists them so the user can pick
;;; one and drop into its lineage. Pure filesystem, like the discharge
;;; endpoints; no substrate context needed.

(defvar *sb-projects-root*
  (or (uiop:getenv "SB_PROJECTS_ROOT")
      (namestring (merge-pathnames "projects/Shen-Backpressure/"
                                   (user-homedir-pathname))))
  "Default root scanned for Shen-Backpressure projects when the /projects
   endpoint is called without a ?root= override. Set SB_PROJECTS_ROOT to
   point elsewhere — this is deployment config, not a design choice.")

(defparameter +sb-scan-prune-dirs+
  '(".git" "node_modules" ".claude" "dist" "shenguard" ".sl" "vendor")
  "Directory names never descended into during project discovery — heavy
   trees and sources of duplicate .sb dirs (e.g. .claude/worktrees/).")

(defun find-sb-history-dirs (root &key (max-depth 8))
  "Recursively find every .sb/history directory under ROOT, bounded by
   MAX-DEPTH and pruning +SB-SCAN-PRUNE-DIRS+. Returns absolute directory
   namestrings. Uses uiop:collect-sub*directories (same util as
   snapshot/filesystem-tree)."
  (let* ((root-dir (uiop:ensure-directory-pathname root))
         (root-str (namestring root-dir))
         (found '()))
    (when (probe-file root-dir)
      (uiop:collect-sub*directories
       root-dir
       ;; collect-test: is this dir a .sb/history/ ?
       (lambda (dir)
         (let* ((parts (pathname-directory dir))
                (leaf (car (last parts)))
                (parent (car (last parts 2))))
           (when (and (equal leaf "history") (equal parent ".sb"))
             (push (namestring dir) found))
           t))
       ;; recurse-test: prune heavy/dup dirs and bound depth
       (lambda (dir)
         (let* ((leaf (car (last (pathname-directory dir))))
                (rel (enough-namestring (namestring dir) root-str))
                (depth (count #\/ rel)))
           (and (not (member leaf +sb-scan-prune-dirs+ :test #'equal))
                (< depth max-depth))))
       ;; collector: unused (collection happens in collect-test)
       (lambda (dir) (declare (ignore dir)) nil)))
    (nreverse found)))

(defun sb-project-name (history-dir)
  "Project name = the directory two levels above .sb/history/
   (…/payment/.sb/history/ -> \"payment\")."
  (let ((parts (pathname-directory (uiop:ensure-directory-pathname history-dir))))
    ;; parts tail: (… "payment" ".sb" "history")
    (or (car (last parts 3)) "project")))

(defun sb-project-root (history-dir)
  "Project root = the dir two levels above .sb/history/ (the dir with sb.toml).
   …/payment/.sb/history/ -> …/payment/"
  (let* ((d (uiop:ensure-directory-pathname history-dir))
         (parts (pathname-directory d)))
    (namestring (make-pathname :directory (butlast parts 2) :defaults d))))

(defun sb-project-entry (history-dir root)
  "Summarize one project from its .sb/history/ dir: name, abs path, project
   root, path relative to ROOT, iteration count, and the newest report's
   status + timestamp. Reuses discharge-history-entries."
  (handler-case
      (let* ((entries (discharge-history-entries history-dir))
             (latest (first entries)))
        (list (cons :name (sb-project-name history-dir))
              (cons :path (namestring history-dir))
              (cons :root (sb-project-root history-dir))
              (cons :rel (enough-namestring
                          (namestring history-dir)
                          (namestring (uiop:ensure-directory-pathname root))))
              (cons :iteration--count (length entries))
              (cons :latest--status (and latest (cdr (assoc :status latest))))
              (cons :latest--timestamp (and latest (cdr (assoc :timestamp latest))))))
    (error ()
      (list (cons :name (sb-project-name history-dir))
            (cons :path (namestring history-dir))
            (cons :root (sb-project-root history-dir))
            (cons :iteration--count 0)
            (cons :latest--status "unreadable")
            (cons :latest--timestamp nil)))))

(defun sb-projects (root)
  "Discover and summarize all Shen-Backpressure projects under ROOT,
   sorted by name."
  (let ((entries (mapcar (lambda (d) (sb-project-entry d root))
                         (find-sb-history-dirs root))))
    (sort entries #'string< :key (lambda (e) (or (cdr (assoc :name e)) "")))))

;;; ===================================================================
;;; Live runs — driving `sb loop` (slice 3)
;;; ===================================================================
;;;
;;; `sb` has no streaming/daemon mode, so we drive `sb loop` as a tracked
;;; subprocess and observe three things: its stderr (iteration/gate lines),
;;; .sb/gates_last_run.json (per-gate pass/fail, every iteration), and the
;;; .sb/history/ reports (the lineage). The cockpit polls GET .../sb-loop/:id.
;;; Runs happen IN PLACE in the project dir — they mutate the repo and spend
;;; harness cost.

(defvar *sb-runs* (make-hash-table :test 'equal) "run-id -> sb-run struct.")
(defvar *sb-runs-lock* (bordeaux-threads:make-lock "sb-runs"))

(defstruct sb-run
  id project cwd process thread
  (status :running)            ; :running :converged :failed :stopped :error
  (iteration 0) max-iter
  (phase :gates)               ; :gates :harness
  gates                        ; decoded gates_last_run.json :gates (list of alists)
  (history-count 0)
  (log nil)                    ; recent stderr lines, oldest first, bounded
  started-at ended-at error-message)

(defparameter +sb-run-log-max+ 80)

(defun new-sb-run-id ()
  (format nil "run-~(~A~)" (subseq (autopoiesis.core:make-uuid) 0 8)))

(defun find-sb-executable ()
  "Locate the `sb` binary; fall back to bare 'sb' (resolved via PATH)."
  (or (handler-case
          (let ((p (uiop:run-program "which sb"
                                     :output '(:string :stripped t)
                                     :ignore-error-status t)))
            (when (and p (not (string= "" p))) p))
        (error () nil))
      "sb"))

(defun sb-run-push-log (run line)
  (let ((lines (append (sb-run-log run) (list line))))
    (setf (sb-run-log run)
          (if (> (length lines) +sb-run-log-max+)
              (last lines +sb-run-log-max+)
              lines))))

(defparameter +ansi-escape-re+
  (cl-ppcre:create-scanner (format nil "~C\\[[0-9;]*m" #\Escape))
  "Matches an ANSI SGR colour escape, e.g. ESC[32m / ESC[0m.")

(defun strip-ansi (s)
  "Remove ANSI colour escapes — sb colours its PASS/FAIL lines."
  (cl-ppcre:regex-replace-all +ansi-escape-re+ s ""))

(defun sb-history-count (cwd)
  "Count discharge reports in <cwd>/.sb/history/."
  (let ((hist (merge-pathnames ".sb/history/"
                               (uiop:ensure-directory-pathname cwd))))
    (if (probe-file hist)
        (length (discharge-history-entries (namestring hist)))
        0)))

(defun parse-sb-loop-line (run line)
  "Update RUN from one (ANSI-stripped) stderr LINE. `sb loop` does not write
   gates_last_run.json, so the gate strip is built from the PASS/FAIL lines:
   each iteration boundary resets the strip, each gate line appends to it."
  (cl-ppcre:register-groups-bind ((#'parse-integer n) (#'parse-integer m))
      ("=== Iteration (\\d+)/(\\d+) ===" line)
    (setf (sb-run-iteration run) n
          (sb-run-max-iter run) m
          (sb-run-phase run) :gates
          (sb-run-gates run) nil))         ; new iteration's gate run
  (cl-ppcre:register-groups-bind (status name dur)
      ("^(PASS|FAIL) \\[([^\\]]+)\\] (.+)$" line)
    (setf (sb-run-gates run)
          (append (sb-run-gates run)
                  (list (list (cons :name name)
                              (cons :passed (string= status "PASS"))
                              (cons :duration dur))))))
  (when (cl-ppcre:scan "Calling harness" line)
    (setf (sb-run-phase run) :harness))
  (when (cl-ppcre:scan "All gates passed on iteration" line)
    (setf (sb-run-status run) :converged))
  (when (cl-ppcre:scan "max iterations \\(\\d+\\) reached" line)
    (setf (sb-run-status run) :failed)))

(defun run-sb-loop-thread (run)
  "Reader thread: spawn `sb loop` in the project dir, stream its output into
   RUN, refreshing gate + history state at each iteration boundary."
  (let* ((cwd (sb-run-cwd run))
         ;; `exec` replaces the shell so the process we hold IS `sb loop`
         ;; (one fewer layer to chase when stopping).
         (cmd (format nil "~@[RALPH_MAX_ITER=~A ~]exec ~A loop </dev/null"
                      (sb-run-max-iter run) (find-sb-executable))))
    (handler-case
        (let ((process (sb-ext:run-program
                        "/bin/sh" (list "-c" cmd)
                        :directory (uiop:ensure-directory-pathname cwd)
                        :output :stream :error :output :wait nil)))
          (setf (sb-run-process run) process)
          (unwind-protect
              (let ((out (sb-ext:process-output process)))
                (loop for raw = (read-line out nil :eof)
                      until (eq raw :eof)
                      for line = (strip-ansi raw)
                      do (sb-run-push-log run line)
                         (parse-sb-loop-line run line)
                         (when (cl-ppcre:scan "=== Iteration" line)
                           (setf (sb-run-history-count run) (sb-history-count cwd)))))
            (when process
              (sb-ext:process-wait process)
              ;; Final refresh — pick up any new history report from this run.
              (setf (sb-run-history-count run) (sb-history-count cwd))
              (let ((code (sb-ext:process-exit-code process)))
                (when (eq (sb-run-status run) :running)
                  (setf (sb-run-status run)
                        (if (and code (zerop code)) :converged :failed))))
              (setf (sb-run-ended-at run) (get-universal-time))
              (sb-ext:process-close process))))
      (error (e)
        (setf (sb-run-status run) :error
              (sb-run-error-message run) (format nil "~A" e)
              (sb-run-ended-at run) (or (sb-run-ended-at run) (get-universal-time)))
        (log:warn "sb-loop run error: ~A" e)))))

(defun active-run-for-cwd (cwd)
  "The currently :running sb-run for CWD, or nil."
  (bordeaux-threads:with-lock-held (*sb-runs-lock*)
    (loop for r being the hash-values of *sb-runs*
          when (and (eq (sb-run-status r) :running)
                    (string= (sb-run-cwd r) cwd))
            return r)))

(defun start-sb-loop (project-root &key max-iter)
  "Spawn `sb loop` in PROJECT-ROOT (the dir with sb.toml). Returns the run."
  (let* ((cwd (namestring (uiop:ensure-directory-pathname project-root)))
         (id (new-sb-run-id))
         (run (make-sb-run :id id
                           :project (or (car (last (pathname-directory
                                                    (uiop:ensure-directory-pathname cwd))))
                                        "project")
                           :cwd cwd
                           :max-iter max-iter
                           :status :running
                           :started-at (get-universal-time))))
    (bordeaux-threads:with-lock-held (*sb-runs-lock*)
      (setf (gethash id *sb-runs*) run))
    (setf (sb-run-thread run)
          (bordeaux-threads:make-thread
           (lambda () (run-sb-loop-thread run))
           :name (format nil "sb-loop-~A" id)))
    run))

(defun descendant-pids (pid)
  "All descendant pids of PID (children, recursively) via `pgrep -P`. macOS
   has no setsid, so on stop we kill the whole tree rather than a group."
  (handler-case
      (let* ((out (uiop:run-program (list "pgrep" "-P" (princ-to-string pid))
                                    :output '(:string :stripped t)
                                    :ignore-error-status t))
             (kids (when (and out (> (length out) 0))
                     (loop for s in (uiop:split-string out :separator '(#\Newline))
                           for n = (ignore-errors (parse-integer s))
                           when n collect n))))
        (append kids (mapcan #'descendant-pids kids)))
    (error () nil)))

(defun kill-pids (pids signal-name)
  (when pids
    (ignore-errors
      (uiop:run-program (list* "kill" (format nil "-~A" signal-name)
                               (mapcar #'princ-to-string pids))
                        :ignore-error-status t))))

(defun stop-sb-loop (run)
  "Terminate RUN's subprocess and its descendants (the harness child, etc.):
   SIGTERM the whole tree, then SIGKILL survivors. Mark it stopped."
  (let ((p (sb-run-process run)))
    (when (and p (sb-ext:process-alive-p p))
      (let ((tree (append (descendant-pids (sb-ext:process-pid p))
                          (list (sb-ext:process-pid p)))))
        (kill-pids tree "TERM")
        (sleep 1)
        (when (sb-ext:process-alive-p p)
          (kill-pids tree "KILL")))))
  (setf (sb-run-status run) :stopped
        (sb-run-ended-at run) (or (sb-run-ended-at run) (get-universal-time)))
  run)

(defun sb-run-alist (run)
  "JSON projection of a run for the status endpoint (snake_case keys)."
  (list (cons :run--id (sb-run-id run))
        (cons :project (sb-run-project run))
        (cons :cwd (sb-run-cwd run))
        (cons :status (string-downcase (symbol-name (sb-run-status run))))
        (cons :iteration (sb-run-iteration run))
        (cons :max--iter (sb-run-max-iter run))
        (cons :phase (string-downcase (symbol-name (sb-run-phase run))))
        (cons :gates (or (sb-run-gates run) #()))
        (cons :history--count (sb-run-history-count run))
        (cons :log (coerce (sb-run-log run) 'vector))
        (cons :started--at (sb-run-started-at run))
        (cons :ended--at (sb-run-ended-at run))
        (cons :error (sb-run-error-message run))))

(defun rest-handle-aether (request)
  "Dispatch /api/aether/* requests."
  (let ((method (hunchentoot:request-method request))
        (uri (hunchentoot:request-uri request)))
    ;; Strip query string
    (let ((qpos (position #\? uri)))
      (when qpos (setf uri (subseq uri 0 qpos))))
    (cond
      ;; POST /api/aether/spawn
      ((and (eq method :post) (string= uri "/api/aether/spawn"))
       (require-permission :write)
       (let* ((body (parse-json-body))
              (prompt (cdr (assoc :prompt body)))
              (parent (cdr (assoc :parent body)))
              (model (cdr (assoc :model body)))
              (cwd (cdr (assoc :cwd body))))
         (cond
           ((or (null prompt) (string= prompt ""))
            (json-error "prompt is required" :status 400 :error-type "Bad Request"))
           (t
            (handler-case
                (multiple-value-bind (session initial)
                    (spawn-aether-session :prompt prompt
                                          :parent parent
                                          :model model
                                          :cwd cwd)
                  (json-ok
                   (list (cons :session_id (aether-session-id session))
                         (cons :initial_snapshot_id
                               (autopoiesis.snapshot:snapshot-id initial))
                         (cons :lineage (aether-session-lineage-name session))
                         (cons :model (aether-session-model session)))))
              (error (e)
                (json-error (format nil "spawn failed: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; GET /api/aether/sessions
      ((and (eq method :get) (string= uri "/api/aether/sessions"))
       (require-permission :read)
       (json-ok (list-aether-sessions)))
      ;; GET /api/aether/snapshots/:id/files
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/snapshots/[^/]+/files$" uri))
       (require-permission :read)
       (let* ((id (cl-ppcre:register-groups-bind (sid)
                      ("^/api/aether/snapshots/([^/]+)/files$" uri)
                    sid))
              (snap (autopoiesis.snapshot:load-snapshot id)))
         (cond ((null snap) (json-not-found "Snapshot" id))
               (t (json-ok (files-listing-for snap))))))
      ;; POST /api/aether/snapshots/:id/checkout
      ;; Body (optional): {"target": "/abs/path"} — falls back to the cwd
      ;; the snapshot was captured at.
      ((and (eq method :post)
            (cl-ppcre:scan "^/api/aether/snapshots/[^/]+/checkout$" uri))
       (require-permission :write)
       (let* ((id (cl-ppcre:register-groups-bind (sid)
                      ("^/api/aether/snapshots/([^/]+)/checkout$" uri)
                    sid))
              (snap (autopoiesis.snapshot:load-snapshot id)))
         (cond
           ((null snap) (json-not-found "Snapshot" id))
           (t
            (let* ((body (parse-json-body))
                   (req-target (cdr (assoc :target body)))
                   (target (or req-target (snapshot-cwd snap))))
              (cond
                ((or (null target) (zerop (length target)))
                 (json-error
                  "Snapshot has no captured cwd; specify target in body."
                  :status 400 :error-type "Bad Request"))
                (t
                 (handler-case
                     (let ((count (checkout-snapshot-to snap target)))
                       (json-ok
                        (list (cons :snapshot_id id)
                              (cons :target target)
                              (cons :entries_written count))))
                   (error (e)
                     (json-error (format nil "checkout failed: ~A" e)
                                 :status 500 :error-type "Internal Error"))))))))))
      ;; GET /api/aether/blame/:snapshot-id/:url-encoded-path
      ;; Per-line file ancestry. Walks the lineage chain from the snapshot
      ;; backward, attributing each line of the file to the earliest
      ;; ancestor whose tree already contained that exact line.
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/blame/[^/]+/.+$" uri))
       (require-permission :read)
       (cl-ppcre:register-groups-bind (sid encoded-path)
           ("^/api/aether/blame/([^/]+)/(.+)$" uri)
         (let* ((path (handler-case (hunchentoot:url-decode encoded-path)
                        (error () encoded-path)))
                (snap (autopoiesis.snapshot:load-snapshot sid)))
           (cond
             ((null snap) (json-not-found "Snapshot" sid))
             ((null (autopoiesis.snapshot:snapshot-tree-entries snap))
              (json-not-found "Snapshot has no tree" sid))
             (t
              (handler-case
                  (let ((blames (compute-blame snap path)))
                    (cond
                      ((null blames)
                       (json-not-found "File in snapshot" path))
                      (t (json-ok (blame-result-alist snap path blames)))))
                (error (e)
                  (json-error (format nil "blame failed: ~A" e)
                              :status 500 :error-type "Internal Error"))))))))
      ;; POST /api/aether/spawn-batch
      ;; Body: {prompt, variants: [str, str, ...], parent?, cwd_prefix?, model?}
      ;; Fires one rho session per variant; each variant text is appended to
      ;; the base prompt with " — " separator, each gets its own cwd under
      ;; cwd_prefix (/v1/, /v2/, ...). Returns parallel arrays of ids/cwds.
      ((and (eq method :post) (string= uri "/api/aether/spawn-batch"))
       (require-permission :write)
       (let* ((body (parse-json-body))
              (prompt (cdr (assoc :prompt body)))
              (variants (cdr (assoc :variants body)))
              (parent (cdr (assoc :parent body)))
              (cwd-prefix (cdr (assoc :cwd--prefix body)))
              (model (cdr (assoc :model body))))
         (cond
           ((or (null prompt) (string= prompt ""))
            (json-error "prompt is required" :status 400 :error-type "Bad Request"))
           ((or (null variants) (not (listp variants)) (null (car variants)))
            (json-error "variants must be a non-empty array of strings"
                        :status 400 :error-type "Bad Request"))
           (t
            (handler-case
                (let* ((session-ids '())
                       (initial-ids '())
                       (cwds '())
                       (lineages '()))
                  (loop for variant in variants
                        for idx from 1
                        for full-prompt = (if (and variant (> (length variant) 0))
                                              (format nil "~A — ~A" prompt variant)
                                              prompt)
                        for child-cwd = (when (and cwd-prefix (> (length cwd-prefix) 0))
                                          ;; Join with explicit slash + trailing slash;
                                          ;; sidesteps *default-pathname-defaults* games.
                                          (let* ((base (if (eql #\/ (char cwd-prefix
                                                                         (1- (length cwd-prefix))))
                                                           cwd-prefix
                                                           (concatenate 'string cwd-prefix "/"))))
                                            (format nil "~Av~A/" base idx)))
                        do (when child-cwd
                             (ensure-directories-exist
                              (uiop:ensure-directory-pathname child-cwd)))
                           (multiple-value-bind (session initial)
                               (spawn-aether-session :prompt full-prompt
                                                     :parent parent
                                                     :model model
                                                     :cwd child-cwd)
                             (push (aether-session-id session) session-ids)
                             (push (autopoiesis.snapshot:snapshot-id initial) initial-ids)
                             (push (or child-cwd "") cwds)
                             (push (aether-session-lineage-name session) lineages)))
                  (json-ok
                   (list (cons :session_ids (coerce (nreverse session-ids) 'vector))
                         (cons :initial_snapshot_ids
                               (coerce (nreverse initial-ids) 'vector))
                         (cons :cwds (coerce (nreverse cwds) 'vector))
                         (cons :lineages (coerce (nreverse lineages) 'vector))
                         (cons :parent (or parent ""))
                         (cons :count (length variants)))))
              (error (e)
                (json-error (format nil "spawn-batch failed: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; GET /api/aether/snapshots/:a/compare/:b
      ;; Returns side-by-side cognition + filesystem diff between two snapshots.
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/snapshots/[^/]+/compare/[^/]+$" uri))
       (require-permission :read)
       (cl-ppcre:register-groups-bind (a-id b-id)
           ("^/api/aether/snapshots/([^/]+)/compare/([^/]+)$" uri)
         (let ((a-snap (autopoiesis.snapshot:load-snapshot a-id))
               (b-snap (autopoiesis.snapshot:load-snapshot b-id)))
           (cond
             ((null a-snap) (json-not-found "Snapshot" a-id))
             ((null b-snap) (json-not-found "Snapshot" b-id))
             (t
              (handler-case
                  (json-ok (aether-compare-alist a-snap b-snap))
                (error (e)
                  (json-error (format nil "compare failed: ~A" e)
                              :status 500 :error-type "Internal Error"))))))))
      ;; GET /api/aether/snapshots/:id/content
      ;; The full, untruncated text for a snapshot — file content for a write,
      ;; the command for a bash, the agent's narration for thinking/complete.
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/snapshots/[^/]+/content$" uri))
       (require-permission :read)
       (cl-ppcre:register-groups-bind (sid)
           ("^/api/aether/snapshots/([^/]+)/content$" uri)
         (let ((snap (autopoiesis.snapshot:load-snapshot sid)))
           (if (null snap)
               (json-not-found "Snapshot" sid)
               (json-ok (content-alist-for snap))))))
      ;; POST /api/aether/reveal  {"path": "/abs/dir"}
      ;; Opens the path in the OS file browser (so the user can actually find
      ;; the files an agent produced).
      ((and (eq method :post) (string= uri "/api/aether/reveal"))
       (require-permission :read)
       (let* ((body (parse-json-body))
              (path (cdr (assoc :path body))))
         (cond
           ((or (null path) (zerop (length path)))
            (json-error "path is required" :status 400 :error-type "Bad Request"))
           (t (json-ok (list (cons :path path)
                             (cons :revealed (reveal-path path))))))))
      ;; GET /api/aether/discharge?report=<abs-path-to-discharge_report.json>
      ;; Reads a Shen-Backpressure discharge report from disk and returns it
      ;; verbatim. The cockpit's substance layer — per-rule, per-premise
      ;; verification evidence produced by `sb`.
      ((and (eq method :get)
            (let ((qpos (position #\? (hunchentoot:request-uri request))))
              (and qpos (string= "/api/aether/discharge"
                                 (subseq (hunchentoot:request-uri request) 0 qpos)))))
       (require-permission :read)
       (let ((report (hunchentoot:get-parameter "report" request)))
         (cond
           ((or (null report) (zerop (length report)))
            (json-error "report path is required" :status 400 :error-type "Bad Request"))
           ((not (and (> (length report) 5)
                      (string= ".json" (subseq report (- (length report) 5)))))
            (json-error "report must be a .json path" :status 400 :error-type "Bad Request"))
           ((not (probe-file report))
            (json-not-found "Discharge report" report))
           (t
            (handler-case
                (progn
                  (setf (hunchentoot:content-type*) "application/json")
                  (uiop:read-file-string report))
              (error (e)
                (json-error (format nil "could not read report: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; GET /api/aether/discharge-history?dir=<abs-path-to-.sb/history-dir>
      ;; Lists the discharge reports in DIR newest-first, each with a
      ;; lightweight summary + derived status. The lineage view's data
      ;; source — drill-down hands a returned :path back to /discharge.
      ((and (eq method :get) (string= uri "/api/aether/discharge-history"))
       (require-permission :read)
       (let ((dir (hunchentoot:get-parameter "dir" request)))
         (cond
           ((or (null dir) (zerop (length dir)))
            (json-error "dir path is required" :status 400 :error-type "Bad Request"))
           ((not (probe-file (uiop:ensure-directory-pathname dir)))
            (json-not-found "Discharge history directory" dir))
           (t
            (handler-case
                (let ((entries (discharge-history-entries dir)))
                  (json-ok (list (cons :entries (coerce entries 'vector))
                                 (cons :count (length entries)))))
              (error (e)
                (json-error (format nil "history list failed: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; GET /api/aether/projects?root=<dir>
      ;; The cockpit home: discover repos with a .sb/history/ dir under ROOT
      ;; (default *sb-projects-root*), each with iteration count + latest
      ;; status. Selecting one hands its :path to /discharge-history.
      ((and (eq method :get) (string= uri "/api/aether/projects"))
       (require-permission :read)
       (let* ((param (hunchentoot:get-parameter "root" request))
              (root (if (and param (> (length param) 0)) param *sb-projects-root*)))
         (cond
           ((not (probe-file (uiop:ensure-directory-pathname root)))
            (json-not-found "Projects root" root))
           (t
            (handler-case
                (let ((projects (sb-projects root)))
                  (json-ok (list (cons :root (namestring
                                              (uiop:ensure-directory-pathname root)))
                                 (cons :projects (coerce projects 'vector))
                                 (cons :count (length projects)))))
              (error (e)
                (json-error (format nil "project scan failed: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; POST /api/aether/sb-loop/start  {dir, max_iter?}
      ;; Drive `sb loop` in DIR (the project root, in place). Returns a run_id
      ;; the cockpit polls. Mutates the repo + spends harness cost.
      ((and (eq method :post) (string= uri "/api/aether/sb-loop/start"))
       (require-permission :write)
       (let* ((body (parse-json-body))
              (dir (cdr (assoc :dir body)))
              (max-iter (cdr (assoc :max--iter body))))
         (cond
           ((or (null dir) (zerop (length dir)))
            (json-error "dir is required" :status 400 :error-type "Bad Request"))
           ((not (probe-file (merge-pathnames "sb.toml"
                                              (uiop:ensure-directory-pathname dir))))
            (json-error (format nil "no sb.toml in ~A" dir)
                        :status 400 :error-type "Bad Request"))
           ((active-run-for-cwd (namestring (uiop:ensure-directory-pathname dir)))
            (json-error "a run is already active for this project"
                        :status 409 :error-type "Conflict"))
           (t
            (handler-case
                (let ((run (start-sb-loop dir :max-iter (and (integerp max-iter) max-iter))))
                  (json-ok (list (cons :run--id (sb-run-id run))
                                 (cons :status "running"))))
              (error (e)
                (json-error (format nil "start failed: ~A" e)
                            :status 500 :error-type "Internal Error")))))))
      ;; POST /api/aether/sb-loop/:id/stop
      ((and (eq method :post)
            (cl-ppcre:scan "^/api/aether/sb-loop/[^/]+/stop$" uri))
       (require-permission :write)
       (let* ((id (cl-ppcre:register-groups-bind (rid)
                      ("^/api/aether/sb-loop/([^/]+)/stop$" uri) rid))
              (run (bordeaux-threads:with-lock-held (*sb-runs-lock*)
                     (gethash id *sb-runs*))))
         (if (null run)
             (json-not-found "Run" id)
             (json-ok (sb-run-alist (stop-sb-loop run))))))
      ;; GET /api/aether/sb-loop/:id  — the poll target
      ((and (eq method :get)
            (cl-ppcre:scan "^/api/aether/sb-loop/[^/]+$" uri))
       (require-permission :read)
       (let* ((id (cl-ppcre:register-groups-bind (rid)
                      ("^/api/aether/sb-loop/([^/]+)$" uri) rid))
              (run (bordeaux-threads:with-lock-held (*sb-runs-lock*)
                     (gethash id *sb-runs*))))
         (if (null run)
             (json-not-found "Run" id)
             (json-ok (sb-run-alist run)))))
      ;; Unknown
      (t
       (json-not-found "AETHER route" uri)))))

;;; ===================================================================
;;; Snapshot comparison (cognition + filesystem)
;;; ===================================================================

(defun snapshot-meta-summary (snap)
  "Extract a JSON-friendly subset of a snapshot's metadata for compare output."
  (let ((md (autopoiesis.snapshot:snapshot-metadata snap)))
    `((:lineage . ,(or (getf md :lineage) ""))
      (:mood . ,(or (getf md :mood) ""))
      (:event_type . ,(or (getf md :event-type) ""))
      (:session . ,(or (getf md :session) ""))
      (:ticks . ,(or (getf md :ticks) 0))
      (:depth . ,(or (getf md :depth) 0))
      (:cwd . ,(or (getf md :cwd) ""))
      (:files . ,(or (getf md :files) 0))
      (:text . ,(or (getf md :text) "")))))

(defun aether-common-ancestor (a-id b-id)
  "Walk parent chains of A-ID and B-ID, return first shared snapshot id (or nil).
   Bounded by a max-walk to avoid pathological cycles."
  (let ((a-ancestors (make-hash-table :test 'equal))
        (max-walk 10000))
    ;; Collect A's ancestors (including itself).
    (loop for cur = a-id then (let ((s (autopoiesis.snapshot:load-snapshot cur)))
                                (and s (autopoiesis.snapshot:snapshot-parent s)))
          for n from 0 below max-walk
          while cur
          do (setf (gethash cur a-ancestors) t))
    ;; Walk B's chain, return first match.
    (loop for cur = b-id then (let ((s (autopoiesis.snapshot:load-snapshot cur)))
                                (and s (autopoiesis.snapshot:snapshot-parent s)))
          for n from 0 below max-walk
          while cur
          when (gethash cur a-ancestors) return cur
          finally (return nil))))

(defun edit-path-to-string (path)
  "Render a sexpr-diff path (list of :car/:cdr) as a compact dotted string."
  (if (null path)
      "/"
      (with-output-to-string (s)
        (dolist (step path)
          (write-string (case step (:car ".a") (:cdr ".d") (t ".?")) s)))))

(defun truncate-printable (obj max-len)
  "prin1 OBJ and truncate to MAX-LEN chars for diff summaries."
  (let ((rendered (handler-case (prin1-to-string obj)
                    (error () "<unprintable>"))))
    (if (> (length rendered) max-len)
        (concatenate 'string (subseq rendered 0 max-len) "…")
        rendered)))

(defun edit-to-alist (edit)
  "Convert one sexpr-edit struct to a JSON-friendly alist."
  (let* ((type (autopoiesis.core:sexpr-edit-type edit))
         (path (autopoiesis.core:sexpr-edit-path edit))
         (old (autopoiesis.core:sexpr-edit-old edit))
         (new (autopoiesis.core:sexpr-edit-new edit)))
    `((:type . ,(string-downcase (symbol-name type)))
      (:path . ,(edit-path-to-string path))
      (:summary . ,(case type
                     (:replace (format nil "~A → ~A"
                                       (truncate-printable old 60)
                                       (truncate-printable new 60)))
                     (:insert (format nil "+ ~A" (truncate-printable new 80)))
                     (:delete (format nil "- ~A" (truncate-printable old 80)))
                     (t (format nil "~A" type)))))))

(defun cognition-diff-alist (a-snap b-snap)
  "Compute sexpr-diff between two snapshots' agent-state.
   Returns alist with :edit_count and :edits (truncated to first 20)."
  (let* ((edits (autopoiesis.core:sexpr-diff
                 (autopoiesis.snapshot:snapshot-agent-state a-snap)
                 (autopoiesis.snapshot:snapshot-agent-state b-snap)))
         (count (length edits))
         (head (if (> count 20) (subseq edits 0 20) edits)))
    `((:edit_count . ,count)
      (:truncated . ,(if (> count 20) t nil))
      (:edits . ,(coerce (mapcar #'edit-to-alist head) 'vector)))))

(defun fs-entry-to-alist (entry)
  "JSON-friendly summary of a tree entry."
  `((:path . ,(or (autopoiesis.snapshot:entry-path entry) ""))
    (:type . ,(string-downcase
               (symbol-name (or (autopoiesis.snapshot:entry-type entry) :file))))
    (:size . ,(or (autopoiesis.snapshot:entry-size entry) 0))
    (:hash . ,(or (autopoiesis.snapshot:entry-hash entry) ""))))

(defun fs-changed-to-alist (old-entry new-entry)
  "JSON-friendly summary of a modified file (paired old + new)."
  `((:path . ,(or (autopoiesis.snapshot:entry-path new-entry) ""))
    (:size_a . ,(or (autopoiesis.snapshot:entry-size old-entry) 0))
    (:size_b . ,(or (autopoiesis.snapshot:entry-size new-entry) 0))
    (:hash_a . ,(or (autopoiesis.snapshot:entry-hash old-entry) ""))
    (:hash_b . ,(or (autopoiesis.snapshot:entry-hash new-entry) ""))))

(defun filesystem-diff-alist (a-snap b-snap)
  "Build a JSON-friendly added/removed/changed grouping from tree-diff."
  (let* ((a-entries (autopoiesis.snapshot:snapshot-tree-entries a-snap))
         (b-entries (autopoiesis.snapshot:snapshot-tree-entries b-snap))
         (changes (autopoiesis.snapshot:tree-diff a-entries b-entries))
         (added '())
         (removed '())
         (changed '()))
    (dolist (c changes)
      (case (first c)
        (:added (push (fs-entry-to-alist (second c)) added))
        (:removed (push (fs-entry-to-alist (second c)) removed))
        (:modified (push (fs-changed-to-alist (second c) (third c)) changed))))
    `((:added . ,(coerce (nreverse added) 'vector))
      (:removed . ,(coerce (nreverse removed) 'vector))
      (:changed . ,(coerce (nreverse changed) 'vector))
      (:count_a . ,(length (or a-entries '())))
      (:count_b . ,(length (or b-entries '()))))))

(defun aether-compare-alist (a-snap b-snap)
  "Top-level compare payload: both sides' metadata, common ancestor,
   cognition diff, filesystem diff. Each section is shaped as a JSON object."
  (let ((a-id (autopoiesis.snapshot:snapshot-id a-snap))
        (b-id (autopoiesis.snapshot:snapshot-id b-snap)))
    `((:a . ((:id . ,a-id)
             (:metadata . ,(snapshot-meta-summary a-snap))))
      (:b . ((:id . ,b-id)
             (:metadata . ,(snapshot-meta-summary b-snap))))
      (:common_ancestor . ,(or (aether-common-ancestor a-id b-id) ""))
      (:cognition_diff . ,(cognition-diff-alist a-snap b-snap))
      (:filesystem_diff . ,(filesystem-diff-alist a-snap b-snap)))))
