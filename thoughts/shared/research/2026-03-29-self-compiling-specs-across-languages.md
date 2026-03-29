---
date: 2026-03-29T15:45:29Z
researcher: Claude
git_commit: de89822
branch: main
repository: autopoiesis
topic: "How self-compiling specifications work across different programming language paradigms"
tags: [research, architecture, language-design, specs, verification, shen, eval, skel]
status: complete
last_updated: 2026-03-29
last_updated_by: Claude
---

# Research: Self-Compiling Specs Across Language Paradigms

**Date**: 2026-03-29T15:45:29Z
**Git Commit**: de89822
**Branch**: main

## Research Question

How does the core Autopoiesis pattern — declarative specs that compile themselves into executable verification code — translate across different programming language paradigms? The approach must look fundamentally different for compiled vs interpreted languages, static vs dynamic type systems, and homoiconic vs non-homoiconic syntax. What does Autopoiesis already do at its language boundaries, and what can we learn from how other languages solve this?

## Summary

Autopoiesis implements **four distinct spec-to-code pipelines** internally, all sharing the pattern: declarative data stored as S-expressions → lazy compilation on first use → executable verification. At its language boundaries (Go SDK, TypeScript frontend, Rust TUI), the system already confronts the "same concept, different language" problem — and the sharpest information loss is always the same: arbitrary S-expressions arrive as opaque strings in every foreign language.

Across the broader language ecosystem, three fundamental patterns emerge for self-compiling specs:

| Pattern | When checks happen | Examples |
|---------|-------------------|----------|
| **Compile-time expansion** | Compilation | Rust proc macros, CL macros, TypeScript type inference from Zod |
| **External code generation** | Build step + compile | protobuf codegen, OpenAPI generator, `go:generate` |
| **Runtime interpretation** | Execution | Pydantic validators, JSON Schema/Ajv, CL `satisfies` predicates |

Common Lisp is unique in supporting all three within a single syntactic framework. This is what makes it the natural home for Autopoiesis — but the architecture could be ported, with each target language using its strongest native pattern.

## Detailed Findings

### What Autopoiesis Already Does: Four Internal Pipelines

#### Pipeline 1: Shen Prolog Rules (S-expression → Prolog predicate)

**Files**: `packages/shen/src/rules.lisp`, `packages/shen/src/bridge.lisp`

Rules are stored as raw S-expressions in `*rule-store*` (keyword → clause list). On first query, `compile-rule-into-shen` transforms the AP clause format into Shen's internal `(HEAD - BODY)` triple representation via `clauses-to-shen-internal`, then passes it to `shen.s-prolog` for Prolog assertion.

The key design: rules exist simultaneously as CL data (inspectable, serializable, survives forking) and as compiled Shen Prolog predicates (queryable). The data form is the canonical representation; the compiled form is derived on demand.

#### Pipeline 2: Eval Verifiers (keyword spec → executable check)

**File**: `packages/eval/src/verifiers.lisp`

Seven built-in verifier keywords (`:exit-zero`, `:contains`, `:regex`, `:file-exists`, etc.) are registered as lambda functions at load time. `run-verifier` is a polymorphic dispatcher accepting four designator forms: keyword, plist-with-`:type`, function object, or named symbol.

This is the simplest self-compiling spec: a keyword IS the spec, and the registry IS the compiler. The "compilation" is just a hash table lookup.

#### Pipeline 3: CL Fallback Verification (Prolog clauses → CL check specs)

**File**: `packages/shen/src/verifier.lisp`

`clauses-to-cl-check` pattern-matches Prolog clause S-expressions to extract CL-executable check specs. It recognizes `(has-file Tree "path")` → `:files-exist` and `(output-contains "substr")` → `:output-contains`, with an `:all` combinator for composition.

**This is the most instructive pipeline for the cross-language question.** It demonstrates taking a spec written in one paradigm (Prolog logic) and re-interpreting it in another (imperative CL checks). The same rule can execute as a Prolog query (when Shen is loaded) or as a sequence of CL function calls (when it isn't). The spec is the same; the execution strategy adapts to the available runtime.

#### Pipeline 4: SKEL/BAML (schema → LLM prompt + output parser)

**Files**: `packages/core/src/skel/core.lisp`, `packages/core/src/skel/types.lisp`, `packages/core/src/skel/class.lisp`

`define-skel-class` macro expands into both a real CLOS class AND a `skel-class-metadata` object with `check` and `assert-constraint` closures per slot. `skel-class-to-json-schema` generates JSON Schema from the same metadata, which is appended to LLM prompts. The same spec drives: what the LLM is asked to produce, how the output is parsed, and what constraints are validated.

#### Pipeline 5: Extension Compiler (S-expression → sandboxed executable)

**File**: `packages/core/src/core/extension-compiler.lisp`

Agent-written S-expression code is validated by a recursive AST walker (`validate-extension-source`) against whitelisted symbols, then compiled via CL's `(compile nil (lambda () ,source))`. The spec here is the whitelist itself — a declarative list of allowed operations that the compiler enforces.

### What Happens at Language Boundaries

Autopoiesis already crosses five language boundaries. Each reveals what the target language can and cannot capture:

| Boundary | What crosses | What's lost |
|----------|-------------|-------------|
| CL → TypeScript (frontend) | Agent state, thoughts, eval data as JSON | S-expressions become opaque `prin1` strings; agent state enum collapsed to `string`; thought subclass hierarchy flattened to optional fields |
| CL → Go SDK | Agent CRUD, snapshots, events as JSON | `Snapshot.Metadata` becomes `interface{}`; diff tree is pre-stringified; plist/object ambiguity requires custom `UnmarshalJSON` |
| CL → Rust TUI | Agent state, thoughts via WebSocket | **Least loss**: Rust `serde` enums capture `AgentState::Running` etc.; `Uuid` type for IDs; but thought content is still `String` |
| CL → Claude API | Tool schemas, message content | CL type specs → JSON Schema type strings via `lisp-type-to-json-type`; `(or ...)` union types collapse to first member |
| CL → subprocess CLI | Prompts in, JSON/JSONL out | Full round-trip: CL prompt string → subprocess stdin → stdout JSON → CL parser. `cl-json`'s `camel-case-to-lisp` produces double-dash artifacts (`tool--name`) |

**The consistent finding**: arbitrary S-expressions serialized via `prin1-to-string` arrive as opaque strings in every foreign language. Only the CL process can re-parse them. The Rust boundary is the most faithful for enums. The Go TUI is the only consumer that explicitly handles plist-vs-JSON-object ambiguity.

### How Each Language Would Implement Self-Compiling Specs

#### Rust: Proc Macros (compile-time AST transformation)

The spec is an attribute annotation on a struct. A procedural macro (`TokenStream → TokenStream`) runs inside the compiler, receives the struct definition as an AST, and emits a trait implementation.

```rust
#[derive(Validate)]
struct Config {
    #[garde(length(min=1, max=100))]
    name: String,
    #[garde(range(min=0, max=150))]
    age: u32,
}
```

The macro generates a `Validate` trait impl with per-field runtime checks. The **compile-time guarantee** is structural: if a field type doesn't satisfy the validation rule's type bound, the generated impl won't compile. The **runtime check** is the `.validate()` call.

For Autopoiesis in Rust: rules-as-data would use `serde`-derived structs. The equivalent of `clauses-to-shen-internal` would be a proc macro that generates pattern-matching code from a declarative rule DSL. Agent state serialization would be derive-based, not homoiconic — you'd `#[derive(Serialize, Deserialize)]` instead of `persistent-agent-to-sexpr`.

#### Go: `go:generate` + Code Generation (external build step)

Go has no macros. Specs are external files (`.proto`, `.json`, `.yaml`) processed by a code generator that emits `.go` source files before compilation.

```proto
message Agent {
  string id = 1;
  string name = 2;
  repeated string capabilities = 3;
}
```

`protoc --go_out=.` generates Go structs with `protobuf` struct tags. Validation via `protovalidate` uses CEL expressions evaluated by an embedded interpreter at runtime.

For Autopoiesis in Go: the eval verifier registry would be a `map[string]func(...)`. Rules-as-data would be JSON or YAML parsed at startup. The "self-compiling" aspect would be a build step that reads rule files and generates Go validation functions — or an embedded interpreter (like CEL) for runtime evaluation.

#### Python: Metaclass Magic (import-time code generation)

Python's class creation machinery (`__init_subclass__`, metaclasses) runs at import time, transforming type annotations into validators.

```python
class Agent(BaseModel):
    name: Annotated[str, Field(min_length=1)]
    capabilities: list[str]
    state: Literal["running", "paused", "stopped"]
```

Pydantic's metaclass generates `__init__` validation, JSON Schema export (`model_json_schema()`), and serialization — all from the same annotations. With the mypy plugin, the annotations also provide static type checking.

For Autopoiesis in Python: rules would be dictionaries or dataclasses. The `clauses-to-cl-check` pattern would be a function that reads rule dicts and returns callable validators. The extension compiler would use `ast.parse` + `ast.NodeVisitor` for whitelist enforcement, then `compile()` + `exec()`. Homoiconicity isn't available, but Python's `ast` module provides a structural equivalent.

#### TypeScript: Schema Libraries (runtime objects with type inference)

TypeScript's type system is erased at runtime, so schemas must be maintained as runtime objects. Zod and io-ts keep the schema alive and derive static types from it.

```typescript
const AgentSchema = z.object({
  name: z.string().min(1),
  capabilities: z.array(z.string()),
  state: z.enum(["running", "paused", "stopped"]),
});
type Agent = z.infer<typeof AgentSchema>;
```

The schema IS the validator. `z.infer<>` extracts a static TypeScript type via conditional types. No code generation, no build step — the schema object is both the spec and the runtime check.

For Autopoiesis in TypeScript: this is essentially what the frontend already does with its type definitions in `api/types.ts`, except without runtime validation. Adding Zod schemas would close the gap — the same schema would drive TypeScript type checking AND runtime API response validation.

#### C: Minimal — External Tools Only

C has no type-level spec mechanism beyond struct layout. `protobuf-c` generates structs from `.proto` files, but there's no way to encode constraints (ranges, patterns, invariants) that the compiler can check. All validation is hand-written or generated as explicit runtime `if` checks.

For Autopoiesis in C: rules would be C structs or arrays of function pointers. The extension compiler would be a separate validator program. Homoiconicity is not available; the closest equivalent is a custom bytecode interpreter.

### The Three Fundamental Patterns

| Pattern | Mechanism | When | Trade-off |
|---------|-----------|------|-----------|
| **A: Interpretation** | Spec kept as runtime data, validator engine interprets it | Runtime | Flexible (spec changes without recompile) but slower |
| **B: Code generation** | External tool reads spec, emits target language source | Build step | Zero runtime dependency on spec toolchain but requires rebuild |
| **C: Compile-time expansion** | Spec embedded in source, compiler/macro expands it | Compilation | Tightest integration but couples spec to host language |

**What Autopoiesis does**: Primarily Pattern A (rules in `*rule-store*`, verifiers in `*verifier-registry*`, SKEL schemas in `*skel-types*`) with Pattern C for the extension compiler (`compile nil`) and SKEL class macros (`define-skel-class`).

**The key insight the user identified**: "the fact that we're able to take a spec that compiles itself and turn that into code checks in the implementation language is really the key idea, even though that looks quite different for different target languages."

This is exactly what `clauses-to-cl-check` demonstrates: a Prolog spec (Pattern A data) is pattern-matched into CL check functions (Pattern C executable). The same transformation in Go would produce Go functions. In Rust, proc macro output. In Python, Pydantic validators. In TypeScript, Zod schemas. The spec stays the same; the "compiler" adapts to the target.

## Architecture Documentation

### How This Influences What's Built

The codebase reflects several conscious design decisions that follow from the cross-language question:

1. **Dynamic resolution everywhere**: The API server, eval verifiers, and Shen bridge all use `find-package`/`find-symbol`/`fboundp` guards rather than compile-time package dependencies. This is the CL equivalent of "late binding" — it allows the system to gracefully degrade when optional subsystems aren't loaded.

2. **JSON as the universal interchange**: Every language boundary uses JSON (with MessagePack as a binary optimization for high-frequency streams). The serialization layer (`serialization.lisp`, `serializers.lisp`) explicitly handles the CL→JSON transformation, accepting information loss (S-expressions → strings) as the cost of polyglot compatibility.

3. **The SKEL system bridges the gap**: `skel-class-to-json-schema` generates JSON Schema from CL type metadata. This is the closest thing to "cross-language spec compilation" in the codebase — a CL spec produces a JSON Schema that could, in principle, drive validators in any language.

4. **Dual-representation as a pattern**: Rules exist as both data (S-expressions) and compiled form (Shen predicates). Agents exist as both structs (in-memory) and S-expressions (`persistent-agent-to-sexpr`). This duality is what enables the "same spec, different execution strategy" pattern.

## Code References

- `packages/shen/src/rules.lisp:89-136` — `clauses-to-shen-internal` + `split-clause-for-shen` (data → Prolog)
- `packages/shen/src/verifier.lisp:121-177` — `clauses-to-cl-check` + `cl-check-verify` (Prolog → CL checks)
- `packages/eval/src/verifiers.lisp:24-73` — `run-verifier` polymorphic dispatch
- `packages/core/src/skel/class.lisp:179-213` — `define-skel-class` macro (spec → CLOS + metadata)
- `packages/core/src/skel/class.lisp:574-595` — `skel-class-to-json-schema` (CL spec → JSON Schema)
- `packages/core/src/core/extension-compiler.lisp:232-383` — `validate-extension-source` (S-expression walker)
- `packages/core/src/agent/persistent-agent.lisp:63-102` — `persistent-agent-to-sexpr` / `sexpr-to-persistent-agent`
- `packages/api-server/src/serializers.lisp` — CL→JSON serialization (what's lost at the boundary)
- `frontends/command-center/src/api/types.ts` — TypeScript domain model (what TS captures)
- `nexus/crates/nexus-protocol/src/types.rs` — Rust domain model (most faithful enum typing)
- `sdk/go/apclient/types.go` — Go domain model (`interface{}` for untyped fields)
- `tui/internal/ws/plist.go` — Go plist bridge (handling CL serialization artifacts)
- `packages/core/src/integration/tool-mapping.lisp:12-50` — CL type → JSON Schema type mapping

## Open Questions

1. Could the SKEL JSON Schema output be used to generate Zod validators for the TypeScript frontend, closing the "runtime validation" gap?
2. Could `clauses-to-cl-check` be generalized to `clauses-to-<language>-check` — producing Go functions, Python validators, or TypeScript Zod schemas from the same Prolog clause data?
3. The `define-cli-provider` macro already generates CLOS classes from declarative specs. Could a similar macro generate Go or Rust provider clients from the same spec?
