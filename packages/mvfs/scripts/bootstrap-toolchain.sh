#!/usr/bin/env bash
# Bootstrap a shen-lua toolchain (LuaJIT 2.1 + shen-lua) into ./.toolchain.
# Reproduces the environment used to typecheck/run mvfs P0. Idempotent.
#
# Result: prints the path to the shen-lua launcher. Use as:
#   eval "export SHEN=$(scripts/bootstrap-toolchain.sh)"
#   make typecheck
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # packages/mvfs
TC="$HERE/.toolchain"
mkdir -p "$TC"; cd "$TC"

# 1. LuaJIT 2.1 (the only hard requirement of shen-lua)
if [ ! -x "$TC/LuaJIT-2.1/src/luajit" ]; then
  curl -sSL -o luajit.tgz "https://codeload.github.com/LuaJIT/LuaJIT/tar.gz/refs/heads/v2.1"
  tar xzf luajit.tgz
  make -C LuaJIT-2.1 -j"$(nproc)" >/dev/null
fi
export PATH="$TC/LuaJIT-2.1/src:$PATH"            # so `luajit` resolves for bin/shen

# 2. shen-lua (source checkout; LuaJIT port of the Shen 41.2 kernel)
if [ ! -x "$TC/shen-lua/bin/shen" ]; then
  curl -sSL -o shen-lua.tgz "https://codeload.github.com/pyrex41/shen-lua/tar.gz/refs/heads/main"
  tar xzf shen-lua.tgz
  mv shen-lua-main shen-lua
fi

# bin/shen finds luajit via #!/usr/bin/env luajit, so PATH must include it.
echo "$TC/shen-lua/bin/shen"
