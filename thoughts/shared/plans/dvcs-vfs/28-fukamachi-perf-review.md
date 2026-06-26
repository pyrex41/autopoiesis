---
date: 2026-06-25
reviewer: "Eitaro Fukamachi (persona)"
status: review
topic: "Server-perf + shippability review of the hot-path performance architecture (26): a provable Shen brain compiled per-path, OpenResty/shen-lua read tier + shen-SBCL/go land tier"
target: thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
inputs:
  - thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
  - thoughts/shared/plans/dvcs-vfs/25-final-verdict-go-vs-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/10-fukamachi-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/19-fukamachi-shen-backends.md
tags: [review, performance, shen, lua, openresty, luajit, sendfile, x-accel, edenfs, ocaml, multi-runtime, build-matrix, shipping]
---

# Server-perf + shippability review of `26` (the hot-path perf architecture)

My lane, unchanged across every review I've written for this project: **will it ship, what breaks in
production, and what does the build/deploy/dependency/concurrency surface actually look like under
load.** I built Woo (libev, the fastest CL HTTP server), Clack, Dexador; I have spent more of my life
than I'd like inside event loops, `sendfile`, and the gap between "fast in a benchmark" and "fast in
prod." The consistency model is Aphyr's (his §9.4); the OpenResty internals — `lua_shared_dict` GC,
cosocket semantics, FFI-vs-NYI on LuaJIT traces — are agentzh's (he wrote it, §9.1/§9.2); the
X-Accel/cache-poisoning/multi-tenant-isolation security is Ptacek's (§9.5). I stay adjacent and only
touch those where they collide with shippability.

I'm reviewing this as the doc's own appendix asks: *"the Shen path's answer to the hot-path concern
that drove the OCaml recommendation."* So the operative question for me is narrow and I will answer it
flatly at the end: **does this perf story move me off the all-OCaml lean I and the panel landed on in
`25`?**

---

## Verdict

**The core perf *insight* is correct and I'll defend it. The perf *architecture as a shippable
system* is not — it converts a one-runtime, one-toolchain, one-failure-domain product (all-OCaml,
`13`) into a three-system fleet (OpenResty/LuaJIT read tier + shen-SBCL/go land tier + the Shen→Lua
build pipeline that generates and version-locks the Lua), and it does so to win a hot-path battle that
all-OCaml can win *with the same architectural move* and none of the new operational surface.**

The decisive thing to understand: **"brain decides, nginx serves zero-copy" is not a Shen idea. It is
a deployment topology that any language can adopt**, and it is in fact *the exact mitigation I already
prescribed for OCaml* in `10` (Findings 2 + 6: "the bytes never need to cross the bridge; put a
content-hash read cache in front and only the *decision* path is hot"). The doc's strongest section
(§3, the X-Accel handoff) is a perf pattern, not a language argument. Strip the Shen framing away and
what's left is "front your decision tier with nginx and `sendfile` the blobs" — which is true,
excellent, and equally available to the all-OCaml build. The doc smuggles a general perf win in as if
it were a Shen-specific win, and that's the move I most want the panel to see through.

So: **shippable as a *pattern* (adopt the read/serve split regardless of language); not shippable as a
*reason to choose Shen*.** The multi-backend-from-one-source story is, from the build/ops seat, a
version-skew and observability liability heavier than the single-runtime all-OCaml it's trying to
rescue. Severity-ranked findings below.

**1 Blocker, 5 Significant, 2 Nice-to-have.**

---

## What the doc gets right (I won't damn the good parts)

Credit where it's due, because the perf reasoning is mostly sound and I'd lift three ideas straight
into the OCaml plan:

1. **Build-time proof vs run-time speed is a real dissolution (§1).** The "category error" framing is
   correct: a type checker that ran at build time is not in the request path. This is true and it's
   the right rebuttal to a lazy "provable ⇒ slow" objection. (It is *also* true of OCaml's GADTs,
   which the panel already noted — so it argues for "compile your proofs away," not for Shen
   specifically.)
2. **Content addressing ⇒ zero-invalidation caching (§3.1).** This is the genuinely beautiful
   property and it is the one I'd build the whole perf story around in *any* language. A hash names one
   byte string forever; every cache layer (in-process, on-disk, CDN `immutable`) is correct by
   construction. I said the same thing in `10` ("a hash is a hash forever") about the OCaml read
   cache. It's the best idea in the document and it is language-agnostic.
3. **Brain-decides / nginx-serves with `X-Accel-Redirect` + `sendfile` + `open_file_cache` (§3).**
   This is exactly how you keep a slow-ish language off the byte path, and it's how I'd architect it
   too. `sendfile` to keep bytes in the kernel, `open_file_cache` to keep the fd hot, the decision
   tier never touching the payload — all correct event-loop-server instinct. (Caveats on where it
   leaks: below.)
4. **EdenFS shape (§4): fast source-of-truth service + thin caching mount.** Correct and honest. You
   were never running a kernel mount inside Shen *or* OCaml; the mount is a thin client either way.
   Good that the doc says so out loud.

None of (1)–(4) require Shen. That's the whole problem with using them as a Shen argument.

---

## Findings

### F1. [Blocker] You now ship and operate THREE production systems from one source; the "one provable source" framing hides a build/version/observability surface heavier than all-OCaml's one-runtime story

**Concern.** The doc sells "one provable Shen source, compiled per-path" (§2) as an *advantage* — a
single spec, many fast bodies. From the ops seat that is precisely backwards: **one source, many
*targets* means you run, version, patch, monitor, and debug N independent runtimes in prod, and the
"one source" guarantee is only as good as your ability to prove all N targets were built from the same
revision and behave identically.** Concretely, this architecture deploys:

1. **The read tier:** OpenResty (nginx + LuaJIT) running *generated* Lua emitted by shen-lua, plus a
   *separately generated* Lua ACL matcher from the partial-eval Datalog→Lua step (§6, see F6).
2. **The land tier:** shen-SBCL (or shen-go) shelling out to `git` — a second language runtime, a
   second GC, a second compiler toolchain, plus `git` as a trusted oracle subprocess.
3. **The Shen toolchain itself** as a *build-time dependency in your release pipeline* — shen-lua,
   shen-SBCL/go, the Datalog→Lua generator (F6) — each of which must be pinned, vendored, and CI'd, or
   your "one source" is floating against a moving transpiler.

Compare to all-OCaml (`13`): **one compiler, one runtime, one GC, one type system, one in-process
transactor, one binary to ship.** I spent my Blocker in `10` insisting the team pin/vendor/seam *one*
upstream (Irmin). This architecture asks them to do that discipline for **three toolchains plus two
generated-artifact pipelines**, and then — the part nobody budgets — to keep them *version-coherent*:
when a land happens, the read tier's resolve cache and (if policy changed) its generated Lua matcher
must be regenerated, redeployed across a stateless fleet, and proven to match the land tier's view.
That's a distributed-build-coherence problem the all-OCaml build simply does not have.

The 3am-page math is the killer, and it's the *same shape* as the one Ptacek and Hickey killed shen-go
on in `25` ("a silent data-loss fork correlated across a Go panic, a Shen error, and a daemon log
nobody can read"). Here it's worse: a wrong read could be a LuaJIT trace bailout *or* a stale
generated matcher *or* a shen-lua codegen bug *or* a resolve-cache that's behind the land tier *or* the
land tier itself — across **two languages, two runtimes, and two codegen stages**, debugged by an
on-call who has to read Lua-generated-from-Shen *and* SBCL-Shen *and* nginx logs. "One provable
source" does not help you at 3am when the question is "which of my three runtimes lied."

**Recommendation.** This is the load-bearing finding and it's why the verdict is what it is. Either:
- **(a)** Adopt the *topology* (read/serve split, content-addressed caching, X-Accel `sendfile`) in
  **all-OCaml** — OCaml can sit behind nginx with X-Accel exactly the same way; the brain-decides tier
  is an OCaml HTTP service, the byte path is nginx `sendfile`, and you keep **one runtime**. You get
  100% of the perf insight (F0/§3) with **none** of the multi-runtime ops surface. This is my actual
  recommendation and it's free — see F0.
- **(b)** If you insist on the Shen source, do **not** ship two Shen *backends*. Pick **one** Shen
  target for *both* tiers (e.g. shen-lua/OpenResty for reads and a small OpenResty-hosted land
  endpoint that shells to `git`, or shen-SBCL for both with nginx in front), so you operate one Shen
  runtime, not two. The "best host per path" cleverness is the source of the multi-runtime tax; drop
  it and you've at least halved the ops surface.

Shipping a product means operating it for years. "One source, three runtimes" optimizes the artifact
you write and pessimizes the system you run. I've maintained libraries other people operate; the thing
that kills them is exactly this — elegant at authoring time, a fleet of failure domains at 3am.

### F0. [Significant — and it's the reframe] The read/serve split is a topology, not a language; all-OCaml gets the identical perf win behind the same nginx

**Concern.** The doc's central perf claim (§3, §8) is "Shen decides, nginx serves." But nginx +
`X-Accel-Redirect` + `sendfile` is a **reverse-proxy contract**, not a Lua feature. *Any* upstream
that can compute a decision and return an `X-Accel-Redirect: /cas/<hash>` header gets the kernel
zero-copy byte path. An OCaml (or Go, or Rust) decision service behind nginx serves blobs with the
exact same `sendfile`, the exact same `open_file_cache`, the exact same CDN-`immutable` edge story.
The doc never shows what shen-lua-*in-process* buys over OCaml-*behind-nginx*, and the honest answer is:
**only the in-process `lua_shared_dict` decision cache** — and that is a cache, which any language can
also have (in-process hashmap, mmap, or a sidecar), and which for the resolve+ACL working set is small
and cheap regardless of host.

So the real question the doc dodges: is the *decision path* — resolve `(commit,path)→hash` + ACL check
— so hot that running it in LuaJIT-in-nginx beats running it in OCaml-behind-nginx? On a
content-addressed workload where both layers hit a warm cache ~always (the doc's own §3.1 premise),
**no.** The byte path is identical (kernel `sendfile` either way), and the decision path is a
cache-hit dict lookup either way. The doc is optimizing the part that isn't the bottleneck and paying
the three-runtime tax (F1) to do it.

**Recommendation.** State the all-OCaml-behind-nginx baseline explicitly and benchmark against it
before adopting any of the Shen machinery. I'd bet a good dinner the difference at moderate scale is in
the noise, and the moment it is, F1's entire cost is unjustified. **Put nginx + X-Accel + sendfile in
front of the all-OCaml decision tier and you've imported the doc's best idea into the winning plan.**
This is the single most valuable thing this document produced, and it argues *for* `13`, not for Shen.

### F2. [Significant] The decision path runs per-request and is where the perf story actually leaks; the doc's latency budget undercounts it

**Concern.** §4's budget is honest about the warm/local cases (microseconds, never leave the box) and
the cold case (1 RTT + transfer). But the *per-request* decision path is glossed as "~tens of µs,
shared_dict, JIT'd," and that's the part that doesn't get to be free, in *any* language:

1. **Cache-miss amplification on the resolve step.** A `(commit, path)` resolve is a *tree walk* on a
   cold subtree — not one dict lookup but potentially many, each possibly a `shared_dict` miss that
   faults a tree object from disk/CAS via `cosocket` (§6). The doc waves at this with "batch the
   `want` set" (§6, HTTP/2) but a cold `git checkout`-shaped access pattern (open an IDE on a fresh
   clone) is exactly the fan-out storm Torvalds flagged, and it lands on the *decision* tier, not the
   byte tier. "shared_dict hit ~always" is true in steady state and false on the workload that
   actually stresses you (first-access, CI runners, cold replicas after a deploy).
2. **TLS + sendfile interaction.** This is squarely my lane and the doc ignores it. `sendfile`'s
   kernel zero-copy **does not apply to TLS-terminated connections** unless you have kTLS
   (kernel-TLS) configured and supported end to end — and OpenResty/nginx kTLS is a fussy, recent,
   kernel-version-gated thing. The instant you terminate HTTPS at nginx (which you will — this is a
   multi-tenant source-of-truth service), the "kernel zero-copy" claim degrades to "userspace copy +
   encrypt" unless kTLS is wired up. The doc's headline ("nginx serves bytes zero-copy") is **only
   true for plaintext or kTLS**, and it doesn't say so. For a security-sensitive code-serving service,
   plaintext is off the table, so this needs a kTLS line item or the zero-copy claim is overstated.
3. **The mount is still not HTTP (the doc's own §9.3).** Agreed and important: OpenResty makes the
   *service* fast; the FUSE/9p syscall path is where mount latency lives, and that's unchanged by any
   of this. This is the same point I made in `10`/`19` — ship no-mount as the real default.

**Recommendation.** Rewrite §4's budget to (a) cost the *cold-subtree resolve* fan-out explicitly (it
dominates first-access), (b) state the TLS/kTLS precondition for the zero-copy claim and treat kTLS as
a real, kernel-version-gated dependency (or honestly downgrade to "userspace serve, no Lua copy"), and
(c) keep the no-mount default. None of these are Shen-specific; they're the leaks in the *topology*,
and they apply identically to the all-OCaml-behind-nginx version — which is fine, because that's the
version I want you to build.

### F3. [Significant] The load-bearing assumption — shen-lua emits JIT-friendly LuaJIT — is unproven and is exactly the kind of "asserted maturity" I've now caught wrong twice on this project

**Concern.** The doc names this itself as "**the load-bearing assumption**" (§9.1) and it is right to.
But naming it doesn't de-risk it, and history on this project says be skeptical: in `19` I caught
*both* Shen-variant plans asserting library maturity the public record contradicted (go-git's merge,
gix's merge — both backwards). This is the same genre of claim. shen-lua emitting code that **JITs
well on LuaJIT (Lua 5.1 dialect)** — as opposed to merely *runs* on reference Lua — is a real, specific
risk:
- Shen's runtime carries type-tagged dynamic values, a reader, tail calls, and possibly bignums. If
  the generated Lua boxes everything into tables and trampolines tail calls, you get **NYI (not-yet-
  implemented) trace abilities and trace aborts** that drop you to the LuaJIT interpreter — at which
  point your "near-native LuaJIT" decision tier is running *interpreted* Lua emitted by a transpiler,
  which is plausibly **slower than the OCaml-behind-nginx baseline** you're trying to beat.
- LuaJIT GC under a large `shared_dict` of trees/decisions (§9.2) — agentzh's lane, but it's a
  shippability risk: LuaJIT's GC and some builds' ~2GB address constraints vs a monorepo's hot tree
  set is an open question the doc flags and doesn't answer.

**Recommendation.** This must be a **hard gating spike before any of this is planned, not an open
question for the panel.** Take a representative resolve + ACL path, compile it shen-lua→LuaJIT, run it
under `-jv` / `jit.dump`, and **count trace aborts and NYIs on the hot functions.** If the hot path
doesn't stay on green traces, the entire "near-native LuaJIT read tier" premise collapses and you're
strictly worse than OCaml-behind-nginx. Gate the whole Shen-perf direction on this measurement. Do not
let "compiles away to fast Lua" be a faith claim — I've been burned by exactly-this-shaped claim twice
already in these reviews.

### F4. [Significant] Build matrix and lockfile posture: the realistic surface is multiples of all-OCaml's, and the generated artifacts need their own versioning

**Concern.** My standing rule (the `10` Blocker, the `19` C1) is pin + vendor + lockfile + cold-cache
CI per upstream. Apply it honestly here and count the surface:

| Axis | all-OCaml (`13`) | This perf architecture (`26`) |
|---|---|---|
| Language runtimes in prod | 1 (OCaml 5.x) | **2** (LuaJIT, SBCL/Go) |
| Compiler/transpiler toolchains pinned | 1 (ocaml + opam.locked) | **≥3** (shen-lua, shen-SBCL/go, Datalog→Lua generator) |
| Lockfiles | `opam.locked` | opam/quicklisp-or-go-mod **+** OpenResty/luarocks **+** the Shen toolchain pins |
| Generated artifacts to version | 0 | **2** (generated Lua read tier, generated Lua ACL matcher) — see below |
| Deploy units | 1 binary | **OpenResty fleet config + read-tier Lua bundle + land-tier binary + git** |
| Native deps | libfuse/9p (mount only), xdiff | nginx + LuaJIT + OpenResty modules, libfuse/9p, git, SBCL/Go runtime |

The new and nasty one is **versioning the generated Lua**. Generated code is a build artifact, but it's
*also* what runs in prod across a stateless fleet, and it must be coherent with (a) the Shen source
revision it came from and (b) the landed `acl-version` (§6). So you need: a content hash of the
generated bundle, a deploy mechanism that rolls it across the fleet atomically-enough, and a way to
detect a node running stale generated Lua against a newer landed policy. That's a small CD system in
its own right. all-OCaml ships one versioned binary and is done.

**Recommendation.** If this direction survives F1/F3, write the **full build matrix and the
generated-artifact versioning scheme** before committing — treat generated Lua like a compiled binary
with a version stamp, a rollout story, and a "stale artifact" alarm. Compare the CI job count honestly
against `13`'s single cold-cache lockfile build. I expect the comparison to make the all-OCaml choice
self-evident.

### F5. [Significant] Two writers of truth at the protocol seam: the land tier (SBCL/git) and the read tier (Lua) must agree on resolve + ACL semantics, and they're in different languages

**Concern.** §7's proof table is the tell: ACL soundness is proved in Datalog at build time but **runs
in two places — "read tier (generated Lua) + land tier"** — and the land-FSM runs in SBCL. So the same
invariant is enforced by two *different compiled artifacts in two different languages*. The "one
provable source" claim is supposed to make this safe, but it only does if (a) both backends are built
from the identical Shen revision and (b) shen-lua and shen-SBCL codegen are semantically identical on
the relevant constructs. (a) is the version-coherence problem in F1/F4; (b) is a *second* faith claim
on top of F3 — now you need *both* shen-lua *and* shen-SBCL to be faithful, not just one. A
divergence here is an authorization bug (read tier allows what land tier would deny, or vice versa),
which is the worst category to have split across runtimes.

**Recommendation.** This is why the partial-eval differential test (§6, F6) is load-bearing — but it
only covers the Lua matcher vs the Datalog oracle, not shen-lua-codegen vs shen-SBCL-codegen of the
*rest* of the decision logic. Add a **cross-backend conformance suite**: same inputs, assert
read-tier-Lua and land-tier-SBCL produce identical resolve + ACL decisions, run in CI on every Shen
source change. In all-OCaml this finding **does not exist** — there's one compiled enforcement, used by
both the read service and the land transactor in-process. Single runtime makes the whole class of
cross-backend-divergence authz bugs unrepresentable. That's a real, concrete simplicity win for `13`.

### F6. [Nice-to-have → Significant if pursued] The partial-eval Datalog→Lua generator is a science project until proven otherwise; ship the interpreter first

**Concern.** §6 proposes specializing the landed Datalog ACL ruleset into generated LuaJIT-friendly
matcher code at policy-land time, differential-tested against the Datalog oracle. As a *perf
optimization* this is reasonable. As a *build artifact you maintain forever*, it's a partial evaluator
— a genuinely subtle program-generation tool — sitting on the **authorization hot path**, whose
correctness ("generated Lua ≡ Datalog as rules evolve," the doc's own §9.6) is asserted to be covered
by differential testing. Differential testing finds *present* divergences on the inputs you test; it
does not prove equivalence, and an ACL matcher that's subtly wrong on an untested input is a security
bug (Ptacek's lane, but I flag the shippability of *maintaining a code generator* on the auth path).

**Recommendation.** **Don't build the generator for v1.** ACL evaluation on a content-addressed
workload is cache-dominated (one `(principal, path-prefix, acl-version)` dict lookup in steady state,
§6) — the *interpreter* over a small landed ruleset, behind that decision cache, is almost certainly
fast enough, and it's one fewer code generator to own and prove. Ship the interpreted matcher +
decision cache; reach for partial-eval only if a measurement shows the interpreter is the bottleneck
(I doubt it will be). A maintained partial evaluator on the auth path is the kind of thing that's
delightful in a paper and a liability in a pager rotation.

### F7. [Nice-to-have] X-Accel internal-location hardening and shared-cache isolation are real but they're Ptacek's call; I only note they're prerequisites, not afterthoughts

**Concern.** §9.5 flags it correctly: the internal `/cas/<hash>` location must be unreachable directly
(or ACL is bypassed), and multi-tenant `shared_dict` isolation + cache-key poisoning are open. From the
shipping seat these are *prerequisites* for a multi-tenant code-serving service, not hardening to add
later — a directly-reachable `/cas/` is a full ACL bypass. I defer the security analysis to Ptacek;
I only insist they're P0 gates, because "we'll lock the internal location down later" is how you ship a
read-anything bug.

**Recommendation.** Treat X-Accel internal-location enforcement and tenant cache isolation as
go-live gates with explicit tests (attempt direct `/cas/<hash>` fetch → must 403/404; cross-tenant
`shared_dict` read → must fail). Ptacek owns the depth here.

---

## Does this rescue the Shen path? (the question the doc was written to answer)

**No — it adds a third moving system to a Shen path the panel already judged heavier than all-OCaml,
and the one genuine win it surfaces (the read/serve split) belongs to all-OCaml just as much.**

Walking the panel's reasons from `25` against this doc:

- The all-OCaml lean was driven by **single-runtime simplicity, GADTs already expressing the
  invariants, one in-process transactor, and the hot-path/IO worry** (plus Ptacek's "single-maintainer
  transpiler in the prod failure path" and "repo-controlled logic on the authz hot path"). This doc
  addresses *one* of those — the raw hot-path throughput worry — by moving reads to LuaJIT. It does
  nothing about the others and **makes several worse**: it now puts *two* transpilers (shen-lua,
  shen-SBCL/go) plus a *partial evaluator* in the prod/auth failure path, where `25` already counted
  *one* transpiler as a Ptacek strike.
- The hot-path worry it claims to dissolve is dissolved **equally well by all-OCaml-behind-nginx**
  (F0). The doc never demonstrates a perf delta that survives the OCaml-behind-nginx baseline, and on a
  cache-dominated content-addressed workload I don't believe one exists at moderate scale.
- It introduces **new** worries the all-OCaml path doesn't have: cross-backend authz divergence (F5),
  generated-artifact version coherence across a stateless fleet (F1/F4), the unproven shen-lua→LuaJIT
  JIT-friendliness gating assumption (F3), and a maintained partial evaluator on the auth path (F6).

So this is not "the Shen path finally pays for itself." It's "the Shen path acquires a third
production system (OpenResty fleet) on top of the land tier and the Shen toolchain, in exchange for a
perf win that all-OCaml gets for free behind the same nginx." That is heavier than all-OCaml ever was
— which is the opposite of the doc's thesis.

The doc's appendix calls itself the Shen path's answer to the OCaml-driving hot-path concern. The
honest reading is that it **answers the concern by inventing a topology that benefits OCaml at least
as much**, and then attaches a multi-runtime build to it that only Shen needs. Take the topology;
leave the build.

---

## Does the perf story change my all-OCaml lean? — NO

**No. It reinforces it.**

Here's the precise logic:

1. The document's best, true, defensible idea is the **read/serve split** (brain decides, nginx
   `sendfile`s the bytes, content-addressing makes every cache correct). I already prescribed this for
   OCaml in `10`. The doc independently confirms it's the right hot-path shape.
2. That idea is **language-agnostic** (F0). all-OCaml gets identical hot-path perf by sitting its
   decision tier behind nginx with `X-Accel-Redirect` + `sendfile` + `open_file_cache` + a
   content-hash decision cache + CDN `immutable`. Same kernel zero-copy, same caching, **one runtime.**
3. The Shen-specific parts of the doc (compile-per-path, two backends, partial-eval generator) are not
   perf wins over that baseline — they're **operational costs** (three runtimes, two codegen stages,
   cross-backend authz divergence, generated-artifact version coherence, an unproven JIT-friendliness
   gate). They make the system heavier to build, deploy, and debug for no demonstrated throughput gain
   over OCaml-behind-nginx.
4. Therefore the perf architecture, read correctly, **transfers its one good idea into the all-OCaml
   plan and leaves its costs with Shen.** Net effect on my lean: it strengthens all-OCaml, because it
   surfaced the missing piece of the OCaml hot-path story (put nginx in front, X-Accel the blobs) and
   demonstrated that the Shen framing adds only operational tax to it.

**Concrete recommendation to the team:** import §3 (the read/serve split, content-addressed caching,
X-Accel `sendfile`, CDN `immutable`) into `13` as the OCaml read-tier architecture, add the kTLS line
item (F2) and the no-mount default, and **do not adopt the multi-backend Shen build.** If anyone wants
to seriously revisit Shen on perf grounds, the *one* experiment that could change my mind is F3's
gating measurement: shen-lua→LuaJIT staying on green JIT traces *and* beating an OCaml-behind-nginx
baseline on the cold-subtree resolve fan-out under load. Until that number exists, this is a more
expensive way to get a win OCaml already has.

---

## Relationship to prior reviews

- Extends `10` (Findings 2 + 6: keep bytes off the bridge, content-hash read cache) — this doc's §3 is
  the *same* insight generalized to a reverse-proxy topology; I endorse the insight and reclaim it for
  OCaml.
- Extends `19` (the "asserted maturity the public record contradicts" pattern) — F3's
  shen-lua→LuaJIT-JITs-well claim is the same genre of load-bearing-on-faith assertion; gate it with a
  measurement, don't plan on it.
- Consistent with `25`'s verdict — the multi-transpiler-in-the-prod/auth-path strike that helped sink
  shen-go is *multiplied*, not retired, by this architecture (two transpilers + a partial evaluator).

**Bottom line for the panel:** the perf architecture is a good perf *pattern* wearing a Shen costume.
Keep the pattern (nginx + X-Accel + content-addressed caching, in OCaml), discard the costume (three
runtimes from one source). It does not move me off all-OCaml; it shows me how to make all-OCaml's hot
path fast.
