---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-021
status: draft
tags: [ship-next, merge, door, pr-body, review]
ai-first: true
---

## For future Claude
> Until now a repo's `merge_mode` decided how every ship landed: ai_system always
> squashed straight to main, line-oa always waited for a human. R-021 decides per ship,
> by the "door" from Matt Pocock's `pr` skill:
> - "You can walk back through two-way doors, but not one-way doors." A two-way-door
>   ship merges without a human. ai_system squashes as before; line-oa opens the MR and
>   sets auto-merge once its pipeline exists.
> - A one-way-door ship always opens a review and waits for a person, in every repo.
>
> The door comes from the spec's Decisions (`Door: one-way|two-way — why`) and from
> mechanical signals in the diff.
> - The signals can only escalate a door to one-way.
> - A missing door counts as one-way.
>
> The body follows Pocock's template: Summary, Evidence, Merge Danger.

## Goals
- **G1.** Every ship has a door: `one-way` or `two-way`.
  - It is `two-way` only when the spec's Decisions say `Door: two-way` **and** no
    mechanical signal fires. Otherwise it is `one-way`.
  - The reasons are kept, for example `spec: Door: one-way — drops a column` or
    `signal: migration backend/migrations/versions/0042_x.py`.
- **G2.** The mechanical signals are:
  - **migrations:** a changed path matching `*migrations/*`, `*/alembic/versions/*` or
    `db/migrate/*`;
  - **new dependencies:** any line from `sn_new_deps <base> HEAD` (R-015). Version bumps
    are not signals: they roll back with a revert;
  - **deploy, env and CI files:** `Dockerfile*`, `*/Dockerfile*`, `docker-compose*`,
    `*/docker-compose*`, `.gitlab-ci.yml`, `.github/workflows/*`, `env_template*`,
    `*/env_template*`;
  - **the repo's own `one_way_paths`:** a YAML block list of globs in
    `.claude/ship-config.yml`, read from the **base branch** so a ship cannot loosen its
    own door. Glob semantics are shell `case` patterns, where `*` also crosses `/`.
- **G3.** Routing:

  | repo `merge_mode` | door | this ship lands by |
  |---|---|---|
  | squash | two-way | squash merge, as today |
  | squash | one-way | push + PR/MR, in review, `/ship-land` after a human merges |
  | mr | two-way | push + MR, then auto-merge once the MR has a pipeline |
  | mr | one-way | push + MR, in review, waits for a human |

  - The per-ship mode is `SHIP_MERGE_MODE` in `.ship/state.env`. `merge_mode()` returns
    it when it is set. Every later step, `ship_log` included, therefore takes the mr path
    for a one-way ship in a squash repo.
- **G4.** Auto-merge is never set on an MR that has no pipeline.
  - **glab:** wait up to 90 s for the MR's head pipeline. glab 1.99's `mr merge`
    "merges immediately" when no pipeline is running. When one exists, run
    `glab mr merge <iid> --auto-merge --squash --yes` (glab takes an MR iid or branch, not a URL; the iid comes from `…/merge_requests/<iid>`).
  - **gh:** require at least one check on the PR, then `gh pr merge <url> --auto --squash`.
  - **No pipeline or check, or the command fails:** print a WARN and leave the MR for a
    human. The ship continues as in-review.
- **G5.** The body is Pocock's template plus the existing ship details.
  - `## Summary` and `## Evidence` come from `.ship/pr-head.md`, written by the agent in
    Phase 7. Without it, `sn_ship_body` warns on stderr and builds the rest anyway.
  - `## Merge Danger` is generated:
    - `**Door:** <door>`
    - the reasons, as bullets
    - the `**Blast Radius:**` line(s) from `.ship/pr-head.md`, or `**Blast Radius:**
      unstated` when it has none
  - Then `## Ship details`: everything the body carried before (`↳ done when:`, tasks,
    review counts, security, spec review, tests, spec/plan pointers), ending with the
    co-author line.
- **G6.** The door shows up in the ship log row (`door=<door>`) and in the auto summary
  (`• door: <door> → <how it landed>`).

## Non-goals
- Adding `one_way_paths` to langlive-line-oa. That is a separate line-oa MR once this
  ships.
- Classifying additive migrations as two-way. Every migration is one-way for now, to be
  refined with data.
- Changing `/ship-land`. It already finishes any merged review.
- Blast radius as a routing input. It is reported, not routed on.

## Anti-goals
- **A one-way change merged without a human.**
  - Signals only escalate a door.
  - A missing door is one-way.
  - The repo's paths come from the base branch.
- **An auto-merge that skips CI because the pipeline had not started yet.**

## Design
- **`sn_door <worktree>`** (in lib/ship-next.sh) reads state (`ID`, `SLUG`, `ORIG_BRANCH`,
  `REPO`) and the spec `docs/specs/<ID>-<SLUG>.md`.
  - It collects reasons:
    - the spec's `Door:` line, read only from its `## Decisions` section (other sections
      may quote the syntax), or `spec: no Door line`;
    - every signal, each as `signal: <kind> <path or dependency>`.
  - It decides the door as in G1 and the mode as in G3.
  - It persists `SHIP_DOOR`, `SHIP_DOOR_REASONS` (reasons joined by `; `),
    `SHIP_MERGE_MODE` and `SHIP_AUTO_MERGE` (`1` only for an mr repo with a two-way door).
  - It prints `door: <door>` and then one reason per line.
  - It recomputes and overwrites all four keys on every run, so a stale
    `SHIP_MERGE_MODE` never survives a rerun.
  - The signal diff range is the merge-base of `ORIG_BRANCH` and `HEAD`, as
    `sn_new_deps` uses.
- **`_sn_one_way_paths <base>`** prints the globs under `one_way_paths:` in
  `<base>:.claude/ship-config.yml`. It prints nothing when the file or the key is absent.
  - It reuses `_sr_base_file` (lib/security-review.sh) to read the file.
  - The list is a YAML block: the `one_way_paths:` key, then indented `- <glob>` lines,
    optionally quoted, until the next non-indented line.
- **`merge_mode()`** returns `$SHIP_MERGE_MODE` when it is `mr` or `squash`; otherwise it
  behaves as today.
  - Phase 9 step 0a loads state before calling it.
  - Every `merge_mode` caller in lib/ship-next.sh runs after `sn_state_load`.
- **`forge_automerge_cmd <url>`** (lib/merge-mode.sh) echoes the merge command for the
  forge, in the style of `forge_mr_cmd`. Nothing is run there, so it stays testable.
- **`sn_auto_merge <url>`** (lib/ship-next.sh) waits for a pipeline or check, then runs
  the command, as in G4. The wait is
  `SN_PIPELINE_WAIT=${SN_PIPELINE_WAIT:-90}` seconds, polled every 5 s.
  - **glab:** `glab mr view <url> -F json | jq -r '.head_pipeline.id // empty'`.
  - **gh:** `gh pr checks <url>` lists at least one check.
  - Returns 0 when auto-merge was set, and 1 with a WARN otherwise.
- **`sn_land`** uses `merge_mode` (it already loads state). After the mr branch opens the
  review, it calls `sn_auto_merge` when `SHIP_AUTO_MERGE=1`. A failure there does not
  fail `sn_land`.
  - A ship whose mode is mr in a repo with no GitHub or GitLab `origin` stops with
    exit 1, as the mr path already does. The message says a one-way door needs a
    review, so the branch must be merged by hand after one. It never falls back to a
    squash.
- **ship-next Phase 3** step 1 requires a `Door: one-way|two-way — <why>` line in
  Decisions. When unsure, `one-way`.
- **ship-next Phase 7:**
  - New step 0: `sn_door "$WORKTREE"`.
  - New step 0.5: the agent writes `.ship/pr-head.md`:
    - a `## Summary` with the smallest visual that makes the point (pseudocode, a call
      tree, a diff sketch, a file tree or mermaid; Pocock's list), in CONTEXT.md
      vocabulary;
    - a `## Evidence` with before and after: the test that failed and now passes, with
      its command, or a `tdd_rules_prove` line;
    - a `**Blast Radius:** <one word>` line, optionally followed by consequences.
- **ship-next Phase 8** branches on the ship's mode: `merge_mode` after `sn_state_load`,
  not the repo config.
- **ship-next Phase 9:** step 0a loads state. The auto summary of a one-way ship says it
  awaits human review, with the URL.
- **`templates/repo/SPEC.md`** gains a `Door:` line in its Decisions section.

## Decisions
- leric, 2026-10-26: 「好 照建議」. That covers three answers:
  - (Q1) In mr repos a two-way door auto-merges after CI. With project approval rules,
    it waits for them.
  - (Q2) The built-in signals, plus line-oa's paths (push/broadcast, auth/webhook,
    deletion jobs, entrypoints) through `one_way_paths`.
  - (Q3) Open R-021 with `--auto:yes`.
- My call (auto Q1): the door lives in the spec's Decisions, and a missing door counts
  as one-way.
- My call (auto Q2): a new dependency is a signal but a version bump is not, because a
  revert rolls a bump back.
- My call (auto Q3): the per-ship mode is `SHIP_MERGE_MODE` in state, honoured by
  `merge_mode()`. Without it, Phase 8/9 and `ship_log` would take the squash path for a
  one-way ship in ai_system.
- My call (auto Q4): auto-merge waits for the MR's pipeline. glab merges at once when
  none is running, and a just-created MR often has none yet.
- My call (auto Q5): the agent writes Summary and Evidence, because a shell function
  cannot draw the diagram. Merge Danger is computed so the door cannot be misreported.
- My call (auto Q6): the door goes into the log row and the summary.
- My call (builder check): R-021 cannot route itself, because the live ship-next is
  still the old one. Its Phase 7 is done by hand:
  1. Push the branch.
  2. Open a GitHub PR with the new body, built with this worktree's lib.
  3. Mark the row in-review and keep the worktree.
  4. After leric merges, run `/ship-land R-021`.
- My call (builder check): a one-way ship in a repo without a forge remote stops. It
  never falls back to a squash.
- Door: one-way — it changes how every future ship merges, including when a human is
  skipped. By its own rule this ship lands through a PR on ai_system's GitHub and waits
  for leric.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_door` | `sn_door <worktree>` (cwd: the worktree) | Reads `Door:` only inside `## Decisions`. Prints `door: one-way\|two-way` and one reason per line. Persists `SHIP_DOOR`, `SHIP_DOOR_REASONS`, `SHIP_MERGE_MODE`, `SHIP_AUTO_MERGE`. The door is two-way only with a spec `Door: two-way` and no signal. |
| `_sn_one_way_paths` | `_sn_one_way_paths <base>` | One glob per line from `one_way_paths:` in the base branch's `.claude/ship-config.yml`, unquoted. Nothing when absent. |
| `merge_mode` | existing | Returns `$SHIP_MERGE_MODE` when it is `mr` or `squash`; otherwise unchanged. |
| `forge_automerge_cmd` | `forge_automerge_cmd <url>` | Echoes `glab mr merge <iid> --auto-merge --squash --yes` (glab takes an MR iid or branch, not a URL; the iid comes from `…/merge_requests/<iid>`) or `gh pr merge <url> --auto --squash`. Exit 1 for an unknown forge. |
| `sn_auto_merge` | `sn_auto_merge <url>` | Runs the merge command only once a pipeline or check exists within `SN_PIPELINE_WAIT` seconds. Otherwise it prints WARN and returns 1 without merging. |
| `sn_land` | existing | Lands by `merge_mode` (per ship). With `SHIP_AUTO_MERGE=1` it calls `sn_auto_merge` after the review opens. Its failure does not fail `sn_land`. |
| `sn_ship_body` | existing | The body is `## Summary` and `## Evidence` (from `.ship/pr-head.md`), then `## Merge Danger` (door, reasons, Blast Radius), then `## Ship details` (the previous content). It warns when `.ship/pr-head.md` is missing. |
| `sn_log` / `sn_summary` | existing | The row has `door=<door>`. The summary has a `• door:` line. |
| ship-next Phase 3/7/8/9 text | command text | Phase 3 requires `Door:`. Phase 7 runs `sn_door` and has the agent write `.ship/pr-head.md`. Phases 8 and 9 use the per-ship mode. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | spec `Door: two-way — x`, diff touches only `src/a.py`, squash repo | `sn_door` | `door: two-way`; state has `SHIP_MERGE_MODE=squash`, `SHIP_AUTO_MERGE=0` |
| AC-2 | the same, but the spec has no `Door:` line | `sn_door` | `door: one-way`; the reason `spec: no Door line`; `SHIP_MERGE_MODE=mr` |
| AC-3 | spec two-way; the diff adds `backend/migrations/versions/0042_x.py` | `sn_door` | one-way; reason `signal: migration backend/migrations/versions/0042_x.py` |
| AC-4 | spec two-way; `package.json` adds a dependency / only bumps a version | `sn_door` | one-way with `signal: new dependency left-pad` / two-way |
| AC-5 | spec two-way; the diff touches `Dockerfile.backend` / `.github/workflows/ci.yml` | `sn_door` | one-way with `signal: deploy …` |
| AC-6 | the base branch's ship-config lists `backend/app/domain/push_*.py`; the diff touches `backend/app/domain/push_recipients.py`. The same entry only on the ship branch | `sn_door` | one-way with `signal: one_way_paths …` / two-way, because base-branch config wins |
| AC-7 | an mr repo, spec two-way, no signal | `sn_door` | two-way; `SHIP_MERGE_MODE=mr`, `SHIP_AUTO_MERGE=1` |
| AC-8 | state `SHIP_MERGE_MODE=mr` in a repo whose config says squash (and the reverse) | `merge_mode` after `sn_state_load` | `mr` (`squash`) |
| AC-9 | a stub `glab` whose `mr view` reports no head pipeline; `SN_PIPELINE_WAIT=0` | `sn_auto_merge <url>` | returns 1, WARN; `glab mr merge` never called |
| AC-10 | a stub `glab` reporting a pipeline | `sn_auto_merge <url>` | calls `glab mr merge <iid> --auto-merge --squash --yes` (glab takes an MR iid or branch, not a URL; the iid comes from `…/merge_requests/<iid>`); returns 0 |
| AC-11 | `.ship/pr-head.md` with Summary, Evidence and `**Blast Radius:** low`; state door one-way with 2 reasons | `sn_ship_body` | sections in the order Summary, Evidence, Merge Danger, Ship details; Merge Danger has `**Door:** one-way`, 2 reason bullets and `**Blast Radius:** low`; `↳ done when:` is inside Ship details; the co-author line is last |
| AC-12 | no `.ship/pr-head.md` | `sn_ship_body` | WARN on stderr; the body still has Merge Danger with `**Blast Radius:** unstated` and Ship details |
| AC-13 | state `SHIP_DOOR=one-way` | `sn_log` (squash default row) / `sn_summary` | the row contains `door=one-way`; the summary has a `• door: one-way` line |
| AC-14 | ship-next.md | read | Phase 3 requires `Door:`; Phase 7 runs `sn_door` and names `.ship/pr-head.md`; Phase 9 step 0a loads state before `merge_mode` |
| AC-15 | the full suite | `bats tests/` | green apart from the known cwd-guard failure in a linked worktree |
