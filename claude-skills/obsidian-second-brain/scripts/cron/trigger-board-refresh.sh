#!/bin/bash
# Triggered by launchd Mon-Fri 09:00 local time.
# Pipes the prompt to `claude -p` for non-interactive execution.

set -euo pipefail

REPO=/Users/leric/Desktop/code/obsidian-second-brain
PROMPT=$REPO/scripts/cron/board-refresh-prompt.txt
LOG=/tmp/langlive-board-refresh.log

# launchd strips most env vars and doesn't run shell rc files.
# Set PATH explicitly so `claude` (and node, git, etc.) resolve.
# (Don't `source ~/.zshrc` — zsh syntax is fatal under bash.)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

cd "$REPO"

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') board-refresh fired ===="
  claude -p "$(cat "$PROMPT")" --output-format text
  echo "==== exit code: $? ===="
} >> "$LOG" 2>&1
