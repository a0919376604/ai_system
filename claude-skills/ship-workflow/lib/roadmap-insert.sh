#!/usr/bin/env bash
# roadmap-insert.sh — insert a new R-NNN line into ROADMAP.md "🔥 Now" section.
#
# Usage:
#   roadmap-insert.sh <ROADMAP.md path> <R-NNN> <description> [--adhoc]

set -euo pipefail

ROADMAP="${1:-}"
RID="${2:-}"
DESC="${3:-}"
ADHOC=0
[ "${4:-}" = "--adhoc" ] && ADHOC=1

if [ -z "$ROADMAP" ] || [ -z "$RID" ] || [ -z "$DESC" ]; then
  echo "Usage: $0 <ROADMAP.md> <R-NNN> <description> [--adhoc]" >&2
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

# Build the new line
suffix=""
if [ "$ADHOC" -eq 1 ]; then
  suffix=" · adhoc-inserted=true · status=in-progress"
else
  suffix=" · status=in-progress"
fi
NEW_LINE="- [ ] **${RID}** ${DESC}${suffix}"

# Insert after the Now heading. Atomic write via .tmp + mv.
TMP="${ROADMAP}.tmp"
awk -v line="$NEW_LINE" '
  { print }
  /^## 🔥 Now/ && !inserted {
    print line
    inserted = 1
  }
' "$ROADMAP" > "$TMP"
mv "$TMP" "$ROADMAP"
