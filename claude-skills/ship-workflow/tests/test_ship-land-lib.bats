#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ship-land-lib)"
  cd "$SCRATCH"
  git init -q --bare -b main origin.git
  git init -q -b main work
  cd work
  git config user.email t@t
  git config user.name t
  printf '%s\n' '- **Old** — kept' > CONTEXT.md
  git add -A && git commit -q -m base
  git remote add origin "$SCRATCH/origin.git"
  git push -q origin main
  mkdir -p "$SCRATCH/bin"
  printf '#!/bin/sh\nexit 1\n' > "$SCRATCH/bin/glab"
  cp "$SCRATCH/bin/glab" "$SCRATCH/bin/gh"
  chmod +x "$SCRATCH/bin/"*
  export PATH="$SCRATCH/bin:$PATH"
  source "$SHIP_LIB/ship-land.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "land_is_merged: false for a branch with commits not in base" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m work
  git checkout -q main
  run land_is_merged ship/R-1-x main
  [ "$status" -ne 0 ]
}

@test "land_is_merged: true once the branch tip is in base" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m work
  git checkout -q main
  git merge -q --no-ff ship/R-1-x -m "Merge R-1"
  git push -q origin main
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_worktree_for_branch: finds the worktree of a branch" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/ship worktree"
  run land_worktree_for_branch ship/R-1-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$SCRATCH/ship worktree" && pwd -P)" ]
  run land_worktree_for_branch nope
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "land_is_merged: a forge-reported merge counts even when the tip is not in origin/<base>" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m work
  export MERGED_TIP=$(git rev-parse HEAD)
  git push -q origin "$MERGED_TIP:refs/merge-requests/7/head"
  forge_cli() { echo glab; }
  cat > "$SCRATCH/bin/glab" <<'EOF'
#!/bin/sh
case "$*" in
  *state=merged*source_branch=ship%2FR-1-x*) printf '[{"iid":7,"sha":"%s"}]\n' "$MERGED_TIP"  ;;
  *) exit 1 ;;
esac
EOF
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_is_merged: gh reports merged" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m work
  export MERGED_TIP=$(git rev-parse HEAD)
  git push -q origin "$MERGED_TIP:refs/pull/7/head"
  forge_cli() { echo gh; }
  cat > "$SCRATCH/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  "pr list --head ship/R-1-x --base main --state merged --json number,headRefOid --jq "*) echo "7 0123456789abcdef0123456789abcdef01234567" ;;
  *) exit 1 ;;
esac
EOF
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_push: pushes when origin has not moved" {
  git worktree add -q --detach "$SCRATCH/land" origin/main
  cd "$SCRATCH/land"
  git commit -q --allow-empty -m compound
  run land_push main
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$SCRATCH/origin.git" rev-parse main)" = "$(git rev-parse HEAD)" ]
}

@test "land_push: rebases and retries when another push landed first" {
  git worktree add -q --detach "$SCRATCH/land" origin/main
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
  git -C "$SCRATCH/other" config user.email t@t
  git -C "$SCRATCH/other" config user.name t
  echo concurrent > "$SCRATCH/other/other"
  git -C "$SCRATCH/other" add other
  git -C "$SCRATCH/other" commit -q -m concurrent
  git -C "$SCRATCH/other" push -q origin main
  cd "$SCRATCH/land"
  echo compound > learning
  git add learning && git commit -q -m compound
  run land_push main
  [ "$status" -eq 0 ]
  git log --format=%s origin/main | grep -qxF concurrent
  git log --format=%s origin/main | grep -qxF compound
}

@test "land_push: a rejection that is not a race fails at once" {
  before=$(git rev-parse origin/main)
  printf '#!/bin/sh\necho attempt >> "%s/attempts"\nexit 1\n' "$SCRATCH" > "$SCRATCH/origin.git/hooks/pre-receive"
  chmod +x "$SCRATCH/origin.git/hooks/pre-receive"
  git commit -q --allow-empty -m compound
  run land_push main
  [ "$status" -eq 1 ]
  [ "$(git --git-dir="$SCRATCH/origin.git" rev-parse main)" = "$before" ]
  [ "$(wc -l < "$SCRATCH/attempts" | tr -d ' ')" -eq 1 ]
}

@test "land_resolve: prints REPO BASE BRANCH SHIP_WT LAND_WT" {
  repo=$(pwd -P)
  git worktree add -q -b ship/R-1-x "$SCRATCH/ship"
  eval "$(land_resolve R-1)"
  [ "$REPO" = "$repo" ]
  [ "$BRANCH" = "ship/R-1-x" ]
  [ "$BASE" = main ]
  [ "$SHIP_WT" = "$(cd "$SCRATCH/ship" && pwd -P)" ]
  [ "$LAND_WT" = "${TMPDIR:-/tmp}/ship-land-$(basename "$repo")-R-1/wt" ] || return 1
  eval "$(land_resolve R-9)"
  [ -z "$BRANCH" ]
}


@test "land_is_merged: refuses when the local branch has commits the merged review did not include" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  export MERGED_TIP=$(git rev-parse HEAD)
  git commit -q --allow-empty -m unreviewed
  git push -q origin "$MERGED_TIP:refs/merge-requests/7/head"
  forge_cli() { echo glab; }
  cat > "$SCRATCH/bin/glab" <<'EOF'
#!/bin/sh
printf '[{"iid":7,"sha":"%s"}]\n' "$MERGED_TIP"
EOF
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 1 ]
}

@test "land_push: a race seen through an earlier fetch still rebases" {
  git worktree add -q --detach "$SCRATCH/land" origin/main
  git -C "$SCRATCH/land" commit -q --allow-empty -m compound
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
  git -C "$SCRATCH/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m concurrent
  git -C "$SCRATCH/other" push -q origin main
  git fetch -q origin
  cd "$SCRATCH/land"
  run land_push main
  [ "$status" -eq 0 ]
  git --git-dir="$SCRATCH/origin.git" log --format=%s main | grep -qxF concurrent
  git --git-dir="$SCRATCH/origin.git" log --format=%s main | grep -qxF compound
}

@test "land_push: two lands appending to _log.md both land" {
  mkdir -p docs/learnings
  echo header > docs/learnings/_log.md
  git add docs/learnings/_log.md && git commit -q -m log
  git push -q origin main
  git worktree add -q --detach "$SCRATCH/land" origin/main
  echo second >> "$SCRATCH/land/docs/learnings/_log.md"
  git -C "$SCRATCH/land" commit -qam second
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
  echo first >> "$SCRATCH/other/docs/learnings/_log.md"
  git -C "$SCRATCH/other" -c user.name=t -c user.email=t@t commit -qam first
  (cd "$SCRATCH/other" && land_push main)
  cd "$SCRATCH/land"
  run land_push main
  [ "$status" -eq 0 ]
  git --git-dir="$SCRATCH/origin.git" show main:docs/learnings/_log.md | grep -qxF first
  git --git-dir="$SCRATCH/origin.git" show main:docs/learnings/_log.md | grep -qxF second
}

@test "land_resolve: REPO is the main checkout even when run from a worktree" {
  repo=$(pwd -P)
  git worktree add -q -b ship/R-1-x "$SCRATCH/ship"
  cd "$SCRATCH/ship"
  eval "$(land_resolve R-1)"
  [ "$REPO" = "$repo" ]
}

@test "land_resolve: SHIP_WT is blank when the branch is checked out in the main checkout" {
  git checkout -q -b ship/R-1-x
  eval "$(land_resolve R-1)"
  [ -z "$SHIP_WT" ]
}

@test "land_resolve: LAND_WT includes the repo name" {
  repo=$(pwd -P)
  eval "$(land_resolve R-1)"
  [ "$LAND_WT" = "${TMPDIR:-/tmp}/ship-land-$(basename "$repo")-R-1/wt" ]
}

@test "land_is_merged (glab): merged head that is a child of the local tip counts" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  git checkout -q --detach
  git commit -q --allow-empty -m suggestion
  export MERGED_TIP=$(git rev-parse HEAD)
  git push -q origin "$MERGED_TIP:refs/merge-requests/7/head"
  forge_cli() { echo glab; }
  cat > "$SCRATCH/bin/glab" <<'EOF'
#!/bin/sh
printf '[{"iid":7,"sha":"%s"}]\n' "$MERGED_TIP"
EOF
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_is_merged (gh): merged PR head that contains the tip counts" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  git checkout -q --detach
  git commit -q --allow-empty -m suggestion
  git push -q origin HEAD:refs/pull/7/head
  forge_cli() { echo gh; }
  cat > "$SCRATCH/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  "pr list --head ship/R-1-x --base main --state merged --json number,headRefOid --jq "*) echo "7 0123456789abcdef0123456789abcdef01234567" ;;
  *) exit 1 ;;
esac
EOF
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_is_merged (glab): a milestone iid in the JSON is not read as a review" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  export MERGED_TIP=$(git rev-parse HEAD)
  git push -q origin HEAD:refs/merge-requests/7/head
  forge_cli() { echo glab; }
  cat > "$SCRATCH/bin/glab" <<'EOF'
#!/bin/sh
printf '[{"iid":7,"milestone":{"iid":99},"sha":"%s"}]\n' "$MERGED_TIP"
EOF
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_push: a rebase conflict prints how to retry" {
  mkdir -p docs/product
  echo original > docs/product/ROADMAP.md
  git add docs/product/ROADMAP.md && git commit -q -m roadmap
  git push -q origin main
  git worktree add -q --detach "$SCRATCH/land" origin/main
  echo second > "$SCRATCH/land/docs/product/ROADMAP.md"
  git -C "$SCRATCH/land" commit -qam second
  echo first > docs/product/ROADMAP.md
  git commit -qam first
  git push -q origin main
  before=$(git rev-parse origin/main)
  cd "$SCRATCH/land"
  bats_require_minimum_version 1.5.0
  run --separate-stderr land_push main
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"re-run /ship-land"* ]] || return 1
  [[ "$stderr" == *"git worktree remove --force"* ]] || return 1
  [[ "$stderr" == *"$(git rev-parse --show-toplevel)"* ]] || return 1
  [ "$(git --git-dir="$SCRATCH/origin.git" rev-parse main)" = "$before" ]
}

@test "land_is_merged (glab): the API head sha counts when GitLab has dropped the MR ref" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  git checkout -q --detach
  git commit -q --allow-empty -m suggestion
  export MERGED_TIP=$(git rev-parse HEAD)
  # no refs/merge-requests/* on origin: GitLab cleans them up after a while (R-011)
  forge_cli() { echo glab; }
  cat > "$SCRATCH/bin/glab" <<'EOF2'
#!/bin/sh
printf '[{"iid":7,"sha":"%s"}]\n' "$MERGED_TIP"
EOF2
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_is_merged (gh): the API headRefOid counts when refs/pull is gone" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  export MERGED_TIP=$(git rev-parse HEAD)
  forge_cli() { echo gh; }
  cat > "$SCRATCH/bin/gh" <<'EOF2'
#!/bin/sh
case "$*" in
  *"--state merged"*headRefOid*) echo "7 $MERGED_TIP" ;;
  *) exit 1 ;;
esac
EOF2
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_is_merged (glab): an API sha that is not a local commit, with no ref, is not proof" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  forge_cli() { echo glab; }
  cat > "$SCRATCH/bin/glab" <<'EOF2'
#!/bin/sh
printf '[{"iid":7,"sha":"%s"}]\n' 0123456789abcdef0123456789abcdef01234567
EOF2
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 1 ]
}

@test "zsh: land_is_merged reads every merged MR, not just the first" {
  git checkout -q -b ship/R-1-x
  git commit -q --allow-empty -m reviewed
  export MERGED_TIP=$(git rev-parse HEAD)
  cat > "$SCRATCH/bin/glab" <<'EOF2'
#!/bin/sh
printf '[{"iid":6,"sha":"0123456789abcdef0123456789abcdef01234567"},{"iid":7,"sha":"%s"}]\n' "$MERGED_TIP"
EOF2
  run env SHIP_LIB="$SHIP_LIB" zsh -c 'source "$SHIP_LIB/ship-land.sh"; forge_cli() { echo glab; }; land_is_merged ship/R-1-x main; echo rc=$?'
  [ "$(printf '%s\n' "$output" | tail -1)" = "rc=0" ] || { echo "$output"; return 1; }
}
