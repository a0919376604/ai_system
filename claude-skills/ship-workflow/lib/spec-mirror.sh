#!/usr/bin/env bash
# spec-mirror.sh — copy a spec from repo to vault with mirror-source: key injected.
#
# Usage:
#   spec-mirror.sh <src-spec-path> <dst-vault-path>
#
# Side effects:
#   - Auto-creates <dst> parent dir via mkdir -p
#   - Writes to <dst>.tmp then atomically mv to <dst>
#   - Injects `mirror-source: <src>` inside the frontmatter block (before
#     the closing `---`), unless already present (idempotent).
#   - If <src> has no frontmatter, body is copied verbatim with no injection.
#
# Exit codes:
#   0  success
#   1  fewer than 2 args
#   2  src file not found

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <src-spec-path> <dst-vault-path>" >&2
  exit 1
fi

SRC="$1"
DST="$2"

if [ ! -f "$SRC" ]; then
  echo "ERROR: source spec not found: $SRC" >&2
  exit 2
fi

# The destination may be a symlink back to the source: that is how the vault
# copy is made editable from Obsidian without a second file to keep in sync.
# Copying over it would replace the link with a stale duplicate, and the next
# Obsidian edit would stop reaching git. `-ef` compares device+inode, so it
# catches symlinks, hardlinks and equivalent paths alike.
if [ "$DST" -ef "$SRC" ]; then
  echo "mirror: $DST is the same file as $SRC — nothing to copy" >&2
  exit 0
fi

mkdir -p "$(dirname "$DST")"
TMP="${DST}.tmp"

awk -v src="$SRC" '
  BEGIN { state = "pre"; injected = 0 }

  # First --- enters frontmatter
  state == "pre" && /^---$/ { state = "fm"; print; next }

  # While inside frontmatter, watch for existing mirror-source
  state == "fm" && /^mirror-source:/ { injected = 1; print; next }

  # Second --- exits frontmatter — inject before printing it
  state == "fm" && /^---$/ {
    if (!injected) print "mirror-source: " src
    state = "body"
    print; next
  }

  # All other lines: print as-is
  { print }
' "$SRC" > "$TMP"

mv "$TMP" "$DST"
