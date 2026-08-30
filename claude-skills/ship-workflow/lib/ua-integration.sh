#!/usr/bin/env bash
# ship-workflow/lib/ua-integration.sh
# Detects Understand-Anything plugin + repo KG, exposes helpers for
# ship-next phases and ship-compound. Auto-detected; every public
# function is a silent no-op when UA is absent.
#
# Design: reads .ua/knowledge-graph.json directly (no UA slash command
# invocation) so it works from any IDE and is unaffected by Claude Code
# plugin discovery timing.

# --- 1. Detection ------------------------------------------------------------

# ua_check_installed
# Exit 0 = UA plugin dir + repo KG both present.
# Exit 1 = plugin dir missing.
# Exit 2 = plugin dir present but KG missing.
# No stdout on any path.
ua_check_installed() {
  local plugin_dir="$HOME/.claude/plugins/cache/understand-anything"
  [ -d "$plugin_dir" ] || return 1
  local kg
  kg=$(_ua_kg_path)
  [ -n "$kg" ] && [ -f "$kg" ] || return 2
  return 0
}

# --- Internal helpers --------------------------------------------------------

# _ua_kg_path — echoes the repo's KG file path (new .ua/ or legacy
# .understand-anything/), or nothing if outside a git repo.
_ua_kg_path() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  if [ -f "$root/.ua/knowledge-graph.json" ]; then
    echo "$root/.ua/knowledge-graph.json"
  elif [ -f "$root/.understand-anything/knowledge-graph.json" ]; then
    echo "$root/.understand-anything/knowledge-graph.json"
  fi
}

# --- 2. Drift check ----------------------------------------------------------

# ua_check_drift — echoes markdown warning block if KG's baseline commit
# differs from HEAD by any project files. Empty stdout when UA absent
# or KG fresh. Always exit 0 (drift is a warning, not a gate).
#
# Format:
#   ≤50 file diff → yellow (⚠) "UA KG is stale: N file(s) changed..."
#   >50 file diff → red (❌) "UA KG severely stale: N file(s) changed..."
ua_check_drift() {
  ua_check_installed 2>/dev/null || return 0
  local kg_commit
  kg_commit=$(_ua_kg_commit_hash) || return 0
  [ -z "$kg_commit" ] && return 0
  local head_commit
  head_commit=$(git rev-parse HEAD 2>/dev/null) || return 0
  [ "$kg_commit" = "$head_commit" ] && return 0
  # Count project files that diverge (excludes .ua/ artifacts)
  local diff_count
  diff_count=$(git diff --name-only "$kg_commit" HEAD -- . ':(exclude).ua' ':(exclude).understand-anything' 2>/dev/null | wc -l | tr -d ' ')
  [ "$diff_count" -eq 0 ] && return 0
  if [ "$diff_count" -gt 50 ]; then
    cat <<EOF
> ❌ UA KG severely stale: $diff_count file(s) changed since KG built at \`$kg_commit\`.
>    Blast-radius report will be misleading. Strongly recommend \`/understand\` before merging.
EOF
  else
    cat <<EOF
> ⚠ UA KG is stale: $diff_count file(s) changed since KG built at \`$kg_commit\`.
> Run \`/understand\` to refresh before trusting blast-radius output.
EOF
  fi
}

# _ua_kg_commit_hash — echoes project.gitCommitHash field from the KG,
# or empty on any failure.
_ua_kg_commit_hash() {
  local kg
  kg=$(_ua_kg_path)
  [ -z "$kg" ] && return 0
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["project"].get("gitCommitHash",""))' "$kg" 2>/dev/null
}

# _ua_extract_file_summary — echoes the summary field of the node with
# filePath == $1, or empty if no match / KG unreadable.
_ua_extract_file_summary() {
  local target_path="$1"
  local kg
  kg=$(_ua_kg_path)
  [ -z "$kg" ] && return 0
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for n in d.get("nodes", []):
        if n.get("filePath") == sys.argv[2] and n.get("type") == "file":
            print(n.get("summary", ""))
            break
except Exception:
    pass
' "$kg" "$target_path" 2>/dev/null
}
