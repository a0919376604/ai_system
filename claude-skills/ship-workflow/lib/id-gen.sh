#!/usr/bin/env bash
# id-gen.sh — allocate the next ID for IDEA / D / R sequences.
#
# Usage:
#   id-gen.sh idea            # next IDEA-NNN
#   id-gen.sh decision        # next D-NNN
#   id-gen.sh roadmap         # next R-NNN
#   id-gen.sh roadmap --child R-014   # next child of R-014 (e.g. R-014.3)
#   id-gen.sh <type> --reserve        # next + create a reservation marker so
#                                       concurrent callers can't pick the same NNN

set -euo pipefail

TYPE="${1:-}"
RESERVE=0
CHILD_PARENT=""

# Parse optional flags
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --reserve)  RESERVE=1; shift ;;
    --child)    CHILD_PARENT="${2:-}"; shift 2 ;;
    *)          shift ;;
  esac
done

REPO_ROOT="$(pwd)"
LOCKDIR="$REPO_ROOT/.claude/.id-gen.lock"
mkdir -p "$REPO_ROOT/.claude"

# Cross-platform locking via mkdir (atomic on POSIX). Retry up to 50 * 0.1s = 5s.
acquire_lock() {
  local tries=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ]; then
      echo "ERROR: could not acquire lock $LOCKDIR after 5s" >&2
      exit 3
    fi
    sleep 0.1
  done
  # Release lock on exit
  trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT
}

# Pad width (read from global config, default 3)
GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
PAD=$(awk -F': *' '$1=="default_id_pad" {
  sub(/[ \t]*#.*$/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit
}' "$GLOBAL_CFG" 2>/dev/null || true)
PAD="${PAD:-3}"

case "$TYPE" in
  idea)
    prefix="IDEA-"
    search_dirs=("$REPO_ROOT/docs/ideas")
    ;;
  decision)
    prefix="D-"
    search_dirs=("$REPO_ROOT/docs/decisions")
    ;;
  roadmap)
    prefix="R-"
    search_dirs=("$REPO_ROOT/docs/brainstorms"
                 "$REPO_ROOT/docs/specs"
                 "$REPO_ROOT/docs/plans"
                 "$REPO_ROOT/docs/learnings")
    ;;
  *)
    echo "ERROR: unknown type '$TYPE' (expected idea|decision|roadmap)" >&2
    exit 2
    ;;
esac

# Child allocation: given parent R-014, return next R-014.M.
# Scans:
#   - on-disk files starting with R-014. in the 4 R-NNN folders
#   - ROADMAP.md mirror for **R-014.M** markers
#   - reservation file lines starting with R-014.
# Then prints R-014.<max+1>
if [ -n "$CHILD_PARENT" ]; then
  if [ "$TYPE" != "roadmap" ]; then
    echo "ERROR: --child only valid with type 'roadmap'" >&2
    exit 2
  fi
  if [[ ! "$CHILD_PARENT" =~ ^R-[0-9]+$ ]]; then
    echo "ERROR: --child requires a parent R-NNN (got '$CHILD_PARENT')" >&2
    exit 2
  fi

  child_prefix="${CHILD_PARENT}."

  next_child() {
    local max=0
    for d in "${search_dirs[@]}"; do
      [ -d "$d" ] || continue
      while IFS= read -r f; do
        local n
        n=$(basename "$f" | sed -E "s/^${CHILD_PARENT}\.([0-9]+).*/\1/")
        n=$((10#$n))
        [ "$n" -gt "$max" ] && max=$n
      done < <(find "$d" -maxdepth 1 -type f -name "${CHILD_PARENT}.*.md" 2>/dev/null)
    done

    # ROADMAP scan for **R-014.M** patterns
    if [ -f "$REPO_ROOT/docs/product/ROADMAP.md" ]; then
      local escaped_parent
      escaped_parent=$(echo "$CHILD_PARENT" | sed 's/[.]/\\./g')
      while IFS= read -r line; do
        local n
        n=$(echo "$line" | sed -E "s/.*\*\*${escaped_parent}\.([0-9]+)\*\*.*/\1/")
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        n=$((10#$n))
        [ "$n" -gt "$max" ] && max=$n
      done < <(grep -oE "\*\*${escaped_parent}\.[0-9]+\*\*" "$REPO_ROOT/docs/product/ROADMAP.md")
    fi

    # Reservation file scan
    if [ -f "$REPO_ROOT/.claude/.id-reservations" ]; then
      while IFS= read -r line; do
        if [[ "$line" == "${child_prefix}"* ]]; then
          local n
          n="${line#${child_prefix}}"
          [[ "$n" =~ ^[0-9]+$ ]] || continue
          n=$((10#$n))
          [ "$n" -gt "$max" ] && max=$n
        fi
      done < "$REPO_ROOT/.claude/.id-reservations"
    fi

    echo "${child_prefix}$((max + 1))"
  }

  acquire_lock
  new_id="$(next_child)"
  if [ "$RESERVE" -eq 1 ]; then
    echo "$new_id" >> "$REPO_ROOT/.claude/.id-reservations"
  fi
  echo "$new_id"
  exit 0
fi

next_id() {
  local max=0
  for d in "${search_dirs[@]}"; do
    [ -d "$d" ] || continue
    # find ${prefix}NNN-*.md, extract NNN as number
    while IFS= read -r f; do
      local n
      n=$(basename "$f" | sed -E "s/^${prefix}([0-9]+).*/\1/")
      n=$((10#$n))
      [ "$n" -gt "$max" ] && max=$n
    done < <(find "$d" -maxdepth 1 -type f -name "${prefix}*.md" 2>/dev/null)
  done

  # For R-* (roadmap) also scan the mirrored ROADMAP.md for **R-NNN** markers.
  # /ship-next --adhoc inserts items into ROADMAP without yet creating files,
  # so the disk-only scan can miss those.
  if [ "$prefix" = "R-" ] && [ -f "$REPO_ROOT/docs/product/ROADMAP.md" ]; then
    while IFS= read -r line; do
      local n
      n=$(echo "$line" | sed -E 's/.*\*\*R-([0-9]+)\*\*.*/\1/')
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      n=$((10#$n))
      [ "$n" -gt "$max" ] && max=$n
    done < <(grep -oE '\*\*R-[0-9]+\*\*' "$REPO_ROOT/docs/product/ROADMAP.md")
  fi

  # Also account for reservations
  if [ -f "$REPO_ROOT/.claude/.id-reservations" ]; then
    while IFS= read -r line; do
      if [[ "$line" == "${prefix}"* ]]; then
        local n
        n="${line#${prefix}}"
        n=$((10#$n))
        [ "$n" -gt "$max" ] && max=$n
      fi
    done < "$REPO_ROOT/.claude/.id-reservations"
  fi

  printf "%s%0*d" "$prefix" "$PAD" "$((max + 1))"
}

# Serialize so concurrent invocations don't collide.
acquire_lock

new_id="$(next_id)"

if [ "$RESERVE" -eq 1 ]; then
  echo "$new_id" >> "$REPO_ROOT/.claude/.id-reservations"
fi

echo "$new_id"
