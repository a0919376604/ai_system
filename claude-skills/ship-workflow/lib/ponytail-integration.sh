#!/usr/bin/env bash
# ship-workflow/lib/ponytail-integration.sh
# Detects an installed ponytail plugin and renders its ladder into
# .ship/ponytail-rules.md for the Phase 5 executor to read.
#
# Why render instead of relying on the plugin's own activation: Phase 5
# spawns a fresh subagent per task, and ponytail documents that subagent
# start hooks cannot inject its ruleset. Injection beats activation.
#
# Every public function is a silent no-op when ponytail is absent.

PONYTAIL_SCOPE_HEADER="Scope: product code. Test code is out of scope for this ladder and is governed by .ship/tdd-rules.md."

# _ponytail_dir — echo the highest-sorting installed version directory.
_ponytail_dir() {
  local base="$HOME/.claude/plugins/cache/ponytail"
  [ -d "$base" ] || return 0
  ls -1 "$base" 2>/dev/null | sort -V | tail -1 | while IFS= read -r v; do
    [ -n "$v" ] && echo "$base/$v"
  done
}

# ponytail_version — echo the installed version, or nothing.
ponytail_version() {
  local d
  d=$(_ponytail_dir)
  [ -n "$d" ] || return 0
  basename "$d"
}

# ponytail_ruleset_path — echo the shipped AGENTS.md path, or nothing.
ponytail_ruleset_path() {
  local d
  d=$(_ponytail_dir)
  [ -n "$d" ] || return 0
  [ -f "$d/AGENTS.md" ] || return 0
  echo "$d/AGENTS.md"
}

# ponytail_check_installed — exit 0 only when plugin dir AND ruleset exist.
ponytail_check_installed() {
  local p
  p=$(ponytail_ruleset_path)
  [ -n "$p" ] || return 1
  return 0
}

# ponytail_ruleset_sha256 — echo the ruleset hash, or nothing.
ponytail_ruleset_sha256() {
  local p
  p=$(ponytail_ruleset_path)
  [ -n "$p" ] || return 0
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$p" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$p" | awk '{print $1}'
  fi
}

# ponytail_render_rules <outfile> — write scope header + ladder, or no-op.
ponytail_render_rules() {
  local out="$1" p
  [ -n "$out" ] || return 0
  p=$(ponytail_ruleset_path)
  [ -n "$p" ] || return 0
  {
    echo "$PONYTAIL_SCOPE_HEADER"
    echo
    cat "$p"
  } > "$out"
}
