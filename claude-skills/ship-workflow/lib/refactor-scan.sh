#!/usr/bin/env bash
# R-025: rs_hotspots, rs_done_when and rs_write_rows support /ship-refactor-scan.

RS_GUARD_1='先補「固定現有行為」的測試（打在重構後模組的介面上），全綠才動結構'
RS_GUARD_2='搬動結構期間既有測試一行都不改且保持全綠；介面測試涵蓋後，才在最後一個獨立 commit 刪掉被取代的淺層測試'
RS_GUARD_3='只動結構不改行為，行為改動另開項目'

rs_hotspots() (
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf '%s\n' 'ERROR: rs_hotspots requires a git repo' >&2
    return 1
  }
  cd "$root" || return 1
  awk -F '\t' '
    FILENAME == ARGV[1] { if ($0 != "") churn[$0]++; next }
    {
      file = $2
      if (file ~ /(^|\/)(test|tests|__tests__|spec|migrations|vendor|node_modules|dist|build)(\/|$)/) next
      name = file; sub(/^.*\//, "", name)
      if (name ~ /^test_/ || name ~ /\.(test|spec)\./ || name ~ /\.d\.ts$/ || name ~ /\.min\./) next
      if (name !~ /\.(py|ts|tsx|js|jsx|mjs|cjs|go|rs|rb|java|kt|swift|php|cs|c|cc|cpp|h|hpp|sh|vue|svelte|scala)$/) next
      if (churn[file]) printf "%d\t%d\t%d\t%s\n", churn[file] * $1, churn[file], $1, file
    }
  ' <(git -c core.quotePath=false log --since="${1:-6} months ago" --no-merges --format= --name-only) \
    <(git -c core.quotePath=false grep -I -c '' HEAD -- 2>/dev/null | awk '{
      # "HEAD:<path>:<lines>" — the line count of each text file at HEAD, not on disk.
      sub(/^HEAD:/, ""); n = $0; sub(/^.*:/, "", n); sub(/:[0-9]+$/, "")
      printf "%s\t%s\n", n, $0
    }') | sort -t$'\t' -k1,1nr -k4,4 | head -n "${2:-10}"
)

rs_done_when() {
  [ -n "${1:-}" ] || return 2
  printf '%s；%s；%s；%s' "$1" "$RS_GUARD_1" "$RS_GUARD_2" "$RS_GUARD_3"
  if [ -n "${2:-}" ]; then printf '；Door: one-way — %s' "$2"; fi
  printf '\n'
}

rs_write_rows() (
  local roadmap="$1" report="$2" rows tmp line rid previous=""
  local chain card description summary outcome reason done_when
  local lib="${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}"
  rows=$(awk -F '\t' '
    function bad(problem) { printf "line %d: %s\n", NR, problem > "/dev/stderr"; exit 2 }
    /^$/ { next }
    {
      if (NF != 6) bad("expected 6 fields")
      for (i=1; i<=5; i++) if ($i == "") bad("empty required field " i)
      if ($1 != "new" && $1 != "after") bad("chain must be new or after")
      if ($2 !~ /^[0-9]+$/) bad("card must be numeric")
      if (!seen && $1 == "after") bad("first row cannot be after")
      seen=1
      print
    }
  ') || return 2
  [ -n "$rows" ] || return 0
  tmp=$(mktemp) || return 1
  trap 'rm -f "$tmp"' EXIT
  while IFS= read -r line; do
    chain=$(printf '%s\n' "$line" | cut -f1)
    card=$(printf '%s\n' "$line" | cut -f2)
    description=$(printf '%s\n' "$line" | cut -f3)
    rid=$("$lib/id-gen.sh" roadmap --reserve) || return 1
    if [ "$chain" = after ]; then
      description="${description}；接在 ${previous} 之後做"
    fi
    description="${description}（報告：Reports/${report}#c${card}）"
    printf '%s\t%s\t%s\n' "$rid" "$description" "$(printf '%s\n' "$line" | cut -f4-6)" >> "$tmp" || return 1
    previous="$rid"
  done <<< "$rows"
  while IFS= read -r line; do
    rid=$(printf '%s\n' "$line" | cut -f1)
    description=$(printf '%s\n' "$line" | cut -f2)
    summary=$(printf '%s\n' "$line" | cut -f3)
    outcome=$(printf '%s\n' "$line" | cut -f4)
    reason=$(printf '%s\n' "$line" | cut -f5)
    done_when=$(rs_done_when "$outcome" "$reason") || return 1
    "$lib/roadmap-insert.sh" "$roadmap" "$rid" "$description" --next \
      --summary "$summary" --done-when "$done_when" || return 1
  done < <(awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}' "$tmp")
  cut -f1,2 "$tmp"
)
