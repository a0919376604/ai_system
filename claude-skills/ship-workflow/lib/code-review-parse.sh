#!/usr/bin/env bash
# code-review-parse.sh — count severity findings in code-review-skill markdown output.
#
# Usage:
#   eval "$(code-review-parse.sh /path/to/review.md [/path/to/security.md …])"
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

# One or more review files; counts are summed across all of them (R-003: the
# code review and the security review are parsed together).
if [ "$#" -lt 1 ]; then
  echo "ERROR: input file not found: " >&2
  exit 2
fi
for f in "$@"; do
  [ -f "$f" ] || { echo "ERROR: input file not found: $f" >&2; exit 2; }
done

# The anchored [pre-existing] rule lives in one place, shared with Phase 6 step 4.5.
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/pre-existing.sh"

ALL=$(mktemp "${TMPDIR:-/tmp}/crp-all.XXXXXX")
FILE=$(mktemp "${TMPDIR:-/tmp}/crp-kept.XXXXXX")
trap 'rm -f "$ALL" "$FILE"' EXIT
# `awk 1` ends every file's last line. A plain `cat` glued the next report's first
# line onto a report written without a trailing newline, hiding a HIGH finding.
awk 1 "$@" > "$ALL"

# `[pre-existing]` findings (R-003) exist on the base branch already: they are
# reported, but they never count toward any severity — so they can never block a
# ship or be asked about as one of its own importants. Only the anchored tag
# counts (PRE_EXISTING_RE). Everything below counts the remaining lines.
grep -vE "$PRE_EXISTING_RE" "$ALL" > "$FILE" || true

# Each helper greps lines matching ANY pattern for the level and counts.
# Note: `grep -c` counts matching lines, not match instances — so duplicate
# patterns on one line still count as 1.
#
# Inline emoji and `[tag]` must be at the **start of a line** (after optional
# leading whitespace) to count — this filters out legend / inline-text usage.

count_blocking() {
  # Line start: 🔴 or [blocking]; OR anywhere: **Severity:** blocking/🔴
  grep -ciE '^[[:space:]]*(🔴|\[blocking\])|\*\*Severity:\*\*[[:space:]]*(blocking|🔴)' "$FILE" || true
}

count_major() {
  # Line start: 🟡, [major], or [important]; OR anywhere: **Severity:** major/important/🟡
  grep -ciE '^[[:space:]]*(🟡|\[major\]|\[important\])|\*\*Severity:\*\*[[:space:]]*(major|important|🟡)' "$FILE" || true
}

count_minor() {
  # Line start: 🟢, [minor], or [nit]; OR anywhere: **Severity:** minor/nit/🟢
  grep -ciE '^[[:space:]]*(🟢|\[minor\]|\[nit\])|\*\*Severity:\*\*[[:space:]]*(minor|nit|🟢)' "$FILE" || true
}

count_praise() {
  # Line start: 🎉 or [praise]; OR anywhere: **Severity:** praise/🎉
  grep -ciE '^[[:space:]]*(🎉|\[praise\])|\*\*Severity:\*\*[[:space:]]*(praise|🎉)' "$FILE" || true
}

# --- Category counters (orthogonal to severity) ------------------------------
# A finding may carry a category tag in addition to its severity tag.
# Category tags are matched anywhere on the line, since severity already
# occupies the line-start position.

count_seam_violation() {
  grep -ciE '\[seam-violation\]' "$FILE" || true
}

count_assertion_roulette() {
  grep -ciE '\[assertion-roulette\]' "$FILE" || true
}

count_weak_assertion() {
  grep -ciE '\[weak-assertion\]' "$FILE" || true
}

count_pre_existing() {
  grep -cE "$PRE_EXISTING_RE" "$ALL" || true
}

count_security() {
  # Finding lines only — not prose or indented detail lines that mention a category.
  grep -ciE '^[[:space:]]*(🔴|🟡|🟢|\[blocking\]|\[important\]|\[major\]|\[minor\]|\[nit\]).*\[security:' "$FILE" || true
}

BLOCKING=$(count_blocking)
MAJOR=$(count_major)
MINOR=$(count_minor)
PRAISE=$(count_praise)
SEAM_VIOLATION=$(count_seam_violation)
ASSERTION_ROULETTE=$(count_assertion_roulette)
WEAK_ASSERTION=$(count_weak_assertion)
PRE_EXISTING=$(count_pre_existing)
SECURITY=$(count_security)

# Strip whitespace that grep -c may inject on some bash versions
BLOCKING=$(echo -n "$BLOCKING" | tr -d '[:space:]')
MAJOR=$(echo -n "$MAJOR" | tr -d '[:space:]')
MINOR=$(echo -n "$MINOR" | tr -d '[:space:]')
PRAISE=$(echo -n "$PRAISE" | tr -d '[:space:]')
SEAM_VIOLATION=$(echo -n "$SEAM_VIOLATION" | tr -d '[:space:]')
ASSERTION_ROULETTE=$(echo -n "$ASSERTION_ROULETTE" | tr -d '[:space:]')
WEAK_ASSERTION=$(echo -n "$WEAK_ASSERTION" | tr -d '[:space:]')
PRE_EXISTING=$(echo -n "$PRE_EXISTING" | tr -d '[:space:]')
SECURITY=$(echo -n "$SECURITY" | tr -d '[:space:]')

echo "BLOCKING_COUNT=${BLOCKING}"
echo "MAJOR_COUNT=${MAJOR}"
echo "MINOR_COUNT=${MINOR}"
echo "PRAISE_COUNT=${PRAISE}"
echo "SEAM_VIOLATION_COUNT=${SEAM_VIOLATION}"
echo "ASSERTION_ROULETTE_COUNT=${ASSERTION_ROULETTE}"
echo "WEAK_ASSERTION_COUNT=${WEAK_ASSERTION}"
echo "PRE_EXISTING_COUNT=${PRE_EXISTING:-0}"
echo "SECURITY_COUNT=${SECURITY:-0}"
