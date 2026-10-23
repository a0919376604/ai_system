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

# ── Deferred entries (merge_mode=mr) ─────────────────────────────────────────
# A review branch must not edit CONTEXT.md: every ship appending or refining it
# made parallel MRs conflict. In mr mode a ship queues its entries in
# docs/ship-pending/<R-NNN>-context.md (a path no other ship writes), and
# /ship-land folds them into CONTEXT.md on the base branch after the MR merges.

CONTEXT_PENDING_DIR_REL="docs/ship-pending"

# context_pending_add <R-NNN> "<entry>" — queue one or more entries. The first
# line must be `- **<term>** — <definition>`; every later line must be either
# indented (a continuation) or another such entry line. Anything else — an
# unindented line, a blank line — would be dropped by context_pending_apply,
# so it is refused here, before the queue is reviewed and merged. Exit 2 on a
# bad ID, a malformed entry, or outside a git repo.
context_pending_add() {
  local id="$1" entry="$2" root first bad
  case "$id" in
    R-[0-9]*) : ;;
    *) echo "context_pending_add: need an R-NNN, got '$id'" >&2; return 2 ;;
  esac
  # A trailing newline (a closing quote on its own line) is not a blank line.
  entry=$(printf '%s' "$entry")
  first=$(printf '%s\n' "$entry" | head -1)
  printf '%s\n' "$first" | grep -qE '^- \*\*[^*]+\*\* — ' \
    || { echo "context_pending_add: not a '- **term** — definition' entry" >&2; return 2; }
  bad=$(printf '%s\n' "$entry" | awk 'NR > 1 && !/^[ \t]/ && !/^- \*\*[^*]+\*\* — / { print NR ": " $0 }')
  [ -z "$bad" ] || {
    echo "context_pending_add: line is neither indented nor a new entry — $bad" >&2
    return 2
  }
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
  mkdir -p "$root/$CONTEXT_PENDING_DIR_REL" || return 2
  printf '%s\n' "$entry" >> "$root/$CONTEXT_PENDING_DIR_REL/$id-context.md"
}

# context_pending_apply <R-NNN> — fold queued entries into CONTEXT.md at the
# repo root. A pending term that already exists replaces that entry, including
# its continuation lines (the following lines that begin with whitespace); a
# new term is appended. Each term ends up exactly once. Deletes the pending
# file and echoes how many distinct terms it applied. No pending file: no-op,
# no output. Does not stage or commit.
context_pending_apply() {
  local id="$1" root pending ctx n
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
  pending="$root/$CONTEXT_PENDING_DIR_REL/$id-context.md"
  ctx="$root/CONTEXT.md"
  [ -f "$pending" ] || return 0
  if [ ! -s "$pending" ]; then rm -f "$pending"; echo 0; return 0; fi
  [ -f "$ctx" ] || : > "$ctx"
  n=$(grep -oE '^- \*\*[^*]+\*\*' "$pending" | sort -u | wc -l | tr -d '[:space:]')
  awk '
    function term_of(line,   t) { t = line; sub(/^- \*\*/, "", t); sub(/\*\*.*$/, "", t); return t }
    FNR == NR {
      if ($0 ~ /^- \*\*[^*]+\*\*/) {
        cur = term_of($0)
        if (!(cur in blk)) order[++n] = cur
        blk[cur] = $0
        next
      }
      if (cur != "" && $0 ~ /^[ \t]/) { blk[cur] = blk[cur] "\n" $0; next }
      cur = ""
      next
    }
    {
      if ($0 ~ /^- \*\*[^*]+\*\*/) {
        t = term_of($0)
        if (t in done) { skipping = 1; next }
        if (t in blk) { print blk[t]; done[t] = 1; skipping = 1; next }
        skipping = 0; print; next
      }
      if (skipping && $0 ~ /^[ \t]/) next
      skipping = 0
      print
    }
    END { for (i = 1; i <= n; i++) if (!(order[i] in done)) print blk[order[i]] }
  ' "$pending" "$ctx" > "$ctx.tmp" && mv "$ctx.tmp" "$ctx" || return 1
  rm -f "$pending"
  echo "$n"
}
