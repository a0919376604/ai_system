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
  local cfg="$(pwd)/.claude/ship-config.yml" v
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
