# Logic Meets Learning: Prolog-Powered Agent Reasoning

*Part 5 of the Autopoiesis Series*

LLMs are powerful pattern matchers. They've read the entire internet and can synthesize it into remarkably coherent responses. They're also confident liars. Ask an LLM whether a deployment is safe and it will give you a plausible-sounding answer every single time, even when the answer is wrong, even when the consequences of being wrong are severe.

Logic programs are the opposite. Prolog doesn't guess. It doesn't pattern-match from training data. It derives what the rules allow, and *nothing else*. If you haven't defined a rule that lets it conclude "this deployment is safe," it won't. There's no hallucination in logic programming -- just sound or unsound inference.

What if you could have both? An agent that uses an LLM for creative reasoning -- generating hypotheses, synthesizing information, writing code -- but falls back to formal logic for verification and safety constraints. The LLM proposes; logic disposes.

The Shen Prolog extension explores this idea. Rules are defined as S-expression data that survive forking, time-travel, and serialization. The platform provides a reasoning mixin that augments (not replaces) an agent's existing intelligence. And because rules are data -- not interpreter state -- they participate in everything the platform already does: structural sharing, snapshots, evolution.

A transparency note: the primary working path today is rules-as-data with CL fallback verification. The Shen bridge loads successfully and basic evaluation works, but Prolog query execution via `eval-kl` does not work because `defprolog` is a Shen macro that cannot be processed at the KLambda level. The CL fallback verifier handles the practical verification use cases -- file existence checks, output matching, compositional combinators -- without needing Prolog execution at all. Full Prolog query support is aspirational, pending resolution of the macro expansion gap in `shen-cl`.

## A 60-Second Prolog Primer

If you've never seen Prolog, here's the core idea. You define **facts** and **rules**, then ask **queries**.

A fact is a simple assertion: "Alice is Bob's parent." A rule derives new facts from existing ones: "X is Y's ancestor if X is Y's parent, or X is the parent of someone who is Y's ancestor." A query asks: "Is Alice an ancestor of Charlie?"

The runtime works backward from the query, trying to prove it by chaining rules together. If it finds a chain of facts and rules that proves the query, it succeeds. If it exhausts all possibilities without proving it, it fails. There's no "maybe," no confidence score -- just proved or not proved.

This makes Prolog perfect for verification. You define what "correct" means as rules, and then you ask whether a given situation satisfies those rules. The answer is deterministic and auditable.

## Rules as Data

In traditional Prolog, rules live in the interpreter's global state. You `assert` them and they exist until you `retract` them. This is fine for a standalone Prolog program, but it's terrible for an agent platform where you need rules to survive serialization, participate in forking, and travel through time with the rest of the agent's state.

Autopoiesis stores rules as S-expressions -- data that maps to Prolog predicates but lives in the platform's persistent data structures.

```lisp
(define-rule :member
  '((mem X [X | _] <--)
    (mem X [_ | Y] <-- (mem X Y))))
```

The `define-rule` function takes a keyword name and a list of clause S-expressions. The `<--` arrow separates the head (what the rule concludes) from the body (what it requires). This is standard Prolog notation, just written as S-expressions.

These clauses are stored as S-expression data in `*rule-store*`. The platform also attempts to compile them into Shen Prolog's `defprolog` form, though as discussed in Part 4b, this compilation does not currently succeed via `eval-kl`. The source of truth is always the S-expression data, not the compiled state -- and this turns out to be the more important half of the design.

Here is verified output showing rules defined, serialized, and round-tripped:

```
Rules defined: (QUALITY-CHECK DEPLOY-SAFE CODE-REVIEW)

Serialized: ((:QUALITY-CHECK (QUALITY-CHECK TREE) <--
              (HAS-FILE TREE "README.md") (HAS-FILE TREE "src/")
              (HAS-FILE TREE "tests/"))
             (:DEPLOY-SAFE (DEPLOY-SAFE MODULE) <-- (TESTED MODULE)
              (ALL-DEPS-TESTED MODULE))
             (:CODE-REVIEW (CODE-REVIEW FILE) <-- (HAS-TESTS FILE)
              (NO-LINT-ERRORS FILE) (DOCUMENTED FILE)))
After clear: 0 rules
After restore: 3 rules
```

Why does this matter? Three reasons:

**Forking.** When you fork an agent (O(1) via structural sharing -- see Part 3), the forked agent gets its own copy of the knowledge base. Rules are stored in the agent's metadata pmap, so forking is just a pointer copy. The child can add rules without affecting the parent.

**Serialization.** `rules-to-sexpr` dumps the entire rule store to a list of `(name . clauses)` pairs. `sexpr-to-rules` loads them back. No special serialization logic, no binary formats -- just S-expressions all the way down. Rules round-trip through snapshots, backups, and network transfer.

**Evolution.** In the swarm layer (covered in the architecture docs), agents undergo crossover and mutation. Because rules are data in persistent maps, the evolutionary operators can recombine rule sets from different agents without any special-case code. An agent that evolved a good set of safety rules can pass them to its descendants.

## The Reasoning Mixin

The integration point is a CLOS mixin class. If you want an agent with Prolog reasoning, you mix it in:

```lisp
(defclass prolog-agent (agent shen-reasoning-mixin) ())
```

That's it. The mixin adds a `knowledge-base` slot (a list of `(rule-name . clauses)` pairs) and specializes the `reason` generic function with an `:around` method.

Here is what happens during the cognitive cycle. When the platform calls `reason` on an agent that has the mixin, the `:around` method fires first. It loads the agent's knowledge base (`load-agent-knowledge`), queries each rule against the current observations, collects any derived facts, and appends them to the observations before calling the next method. The LLM-based reasoning then runs with *augmented* input -- it sees both the raw observations and whatever the rules derived from them.

```lisp
;; The :around method (simplified from source)
(defmethod reason :around ((agent shen-reasoning-mixin) observations)
  (let* ((prolog-results (reason-with-prolog agent observations))
         (augmented (if prolog-results
                        (append observations
                                (list :prolog-derived prolog-results))
                        observations)))
    (call-next-method agent augmented)))
```

This is augmentation, not replacement. If Shen isn't loaded or if Prolog queries are not functional (as is currently the case -- see Part 4b), the mixin is inert -- `reason-with-prolog` returns nil and the original observations pass through unchanged. The agent never breaks because of the logic layer; it only gets smarter when the rules have something to say. The current practical path for rule-based verification is through the CL fallback in the eval verifiers, rather than through the reasoning mixin's Prolog queries.

Knowledge base management is straightforward:

```lisp
(let ((agent (make-instance 'prolog-agent :name "safety-checker")))
  ;; Add rules
  (add-knowledge agent :ancestor
    '((ancestor X Y) <-- (parent X Y))
    '((ancestor X Y) <-- (parent X Z) (ancestor Z Y)))

  ;; Rules persist with the agent
  (remove-knowledge agent :ancestor)
  (clear-knowledge agent))
```

Thread safety comes from `*shen-lock*` -- a global lock that serializes all Shen calls. Shen uses mutable global state internally, so this is non-negotiable. The lock is acquired in `load-agent-knowledge` before clearing and reloading rules, ensuring no cross-agent contamination even when multiple agents reason concurrently.

## Practical Example: Deployment Safety

Suppose you want hard constraints on deployment safety that cannot be hallucinated away. Rules-as-data lets you express these constraints declaratively:

```lisp
;; Rule: a module is deploy-safe if it's tested and all deps are tested
(define-rule :deploy-safe
  '((deploy-safe Module) <-- (tested Module) (all-deps-tested Module)))

;; Rule: code quality requires specific files
(define-rule :quality-check
  '((quality-check Tree) <--
    (has-file Tree "README.md")
    (has-file Tree "tests/")
    (has-file Tree "src/")))
```

The CL fallback verifier can inspect these rule clauses and run them as native checks. Here is verified output showing this in action:

```
:files-exist [README.md, src/main.py] with matching tree: PASS
:files-exist [README.md, MISSING.txt] with partial tree: FAIL
:output-contains 'All tests passed': PASS
:all combinator (files + output): PASS
```

The `:quality-check` rule contains `(has-file Tree "README.md")` predicates. The CL fallback recognizes these patterns and converts them to `:files-exist` checks that run against the actual project tree. If the tree doesn't have a `tests/` directory, the check fails deterministically. No amount of prompt engineering will make the verifier approve a deployment that's missing its test directory. The rules are the rules.

The key insight: while full Prolog query execution is not yet working (see Part 4b), the CL fallback path provides the same deterministic verification for the predicates that matter most -- file existence, output matching, and compositional combinators. The rule S-expressions serve as both documentation of the constraints and executable specifications via the fallback path.

For persistent agents, the knowledge base travels with the agent state. `save-knowledge-to-pmap` serializes the knowledge base into the agent's metadata pmap. `load-knowledge-from-pmap` restores it. When you fork an agent or restore from a snapshot, the rules come along automatically:

```lisp
;; Save knowledge to persistent storage
(save-knowledge-to-pmap agent)  ; returns updated metadata pmap

;; Later, restore from a pmap
(load-knowledge-from-pmap agent restored-pmap)
```

## Compositional Verification

The Shen package adds two verifier types to the Eval Lab (covered in Part 4): `:prolog-query` and `:prolog-check`.

**`:prolog-query`** is designed to verify eval scenario output against a named rule in `*rule-store*`. You define rules that describe what "correct" looks like, then reference them from your eval scenarios:

```lisp
;; Define a rule for what a valid project structure looks like
(define-rule :valid-project
  '((valid-project Tree) <--
    (has-file Tree "src/main.py")
    (has-file Tree "README.md")
    (has-file Tree "tests/test_main.py")))

;; Use it in a scenario
(create-scenario
  :name "Project Scaffolding"
  :prompt "Create a Python project with src, tests, and a README"
  :verifier '(:type :prolog-query)
  :expected :valid-project)
```

When Prolog execution is not available (which is currently the case -- see Part 4b), the verifier falls back to the CL path, which inspects the rule's clause structure and converts `(has-file Tree "path")` predicates into native `:files-exist` checks.

**`:prolog-check`** uses inline check specifications rather than named rules. This is the more directly practical verifier today:

```lisp
(create-scenario
  :name "Config File Creation"
  :prompt "Create a production config.json"
  :verifier '(:type :prolog-check)
  :expected '(:all
              (:files-exist ("config.json"))
              (:output-contains "done")))
```

The `:all` combinator requires every sub-check to pass. You can also use `:files-exist`, `:output-contains`, and `:file-count-above` as standalone checks. This is the **CL fallback** path, and it is the currently working verification mechanism. The function `clauses-to-cl-check` recognizes patterns like `(has-file Tree "path")` and converts them to `(:files-exist ("path"))` specs that run as native Common Lisp checks. No Prolog execution needed.

Verified output from the CL fallback:

```
:files-exist [README.md, src/main.py] with matching tree: PASS
:files-exist [README.md, MISSING.txt] with partial tree: FAIL
:output-contains 'All tests passed': PASS
:all combinator (files + output): PASS
```

![Prolog Rules](images/p5-prolog-rules.png)

## The Series in Perspective

This is Part 5, and it's worth stepping back to see how the pieces fit together.

In [Part 1](/blog/part-1), we established the foundation: agent cognition represented as S-expressions, code-as-data and data-as-code. Every thought, observation, and decision is a data structure that can be inspected, transformed, and serialized.

In [Part 2](/blog/part-2), we showed how that foundation enables orchestration. When agent state is data, a conductor can manage multiple agents, route events, and coordinate workflows without reaching into opaque objects.

In [Part 3](/blog/part-3), we leveraged the data foundation for time-travel. Content-addressable snapshots, branching, and O(1) forking via structural sharing -- all possible because agent state is transparent, immutable data.

In [Part 4](/blog/part-4), we built the Eval Lab on top of all this. Scenarios, harnesses, trials, and comparison matrices that treat agent evaluation like software testing. Scenarios are substrate entities. Results are substrate entities. Everything is queryable, versionable data.

And now, in Part 5, we've added rule-based verification. Rules stored as S-expression data in persistent maps. Rules that survive forking, serialization, and evolution. A CL fallback verifier that inspects rule clauses and runs deterministic checks without needing a Prolog runtime. The full Prolog query path -- where Shen's Prolog engine does unification and backtracking -- is aspirational, pending resolution of the `defprolog` macro compilation gap described in Part 4b. But the core value proposition -- rules as portable, inspectable data with deterministic verification -- works today.

Each capability builds on the homoiconic foundation. None of this is possible when agent state is opaque objects in memory, when configuration lives in YAML files, when the runtime can't inspect its own cognition. The S-expression substrate makes every layer composable with every other layer -- not through special-purpose integration code, but because everything speaks the same language: data.

That's the thesis of Autopoiesis. Agents aren't black boxes. They're programs that can read, write, and reason about themselves. And when you build on that foundation, capabilities like eval, time-travel, and rule-based verification aren't bolt-on features -- they're natural consequences of the architecture.

The code is on [GitHub](https://github.com/pyrex41/autopoiesis). Contributions welcome.

---

*This is Part 5 of the Autopoiesis series.*

- [Part 1: Cognition as Data](/blog/part-1) -- S-expressions, homoiconicity, and why agent state should be code
- [Part 2: Orchestrating the Orchestra](/blog/part-2) -- Conductors, workers, and multi-agent coordination
- [Part 3: Time Travel for Agents](/blog/part-3) -- Snapshots, branching, and content-addressable agent state
- [Part 4: The Eval Lab](/blog/part-4) -- Benchmarking agents like software
- [Part 4b: Under the Hood — Shen Prolog](part-4b.md)
- **Part 5: Logic Meets Learning** -- Prolog-powered agent reasoning
