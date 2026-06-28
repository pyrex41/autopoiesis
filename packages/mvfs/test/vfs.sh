#!/usr/bin/env bash
# mvfs P1 — VFS mount client, checkout-first v1 (spec/05): sparse profile,
# lazy materialize, git-index dirstate, O(changes) status, profile widening.
# The mount is trusted shell on the git-CAS; dirstate persists at .mvfs/dirstate.
# Requires SHEN + git.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/acl.shen src/vfs.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }
chk_has(){ case "$2" in *"$3"*) echo "  PASS: $1";PASS=$((PASS+1));; *) echo "  FAIL: $1 (got '$2' want substr '$3')";FAIL=$((FAIL+1));; esac; }
pos(){ [ "$1" -gt 0 ] 2>/dev/null && echo yes || echo no; }

# real monorepo. NOTE: content dirs avoid the names src/ and host/ (those are the
# loader symlinks in $WORK); we `git add` the content dirs explicitly, never `.`,
# so the symlinks never enter the tree and we never write through them.
git init -q .; git config user.email t@e.st; git config user.name t
mkdir -p app docs tools
printf 'A1\n' > app/a.txt; printf 'B1\n' > app/b.txt; printf 'C1\n' > docs/c.txt; printf 'D1\n' > tools/d.txt
git add app docs tools; git commit -q -m base
TREE=$(git rev-parse 'HEAD^{tree}')
WT="wt"; DS="$WORK/.mvfs-dirstate"
echo "TREE=$TREE"

echo "===== clone + materialize sparse profile [app/] ====="
shen -e "(mvfs.save-dirstate! (mvfs.checkout! \"$TREE\" [\"app/\"] [] \"$WT\") \"$DS\")" >/dev/null
chk "app/a.txt materialized"        "$(pos "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"app/a.txt\"))")")" "yes"
chk "app/b.txt materialized"        "$(pos "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"app/b.txt\"))")")" "yes"
chk "docs/c.txt NOT materialized (out of profile)" "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"docs/c.txt\"))")" "-1"
chk "tools/d.txt NOT materialized"  "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"tools/d.txt\"))")" "-1"
chk "materialized content correct"  "$(cat "$WT/app/a.txt")" "A1"

echo "===== status clean right after checkout ====="
chk "status == [] (clean)"          "$(shen -e "(mvfs.status (mvfs.load-dirstate \"$DS\") \"$WT\")")" "[]"

echo "===== edit a file -> status modified (O(changes), size+hash) ====="
printf 'A2\n' >> "$WT/app/a.txt"
chk_has "status shows app/a.txt modified" "$(shen -e "(mvfs.status (mvfs.load-dirstate \"$DS\") \"$WT\")")" "app/a.txt"
chk_has "status state = modified"          "$(shen -e "(mvfs.status (mvfs.load-dirstate \"$DS\") \"$WT\")")" "modified"

echo "===== delete a tracked file -> status deleted ====="
rm "$WT/app/b.txt"
chk_has "status shows app/b.txt deleted"  "$(shen -e "(mvfs.status (mvfs.load-dirstate \"$DS\") \"$WT\")")" "deleted"

echo "===== widen profile to [app/ docs/] -> docs/c.txt faults in ====="
# restore b so dirstate stays consistent; widen materializes only the NEW (docs/) paths
printf 'B1\n' > "$WT/app/b.txt"
shen -e "(mvfs.save-dirstate! (mvfs.checkout! \"$TREE\" [\"app/\" \"docs/\"] (mvfs.load-dirstate \"$DS\") \"$WT\") \"$DS\")" >/dev/null
chk "docs/c.txt now materialized"   "$(pos "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"docs/c.txt\"))")")" "yes"
chk "docs/c.txt content correct"    "$(cat "$WT/docs/c.txt")" "C1"
chk "tools/ still excluded"         "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"tools/d.txt\"))")" "-1"

echo "===== switch-revision: edit app/a.txt + remove app/b.txt in a new commit ====="
# build a second revision: app/a.txt changes content, app/b.txt deleted, app/e.txt added
git rm -q app/b.txt; printf 'A1-v2\n' > app/a.txt; printf 'E1\n' > app/e.txt
git add app; git commit -q -m v2
TREE2=$(git rev-parse 'HEAD^{tree}')
# switch the wt (profile app/+docs/) from the current dirstate to TREE2
DS2=$(shen -e "(mvfs.switch! (mvfs.load-dirstate \"$DS\") \"$TREE2\" [\"app/\" \"docs/\"] \"$WT\")")
shen -e "(mvfs.save-dirstate! (mvfs.switch! (mvfs.load-dirstate \"$DS\") \"$TREE2\" [\"app/\" \"docs/\"] \"$WT\") \"$DS\")" >/dev/null
chk "app/a.txt updated to v2 content"  "$(cat "$WT/app/a.txt")" "A1-v2"
chk "app/b.txt evicted (removed in v2)" "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"app/b.txt\"))")" "-1"
chk "app/e.txt materialized (added in v2)" "$(pos "$(shen -e "(mvfs.file-size (mvfs.wt-path \"$WT\" \"app/e.txt\"))")")" "yes"
chk "docs/c.txt still present (unchanged)" "$(cat "$WT/docs/c.txt")" "C1"
chk "status clean after switch"        "$(shen -e "(mvfs.status (mvfs.load-dirstate \"$DS\") \"$WT\")")" "[]"

echo "===== vfs result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
