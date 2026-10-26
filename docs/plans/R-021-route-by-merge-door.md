# R-021 Route by merge door Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:**
- Each ship gets a door (one-way or two-way) from the spec and from mechanical diff
  signals.
- Two-way doors merge without a human. A squash repo squashes; an mr repo auto-merges
  after CI.
- One-way doors always open a review for a person.
- The body follows Pocock's Summary / Evidence / Merge Danger template.

**Architecture:**
- **lib/merge-mode.sh:** `merge_mode()` honours a per-ship `SHIP_MERGE_MODE`; new
  `forge_automerge_cmd`.
- **lib/ship-next.sh:** new `_sn_glob_match`, `_sn_one_way_paths`, `sn_door` and
  `sn_auto_merge`. `sn_land` calls `sn_auto_merge`. `sn_ship_body`, `sn_log`,
  `sn_summary` and `sn_cleanup` change.
- **Text:** ship-next.md (Phases 3, 7, 8, 9), the `templates/repo/SPEC.md` template and
  the README.

**Tech Stack:** bash and zsh (the lib is sourced from Claude Code's zsh, where `grep` is an ugrep wrapper), BSD awk, git, `jq`, `glab`/`gh` (stubbed in tests), bats.

**Spec:** `docs/specs/R-021-route-by-merge-door.md`. Read it first. Its Goals, Design, Seams and §4 Acceptance are the contract.

## Global Constraints
- **Exact state keys:** `SHIP_DOOR` (`one-way`|`two-way`), `SHIP_DOOR_REASONS` (reasons
  joined by `; `), `SHIP_MERGE_MODE` (`squash`|`mr`), `SHIP_AUTO_MERGE` (`0`|`1`),
  `SHIP_AUTO_MERGED` (`0`|`1`).
- **Exact reason prefixes:**
  - `spec: ` (the Decisions `Door:` line, or `spec: no Door line`)
  - `signal: migration <path>`
  - `signal: new dependency <name> (<file>)`
  - `signal: deploy <path>`
  - `signal: one_way_paths <path>`
- **Exact commands:**
  - `glab mr merge <url> --auto-merge --squash --yes`
  - `gh pr merge <url> --auto --squash`
- **Exact log, summary and timing strings:**
  - log row: `door=${SHIP_DOOR:-unset}`
  - summary line starts with `• door: `
  - `SN_PIPELINE_WAIT` defaults to 90, with polls every 5 s
- **Glob matching** (built-in patterns and `one_way_paths`) goes through one helper that
  behaves identically under zsh. zsh does not glob an unquoted `$var` in a `case`
  pattern. Use `bash -c 'case "$2" in $1) exit 0;; esac; exit 1' _ "<glob>" "<path>"`.
- **No glob that can match nothing in a command block** (zsh aborts), and no `$0`–`$9`
  in `commands/*.md`. Use `command grep` where an exit status matters.
- **No new dependencies.** `jq` is already required by `sn_new_deps`. Without `jq`,
  `sn_auto_merge` prints a WARN and returns 1, so it never merges.
- **Tests run scoped:** `cd claude-skills/ship-workflow && bats tests/<file>.bats`. Only
  Task 6 runs the full suite. The known `cwd-guard: exits 0 when not in a git repo at
  all` failure in a linked worktree is pre-existing.

## Review Focus
These inputs are not named in the ACs but will occur. Each has a test in the owning task.
1. A spec whose body quotes `Door: two-way` outside `## Decisions` (as this spec does),
   while its Decisions has no `Door:` line. The door is one-way, reason
   `spec: no Door line` (Task 2).
2. A `one_way_paths` entry written quoted (`- "backend/app/api/auth.py"`) and one with
   a trailing comment (`- backend/x/*.py  # pushes`). Both match (Task 2).
3. A rerun of `sn_door` after the spec changed from one-way to two-way. All four keys
   are overwritten, and the mode follows (Task 2).
4. `SHIP_AUTO_MERGE=1`, but the forge CLI fails (non-zero exit) when setting auto-merge.
   `sn_land` still exits 0 and records `SHIP_AUTO_MERGED=0` (Task 3).
5. `sn_cleanup` for a one-way ship in a squash repo. The worktree and branch are kept,
   because the mode is mr from state (Task 3).

---

### Task 1: `merge_mode` honours the per-ship mode; `forge_automerge_cmd`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/merge-mode.sh`
- Test: `claude-skills/ship-workflow/tests/test_merge-mode.bats` (append)

**Interfaces:**
- Produces: `merge_mode` returns `$SHIP_MERGE_MODE` when it is `mr` or `squash`.
- Produces: `forge_automerge_cmd <url>` echoes the command, or exits 1 for an unknown
  forge.

- [x] **Step 1: Write the failing tests.**
  - **`merge_mode: a per-ship SHIP_MERGE_MODE wins over the repo config` (AC-8).**
    - Config `merge_mode: squash` with `SHIP_MERGE_MODE=mr` gives `mr`.
    - Config `mr` with `SHIP_MERGE_MODE=squash` gives `squash`.
    - `SHIP_MERGE_MODE=bogus` gives the config value.
    - Empty `SHIP_MERGE_MODE` gives the config value.
  - **`forge_automerge_cmd: glab and gh forms`.**
    - With the origin remote set to a gitlab URL, the output is exactly
      `glab mr merge https://x/mr/1 --auto-merge --squash --yes`.
    - With a github.com URL, it is `gh pr merge https://x/pull/1 --auto --squash`.
    - With an unknown remote, the status is 1.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_merge-mode.bats`.
- [x] **Step 3: Implement.**
  - At the top of `merge_mode`: `case "${SHIP_MERGE_MODE:-}" in mr|squash) echo "$SHIP_MERGE_MODE"; return 0 ;; esac`.
  - Add `forge_automerge_cmd` beside `forge_mr_cmd`, using `forge_cli`.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_merge-mode.bats tests/test_ship-next-merge-mode.bats`.
- [x] **Step 5: Commit.** `git commit -m "feat(R-021): merge_mode honours a per-ship mode; forge_automerge_cmd"`

### Task 2: `sn_door` — the door, its reasons and the per-ship mode

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh`. Add `_sn_glob_match`,
  `_sn_one_way_paths` and `sn_door` after `sn_mech_gates`.
- Create: `claude-skills/ship-workflow/tests/test_ship-next-door.bats`

**Interfaces:**
- Consumes:
  - `sn_new_deps <base> <head>` (existing; prints `<file>\t<name>`)
  - `_sr_base_file <base> <path>` (lib/security-review.sh; prints that file at the base
    branch)
  - `merge_mode` (Task 1)
  - `sn_state_load` and `sn_state_set`
- Produces:
  - `_sn_glob_match <glob> <path>` returns 0 on a match.
  - `_sn_one_way_paths <base>` prints one glob per line.
  - `sn_door <worktree>` prints `door: <door>` then one reason per line, and persists
    the four keys.

- [x] **Step 1: Write the failing tests.** Fixture:
  - A scratch git repo on `main` with `src/a.py` committed.
  - Optionally a `.claude/ship-config.yml` on `main`.
  - Then `git checkout -b ship/R-9-x`, with
    `docs/specs/R-9-x.md` = `# x\n\n## Goals\nDoor: two-way here is a quote\n\n## Decisions\n- Door: <door> — why\n`.
  - State in the repo dir: `sn_state_set "$PWD" ID R-9`, `SLUG x`, `ORIG_BRANCH main`,
    `REPO "$PWD"`.
  - Each case commits its changes on the ship branch, then runs
    `bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_door "$PWD"'`.

  The cases:
  - **`two-way spec, plain change: squash` (AC-1).** Change `src/a.py`. The first line
    is `door: two-way`, and the state has `SHIP_MERGE_MODE=squash` and
    `SHIP_AUTO_MERGE=0`.
  - **`no Door line in Decisions: one-way` (AC-2, Review Focus 1).**
    - The spec keeps the `## Goals` quote but has no Decisions `Door:` line.
    - Result: `door: one-way`, a line `spec: no Door line`, and `SHIP_MERGE_MODE=mr`.
  - **`a migration forces one-way` (AC-3).** Add
    `backend/migrations/versions/0042_x.py`. The output has
    `signal: migration backend/migrations/versions/0042_x.py`.
  - **`a new dependency forces one-way; a version bump does not` (AC-4).**
    - `main` has `package.json` `{"dependencies":{"a":"1"}}`.
    - Adding `"left-pad":"1"` gives `signal: new dependency left-pad (package.json)`.
    - Bumping `a` to `2` only gives `door: two-way`.
  - **`deploy files force one-way` (AC-5).** `Dockerfile.backend` and
    `.github/workflows/ci.yml` each give a `signal: deploy` line.
  - **`one_way_paths come from the base branch` (AC-6, Review Focus 2).**
    - On `main`, add `.claude/ship-config.yml` with:
      ```
      one_way_paths:
        - backend/app/domain/push_*.py
        - "backend/app/api/auth.py"
        - backend/x/*.py  # pushes
      ```
    - On the ship branch, touch `backend/app/domain/push_recipients.py`,
      `backend/app/api/auth.py` and `backend/x/y.py`. Each gives a
      `signal: one_way_paths` line.
    - A second fixture adds the same config **only on the ship branch**. Touching
      `push_recipients.py` there gives `door: two-way`.
  - **`an mr repo with a two-way door auto-merges` (AC-7).** `main`'s config has
    `merge_mode: mr`, and the spec is two-way. Result: `SHIP_MERGE_MODE=mr` and
    `SHIP_AUTO_MERGE=1`.
  - **`a rerun overwrites the keys` (Review Focus 3).** Run once with a one-way spec,
    then change the spec to two-way, commit, and rerun. The state has
    `SHIP_DOOR=two-way` and `SHIP_MERGE_MODE=squash`.
  - **`zsh gives the same door`.** The AC-6 case under `zsh -c`.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_ship-next-door.bats`.
- [x] **Step 3: Implement.**
  - **`_sn_glob_match`:** as in Global Constraints.
  - **`_sn_one_way_paths <base>`:**
    - `_sr_base_file "$base" .claude/ship-config.yml | awk` to collect the indented
      `- ` items after `^one_way_paths:` until the next non-indented, non-blank line.
    - Strip a trailing ` # comment`, surrounding quotes and whitespace.
    - Source `security-review.sh` if `_sr_base_file` is not defined.
  - **`sn_door <worktree>`:**
    1. `sn_state_load`; `cd` into the worktree.
    2. Read the Decisions `Door:` line: `awk '/^## Decisions/{d=1;next} /^## /{d=0} d && /Door:[[:space:]]*(one-way|two-way)/'`, first match.
    3. Take the changed paths from
       `git -c core.quotePath=false diff --name-only "$(git merge-base "$ORIG_BRANCH" HEAD)" HEAD`.
    4. Collect the reasons. The built-in globs are, for migrations,
       `*migrations/*`, `*/alembic/versions/*` and `db/migrate/*`; and for deploy,
       `Dockerfile*`, `*/Dockerfile*`, `docker-compose*`, `*/docker-compose*`,
       `.gitlab-ci.yml`, `.github/workflows/*`, `env_template*` and
       `*/env_template*`. Then `sn_new_deps "$ORIG_BRANCH" HEAD`, then
       `_sn_one_way_paths "$ORIG_BRANCH"`.
    5. Decide the door. `REPO_MODE=$(SHIP_MERGE_MODE= merge_mode)` (unset, so the repo
       config decides). The mode is `squash` only when `REPO_MODE` is squash and the
       door is two-way; otherwise `mr`. `SHIP_AUTO_MERGE=1` only when `REPO_MODE` is mr
       and the door is two-way.
    6. Set all four keys and print the result.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_ship-next-door.bats tests/test_ship-next-lib.bats`.
- [x] **Step 5: Commit.** `git commit -m "feat(R-021): sn_door — door, reasons and per-ship merge mode"`

### Task 3: `sn_auto_merge`, `sn_land` and `sn_cleanup`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh`. Add `sn_auto_merge`. Change
  the `sn_land` mr branch, and add `sn_state_load` at the top of `sn_cleanup`.
- Test: `claude-skills/ship-workflow/tests/test_ship-next-door.bats` (append)

**Interfaces:**
- Consumes: `forge_cli` and `forge_automerge_cmd` (Task 1); `SHIP_AUTO_MERGE` (Task 2).
- Produces: `sn_auto_merge <url>` returns 0 when auto-merge was set, and 1 with a WARN
  otherwise. `sn_land` persists `SHIP_AUTO_MERGED`.

- [x] **Step 1: Write the failing tests.** Stub CLIs: write `glab` and `gh` scripts into
  `$BATS_TEST_TMPDIR/bin`, prepended to `PATH`. Each appends `"$*"` to
  `$BATS_TEST_TMPDIR/calls`. The `glab mr view` stub prints `$STUB_VIEW_JSON`. The
  origin remote is set to a gitlab URL.
  - **`no pipeline: no merge` (AC-9).** `STUB_VIEW_JSON='{"head_pipeline":null}'` and
    `SN_PIPELINE_WAIT=0`. `sn_auto_merge https://g/mr/1` returns 1, the output contains
    `WARN`, and `calls` has no `mr merge` line.
  - **`a pipeline: auto-merge is set` (AC-10).**
    `STUB_VIEW_JSON='{"head_pipeline":{"id":7}}'`. The status is 0, and `calls` holds
    the line `mr merge https://g/mr/1 --auto-merge --squash --yes`.
  - **`a failing merge command does not fail sn_land` (Review Focus 4).**
    - Set up a bare origin, a pushed ship branch and state `SHIP_AUTO_MERGE=1`.
    - The `glab` stub prints a URL for `mr create`, a pipeline for `mr view`, and exits
      1 for `mr merge`.
    - `sn_land` exits 0, and the state has `SHIP_AUTO_MERGED=0`.
    - Reuse the mr-mode `sn_land` setup in `tests/test_ship-next-lib.bats` where one
      exists. Otherwise build a minimal repo with a bare `origin`, and use a `git`
      remote URL containing `gitlab` via `git remote set-url --push`. Keep the fetch URL
      pointing at the bare repo.
  - **`sn_cleanup keeps a one-way ship's worktree in a squash repo` (Review Focus 5).**
    - A squash repo (no config), plus a linked worktree with state
      `SHIP_MERGE_MODE=mr`.
    - `sn_cleanup "$WT" "$BRANCH"` leaves the worktree directory and the branch.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_ship-next-door.bats`.
- [x] **Step 3: Implement.**
  - **`sn_auto_merge`:**
    - Return 1 with a WARN if `jq` is missing for glab.
    - Poll every 5 s until `SN_PIPELINE_WAIT` seconds have passed, at least once. For
      glab, `glab mr view "$url" -F json | jq -r '.head_pipeline.id // empty'` must be
      non-empty. For gh, `gh pr checks "$url"` must print at least one line.
    - Then `eval "$(forge_automerge_cmd "$url")"`. Return its status, with a WARN on
      failure.
    - With no pipeline: `WARN: no pipeline on <url> after <n>s — auto-merge not set; a human merges it`, and return 1.
  - **In `sn_land`'s mr branch,** after `review open:`:
    - `SHIP_AUTO_MERGED=0`
    - `if [ "${SHIP_AUTO_MERGE:-0}" = 1 ] && sn_auto_merge "$SHIP_REVIEW_URL"; then SHIP_AUTO_MERGED=1; fi`
    - `sn_state_set` it.
    - Change the unknown-forge message to add `— a one-way door needs a review; merge it by hand after one` when `SHIP_DOOR` is `one-way`.
  - **`sn_cleanup`:** call `sn_state_load "$1"` first, guarded by
    `[ -f "$1/.ship/state.env" ]`.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_ship-next-door.bats tests/test_ship-next-lib.bats tests/test_command-blocks.bats`.
- [x] **Step 5: Commit.** `git commit -m "feat(R-021): auto-merge only after a pipeline; sn_cleanup follows the ship's mode"`

### Task 4: Body template, log row and summary

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh` (`sn_ship_body`, `sn_log`,
  `sn_summary`)
- Modify:
  - `claude-skills/ship-workflow/tests/test_ship-next-lib.bats`. Change the two existing
    `head -1 … '↳ done when: Ready'` assertions, in `ship body lines start at column 0`
    and `ship body carries done-when past explain…`, to `grep -qxF '↳ done when: Ready'`.
  - `test_ship-next-security.bats`, only if its body greps break.
- Test: `claude-skills/ship-workflow/tests/test_ship-next-door.bats` (append)

**Interfaces:**
- Consumes: `SHIP_DOOR`, `SHIP_DOOR_REASONS`, `SHIP_MERGE_MODE`, `SHIP_AUTO_MERGED`,
  `SHIP_REVIEW_URL` (state); `<worktree>/.ship/pr-head.md`.

- [x] **Step 1: Write the failing tests.**
  - **`body: Summary, Evidence, Merge Danger, Ship details in order` (AC-11).**
    - `.ship/pr-head.md` is
      `## Summary\nS-LINE\n\n## Evidence\nE-LINE\n\n**Blast Radius:** low\nB-LINE\n`.
    - The state has `SHIP_DOOR=one-way` and `SHIP_DOOR_REASONS='spec: no Door line; signal: migration m/1.py'`.
    - Use the same vault and ROADMAP setup as the existing body tests.
    - The line numbers must be strictly increasing, in this order:
      - `## Summary` < `S-LINE` < `## Evidence` < `E-LINE`
      - `< ## Merge Danger < **Door:** one-way < - spec: no Door line < - signal: migration m/1.py`
      - `< **Blast Radius:** low < B-LINE < ## Ship details < ↳ done when: Ready`
    - The last line is the co-author line.
  - **`body without pr-head.md warns and still carries Merge Danger` (AC-12).** No
    `pr-head.md`. Stderr contains `WARN`, and the body has `**Blast Radius:** unstated`
    and `## Ship details`.
  - **`log row and summary carry the door` (AC-13).**
    - State `SHIP_DOOR=one-way`, `SHIP_MERGE_MODE=mr`,
      `SHIP_REVIEW_URL=https://g/mr/1`, `SHIP_AUTO_MERGED=0`.
    - `sn_summary` with `AUTO=1` contains `• door: one-way → awaiting human review: https://g/mr/1`.
    - With `SHIP_DOOR=two-way` and `SHIP_MERGE_MODE=squash` it contains
      `• door: two-way → squash-merged`.
    - With `two-way`, `mr` and `SHIP_AUTO_MERGED=1` it contains
      `• door: two-way → auto-merge set (merges after CI)`.
    - A squash default `sn_log` row (reuse the `p9_log_block` pattern in
      `tests/test_command-blocks.bats`, or an equivalent minimal repo) contains
      `door=one-way`.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_ship-next-door.bats`.
- [x] **Step 3: Implement.**
  - **`sn_ship_body`:** print the pr-head lines that are not in the Blast Radius block;
    that block runs from the `**Blast Radius:**` line to the next `## ` or EOF. Then:
    - a blank line and `## Merge Danger`;
    - `**Door:** ${SHIP_DOOR:-one-way}`;
    - each reason as `- <reason>`;
    - the Blast Radius block, or `**Blast Radius:** unstated`;
    - `## Ship details`, then the previous body content unchanged.
    - When `pr-head.md` is missing, print a WARN to stderr.
  - **`sn_log`'s default row:** add `, door=${SHIP_DOOR:-unset}` after
    `spec_gaps=…`.
  - **`sn_summary`:** add the `• door:` line after the spec review line, with the three
    landing phrases above.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_ship-next-door.bats tests/test_ship-next-lib.bats tests/test_ship-next-security.bats tests/test_command-blocks.bats tests/test_ponytail-integration.bats`.
- [x] **Step 5: Commit.** `git commit -m "feat(R-021): Pocock body — Summary, Evidence, Merge Danger; door in log and summary"`

### Task 5: Command text, spec template, README

**Files:**
- Modify:
  - `claude-skills/ship-workflow/commands/ship-next.md` (Phases 3, 7, 8, 9)
  - `claude-skills/ship-workflow/templates/repo/SPEC.md`
  - `claude-skills/ship-workflow/README.md`
- Create: `claude-skills/ship-workflow/tests/test_ship-next-door-text.bats`

- [x] **Step 1: Write the failing tests** (AC-14). Use `awk` phase ranges as in
  `tests/test_ship-next-grilling.bats`.
  - Phase 3 contains `Door: one-way|two-way`.
  - Phase 7 contains `sn_door "$WORKTREE"` and `.ship/pr-head.md`.
  - Phase 8 contains `sn_state_load`, with `merge_mode` after it.
  - Phase 9 step 0a's bash block contains `sn_state_load` on a line before
    `MERGE_MODE=$(merge_mode)`. Extract it with the `block` helper style, or `awk` from
    `0a\.` to `^0\. `.
  - `templates/repo/SPEC.md` contains `Door:`.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_ship-next-door-text.bats`.
- [x] **Step 3: Edit.**
  - **Phase 3 step 1:** after the `## Decisions` requirement, add: "The Decisions must
    hold one line `Door: one-way|two-way — <why>`, Pocock's merge danger. One-way means
    hard to walk back: schema or data changes, deletions, messages sent to users, auth,
    deploy. When unsure, write one-way."
  - **Phase 7:** replace the intro line, "Read `merge_mode`…", with: "The ship's mode
    comes from step 0: a two-way door keeps the repo's `merge_mode`; a one-way door
    always opens a review."
    - **Step 0:** `sn_door "$WORKTREE"`, in a bash block.
    - **Step 0.5:** the agent writes `.ship/pr-head.md`: `## Summary` (the smallest
      visual, using Pocock's list), `## Evidence` (before/after: the test that failed
      and now passes, with its command, or a `tdd_rules_prove` line) and
      `**Blast Radius:** <one word>`, plus optional consequences.
  - **Phase 8:** state that `squash` and `mr` mean the ship's mode,
    `source …/ship-next.sh && sn_state_load "$WORKTREE" && merge_mode`.
  - **Phase 9 step 0a:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh` and
    `sn_state_load "$WORKTREE"` before `MERGE_MODE=$(merge_mode)`.
  - **SPEC.md:** add `- Door: one-way|two-way — <why; one-way when unsure>` under its
    Decisions section.
  - **README:** add a short "Door routing (ship-next Phase 7)" paragraph with the
    routing table from spec G3.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_ship-next-door-text.bats tests/test_no-positional-params.bats tests/test_block-endings.bats tests/test_templates-seams.bats`.
- [x] **Step 5: Commit.** `git commit -m "feat(R-021): ship-next text — Door in spec, sn_door and pr-head in Phase 7, per-ship mode"`

### Task 6: Full suite

- [x] **Step 1: Run.** `cd claude-skills/ship-workflow && bats tests/`. Expected: all pass except the known `cwd-guard: exits 0 when not in a git repo at all` (AC-15).
- [x] **Step 2: Fix what fails.** Fix any other failure within scope. A failure that also fails on `main` is reported, not fixed. Commit any fix as `fix(R-021): …`.


## Execution log

- Tasks 1–4: completed in order with failing tests observed before implementation and all prescribed scoped checks green (25, 59, 114 and 141 tests respectively). Commits: dc6e1f6, 5681ed2, b70fc91, a7f4533.
- Deviation: Phase 8 explicitly sources merge-mode.sh before the prescribed state-loading expression — ship-next.sh does not define merge_mode at source time, so the expression otherwise fails in a fresh shell.
- Task 5: all five prescribed text tests failed before editing; 19 scoped checks now pass, including execution of the Phase 8/9 mode blocks in fresh bash and zsh shells.
- Final read-only review: no important new defects; all five Review Focus cases verified. Deferred minor: GitHub checks and delayed polling have no dedicated tests; the prescribed Task 3 tests exercise GitLab and zero-wait/pipeline-present paths.
- Deviation: added explicit `|| return 1` to the new door tests' double-bracket assertions — the full-suite hygiene guard showed that intermediate `[[ ... ]]` assertions can otherwise be silently ignored by Bats. Assertions are strengthened, not removed or loosened.
- Task 6: first full run found the known cwd-guard baseline failure and the new assertion-hygiene failure. After the local assertion repair, `bats tests/test_ship-next-door.bats tests/test_suite-hygiene.bats` passed 19/19. Final `cd claude-skills/ship-workflow && bats tests/`: 689 passed out of 690; only `cwd-guard: exits 0 when not in a git repo at all` failed, as explicitly expected by the plan. No baseline fix made.
- Final status: DONE_WITH_CONCERNS (two documented local deviations; known baseline failure; deferred minor coverage gap). Stayed on ship/R-021-route-by-merge-door, with no remote push or amended commit.
