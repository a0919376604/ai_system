#!/usr/bin/env bash
# code-review-parse.sh — count severity findings in code-review-skill markdown output.
#
# Usage:
#   eval "$(code-review-parse.sh /path/to/review.md)"
#   echo "$BLOCKING_COUNT"   # → e.g. 2
#
# Recognizes THREE severity-tag styles in the input (any one counts):
#
#   1. `**Severity:** <level>`            — markdown bold key-value pair
#   2. `[<level>]`                        — inline square-bracket tag
#   3. emoji-tier (awesome-skills/code-review-skill convention):
#        🔴 → BLOCKING
#        🟡 → MAJOR
#        🟢 → MINOR
#        🎉 → PRAISE
#      Also accepts `[nit]` as MINOR (awesome-skills idiom).
#
# Word match is case-insensitive: blocking | major | minor | nit | praise.
# Emoji match is exact codepoint.
#
# Each MATCHING LINE counts once — a line with both 🔴 and `[blocking]` counts as 1 (not 2).

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: input file not found: $FILE" >&2
  exit 2
fi

# Each helper greps lines matching ANY pattern for the level and counts.
# Note: `grep -c` counts matching lines, not match instances — so duplicate
# patterns on one line still count as 1.

count_blocking() {
  # `**Severity:** blocking` OR `[blocking]` OR 🔴
  grep -ciE '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' "$FILE" || echo 0
}

count_major() {
  # `**Severity:** major` OR `[major]` OR 🟡
  grep -ciE '(\*\*Severity:\*\*[[:space:]]*major|\[major\]|🟡)' "$FILE" || echo 0
}

count_minor() {
  # `**Severity:** minor` OR `[minor]` OR `[nit]` OR 🟢
  grep -ciE '(\*\*Severity:\*\*[[:space:]]*minor|\[minor\]|\[nit\]|🟢)' "$FILE" || echo 0
}

count_praise() {
  # `**Severity:** praise` OR `[praise]` OR 🎉
  grep -ciE '(\*\*Severity:\*\*[[:space:]]*praise|\[praise\]|🎉)' "$FILE" || echo 0
}

BLOCKING=$(count_blocking)
MAJOR=$(count_major)
MINOR=$(count_minor)
PRAISE=$(count_praise)

# Strip whitespace that grep -c may inject on some bash versions
BLOCKING=$(echo -n "$BLOCKING" | tr -d '[:space:]')
MAJOR=$(echo -n "$MAJOR" | tr -d '[:space:]')
MINOR=$(echo -n "$MINOR" | tr -d '[:space:]')
PRAISE=$(echo -n "$PRAISE" | tr -d '[:space:]')

echo "BLOCKING_COUNT=${BLOCKING}"
echo "MAJOR_COUNT=${MAJOR}"
echo "MINOR_COUNT=${MINOR}"
echo "PRAISE_COUNT=${PRAISE}"
