#!/usr/bin/env bash
# PR-mode glue; review helpers remain in ship-workflow/lib.

pr_target() {
  local target="${1:-}" provider number='' base base_sha head title url='' label json remote
  case "$target" in
    '') provider=branch ;;
    https://github.com/*/pull/*) provider=github; number=${target##*/} ;;
    https://*/-/merge_requests/*) provider=gitlab; number=${target##*/} ;;
    \!*) provider=gitlab; number=${target#\!} ;;
    \#*|[0-9]*)
      number=$(printf '%s' "$target" | sed 's/^#//')
      remote=$(git remote get-url origin) || return 1
      case "$remote" in *github.com*) provider=github ;; *) provider=gitlab ;; esac ;;
    *) printf "pr_target: cannot read target '%s'\n" "$target" >&2; return 2 ;;
  esac
  if [ "$provider" != branch ]; then
    case "$number" in
      ''|*[!0-9]*) printf "pr_target: cannot read target '%s'\n" "$target" >&2; return 2 ;;
    esac
  fi
  case "$provider" in
    github)
      json=$(gh pr view "$number" --json number,title,url,baseRefName,baseRefOid,headRefOid) || return 1
      number=$(printf '%s' "$json" | jq -er '.number') || return 1
      base=$(printf '%s' "$json" | jq -er '.baseRefName') || return 1
      base_sha=$(printf '%s' "$json" | jq -er '.baseRefOid') || return 1
      head=$(printf '%s' "$json" | jq -er '.headRefOid') || return 1
      title=$(printf '%s' "$json" | jq -r '.title') || return 1
      url=$(printf '%s' "$json" | jq -r '.url') || return 1 ;;
    gitlab)
      json=$(glab mr view "$number" -F json) || return 1
      number=$(printf '%s' "$json" | jq -er '.iid') || return 1
      base=$(printf '%s' "$json" | jq -er '.target_branch') || return 1
      base_sha=$(printf '%s' "$json" | jq -er '.diff_refs.base_sha') || return 1
      head=$(printf '%s' "$json" | jq -er '.sha') || return 1
      title=$(printf '%s' "$json" | jq -r '.title') || return 1
      url=$(printf '%s' "$json" | jq -r '.web_url') || return 1 ;;
    branch)
      base=$(git symbolic-ref --short refs/remotes/origin/HEAD) || return 1
      base=${base#origin/}
      base_sha=$(git merge-base "origin/$base" HEAD) || return 1
      head=$(git rev-parse HEAD) || return 1
      title=$(git branch --show-current) || return 1 ;;
  esac
  label=${number:-${title//\//-}}
  printf '%s=%q\n' PR_PROVIDER "$provider" PR_NUMBER "$number" PR_BASE "$base" \
    PR_BASE_SHA "$base_sha" PR_HEAD "$head" PR_TITLE "$title" PR_URL "$url" PR_LABEL "$label"
}

pr_checkout() (
  local top dir
  top=$(git rev-parse --show-toplevel) || return 1
  git fetch -q origin "$PR_BASE" || return 1
  case "$PR_PROVIDER" in
    github) git fetch -q origin "pull/$PR_NUMBER/head" || return 1 ;;
    gitlab) git fetch -q origin "merge-requests/$PR_NUMBER/head" || return 1 ;;
  esac
  dir="$(dirname "$top")/$(basename "$top")-worktrees/pr-review-$PR_LABEL"
  if [ -e "$dir" ]; then
    git worktree remove --force "$dir" || return 1
  fi
  git worktree add -q --detach "$dir" "$PR_HEAD" || return 1
  # The PR is untrusted: a committed .ship/state.env would be sourced by sn_state_load,
  # a .ship/*.tmp symlink would redirect our writes, and .claude/.ship-executor would
  # switch off the codex axis, and a .codex/ config could steer codex review itself.
  # Review state is ours alone; the files stay in the diff.
  if [ -n "$(git -C "$dir" ls-files -- .ship .claude .codex)" ]; then
    printf '%s\n' 'pr_checkout: removed the PR'"'"'s own .ship/, .claude/ and .codex/ from the review worktree (still reviewed in the diff)' >&2
  fi
  rm -rf "$dir/.ship" "$dir/.claude" "$dir/.codex" || return 1
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/ship-next.sh" || return 1
  sn_state_set "$dir" ID "PR-$PR_LABEL" || return 1
  sn_state_set "$dir" SLUG review || return 1
  sn_state_set "$dir" ORIG_BRANCH "$PR_BASE_SHA" || return 1
  printf '%s\n' "$dir"
)

pr_spec() {
  local out="$1" json title body issues numbers issue
  rm -f "$out" || return 1
  case "$PR_PROVIDER" in
    branch) return 3 ;;
    github)
      json=$(gh pr view "$PR_NUMBER" --json title,body,closingIssuesReferences) || return 1
      title=$(printf '%s' "$json" | jq -r '.title') || return 1
      body=$(printf '%s' "$json" | jq -r '.body // ""') || return 1
      numbers=$(printf '%s' "$json" | jq -r '.closingIssuesReferences[]?.number') || return 1
      issues=$(printf '%s\n' "$numbers" | while IFS= read -r number; do
        [ -n "$number" ] || continue
        issue=$(gh issue view "$number" --json title,body) || return 1
        printf '%s' "$issue" | jq -r --arg n "$number" '"\n## Issue #\($n) · \(.title)\n\n\(.body // "")"' || return 1
      done) || return 1 ;;
    gitlab)
      json=$(glab mr view "$PR_NUMBER" -F json) || return 1
      title=$(printf '%s' "$json" | jq -r '.title') || return 1
      body=$(printf '%s' "$json" | jq -r '.description // ""') || return 1
      json=$(glab api "projects/:id/merge_requests/$PR_NUMBER/closes_issues") || return 1
      issues=$(printf '%s' "$json" | jq -r '.[] | "\n## Issue #\(.iid) · \(.title)\n\n\(.description // "")"') || return 1 ;;
    *) return 2 ;;
  esac
  [ -n "$body$issues" ] || return 3
  {
    printf '# %s\n\n%s\n' "$title" "$body"
    [ -z "$issues" ] || printf '%s\n' "$issues"
  } > "$out"
}

pr_report() {
  local out="$1" review="$2" spec="$3" security="$4" parsed
  local BLOCKING_COUNT MAJOR_COUNT MINOR_COUNT SPEC_GAP_COUNT SECURITY_COUNT
  local PRAISE_COUNT SEAM_VIOLATION_COUNT ASSERTION_ROULETTE_COUNT WEAK_ASSERTION_COUNT PRE_EXISTING_COUNT PONYTAIL_COUNT
  local parser="${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/code-review-parse.sh"
  if [ "$spec" = - ]; then
    parsed=$("$parser" "$review" "$security") || return 1
  else
    parsed=$("$parser" "$review" "$spec" "$security") || return 1
  fi
  eval "$parsed"
  {
    printf '# PR review · %s\n\n' "$PR_TITLE"
    printf '%s · `%s` (%s)…%s\n\n' "${PR_URL:-branch: $PR_TITLE}" "$PR_BASE" "${PR_BASE_SHA:0:8}" "${PR_HEAD:0:8}"
    if [ "$BLOCKING_COUNT" -eq 0 ]; then
      printf '**結論：可以合併**\n\n'
    else
      printf '**結論：先修 %s 個 blocking**\n\n' "$BLOCKING_COUNT"
    fi
    printf '| blocking | major | minor | spec gaps | security |\n| --- | --- | --- | --- | --- |\n'
    printf '| %s | %s | %s | %s | %s |\n' "$BLOCKING_COUNT" "$MAJOR_COUNT" "$MINOR_COUNT" "$SPEC_GAP_COUNT" "$SECURITY_COUNT"
    printf '\n## 程式碼與跨模型\n\n'
    cat "$review" || return 1
    printf '\n## Spec\n\n'
    if [ "$spec" = - ]; then
      printf '略過：沒有描述或 issue 可對照\n'
    else
      cat "$spec" || return 1
    fi
    printf '\n## 安全\n\n'
    cat "$security" || return 1
  } > "$out" || return 1
  printf '%s\n' "$out"
}

pr_comment() {
  case "$PR_PROVIDER" in
    github) gh pr comment "$PR_NUMBER" --body-file "$1" ;;
    gitlab) local report; report=$(cat "$1") || return 1
      glab mr note "$PR_NUMBER" --message "$report" ;;
    *) echo 'pr_comment: no PR/MR to comment on' >&2; return 2 ;;
  esac
}
