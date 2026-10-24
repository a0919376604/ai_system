#!/usr/bin/env bash
# ship-workflow/lib/pre-existing.sh
# Follow-ups for `[pre-existing]` review findings (R-003). A defect that already
# exists on the base branch gets flagged again by every ship that touches its code
# path; without a stable key, each ship would file a duplicate IDEA — the repeat-flag
# noise the Pre-existing tag exists to remove.
#
# Convention: the IDEA created for a pre-existing finding carries the literal text
# `(pre-existing-key: <key>)`. The parentheses delimit the key, so `a.py:sql` is
# never mistaken for `a.py:sql_injection`.

# The ONE position a `[pre-existing]` tag counts in: right after the severity tag at
# the start of a finding line, exactly as review-extra-checks.md and the security
# prompt prescribe. Anywhere else — quoted in a description, inside a path, in mixed
# case — it is just text, and the finding counts as this ship's own. Fail closed.
PRE_EXISTING_RE='^[[:space:]]*(🔴|🟡|🟢|🎉)?[[:space:]]*\[(blocking|important|major|minor|nit|praise)\][[:space:]]*\[pre-existing\]'

# pre_existing_lines <file>… — print the finding lines tagged in that position.
pre_existing_lines() {
  grep -hE "$PRE_EXISTING_RE" "$@" 2>/dev/null || true
}

# pre_existing_key <finding-line> — echo `<file>:<category>` for a finding tagged
# `[security:<category>]`, else `<file>:<first 40 chars of the description,
# lowercased>`. Exit 2 when the line names no `<file>:<line>`.
pre_existing_key() {
  local line file cat desc
  # A CRLF report would leave \r in the key, and it would never match its IDEA.
  line=$(printf '%s' "$1" | tr -d '\r')
  file=$(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9_./-]+:[0-9]+' | head -1 | cut -d: -f1)
  [ -n "$file" ] || return 2
  cat=$(printf '%s\n' "$line" | sed -n 's/.*\[security:\([A-Za-z0-9_]*\)\].*/\1/p' | head -1)
  if [ -n "$cat" ]; then
    echo "$file:$cat"
    return 0
  fi
  # Byte cut, then drop any partial UTF-8 character it left at the end: a key that
  # ends mid-character can never be reproduced in an IDEA, so it would never match.
  desc=$(printf '%s\n' "$line" | sed 's/^.* — //' | tr '[:upper:]' '[:lower:]' \
         | LC_ALL=C cut -c1-40 | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
  echo "$file:$desc"
}

# pre_existing_tracked <key> — exit 0 when some docs/ideas/*.md already carries
# `(pre-existing-key: <key>)`.
pre_existing_tracked() {
  local key="$1" root
  [ -n "$key" ] || return 2
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -d "$root/docs/ideas" ] || return 1
  grep -rqF -- "(pre-existing-key: $key)" "$root/docs/ideas" 2>/dev/null
}

# pre_existing_strip_unverified <base> <file>… — in place, drop the tag from every
# pre-existing finding whose cited file does not exist on <base> (or that cites no
# file at all): a file this diff created cannot hold a pre-existing defect. Such a
# finding then counts as this ship's own. Exit 2 when <base> does not resolve.
pre_existing_strip_unverified() {
  local base="$1" f line file tmp
  git rev-parse --verify -q "${base}^{commit}" >/dev/null 2>&1 || return 2
  shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    tmp="$f.strip.$$"
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
      if printf '%s\n' "$line" | grep -qE "$PRE_EXISTING_RE"; then
        file=$(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9_./-]+:[0-9]+' | head -1 | cut -d: -f1)
        if [ -z "$file" ] || ! git cat-file -e "${base}:${file}" 2>/dev/null; then
          line=$(printf '%s\n' "$line" | sed 's/\[pre-existing\][[:space:]]*//')
        fi
      fi
      printf '%s\n' "$line" >> "$tmp"
    done < "$f"
    mv "$tmp" "$f"
  done
}

# pre_existing_drop <file>… — omit pre-existing findings and their indented details.
pre_existing_drop() { PE="$PRE_EXISTING_RE" awk '$0 ~ ENVIRON["PE"] {skip=1; next} skip && /^[[:space:]]+[^[:space:]]/ {next} {skip=0; print}' "$@"; }
