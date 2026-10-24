#!/usr/bin/env bash
# ship-workflow/lib/command-copies.sh
# ship-workflow's commands are installed once per machine: ai_system's
# `./sync.sh restore` links them into ~/.claude/commands/. ship-init used to copy
# commands/*.md into every repo's .claude/commands/ as well, and those copies went
# stale — on 2026-10-23 six repos held 60 of them, none current (R-004 §3.4).

# remove_command_copies <repo-path> — remove the repo's copies of the 13 current and
# former ship-workflow commands; leave every other file in .claude/commands/ alone.
#   tracked copy   → `git rm` (staged, never committed: the operator commits or opens an MR)
#   untracked copy → `rm`
#   a tracked copy with local edits is left in place and reported, so no edit is lost.
# Refuses, removing nothing, unless ~/.claude/commands/ship-next.md resolves: a repo
# must never be left with no working /ship-next. Works in a linked worktree.
remove_command_copies() {
  local repo="${1:-}" name rel own live
  [ -n "$repo" ] && [ -d "$repo" ] || { echo "usage: remove_command_copies <repo-path>" >&2; return 2; }
  # Run from ~ (a session started there), the repo's commands dir IS the user-level one,
  # and its ship-*.md are the installed links, not copies.
  own=$(cd "$repo/.claude/commands" 2>/dev/null && pwd -P) || own=""
  live=$(cd "$HOME/.claude/commands" 2>/dev/null && pwd -P) || live=""
  if [ -n "$own" ] && [ "$own" = "$live" ]; then
    echo "refusing: $repo/.claude/commands is ~/.claude/commands — those are the installed commands, not copies. Nothing removed." >&2
    return 1
  fi
  if [ ! -f "$HOME/.claude/commands/ship-next.md" ]; then
    echo "refusing: ~/.claude/commands/ship-next.md does not resolve — run ./sync.sh restore in ai_system first. Nothing removed." >&2
    return 1
  fi
  for name in ship-next ship-compound ship-idea ship-land ship-init ship-propose \
              ship-explain ship-brief ship-research ship-decision ship-roadmap \
              ship-arch ship-build; do
    rel=".claude/commands/${name}.md"
    [ -e "$repo/$rel" ] || [ -L "$repo/$rel" ] || continue
    if git -C "$repo" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      if git -C "$repo" rm -q -- "$rel" >/dev/null 2>&1; then
        echo "removed (staged): $rel"
      else
        echo "kept: $rel has local edits — remove it by hand once you no longer need them" >&2
      fi
    else
      rm -f "$repo/$rel" && echo "removed (untracked): $rel"
    fi
  done
  return 0
}
