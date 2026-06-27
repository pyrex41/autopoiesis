# mvfs P0 build harness.
#
# Requires the shen-lua launcher (LuaJIT 2.1). Point SHEN at it, e.g.:
#   export SHEN=/path/to/shen-lua/bin/shen
# or run `scripts/bootstrap-toolchain.sh` to build LuaJIT + fetch shen-lua
# into ./.toolchain and set SHEN automatically.
SHEN ?= shen

# Load order matters: scalars (synonyms) first; then callee-before-caller.
CORE = src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen \
       src/log.shen src/fsm.shen src/cli.shen
POS  = test/log-test.shen
NEG  = test/illegal.shen
# Optional lore fragment backend host (doc 33). Not part of CORE: the trunk land
# path is git (daemon-free). Typechecked separately; needs no running loreserver.
LORE = src/host-lore.shen

.PHONY: typecheck typecheck-negative typecheck-lore test all help
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
