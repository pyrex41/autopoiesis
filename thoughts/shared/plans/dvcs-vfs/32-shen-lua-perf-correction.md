---
date: 2026-06-25
researcher: Claude
topic: "Correction: pyrex41/shen-lua is a JIT-engineered LuaJIT target — agentzh's F1 (the load-bearing perf objection) is refuted by the actual implementation"
inputs:
  - https://github.com/pyrex41/shen-lua (README)
  - thoughts/shared/plans/dvcs-vfs/27-agentzh-perf-review.md
  - thoughts/shared/plans/dvcs-vfs/31-synthesis-perf.md
  - thoughts/shared/plans/dvcs-vfs/25-final-verdict-go-vs-ocaml.md
tags: [correction, shen-lua, luajit, performance, decision-revision]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# Correction: the actual `shen-lua` refutes the perf objection

The perf panel's load-bearing objection (agentzh F1, `27`) was: *"shen-lua's generated code won't
JIT — a Lisp-with-types compiled to Lua hits LuaJIT's trace killers (boxing, non-tail recursion,
megamorphic dispatch, NYIs), so it runs interpreted."* That was **a-priori reasoning about a naive
port**, not a measurement of the real one. The real one — **`pyrex41/shen-lua`, authored by the user
(pyrex41), who also wrote shen-go, shen-rust, and has shen-ocaml in development** — was engineered
specifically to dodge every trace-killer named. Reading its README:

## What shen-lua actually is (from the README)

- **Targets LuaJIT 2.1**; **source-to-source compiles KLambda → Lua source → LuaJIT
  trace-compiles to machine code.** Not a tree-walker, not an interpreter.
- **JIT-friendly value representation by design** (the README's words: "hot paths stay
  trace-JIT-friendly," "avoiding unnecessary boxing"): numbers→Lua numbers, strings→strings,
  bools→bools, symbols→interned tables, NIL→sentinel, cons→`{h,t}`+metatable, vectors→array tables,
  functions→Lua functions.
- **Native tail calls**: statement-based codegen with **tail-call-to-loop lowering**; real Lua
  `return` + `if`/`elseif` chains → LuaJIT proper tail calls ("the kernel relies on TCO heavily").
- **Special forms emit native Lua control flow** (`if`/`cond`/`let`/`do`/`lambda`) — no dispatch
  interpreter.
- **Native `soa32` substrate for the Prolog engine + typechecker**: terms as plain Lua numbers,
  range-tagged over **int32 FFI arrays**, `<` comparisons for tag tests — no bit ops, no 64-bit
  cdata. **8.9× faster than the legacy engine, −93% allocation per inference.**
- **Content-keyed caches**: kernel bytecode cache (`string.dump`, **~30 ms warm boot** vs ~1 s
  recompile); user fasl cache (skips reader/macroexpand/typecheck).
- **Benchmarks (Apple Silicon, LuaJIT 2.1)**: warm suite ~2.3 s; **~1.5× slower than shen-cl on
  SBCL** with caching.

## Point-by-point: agentzh F1 vs reality

| agentzh's predicted trace-killer | shen-lua's actual design |
|---|---|
| boxing / type-tagged values | values map to Lua primitives; "avoiding unnecessary boxing"; explicitly "trace-JIT-friendly" |
| deep / non-tail recursion | tail-call-to-loop lowering + native Lua proper tail calls |
| megamorphic dispatch | special forms emit native Lua control flow directly |
| Datalog/Prolog won't JIT (F6) | native soa32 FFI-int32 inference substrate, **already 8.9× / −93% alloc** |
| "runs interpreted, 10×+ haircut" | source→Lua→**machine code**; **~1.5× of SBCL**, not 10× |

**Verdict on F1: refuted for this implementation.** agentzh's instinct is correct for a *generic*
Lisp-to-Lua transpiler; it does not describe `shen-lua`, which is a performance-engineered LuaJIT
target with a data-oriented inference engine. "shen-lua is LuaJIT and very fast" is **accurate**.

## What this changes (and what it doesn't)

**Changes — perf is no longer a disqualifier for the Shen path:**
- The `26` thesis ("proving is build-time; running is fast on LuaJIT") is **true** for shen-lua, not
  optimistic. The hot path compiles to machine code; the inference/ACL engine is already fast and
  allocation-light.
- The earlier all-OCaml verdict (`25`) leaned partly on premises that **do not hold for pyrex41**:
  "Shen is slow / unproven on the hot path" (false — benchmarked, JIT-compiled), "betting on ports
  that don't exist" (false — the user wrote shen-lua/go/rust; ocaml in dev), "single-maintainer
  transpiler is a prod risk / bus-factor" (it is the user's own, intentionally — and for an
  expressive/provable reference implementation that is the point, not a hazard). Those premises were
  generic risk priors; they're wrong for the person who owns and benchmarked the toolchain.
- The "one provable source → best host per path" strategy (`26` §2) is **real, not hypothetical**:
  shen-rust has an AOT-compiled kernel, shen-go a bytecode VM, shen-lua a LuaJIT machine-code target.

**Does NOT change (these stand regardless of language, and are the real remaining work):**
- **Security obligations (Ptacek `30`):** the hash-as-capability bypass and per-principal-vs-edge-cache
  tension are language-agnostic. Still must be designed (serve tokens, tier split, per-principal
  partitioning, revocation).
- **Consistency obligations (Aphyr `29`):** `as-of` enforcement, versioned resolve/ACL cache keys,
  monotonic reads — language-agnostic. Still must be specified.
- **Fukamachi's F0 (`28`)** is *technically* still true (the read/serve pattern isn't Shen-exclusive),
  but it is now **moot for the decision**: the user's case for Shen was always
  expressiveness + provability, and the only thing F0/agentzh added was "and you pay a perf tax for
  it." That tax is now measured at ~1.5× SBCL with a machine-code hot path — i.e., **not a tax worth
  trading expressiveness/provability away for.**

## Revised recommendation

For **pyrex41 specifically** — the author of a fast, JIT-compiled, provable Shen with a native
inference engine and three working backends (+ OCaml in dev) — **the all-Shen path is not the risky
choice the generic panel made it out to be; it is the natural one.** The earlier all-OCaml verdict
was over-indexed on portability/maturity/bus-factor priors that don't apply when you own and have
benchmarked the toolchain. With perf removed as a disqualifier:

- **Build it in Shen** (shen-lua hot path + a land tier; shell out to `git` for CAS/merge per the
  user's direction), using the native soa32 inference substrate for the **Datalog ACL/policy control
  plane** (already fast), and the sequent type system for the provable land-FSM/lease/merge
  invariants.
- The genuinely-remaining work is **language-agnostic and unchanged**: the fenced single-leader
  land-queue kernel, the serve-token security model, and the as-of consistency contract. Build those
  next; they're the same in any language and they're what's actually hard.
- all-OCaml (`13`) remains a legitimate *alternative* if the goal shifts to "hire a team / hand it
  off," because Irmin + a mainstream language lowers the bus-factor for *other* people — but that is a
  team/organizational argument, not a technical-superiority one, and it does not apply to a
  solo/expressive/provable build.

## Honest note on process

The panel's value was real (the security + consistency findings stand and are important). But two
rounds of "Shen is slow/risky" rested on an assumption about `shen-lua` that a 5-minute read of its
README falsifies. The lesson: when the user has built the artifact, **read the artifact** before
deferring to a persona's prior. Corrected here.

## Appendix
Source: `pyrex41/shen-lua` README (public). Revises `27` (F1), `31` (perf synthesis), and the
weight of `25` (verdict) for the toolchain author. Security (`30`) and consistency (`29`) findings
unaffected.
