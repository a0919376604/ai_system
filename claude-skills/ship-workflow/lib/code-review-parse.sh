#!/usr/bin/env bash
# code-review-parse.sh — count severity findings in code-review-skill markdown output.
#
# Usage:
#   eval "$(code-review-parse.sh /path/to/review.md)"
#   echo "$BLOCKING_COUNT"   # → e.g. 2
#
# Recognizes severity-tag styles in the input (any one counts):
#
#   1. `**Severity:** <level>`            — markdown bold key-value pair
#   2. `[<level>]` at line start          — inline square-bracket tag
#   3. emoji-tier at line start (awesome-skills/code-review-skill convention):
#        🔴 → BLOCKING
#        🟡 → MAJOR
#        🟢 → MINOR
#        🎉 → PRAISE
#      Also accepts `[nit]` as MINOR (awesome-skills idiom).
#      Also accepts `[important]` and the word `important` after **Severity:** as MAJOR
#      (awesome-skills uses [important] for yellow-tier instead of [major]).
#
# Category tags are orthogonal to severity and matched anywhere on a line:
#   [seam-violation], [assertion-roulette], [weak-assertion].
# Emits SEAM_VIOLATION_COUNT, ASSERTION_ROULETTE_COUNT, WEAK_ASSERTION_COUNT
# alongside the four existing severity counters.
#
# Word match is case-insensitive: blocking | major | important | minor | nit | praise.
# Emoji match is exact codepoint.
#
# Each MATCHING LINE counts once — a line with both 🔴 and `[blocking]` counts as 1 (not 2).
#
# **Legend / example / explanation lines are deliberately ignored** by anchoring
# inline emoji + bracket tags to line start. This prevents counting things like:
#
#   Legend: 🔴 blocking, 🟡 major, 🟢 minor, 🎉 praise
#   Severity levels: 🔴 / 🟡 / 🟢 are the three tiers ...
#
# as findings. The `**Severity:** <word>` form is left unanchored because that
# pattern is structurally specific to finding documentation.

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: input file not found: $FILE" >&2
  exit 2
fi

# Each helper greps lines matching ANY pattern for the level and counts.
# Note: `grep -c` counts matching lines, not match instances — so duplicate
# patterns on one line still count as 1.
#
# Inline emoji and `[tag]` must be at the **start of a line** (after optional
# leading whitespace) to count — this filters out legend / inline-text usage.

count_blocking() {
  # Line start: 🔴 or [blocking]; OR anywhere: **Severity:** blocking/🔴
  grep -ciE '^[[:space:]]*(🔴|\[blocking\])|\*\*Severity:\*\*[[:space:]]*(blocking|🔴)' "$FILE" || echo 0
}

count_major() {
  # Line start: 🟡, [major], or [important]; OR anywhere: **Severity:** major/important/🟡
  grep -ciE '^[[:space:]]*(🟡|\[major\]|\[important\])|\*\*Severity:\*\*[[:space:]]*(major|important|🟡)' "$FILE" || echo 0
}

count_minor() {
  # Line start: 🟢, [minor], or [nit]; OR anywhere: **Severity:** minor/nit/🟢
  grep -ciE '^[[:space:]]*(🟢|\[minor\]|\[nit\])|\*\*Severity:\*\*[[:space:]]*(minor|nit|🟢)' "$FILE" || echo 0
}

count_praise() {
  # Line start: 🎉 or [praise]; OR anywhere: **Severity:** praise/🎉
  grep -ciE '^[[:space:]]*(🎉|\[praise\])|\*\*Severity:\*\*[[:space:]]*(praise|🎉)' "$FILE" || echo 0
}

# --- Category counters (orthogonal to severity) ------------------------------
# A finding may carry a category tag in addition to its severity tag.
# Category tags are matched anywhere on the line, since severity already
# occupies the line-start position.

count_seam_violation() {
  grep -ciE '\[seam-violation\]' "$FILE" || echo 0
}

count_assertion_roulette() {
  grep -ciE '\[assertion-roulette\]' "$FILE" || echo 0
}

count_weak_assertion() {
  grep -ciE '\[weak-assertion\]' "$FILE" || echo 0
}

BLOCKING=$(count_blocking)
MAJOR=$(count_major)
MINOR=$(count_minor)
PRAISE=$(count_praise)
SEAM_VIOLATION=$(count_seam_violation)
ASSERTION_ROULETTE=$(count_assertion_roulette)
WEAK_ASSERTION=$(count_weak_assertion)

# Strip whitespace that grep -c may inject on some bash versions
BLOCKING=$(echo -n "$BLOCKING" | tr -d '[:space:]')
MAJOR=$(echo -n "$MAJOR" | tr -d '[:space:]')
MINOR=$(echo -n "$MINOR" | tr -d '[:space:]')
PRAISE=$(echo -n "$PRAISE" | tr -d '[:space:]')
SEAM_VIOLATION=$(echo -n "$SEAM_VIOLATION" | tr -d '[:space:]')
ASSERTION_ROULETTE=$(echo -n "$ASSERTION_ROULETTE" | tr -d '[:space:]')
WEAK_ASSERTION=$(echo -n "$WEAK_ASSERTION" | tr -d '[:space:]')

echo "BLOCKING_COUNT=${BLOCKING}"
echo "MAJOR_COUNT=${MAJOR}"
echo "MINOR_COUNT=${MINOR}"
echo "PRAISE_COUNT=${PRAISE}"
echo "SEAM_VIOLATION_COUNT=${SEAM_VIOLATION}"
echo "ASSERTION_ROULETTE_COUNT=${ASSERTION_ROULETTE}"
echo "WEAK_ASSERTION_COUNT=${WEAK_ASSERTION}"
