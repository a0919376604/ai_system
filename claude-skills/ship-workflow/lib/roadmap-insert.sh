#!/usr/bin/env bash
# roadmap-insert.sh — modify ROADMAP.md "🔥 Now" section.
#
# Usage:
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> <description> [--adhoc] [--epic]
#       Insert a new R-NNN line at the top of "Now".
#       --adhoc  → add adhoc-inserted=true marker
#       --epic   → add (epic) suffix to RID (marks parent of decomposition)
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN.M> <description> --child <parent>
#       Insert a child line indented under the parent's row.
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> --mark-warning "<reason>"
#       Prefix the existing R-NNN line with ⚠️ + add a `↳ flagged:` annotation
#       on the next line. Idempotent.
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> --mark-epic
#       Convert existing line to (epic) — strip ⚠️ + flagged annotation if
#       present, append (epic) marker. Used when decomposition starts.

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

# Pull arg at position 3 if it's not a flag → it's DESC
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
    *)              shift ;;
  esac
done

TMP="${ROADMAP}.tmp"

case "$MODE" in
  insert)
    # Default mode: insert new line at top of Now
    if [ -z "$DESC" ]; then
      echo "ERROR: insert mode requires <description>" >&2
      exit 2
    fi
    suffix=""
    [ "$ADHOC" -eq 1 ] && suffix=" · adhoc-inserted=true"
    suffix="${suffix} · status=in-progress"
    if [ "$EPIC" -eq 1 ]; then
      NEW_LINE="- [ ] **${RID} (epic)** ${DESC}${suffix}"
    else
      NEW_LINE="- [ ] **${RID}** ${DESC}${suffix}"
    fi
    awk -v line="$NEW_LINE" '
      { print }
      /^## 🔥 Now/ && !inserted {
        print line
        inserted = 1
      }
    ' "$ROADMAP" > "$TMP"
    mv "$TMP" "$ROADMAP"
    ;;

  child)
    # Insert child line indented under parent's row
    if [ -z "$DESC" ]; then
      echo "ERROR: child mode requires <description>" >&2
      exit 2
    fi
    if [ -z "$CHILD_PARENT" ]; then
      echo "ERROR: --child requires a parent R-NNN" >&2
      exit 2
    fi
    NEW_LINE="  - [ ] **${RID}** ${DESC} · status=in-progress"
    # Parent pattern: `- [ ] **R-014` followed by either `**` or ` ` (epic case)
    awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" '
      {
        print
        if (!inserted && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" parent "(\\*\\*| )")) {
          # Skip any existing "↳" annotation line that follows
          inserted = 1
          pending_child = 1
          next
        }
        if (pending_child) {
          if ($0 ~ /^[[:space:]]*↳/) {
            # Print the annotation, then queue our child
            next   # already printed above
          }
          # Not annotation → print our child BEFORE this line
          # But we already printed this line. Need different approach.
          pending_child = 0
        }
      }
      # After main loop: nothing. We handle inline above.
    ' "$ROADMAP" > "$TMP"
    # The simpler approach: just insert child directly after parent line.
    # Re-do with cleaner logic:
    awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" '
      {
        print
        if (!inserted && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" parent "(\\*\\*| )")) {
          print line
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
