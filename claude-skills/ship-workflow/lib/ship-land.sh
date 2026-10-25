#!/usr/bin/env bash
# ship-workflow/lib/ship-land.sh
# The mechanical half of /ship-land (R-008).

command -v forge_cli >/dev/null 2>&1 || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"

LAND_PUSH_ATTEMPTS=3

# land_is_merged <branch> <base> — exit 0 iff the review for <branch> merged into
# <base>. The forge is asked first: a squash merge leaves the branch tip outside
# origin/<base>, so ancestry alone reads a merged review as open (R-002). With no
# forge answer, fall back to ancestry. Exit 2 on usage.
land_is_merged() {
  local branch="$1" base="$2" tip json ids n
  [ -n "$branch" ] && [ -n "$base" ] || return 2
  # The review head must CONTAIN the local tip: equal, or with forge-side
  # commits on top ("Apply suggestion"). This keeps git branch -D from losing
  # local work. Review head refs survive --remove-source-branch.
  tip=$(git rev-parse -q --verify "$branch") || return 1
  case "$(forge_cli 2>/dev/null)" in
    glab)
      json=$(glab api "projects/:id/merge_requests?state=merged&target_branch=${base}&source_branch=$(printf '%s' "$branch" | sed 's#/#%2F#g')" 2>/dev/null)
      if command -v jq >/dev/null 2>&1; then ids=$(printf '%s' "$json" | jq -r '.[].iid' 2>/dev/null)
      else ids=$(printf '%s' "$json" | grep -oE '\{"id":[0-9]+,"iid":[0-9]+' | grep -oE '[0-9]+$'); fi
      for n in $ids; do
        git fetch -q origin "refs/merge-requests/$n/head" 2>/dev/null \
          && git merge-base --is-ancestor "$tip" FETCH_HEAD && return 0
      done ;;
    gh)
      for n in $(gh pr list --head "$branch" --base "$base" --state merged --json number --jq '.[].number' 2>/dev/null); do
        git fetch -q origin "refs/pull/$n/head" 2>/dev/null \
          && git merge-base --is-ancestor "$tip" FETCH_HEAD && return 0
      done ;;
  esac
  git merge-base --is-ancestor "$tip" "origin/$base" 2>/dev/null
}

# land_push <base> — push HEAD to origin/<base>. When another push landed first,
# rebase onto it and retry, LAND_PUSH_ATTEMPTS times. Any other rejection, or a
# rebase conflict, fails at once with nothing pushed. Exit 1 on failure, 2 on usage.
land_push() {
  local base="$1" attempt=0 err attr
  [ -n "$base" ] || return 2
  err=$(mktemp) || return 1
  while [ "$attempt" -lt "$LAND_PUSH_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    if git push -q origin "HEAD:$base" 2>"$err"; then rm -f "$err"; return 0; fi
    git fetch -q origin "$base" 2>/dev/null || { cat "$err" >&2; rm -f "$err"; return 1; }
    if git merge-base --is-ancestor "origin/$base" HEAD; then
      cat "$err" >&2; rm -f "$err"
      echo "land_push: push to origin/$base rejected, and not by a concurrent push" >&2
      return 1
    fi
    attr=$(mktemp) || { rm -f "$err"; return 1; }
    printf 'docs/learnings/_log.md merge=union\n' > "$attr"
    git -c core.attributesFile="$attr" rebase -q "origin/$base" >/dev/null 2>&1 || {
      git rebase --abort >/dev/null 2>&1; rm -f "$err" "$attr"
      echo "land_push: rebasing onto the new origin/$base conflicted — nothing pushed. Another land changed the same lines (usually the vault mirror). Retry: git worktree remove --force \"$(git rev-parse --show-toplevel)\", then re-run /ship-land." >&2
      return 1
    }
    rm -f "$attr"
  done
  rm -f "$err"
  echo "land_push: lost the race to origin/$base $LAND_PUSH_ATTEMPTS times" >&2
  return 1
}

# land_resolve <R-NNN> — print REPO BASE BRANCH SHIP_WT LAND_WT as shell
# assignments for eval. Run from the main checkout. Blocks in ship-land.md run in
# separate shells, so each one re-resolves instead of sharing variables.
land_resolve() {
  local id="$1" repo base branch wt
  [ -n "$id" ] || return 2
  repo=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
  repo=$(dirname "$repo") || return 1
  base=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  [ -n "$base" ] || base=main
  branch=$(git -C "$repo" branch --list "ship/${id}-*" --format='%(refname:short)' | head -1)
  wt=""; [ -n "$branch" ] && wt=$(cd "$repo" && land_worktree_for_branch "$branch")
  [ "$wt" != "$repo" ] || wt=""
  printf 'REPO=%q\nBASE=%q\nBRANCH=%q\nSHIP_WT=%q\nLAND_WT=%q\n' \
    "$repo" "$base" "$branch" "$wt" "${TMPDIR:-/tmp}/ship-land-$(basename "$repo")-${id}/wt"
}
# land_worktree_for_branch <branch> — echo its worktree path, or nothing when absent.
land_worktree_for_branch() { git worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{w=substr($0,10)} /^branch /{if ($2==b) print w}'; }
