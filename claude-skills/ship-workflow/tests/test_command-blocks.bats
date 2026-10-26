#!/usr/bin/env bats
# Executes the real bash blocks of command files in scratch repos, instead of
# grepping their text. The R-001 review found defects that only show when a
# block runs: an unset $WORKTREE making Phase 9 push the base branch, a mirror
# restore that blocks worktree removal, a lib not sourced by the block that
# calls it. A grep cannot see any of those.
load helpers

setup() {
  export SCRATCH="$(make_scratch command-blocks)"
  # Blocks source ~/.claude/skills/ship-workflow/lib/*.sh — point that at this tree.
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME/.claude/skills"
  ln -s "$SHIP_SKILL_ROOT" "$HOME/.claude/skills/ship-workflow"
  cd "$SCRATCH"
  git init -q --bare -b main origin.git
  git init -q -b main repo
  cd repo
  git config user.email t@t
  git config user.name t
  mkdir -p .claude docs/learnings docs/product
  echo 'merge_mode: mr' > .claude/ship-config.yml
  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
  echo roadmap > docs/product/ROADMAP.md
  git add -A && git commit -q -m base
  git remote add origin "$SCRATCH/origin.git"
  git push -q origin main
  export REPO="$SCRATCH/repo"
}
teardown() { rm -rf "$SCRATCH"; }

# block <command file> <start ERE> <end ERE> — the bash fences between two lines.
block() {
  S="$2" E="$3" awk '$0 ~ ENVIRON["S"] {f=1} $0 ~ ENVIRON["E"] {f=0} f' \
      "$SHIP_SKILL_ROOT/commands/$1" \
    | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
}

p9_log_block() {
  printf 'source %q\n' "$SHIP_LIB/ship-next.sh"
  echo 'sn_log "${WORKTREE:-}" "$ID" "${SHIP_LOG_ROW:-}"'
}

@test "ship-next P9 (mr): an unset WORKTREE pushes nothing and writes nothing" {
  git commit -q --allow-empty -m "local-only work on main"
  p9_log_block > "$SCRATCH/p9.sh"
  [ -s "$SCRATCH/p9.sh" ]
  origin_before=$(git ls-remote origin refs/heads/main | cut -f1)
  run env WORKTREE= ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -ne 0 ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
  [ -z "$(git status --porcelain)" ] || { echo "the base checkout was written"; return 1; }
}

@test "ship-next P9 (mr): writes the row to the worktree's .ship/ship-log-rows, commits and pushes nothing" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  mkdir -p "$SCRATCH/wt/.ship"
  git commit -q --allow-empty -m "local-only work on main"
  main_before=$(git rev-parse HEAD)
  wt_before=$(git -C "$SCRATCH/wt" rev-parse HEAD)
  origin_before=$(git ls-remote origin)
  row='| d | ship-next | R-1 | shipped | n |'
  p9_log_block > "$SCRATCH/p9.sh"
  run env WORKTREE="$SCRATCH/wt" ID=R-1 SHIP_LOG_ROW="$row" bash "$SCRATCH/p9.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SCRATCH/wt/.ship/ship-log-rows")" = "$row" ]
  [ "$(git rev-parse HEAD)" = "$main_before" ]
  [ "$(git -C "$SCRATCH/wt" rev-parse HEAD)" = "$wt_before" ]
  [ "$(git ls-remote origin)" = "$origin_before" ]
}

@test "ship-next P9 (squash): appends the row and commits it on the current branch" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  git commit -q -am "squash mode"
  p9_log_block > "$SCRATCH/p9.sh"
  run env ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "log: ship R-1" ]
  tail -1 docs/learnings/_log.md | grep -qF '| ship-next | R-1 |'
}

@test "zsh: ship-next P9 (mr) with an unset WORKTREE still pushes nothing" {
  command -v zsh >/dev/null || skip "zsh not installed"
  git commit -q --allow-empty -m "local-only work on main"
  p9_log_block > "$SCRATCH/p9.sh"
  origin_before=$(git ls-remote origin refs/heads/main | cut -f1)
  run env WORKTREE= ID=R-1 zsh "$SCRATCH/p9.sh"
  [ "$status" -ne 0 ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
}

compound_step9() { block ship-compound.md '^9\. \*\*Log \+ commit' '^10\. \*\*Report'; }

@test "ship-compound step 9 stops before committing when the learning is missing" {
  compound_step9 > "$SCRATCH/s9.sh"
  head_before=$(git rev-parse HEAD)
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head_before" ]
}

@test "ship-compound step 9 commits in a repo with no vault mirror" {
  git rm -q -r docs/product
  git commit -q -m "no vault mirror"
  echo learning > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "compound: R-1 — shipped + learning" ]
  git show --name-only --format= HEAD | grep -qxF docs/learnings/R-1-x.md
  git show --name-only --format= HEAD | grep -qxF docs/learnings/_log.md
}

@test "ship-compound step 9 appends SHIP_COMMIT_SUFFIX to the subject" {
  echo learning > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x SHIP_COMMIT_SUFFIX=" [skip ci]" bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "compound: R-1 — shipped + learning [skip ci]" ]
}

@test "ship-compound step 9 removes this ship's plan and fix-plans, not another ship's" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  cd "$SCRATCH/wt"
  mkdir -p docs/plans
  touch docs/plans/R-1-x.md docs/plans/R-1-x-review-fix-2.md docs/plans/R-2-y.md
  git add docs/plans && git commit -q -m "plans"
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  deleted=$(git show --name-status --format= HEAD | awk '$1=="D"{print $2}' | sort | tr '\n' ' ')
  [ "$deleted" = "docs/plans/R-1-x-review-fix-2.md docs/plans/R-1-x.md " ]
  [ "$(git ls-files docs/plans)" = "docs/plans/R-2-y.md" ]
}

@test "ship-compound step 9 removes a plan with uncommitted edits and logs the row once" {
  git worktree add -q --detach "$SCRATCH/wt" origin/main
  cd "$SCRATCH/wt"
  mkdir -p docs/plans
  echo plan > docs/plans/R-1-x.md
  git add docs/plans && git commit -q -m "plan"
  echo "## Execution log" >> docs/plans/R-1-x.md
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  [ -z "$(git ls-files docs/plans)" ]
  [ "$(grep -c '| ship-compound | R-1 |' docs/learnings/_log.md)" -eq 1 ]
}

@test "ship-compound step 9 removes this ship's plan, not a sibling R-1.1 plan" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  mkdir -p docs/plans docs/proposals
  echo p > docs/proposals/p.md
  touch docs/plans/R-1-x.md docs/plans/R-1.1-z.md
  git add -A && git commit -q -m "squash mode + plans"
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  [ "$(git show --name-status --format= HEAD | awk '$1=="D"{print $2}')" = "docs/plans/R-1-x.md" ]
  [ "$(git ls-files docs/plans)" = "docs/plans/R-1.1-z.md" ]
}

@test "ship-compound step 9 removes this ship's spec, brainstorm and plan, not another ship's spec" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  cd "$SCRATCH/wt"
  mkdir -p docs/specs docs/brainstorms docs/plans
  touch docs/specs/R-1-x.md docs/brainstorms/R-1-x.md docs/plans/R-1-x.md docs/specs/R-2-y.md
  git add docs && git commit -q -m "ship docs"
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  [ "$(git ls-files docs/specs docs/brainstorms docs/plans)" = "docs/specs/R-2-y.md" ]
}

@test "ship-compound step 9 mirrors the spec's latest text to the vault before removing it" {
  printf 'airos_vault: %s\nairos_projects_dir: "10 Projects"\n' "$SCRATCH/vault" > "$HOME/.claude/ship-workflow.yml"
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  cd "$SCRATCH/wt"
  mkdir -p docs/specs
  echo v1 > docs/specs/R-1-x.md
  git add docs && git commit -q -m spec
  echo v2-after-review > docs/specs/R-1-x.md
  git commit -q -am "spec edited in review"
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  VP=$("$HOME/.claude/skills/ship-workflow/lib/airos-binding.sh" project_path)
  grep -q v2-after-review "$VP/Specs/R-1-x.md"
  [ -z "$(git ls-files docs/specs)" ]
}

@test "ship-compound step 9 removes the spec with no vault configured" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  mkdir -p docs/specs docs/proposals
  echo p > docs/proposals/p.md
  echo spec > docs/specs/R-1-x.md
  git add -A && git commit -q -m "squash mode + spec"
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  [ -z "$(git ls-files docs/specs)" ]
}

@test "ship-compound step 9 skips an ignored vault mirror instead of failing" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  git rm -rq --cached docs/product && printf 'docs/product/\n' > .gitignore
  git add -A && git commit -q -m "mirror untracked and ignored"
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(git ls-files docs/product)" ]
  [ "$(git log -1 --format=%s)" = "compound: R-1 — shipped + learning" ]
}

@test "ship-compound tells a small-change-lane ship (no plan) where its inputs are" {
  sec=$(awk '/^2\. \*\*Identify the ship/,/^4\. /' "$SHIP_SKILL_ROOT/commands/ship-compound.md")
  echo "$sec" | grep -qF 'small-change lane' || { echo "steps 2-3 ignore lane ships"; return 1; }
  ! grep -qF 'No plan found' "$SHIP_SKILL_ROOT/commands/ship-compound.md"
}

land_step5() { block ship-land.md '^5\. \*\*Clean up' '^6\. \*\*Report'; }

@test "ship-land step 5 removes a worktree whose vault mirror sync dirtied" {
  # sync.sh rewrites the mirror in every working tree, and since R-001 a review
  # branch no longer commits it: tracked mirror files show as modified and new
  # ones as untracked. Neither may block the cleanup.
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  echo "synced" >> "$SCRATCH/wt/docs/product/ROADMAP.md"
  mkdir -p "$SCRATCH/wt/docs/proposals"
  echo "new proposal" > "$SCRATCH/wt/docs/proposals/R-9-proposal.md"
  land_step5 > "$SCRATCH/s5.sh"
  [ -s "$SCRATCH/s5.sh" ]
  run env ARGUMENTS=R-1 BRANCH=ship/R-1-x bash "$SCRATCH/s5.sh"
  [ "$status" -eq 0 ]
  [ ! -d "$SCRATCH/wt" ] || { echo "worktree not removed: $output"; return 1; }
  run git rev-parse --verify -q refs/heads/ship/R-1-x
  [ "$status" -ne 0 ]
}

@test "every ship-land block that calls the lib sources it — blocks do not share a shell" {
  awk '/^[[:space:]]*```bash[[:space:]]*$/{n++; f=1; next} /^[[:space:]]*```[[:space:]]*$/{f=0} f{print n": "$0}' \
    "$SHIP_SKILL_ROOT/commands/ship-land.md" > "$SCRATCH/blocks"
  for n in $(grep -E 'land_resolve|land_is_merged|land_push' "$SCRATCH/blocks" | cut -d: -f1 | sort -u); do
    grep -E "^$n: " "$SCRATCH/blocks" | grep -qF 'lib/ship-land.sh' \
      || { echo "block $n calls the lib without sourcing it"; return 1; }
  done
}

@test "ship-land's worktree guard: allows a subdirectory of the main checkout, refuses a worktree" {
  cond=$(grep -F -- '--git-common-dir' "$SHIP_SKILL_ROOT/commands/ship-land.md" | head -1 \
         | sed -e 's/^[[:space:]]*if //' -e 's/; then[[:space:]]*$//')
  [ -n "$cond" ]
  mkdir -p deep/dir
  run bash -c "cd deep/dir && $cond"
  [ "$status" -ne 0 ] || { echo "refuses a subdirectory of the main checkout"; return 1; }
  git worktree add -q -b ship/R-2-x "$SCRATCH/wt2"
  run bash -c "cd '$SCRATCH/wt2' && $cond"
  [ "$status" -eq 0 ]
}

@test "every command block that reads MERGE_MODE resolves it — blocks do not share a shell" {
  # Phase 9 step 3 once took the squash branch in mr mode because MERGE_MODE
  # was set two blocks earlier. The ship's log row then never reached its MR.
  for f in ship-next ship-compound ship-land; do
    awk '/^[[:space:]]*```bash[[:space:]]*$/{n++; f=1; next} /^[[:space:]]*```[[:space:]]*$/{f=0} f{print n": "$0}' \
      "$SHIP_SKILL_ROOT/commands/$f.md" > "$SCRATCH/blocks"
    for n in $(grep -F '$MERGE_MODE' "$SCRATCH/blocks" | cut -d: -f1 | sort -u); do
      grep -E "^$n: " "$SCRATCH/blocks" | grep -qF 'MERGE_MODE=$(merge_mode)' \
        || { echo "$f.md block $n reads MERGE_MODE without resolving it"; return 1; }
    done
  done
}

@test "ship-next P9 step 1 (mr) keeps the worktree the review still needs" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  { printf 'source %q\n' "$SHIP_LIB/ship-next.sh"; echo 'sn_cleanup "$WORKTREE" "${BRANCH:-ship/R-1-x}"'; } > "$SCRATCH/p9s1.sh"
  [ -s "$SCRATCH/p9s1.sh" ]
  run env WORKTREE="$SCRATCH/wt" bash "$SCRATCH/p9s1.sh"
  [ "$status" -eq 0 ]
  [ -d "$SCRATCH/wt" ] || { echo "removed the worktree of an open review"; return 1; }
}

@test "ship-next P9 (mr): refuses another ship's worktree left over in WORKTREE" {
  git worktree add -q -b ship/R-2-y "$SCRATCH/wt-other"
  p9_log_block > "$SCRATCH/p9.sh"
  run env WORKTREE="$SCRATCH/wt-other" ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -ne 0 ]
  run git ls-remote --exit-code origin refs/heads/ship/R-2-y
  [ "$status" -ne 0 ] || { echo "R-1's row was pushed to R-2's review"; return 1; }
}

@test "ship-land step 5 never cleans the operator's own checkout" {
  # If the ship branch is checked out in the main checkout, the worktree lookup
  # resolves to the main checkout itself; cleaning there deletes the operator's
  # untracked files.
  git checkout -q -b ship/R-1-x
  mkdir -p docs/proposals
  echo "operator draft" > docs/proposals/draft.md
  land_step5 > "$SCRATCH/s5.sh"
  run env ARGUMENTS=R-1 BRANCH=ship/R-1-x bash "$SCRATCH/s5.sh"
  [ -f docs/proposals/draft.md ] || { echo "cleaned the operator's checkout"; return 1; }
}

# --- R-003: the Phase 6 security pass -----------------------------------------

sec_pass_block()  { block ship-next.md '^1\.5\. \*\*Security pass' '^1\.6\. \*\*Check the security report'; }
sec_check_block() { block ship-next.md '^1\.6\. \*\*Check the security report' '^2\. \*\*Loop'; }
pre_block()       { block ship-next.md '^4\.5\. \*\*Pre-existing findings' '^## Phase 7'; }

@test "ship-next P6 security pass: refuses to run with ORIG_BRANCH unset" {
  sec_pass_block > "$SCRATCH/s15.sh"
  [ -s "$SCRATCH/s15.sh" ]
  run env ID=R-T1 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -ne 0 ]
  [ ! -e .ship/security-review-prompt.md ] || { echo "rendered without a base"; return 1; }
}

@test "ship-next P6 security pass: renders the prompt against the base branch" {
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T2 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 0 ]
  grep -qF 'git diff main...HEAD' .ship/security-review-prompt.md
  rm -f /tmp/ship-next-security-R-T2-1.md
}

@test "ship-next P6 security pass: switched off on the base branch, it reports no findings" {
  echo 'security_review: off' >> .claude/ship-config.yml
  git commit -q -am "review off"
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T3 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 0 ]
  [ "$(cat /tmp/ship-next-security-R-T3-1.md)" = "No security findings." ]
  [ ! -e .ship/security-review-prompt.md ]
  rm -f /tmp/ship-next-security-R-T3-1.md
}

@test "ship-next P6 security pass: a stale skill checkout halts instead of skipping" {
  # The lib is present but its template is not — what a checkout from before
  # R-003 plus a half-synced lib looks like. Skipping would make the gate vanish.
  mkdir -p "$SCRATCH/stale/.claude/skills/ship-workflow/lib"
  cp "$SHIP_SKILL_ROOT/lib/security-review.sh" "$SCRATCH/stale/.claude/skills/ship-workflow/lib/"
  sec_pass_block > "$SCRATCH/s15.sh"
  run env HOME="$SCRATCH/stale" ORIG_BRANCH=main ID=R-T4 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not skipping it"* ]] || return 1
  rm -f /tmp/ship-next-security-R-T4-1.md
}

@test "ship-next P6 security check: an upstream-format report is rejected, a clean one passes" {
  sec_check_block > "$SCRATCH/s16.sh"
  [ -s "$SCRATCH/s16.sh" ]
  printf 'No findings.\n' > "$SCRATCH/rev.md"
  printf '%s\n' '# Vuln 1: XSS: `a.py:1`' '* Severity: High' > /tmp/ship-next-security-R-T5-1.md
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 3 ]
  echo "No security findings." > /tmp/ship-next-security-R-T5-1.md
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 0 ]
  rm -f /tmp/ship-next-security-R-T5-1.md
}

@test "ship-next P6 pre-existing step: already-tracked defects are not filed again" {
  mkdir -p docs/ideas
  echo 'flat prompt (pre-existing-key: p.py:prompt_injection)' > docs/ideas/IDEA-001-x.md
  printf '%s\n' '🔴 [blocking] [pre-existing] [security:prompt_injection] p.py:3 — flat prompt' > "$SCRATCH/sec.md"
  printf '%s\n' '🟡 [important] [pre-existing] q.py:9 — Retry loop never backs off' \
                 '🔴 [blocking] r.py:2 — a new finding that quotes the [pre-existing] tag' > "$SCRATCH/rev.md"
  pre_block > "$SCRATCH/s45.sh"
  [ -s "$SCRATCH/s45.sh" ]
  run env REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" bash "$SCRATCH/s45.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already tracked: p.py:prompt_injection"* ]] || return 1
  [[ "$output" == *"new pre-existing: q.py:retry loop never backs off"* ]] || return 1
  [[ "$output" != *"r.py"* ]] || { echo "a quoted tag was treated as pre-existing"; return 1; }
}

# --- R-003 review round 1 ------------------------------------------------------

@test "ship-next P6 security pass: a stale report from an earlier run is removed first" {
  # Otherwise a leftover "No security findings." passes 1.6 for a pass that never ran.
  echo "No security findings." > /tmp/ship-next-security-R-T6-1.md
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T6 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 0 ]
  [ ! -e /tmp/ship-next-security-R-T6-1.md ] || { echo "stale report survived"; return 1; }
  printf 'No findings.\n' > "$SCRATCH/rev.md"
  sec_check_block > "$SCRATCH/s16.sh"
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T6 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 3 ]
}

@test "ship-next P6 security pass: a missing lib halts — it is not reported as switched off" {
  mkdir -p "$SCRATCH/nolib/.claude/skills/ship-workflow/lib"
  sec_pass_block > "$SCRATCH/s15.sh"
  run env HOME="$SCRATCH/nolib" ORIG_BRANCH=main ID=R-T7 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib is missing"* ]] || return 1
  [[ "$output" != *"security review: off"* ]] || { echo "reported as off"; return 1; }
  [ ! -e /tmp/ship-next-security-R-T7-1.md ]
}

@test "ship-next P6 security pass: records whether the review ran, for the landed commit" {
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T8 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$(cat .ship/security-review-state)" = "on" ]
  echo 'security_review: off' >> .claude/ship-config.yml
  git commit -q -am "review off"
  run env ORIG_BRANCH=main ID=R-T8 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$(cat .ship/security-review-state)" = "off" ]
  rm -f /tmp/ship-next-security-R-T8-1.md
}

@test "ship-next P6 security check: a pre-existing tag the base branch cannot back is removed" {
  printf 'No findings.\n' > "$SCRATCH/rev.md"
  printf '%s\n' '🔴 [blocking] [pre-existing] [security:command_injection] brand-new.sh:1 — x' \
                '   Base evidence: brand-new.sh:1 exists unchanged on main' > /tmp/ship-next-security-R-T9-1.md
  sec_check_block > "$SCRATCH/s16.sh"
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T9 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 0 ]
  head -1 /tmp/ship-next-security-R-T9-1.md | grep -qF '🔴 [blocking] [security:command_injection] brand-new.sh:1' || return 1
  rm -f /tmp/ship-next-security-R-T9-1.md
}

# --- R-003 review round 2 ------------------------------------------------------

major_block()      { block ship-next.md '^4\. \*\*Major findings handling' '^4\.5\. \*\*Pre-existing findings'; }
p9_capture_block() { printf 'source %q\n' "$SHIP_LIB/ship-next.sh"; echo 'sn_capture "$WORKTREE" "$ID"'; }

@test "ship-next P6 step 4: files every major from both reports, never a pre-existing finding's detail line" {
  printf '%s\n' '🟡 [important] [pre-existing] old.sh:1 — old defect' \
                '   Base evidence: old.sh:1 exists unchanged on main' \
                '   Fix: later' \
                '🟡 [important] a.sh:2 — first new major' > "$SCRATCH/rev.md"
  printf '%s\n' '🟡 [important] [security:xss] b.sh:3 — second new major' \
                '   Exploit scenario: y' > "$SCRATCH/sec.md"
  # /ship-idea is a slash command, not a program: record what the block would file.
  { echo 'ship_idea() { printf "%s\n" "$2" >> "$SCRATCH/ideas.txt"; }'
    major_block | sed 's#/ship-idea #ship_idea #'; } > "$SCRATCH/s4.sh"
  printf '%s\n' 'No spec gaps.' > "$SCRATCH/spec.md"
  run env SPEC_OUT="$SCRATCH/spec.md" AUTO=1 MAJOR_COUNT=2 REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" \
      WORKTREE="$REPO" ID=R-T10 bash "$SCRATCH/s4.sh"
  grep -qF 'a.sh:2 — first new major' "$SCRATCH/ideas.txt" || { cat "$SCRATCH/ideas.txt"; return 1; }
  grep -qF 'b.sh:3 — second new major' "$SCRATCH/ideas.txt" || { cat "$SCRATCH/ideas.txt"; return 1; }
  if grep -qF 'Base evidence' "$SCRATCH/ideas.txt"; then echo "filed a detail line as a major"; return 1; fi
}

@test "ship-next P9: the security-review state is captured before the worktree is removed" {
  mkdir -p "$SCRATCH/wt/.ship" && echo off > "$SCRATCH/wt/.ship/security-review-state"
  p9_capture_block > "$SCRATCH/p90.sh"
  run env WORKTREE="$SCRATCH/wt" ID=R-T11 bash "$SCRATCH/p90.sh"
  [ "$status" -eq 0 ]
  rm -rf "$SCRATCH/wt"   # step 1 removes the worktree
  # Step 4 is its own block, so its own shell: a variable set in step 0 is gone.
  { printf 'source %q\n' "$SHIP_LIB/ship-next.sh"; echo 'sn_summary "$WORKTREE" "$ID"'; } > "$SCRATCH/p94.sh"
  run env AUTO=1 WORKTREE="$SCRATCH/wt" ID=R-T11 ORIG_BRANCH=main bash "$SCRATCH/p94.sh"
  rm -f /tmp/ship-R-T11-security-review-state /tmp/ship-R-T11-state.env
  [[ "$output" == *"off (ship-config on main)"* ]]
}

@test "ship-init step 1 ignores flags when picking the target" {
  block ship-init.md '^1\. \*\*Resolve target directory' '^2\. ' \
    | sed '/^ *ARG=/q' > "$SCRATCH/s1-block.sh"
  sed "1i\\
ARGUMENTS='--upgrade /tmp/x'
" "$SCRATCH/s1-block.sh" > "$SCRATCH/s1.sh"
  printf '%s\n' 'printf '\''%s'\'' "$ARG"' >> "$SCRATCH/s1.sh"
  run bash "$SCRATCH/s1.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/x" ]

  sed "1i\\
ARGUMENTS='--upgrade'
" "$SCRATCH/s1-block.sh" > "$SCRATCH/s1.sh"
  printf '%s\n' 'printf '\''%s'\'' "$ARG"' >> "$SCRATCH/s1.sh"
  run bash "$SCRATCH/s1.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}


# Each shell gets an independent checkout; no shared fixture is changed.
land_case() {
  export TMPDIR="$SCRATCH/tmp-$1"
  mkdir -p "$TMPDIR"
  git clone -q "$SCRATCH/origin.git" "$SCRATCH/repo-$1"
  cd "$SCRATCH/repo-$1"
  git config user.email t@t
  git config user.name t
  git worktree add -q -b ship/R-1-x "$SCRATCH/ship-$1"
  source "$SHIP_LIB/ship-land.sh"
  eval "$(land_resolve R-1)"
}

@test "ship-land step 4 refuses to push when the land worktree has no compound commit for the ID" {
  for shell in bash zsh; do
    land_case "$shell"
    git worktree add -q --detach "$LAND_WT" origin/main
    before=$(git --git-dir="$SCRATCH/origin.git" rev-parse main)
    block ship-land.md '^4\. \*\*Push' '^5\. ' > "$SCRATCH/s4.sh"
    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s4.sh"
    [ "$status" -ne 0 ]
    [ "$(git --git-dir="$SCRATCH/origin.git" rev-parse main)" = "$before" ]
  done
}

@test "ship-land step 5 removes a ship worktree that still holds .ship/" {
  for shell in bash zsh; do
    land_case "$shell"
    mkdir -p "$SHIP_WT/.ship"
    echo draft > "$SHIP_WT/.ship/learning-draft.md"
    land_step5 > "$SCRATCH/s5.sh"
    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s5.sh"
    [ "$status" -eq 0 ]
    [ ! -d "$SHIP_WT" ]
    run git rev-parse --verify -q refs/heads/ship/R-1-x
    [ "$status" -ne 0 ]
  done
}

@test "ship-land step 3 replays every deferred row" {
  for shell in bash zsh; do
    land_case "$shell"
    mkdir -p "$SHIP_WT/.ship"
    printf '%s\n' 'idea row' 'ship row' > "$SHIP_WT/.ship/ship-log-rows"
    block ship-land.md '^3\. \*\*Compound' '^4\. ' > "$SCRATCH/s3.sh"
    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s3.sh"
    [ "$status" -eq 0 ]
    [ "$(tail -2 "$LAND_WT/docs/learnings/_log.md")" = "$(printf '%s\n' 'idea row' 'ship row')" ]
  done
}

@test "ship-land step 3 warns when the ship worktree is gone" {
  for shell in bash zsh; do
    land_case "$shell"
    git worktree remove "$SHIP_WT"
    block ship-land.md '^3\. \*\*Compound' '^4\. ' > "$SCRATCH/s3.sh"
    run env ARGUMENTS=R-1 "$shell" -c '"$0" "$1" 2>"$2"' "$shell" "$SCRATCH/s3.sh" "$SCRATCH/stderr"
    [ "$status" -eq 0 ]
    grep -qF WARN "$SCRATCH/stderr"
  done
}

@test "ship-land step 3 refuses to discard a land worktree that has unpushed commits" {
  for shell in bash zsh; do
    land_case "$shell"
    git worktree add -q --detach "$LAND_WT" origin/main
    git -C "$LAND_WT" commit -q --allow-empty -m 'compound: R-1 — shipped + learning'
    before=$(git -C "$LAND_WT" rev-parse HEAD)
    block ship-land.md '^3\. \*\*Compound' '^4\. ' > "$SCRATCH/s3.sh"
    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s3.sh"
    [ "$status" -ne 0 ]
    [ "$(git -C "$LAND_WT" rev-parse HEAD)" = "$before" ]
    [[ "$output" == *"push it with step 4 or remove it by hand"* ]] || return 1
  done
}

@test "ship-land skips to cleanup when origin/<base> already has the compound commit" {
  for shell in bash zsh; do
    land_case "$shell"
    git commit -q --allow-empty -m 'compound: R-1 — shipped + learning'
    git push -q origin main
    block ship-land.md '^1\. \*\*Resolve' '^2\. ' > "$SCRATCH/s1.sh"
    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s1.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already compounded"* ]] || return 1
    [[ "$output" == *"go to step 5"* ]] || return 1
  done
}

@test "ship-compound step 9 stages the whole vault mirror" {
  for shell in bash zsh; do
    echo old > docs/product/VISION.md
    git add docs/product/VISION.md && git commit -q -m vision
    echo refreshed-roadmap >> docs/product/ROADMAP.md
    echo refreshed-vision >> docs/product/VISION.md
    echo learning > docs/learnings/R-1-x.md
    compound_step9 > "$SCRATCH/s9.sh"
    run env ID=R-1 slug=x "$shell" "$SCRATCH/s9.sh"
    [ "$status" -eq 0 ] || return 1
    [ -z "$(git status --porcelain docs/product)" ] || return 1
  done
}

@test "ship-compound step 7 leaves an already Done row alone" {
  run sed -n '/^7\. /,/^7b\. /p' "$SHIP_SKILL_ROOT/commands/ship-compound.md"
  [[ "$output" == *'If the `${ID}` row is already under "✅ Done" (a re-run of `/ship-land`), leave the ROADMAP as it is.'* ]]
}

@test "ship-next P1 warns when the ship would land off the default branch" {
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git checkout -q -b x
  block ship-next.md '^6\. \*\*Compute worktree path' '^7\. \*\*Detect existing worktree' > "$SCRATCH/p1.sh"
  for shell in bash zsh; do
    run env ID=R-1 SLUG=x "$shell" -c 'source "$1" 2>"$2"' -- "$SCRATCH/p1.sh" "$SCRATCH/warn"
    [ "$status" -eq 0 ]
    grep -qE "WARN:.*'x'.*'main'" "$SCRATCH/warn"
  done
}

@test "ship-next P1 does not fail when the landing branch needs no warning" {
  block ship-next.md '^6\. \*\*Compute worktree path' '^7\. \*\*Detect existing worktree' > "$SCRATCH/p1.sh"
  for shell in bash zsh; do
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    run env ID=R-1 SLUG=x "$shell" "$SCRATCH/p1.sh"
    [ "$status" -eq 0 ]
    git symbolic-ref --delete refs/remotes/origin/HEAD
    run env ID=R-1 SLUG=x "$shell" "$SCRATCH/p1.sh"
    [ "$status" -eq 0 ]
  done
}

@test "ship-next --discard deletes that ship's status file, not a sibling's" {
  vault=$(make_fake_airos "$SCRATCH" repo)
  write_global_config "$HOME" "$vault"
  st="$vault/10 Projects/repo/ship-status"
  mkdir -p "$st"
  echo '{}' > "$st/R-1.json"
  echo '{}' > "$st/R-10.json"
  git worktree add -q -b ship/R-1-x "$SCRATCH/repo-worktrees/R-1-x"
  block ship-next.md '^1\. \*\*Handle `--discard`' '^1\.6\. ' > "$SCRATCH/d.sh"
  [ -s "$SCRATCH/d.sh" ]
  run env MODE=discard TARGET=R-1 bash "$SCRATCH/d.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$st/R-1.json" ]
  [ -e "$st/R-10.json" ]
}

@test "ship-land step 4 records the ship as done once the compound is pushed" {
  for shell in bash zsh; do
    land_case "$shell"
    vault=$(make_fake_airos "$SCRATCH" "repo-$shell")
    write_global_config "$HOME" "$vault"
    git worktree add -q --detach "$LAND_WT" origin/main
    git -C "$LAND_WT" commit -q --allow-empty -m 'compound: R-1 — shipped + learning'
    block ship-land.md '^4\. \*\*Push' '^5\. ' > "$SCRATCH/s4.sh"
    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s4.sh"
    [ "$status" -eq 0 ] || { echo "$shell: $output"; return 1; }
    [ "$(jq -r .phase "$vault/10 Projects/repo-$shell/ship-status/R-1.json")" = done ] || return 1
  done
}

@test "ship-next --discard deletes the status file even when the worktree is already gone" {
  vault=$(make_fake_airos "$SCRATCH" repo)
  write_global_config "$HOME" "$vault"
  st="$vault/10 Projects/repo/ship-status"
  mkdir -p "$st"
  echo '{}' > "$st/R-1.json"
  echo '{}' > "$vault/10 Projects/repo/x.json"
  block ship-next.md '^1\. \*\*Handle `--discard`' '^1\.6\. ' > "$SCRATCH/d.sh"
  run env MODE=discard TARGET=R-1 bash "$SCRATCH/d.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"No worktree found for R-1"* ]] || return 1
  [ ! -e "$st/R-1.json" ] || return 1
  run env MODE=discard TARGET=../x bash "$SCRATCH/d.sh"
  [ -e "$vault/10 Projects/repo/x.json" ]
}

# R-013 review 2: the block runs in a fresh shell; it must not write a state with an
# empty plan, and the cap must still stop the loop.
@test "ship-next P5 record-the-round block, in a fresh shell, keeps the plan and stops at the cap" {
  WT="$SCRATCH/wt"
  vault=$(make_fake_airos "$SCRATCH" wt)
  write_global_config "$HOME" "$vault"
  echo report > "$SCRATCH/report.md"
  block ship-next.md '^     Record the round, then relaunch or stop:' '^     On `relaunch`' > "$SCRATCH/r.sh"
  [ -s "$SCRATCH/r.sh" ]
  for shell in bash zsh; do
    for start in 0 2; do
      rm -rf "$WT" "$vault/10 Projects/wt/ship-status"
      mkdir -p "$WT/.ship"
      printf 'ID=R-9\nSLUG=x\nBRANCH=ship/R-9-x\nCODEX_REPORT=%s\n' "$SCRATCH/report.md" > "$WT/.ship/state.env"
      printf 'plan: docs/plans/R-9-x.md\nslot: R-9-x_\nattempt: %s\nlast_verdict: blocked\n' "$start" > "$WT/.ship/codex-supervise.md"
      run env WORKTREE="$WT" CODEX_CLASS="plan defect" CODEX_NOTE=n CODEX_BLOCKED_AT="Task 1" \
        "$shell" -c 'source "$1"; echo "ROUTE=$CODEX_ROUTE"' -- "$SCRATCH/r.sh"
      [[ "$output" != *"integer expression"* ]] || { echo "$shell: $output"; return 1; }
      grep -qxF 'plan: docs/plans/R-9-x.md' "$WT/.ship/codex-supervise.md" || { echo "$shell: plan lost"; return 1; }
      grep -qxF 'slot: R-9-x_' "$WT/.ship/codex-supervise.md" || return 1
      grep -qxF "attempt: $((start + 1))" "$WT/.ship/codex-supervise.md" || { cat "$WT/.ship/codex-supervise.md"; return 1; }
      if [ "$start" -eq 2 ]; then
        [[ "$output" == *"ROUTE=stop_exhausted"* ]] || { echo "$shell: $output"; return 1; }
        [ "$(jq -r .phase "$vault/10 Projects/wt/ship-status/R-9.json")" = blocked ] || return 1
      else
        [[ "$output" == *"ROUTE=relaunch"* ]] || { echo "$shell: $output"; return 1; }
      fi
    done
  done
}

@test "ship-next P9 (squash): the log row carries spec_gaps" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  git commit -q -am "squash mode"
  mkdir -p "$SCRATCH/wt/.ship"
  source "$SHIP_LIB/ship-next.sh"
  sn_state_set "$SCRATCH/wt" SPEC_GAPS_FOUND 2
  p9_log_block > "$SCRATCH/p9.sh"
  run env WORKTREE="$SCRATCH/wt" ID=R-T16 bash "$SCRATCH/p9.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  command grep -qF 'ponytail=0, spec_gaps=2' docs/learnings/_log.md
}

@test "ship-next P9: the auto summary reports the spec gaps" {
  mkdir -p "$SCRATCH/wt/.ship"
  source "$SHIP_LIB/ship-next.sh"
  sn_state_set "$SCRATCH/wt" SPEC_GAPS_FOUND 2
  { printf 'source %q\n' "$SHIP_LIB/ship-next.sh"; echo 'sn_summary "$WORKTREE" "$ID"'; } > "$SCRATCH/p94.sh"
  run env WORKTREE="$SCRATCH/wt" ID=R-T16 AUTO=1 bash "$SCRATCH/p94.sh"
  rm -f /tmp/ship-R-T16-*
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"spec review: 2 gap(s) found on attempt 1, all closed"* ]]
}

rows_block() { block ship-refactor-scan.md '^3\. \*\*Write rows' '^4\. \*\*Report back'; }

@test "ship-refactor-scan step 3: syncs, writes the rows file into the vault ROADMAP's Next, mirrors it (AC-10c)" {
  vault=$(make_fake_airos "$SCRATCH" repo)
  printf 'airos_vault: %s\nairos_projects_dir: "10 Projects"\n' "$vault" > "$HOME/.claude/ship-workflow.yml"
  VP="$vault/10 Projects/repo"; mkdir -p "$VP/Reports"
  printf '%s\n' $'new\t1\tA 收進一個 module\tsa\toa\t' > "$VP/Reports/refactor-scan-T.rows.tsv"
  rows_block > "$SCRATCH/s3.sh"; [ -s "$SCRATCH/s3.sh" ]
  run env STAMP=T bash "$SCRATCH/s3.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  awk '/^## 🔜 Next/{f=1;next} /^## /{f=0} f' "$VP/ROADMAP.md" | grep -qF 'A 收進一個 module（報告：Reports/refactor-scan-T.html#c1）'
  grep -qF 'A 收進一個 module' docs/product/ROADMAP.md
}
@test "ship-refactor-scan: one bash block per step 0, 1, 3, 4; step 2 has none" {
  [ -n "$(block ship-refactor-scan.md '^0\. \*\*Resolve' '^1\. \*\*Read the method')" ]
  [ -n "$(block ship-refactor-scan.md '^1\. \*\*Read the method' '^2\. \*\*Pick')" ]
  [ -z "$(block ship-refactor-scan.md '^2\. \*\*Pick' '^3\. \*\*Write rows')" ]
  [ -n "$(block ship-refactor-scan.md '^4\. \*\*Report back' '^## ')" ]
}

@test "ship-refactor-scan step 3 under zsh: syncs, writes the rows file into the vault ROADMAP's Next, mirrors it (AC-10c)" {
  command -v zsh >/dev/null || skip "zsh not installed"
  vault=$(make_fake_airos "$SCRATCH" repo)
  printf 'airos_vault: %s\nairos_projects_dir: "10 Projects"\n' "$vault" > "$HOME/.claude/ship-workflow.yml"
  VP="$vault/10 Projects/repo"; mkdir -p "$VP/Reports"
  printf '%s\n' $'new\t1\tA 收進一個 module\tsa\toa\t' > "$VP/Reports/refactor-scan-T.rows.tsv"
  rows_block > "$SCRATCH/s3.sh"; [ -s "$SCRATCH/s3.sh" ]
  run env STAMP=T zsh "$SCRATCH/s3.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  awk '/^## 🔜 Next/{f=1;next} /^## /{f=0} f' "$VP/ROADMAP.md" | grep -qF 'A 收進一個 module（報告：Reports/refactor-scan-T.html#c1）'
  grep -qF 'A 收進一個 module' docs/product/ROADMAP.md
}
