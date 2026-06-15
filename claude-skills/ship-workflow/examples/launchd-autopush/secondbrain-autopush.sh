#!/usr/bin/env bash
# secondbrain-autopush.sh
#
# Auto commit + push the SecondBrain Obsidian vault to GitHub.
# Driven by ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist.
#
# Idempotent: if there are no changes, exits silently.
# Pulls first (rebase) so multiple devices / Obsidian Sync edits don't collide.

set -euo pipefail

VAULT=/Users/leric/Documents/SecondBrain
LOG="$HOME/Library/Logs/secondbrain-autopush.log"
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

  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "ERROR: no 'origin' remote configured"
    exit 3
  fi

  # Pull first (rebase) — covers manual pushes from other machines.
  if ! git pull --rebase origin main 2>&1; then
    echo "WARN: pull --rebase failed (offline or unresolved conflict); will still try to push"
  fi

  # Stage all vault changes (including .obsidian/ config, except items in .gitignore).
  git add -A

  # Skip the commit step if there's nothing staged.
  if git diff --cached --quiet; then
    echo "no changes — nothing to commit"
  else
    files=$(git diff --cached --name-only | wc -l | tr -d ' ')
    short_summary=$(git diff --cached --name-only | head -3 | xargs -I{} basename {} | tr '\n' ',' | sed 's/,$//')
    git commit -m "auto: $(date '+%Y-%m-%d %H:%M') · $files file(s) · $short_summary"
    echo "committed $files file(s)"
  fi

  # Push. If push fails (offline), log and exit non-zero so launchd notices.
  if git push origin main 2>&1; then
    echo "push OK"
  else
    echo "ERROR: push failed (network? credentials?)"
    exit 4
  fi
} >> "$LOG" 2>&1
