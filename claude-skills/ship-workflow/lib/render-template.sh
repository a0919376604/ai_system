#!/usr/bin/env bash
# render-template.sh — sed-based {{key}} substitution.
#
# Usage: render_template <template_path> key1=value1 key2=value2 ...
# Echoes rendered template to stdout. Unspecified placeholders stay
# as literal {{key}} (leaves TODO markers visible for human review).

render_template() {
  local template="$1"; shift
  [ -f "$template" ] || return 1
  local sed_args=()
  local kv
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    # Escape sed special chars in value: & / \
    val=$(printf '%s' "$val" | sed 's/[&/\]/\\&/g' | tr '\n' '\r' | sed 's/\r/\\n/g')
    sed_args+=(-e "s/{{${key}}}/${val}/g")
  done
  # Apply all substitutions, then translate the \n literals back to real newlines
  sed "${sed_args[@]}" "$template" | tr '\r' '\n' | sed 's/\\n/\n/g'
}
