#!/usr/bin/env bats
# examples/launchd-autopush/secondbrain-autopush.sh against scratch vaults (R-012).
load helpers

SCRIPT="$SHIP_SKILL_ROOT/examples/launchd-autopush/secondbrain-autopush.sh"

# Never run a script that would fall back to the real vault.
honors_overrides() {
  grep -qE '^VAULT="\$\{SECONDBRAIN_VAULT:-' "$SCRIPT" && grep -qE '^LOG="\$\{SECONDBRAIN_AUTOPUSH_LOG:-' "$SCRIPT"
}

setup() {
  export SCRATCH="$(make_scratch autopush)"
  git init -q --bare -b main "$SCRATCH/origin.git"
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/vault" 2>/dev/null
  git -C "$SCRATCH/vault" config user.email t@t; git -C "$SCRATCH/vault" config user.name t
  echo seed > "$SCRATCH/vault/note.md"
  git -C "$SCRATCH/vault" add -A && git -C "$SCRATCH/vault" commit -qm seed && git -C "$SCRATCH/vault" push -q origin main
  export SECONDBRAIN_VAULT="$SCRATCH/vault" SECONDBRAIN_AUTOPUSH_LOG="$SCRATCH/autopush.log"
}
teardown() { chmod -R u+rwx "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"; }

@test "the script lets tests point it at a scratch vault and log" {
  honors_overrides
}

@test "commits and pushes thousands of files (no SIGPIPE from head under pipefail)" {
  honors_overrides || skip "script would touch the real vault"
  mkdir -p "$SCRATCH/vault/many"
  for i in $(seq 1 3000); do echo "$i" > "$SCRATCH/vault/many/note-$i.md"; done
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { cat "$SECONDBRAIN_AUTOPUSH_LOG"; return 1; }
  grep -q 'push OK' "$SECONDBRAIN_AUTOPUSH_LOG"
  [ "$(git -C "$SCRATCH/origin.git" ls-tree -r --name-only main | grep -c '^many/')" -eq 3000 ]
}

@test "commits before pulling, so a moved origin and a local edit both land without a WARN" {
  honors_overrides || skip "script would touch the real vault"
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other" 2>/dev/null
  git -C "$SCRATCH/other" config user.email t@t; git -C "$SCRATCH/other" config user.name t
  echo remote > "$SCRATCH/other/remote.md"
  git -C "$SCRATCH/other" add -A && git -C "$SCRATCH/other" commit -qm remote && git -C "$SCRATCH/other" push -q origin main
  echo local > "$SCRATCH/vault/local.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { cat "$SECONDBRAIN_AUTOPUSH_LOG"; return 1; }
  ! grep -q 'WARN' "$SECONDBRAIN_AUTOPUSH_LOG" || { cat "$SECONDBRAIN_AUTOPUSH_LOG"; return 1; }
  files=$(git -C "$SCRATCH/origin.git" ls-tree -r --name-only main | tr '\n' ' ')
  [ "$files" = "local.md note.md remote.md " ]
}

@test "an unreadable vault exits 5 and names the macOS privacy fix" {
  honors_overrides || skip "script would touch the real vault"
  chmod 000 "$SCRATCH/vault/.git"
  run bash "$SCRIPT"
  chmod 755 "$SCRATCH/vault/.git"
  [ "$status" -eq 5 ]
  grep -q 'Files and Folders' "$SECONDBRAIN_AUTOPUSH_LOG"
}

@test "a rebase conflict aborts the rebase, pushes nothing, and never commits conflict markers" {
  honors_overrides || skip "script would touch the real vault"
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other" 2>/dev/null
  git -C "$SCRATCH/other" config user.email t@t; git -C "$SCRATCH/other" config user.name t
  echo remote-edit > "$SCRATCH/other/note.md"
  git -C "$SCRATCH/other" commit -qam remote && git -C "$SCRATCH/other" push -q origin main
  echo local-edit > "$SCRATCH/vault/note.md"
  origin_before=$(git -C "$SCRATCH/origin.git" rev-parse main)
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -d "$SCRATCH/vault/.git/rebase-merge" ] && [ ! -d "$SCRATCH/vault/.git/rebase-apply" ]
  [ "$(cat "$SCRATCH/vault/note.md")" = local-edit ]
  [ "$(git -C "$SCRATCH/origin.git" rev-parse main)" = "$origin_before" ]
  run bash "$SCRIPT"
  ! git -C "$SCRATCH/vault" log -p | grep -q '^+<<<<<<<' || { echo "conflict markers committed"; return 1; }
}

@test "a directory that is not a git repo exits 2, not the privacy error" {
  honors_overrides || skip "script would touch the real vault"
  rm -rf "$SCRATCH/vault/.git"
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
