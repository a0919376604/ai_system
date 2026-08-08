#!/usr/bin/env bash
# test-sync-divergence.sh — R-087 integration test for sync.sh divergence guard.
#
# Sets up a temporary vault + repo pair with a controlled divergence, then
# exercises the 4 code paths:
#   1. plain      → abort (exit 3)
#   2. --force    → abort (exit 3) · --force only bypasses freshness
#   3. --override-divergence → succeed with WARN (exit 0) · repo clobbered
#   4. no divergence → succeed silently (exit 0) · content matches
#
# Usage:
#   bash lib/tests/test-sync-divergence.sh
#
# Prints PASS/FAIL per case. Exits 0 iff all cases pass.

# Test uses explicit pass/fail reporting — no `set -e` (would swallow early
# subshells returning nonzero from the very sync.sh aborts we're asserting on).
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$LIB_DIR/sync.sh"

TMPROOT=$(mktemp -d -t ship-sync-test.XXXXXX)
trap 'rm -rf "$TMPROOT"' EXIT

VAULT_DIR="$TMPROOT/vault"
PROJECT_DIR="$VAULT_DIR/10 Projects/testproj"
REPO_DIR="$TMPROOT/repo"
GLOBAL_CFG="$TMPROOT/ship-workflow.yml"

mkdir -p "$PROJECT_DIR" "$REPO_DIR/docs/product" "$REPO_DIR/.claude"

# Minimal global config the scripts read from $HOME/.claude/ship-workflow.yml.
# We can't override that path without editing scripts, so we mount a shim
# below via a temporary HOME.
cat > "$GLOBAL_CFG" <<EOF
airos_vault: $VAULT_DIR
airos_projects_dir: 10 Projects
default_roadmap_mode: soft
auto_pull_freshness_window: 60
code_root: $TMPROOT/code
EOF

# Shim HOME so airos-binding.sh finds the temp config.
export HOME="$TMPROOT"
mkdir -p "$HOME/.claude"
cp "$GLOBAL_CFG" "$HOME/.claude/ship-workflow.yml"

# Per-repo cfg to force the project_name to `testproj` (repo dir basename
# would otherwise leak into airos-binding.sh's default).
mkdir -p "$REPO_DIR/.claude"
cat > "$REPO_DIR/.claude/ship-config.yml" <<EOF
airos_project: testproj
EOF

# Initialize repo git so sync's _repo_commit_ts has something to look at.
(
  cd "$REPO_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name test
)

# ── Set up controlled divergence ─────────────────────────────────────────
# Vault side: "old" version.
cat > "$PROJECT_DIR/ROADMAP.md" <<EOF
# ROADMAP · old vault version

- [ ] R-999 placeholder
EOF

for f in VISION.md STRATEGY.md QUARTERLY_GOALS.md; do
  echo "$f · old vault version" > "$PROJECT_DIR/$f"
done

# Repo side: seed with vault content, commit, then edit + commit ROADMAP
# to make it strictly newer than vault mtime.
for f in VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md; do
  cp "$PROJECT_DIR/$f" "$REPO_DIR/docs/product/$f"
done
(
  cd "$REPO_DIR"
  git add docs/product/*.md .claude/ship-config.yml
  git commit -q -m "seed strategy docs"
)

# Force vault mtime backward + repo commit forward so repo is strictly ahead.
touch -t 202601010000 "$PROJECT_DIR/ROADMAP.md"

# Edit repo ROADMAP + commit (fresh commit ts = now).
cat > "$REPO_DIR/docs/product/ROADMAP.md" <<EOF
# ROADMAP · new repo version

- [x] R-999 placeholder
- [ ] R-087 divergence detection (this ships in the branch under test)
EOF
(
  cd "$REPO_DIR"
  git add docs/product/ROADMAP.md
  git commit -q -m "repo edit ahead of vault"
)

pass=0
fail=0
report() { # $1 name, $2 outcome (PASS|FAIL), $3 detail
  if [ "$2" = "PASS" ]; then
    printf "  ✓ %s\n" "$1"
    pass=$((pass+1))
  else
    printf "  ✗ %s — %s\n" "$1" "$3"
    fail=$((fail+1))
  fi
}

# Reset freshness marker between tests so freshness doesn't skip.
_reset() { rm -f "$REPO_DIR/.claude/.ship-last-pull"; }

# ── Test 1: plain sync.sh → abort (exit 3) ───────────────────────────────
_reset
(cd "$REPO_DIR" && "$SYNC" >/dev/null 2>"$TMPROOT/case1.err"; echo $?) > "$TMPROOT/case1.exit"
ec=$(cat "$TMPROOT/case1.exit")
if [ "$ec" = "3" ] && grep -q "ABORT" "$TMPROOT/case1.err"; then
  report "case 1: default sync aborts on repo-ahead divergence" PASS
else
  report "case 1: default sync aborts on repo-ahead divergence" FAIL "exit=$ec err=$(head -c 120 $TMPROOT/case1.err)"
fi

# ── Test 2: sync.sh --force → still abort (divergence check indep of --force) ──
_reset
(cd "$REPO_DIR" && "$SYNC" --force >/dev/null 2>"$TMPROOT/case2.err"; echo $?) > "$TMPROOT/case2.exit"
ec=$(cat "$TMPROOT/case2.exit")
if [ "$ec" = "3" ] && grep -q "ABORT" "$TMPROOT/case2.err"; then
  report "case 2: --force still respects divergence guard" PASS
else
  report "case 2: --force still respects divergence guard" FAIL "exit=$ec err=$(head -c 120 $TMPROOT/case2.err)"
fi

# ── Test 3: --override-divergence → succeed (exit 0) with WARN + clobber ──
_reset
(cd "$REPO_DIR" && "$SYNC" --override-divergence >/dev/null 2>"$TMPROOT/case3.err"; echo $?) > "$TMPROOT/case3.exit"
ec=$(cat "$TMPROOT/case3.exit")
if [ "$ec" = "0" ] && grep -q "WARN" "$TMPROOT/case3.err" && ! grep -q "R-087" "$REPO_DIR/docs/product/ROADMAP.md"; then
  report "case 3: --override-divergence clobbers with WARN" PASS
else
  report "case 3: --override-divergence clobbers with WARN" FAIL "exit=$ec err=$(head -c 120 $TMPROOT/case3.err) roadmap-has-R087=$(grep -q R-087 $REPO_DIR/docs/product/ROADMAP.md && echo yes || echo no)"
fi

# ── Test 4: no divergence → clean sync (exit 0, silent) ─────────────────
# Restore repo file to match vault so cmp -s returns 0.
cp "$PROJECT_DIR/ROADMAP.md" "$REPO_DIR/docs/product/ROADMAP.md"
_reset
(cd "$REPO_DIR" && "$SYNC" >/dev/null 2>"$TMPROOT/case4.err"; echo $?) > "$TMPROOT/case4.exit"
ec=$(cat "$TMPROOT/case4.exit")
if [ "$ec" = "0" ] && [ ! -s "$TMPROOT/case4.err" ]; then
  report "case 4: no divergence → clean silent sync" PASS
else
  report "case 4: no divergence → clean silent sync" FAIL "exit=$ec err=$(cat $TMPROOT/case4.err)"
fi

echo ""
echo "Summary: $pass pass · $fail fail"
[ "$fail" -eq 0 ]
