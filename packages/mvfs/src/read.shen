\* mvfs/read.shen — the read-tier BRAIN (spec/04, spec/05).
   "Brain decides, nginx serves zero-copy": this module makes the read decision
   — enforce the as-of basis (I8), authorize (I9/I6), resolve path->blob (§5.2),
   and mint the HMAC serve token (§5.3) — and returns either a `serve` directive
   (blob hash + token, which the edge turns into ngx.exec -> internal sendfile)
   or a `deny`. NO blob byte ever touches this code (agentzh: bytes never enter
   the VM). The serve verbs (resolve-path/hmac-sha256/b64url/now-secs/…) are
   audited host primitives in boundary.shen. Pure decision logic otherwise. *\
(package mvfs []

\* ===== the read decision result ===== *\
(datatype read-result
  Hash:hash; Tok:string;
  ==============================
  [serve Hash Tok] : read-result;

  Reason:string;
  ==============================
  [deny Reason] : read-result;)

\* ===== §5.3 serve token: b64url(msg) "." HMAC-SHA256(key, msg) =====
   msg = US-join(hash, principal, acl-version, expiry, nonce) — the exact field
   set covered by the MAC (spec/04 §B.6.2). *\
(define token-msg
  { hash --> principal --> number --> number --> string --> string }
  Hash Princ Aclv Exp Nonce
  -> (join (n->string 31) [Hash Princ (str Aclv) (str Exp) Nonce]))

(define mint-token
  { string --> hash --> principal --> number --> number --> string --> string }
  Key Hash Princ Aclv Exp Nonce
  -> (let Msg (token-msg Hash Princ Aclv Exp Nonce)
       (@s (b64url Msg) "." (hmac-sha256 Key Msg))))

\* ===== I8: as-of basis gate — node must be caught up componentwise ===== *\
(define basis-behind?
  { number --> number --> number --> number --> boolean }   \* reqseq reqacl appseq appacl *\
  ReqSeq ReqAcl AppSeq AppAcl -> (or (< AppSeq ReqSeq) (< AppAcl ReqAcl)))

\* ===== the read decision (spec/04 §A.1 + B.6) =====
   1. I8: refuse if the node's applied basis is behind the request basis.
   2. I9/I6: authorize FIRST (authorize-then-resolve; a deny must not even reveal
      whether the path exists — the edge maps every deny to a uniform 403).
   3. §5.2: resolve (root-tree, path) -> blob hash.
   4. §5.3: mint the per-principal, expiring, single-use serve token bound to the
      blob hash and the applied acl-version. *\
(define read-decide
  { string --> principal --> hash --> path --> number --> number --> number --> number --> boolean --> string --> read-result }
  Key Princ Root Path ReqSeq ReqAcl AppSeq AppAcl Allow Nonce
  -> (if (basis-behind? ReqSeq ReqAcl AppSeq AppAcl)
         [deny "I8 basis-behind: node not caught up (block<=T_ryw then redirect/fail-closed)"]
         (if (not Allow)
             [deny "I9 acl-deny"]
             (let Blob (resolve-path Root Path)
               (if (= Blob "")
                   [deny "not-found"]
                   [serve Blob (mint-token Key Blob Princ AppAcl (+ (now-secs "") 30) Nonce)])))))

\* ===== §5.3 verify (the edge contract, also implemented in serve/verify.lua) =====
   recompute the MAC (constant-time compare), then check: token is for THIS hash,
   bound to THIS principal, minted at acl-version >= required, not expired, and
   the nonce is unused (single-use). Fail closed on any malformed/failed check. *\
(define verify-fields
  { (list string) --> hash --> principal --> number --> string --> boolean }
  [Hash Princ2 AclvS ExpS Nonce] ExpHash Princ ReqAcl Store
  -> (and (= Hash ExpHash)
       (and (= Princ2 Princ)
        (and (>= (str->num AclvS) ReqAcl)
         (and (<= (now-secs "") (str->num ExpS))
          (if (nonce-seen? Store Nonce)
              false
              (nonce-record! Store Nonce))))))
  _ _ _ _ _ -> false)

(define verify-token
  { string --> string --> hash --> principal --> number --> string --> boolean }
  Key Token ExpHash Princ ReqAcl Store
  -> (let Parts (split "." Token)
       (if (< (length Parts) 2)
           false
           (let MsgB64 (head Parts)
            (let Tag (head (tail Parts))
             (let Msg (unb64url MsgB64)
              (if (not (consttime-eq Tag (hmac-sha256 Key Msg)))
                  false
                  (verify-fields (split (n->string 31) Msg) ExpHash Princ ReqAcl Store))))))))
)
