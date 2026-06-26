---
date: 2026-06-25
researcher: Claude
topic: "Perf-panel synthesis — does the OpenResty/shen-lua hot-path architecture hold, and does it reopen the language decision?"
inputs:
  - thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
  - thoughts/shared/plans/dvcs-vfs/27-agentzh-perf-review.md
  - thoughts/shared/plans/dvcs-vfs/28-fukamachi-perf-review.md
  - thoughts/shared/plans/dvcs-vfs/29-aphyr-perf-review.md
  - thoughts/shared/plans/dvcs-vfs/30-ptacek-perf-review.md
tags: [synthesis, performance, openresty, shen-lua, ocaml, decision, read-tier]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# Perf-panel synthesis: the read-tier pattern is a keeper; the Shen-on-LuaJIT bet is not

Four reviewers (agentzh — OpenResty author; Fukamachi — Woo author; Aphyr — consistency;
Ptacek — edge security) assessed the hot-path perf architecture (`26`). The result is clear and,
honestly, a little humbling for the doc: **the architectural *pattern* is genuinely good and worth
adopting, but it is not Shen-specific, the one Shen-specific perf claim is false, and it carries
serious unspecified obligations.** Net: it **reinforces the all-OCaml verdict** while contributing a
valuable, language-neutral read-tier design.

## 1. Verdicts

| Reviewer | Lane | Verdict | Counts |
|---|---|---|---|
| **agentzh** (`27`) | OpenResty/LuaJIT | Conditional yes; the JIT premise is false as written | 2 Critical, 3 Major |
| **Fukamachi** (`28`) | server-perf/ship | Shippable as a *pattern*, not a reason to choose Shen; **reinforces all-OCaml** | 1 Blocker, 5 Significant |
| **Aphyr** (`29`) | consistency | Foundation good; RYW/monotonic enforcement asserted-and-deferred | 2 Critical, 3 Major |
| **Ptacek** (`30`) | edge security | **NO as written** — caches private content under hash-only keys; ships a breach | 2 Critical, 5 High |

## 2. What's genuinely validated (adopt this, in any language)

All four credit the core pattern:
- **"Brain decides, nginx serves zero-copy."** A decision tier resolves `(commit,path)→hash` + checks
  ACL, then `X-Accel-Redirect`/`ngx.exec` to an `internal` location that `sendfile`s the blob — the
  decision logic never touches the bytes. (agentzh: "exactly what I'd build.")
- **Content addressing ⇒ zero-invalidation blob caching**, to RAM, disk, and a CDN edge.
- **`as-of` basis header** for cheap consistent reads off a scale-out tier (Aphyr: the right
  Datomic-style primitive).

## 3. The three things the doc got wrong (and the one that ends the Shen-perf thesis)

1. **[ends the thesis] "Running is near-native LuaJIT" is false** (agentzh F1). Shen-compiled Lua
   (Lisp-with-types) hits LuaJIT's trace-killers → runs *interpreted*, not trace-compiled. The fix —
   relocate the Shen runtime to **build/land time so it emits data (lookup tables + a trie matcher)**
   and make the hot path hand-written Lua over that data — means **Shen is no longer on the hot path
   at all.** Combined with Fukamachi's F0 (below), the Shen-specific perf advantage evaporates.
2. **The win is not Shen-specific** (Fukamachi F0 — the decisive point). `X-Accel`+`sendfile`+
   content-addressed caching+CDN-`immutable` is available to an **OCaml decision tier behind the same
   nginx**. The doc never demonstrates a perf delta that survives an OCaml-behind-nginx baseline on a
   cache-dominated workload. So the good idea **transfers into the all-OCaml plan**, and the
   Shen-specific machinery (compile-per-path, two prod runtimes + two codegen stages, the partial-eval
   generator) is **pure operational cost** — the same multi-runtime 3am-debugging shape that sank
   shen-go, multiplied.
3. **Two hard obligations are language-agnostic and unspecified** — they must be designed in
   regardless of language:
   - **Security (Ptacek):** the `internal /cas/<hash>` handoff is an authz-bypass waiting to happen
     (hash = read capability; one missing `internal;`/smuggled header = read the whole monorepo), and
     caching private per-principal content under a hash-only edge key serves it cross-principal by
     construction. Fix: **HMAC'd single-use `(hash, principal, acl-version, expiry)` serve tokens**
     minted in the authorized resolve step (fail closed), **public/private tier split**,
     **per-principal cache partitioning**, and an answer to **revocation under an `immutable` edge
     cache** (the fired-employee problem).
   - **Consistency (Aphyr):** the `as-of` header is carried but not enforced → RYW + monotonic reads
     break; the resolve/ACL caches are *versioned, not immutable* and must be keyed/invalidated as
     such. Fix: applied-basis enforcement (block/redirect when behind), immutable-basis cache keys,
     fail-closed at stale acl-version, committed-watermark-only caching, client high-water-mark.

## 4. The decision impact

**The perf exploration was productive but it does not reopen the language choice — it confirms
all-OCaml.** Reasoning, straight from the panel:
- The Shen path's perf rescue depended on "shen-lua runs fast on LuaJIT," which is false; the fix
  removes Shen from the hot path entirely.
- Every validated win (read/serve split, content-addressed caching, as-of reads) is **language-neutral
  and applies to an OCaml decision tier behind nginx** — so they are reasons to add a *read tier to
  plan `13`*, not reasons to choose Shen.
- The unsolved obligations (serve-token security, cache-coherent RYW) are language-agnostic and equally
  required either way.

So the user's instinct ("there's a creative way to get perf here") was *right* — there is, and it's a
good one — but it turns out to be **a reverse-proxy topology, not a Shen feature.** It makes the
*all-OCaml* product faster; it does not make *Shen* the right choice.

## 5. What to carry into plan `13` (the durable output of this round)

Add a **read-tier design** to the all-OCaml plan, with the panel's fixes baked in:

| Item | Source | Detail |
|---|---|---|
| OCaml decision tier behind nginx | Fukamachi F0 | resolve+ACL in OCaml; `X-Accel-Redirect` to `internal` CAS location |
| Zero-copy serve | agentzh F3 | `sendfile`+`open_file_cache`; **kTLS** for TLS zero-copy; `aio threads`+`directio` for big blobs |
| Cache hierarchy | agentzh F2 | live-object L1 (per-worker LRU) + L2 shared/disk + CDN; **mlcache-style**, not raw shared_dict |
| Serve tokens | Ptacek S1/S2 | HMAC'd single-use `(hash,principal,acl-version,expiry)`; `internal;` mandatory; public/private tier split; per-principal partitioning |
| Consistent reads | Aphyr | enforce `as-of` (block/redirect when behind); versioned resolve/ACL cache keys; committed-watermark-only; client high-water-mark |
| Cold-fan-in | agentzh F4 / Torvalds (orig) | request coalescing (single-flight) + batched `want`-set fetch (HTTP/2) |
| Policy matcher | agentzh F6 | compile landed Datalog policy to a **trie/table** (lookup), not branchy generated code |
| Revocation story | Ptacek S5 | short TTLs on private edge cache; explicit revocation propagation |

These belong in `13` as the "P5/P6 serving + mount" design, and they are independent of (and do not
delay) the P0 spine.

## 6. Bottom line

- **Adopt the read-tier *pattern*** (brain-decides/nginx-serves/content-cached/as-of), with the
  security + consistency fixes — into the **all-OCaml** plan.
- **Do not adopt** the Shen-on-LuaJIT hot path: the JIT premise is false, and the fix removes Shen
  from the hot path, leaving only operational cost with no perf delta over OCaml-behind-nginx.
- **The language verdict stands: all-OCaml** (`25`), now with a concrete, panel-hardened serving tier.

The expressiveness/provability case for Shen (the `25` "if you want the Shen brain" branch) is
unaffected by this round — it was always a *values* argument (expressive + provable + exploratory),
not a perf argument. This round simply shows perf is **not** an additional reason to pick Shen.

## Appendix — perf-layer docs
`26` hot-path architecture → `27` agentzh · `28` Fukamachi · `29` Aphyr · `30` Ptacek → `31` this
synthesis.
