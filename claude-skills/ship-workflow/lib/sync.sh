#!/usr/bin/env bash
# sync.sh — one-way vault → repo sync of 4 strategy files + Proposals/ +
# Roadmap-Notes/. Aborts on repo-ahead divergence (R-087).
#
# Canonical direction: vault → repo (vault is source of truth for strategy
# docs · repo mirror is for tooling that reads from cwd).
#
# Skipped if the freshness window has not yet expired since the last pull.
#
# Usage:
#   sync.sh                       # honor freshness window; abort if repo is ahead
#   sync.sh --force               # bypass freshness window; still abort on divergence
#   sync.sh --override-divergence # bypass divergence check (dangerous · loses repo edits)
#   sync.sh --force --override-divergence
#                                 # both (original --force pre-R-087 behavior)

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VAULT="$("$LIB_DIR/airos-binding.sh" vault)"
PROJECT_PATH="$("$LIB_DIR/airos-binding.sh" project_path)"
REPO_ROOT="$(pwd)"
LAST_PULL="$REPO_ROOT/.claude/.ship-last-pull"

GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
FRESHNESS=$(awk -F': *' '$1=="auto_pull_freshness_window" {
  sub(/[ \t]*#.*$/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit
}' "$GLOBAL_CFG" 2>/dev/null || true)
FRESHNESS="${FRESHNESS:-60}"

FORCE=0
OVERRIDE_DIV=0
for arg in "$@"; do
  case "$arg" in
    --force)                FORCE=1 ;;
    --override-divergence)  OVERRIDE_DIV=1 ;;
    *)
      echo "sync.sh: unknown flag: $arg" >&2
      echo "Usage: sync.sh [--force] [--override-divergence]" >&2
      exit 2
      ;;
  esac
done

if [ "$FORCE" -ne 1 ] && [ -f "$LAST_PULL" ]; then
  # macOS-compatible stat
  if command -v gstat >/dev/null 2>&1; then
    last_mtime=$(gstat -c %Y "$LAST_PULL")
  else
    last_mtime=$(stat -f %m "$LAST_PULL" 2>/dev/null || stat -c %Y "$LAST_PULL")
  fi
  age=$(( $(date +%s) - last_mtime ))
  if [ "$age" -lt "$FRESHNESS" ]; then
    exit 0
  fi
fi

# ── R-087 · divergence pre-check ─────────────────────────────────────────
# For each of the 4 canonical strategy files, if repo differs from vault AND
# repo's git-log commit-timestamp is newer than vault's mtime, that means
# repo has been edited more recently than vault last saw. Overwriting would
# silently lose repo edits (R-078 bug case).
#
# We use git commit-timestamp (not filesystem mtime) for repo because mtime
# is unreliable across worktree checkouts.
#
# Divergence direction we DO NOT care about: vault-newer-than-repo is the
# normal case and always proceeds (vault is source of truth).

_mtime_of() {
  # $1: file path. Returns unix ts. macOS/Linux compat.
  if command -v gstat >/dev/null 2>&1; then
    gstat -c %Y "$1" 2>/dev/null
  else
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
  fi
}

_repo_commit_ts() {
  # $1: relative path from REPO_ROOT. Returns most-recent commit ts, or 0
  # if not tracked / not in a git repo.
  local relpath="$1"
  git -C "$REPO_ROOT" log -1 --format=%ct -- "$relpath" 2>/dev/null || echo 0
}

DIV_FOUND=0
DIV_MSG=""

for f in VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md; do
  src="$PROJECT_PATH/$f"
  dst="$REPO_ROOT/docs/product/$f"
  # Only inspect when both sides exist AND they differ.
  [ -f "$src" ] && [ -f "$dst" ] || continue
  if cmp -s "$src" "$dst"; then continue; fi

  vault_mtime="$(_mtime_of "$src")"
  vault_mtime="${vault_mtime:-0}"
  repo_commit_ts="$(_repo_commit_ts "docs/product/$f")"
  repo_commit_ts="${repo_commit_ts:-0}"

  if [ "$repo_commit_ts" -gt "$vault_mtime" ]; then
    diff_age=$(( repo_commit_ts - vault_mtime ))
    DIV_FOUND=1
    DIV_MSG="${DIV_MSG}  docs/product/${f} · repo commit is ${diff_age}s newer than vault mtime
"
  fi
done

if [ "$DIV_FOUND" -eq 1 ] && [ "$OVERRIDE_DIV" -ne 1 ]; then
  cat >&2 <<EOF
sync.sh: ABORT — repo has newer content than vault for:
${DIV_MSG}
Vault appears stale relative to committed repo state.
Overwriting would silently lose the repo edits (R-078 bug case).

Options:
  (a) Update vault manually so it catches up with repo, then re-run sync.sh
      cp docs/product/<file> "$PROJECT_PATH/<file>"
      # then in vault: git commit / obsidian sync / whatever your vault workflow is
  (b) Overwrite anyway (dangerous · loses repo edits):
      sync.sh --override-divergence
  (c) Read R-087 in ROADMAP.md for the full context of this guard.

EOF
  exit 3
fi

# If --override-divergence was used AND divergence was found, print a loud
# warning so the operator sees what they just chose to do.
if [ "$DIV_FOUND" -eq 1 ] && [ "$OVERRIDE_DIV" -eq 1 ]; then
  echo "sync.sh: WARN — --override-divergence bypassing divergence check" >&2
  echo "         Repo edits WILL be lost for:" >&2
  echo -n "$DIV_MSG" >&2
fi

# ── Existing behavior: vault → repo copy ─────────────────────────────────
mkdir -p "$REPO_ROOT/docs/product"
for f in VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md; do
  src="$PROJECT_PATH/$f"
  dst="$REPO_ROOT/docs/product/$f"
  if [ -f "$src" ]; then
    # Atomic write: cp to .tmp then mv
    cp "$src" "$dst.tmp"
    mv "$dst.tmp" "$dst"
  else
    echo "WARN: $f not found at $src — skipping" >&2
  fi
done

# Mirror vault Proposals/ → repo docs/proposals/ (read-only one-way mirror).
# Skips _archive/ subdir if present (shelved/superseded proposals stay vault-only).
VAULT_PROPOSALS="$PROJECT_PATH/Proposals"
REPO_PROPOSALS="$REPO_ROOT/docs/proposals"
if [ -d "$VAULT_PROPOSALS" ]; then
  mkdir -p "$REPO_PROPOSALS"
  for f in "$VAULT_PROPOSALS"/*.md; do
    [ -f "$f" ] || continue
    bn=$(basename "$f")
    cp "$f" "$REPO_PROPOSALS/$bn.tmp"
    mv "$REPO_PROPOSALS/$bn.tmp" "$REPO_PROPOSALS/$bn"
  done
fi

# Mirror vault Roadmap-Notes/ → repo docs/roadmap-notes/ (read-only one-way mirror).
VAULT_NOTES="$PROJECT_PATH/Roadmap-Notes"
REPO_NOTES="$REPO_ROOT/docs/roadmap-notes"
if [ -d "$VAULT_NOTES" ]; then
  mkdir -p "$REPO_NOTES"
  for f in "$VAULT_NOTES"/*.md; do
    [ -f "$f" ] || continue
    bn=$(basename "$f")
    cp "$f" "$REPO_NOTES/$bn.tmp"
    mv "$REPO_NOTES/$bn.tmp" "$REPO_NOTES/$bn"
  done
fi

# Update freshness marker
mkdir -p "$REPO_ROOT/.claude"
date +%s > "$LAST_PULL"
