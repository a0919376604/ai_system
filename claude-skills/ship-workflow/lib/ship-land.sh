#!/usr/bin/env bash
# ship-workflow/lib/ship-land.sh
# The mechanical half of /ship-land: is the review merged, and fold this
# ship's deferred CONTEXT.md entries onto the base branch.
#
# land_context never touches the operator's checkout. Their base branch is
# routinely behind origin and sometimes dirty, so it works in a throwaway
# worktree at origin/<base> and pushes from there. The fold is deterministic,
# so when a push loses a race it simply redoes the fold on the new tip —
# there is nothing to rebase and nothing that can conflict.

LAND_PUSH_ATTEMPTS=3

command -v context_pending_apply >/dev/null 2>&1 \
  || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/context-md.sh"

# land_is_merged <branch> <base-ref> — exit 0 iff the branch tip is already in
# base-ref. Exit 2 on a missing argument.
land_is_merged() {
  [ -n "$1" ] && [ -n "$2" ] || return 2
  git merge-base --is-ancestor "$1" "$2" 2>/dev/null
}

# land_context <R-NNN> <base> — fold docs/ship-pending/<R-NNN>-context.md into
# CONTEXT.md on origin/<base> in one `[skip ci]` commit and push it.
# Prints `none` (nothing queued, nothing pushed) or `landed <sha>`.
# A rejected push is retried only when origin/<base> actually moved — a lost
# race. Any other rejection (protected branch, auth, network) fails at once
# and shows git's own error, which retrying would only hide.
# Exit 1 when a step fails, on a non-race rejection, or after
# LAND_PUSH_ATTEMPTS lost races; exit 2 on usage.
land_context() {
  local id="$1" base="$2" attempt=0 tmp rc sha base_sha
  [ -n "$id" ] && [ -n "$base" ] || { echo "usage: land_context R-NNN <base>" >&2; return 2; }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ship-land.XXXXXX") || return 1
  while [ "$attempt" -lt "$LAND_PUSH_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    git fetch -q origin "$base" || { rm -rf "$tmp"; return 1; }
    base_sha=$(git rev-parse "origin/$base") || { rm -rf "$tmp"; return 1; }
    git worktree add -q --detach "$tmp/wt" "origin/$base" || { rm -rf "$tmp"; return 1; }
    rc=0
    (
      cd "$tmp/wt" || exit 1
      [ -f "docs/ship-pending/$id-context.md" ] || exit 10
      context_pending_apply "$id" >/dev/null || exit 1
      git add -A CONTEXT.md "docs/ship-pending" || exit 1
      git commit -q -m "context: land $id [skip ci]" || exit 1
      git push -q origin "HEAD:$base" 2>"$tmp/push.err" || exit 11
    ) || rc=$?
    sha=$(git -C "$tmp/wt" rev-parse HEAD 2>/dev/null)
    git worktree remove --force "$tmp/wt" >/dev/null 2>&1
    case "$rc" in
      0)  rm -rf "$tmp"; echo "landed $sha"; return 0 ;;
      10) rm -rf "$tmp"; echo "none"; return 0 ;;
      11)
        git fetch -q origin "$base" 2>/dev/null
        if [ "$(git rev-parse "origin/$base" 2>/dev/null)" = "$base_sha" ]; then
          cat "$tmp/push.err" >&2
          rm -rf "$tmp"
          echo "land_context: push to origin/$base rejected, and not by a concurrent push" >&2
          return 1
        fi
        ;;
      *)  rm -rf "$tmp"; return 1 ;;
    esac
  done
  rm -rf "$tmp"
  echo "land_context: lost the race to origin/$base $LAND_PUSH_ATTEMPTS times" >&2
  return 1
}
