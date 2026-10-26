# R-021 review fix 2

Spec: `docs/specs/R-021-route-by-merge-door.md`. Read it first; it is the contract.

Reports: `/tmp/ship-next-review-R-021-1.md` (code review) and
`/tmp/ship-next-spec-R-021-1.md` (Spec review). Fix their 4 blocking findings and the
1 important one.

Conventions:
- TDD: write each failing test first and see it fail, then fix.
- Tests run scoped: `cd claude-skills/ship-workflow && bats tests/test_ship-next-door.bats tests/test_merge-mode.bats`.
- One commit per task, `fix(R-021): …`.
- Task 6 runs the full suite at the end. The known `cwd-guard` failure in a linked
  worktree is pre-existing.

### Task 1: glab takes an MR iid, not a URL
- **The problem.** `glab mr view` takes `[<id | branch>]` (glab 1.99 `--help`), and so
  does `mr merge`. So `sn_auto_merge` never sees a pipeline on GitLab.
- **Test (the stub).** In `test_ship-next-door.bats`, make the stub `glab` exit 2 with
  `unknown MR` unless the argument after `mr view` or `mr merge` is all digits.
- **Test (the URL).** `sn_auto_merge https://g/grp/repo/-/merge_requests/42`, with a
  pipeline in the stub's JSON. `calls` holds
  `mr view 42 -F json` and `mr merge 42 --auto-merge --squash --yes`.
- **Test (bad URL).** `sn_auto_merge https://g/x` (no iid) returns 1 with a WARN, and
  no `mr merge` is called.
- **Test (forge_automerge_cmd).** In `test_merge-mode.bats`, a GitLab URL ending in
  `/merge_requests/42` echoes `glab mr merge 42 --auto-merge --squash --yes`. The gh
  form keeps the URL; `gh` accepts URLs.
- **Fix.** Add a `_sn_mr_iid <url>` helper (or inline `sed`) that prints the digits
  after `merge_requests/`. Use it for glab view and merge, in both `sn_auto_merge` and
  `forge_automerge_cmd`. No iid → WARN, return 1.

### Task 2: `sn_door` never fails open
- **The problem.** When `merge-base` or `diff` fails, `sn_door` returns before writing
  any key. `merge_mode` then falls back to the repo config, and a squash repo squashes.
- **Test.** State with `ORIG_BRANCH=no-such-branch` in a squash repo, spec two-way.
  - `sn_door` returns non-zero.
  - The state has `SHIP_DOOR=one-way`, `SHIP_MERGE_MODE=mr` and `SHIP_AUTO_MERGE=0`.
  - `SHIP_DOOR_REASONS` contains `door check failed`.
- **Fix.** Before computing anything, persist those safe values with the reason
  `door check failed — treated as one-way`. On success, overwrite all four keys as
  today.

### Task 3: a quoted Door mention cannot lower the door
- **The problem.** The first line that contains `Door: two-way` anywhere wins. A
  decision that quotes it before the real `- Door: one-way — …` line yields two-way.
- **Test.** Decisions =
  ``- My call: a `Door: two-way` ship auto-merges`` then `- Door: one-way — drops a column`.
  The result is `door: one-way`.
- **Test.** Decisions with only the quote line give `spec: no Door line` and one-way.
- **Fix.**
  - Only Decisions lines matching `^[-*[:space:]]*Door:[[:space:]]*(one-way|two-way)`
    count.
  - Any such line saying one-way makes the spec door one-way.
  - Two-way needs at least one such line, and none saying one-way.
  - The reason shows the first counted line, or the one-way line when there is one.

### Task 4: only an active or passing pipeline gets auto-merge (important)
- **The problem.** A failed or canceled head pipeline is still "a pipeline". glab then
  has nothing running to wait for, and merges at once.
- **Test.** Stub JSON `{"head_pipeline":{"id":7,"status":"failed"}}` → returns 1, WARN,
  no `mr merge`.
  `{"head_pipeline":{"id":7,"status":"running"}}` → auto-merge is set.
- **Fix.** Read `.head_pipeline.status`.
  - running, pending, created, waiting_for_resource, preparing, scheduled or success:
    set auto-merge.
  - failed, canceled or skipped: stop polling, WARN `pipeline <status> — auto-merge not
    set`, return 1.
  - empty: keep polling as today.

### Task 5: the push-failure message names the one-way door (Spec review)
- **The problem.** A repo with no `origin` stops at `git push` with "push failed — not
  opening a review…". Only the unknown-forge branch carries the one-way sentence.
- **Test.** A repo with no remote, state `SHIP_MERGE_MODE=mr` and `SHIP_DOOR=one-way`.
  `sn_land` exits non-zero, and stderr contains `a one-way door needs a review`.
- **Fix.** Append the same sentence to the push-failure message when `SHIP_DOOR` is
  `one-way`. Build it once, as a local string, and use it in both messages.

### Task 6: full suite
`cd claude-skills/ship-workflow && bats tests/`. Expected: only the known `cwd-guard`
failure.

## Execution log

- Tasks 1–5: completed in order, each with a failing regression check followed by
  a green scoped suite and its own commit. Scoped suite: 41 tests pass.
- Deviation: added explicit `|| return 1` to two new non-final WARN assertions —
  the full-suite hygiene guard requires this so failed assertions cannot be ignored.
  No assertion was removed or weakened.
- Task 6 initial full run: 697 tests, with the known linked-worktree cwd-guard
  failure and the two assertion-hygiene violations above. Repaired the latter;
  final full-suite result follows.
- Task 6 final full run: 696 passed, 1 known pre-existing failure out of 697
  (`cwd-guard: exits 0 when not in a git repo at all`, test_cwd-guard.bats:23).
  The full suite is not entirely green; no new failures remain. Output:
  /tmp/R-021-review-fix-2-tests-final.log.
- Final status: DONE_WITH_CONCERNS (the assertion repair above and the documented
  baseline failure). No remote push, branch switch, amended commit, or hook bypass.
