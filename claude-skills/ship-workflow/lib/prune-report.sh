#!/usr/bin/env bash
# ship-workflow/lib/prune-report.sh
# Phase 8.5's mechanical half: decide whether a prune report is due, resolve its
# scope, count the candidates Claude wrote, and echo a status line.
#
# READ-ONLY BY CONSTRUCTION. The only filesystem write is `mkdir -p .ship`; the only
# git subcommand is `diff`. Nothing here edits, stages, deletes or commits a test.
#
# This logic used to live as bash inside commands/ship-next.md, and proving it
# destroyed nothing meant extracting the fenced blocks and executing them. Four
# review rounds found holes in that harness rather than in the code: an unindented
# fence was silently skipped, the non-major branch was never exercised, the
# reachability check accepted a vacuous run. A function in lib/ is tested the way
# every other function here is tested, and those holes cannot exist.
#
# Usage:  prune_report <orig_ref> <head_ref> <verdict>
# Echoes the status; always exits 0.

# prune_report_targets <orig_ref> <head_ref>
# Echo the test files in scope: those covering non-test modules the ship touched.
prune_report_targets() {
  local orig="$1" head="$2" touched modules m
  touched=$(git diff --name-only "${orig}...${head}" 2>/dev/null | grep -v '^tests/' || true)
  [ -n "$touched" ] || return 0
  modules=$(echo "$touched" | sed 's|/[^/]*$||' | sort -u)
  for m in $modules; do
    ls "tests/${m##*/}"/*.py 2>/dev/null || true
  done | sort -u
}

# prune_report_count [file]
# Echo the number of CANDIDATE: lines. `grep -c` prints 0 AND exits 1 on no match,
# so `|| echo 0` would append a second zero and render as `00`.
prune_report_count() {
  local f="${1:-.ship/prune-candidates.md}" n
  n=$(grep -c '^CANDIDATE: ' "$f" 2>/dev/null || true)
  n=$(echo "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# prune_report <orig_ref> <head_ref> <verdict>
prune_report() {
  local orig="$1" head="$2" verdict="$3" targets n
  if [ "$verdict" != "major" ]; then
    echo "no report (verdict=${verdict})"
    return 0
  fi
  targets=$(prune_report_targets "$orig" "$head")
  if [ -z "$targets" ]; then
    echo "no report (no scoped test targets)"
    return 0
  fi
  mkdir -p .ship
  n=$(prune_report_count)
  echo "${n} prune candidate(s) — see .ship/prune-candidates.md (nothing deleted)"
}
