\* mvfs/oplog.shen — durable execution P-D2 (spec/08 §6): exactly-once external
   effects. Two mechanisms the panel (doc 42, Aphyr E1/E2) said the fence does NOT
   give you for free:

   E2 — intent->outcome journal on the fenced log: land INTENT (idempotency key)
        before the effect, land OUTCOME after; on replay, skip an effect whose
        outcome is already landed. This is exactly-once *modulo* the intent->outcome
        window (a crash there forces a re-attempt the external endpoint must dedupe)
        — the honest guarantee, same shape as Temporal/Restate.
   E1 — out-of-guest egress capability: the lease holder mints a per-effect token at
        epoch E; the egress proxy admits it iff the HMAC is valid AND its epoch >=
        the current durable epoch (the log's head fence). A stale/partitioned leader
        (epoch < current) is REJECTED even though its guest can still call send() —
        effect ownership enforced OUTSIDE the guest, where the fence cannot reach.

   Reuses the fenced land (intent/outcome are marked landed-entries) and the serve-
   token crypto (hmac-sha256/b64url/consttime-eq). Loaded after policy/read/dx. *\
(package mvfs []

\* ===== E2: the intent -> outcome journal ===== *\
(define journal-entry
  { number --> id --> string --> hash --> number --> landed-entry }   \* seq key marker payload epoch *\
  Seq Key Marker Payload Epoch
  -> [mk-entry Seq Key Key Payload "" "" [Marker] "system" Seq Epoch 0 0 0])

(define land-journal!
  { lease --> id --> string --> hash --> string --> landed }
  L Key Marker Payload Logpath
  -> (with-leadership L
       (/. W
         (let E    (witness-epoch W)
          (let Seq  (+ 1 (head-seq Logpath))
           (let Entry (journal-entry Seq Key Marker Payload E)
            (if (append-fenced! Logpath Entry E)
                [mk-landed Key Key Payload Seq]
                (error "I7: journal land rejected (stale leader)"))))))))

(define land-intent!
  { lease --> id --> hash --> string --> landed }      \* lease key effect-descriptor logpath *\
  L Key Effect Logpath -> (land-journal! L Key ".mvfs/intent" Effect Logpath))
(define land-outcome!
  { lease --> id --> hash --> string --> landed }      \* lease key outcome logpath *\
  L Key Outcome Logpath -> (land-journal! L Key ".mvfs/outcome" Outcome Logpath))

\* effect-status: scan the log for Key -> "done" | "pending" | "none" *\
(define has-marker-key?
  { string --> id --> (list landed-entry) --> boolean }
  _ _ [] -> false
  M K [E | Es] -> (if (and (= K (entry-key E)) (path-has? M (entry-paths E)))
                      true
                      (has-marker-key? M K Es)))
(define effect-status
  { string --> id --> string }
  Logpath Key -> (let Es (read-all Logpath)
                   (if (has-marker-key? ".mvfs/outcome" Key Es)
                       "done"
                       (if (has-marker-key? ".mvfs/intent" Key Es) "pending" "none"))))

\* should-emit?: emit only if the effect has not already completed. "pending" (intent
   landed, outcome not) => re-attempt (the at-least-once window; external dedup). *\
(define should-emit?
  { string --> id --> boolean }
  Logpath Key -> (not (= (effect-status Logpath Key) "done")))

\* outcome recorded for a completed effect (the value a replay returns instead of
   re-performing it) — the Commit of the outcome entry. *\
(define outcome-of
  { string --> id --> hash }
  Logpath Key -> (outcome-in Key (read-all Logpath)))
(define outcome-in
  { id --> (list landed-entry) --> hash }
  _ [] -> ""
  K [E | Es] -> (if (and (= K (entry-key E)) (path-has? ".mvfs/outcome" (entry-paths E)))
                    (entry-commit E)
                    (outcome-in K Es)))

\* ===== the worker-facing durable-effect API (composes E2) =====
   durable-effect! is the one call a durable worker makes around an external effect
   (the Temporal/Restate "activity" wrapper): if the effect already completed (its
   outcome is landed), REPLAY the recorded outcome and do NOT re-run it; otherwise
   land intent -> run the effect (a host command, stdout = outcome) -> land outcome.
   Exactly-once modulo the intent->outcome window (a crash there re-runs; the
   external endpoint must dedupe on the key — pair with the egress capability below). *\
(define durable-effect!
  { lease --> id --> string --> (list string) --> string --> hash }   \* lease key cmd args logpath -> outcome *\
  L Key Cmd Args Logpath
  -> (if (not (should-emit? Logpath Key))
         (outcome-of Logpath Key)                            \* already done: replay, never re-run *\
         (do (land-intent! L Key Cmd Logpath)                \* intent BEFORE the effect *\
          (let Out (git-hash-bytes (shell-run Cmd Args))     \* the external effect (at-least-once window) *\
           (do (land-outcome! L Key Out Logpath)             \* outcome AFTER the effect *\
            Out)))))

\* ===== E1: the out-of-guest egress capability ===== *\
\* token = b64url(msg) "." HMAC(signing-key, msg) ; msg = US-join(key, effect, epoch) *\
(define egress-msg
  { id --> hash --> number --> string }
  Key Effect Epoch -> (join (n->string 31) [Key Effect (str Epoch)]))

\* minted ONLY under leadership (the witness supplies the epoch). *\
(define mint-egress
  { string --> lease-witness --> id --> hash --> string }   \* signing-key witness key effect -> token *\
  SKey W Key Effect -> (let Msg (egress-msg Key Effect (witness-epoch W))
                         (@s (b64url Msg) "." (hmac-sha256 SKey Msg))))

\* current durable epoch = the log's head fence (the latest landed lease epoch). *\
(define current-epoch { string --> number } Logpath -> (head-fence Logpath))

(define egress-fields-ok?
  { (list string) --> id --> hash --> number --> boolean }   \* msg-fields key effect cur-epoch *\
  [K2 E2 EpS] Key Effect CurEpoch
  -> (and (= K2 Key) (and (= E2 Effect) (>= (str->num EpS) CurEpoch)))
  _ _ _ _ -> false)

\* the egress proxy admits an effect iff: HMAC valid AND token epoch >= current
   durable epoch. A stale leader's token (epoch < current) is rejected. *\
(define egress-ok?
  { string --> string --> id --> hash --> string --> boolean }   \* signkey token key effect logpath *\
  SKey Token Key Effect Logpath
  -> (let Parts (split "." Token)
       (if (< (length Parts) 2)
           false
           (let Msg (unb64url (head Parts))
            (if (not (consttime-eq (head (tail Parts)) (hmac-sha256 SKey Msg)))
                false
                (egress-fields-ok? (split (n->string 31) Msg) Key Effect (current-epoch Logpath)))))))
)
