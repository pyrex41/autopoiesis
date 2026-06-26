# mvfs P0 build harness.
# Requires the author's Shen toolchains; point these at your installs:
SHEN_LUA ?= shen-lua          # LuaJIT port (read tier)
SHEN_CL  ?= shen-cl           # Common Lisp port (land tier)

CORE = src/boundary.shen src/checksum.shen src/types.shen src/fsm.shen src/log.shen src/cli.shen
POS  = test/log-test.shen
NEG  = test/illegal.shen

.PHONY: typecheck typecheck-negative test cl lua clean help

help:
	@echo "targets: typecheck typecheck-negative test cl lua"
	@echo "set SHEN_LUA / SHEN_CL to your toolchain paths"

# Typecheck the core. Shen typechecking is enabled with (tc +).
# Expected: PASS (exit 0).
typecheck:
	$(SHEN_CL) --typecheck $(CORE)

# The four illegal programs MUST be rejected. This target SUCCEEDS only when
# the typechecker FAILS on test/illegal.shen (negative test).
typecheck-negative:
	@if $(SHEN_CL) --typecheck $(CORE) $(NEG) >/dev/null 2>&1; then \
		echo "FAIL: test/illegal.shen typechecked but must be rejected"; exit 1; \
	else \
		echo "OK: illegal programs correctly rejected by the typechecker"; \
	fi

test:
	$(SHEN_CL) --load $(CORE) $(POS) --eval "(mvfs.test:run-all)"

# Land tier image (correctness > speed): shen-cl on SBCL, shelling out to git.
cl:
	$(SHEN_CL) --build-image mvfs-land $(CORE)

# Read tier artifact (hot path): shen-lua → Lua → LuaJIT machine code.
lua:
	$(SHEN_LUA) --compile $(CORE) -o build/mvfs-read.lua

clean:
	rm -rf build
