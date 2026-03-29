# Specs That Compile Themselves: How One Idea Looks Different in Every Language

*Part 6 of a series on the Autopoiesis agent platform*

---

Imagine you write a rule: "A project is quality-checked if it has a README, a src/ directory, and its test suite passes." That is a specification. It describes what should be true. It says nothing about how to check it.

Now imagine that one rule can automatically become:

- A Prolog query that verifies it through logical resolution
- A Common Lisp function that checks the filesystem and exit codes
- A JSON Schema that validates API responses against the structure
- A Rust struct with compile-time type guarantees and derived validation
- A Python Pydantic model with runtime constraint checking
- A TypeScript Zod schema that is simultaneously a type and a validator

The rule does not change. The *compiler* changes. Each language has its own way of turning declarative intent into executable checks, and the differences reveal something fundamental about language design. This is the idea behind self-compiling specifications, and after building a system that actually does this across multiple language boundaries, I want to share what I have learned about where the pattern works, where it breaks, and what gets lost in translation.

If you have been following this series, you saw in [Part 4](part-4.md) how the eval lab tests agent behavior with deterministic verifiers, and in [Part 5](part-5.md) how Prolog rules can encode quality constraints that execute as logical queries. This post is about what happens when those specs need to cross language boundaries -- when the same concept must exist in Common Lisp, Rust, TypeScript, Python, and Go simultaneously.

---

## The Three Patterns

Before looking at concrete code, it helps to know there are really only three ways a spec can become executable. Every language uses some combination of these, but each language has a strong preference.

**1. Compile-time expansion.** The spec is embedded in source code. The compiler or macro system transforms it into verification logic during compilation. Examples: Rust proc macros, Common Lisp macros, C++ template metaprogramming.

The advantage is that errors are caught before anything runs. The IDE understands the generated types. The disadvantage is tight coupling -- the spec is expressed in the host language's syntax and can only target that language.

**2. External code generation.** A separate tool reads a spec file (protobuf, OpenAPI, JSON Schema) and emits source code for one or more target languages. Examples: `protoc`, `openapi-generator`, `go:generate`.

The advantage is that one spec produces code for many languages. The generated code is ordinary source that compilers and linters understand. The disadvantage is build step complexity -- you have to regenerate when the spec changes, and the generator is a separate tool to maintain.

**3. Runtime interpretation.** The spec is kept as data at runtime. A validator engine interprets it when needed. Examples: Pydantic, Zod, JSON Schema validators like Ajv, and Common Lisp's `satisfies` type predicates.

The advantage is maximum flexibility -- the spec can change without recompilation. The disadvantage is that violations are only caught when code actually runs. No compile-time safety net.

Most real systems mix these. Rust's `serde` uses compile-time expansion for serialization but runtime interpretation for validation. TypeScript's Zod provides runtime validation but uses conditional types to infer compile-time types from the runtime schema. Autopoiesis uses all three: macros for SKEL class definitions, runtime registries for eval verifiers, and a cross-paradigm compiler that turns Prolog clauses into Common Lisp checks.

---

## One Rule, Five Languages

Let me make this concrete. Here is a quality check rule: a project is valid if it contains `README.md`, has a `src/` directory, and its build output contains the string "0 errors." The rule is simple enough to fit in every language, but complex enough to show real differences.

### Common Lisp (Autopoiesis)

In Autopoiesis, this rule starts life as Prolog clauses stored as S-expressions:

```lisp
;; The rule, stored as data in *rule-store*
((quality-checked Project)
  <-- (has-file Tree "README.md")
      (has-file Tree "src/")
      (output-contains "0 errors"))
```

When Shen Prolog is loaded, this compiles into a Prolog predicate and executes via logical resolution. But here is what makes it interesting: when Shen is *not* loaded, the system does not give up. The function `clauses-to-cl-check` pattern-matches the clause S-expressions and extracts an equivalent CL check specification:

```lisp
(defun clauses-to-cl-check (clauses)
  "Try to convert Prolog clauses to a CL check spec.
   Recognizes patterns like (has-file Tree \"path\") -> (:files-exist ...)."
  (let ((file-paths nil)
        (output-substrings nil))
    (dolist (clause clauses)
      (when (listp clause)
        (let ((body (rest (member '<-- clause))))
          (dolist (term body)
            (when (listp term)
              (cond
                ((and (eq (first term) 'has-file)
                      (stringp (third term)))
                 (push (third term) file-paths))
                ((and (eq (first term) 'output-contains)
                      (stringp (second term)))
                 (push (second term) output-substrings))))))))
    (cond
      ((and file-paths output-substrings)
       `(:all (:files-exist ,(nreverse file-paths))
              ,@(mapcar (lambda (s) `(:output-contains ,s))
                        (nreverse output-substrings))))
      (file-paths
       `(:files-exist ,(nreverse file-paths)))
      ;; ...
      (t nil))))
```

This produces the check spec `(:all (:files-exist ("README.md" "src/")) (:output-contains "0 errors"))`, which `cl-check-verify` then executes as imperative CL code -- walking the filesystem tree and searching strings. Same rule, two execution strategies, chosen at runtime based on what subsystems are available.

The check runs: at verification time, after an eval trial completes. A violation produces `:fail` with the specific check that failed.

### Rust

Rust reaches for compile-time expansion. The rule becomes struct annotations that a proc macro transforms into a `Validate` trait implementation:

```rust
use garde::Validate;
use std::path::PathBuf;

#[derive(Validate)]
struct ProjectQuality {
    #[garde(custom(file_exists))]
    readme: PathBuf,

    #[garde(custom(dir_exists))]
    src_dir: PathBuf,

    #[garde(contains("0 errors"))]
    build_output: String,
}

fn file_exists(path: &PathBuf, _ctx: &()) -> garde::Result {
    if path.exists() && path.is_file() { Ok(()) }
    else { Err(garde::Error::new("file not found")) }
}
```

The `#[derive(Validate)]` macro generates the validation code at compile time. The struct definition is the spec. If you misspell a field or use the wrong type, the compiler catches it. If you forget to call `.validate()`, the constraint is not checked -- but the structural shape is always enforced by the type system.

The check runs: when you call `.validate()` at runtime. Type mismatches are caught at compile time. The developer sees a compiler error for structural issues, a `garde::Result` error for constraint violations.

### Python

Python uses runtime interpretation. The spec becomes a Pydantic model with annotated fields:

```python
from pydantic import BaseModel, field_validator
from pathlib import Path

class ProjectQuality(BaseModel):
    readme: Path
    src_dir: Path
    build_output: str

    @field_validator("readme")
    @classmethod
    def readme_exists(cls, v):
        if not v.exists() or not v.is_file():
            raise ValueError("README.md not found")
        return v

    @field_validator("src_dir")
    @classmethod
    def src_exists(cls, v):
        if not v.exists() or not v.is_dir():
            raise ValueError("src/ directory not found")
        return v

    @field_validator("build_output")
    @classmethod
    def output_clean(cls, v):
        if "0 errors" not in v:
            raise ValueError("build output does not contain '0 errors'")
        return v
```

Pydantic's metaclass magic generates `__init__` validation from these annotations and validators at class definition time (import time, essentially). The same class can also export itself as JSON Schema via `ProjectQuality.model_json_schema()` -- bridging runtime interpretation to external code generation.

The check runs: when you instantiate the model. The developer sees a `ValidationError` with a structured list of what went wrong and where.

### TypeScript

TypeScript's type system is erased at runtime, so you need a library like Zod to keep the spec alive as a runtime object:

```typescript
import { z } from "zod";

const ProjectQuality = z.object({
  readme: z.string().refine(
    (p) => fs.existsSync(p) && fs.statSync(p).isFile(),
    { message: "README.md not found" }
  ),
  srcDir: z.string().refine(
    (p) => fs.existsSync(p) && fs.statSync(p).isDirectory(),
    { message: "src/ directory not found" }
  ),
  buildOutput: z.string().includes("0 errors"),
});

// The type is inferred from the schema -- no separate definition needed
type ProjectQuality = z.infer<typeof ProjectQuality>;
```

The schema object serves double duty. `z.infer<>` uses TypeScript's conditional types to extract a static type, so the compiler knows the shape. The `.parse()` method validates data at runtime. One object, two roles. No code generation step, no separate type definition that can drift out of sync.

The check runs: when you call `.parse()` or `.safeParse()`. Type mismatches are caught by `tsc`. Constraint violations produce a `ZodError` at runtime.

### Go

Go has no macros and no metaclass hooks. The dominant pattern is external code generation. For a protobuf-based approach with `protovalidate`:

```proto
syntax = "proto3";
import "buf/validate/validate.proto";

message ProjectQuality {
  string readme_path = 1 [(buf.validate.field).string.min_len = 1];
  string src_dir_path = 2 [(buf.validate.field).string.min_len = 1];
  string build_output = 3 [(buf.validate.field).string.contains = "0 errors"];
}
```

`protoc` generates a Go struct. The `protovalidate` library evaluates the constraint annotations at runtime using an embedded CEL interpreter. For the filesystem checks, you would add a custom validation function -- protobuf constraints do not know about filesystems.

Alternatively, many Go projects skip the code generation and write structs with validation tags:

```go
type ProjectQuality struct {
    ReadmePath  string `validate:"required,file"`
    SrcDirPath  string `validate:"required,dir"`
    BuildOutput string `validate:"required,contains=0 errors"`
}
```

The check runs: when you call `validator.Struct(&pq)`. There is no compile-time constraint checking beyond basic types. The developer sees a `validator.ValidationErrors` slice.

### The pattern across languages

| Language | Pattern | Check time | Error visibility |
|----------|---------|------------|------------------|
| Common Lisp | Runtime interpretation (with macro option) | Verification time | `:pass` / `:fail` keyword |
| Rust | Compile-time expansion + runtime validate | Compile + runtime | Compiler error + `Result` |
| Python | Import-time metaclass + runtime | Instantiation time | `ValidationError` |
| TypeScript | Runtime object + type inference | Parse time + compile | `ZodError` + `tsc` error |
| Go | External codegen + runtime | Build step + runtime | `ValidationErrors` slice |

---

## What Gets Lost at the Boundaries

Theory is clean. Reality is not. When Autopoiesis sends agent state from Common Lisp to the TypeScript frontend or the Rust TUI, something is always lost in translation. The boundaries are where the idea of self-compiling specs gets its hardest test.

Consider agent state. In Common Lisp, an agent's state is one of the keywords `:initialized`, `:running`, `:paused`, `:stopped`. In the Rust domain types, this becomes a proper enum with exhaustive matching:

```rust
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentState {
    #[default]
    Initialized,
    Running,
    Paused,
    Stopped,
}
```

Rust captures the full constraint: there are exactly four states, the compiler forces you to handle all of them, and the default is `Initialized`. In the TypeScript frontend, the same concept becomes:

```typescript
export interface Agent {
  id: string;
  name: string;
  state: string;  // <-- just a string
  capabilities: string[];
  // ...
}
```

That `state: string` is a quiet loss. TypeScript *could* express `state: "initialized" | "running" | "paused" | "stopped"` as a union type, but the Autopoiesis frontend uses plain `string`. Any typo compiles. Any nonsense value passes the type checker. The spec that existed as a keyword enumeration in CL, and as an exhaustive enum in Rust, has dissolved into an unchecked string.

Thought content is worse. In CL, an observation thought's content is a structured S-expression -- a plist like `(:input "analyze auth module")` that code can destructure and pattern-match. When this crosses the JSON serialization boundary, it becomes an opaque `prin1-to-string` output:

```
"(:INPUT \"analyze auth module\")"
```

In TypeScript, that is `content: string`. In Rust, `pub content: String`. In Go, `Content string`. Every foreign language receives the same opaque blob. Only the CL process can re-parse it back into structured data. The thought's internal structure -- the fact that it *has* an `:input` key, that the value is a string -- is invisible to every consumer.

The SKEL system offers a partial bridge. `skel-class-to-json-schema` generates JSON Schema from CL type metadata, which means a SKEL-defined type can, in principle, have its constraints validated in any language that has a JSON Schema library. The CL type spec `(:string :min-length 1)` becomes `{"type": "string", "minLength": 1}` in JSON Schema, which Zod, Pydantic, or Go's `jsonschema` library can all enforce. This is the closest thing to true cross-language spec compilation in the codebase.

The lesson is consistent: **the richer the target language's type system, the more information survives the boundary crossing.** Rust captures the most -- enums, option types, UUID-typed IDs. TypeScript captures structure but not runtime constraints unless you add Zod. Go captures basic structure but resorts to `interface{}` for anything it cannot type statically.

---

## The Homoiconic Advantage

There is a reason Autopoiesis is built in Common Lisp, and it is not nostalgia. It is that CL is the only mainstream language where the spec, the compiler, and the output are all the same data structure.

Consider what `clauses-to-cl-check` actually does. It receives a list of S-expressions representing Prolog clauses. It walks them as data -- checking `(first term)`, testing `(stringp (third term))`. It produces a new S-expression representing a check spec. That spec is then interpreted by `cl-check-verify`, which dispatches on keywords (`:files-exist`, `:output-contains`, `:all`) to run the actual checks.

At no point does the system need a parser, an AST library, or a code generation template. The Prolog clause `(has-file Tree "README.md")` is already a list. The check spec `(:files-exist ("README.md"))` is already a list. The code that transforms one into the other uses the same `car`/`cdr`/`cond` operations you would use to process any list. The spec is data. The compiler is a function over data. The output is data that happens to be executable.

The eval verifier registry shows the same pattern from the other direction. A verifier is registered as a keyword mapped to a lambda:

```lisp
(register-verifier :contains
  (lambda (output &key expected &allow-other-keys)
    (if (and output expected (search expected output))
        :pass :fail)))
```

The keyword `:contains` is both the spec (declaring what kind of verification this is) and the dispatch key (selecting the implementation at runtime). There is no separate "verifier definition language." The language *is* the definition language.

This extends to the extension compiler, where agent-written S-expression code is validated by walking it as a data structure against a whitelist of allowed symbols, then compiled into a function using CL's built-in `compile`. The whitelist is the spec. The walker is the compiler. The output is native machine code. Same syntax all the way down.

Now the honest trade-off: this power comes at a real cost. CL's tooling ecosystem is smaller than TypeScript's or Python's. IDE support, while excellent in Emacs with SLIME/SLY, does not match what VS Code provides for TypeScript out of the box. The talent pool is smaller. The library ecosystem, while deep, is narrower. Every language makes trade-offs, and CL trades ecosystem size for expressive power. Whether that trade-off is right depends on what you are building. For a system where specs need to transform themselves into executable code across paradigm boundaries, it turned out to be the right call.

---

## The Spec is the Source of Truth

The real insight from building all of this is not about any particular language. It is that **the spec should be the canonical artifact, and everything else should be derived from it.**

Whether that derivation happens via:

- CL macros at read/compile/load time
- Rust proc macros at compile time
- Python metaclasses at import time
- TypeScript conditional types inferred from runtime schemas
- Go code generators at build time
- Or a cross-paradigm compiler like `clauses-to-cl-check` that translates between execution models

...the pattern is the same. Write the rule once. Let the toolchain compile it into whatever your target language needs.

In Autopoiesis, this manifests as Prolog rules that become CL check functions, SKEL schemas that become both CLOS classes and JSON Schema, eval verifier keywords that become lambda functions, and extension compiler whitelists that become AST validators. The Common Lisp implementation is one expression of the idea -- one where the boundaries between spec, compiler, and output happen to be especially thin.

But you can apply the same thinking in any language. If you are building an agent platform in Python, put your specs in Pydantic models and generate JSON Schema from them. In Rust, use derive macros to generate validation from struct annotations. In TypeScript, use Zod schemas as the single source of truth for both types and runtime checks. In Go, use protobuf definitions and generate both server stubs and validation code.

The specific tool does not matter. What matters is the discipline: one spec, derived everything. When the spec changes, the checks change. When the checks change, nothing else needs to. That is what self-compiling specifications look like in practice, regardless of the language you write them in.

---

*This post is part of a series on the Autopoiesis agent platform.*
- [Part 1: Code That Rewrites Itself](part-1.md)
- [Part 2: Multi-Agent Orchestration](part-2.md)
- [Part 3: Git for Agent State](part-3.md)
- [Part 4: The Eval Lab](part-4.md)
- [Part 4b: Under the Hood -- Shen Prolog](part-4b.md)
- [Part 5: Logic Meets Learning](part-5.md)
- **Part 6: Specs That Compile Themselves** (you are here)

[GitHub Repository](https://github.com/pyrex41/autopoiesis)
