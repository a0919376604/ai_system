#!/usr/bin/env bash
# roadmap-insert.sh — modify ROADMAP.md "🔥 Now" section.
#
# Usage:
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> <description> [--adhoc] [--epic] [--done-when "<criteria>"] [--est <duration>]
#       Insert a new R-NNN line at the top of "Now".
#       --adhoc      → add adhoc-inserted=true marker
#       --epic       → add (epic) suffix to RID (marks parent of decomposition)
#       --done-when  → add a "done when" annotation on a second line
#       --est        → add est=<duration> to the line (e.g. "3d", "1w")
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN.M> <description> --child <parent> [--done-when ...] [--est ...]
#       Insert an indented child line under the parent. Same --done-when /
#       --est annotations supported.
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> --mark-warning "<reason>"
#       Prefix the existing R-NNN line with WARN icon + add a flagged
#       annotation on the next line. Idempotent.
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> --mark-epic
#       Convert existing line to (epic) — strip warn icon + flagged annotation
#       if present, append (epic) marker. Used when decomposition starts.

set -euo pipefail

ROADMAP="${1:-}"
RID="${2:-}"

if [ -z "$ROADMAP" ] || [ -z "$RID" ]; then
  echo "Usage: see header of $0" >&2
  exit 2
fi
if [ ! -f "$ROADMAP" ]; then
  echo "ERROR: ROADMAP not found: $ROADMAP" >&2
  exit 1
fi
if ! grep -q "^## 🔥 Now" "$ROADMAP"; then
  echo "ERROR: no '## 🔥 Now' heading found in $ROADMAP" >&2
  exit 1
fi

# Parse flags (positions vary by mode)
MODE="insert"           # insert | child | mark-warning | mark-epic
DESC=""
ADHOC=0
EPIC=0
CHILD_PARENT=""
WARN_REASON=""
DONE_WHEN=""
EST=""

# Pull arg at position 3 if it is not a flag → it is DESC
if [ $# -ge 3 ] && [[ "${3:-}" != --* ]]; then
  DESC="$3"
  shift 3
else
  shift 2
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --adhoc)        ADHOC=1; shift ;;
    --epic)         EPIC=1; shift ;;
    --child)        MODE="child"; CHILD_PARENT="$2"; shift 2 ;;
    --mark-warning) MODE="mark-warning"; WARN_REASON="${2:-}"; shift 2 ;;
    --mark-epic)    MODE="mark-epic"; shift ;;
    --done-when)    DONE_WHEN="${2:-}"; shift 2 ;;
    --est)          EST="${2:-}"; shift 2 ;;
    *)              shift ;;
  esac
done

TMP="${ROADMAP}.tmp"

case "$MODE" in
  insert)
    # Default mode: insert new line at top of Now (plus optional done-when annotation)
    if [ -z "$DESC" ]; then
      echo "ERROR: insert mode requires <description>" >&2
      exit 2
    fi
    suffix=""
    [ -n "$EST" ]      && suffix=" · est=${EST}"
    [ "$ADHOC" -eq 1 ] && suffix="${suffix} · adhoc-inserted=true"
    suffix="${suffix} · status=in-progress"
    if [ "$EPIC" -eq 1 ]; then
      NEW_LINE="- [ ] **${RID} (epic)** ${DESC}${suffix}"
    else
      NEW_LINE="- [ ] **${RID}** ${DESC}${suffix}"
    fi
    ANNOTATION=""
    [ -n "$DONE_WHEN" ] && ANNOTATION="    ↳ done when: ${DONE_WHEN}"

    awk -v line="$NEW_LINE" -v annot="$ANNOTATION" '
      { print }
      /^## 🔥 Now/ && !inserted {
        print line
        if (annot != "") print annot
        inserted = 1
      }
    ' "$ROADMAP" > "$TMP"
    mv "$TMP" "$ROADMAP"
    ;;

  child)
    # Insert child line indented under parent (plus optional done-when annotation)
    if [ -z "$DESC" ]; then
      echo "ERROR: child mode requires <description>" >&2
      exit 2
    fi
    if [ -z "$CHILD_PARENT" ]; then
      echo "ERROR: --child requires a parent R-NNN" >&2
      exit 2
    fi
    suffix=""
    [ -n "$EST" ] && suffix=" · est=${EST}"
    suffix="${suffix} · status=in-progress"
    NEW_LINE="  - [ ] **${RID}** ${DESC}${suffix}"
    ANNOTATION=""
    [ -n "$DONE_WHEN" ] && ANNOTATION="      ↳ done when: ${DONE_WHEN}"

    awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" -v annot="$ANNOTATION" '
      {
        print
        if (!inserted && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" parent "(\\*\\*| )")) {
          print line
          if (annot != "") print annot
          inserted = 1
        }
      }
    ' "$ROADMAP" > "$TMP"
    if ! grep -q "$RID" "$TMP"; then
      echo "ERROR: parent $CHILD_PARENT not found in ROADMAP" >&2
      rm -f "$TMP"
      exit 1
    fi
    mv "$TMP" "$ROADMAP"
    ;;

  mark-warning)
    # Prefix the R-NNN line with WARN icon + add flag annotation underneath
    if [ -z "$WARN_REASON" ]; then
      echo "ERROR: --mark-warning requires a reason string" >&2
      exit 2
    fi
    awk -v rid="$RID" -v reason="$WARN_REASON" '
      {
        if (!modified && match($0, "^- \\[ \\] \\*\\*" rid "(\\*\\*| )")) {
          # Add ⚠️ if not already present
          if ($0 !~ /⚠️/) {
            sub(/^- \[ \] /, "- [ ] ⚠️ ", $0)
          }
          print
          # Add annotation if next line is not already one
          getline nxt
          if (nxt ~ /^[[:space:]]*↳ flagged:/) {
            print nxt   # keep existing
          } else {
            print "  ↳ flagged: " reason
            print nxt
          }
          modified = 1
          next
        }
        print
      }
    ' "$ROADMAP" > "$TMP"
    mv "$TMP" "$ROADMAP"
    ;;

  mark-epic)
    # Convert R-NNN line to (epic): strip ⚠️ + ↳ flagged annotation, add (epic)
    awk -v rid="$RID" '
      {
        if (!modified && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" rid "(\\*\\*| )")) {
          # Strip ⚠️
          sub(/⚠️ /, "", $0)
          # Add (epic) if not already present
          if ($0 !~ /\(epic\)/) {
            sub("\\*\\*" rid "\\*\\*", "**" rid " (epic)**", $0)
          }
          print
          # Skip a following ↳ flagged line if present
          getline nxt
          if (nxt ~ /^[[:space:]]*↳ flagged:/) {
            # drop it
          } else {
            print nxt
          }
          modified = 1
          next
        }
        print
      }
    ' "$ROADMAP" > "$TMP"
    mv "$TMP" "$ROADMAP"
    ;;

  *)
    echo "ERROR: unknown mode '$MODE'" >&2
    exit 2
    ;;
esac
