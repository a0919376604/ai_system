#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch merge-mode)"
  mkdir -p "$SCRATCH/repo"; cd "$SCRATCH/repo"
  git init -q
  source "$SHIP_LIB/merge-mode.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "merge_mode: defaults to squash when there is no config" {
  run merge_mode
  [ "$output" = "squash" ]
}

@test "merge_mode: reads mr from per-repo config" {
  mkdir -p .claude; printf 'merge_mode: mr\n' > .claude/ship-config.yml
  run merge_mode
  [ "$output" = "mr" ]
}

@test "merge_mode: an unrecognised value falls back to squash, loudly" {
  mkdir -p .claude; printf 'merge_mode: yolo\n' > .claude/ship-config.yml
  # bats `run` MERGES stdout and stderr, so each stream is checked separately.
  run bash -c "source '$SHIP_LIB/merge-mode.sh'; merge_mode 2>/dev/null"
  [ "$output" = "squash" ]
  # Silent fallback would merge to main when the operator asked for review.
  run bash -c "source '$SHIP_LIB/merge-mode.sh'; merge_mode 2>&1 >/dev/null"
  [[ "$output" == *yolo* ]]
}

@test "merge_mode: tolerates quotes and trailing spaces" {
  mkdir -p .claude; printf 'merge_mode: "mr"   \n' > .claude/ship-config.yml
  run merge_mode
  [ "$output" = "mr" ]
}

@test "merge_mode: a commented-out key is not read" {
  mkdir -p .claude; printf '# merge_mode: mr\n' > .claude/ship-config.yml
  run merge_mode
  [ "$output" = "squash" ]
}

@test "forge_cli: gitlab remote selects glab" {
  git remote add origin git@gitlab.svc.langlive.tech:mct/langlive-line-oa.git
  run forge_cli
  [ "$output" = "glab" ]
}

@test "forge_cli: github remote selects gh" {
  git remote add origin git@github.com:a0919376604/ai_system.git
  run forge_cli
  [ "$output" = "gh" ]
}

@test "forge_cli: an unknown host yields nothing and exits non-zero" {
  git remote add origin git@bitbucket.org:x/y.git
  run forge_cli
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "forge_cli: no remote at all yields nothing and exits non-zero" {
  run forge_cli
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "forge_mr_cmd: builds the right command per forge without running it" {
  git remote add origin git@gitlab.svc.langlive.tech:mct/x.git
  run forge_mr_cmd "feat/x" "main" "T" "/tmp/body.md"
  [ "$status" -eq 0 ]
  [[ "$output" == glab\ mr\ create* ]] || return 1
  [[ "$output" == *--source-branch* ]] || return 1
  [[ "$output" == *--description* ]] || return 1
  [[ "$output" == *--no-editor* ]]
}

@test "forge_mr_cmd: github variant uses gh pr create" {
  git remote add origin git@github.com:a/b.git
  run forge_mr_cmd "feat/x" "main" "T" "/tmp/body.md"
  [[ "$output" == gh\ pr\ create* ]] || return 1
  [[ "$output" == *--body-file* ]]
}

@test "forge_mr_cmd: every flag it emits is one the installed CLI accepts" {
  # The reason this test exists: the glab branch emitted --description-file,
  # a flag glab does not have. The unit test asserted that same invented flag,
  # so both agreed with each other and neither agreed with the tool. It failed
  # the first time it was run for real. Check against --help, not belief.
  for forge in glab gh; do
    command -v "$forge" >/dev/null || continue
    case "$forge" in
      glab) git remote remove origin 2>/dev/null || true
            git remote add origin git@gitlab.example.com:a/b.git
            help=$(glab mr create --help 2>&1) ;;
      gh)   git remote remove origin 2>/dev/null || true
            git remote add origin git@github.com:a/b.git
            help=$(gh pr create --help 2>&1) ;;
    esac
    cmd=$(forge_mr_cmd br main T /tmp/b.md)
    for flag in $(printf '%s\n' "$cmd" | tr ' ' '\n' | grep '^--'); do
      printf '%s' "$help" | grep -qF -- "$flag" \
        || { echo "$forge does not accept $flag"; return 1; }
    done
  done
}
