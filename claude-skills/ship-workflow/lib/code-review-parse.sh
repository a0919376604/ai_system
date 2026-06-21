#!/usr/bin/env bash
# code-review-parse.sh — count severity findings in code-review-skill markdown output.
#
# Usage:
#   eval "$(code-review-parse.sh /path/to/review.md)"
#   echo "$BLOCKING_COUNT"   # → e.g. 2
#
# Recognizes two severity-tag styles in the input:
#   1. **Severity:** <level>     (markdown bold key-value pair)
#   2. [<level>] ...             (inline square-bracket tag at line start or mid-line)
# <level> match is case-insensitive: blocking | major | minor | praise

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: input file not found: $FILE" >&2
  exit 2
fi

count_severity() {
  local level="$1"
  # -i case-insensitive, -E extended, -c count
  # Two patterns OR'd:
  #   \*\*Severity:\*\*[[:space:]]*<level>
  #   \[<level>\]
  grep -ciE "(\*\*Severity:\*\*[[:space:]]*${level}|\[${level}\])" "$FILE" || echo 0
}

BLOCKING=$(count_severity "blocking")
MAJOR=$(count_severity "major")
MINOR=$(count_severity "minor")
PRAISE=$(count_severity "praise")

# Strip newlines that grep -c may inject in some bash versions
BLOCKING=$(echo -n "$BLOCKING" | tr -d '[:space:]')
MAJOR=$(echo -n "$MAJOR" | tr -d '[:space:]')
MINOR=$(echo -n "$MINOR" | tr -d '[:space:]')
PRAISE=$(echo -n "$PRAISE" | tr -d '[:space:]')

echo "BLOCKING_COUNT=${BLOCKING}"
echo "MAJOR_COUNT=${MAJOR}"
echo "MINOR_COUNT=${MINOR}"
echo "PRAISE_COUNT=${PRAISE}"
