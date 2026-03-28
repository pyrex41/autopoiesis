# Under the Hood: How Shen Prolog Actually Works Inside Autopoiesis

*Part 4b of the Autopoiesis Series*

Part 5 showed you what Shen Prolog does for agents: rules as data, a reasoning mixin, deterministic verification alongside LLM intelligence. If you read that post and thought "OK, but how does any of this actually work?" -- this is the post for you.

We're going to trace a rule from definition through compilation to query execution. We'll look at how the Shen language runtime gets loaded into a running SBCL process without saving a new binary. We'll understand why there's a single global lock for all Prolog queries, how the CL fallback verifier reverse-engineers Prolog clauses into native checks, and why storing rules as S-expressions rather than compiled predicates is the decision that makes everything else possible.

This is the mechanical deep dive. Expect code.

## The Bridge: Loading Shen Into a Running SBCL

The first problem is a bootstrap problem. Shen is a language implemented on top of Common Lisp. It has its own compiler, its own type system, its own Prolog engine. To use any of that, you need the entire Shen kernel loaded into your Lisp image. The standard approach is `boot.lsp`, which loads the kernel and then calls `save-lisp-and-die` to produce a standalone Shen binary. That's useless for us -- we need Shen loaded into an *already running* application, not a fresh image.

The solution is `load-into-sbcl.lsp`, a custom loader that does what `boot.lsp` does minus the save-and-die. It's 57 lines of careful sequencing.

The tricky part is forward declarations. The Shen kernel files have circular dependencies -- `primitives.lsp` calls initialization functions that don't exist until `init.lsp` loads 20 files later. The loader stubs them out first:

```lisp
;; load-into-sbcl.lsp, lines 10-13
(defun |shen.initialise| () nil)
(defun |shen-cl.initialise| () nil)
(defun |shen.x.features.initialise| (&rest args) (declare (ignore args)) nil)
```

Then it loads 25 kernel files in dependency order -- package definitions, primitives, native bindings, the compiler, the Prolog engine, the type system, and initialization:

```lisp
;; load-into-sbcl.lsp, lines 16-41
(dolist (path '("src/package.lsp"
               "src/primitives.lsp"
               "src/native.lsp"
               "src/shen-utils.lsp"
               "compiled/compiler.lsp"
               ;; ... 20 more files ...
               "compiled/init.lsp"
               "compiled/extension-features.lsp"
               "compiled/extension-launcher.lsp"
               "compiled/extension-factorise-defun.lsp"
               "src/overwrite.lsp"))
  (load path :verbose nil :print nil))
```

After loading, the stubs have been replaced by real implementations. Now we call the real initializers. But here's a subtlety you might not catch if you haven't worked across language boundaries: Shen v3.x preserves symbol case. CL upcases everything by default. The initialization function isn't `SHEN.INITIALISE` -- it's `|shen.initialise-environment|`, with pipe quotes preserving lowercase. So we can't just call a symbol directly; we have to find it:

```lisp
;; load-into-sbcl.lsp, lines 44-45
(funcall (find-symbol "shen.initialise-environment" :shen))
```

The same case sensitivity issue shows up everywhere in the bridge. In `shen-eval` (`bridge.lisp`, line 128), every call to the Shen evaluator checks both case variants:

```lisp
;; bridge.lisp, lines 128-129
(let* ((eval-fn (or (find-symbol "eval-kl" :shen)    ; v3.x (case-preserved)
                    (find-symbol "EVAL-KL" :shen)))   ; older versions
```

Now, how does Autopoiesis actually trigger the load? `ensure-shen-loaded` (`bridge.lisp`, line 70) uses lazy loading with double-checked locking -- check `*shen-loaded-p*` without the lock (fast path), then check again under the lock (correct path):

```lisp
;; bridge.lisp, lines 74-79
(when *shen-loaded-p*
  (return-from ensure-shen-loaded t))
(bt:with-lock-held (*shen-lock*)
  ;; Double-check under lock
  (when *shen-loaded-p*
    (return-from ensure-shen-loaded t))
```

The file search (`find-shen-install`, line 38) looks in a cascading set of locations -- `~/shen-cl/`, `vendor/shen-cl/` relative to the ASDF system, Quicklisp local-projects, `/usr/local/share/`, `/opt/`. It checks for our custom `load-into-sbcl.lsp` first, then the standard `boot.lsp` and `install.lsp`. The first file that `probe-file` confirms exists wins.

One more detail that cost debugging time: the Shen kernel files use relative paths internally. Loading `primitives.lsp` from `/Users/you/shen-cl/` works. Loading it from `/Users/you/projects/autopoiesis/` does not, because the kernel expects to find `compiled/core.lsp` relative to its own directory. The bridge sets *both* the OS working directory and CL's `*default-pathname-defaults*` before loading, and restores both afterward:

```lisp
;; bridge.lisp, lines 95-96
(uiop:chdir shen-dir)
(setf *default-pathname-defaults* shen-dir)
```

Setting only one of these isn't enough. CL's `load` uses `*default-pathname-defaults*` for pathname merging, but some Shen internals use POSIX paths that resolve against the OS working directory. Belt and suspenders.

## Thread Safety: One Lock to Rule Them All

Shen is a language runtime, not a library. It has global mutable state -- a symbol table, a type checker, Prolog assertion databases. Two threads evaluating Shen expressions simultaneously would corrupt that state. So the bridge serializes all Shen access through a single lock:

```lisp
;; bridge.lisp, line 14
(defvar *shen-lock* (bt:make-lock "shen")
  "Lock serializing all Shen calls (Shen uses global mutable state).")
```

Every function that touches Shen acquires it. `shen-eval` (`bridge.lisp`, line 127):

```lisp
(bt:with-lock-held (*shen-lock*)
  (let* ((eval-fn (or (find-symbol "eval-kl" :shen)
                      (find-symbol "EVAL-KL" :shen)))
         (result (when (and eval-fn (fboundp eval-fn))
                   (funcall eval-fn form))))
    (shen-to-cl result)))
```

`shen-query` (`bridge.lisp`, line 141) does the same, with an added `handler-case` that catches errors from failed Prolog queries and returns nil instead of signaling.

The lock is a `bt:make-lock`, not `bt:make-recursive-lock`. This is a deliberate choice. A recursive lock would allow re-entrant acquisition from the same thread, which sounds convenient but masks bugs. If `shen-eval` somehow called `shen-eval` recursively (say, through a Shen callback into CL), a recursive lock would silently allow it, potentially with the Shen runtime in an inconsistent intermediate state. A non-recursive lock deadlocks immediately, making the bug obvious. In practice, the call graph is always CL -> Shen (never Shen -> CL -> Shen), so re-entrancy never arises and the simpler lock is correct.

The trade-off is throughput. With one global lock, you get exactly one Shen query at a time across your entire process. For an agent platform where Prolog queries are verification checks (milliseconds, not minutes), this is fine. If you needed high-throughput parallel Prolog, you'd need multiple Shen instances in separate OS processes -- but that's a problem nobody using this platform has actually had.

There's a subtlety in the per-agent reasoning path. When agent A reasons, `load-agent-knowledge` (`reasoning.lisp`, line 59) clears the global rule store and reloads A's rules:

```lisp
;; reasoning.lisp, lines 63-65
(clear-rules)
(dolist (entry (agent-knowledge-base agent))
  (define-rule (car entry) (cdr entry)))
```

If agent B tried to reason concurrently, its rules would get blown away by A's `clear-rules`. The lock prevents this. Each agent gets exclusive access to the Shen runtime for the duration of its reasoning phase. Load rules, query them, release -- the next agent gets a clean slate.

## The Rule Lifecycle: From S-Expression to Prolog

Let's trace a single rule through the entire pipeline, from definition to query result.

### Step 1: Definition

```lisp
(define-rule :member
  '((mem X [X | _] <--)
    (mem X [_ | Y] <-- (mem X Y))))
```

`define-rule` (`rules.lisp`, line 36) does three things: validates the inputs, stores the clauses, and optionally compiles them.

```lisp
;; rules.lisp, lines 45-51
(check-type name keyword)
(check-type clauses list)
(setf (gethash name *rule-store*) clauses)
;; Compile into Shen if loaded
(when (shen-available-p)
  (compile-rule-into-shen name clauses))
name)
```

The rule is now a hash table entry: `:member` maps to a list of clause S-expressions. That's the source of truth. The compiled Prolog predicate in the Shen runtime is a cache, not the canonical representation.

Notice the store uses `'eq` test with keyword keys (`rules.lisp`, line 24). Keywords are interned singletons in CL, so `eq` comparison is a pointer check. Fast, and no risk of string comparison subtleties.

### Step 2: Compilation

`compile-rule-into-shen` (`rules.lisp`, line 75) transforms the S-expression clauses into a Shen `defprolog` form and evaluates it:

```lisp
;; rules.lisp, lines 78-83
(let ((shen-form (clauses-to-defprolog name clauses)))
  (shen-eval shen-form)
  (setf (gethash name *compiled-rules*) t))
```

`clauses-to-defprolog` (`rules.lisp`, line 92) does the actual translation. It converts the keyword name to a Shen symbol and wraps the clauses:

```lisp
;; rules.lisp, lines 96-97
(let ((shen-name (rule-name-to-shen name)))
  `(defprolog ,shen-name ,@clauses))
```

`rule-name-to-shen` (`rules.lisp`, line 99) converts `:member` to the symbol `member` in the `:SHEN` package. The `string-downcase` is critical -- Shen expects lowercase identifiers, but CL's keyword `:MEMBER` has an uppercase name internally:

```lisp
;; rules.lisp, lines 102-105
(let ((str (string-downcase (symbol-name name))))
  (if (find-package :shen)
      (intern str :shen)
      (intern str)))
```

So for our `:member` rule, the generated Shen form is:

```lisp
(defprolog member
  (mem X [X | _] <--)
  (mem X [_ | Y] <-- (mem X Y)))
```

This gets passed to `shen-eval`, which acquires `*shen-lock*`, finds the `eval-kl` function, and evaluates the form in the Shen runtime. The Shen Prolog engine compiles it into its internal representation -- an indexed set of clauses with unification-ready argument patterns.

The `*compiled-rules*` hash table (`rules.lisp`, line 29) tracks which rules have been compiled in the current session. This is separate from `*rule-store*` because compilation is session-specific -- if you serialize rules and reload them in a new image, they need recompilation. `ensure-rule-compiled` (`rules.lisp`, line 85) checks this table before each query and compiles on demand.

### Step 3: Querying

```lisp
(query-rules :member :context '(1 (1 2 3)))
```

`query-rules` (`rules.lisp`, line 111) ensures the rule is compiled, builds a Shen Prolog query form, and dispatches:

```lisp
;; rules.lisp, lines 119-125
(unless (shen-available-p)
  (error "Shen is not loaded. Call (ensure-shen-loaded) first."))
(ensure-rule-compiled name)
(let* ((shen-name (rule-name-to-shen name))
       (args (or context
                 (remove nil (list tree output exit-code)))))
  (shen-query `((,shen-name ,@args))))
```

This builds `((member 1 (1 2 3)))` and passes it to `shen-query` (`bridge.lisp`, line 134), which wraps it in Shen's Prolog query syntax:

```lisp
;; bridge.lisp, line 143
(let* ((wrapped `(prolog? ,@query-form (return Result)))
```

The final form sent to `eval-kl` is:

```lisp
(prolog? (member 1 (1 2 3)) (return Result))
```

Shen's Prolog engine takes over. It attempts unification of `(1 (1 2 3))` against the first clause `(mem X [X | _])`. `X` unifies with `1`, and `[X | _]` matches `(1 2 3)` because the head is `1` (which equals `X`). The query succeeds. The result goes through `shen-to-cl` (`bridge.lisp`, line 156), which converts Shen's `true` symbol to CL's `T`.

If we queried `(query-rules :member :context '(4 (1 2 3)))`, the first clause would fail (4 doesn't match 1), so Shen tries the second clause `(mem X [_ | Y] <-- (mem X Y))`. This strips the head of the list and recurses. After exhausting the list without finding 4, the query fails and `shen-query` returns `NIL`.

### Step 4: Serialization

```lisp
(rules-to-sexpr)
;; => ((:member (mem X [X | _] <--) (mem X [_ | Y] <-- (mem X Y))))
```

`rules-to-sexpr` (`rules.lisp`, line 131) walks the hash table and produces `(name . clauses)` pairs. `sexpr-to-rules` (`rules.lisp`, line 142) does the reverse -- it calls `define-rule` for each entry, which stores and optionally compiles:

```lisp
;; rules.lisp, lines 143-144
(dolist (entry sexpr)
  (define-rule (car entry) (cdr entry)))
```

The serialized form is pure S-expressions. No Shen runtime state, no compiled predicate bytecode, no binary blobs. You can write it to a substrate datom, embed it in JSON, store it in a persistent agent's metadata pmap, or print it to a file. The data *is* the rule. Compilation is a derived operation that can be redone at any time.

## The CL Fallback: When Shen Isn't Installed

The ASDF system definition (`autopoiesis-shen.asd`, line 8) declares only `:autopoiesis` as a dependency -- not Shen. The comment at the top says it clearly:

```
;;;; the extension compiles and loads without Shen installed,
;;;; but Prolog queries require shen-cl to be available.
```

This means the package loads on any Autopoiesis installation, but Prolog queries signal errors if Shen isn't there. For the eval verifiers, that's not acceptable -- you want verification to work everywhere. So the verifier module implements a CL fallback path.

When the `:prolog-query` verifier fires and Shen isn't available, it calls `cl-fallback-verify` (`verifier.lisp`, line 109) instead of querying the Prolog engine:

```lisp
;; verifier.lisp, lines 75-77
(unless (shen-available-p)
  (return-from prolog-query-verifier
    (cl-fallback-verify expected output result)))
```

`cl-fallback-verify` does something clever: it inspects the Prolog clause structure to see if it can be translated to native CL checks. `clauses-to-cl-check` (`verifier.lisp`, line 121) is basically a pattern recognizer for Prolog clauses:

```lisp
;; verifier.lisp, lines 127-138
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
```

It walks each clause, finds the body terms (everything after `<--`), and matches them against known predicates. A `(has-file Tree "src/main.py")` term becomes a `:files-exist` check. An `(output-contains "All tests passed")` term becomes an `:output-contains` check. If the clause has both, they get combined with `:all`:

```lisp
;; verifier.lisp, lines 140-142
((and file-paths output-substrings)
 `(:all (:files-exist ,(nreverse file-paths))
        ,@(mapcar (lambda (s) `(:output-contains ,s))
                  (nreverse output-substrings))))
```

The CL check runner (`cl-check-verify`, line 153) dispatches on these spec keywords. `:files-exist` calls `cl-tree-has-file` for each path. `:output-contains` does a substring search. `:file-count-above` counts file entries. `:all` requires every sub-check to pass:

```lisp
;; verifier.lisp, lines 173-177
(:all
 (let ((checks (rest spec)))
   (if (every (lambda (check)
                (eq :pass (cl-check-verify check output result)))
              checks)
       :pass :fail)))
```

`cl-tree-has-file` (`verifier.lisp`, line 16) itself has a fallback within the fallback. It first tries to use `TREE-FIND-ENTRY` from the snapshot package (an optimized tree search). If that function isn't available, it falls back to a linear scan:

```lisp
;; verifier.lisp, lines 24-29
(if find-fn
    (not (null (funcall find-fn tree path)))
    ;; Fallback: manual search
    (some (lambda (entry)
            (and (listp entry)
                 (stringp (second entry))
                 (string= (second entry) path)))
          tree))
```

The philosophy is: always return `:pass`, `:fail`, or `:error`. Never crash. Degrade gracefully from Shen Prolog to pattern-matched CL checks to "I can't verify this, here's `:error`." The test suite (`shen-tests.lisp`, lines 121-151) explicitly tests the fallback path with rules containing `has-file` predicates, verifying that the CL path produces the same `:pass`/`:fail` results that Shen would.

## Persistent Agent Integration: Rules That Survive Forking

The `shen-reasoning-mixin` (`reasoning.lisp`, line 16) is a CLOS class with a single slot:

```lisp
;; reasoning.lisp, lines 17-21
(defclass shen-reasoning-mixin ()
  ((knowledge-base :initarg :knowledge-base
                   :accessor agent-knowledge-base
                   :initform nil
                   :documentation "List of (rule-name . clauses) pairs.
Loaded into Shen before each reasoning phase."))
```

You mix it into an agent class and the agent gains a knowledge base. The knowledge base is a simple association list -- `((rule-name . clauses) ...)`. `add-knowledge` (`reasoning.lisp`, line 37) conses a new entry onto the front after removing any existing entry with the same name:

```lisp
;; reasoning.lisp, lines 41-44
(let ((kb (agent-knowledge-base agent)))
  (setf (agent-knowledge-base agent)
        (cons (cons rule-name clauses)
              (remove rule-name kb :key #'car))))
```

This means redefining a rule replaces it (the `remove`) and puts the new version at the front of the list (`cons`). The test at `shen-tests.lisp` line 172 verifies this: add `:rule-a`, add `:rule-b`, redefine `:rule-a` -- length stays at 2.

The reasoning integration happens through a method specialization that's worth examining closely. Because `autopoiesis.shen` is a separate ASDF system loaded after the core platform, it can't use a static `defmethod` -- the generic function might not exist at compile time. So it uses `eval` with runtime method definition (`reasoning.lisp`, lines 104-118):

```lisp
;; reasoning.lisp, lines 104-106
(let* ((agent-pkg (find-package :autopoiesis.agent))
       (reason-fn (when agent-pkg (find-symbol "REASON" agent-pkg))))
  (if (and reason-fn (fboundp reason-fn))
      (eval
       `(defmethod ,(intern "REASON" agent-pkg) :around
          ((agent shen-reasoning-mixin) observations)
          ...))
```

The `:around` method calls `reason-with-prolog` (`reasoning.lisp`, line 67), which loads the agent's rules into the global store, queries each one, and collects results:

```lisp
;; reasoning.lisp, lines 73-87
(load-agent-knowledge agent)
(let ((results nil))
  (dolist (entry (agent-knowledge-base agent))
    (let* ((rule-name (car entry))
           (result (handler-case
                       (query-rules rule-name :context observations)
                     (error () nil))))
      (when result
        (push (list :derived rule-name result) results))))
  (nreverse results))
```

The derived facts are appended to the observations as `:prolog-derived`, and `call-next-method` passes the augmented data to the normal reasoning pipeline. If Shen isn't loaded, `reason-with-prolog` returns nil immediately (`reasoning.lisp`, line 71) and the `:around` method passes observations through unchanged. The agent never breaks.

For persistent agents, the knowledge base needs to survive serialization into metadata pmaps. `save-knowledge-to-pmap` (`reasoning.lisp`, line 124) does this:

```lisp
;; reasoning.lisp, lines 134-138
(funcall pmap-put
         (or (ignore-errors
               (slot-value agent 'autopoiesis.agent::metadata))
             (funcall (find-symbol "PMAP-EMPTY" pkg)))
         :shen-rules
         kb-sexpr)
```

It calls `pmap-put` -- which returns a *new* pmap, leaving the old one untouched (persistent data structures from the `fset` library). The knowledge base is stored under the `:shen-rules` key. When you fork an agent, the metadata pmap is shared via structural sharing. The forked agent's rules are the same pointer as the parent's until one of them modifies its knowledge base, at which point `pmap-put` creates a new branch. This is O(1) forking with copy-on-write semantics for rules -- you get it for free from the persistent data structure foundation.

`load-knowledge-from-pmap` (`reasoning.lisp`, line 141) restores rules from a pmap into the agent's `knowledge-base` slot. Time-travel restore, snapshot recovery, agent deserialization -- they all come through this path.

## The Eval Connection: Compositional Verification

Two verifier types connect Shen Prolog to the Eval Lab from Part 4. They're registered by `register-shen-verifiers` (`verifier.lisp`, line 47), which uses dynamic resolution to find the eval package's `REGISTER-VERIFIER` function:

```lisp
;; verifier.lisp, lines 51-53
(let* ((pkg (find-package :autopoiesis.eval))
       (register-fn (when pkg (find-symbol "REGISTER-VERIFIER" pkg))))
  (unless (and register-fn (fboundp register-fn))
    (return-from register-shen-verifiers nil))
```

If the eval package isn't loaded, registration is a no-op. No hard dependency, no load-order problems.

**`:prolog-query`** (`verifier.lisp`, line 69) looks up a named rule and queries it with context from the eval harness result. The context includes the after-tree (filesystem state after execution), the captured output, and the exit code:

```lisp
;; verifier.lisp, lines 83-89
(let* ((metadata (getf result :metadata))
       (after-tree (getf metadata :after-tree))
       (query-result (query-rules expected
                                  :tree (or after-tree '())
                                  :output (or output "")
                                  :exit-code (or (getf result :exit-code) -1))))
  (if query-result :pass :fail))
```

**`:prolog-check`** (`verifier.lisp`, line 92) skips the rule store entirely and dispatches directly to `cl-check-verify`. This is for inline check specs -- when you don't need a reusable named rule, just a quick compositional check:

```lisp
(:all
  (:files-exist ("src/main.py" "README.md" "tests/"))
  (:output-contains "All tests passed")
  (:file-count-above 5))
```

The `:all` combinator is the key to composability. Each sub-check is independent. You can combine file existence checks, output substring matches, and file count thresholds in any combination. Adding a new check type means adding one clause to `cl-check-verify`'s `ecase` and one pattern to `clauses-to-cl-check`'s recognition logic. The verifiers compose from the bottom up, not the top down.

## What We Learned Building This

A few lessons from integrating an external language runtime into a running application, for anyone contemplating something similar:

**Lazy loading is essential.** The Shen kernel takes measurable time to load (it's compiling a language runtime). Most users of the platform never use Prolog reasoning. `ensure-shen-loaded` means you don't pay the cost unless you actually call `shen-eval` or `query-rules`. The double-checked locking pattern -- check without the lock, check again with -- avoids both the overhead of locking on every call and the race condition of loading twice.

**Forward declarations solve circular dependencies during bootstrap.** The Shen kernel files form a dependency DAG that's close to, but not quite, a total order. Stubbing out the initialization functions with no-ops lets the loader process files in a workable sequence, then call the real initializers at the end. This is ugly but robust.

**Case sensitivity across language boundaries is subtle.** Common Lisp upcases symbol names by default. Shen v3.x preserves case with pipe-quoted symbols. If you hardcode `(funcall 'shen:EVAL-KL ...)` it works with older Shen but not v3.x. Always use `find-symbol` with a string argument when crossing the boundary.

**Global mutable state in embedded runtimes needs explicit serialization.** If the embedded runtime were purely functional, you could have per-thread instances. Shen isn't, so you get a lock. The simplicity of a single lock beats the complexity of per-thread Shen images for our throughput requirements.

**Fallback paths deserve the same test coverage as the happy path.** The CL fallback verifier is tested in `shen-tests.lisp` with trees that pass and trees that fail (`lines 121-151`). If you only test the Shen path, you won't discover that your fallback silently returns `:error` for clause patterns it doesn't recognize.

**Data over code.** This is the big one. Storing rules as S-expressions rather than compiled Prolog predicates means rules survive serialization, forking, time-travel, and cross-process transfer. The compiled predicate is an optimization, not a source of truth. The `*rule-store*` hash table holds the data; the `*compiled-rules*` hash table tracks a cache. If the cache is cold, you recompile from the data. If the data is serialized and deserialized across a network, you compile on the other side. The data is portable. The compiled state is local.

This is the same principle that makes the entire Autopoiesis platform work -- represent everything as data, derive behavior from it, and you get portability, inspectability, and composability as natural consequences.

---

*This is Part 4b of a 5-part series on the Autopoiesis agent platform.*

- [Part 1: Code That Rewrites Itself](part-1.md)
- [Part 2: Multi-Agent Orchestration](part-2.md)
- [Part 3: Git for Agent State](part-3.md)
- [Part 4: The Eval Lab](part-4.md)
- **Part 4b: Under the Hood -- Shen Prolog** (you are here)
- [Part 5: Logic Meets Learning](part-5.md)

[GitHub Repository](https://github.com/pyrex41/autopoiesis)
