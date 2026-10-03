#!/usr/bin/env bash
# roadmap-insert.sh — modify ROADMAP.md "🔥 Now" section.
#
# Usage:
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> <description> [--adhoc] [--epic] [--done-when "<criteria>"] [--est <duration>]
#       Insert a new R-NNN line at the top of "Now".
#       --adhoc      → add adhoc-inserted=true marker
#       --epic       → add (epic) suffix to RID (marks parent of decomposition)
#       --done-when  → add a "done when" annotation on a second line
#       --explain    → add ↳ explain: [[<slug>]] annotation (positioned BEFORE done-when)
#       --est        → add est=<duration> to the line (e.g. "3d", "1w")
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN.M> <description> --child <parent> [--done-when ...] [--est ...]
#       Insert an indented child line under the parent. Same --done-when /
#       --est annotations supported.
#       --explain    → add ↳ explain: [[<slug>]] annotation (positioned BEFORE done-when)
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> --mark-warning "<reason>"
#       Prefix the existing R-NNN line with WARN icon + add a flagged
#       annotation on the next line. Idempotent.
#
#   roadmap-insert.sh <ROADMAP.md> <R-NNN> --mark-review "<mr-url>"
#       Flip the row's status= to in-review and record the MR/PR link.
#       Used by Phase 7 in merge_mode=mr, where the branch is pushed for
#       review instead of squash-merged, so the row is NOT Done yet.
#       Idempotent. /ship-land moves it to Done once the MR merges.
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
REVIEW_URL=""
DONE_WHEN=""
EXPLAIN=""
EST=""

# Pull arg at position 3 if it is not a flag → it is DESC
if [ $# -ge 3 ] && [[ "${3:-}" != --* ]]; then
  DESC="$3"
  shift 3
else
  shift 2
fi

# shift2: `shift 2` aborts the whole script under `set -e` when only one arg
# is left, so a flag given without its value died silently with exit 1 and no
# message — every validation error below was unreachable. Shift what exists.
_sh2() { if [ "$1" -gt 1 ]; then echo 2; else echo 1; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --adhoc)        ADHOC=1; shift ;;
    --epic)         EPIC=1; shift ;;
    --child)        MODE="child"; CHILD_PARENT="${2:-}"; shift "$(_sh2 $#)" ;;
    --mark-warning) MODE="mark-warning"; WARN_REASON="${2:-}"; shift "$(_sh2 $#)" ;;
    --mark-review)  MODE="mark-review"; REVIEW_URL="${2:-}"; shift "$(_sh2 $#)" ;;
    --mark-epic)    MODE="mark-epic"; shift ;;
    --done-when)    DONE_WHEN="${2:-}"; shift "$(_sh2 $#)" ;;
    --explain)      EXPLAIN="${2:-}"; shift "$(_sh2 $#)" ;;
    --inject-explain) MODE="inject-explain"; EXPLAIN="${2:-}"; shift "$(_sh2 $#)" ;;
    --est)          EST="${2:-}"; shift "$(_sh2 $#)" ;;
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
    EXPLAIN_LINE=""
    DONE_LINE=""
    [ -n "$EXPLAIN" ]   && EXPLAIN_LINE="    ↳ explain: [[${EXPLAIN}]]"
    [ -n "$DONE_WHEN" ] && DONE_LINE="    ↳ done when: ${DONE_WHEN}"

    awk -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
      { print }
      /^## 🔥 Now/ && !inserted {
        print line
        if (explain   != "") print explain
        if (done_line != "") print done_line
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
    EXPLAIN_LINE=""
    DONE_LINE=""
    [ -n "$EXPLAIN" ]   && EXPLAIN_LINE="      ↳ explain: [[${EXPLAIN}]]"
    [ -n "$DONE_WHEN" ] && DONE_LINE="      ↳ done when: ${DONE_WHEN}"

    # awk's `END { exit !inserted }` returns non-zero if no row matched the
    # parent regex. This is more robust than grepping for $RID afterwards,
    # which false-positives when the child ID happens to appear elsewhere
    # in the file (e.g. as a wikilink in a comment).
    if awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
      {
        print
        if (!inserted && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" parent "(\\*\\*| )")) {
          print line
          if (explain   != "") print explain
          if (done_line != "") print done_line
          inserted = 1
        }
      }
      END { exit !inserted }
    ' "$ROADMAP" > "$TMP"; then
      mv "$TMP" "$ROADMAP"
    else
      echo "ERROR: parent $CHILD_PARENT not found in ROADMAP" >&2
      rm -f "$TMP"
      exit 1
    fi
    ;;

  mark-review)
    # Phase 7 (merge_mode=mr) pushed the branch and opened an MR. The row is
    # shipped but NOT landed, so it stays in Now with status=in-review and a
    # link to the review. Marking it Done here would make the ROADMAP claim
    # something that has not happened yet.
    if [ -z "$REVIEW_URL" ]; then
      echo "ERROR: --mark-review requires an MR/PR url" >&2
      exit 2
    fi
    if awk -v rid="$RID" -v url="$REVIEW_URL" '
      {
        if (!modified && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" rid "(\\*\\*| )")) {
          line = $0
          if (line ~ /status=[A-Za-z0-9._-]+/) {
            sub(/status=[A-Za-z0-9._-]+/, "status=in-review", line)
          } else {
            line = line " · status=in-review"
          }
          if (index(line, url) == 0) { line = line " · mr=" url }
          print line
          modified = 1
          next
        }
        print
      }
      END { exit !modified }
    ' "$ROADMAP" > "$TMP"; then
      mv "$TMP" "$ROADMAP"
    else
      rm -f "$TMP"
      echo "ERROR: no row found for $RID in $ROADMAP" >&2
      exit 1
    fi
    ;;

  mark-warning)
    # Prefix the R-NNN line with WARN icon + add flag annotation underneath
    if [ -z "$WARN_REASON" ]; then
      echo "ERROR: --mark-warning requires a reason string" >&2
      exit 2
    fi
    # awk's `END { exit !modified }` returns non-zero when no row matched.
    # The match regex allows an optional `⚠️ ` already on the row so that
    # re-applying mark-warning on an already-flagged row is a no-op (idempotent),
    # not an error.
    if awk -v rid="$RID" -v reason="$WARN_REASON" '
      {
        if (!modified && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" rid "(\\*\\*| )")) {
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
      END { exit !modified }
    ' "$ROADMAP" > "$TMP"; then
      mv "$TMP" "$ROADMAP"
    else
      echo "ERROR: row $RID not found in $ROADMAP" >&2
      rm -f "$TMP"
      exit 1
    fi
    ;;

  mark-epic)
    # Convert R-NNN line to (epic): strip ⚠️ + ↳ flagged annotation, add (epic)
    # awk's `END { exit !modified }` returns non-zero when no row matched.
    if awk -v rid="$RID" '
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
      END { exit !modified }
    ' "$ROADMAP" > "$TMP"; then
      mv "$TMP" "$ROADMAP"
    else
      echo "ERROR: row $RID not found in $ROADMAP" >&2
      rm -f "$TMP"
      exit 1
    fi
    ;;

  inject-explain)
    if [ -z "$EXPLAIN" ]; then
      echo "ERROR: --inject-explain requires a slug" >&2
      exit 2
    fi
    new_annot="↳ explain: [[${EXPLAIN}]]"
    # awk's `END { exit !modified }` returns non-zero if no row matched the regex.
    # This is more robust than counting $RID occurrences afterwards, which
    # would false-positive if $RID appears as a wikilink elsewhere in the file.
    if awk -v rid="$RID" -v new_annot="$new_annot" '
      function indent_for(line) {
        if (match(line, /^  /)) return "      "
        return "    "
      }
      {
        if (!modified && match($0, "^(  )?- \\[ \\] (⚠️ )?\\*\\*" rid "(\\*\\*| )")) {
          row_line = $0
          row_indent = indent_for(row_line)
          print row_line
          # Look ahead at next line — may be existing explain annotation
          if ((getline nxt) > 0) {
            if (nxt ~ ("^" row_indent "↳ explain:")) {
              if (nxt == row_indent new_annot) {
                # Idempotent: same slug, keep as-is
                print nxt
              } else {
                # Different slug — replace + warn to stderr
                old = nxt
                sub("^" row_indent "↳ explain: \\[\\[", "", old)
                sub("\\]\\][[:space:]]*$", "", old)
                printf("WARN: replacing explain annotation; old slug %s note remains on disk — archive/delete manually if no longer needed\n", old) > "/dev/stderr"
                print row_indent new_annot
              }
            } else {
              # No existing explain; inject new annotation, then re-emit captured line
              print row_indent new_annot
              print nxt
            }
          } else {
            # Row was last line of file
            print row_indent new_annot
          }
          modified = 1
          next
        }
        print
      }
      END { exit !modified }
    ' "$ROADMAP" > "$TMP"; then
      mv "$TMP" "$ROADMAP"
    else
      echo "ERROR: row $RID not found in $ROADMAP" >&2
      rm -f "$TMP"
      exit 1
    fi
    ;;

  *)
    echo "ERROR: unknown mode '$MODE'" >&2
    exit 2
    ;;
esac
