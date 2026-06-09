;;;; run-parallel-branches-demo.lisp - Slice 1: parallel sub-agents on branches
;;;;
;;;; Proves: N sub-agents run concurrently, each on its OWN speculative datom
;;;; branch (read-only on shared state, no interning race), then fan-in merges
;;;; the branches with cardinality-aware set-union + conflict-flag -- replacing
;;;; the current "collect, never merge".
;;;;
;;;; Mirrors the campaign.lisp threading pattern (packages/research/src/campaign.lisp:359):
;;;; capture *substrate*/*store*, rebind in each bt:make-thread, condition-var fan-in.
;;;; Difference: fan-in is branch-merge (substrate speculative module), not coerce-to-list.
;;;;
;;;;   sbcl --noinform --non-interactive --load \
;;;;     packages/substrate/scripts/run-parallel-branches-demo.lisp

(in-package #:cl-user)

(dolist (dir '("./packages/core/"
               "./packages/substrate/"
               "./packages/api-server/"
               "./vendor/platform-vendor/woo/"))
  (push (pathname dir) asdf:*central-registry*))

(asdf:load-asd (truename "./vendor/platform-vendor/woo/woo.asd"))
(ql:quickload :woo :silent t)
(ql:quickload :autopoiesis :silent t)

(defpackage #:sb-parallel-demo
  (:use #:cl)
  (:local-nicknames (#:s #:autopoiesis.substrate)))
(in-package #:sb-parallel-demo)

(defvar *fails* nil)
(defun check (name ok &optional detail)
  (format t "  [~A] ~A~@[  ~A~]~%" (if ok "PASS" "FAIL") name detail)
  (unless ok (push name *fails*)))

(defun many-values (ename aname)
  (sort (remove-duplicates
         (mapcar (lambda (e) (getf e :value))
                 (s:entity-history ename aname :last-n 1000))
         :test #'equal)
        #'string<))

;;; Each sub-agent: fork a branch, stage its work (reads base only), return branch.
(defun sub-agent (id entrypoint-choice lang-choice)
  "Simulated parallel builder. Stages writes into its own branch; touches the
   base store ONLY via reads (entity-attr inside branch-stage)."
  (let ((br (s:branch-fork :name (format nil "agent-~A" id))))
    (s:branch-stage br "module" "module/file" (format nil "file-~A.py" id)) ; :many
    (s:branch-stage br "module" "module/note" (format nil "agent ~A worked" id)) ; :many
    (when entrypoint-choice
      (s:branch-stage br "module" "module/entrypoint" entrypoint-choice))  ; :one (contested)
    (when lang-choice
      (s:branch-stage br "module" "module/lang" lang-choice))              ; :one (independent)
    (sleep 0.02)                          ; make the parallelism real
    br))

(defun run-demo ()
  (setf *fails* nil)
  (s:with-store ()
    ;; schema
    (s:declare-cardinality "module/entrypoint" :one)
    (s:declare-cardinality "module/lang"       :one)
    (s:declare-cardinality "module/file"       :many)
    (s:declare-cardinality "module/note"       :many)

    ;; base module, forked from by every sub-agent
    (s:transact! (list (s:make-datom "module" "module/entrypoint" "main.py")
                       (s:make-datom "module" "module/lang"       "python")
                       (s:make-datom "module" "module/file"       "main.py")))
    (let ((tx0 (s::store-tx-counter s:*store*)))
      (format t "~&== base established (tx=~A) ==~%" tx0)

      ;; --- 3 sub-agents in parallel (campaign threading pattern) ---
      (let* ((specs '((0 "app.py"    nil)        ; contests entrypoint
                      (1 "server.py" nil)        ; contests entrypoint (differently)
                      (2 nil         "python3"))) ; independent :one (lang)
             (n (length specs))
             (results (make-array n :initial-element nil))
             (lock (bt:make-lock "branch-results"))
             (done (bt:make-condition-variable :name "agents-done"))
             (done-count 0)
             (cap-substrate s:*substrate*)
             (cap-store s:*store*))
        (loop for spec in specs
              for i from 0
              do (let ((my-spec spec) (my-i i))
                   (bt:make-thread
                    (lambda ()
                      (let ((s:*substrate* cap-substrate)
                            (s:*store* cap-store))
                        (let ((br (sub-agent (first my-spec) (second my-spec) (third my-spec))))
                          (bt:with-lock-held (lock)
                            (setf (aref results my-i) br)
                            (incf done-count)
                            (when (= done-count n)
                              (bt:condition-notify done))))))
                    :name (format nil "agent-~A" i))))
        (bt:with-lock-held (lock)
          (loop while (< done-count n)
                do (bt:condition-wait done lock :timeout 30)))

        ;; parallel phase did NOT write to base (work deferred to merge)
        (let ((tx1 (s::store-tx-counter s:*store*)))
          (check "parallel phase wrote nothing to base (deferred to merge)"
                 (= tx1 tx0) (format nil "tx0=~A tx1=~A" tx0 tx1)))

        ;; --- fan-in: merge each branch sequentially (cardinality-aware) ---
        (let ((all-conflicts nil) (total-applied 0))
          (loop for br across results
                do (multiple-value-bind (applied conflicts) (s:branch-merge br)
                     (incf total-applied applied)
                     (setf all-conflicts (append all-conflicts conflicts))))
          (format t "== merged ~A branches: ~A writes applied, ~A conflict(s) ==~%"
                  n total-applied (length all-conflicts))

          ;; merge advanced the base tx (writes happened only here)
          (check "merge advanced base tx (writes only at fan-in)"
                 (> (s::store-tx-counter s:*store*) tx0))

          ;; :many union across ALL three parallel branches, zero conflict
          (check ":many files union across 3 branches"
                 (equal (many-values "module" "module/file")
                        '("file-0.py" "file-1.py" "file-2.py" "main.py"))
                 (many-values "module" "module/file"))
          (check ":many notes union across 3 branches"
                 (= 3 (length (many-values "module" "module/note")))
                 (many-values "module" "module/note"))

          ;; independent :one applied clean (no conflict)
          (check "independent :one (lang) applied = python3"
                 (equal (s:entity-attr "module" "module/lang") "python3")
                 (s:entity-attr "module" "module/lang"))

          ;; contested :one: first writer wins, the diverging one is FLAGGED
          (check "contested :one entrypoint resolved to first merged (app.py)"
                 (equal (s:entity-attr "module" "module/entrypoint") "app.py")
                 (s:entity-attr "module" "module/entrypoint"))
          (check "exactly one conflict flagged, on module/entrypoint"
                 (and (= 1 (length all-conflicts))
                      (equal (s:merge-conflict-attribute (first all-conflicts))
                             "module/entrypoint")))
          ;; the conflict proves branch ISOLATION: agent-1 forked from base
          ;; ("main.py"), never saw agent-0's concurrent "app.py"
          (when all-conflicts
            (check "conflict shows branch isolation (forked=main.py, wanted=server.py)"
                   (and (equal (s:merge-conflict-forked (first all-conflicts)) "main.py")
                        (equal (s:merge-conflict-wanted (first all-conflicts)) "server.py")
                        (equal (s:merge-conflict-base-now (first all-conflicts)) "app.py"))))))))

  (format t "~%================ ~A ================~%" (if *fails* "NO-GO" "GO"))
  (when *fails* (format t "failed: ~{~A~^, ~}~%" (reverse *fails*)))
  (format t "===================================~%")
  (if *fails* 1 0))

(uiop:quit (run-demo))
