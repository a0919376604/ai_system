#!/usr/bin/env bash
# ship-workflow/lib/merge-mode.sh
# How Phase 7 lands a shipped branch: squash-merge it locally, or push it and
# open a merge/pull request for review.
#
# Default is `squash`, the behaviour every repo had before this existed. A repo
# opts in with `merge_mode: mr` in .claude/ship-config.yml.
#
# An unrecognised value falls back to squash but says so on stderr: silently
# merging to main when the operator asked for review is the one outcome worth
# being noisy about.

# merge_mode — echo squash|mr
merge_mode() {
  case "${SHIP_MERGE_MODE:-}" in mr|squash) echo "$SHIP_MERGE_MODE"; return 0 ;; esac
  local cfg="$(pwd)/.claude/ship-config.yml" v common
  if [ ! -f "$cfg" ]; then
    # A ship worktree may not carry the config: /ship-init --custom writes it
    # but never stages it. Reading the cwd alone then turned mr into squash
    # inside the worktree, where every mr-mode guard runs. Fall back to the
    # main checkout's copy; a config in the cwd still wins.
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
      && cfg="$(dirname "$common")/.claude/ship-config.yml"
  fi
  [ -f "$cfg" ] || { echo squash; return 0; }
  v=$(sed -n 's/^merge_mode:[[:space:]]*//p' "$cfg" | head -1 \
      | tr -d '"'"'"' \t\r')
  case "$v" in
    mr)     echo mr ;;
    squash) echo squash ;;
    '')     echo squash ;;
    *)      echo "merge_mode: unrecognised value '$v' — using squash" >&2
            echo squash ;;
  esac
}

# forge_cli — echo the CLI that talks to this repo's forge: glab|gh.
# Exit 1 when the remote is missing or unrecognised; the caller must not
# guess, because guessing wrong means pushing a branch nowhere useful.
forge_cli() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  [ -n "$url" ] || return 1
  case "$url" in
    *gitlab*)     echo glab ;;
    *github.com*) echo gh ;;
    *)            return 1 ;;
  esac
}

# forge_mr_cmd <branch> <target> <title> <bodyfile>
# Echo the command that would open the MR/PR. Echoing rather than running
# keeps it testable without a network, and lets the phase show the operator
# exactly what it is about to do.
forge_mr_cmd() {
  local branch="$1" target="$2" title="$3" body="$4" cli
  cli=$(forge_cli) || return 1
  case "$cli" in
    # glab takes the description as TEXT, not a path: there is no
    # --description-file. The first version of this invented one, and the
    # unit test asserted the invented flag — pinning the assumption instead
    # of the tool. It failed the first time it was really run.
    # --no-editor keeps it non-interactive.
    glab) printf 'glab mr create --source-branch %s --target-branch %s --title %s --description "$(cat %s)" --no-editor --remove-source-branch\n' \
            "$branch" "$target" "'$title'" "$body" ;;
    gh)   printf 'gh pr create --head %s --base %s --title %s --body-file %s\n' \
            "$branch" "$target" "'$title'" "$body" ;;
  esac
}

_sn_mr_iid() {
  local iid
  iid=$(printf '%s\n' "$1" | sed -nE 's@.*/merge_requests/([0-9]+)([/?#].*)?$@\1@p')
  [ -n "$iid" ] || { echo "WARN: no MR iid in $1 — auto-merge not set" >&2; return 1; }
  printf '%s\n' "$iid"
}

# forge_automerge_cmd <url> — echo the forge command without running it.
forge_automerge_cmd() {
  local cli iid
  cli=$(forge_cli) || return 1
  case "$cli" in
    glab) iid=$(_sn_mr_iid "$1") || return 1
          case "${2:-}" in *[!0-9a-f]*) echo "WARN: not a commit sha: $2" >&2; return 1 ;; esac
          # `glab mr merge --auto-merge` sends `auto_merge`, which GitLab < 17.11 ignores
          # and merges at once (R-023: line-oa 16.11.3 merged !311 mid-pipeline). The
          # merge API takes the 16.x name and the 17.11+ name side by side.
          printf 'glab api --method PUT projects/:id/merge_requests/%s/merge --field merge_when_pipeline_succeeds=true --field auto_merge=true --field squash=true%s\n' \
            "$iid" "${2:+ --raw-field sha=$2}" ;;
    gh) printf 'gh pr merge %s --auto --squash\n' "$1" ;;
    *) return 1 ;;
  esac
}
