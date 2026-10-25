#!/usr/bin/env bash
# ship-workflow/lib/context-md.sh
# Helpers for <repo>/CONTEXT.md — the project's shared domain vocabulary.
# Every public function is a silent no-op when CONTEXT.md or the git repo
# is absent: no stdout, exit 0 (except the boolean context_md_over_cap).
#
# Entry format is exactly one bullet per entry:
#   - **<term>** — <definition>
# Continuation lines are indented and are NOT counted as entries.

CONTEXT_MD_MAX_LINES=200
CONTEXT_MD_MAX_ENTRIES=60
CONTEXT_MD_TARGET_LINES=150

# context_md_path — echo the repo-root CONTEXT.md path, or nothing.
context_md_path() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] || return 0
  [ -f "$root/CONTEXT.md" ] || return 0
  echo "$root/CONTEXT.md"
}

# context_md_line_count — echo line count, or 0.
context_md_line_count() {
  local f
  f=$(context_md_path)
  if [ -z "$f" ]; then echo 0; return 0; fi
  wc -l < "$f" | tr -d '[:space:]'
}

# context_md_entry_count — echo number of `- **term**` bullets, or 0.
context_md_entry_count() {
  local f n
  f=$(context_md_path)
  if [ -z "$f" ]; then echo 0; return 0; fi
  n=$(grep -cE '^- \*\*[^*]+\*\*' "$f" || true)
  n=$(echo -n "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# context_md_over_cap — exit 0 if over either cap, 1 otherwise.
context_md_over_cap() {
  local lines entries
  lines=$(context_md_line_count)
  entries=$(context_md_entry_count)
  [ "$lines" -gt "$CONTEXT_MD_MAX_LINES" ] && return 0
  [ "$entries" -gt "$CONTEXT_MD_MAX_ENTRIES" ] && return 0
  return 1
}

# context_md_orphan_terms — echo terms (one per line) with no occurrence
# anywhere in the repo outside CONTEXT.md itself. Prune candidates.
context_md_orphan_terms() {
  local f root term
  f=$(context_md_path)
  [ -n "$f" ] || return 0
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  grep -oE '^- \*\*[^*]+\*\*' "$f" 2>/dev/null \
    | sed -e 's/^- \*\*//' -e 's/\*\*$//' \
    | while IFS= read -r term; do
        [ -n "$term" ] || continue
        if ! grep -rqIF --exclude=CONTEXT.md -- "$term" "$root" 2>/dev/null; then
          echo "$term"
        fi
      done
}
