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

# _ua_extract_callers — echoes markdown bullet lines for 1-hop upstream
# callers of nodes whose filePath == $1. Format:
#   - <source_id> (via <edge_type>, weight <n>)
#
# NOTE: Python code uses % formatting (not f-strings) so it runs on
# Python 3.9+ without PEP 701 (which enables nested-same-quote f-string
# subscripts and only ships in Python 3.12+).
_ua_extract_callers() {
  local target_path="$1"
  local kg
  kg=$(_ua_kg_path)
  [ -z "$kg" ] && return 0
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    target_ids = set()
    for n in d.get("nodes", []):
        if n.get("filePath") == sys.argv[2]:
            target_ids.add(n.get("id"))
    for e in d.get("edges", []):
        if e.get("target") in target_ids:
            src = e.get("source", "?")
            etype = e.get("type", "?")
            w = e.get("weight", 0)
            print("- %s (via %s, weight %s)" % (src, etype, w))
except Exception:
    pass
' "$kg" "$target_path" 2>/dev/null
}

# _ua_extract_layers — echoes markdown bullet lines for layers whose
# nodeIds intersect nodes of the given files. Format:
#   - <layer_name>: <description>
_ua_extract_layers() {
  local kg
  kg=$(_ua_kg_path)
  [ -z "$kg" ] && return 0
  local files_json
  files_json=$(printf '%s\n' "$@" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    files = set(json.loads(sys.argv[2]))
    node_ids = set()
    for n in d.get("nodes", []):
        if n.get("filePath") in files:
            node_ids.add(n.get("id"))
    for layer in d.get("layers", []):
        if set(layer.get("nodeIds", [])) & node_ids:
            name = layer.get("name", "?")
            desc = layer.get("description", "")
            print("- %s: %s" % (name, desc))
except Exception:
    pass
' "$kg" "$files_json" 2>/dev/null
}

# --- 3. Phase 3 pre-brainstorm context ---------------------------------------

# ua_get_pre_brainstorm_context <R-NNN>
# Reads docs/specs/<R-NNN>-*.md, extracts target-files: YAML list,
# echoes markdown per-file with summary + top 3 callers.
# Empty on any failure (UA absent, spec missing, target-files unset).
ua_get_pre_brainstorm_context() {
  local rid="$1"
  ua_check_installed 2>/dev/null || return 0
  local spec
  spec=$(ls docs/specs/${rid}-*.md 2>/dev/null | head -1)
  [ -z "$spec" ] || [ ! -f "$spec" ] && return 0
  # Grep the target-files: block (YAML list)
  local files
  files=$(awk '/^target-files:/{flag=1; next} /^[a-z-]+:/{flag=0} flag && /^[[:space:]]*-[[:space:]]/{sub(/^[[:space:]]*-[[:space:]]*/,""); print}' "$spec" | head -10)
  [ -z "$files" ] && return 0
  echo "## UA pre-brainstorm context"
  echo
  echo "The following files are on this R-NNN's target list. UA's take:"
  echo
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    echo "### \`$f\`"
    local summary
    summary=$(_ua_extract_file_summary "$f")
    [ -n "$summary" ] && echo "$summary" && echo
    local callers
    callers=$(_ua_extract_callers "$f" | head -3)
    if [ -n "$callers" ]; then
      echo "Callers (top 3):"
      echo "$callers"
      echo
    fi
  done <<< "$files"
}
