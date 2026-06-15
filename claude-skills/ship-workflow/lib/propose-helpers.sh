#!/usr/bin/env bash
# propose-helpers.sh — utilities for /ship-propose.
#
# Subcommands:
#   list-roadmap-items <ROADMAP.md>           Print "<section>\t<id>\t<description>" lines.
#   list-active-proposals <Proposals-dir>     Print R-NNN with active proposals (status in draft|in-review|accepted).
#   next-item <ROADMAP.md> <Proposals-dir>    Print next R-NNN that has NO active proposal.
#                                              Resolution order: Now → Next → Later. Empty if none.
#   classify-size <effort> <confidence>       Print S | M | L | skip. Inputs:
#                                              effort ∈ {S,M,L,unknown}, confidence ∈ {high,medium,low,unknown}.
#   slugify <description>                     Print kebab-case slug, cap 6 words.
#   proposal-filename <date> <id> <slug>      Print canonical filename.

set -euo pipefail

cmd="${1:-}"
shift || true

list_roadmap_items() {
  local roadmap="$1"
  [ -f "$roadmap" ] || { echo "no roadmap: $roadmap" >&2; return 1; }
  local section=""
  while IFS= read -r line; do
    case "$line" in
      "## 🔥 Now"*) section="Now" ;;
      "## 🔜 Next"*) section="Next" ;;
      "## 🕐 Later"*) section="Later" ;;
      "## ✅ Done"*) section="Done" ;;
    esac
    # Match: - [ ] **R-NNN** description ...    (allow R-NNN.M too)
    if [[ "$line" =~ ^-\ \[[\ x]\]\ \*\*([Rr]-[0-9]+(\.[0-9]+)?)\*\*[[:space:]]*(.*)$ ]]; then
      local id="${BASH_REMATCH[1]}"
      local desc="${BASH_REMATCH[3]}"
      [ -n "$section" ] && [ "$section" != "Done" ] && printf "%s\t%s\t%s\n" "$section" "$id" "$desc"
    fi
  done < "$roadmap"
}

list_active_proposals() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    local rid status
    rid=$(awk '/^roadmap-id:/ {gsub(/^roadmap-id:[ \"]*|[ \"]*$/, ""); print; exit}' "$f")
    status=$(awk '/^status:/ {gsub(/^status:[ \"]*|[ \"]*$/, ""); print; exit}' "$f")
    [ -z "$rid" ] && continue
    case "$status" in
      draft|in-review|accepted) echo "$rid" ;;
    esac
  done | sort -u
}

next_item() {
  local roadmap="$1"
  local proposals_dir="$2"
  local active
  active=$(list_active_proposals "$proposals_dir" | sort -u)
  for section in Now Next Later; do
    while IFS=$'\t' read -r sec id desc; do
      [ "$sec" = "$section" ] || continue
      if ! grep -Fxq "$id" <<< "$active"; then
        printf "%s\t%s\t%s\n" "$sec" "$id" "$desc"
        return 0
      fi
    done < <(list_roadmap_items "$roadmap")
  done
  return 1
}

classify_size() {
  local effort="${1:-unknown}"
  local conf="${2:-unknown}"
  if [ "$effort" = "S" ] && [ "$conf" = "high" ]; then
    echo "skip"
  elif [ "$effort" = "L" ] || [ "$conf" = "low" ]; then
    echo "L"
  elif [ "$effort" = "M" ] || [ "$conf" = "medium" ]; then
    echo "M"
  else
    echo "M"
  fi
}

slugify() {
  local input="$*"
  # Lower, replace non-alphanum with hyphen, collapse hyphens, trim.
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
    | awk -F- 'BEGIN{OFS="-"} {n=NF>6?6:NF; out=$1; for(i=2;i<=n;i++) out=out"-"$i; print out}'
}

proposal_filename() {
  local date="$1"
  local id="$2"
  local slug="$3"
  printf "%s-%s-%s-proposal.md\n" "$date" "$id" "$slug"
}

case "$cmd" in
  list-roadmap-items)    list_roadmap_items "$@" ;;
  list-active-proposals) list_active_proposals "$@" ;;
  next-item)             next_item "$@" ;;
  classify-size)         classify_size "$@" ;;
  slugify)               slugify "$@" ;;
  proposal-filename)     proposal_filename "$@" ;;
  ""|-h|--help)
    grep -E '^#( |$)' "$0" | sed 's/^# \?//'
    ;;
  *)
    echo "unknown subcommand: $cmd" >&2
    echo "Run with --help for usage" >&2
    exit 2
    ;;
esac
