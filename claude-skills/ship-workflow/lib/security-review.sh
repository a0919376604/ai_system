#!/usr/bin/env bash
# ship-workflow/lib/security-review.sh
# The Phase 6 security pass (R-003): a vendored copy of Anthropic's open-source
# /security-review prompt, rendered for this ship's diff.
#
# The review's own configuration — the `security_review: off` switch and the
# repo's docs/SECURITY_REVIEW.md notes — is read from the BASE branch, never from
# the branch under review. Otherwise a ship, or an autonomous fix-plan trying to
# clear a security blocker, could relax its own review in the same diff.

SECURITY_REVIEW_TEMPLATE="${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/security-review/PROMPT.md"

# _sr_base_file <base> <path> — print <path> as it exists on <base>; fail if absent.
_sr_base_file() {
  git show "$1:$2" 2>/dev/null
}

# security_review_enabled <orig_branch> — exit 0 unless the base branch's
# .claude/ship-config.yml says `security_review: off`. Default on.
security_review_enabled() {
  local base="$1" v
  [ -n "$base" ] || return 0
  v=$(_sr_base_file "$base" .claude/ship-config.yml \
      | sed -n 's/^security_review:[[:space:]]*//p' | head -1 \
      | tr -d '"'"'"' \t\r')
  [ "$v" = "off" ] && return 1
  return 0
}

# security_review_render <orig_branch> <out_file> — write the rendered prompt.
# Exit 2 on a missing argument, an unresolvable base, or a missing template.
# No git writes, no network.
security_review_render() {
  local base="$1" out="$2" esc notes touched p
  [ -n "$base" ] && [ -n "$out" ] \
    || { echo "usage: security_review_render <orig_branch> <out_file>" >&2; return 2; }
  git rev-parse --verify -q "${base}^{commit}" >/dev/null \
    || { echo "security_review_render: '$base' does not resolve" >&2; return 2; }
  [ -f "$SECURITY_REVIEW_TEMPLATE" ] \
    || { echo "security_review_render: template missing: $SECURITY_REVIEW_TEMPLATE" >&2; return 2; }
  mkdir -p "$(dirname "$out")" || return 2

  # Escape the replacement for sed: & and the | delimiter are special there.
  esc=$(printf '%s' "$base" | sed 's/[&|\\]/\\&/g')
  sed "s|{{orig_branch}}|$esc|g" "$SECURITY_REVIEW_TEMPLATE" > "$out.tmp" || return 2

  if notes=$(_sr_base_file "$base" docs/SECURITY_REVIEW.md) && [ -n "$notes" ]; then
    printf '\n## REPOSITORY-SPECIFIC NOTES\n\n%s\n' "$notes" >> "$out.tmp"
  fi

  # Root-anchored (`:/`), so the answer does not depend on the cwd. The repo's own
  # copy of ship-next is included: a diff that drops step 1.5 from it would remove
  # the security pass for every later ship.
  touched=$(git diff --name-only "${base}...HEAD" -- \
            ':/docs/SECURITY_REVIEW.md' ':/.claude/ship-config.yml' ':/.claude/commands/ship-next.md' 2>/dev/null)
  if [ -n "$touched" ]; then
    printf "\n## CHANGES TO THIS REVIEW'S OWN CONFIGURATION\n\n" >> "$out.tmp"
    printf '%s\n' "$touched" | while IFS= read -r p; do
      printf -- '- this diff modifies `%s`; the change takes effect only after merge — review it as part of this pass.\n' "$p"
    done >> "$out.tmp"
  fi

  mv "$out.tmp" "$out" || return 2
  echo "$out"
}

# security_review_output_check <file> — exit 0 when the pass produced something
# code-review-parse.sh can count: exactly "No security findings.", or only finding
# lines in the ship-next format, their indented detail lines and blank lines. Exit 3
# otherwise. Any other line — an upstream "# Vuln 1 / * Severity: High" block, a
# bulleted "- 🔴 …", a bold "**HIGH**" — could hold a finding that parses as zero
# and passes the gate silently, so one well-formed line does not excuse it. A
# detail line may not carry a severity either, and marker and tag must agree.
#
# `command grep`: step 1.6 sources this into Claude Code's shell, which wraps grep
# in ugrep, and ugrep's `-vq` exits 1 even when a line does not match — the
# foreign-line test would never fire there.
security_review_output_check() {
  local f="$1" finding='^(🔴 \[blocking\]|🟡 \[important\]|🟢 \[nit\]) '
  [ -f "$f" ] || return 3
  [ "$(tr -d '[:space:]' < "$f")" = "Nosecurityfindings." ] && return 0
  command grep -vqE "^[[:space:]]*\$|${finding}|^[[:space:]]+[^[:space:]]" "$f" && return 3
  # Any case, any spelling of a severity in a detail line, or an indented heading.
  command grep -qiE '^[[:space:]]+(#|.*(🔴|🟡|🟢|🎉|\[(blocking|important|major|minor|nit|praise)\]|severity|\*\*(high|medium|low)\*\*))' "$f" && return 3
  command grep -qE "$finding" "$f" && return 0
  return 3
}
