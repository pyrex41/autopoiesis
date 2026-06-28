# mvfs P0 build harness.
#
# Requires the shen-lua launcher (LuaJIT 2.1). Point SHEN at it, e.g.:
#   export SHEN=/path/to/shen-lua/bin/shen
# or run `scripts/bootstrap-toolchain.sh` to build LuaJIT + fetch shen-lua
# into ./.toolchain and set SHEN automatically.
SHEN ?= shen

# Load order matters: scalars (synonyms) first; then callee-before-caller.
CORE = src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen \
       src/log.shen src/fsm.shen src/read.shen src/acl.shen src/policy.shen \
       src/vfs.shen src/cli.shen
POS  = test/log-test.shen
NEG  = test/illegal.shen
# Optional lore fragment backend host (doc 33). Not part of CORE: the trunk land
# path is git (daemon-free). Typechecked separately; needs no running loreserver.
LORE = src/host-lore.shen

.PHONY: typecheck typecheck-negative typecheck-lore test e2e t1 t1-kill t2 t3 read read-edge acl vfs policy all help
all: typecheck typecheck-negative typecheck-lore

help:
	@echo "targets: typecheck typecheck-negative test"
	@echo "set SHEN to the shen-lua launcher (bin/shen), or run scripts/bootstrap-toolchain.sh"

# Typecheck the core under Shen's sequent-calculus checker (tc +). Expect exit 0.
typecheck:
	$(SHEN) -e "(tc +)" $(CORE) $(POS)

# Typecheck the optional lore fragment backend host (doc 33). Expect exit 0.
typecheck-lore:
	$(SHEN) -e "(tc +)" $(CORE) $(LORE)

# The four illegal programs MUST be rejected. This target SUCCEEDS only when the
# typechecker FAILS to load test/illegal.shen after the core (negative test).
typecheck-negative:
	@if $(SHEN) -e "(tc +)" $(CORE) $(NEG) >/dev/null 2>&1; then \
		echo "FAIL: test/illegal.shen typechecked but must be rejected"; exit 1; \
	else \
		echo "OK: illegal programs correctly rejected by the typechecker"; \
	fi

# Positive runtime smoke: the real FSM submit->admit->base (fast path, no host
# primitives needed) must yield a `based` value.
test:
	$(SHEN) -e "(tc -)" $(CORE) \
	  -e "(mvfs.base (mvfs.admit (mvfs.submit \"c1\" \"k1\" \"tbase\" \"ttree\" [] \"alice\") (mvfs.check \"alice\" [] 0)) \"tbase\" mvfs.git-merge)"

# End-to-end: run the REAL FSM against REAL git + REAL pijul + a fsync'd durable
# log, via the shen-lua host backend (src/host-lua.shen + host/host.lua). Proves
# the pijul merge oracle, the fenced land path, and I7 actually RUN (not just tc).
# Requires SHEN, PIJUL, PIJUL_CONFIG_DIR (an ssh-agent identity), git+pijul on PATH.
e2e:
	bash test/e2e.sh

# T1: two-store crash-atomicity (Aphyr's ship-decider). Injects a crash at the
# W1/W2 windows and asserts the log-first recovery (forward re-apply + backward
# orphan sweep) restores the invariants. Same env requirements as `e2e`.
t1:
	bash test/t1-crash.sh

# T2: fenced split-brain + idempotency, driven through pland! (the unified
# two-phase land). Asserts I7 (stale leader rejected, no orphan), I3 (retry is a
# no-op), MF-3 (land-point conflict rejected), and live forward progress.
t2:
	bash test/t2-split-brain.sh

# T1-kill: REAL crash (SIGKILL) at the post-append window via pland!'s fault seam,
# then recovery. The fidelity upgrade over t1's deterministic step-stops. Also
# asserts MF-4a (the blob byte-backup survives loss of pijul's own change store).
t1-kill:
	bash test/t1-kill.sh

# T3: TOCTOU race (clean@T -> conflict@T+1 with a competing land between admission
# and land) caught by pland!'s MF-3 land-point re-check; plus MF-5 version pinning
# (recover! refuses a log whose meta names an incompatible pijul version).
t3:
	bash test/t3-toctou.sh

# Read tier (spec/04, spec/05): the brain decision path on a real git tree —
# §5.2 resolve, §5.3 serve-token mint/verify, I8 basis gate, I9 authz. Needs SHEN+git.
read:
	bash test/read.sh

# Read tier cross-language: the OpenResty edge (serve/verify.lua under luajit)
# verifies a token minted by the shen-lua brain. Needs SHEN + LUAJIT.
read-edge:
	bash test/read-edge.sh

# Policy/ACL matcher (spec/03): longest-prefix-deny-wins, groups, default-deny,
# + the §6a conformance differential (fast matcher ≡ independent oracle). Needs SHEN.
acl:
	bash test/acl.sh

# VFS mount client, checkout-first v1 (spec/05): sparse profile, lazy materialize,
# git-index dirstate, O(changes) status, profile widening. Needs SHEN + git.
vfs:
	bash test/vfs.sh

# Policy lands (spec/03 §4): ACL tied into the land kernel — policy lands fenced,
# acl-version derived from the log, effective-policy = latest landed ruleset (I6).
policy:
	bash test/policy.sh
