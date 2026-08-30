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
