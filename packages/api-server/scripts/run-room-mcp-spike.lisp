;;;; run-room-mcp-spike.lisp - GO/NO-GO: two agents into ONE shared room over MCP, merge
;;;;
;;;; The keystone of the "shared room" architecture, proven over the WIRE:
;;;;
;;;;   Multiple INDEPENDENT MCP clients connect to ONE substrate-backed room.
;;;;   Each stages work onto its OWN speculative branch via MCP tool calls
;;;;   (room_join / room_post). The room then merges the branches:
;;;;     - independent facts union cleanly
;;;;     - a genuine same-(entity,attribute) :one divergence is FLAGGED
;;;;       (a merge-conflict), never silently lost.
;;;;
;;;; This is the "two people's agents into one shared room, merge across the
;;;; connection" test -- the genuinely new thing in the architecture.
;;;;
;;;; LEVEL REACHED: B (good). The tool calls go over the REAL MCP transport:
;;;;   the existing Streamable-HTTP /mcp endpoint (JSON-RPC 2.0 over HTTP),
;;;;   served by Hunchentoot, hit by two CONCURRENT programmatic MCP clients
;;;;   (real `initialize` handshake + `tools/call`) issued with dexador.
;;;;   No direct substrate calls are used to stage/merge -- everything the
;;;;   agents do crosses the HTTP/JSON-RPC boundary.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/api-server/scripts/run-room-mcp-spike.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/"
               "./packages/substrate/"
               "./packages/api-server/"
               "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)
(asdf:load-asd (truename "./packages/api-server/api-server.asd"))
(ql:quickload :autopoiesis/api :silent t)
(ql:quickload :dexador :silent t)
(ql:quickload :cl-json :silent t)

(defpackage #:room-mcp-spike
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)
                    (#:api #:autopoiesis.api)))
(in-package #:room-mcp-spike)

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defparameter *port* 8231)
(defparameter *mcp-url* (format nil "http://127.0.0.1:~A/mcp" *port*))

;;; ===================================================================
;;; A minimal, real MCP client over the Streamable-HTTP transport.
;;; Every call below is a genuine JSON-RPC 2.0 POST to /mcp.
;;; ===================================================================

(defvar *rpc-id* 0)

;;; The server now serializes JSON-RPC responses with com.inuoe.jzon from
;;; hash-tables, so every object is a PROPER JSON object on the wire, e.g.
;;;   "result":{"content":[{"type":"text","text":"..."}],"isError":false}
;;; cl-json decodes that into a keyword-keyed alist (camelCase splits to
;;; :CAMEL-CASE, underscores -> hyphens), so "isError" -> :IS-ERROR,
;;; "content" -> :CONTENT, "fork_tx" -> :FORK-TX. rpc-get maps a JSON string
;;; key to that keyword; it also still tolerates the legacy array-of-pairs.
(defun json-key->keyword (key)
  "Map a JSON object key string to the keyword cl-json decodes it to:
   camelCase boundaries and underscores become hyphens (isError -> :IS-ERROR,
   protocolVersion -> :PROTOCOL-VERSION, fork_tx -> :FORK-TX)."
  (let ((out (make-string-output-stream)))
    (loop for ch across key
          do (cond ((char= ch #\_) (write-char #\- out))
                   ((upper-case-p ch) (write-char #\- out) (write-char ch out))
                   (t (write-char (char-upcase ch) out))))
    (intern (get-output-stream-string out) :keyword)))

(defun rpc-get (obj key)
  "Get string KEY out of a decoded JSON-RPC value. Primary: keyword-keyed
   alist (the proper-object shape). Falls back to legacy array-of-pairs."
  (cond
    ((null obj) nil)
    ;; keyword-keyed alist (proper JSON object decoded by cl-json)
    ((and (consp obj) (consp (car obj)) (keywordp (caar obj)))
     (cdr (assoc (json-key->keyword key) obj)))
    ;; legacy array-of-pairs: each elt is (\"key\" . rest)
    ((and (consp obj) (consp (car obj)) (stringp (caar obj)))
     (let ((hit (find key obj :key #'car :test #'string=)))
       (when hit
         (let ((rest (cdr hit)))
           (if (and (consp rest) (null (cdr rest))) (car rest) rest)))))
    (t nil)))

(defun jrpc-post (body &key session-id)
  "POST a JSON-RPC body string to /mcp. Returns (values parsed-json session-id-out)."
  (multiple-value-bind (resp status headers)
      (dex:post *mcp-url*
                :headers (append '(("content-type" . "application/json"))
                                 (when session-id `(("mcp-session-id" . ,session-id))))
                :content body)
    (declare (ignore status))
    (values (when (and resp (> (length resp) 0))
              (cl-json:decode-json-from-string resp))
            (or session-id
                ;; dexador returns response headers as a hash-table
                (and (hash-table-p headers) (gethash "mcp-session-id" headers))))))

(defun mcp-initialize (client-name)
  "Perform the MCP initialize handshake. Returns the session-id."
  (incf *rpc-id*)
  (let ((body (cl-json:encode-json-to-string
               `(("jsonrpc" . "2.0")
                 ("id" . ,*rpc-id*)
                 ("method" . "initialize")
                 ("params" . (("protocolVersion" . "2025-03-26")
                              ("capabilities" . ,(make-hash-table))
                              ("clientInfo" . (("name" . ,client-name)
                                               ("version" . "0.0.1")))))))))
    (multiple-value-bind (result sid) (jrpc-post body)
      (declare (ignore result))
      sid)))

(defun mcp-call-tool (session-id tool-name args-alist)
  "Issue a tools/call over HTTP. Returns the decoded tool RESULT object
   (the room handler returns an alist, JSON-encoded into content[0].text)."
  (incf *rpc-id*)
  (let ((body (cl-json:encode-json-to-string
               `(("jsonrpc" . "2.0")
                 ("id" . ,*rpc-id*)
                 ("method" . "tools/call")
                 ("params" . (("name" . ,tool-name)
                              ("arguments" . ,args-alist)))))))
    (multiple-value-bind (resp) (jrpc-post body :session-id session-id)
      (let* ((result (rpc-get resp "result"))
             (is-error (rpc-get result "isError"))
             ;; result is {"content":[{type,text}...],"isError":false};
             ;; content decodes to a list of {:type :text} keyword alists.
             (content (rpc-get result "content"))
             (text (cdr (assoc :text (first content)))))
        (when is-error
          (error "MCP tool ~a returned error: ~a" tool-name text))
        ;; The room tool result is itself JSON-encoded text -> decode it.
        (values (cl-json:decode-json-from-string text) text)))))

(defun mcp-list-tools (session-id)
  "tools/list over HTTP -> list of tool-name strings."
  (incf *rpc-id*)
  (let ((body (cl-json:encode-json-to-string
               `(("jsonrpc" . "2.0") ("id" . ,*rpc-id*) ("method" . "tools/list")))))
    (multiple-value-bind (resp) (jrpc-post body :session-id session-id)
      ;; result is [["tools", {tool}, {tool}, ...]] -> rpc-get returns the
      ;; rest after "tools", i.e. the list of tool objects (keyword alists).
      (let ((tools (rpc-get (rpc-get resp "result") "tools")))
        (mapcar (lambda (td) (cdr (assoc :name td))) tools)))))

;;; ===================================================================
;;; The scenario: two people's agents collaborate on ONE task entity,
;;; without copy-pasting context. Each connects independently over MCP.
;;; ===================================================================

(defun run-spike ()
  (setf *fails* nil)
  ;; --- the room substrate: GLOBAL store (what Hunchentoot threads see) ---
  (s:open-store)
  (api::room-ensure-schema)
  ;; base task that both agents fork from
  (s:transact! (list (s:make-datom "task-42" "room/decision" "use-postgres")
                     (s:make-datom "task-42" "room/note"     "kickoff")))
  (format t "~&== room base established (task-42) ==~%")

  ;; --- start the REAL MCP server (Streamable HTTP /mcp) ---
  (api:start-rest-server :port *port* :host "127.0.0.1")
  (sleep 0.5)

  (unwind-protect
       (progn
         ;; ---- sanity: room tools are advertised over tools/list (real wire) ----
         (let* ((probe-sid (mcp-initialize "probe"))
                (tools (mcp-list-tools probe-sid)))
           (check "room tools advertised over MCP tools/list"
                  (and (member "room_join" tools :test #'string=)
                       (member "room_post" tools :test #'string=)
                       (member "room_merge" tools :test #'string=))
                  (remove-if-not (lambda (n) (and (>= (length n) 5)
                                                  (string= (subseq n 0 5) "room_")))
                                 tools)))

         ;; ---- two INDEPENDENT MCP clients, concurrently ----
         ;; Each: initialize -> room_join -> stage facts via room_post.
         ;; Alice and Bob both touch task-42's :one "room/decision" differently
         ;; (the contested fact) and each contributes independent facts.
         (let ((alice-done (bt:make-semaphore))
               (bob-done   (bt:make-semaphore))
               (alice-err  nil)
               (bob-err    nil))
           (bt:make-thread
            (lambda ()
              (handler-case
                  (let ((sid (mcp-initialize "alice-claude-code")))
                    (mcp-call-tool sid "room_join"  `(("agent" . "alice")))
                    ;; independent :many fact (unions)
                    (mcp-call-tool sid "room_post"
                                   `(("agent" . "alice") ("entity" . "task-42")
                                     ("attribute" . "room/note") ("value" . "alice-investigated-schema")))
                    ;; independent :one fact (no one else sets owner)
                    (mcp-call-tool sid "room_post"
                                   `(("agent" . "alice") ("entity" . "task-42")
                                     ("attribute" . "room/owner") ("value" . "alice")))
                    ;; contested :one fact
                    (mcp-call-tool sid "room_post"
                                   `(("agent" . "alice") ("entity" . "task-42")
                                     ("attribute" . "room/decision") ("value" . "use-sqlite"))))
                (error (e) (setf alice-err e)))
              (bt:signal-semaphore alice-done))
            :name "alice-mcp-client")

           (bt:make-thread
            (lambda ()
              (handler-case
                  (let ((sid (mcp-initialize "bob-codex")))
                    (mcp-call-tool sid "room_join" `(("agent" . "bob")))
                    ;; independent :many fact (unions)
                    (mcp-call-tool sid "room_post"
                                   `(("agent" . "bob") ("entity" . "task-42")
                                     ("attribute" . "room/note") ("value" . "bob-wrote-tests")))
                    ;; independent :one fact (no one else sets status)
                    (mcp-call-tool sid "room_post"
                                   `(("agent" . "bob") ("entity" . "task-42")
                                     ("attribute" . "room/status") ("value" . "in-review")))
                    ;; contested :one fact (diverges from alice)
                    (mcp-call-tool sid "room_post"
                                   `(("agent" . "bob") ("entity" . "task-42")
                                     ("attribute" . "room/decision") ("value" . "use-mysql"))))
                (error (e) (setf bob-err e)))
              (bt:signal-semaphore bob-done))
            :name "bob-mcp-client")

           (bt:wait-on-semaphore alice-done :timeout 30)
           (bt:wait-on-semaphore bob-done   :timeout 30)
           (check "alice MCP client completed without error" (null alice-err) alice-err)
           (check "bob MCP client completed without error"   (null bob-err)   bob-err))

         ;; ---- staging touched NOTHING in the shared base yet ----
         (check "base room/decision unchanged before merge (staging is private)"
                (equal (s:entity-attr "task-42" "room/decision") "use-postgres")
                (s:entity-attr "task-42" "room/decision"))

         ;; ---- observability: room_state shows both agents' staged writes ----
         (let* ((obs-sid (mcp-initialize "observer"))
                (state (mcp-call-tool obs-sid "room_state" '()))
                ;; state may decode either as a keyword alist or the
                ;; array-of-pairs shape; rpc-get tolerates both. agent_count
                ;; is a scalar so it round-trips unambiguously.
                (count (or (cdr (assoc :agent--count state))
                           (rpc-get state "agent_count"))))
           (check "room_state lists both joined agents over MCP"
                  (eql 2 count) count))

         ;; ---- the room MERGES each branch, sequentially, over MCP ----
         ;; Alice merges first (base untouched since her fork -> clean).
         (let* ((merge-sid (mcp-initialize "room-orchestrator"))
                (a-res (mcp-call-tool merge-sid "room_merge" `(("agent" . "alice"))))
                (b-res (mcp-call-tool merge-sid "room_merge" `(("agent" . "bob")))))
           (let ((a-applied   (cdr (assoc :applied a-res)))
                 (a-conflicts (cdr (assoc :conflict--count a-res)))
                 (b-applied   (cdr (assoc :applied b-res)))
                 (b-conflicts (cdr (assoc :conflicts b-res)))
                 (b-cc        (cdr (assoc :conflict--count b-res))))
             (check "alice merge applied her facts with ZERO conflicts (over MCP)"
                    (and (= 0 a-conflicts) (= 3 a-applied))
                    (format nil "applied=~A conflicts=~A" a-applied a-conflicts))
             (check "bob merge FLAGGED exactly one conflict (the contested :one decision)"
                    (and (= 1 b-cc)
                         (string= (cdr (assoc :attribute (first b-conflicts)))
                                  "room/decision"))
                    (format nil "conflict-count=~A conflicts=~A" b-cc b-conflicts))
             (when (and b-conflicts (= 1 b-cc))
               (let ((c (first b-conflicts)))
                 (check "flagged conflict shows branch isolation (forked=use-postgres, wanted=use-mysql, base-now=use-sqlite)"
                        (and (string= (cdr (assoc :forked c))    "use-postgres")
                             (string= (cdr (assoc :wanted c))    "use-mysql")
                             (string= (cdr (assoc :base--now c)) "use-sqlite"))
                        c)))
             ;; bob's INDEPENDENT facts still merged despite his contested one being flagged
             (check "bob's independent :one (status) merged despite his conflict"
                    (>= b-applied 1) (format nil "bob applied=~A" b-applied))))

         ;; ---- final shared-base state (read back over MCP room_read) ----
         (let ((read-sid (mcp-initialize "reader")))
           (flet ((rd (attr)
                    (cdr (assoc :value
                                (mcp-call-tool read-sid "room_read"
                                               `(("entity" . "task-42") ("attribute" . ,attr)))))))
             (check "decision = use-sqlite (alice won the contested :one; bob's flagged, not silently lost)"
                    (string= (rd "room/decision") "use-sqlite") (rd "room/decision"))
             (check "owner = alice (independent :one unioned)"
                    (string= (rd "room/owner") "alice") (rd "room/owner"))
             (check "status = in-review (bob's independent :one unioned)"
                    (string= (rd "room/status") "in-review") (rd "room/status"))))

         ;; ---- :many notes union across both agents + base ----
         (let ((notes (sort (remove-duplicates
                             (mapcar (lambda (e) (getf e :value))
                                     (s:entity-history "task-42" "room/note" :last-n 1000))
                             :test #'equal)
                            #'string<)))
           (check ":many notes UNION across base + alice + bob"
                  (equal notes '("alice-investigated-schema" "bob-wrote-tests" "kickoff"))
                  notes)))

    ;; cleanup
    (ignore-errors (api:stop-rest-server))
    (ignore-errors (s:close-store)))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-spike))
