#!/usr/bin/env bash
# ship-workflow/lib/test-budget.sh
# Measures this ship's test growth against the repo's own baseline.
# Ratios are integer BASIS POINTS (ratio * 1000, floored) so bash 3.2 can
# compare them without bc. Every function echoes 0 / returns cleanly when
# it is outside a git repo or has no data.
#
# Shadow mode is DERIVED, never stored: it reads how many prior rows in
# docs/learnings/_log.md already carry a "ratio " field.

TB_MAJOR_MULT=2
TB_BLOCKING_MULT=4
TB_SHADOW_SHIPS=3

# _tb_is_test_path <path> — exit 0 if the path is test code.
_tb_is_test_path() {
  case "$1" in
    tests/*|test/*|*/tests/*|*/test/*) return 0 ;;
    test_*.py|*_test.py|*/test_*.py|*/*_test.py) return 0 ;;
    *.test.*|*.spec.*|*.bats) return 0 ;;
    *) return 1 ;;
  esac
}

# _tb_is_code_path <path> — exit 0 if the path is code we count at all.
_tb_is_code_path() {
  case "$1" in
    *.py|*.sh|*.bash|*.bats|*.js|*.ts|*.tsx|*.jsx|*.rb|*.go|*.rs) return 0 ;;
    *) return 1 ;;
  esac
}

# _tb_bp <numerator> <denominator> — echo floor(n/d * 1000), or 0 if d is 0.
_tb_bp() {
  local n="$1" d="$2"
  if [ -z "$d" ] || [ "$d" -eq 0 ] 2>/dev/null; then echo 0; return 0; fi
  echo $(( n * 1000 / d ))
}

# tb_baseline_ratio — repo-wide test_lines : src_lines, in basis points.
tb_baseline_ratio() {
  local root f tl=0 sl=0 n
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo 0; return 0; }
  [ -n "$root" ] || { echo 0; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _tb_is_code_path "$f" || continue
    [ -f "$root/$f" ] || continue
    n=$(wc -l < "$root/$f" | tr -d '[:space:]')
    if _tb_is_test_path "$f"; then tl=$(( tl + n )); else sl=$(( sl + n )); fi
  done <<EOF
$(cd "$root" && git ls-files 2>/dev/null)
EOF
  _tb_bp "$tl" "$sl"
}

# tb_ship_ratio <base_ref> <head_ref> — added test_lines : added src_lines, bp.
tb_ship_ratio() {
  local base="$1" head="$2" f tl=0 sl=0 added
  git rev-parse --show-toplevel >/dev/null 2>&1 || { echo 0; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _tb_is_code_path "$f" || continue
    added=$(git diff --numstat "$base...$head" -- "$f" 2>/dev/null | awk '{print $1}' | head -1)
    case "$added" in ''|-) added=0 ;; esac
    if _tb_is_test_path "$f"; then tl=$(( tl + added )); else sl=$(( sl + added )); fi
  done <<EOF
$(git diff --name-only "$base...$head" 2>/dev/null)
EOF
  _tb_bp "$tl" "$sl"
}

# tb_ship_lines <base_ref> <head_ref> — echo "<added_test_lines> <added_src_lines>".
# Shares the classification predicates with tb_ship_ratio so the two can never disagree.
tb_ship_lines() {
  local base="$1" head="$2" f tl=0 sl=0 added
  git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "0 0"; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _tb_is_code_path "$f" || continue
    added=$(git diff --numstat "$base...$head" -- "$f" 2>/dev/null | awk '{print $1}' | head -1)
    case "$added" in ''|-) added=0 ;; esac
    if _tb_is_test_path "$f"; then tl=$(( tl + added )); else sl=$(( sl + added )); fi
  done <<EOF
$(git diff --name-only "$base...$head" 2>/dev/null)
EOF
  echo "$tl $sl"
}

# tb_verdict <ship_bp> <baseline_bp> — echo pass | major | blocking.
tb_verdict() {
  local ship="$1" base="$2"
  if [ -z "$base" ] || [ "$base" -eq 0 ] 2>/dev/null; then echo pass; return 0; fi
  if [ "$ship" -gt $(( base * TB_BLOCKING_MULT )) ]; then echo blocking; return 0; fi
  if [ "$ship" -gt $(( base * TB_MAJOR_MULT )) ]; then echo major; return 0; fi
  echo pass
}

# tb_shadow_active — exit 0 while fewer than TB_SHADOW_SHIPS prior ships
# recorded a ratio in docs/learnings/_log.md.
tb_shadow_active() {
  local root log n
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  log="$root/docs/learnings/_log.md"
  [ -f "$log" ] || return 0
  n=$(grep -cF "ratio " "$log" 2>/dev/null || true)
  n=$(echo -n "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  [ "$n" -lt "$TB_SHADOW_SHIPS" ] && return 0
  return 1
}
