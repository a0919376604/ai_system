#!/usr/bin/env bash
# secondbrain-autopush.sh
#
# Auto commit + push the SecondBrain Obsidian vault to GitHub.
# Driven by ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist, which opens
# ~/Applications/SecondBrainAutopush.app — the app, not launchd, holds the macOS
# privacy grant for ~/Documents (README.md).
#
# Idempotent: if there are no changes, exits silently.
# Commits, then pulls (rebase), then pushes, so other machines' pushes are picked up.

set -euo pipefail

# Overridable so tests can point it at a scratch vault (R-012).
VAULT="${SECONDBRAIN_VAULT:-/Users/leric/Documents/SecondBrain}"
LOG="${SECONDBRAIN_AUTOPUSH_LOG:-$HOME/Library/Logs/secondbrain-autopush.log}"
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH

mkdir -p "$(dirname "$LOG")"

{
  echo ""
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="

  if [ ! -d "$VAULT" ]; then
    echo "ERROR: vault path missing: $VAULT"
    exit 1
  fi
  cd "$VAULT"

  if [ ! -d .git ]; then
    echo "ERROR: $VAULT is not a git repo"
    exit 2
  fi

  # A launchd job may not read ~/Documents (macOS privacy). Without this check git
  # cannot read .git/config and the failure looks like "no origin remote".
  if ! ls .git >/dev/null 2>&1; then
    echo "ERROR: cannot read $VAULT — macOS privacy blocks this process. Run it via"
    echo "       ~/Applications/SecondBrainAutopush.app and allow it under System Settings ›"
    echo "       Privacy & Security › Files and Folders (Documents)."
    exit 5
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "ERROR: no 'origin' remote configured"
    exit 3
  fi

  # A rebase left half-done (by hand, or an older version of this script) must not
  # be committed over: `git add -A` would record the conflict markers.
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    echo "ERROR: a rebase is in progress in $VAULT — finish or abort it by hand"
    exit 6
  fi

  # Commit first, then pull --rebase: a rebase refuses to run over uncommitted
  # changes, which made every pull fail with "You have unstaged changes".
  git add -A
  if git diff --cached --quiet; then
    echo "no changes — nothing to commit"
  else
    files=$(git diff --cached --name-only | wc -l | tr -d ' ')
    # head closes the pipe early; with pipefail that SIGPIPE killed the script
    # silently once a commit had many files. -z keeps non-ASCII names unquoted.
    short_summary=$( { git diff --cached --name-only -z | tr '\0' '\n' | head -3 | sed 's#.*/##' | paste -sd, - ; } 2>/dev/null || true)
    git commit -q -m "auto: $(date '+%Y-%m-%d %H:%M') · $files file(s) · $short_summary"
    echo "committed $files file(s)"
  fi

  # Pick up pushes from other machines before pushing ours.
  if ! git pull --rebase origin main 2>&1; then
    # Never leave the vault mid-rebase: the next run would commit conflict markers.
    git rebase --abort >/dev/null 2>&1 || true
    echo "WARN: pull --rebase failed (offline or conflict); rebase aborted, local commit kept"
  fi

  # Push. A failure (offline, or a conflict left for a human) is logged and exits
  # non-zero; the app wrapper does not pass the code on, so read the log.
  if git push origin main 2>&1; then
    echo "push OK"
  else
    echo "ERROR: push failed (offline? credentials? or a conflict to resolve by hand)"
    exit 4
  fi
} >> "$LOG" 2>&1
