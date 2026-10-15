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
  source "$SHIP_LIB/ship-land.sh"
}
teardown() { rm -rf "$SCRATCH"; }

# Put a pending file for $1 on origin/main, as a merged MR would.
merge_pending() {
  mkdir -p docs/ship-pending
  printf '%s\n' "- **Term$1** — from $1" > "docs/ship-pending/$1-context.md"
  git add -A && git commit -q -m "merge $1" && git push -q origin main
}

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
  run land_is_merged ship/R-1-x main
  [ "$status" -eq 0 ]
}

@test "land_context: nothing queued prints none and pushes nothing" {
  before=$(git ls-remote origin refs/heads/main | cut -f1)
  run land_context R-9 main
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$before" ]
}

@test "land_context: folds the queue onto origin in one [skip ci] commit" {
  merge_pending R-9
  git checkout -q --detach        # the operator's checkout must not move
  head_before=$(git rev-parse HEAD)
  run land_context R-9 main
  [ "$status" -eq 0 ]
  git fetch -q origin main
  [ "$output" = "landed $(git rev-parse origin/main)" ]
  [ "$(git log -1 --format=%s origin/main)" = "context: land R-9 [skip ci]" ]
  git show origin/main:CONTEXT.md | grep -qxF -- '- **TermR-9** — from R-9'
  git show origin/main:CONTEXT.md | grep -qxF -- '- **Old** — kept'
  run git cat-file -e origin/main:docs/ship-pending/R-9-context.md
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head_before" ]
  [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
}

@test "land_context: redoes the fold when another push wins the race" {
  merge_pending R-9
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
  git -C "$SCRATCH/other" config user.email o@o
  git -C "$SCRATCH/other" config user.name o
  # pre-push fires once: someone else lands a commit first, so our push is rejected.
  cat > .git/hooks/pre-push <<EOF
#!/bin/sh
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
[ -f "$SCRATCH/raced" ] && exit 0
touch "$SCRATCH/raced"
git -C "$SCRATCH/other" commit -q --allow-empty -m concurrent
git -C "$SCRATCH/other" push -q origin main
exit 0
EOF
  chmod +x .git/hooks/pre-push
  run land_context R-9 main
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH/raced" ] || { echo "the race never happened"; return 1; }
  git fetch -q origin main
  git log --format=%s origin/main | grep -qxF concurrent
  [ "$(git log -1 --format=%s origin/main)" = "context: land R-9 [skip ci]" ]
}

@test "land_context: a rejection that is not a lost race fails at once with git's error" {
  # e.g. a protected branch: origin/main did not move, so retrying cannot help,
  # and swallowing the error would hide the real cause.
  merge_pending R-9
  cat > .git/hooks/pre-push <<EOF
#!/bin/sh
echo attempt >> "$SCRATCH/attempts"
echo "protected branch: push refused" >&2
exit 1
EOF
  chmod +x .git/hooks/pre-push
  run land_context R-9 main
  [ "$status" -eq 1 ]
  [[ "$output" == *"protected branch: push refused"* ]] || return 1
  [ "$(wc -l < "$SCRATCH/attempts" | tr -d ' ')" -eq 1 ]
  [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
}

@test "land_context: gives up after LAND_PUSH_ATTEMPTS lost races" {
  merge_pending R-9
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
  git -C "$SCRATCH/other" config user.email o@o
  git -C "$SCRATCH/other" config user.name o
  # Every push loses: someone else lands a commit first, every time.
  cat > .git/hooks/pre-push <<EOF
#!/bin/sh
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
echo attempt >> "$SCRATCH/attempts"
git -C "$SCRATCH/other" pull -q --rebase origin main
git -C "$SCRATCH/other" commit -q --allow-empty -m concurrent
git -C "$SCRATCH/other" push -q origin main
exit 0
EOF
  chmod +x .git/hooks/pre-push
  run land_context R-9 main
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$SCRATCH/attempts" | tr -d ' ')" -eq "$LAND_PUSH_ATTEMPTS" ]
  [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
}
