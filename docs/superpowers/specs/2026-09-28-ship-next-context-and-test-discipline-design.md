---
date: 2026-09-28
updated: 2026-09-28
type: spec
status: draft
tags: [ship-workflow, ship-next, context, tdd, seams, ponytail, understand-anything]
ai-first: true
related-specs:
  - 2026-06-21-ship-next-mega-command-design.md
  - 2026-06-22-ship-next-auto-yes-design.md
  - 2026-06-22-spec-vault-mirror-design.md
  - 2026-08-30-ua-ship-workflow-integration-design.md
supersedes: null
---

## For future Claude
> Two gaps in `/ship-next`, closed without replacing its 9-phase shape.
> **Gap 1 (vocabulary):** every R-NNN starts a fresh worktree + fresh session, so the
> agent re-learns project jargon every time and teammates stay unaligned. Fix = a
> git-tracked `CONTEXT.md` read at P3 and auto-written at P8, with a hard line cap.
> **Gap 2 (test churn):** the executor writes tests with no constraint on where they
> attach and nothing ever deletes them. Fix = seams declared in the spec, TDD rules
> injected via `.ship/`, mechanical gates at P6, and a prune *report* at a new P8.5
> (amended 2026-09-29: it was specified to delete; no coverage-derived gate can
> establish deletion safety, so it reports and the operator deletes — see §7.1).
> Plus `ponytail` at P5 (product code only) and a threshold-triggered UA KG rebuild
> at a new P8.7.
> **The governing constraint:** the operator runs `/ship-next` and nothing else.
> Anything not wired into this command does not happen. Do not "solve" a problem by
> emitting a follow-up ticket nobody will read.

## §1 Problem

### 1.1 Symptoms (operator-reported, 2026-09-28)
1. **Domain vocabulary is re-explained every session.** Each R-NNN opens a fresh
   worktree and a fresh agent context. Project-specific terms are re-derived from
   scratch, burning tokens and producing inconsistent naming. Teammates have no
   shared artifact to align on.
2. **Tests grow without bound and constantly need repair.** All four sub-symptoms
   confirmed by the operator:
   - tests assert implementation internals, so refactors break them
   - test count only grows; nothing deletes
   - the refactor step of red-green-refactor is where the pain concentrates
   - executor-written tests are weak (flaky, Assertion Roulette, weak assertions)

### 1.2 Structural root cause
Both symptoms are the same failure: **`/ship-next` has read paths for durable
context but no write-back or decay paths.**

| Artifact | Read by ship-next | Written by ship-next | Pruned by ship-next |
|---|---|---|---|
| UA knowledge graph | P1.5, P3, P6, P8 | never | never |
| Domain vocabulary | does not exist | does not exist | n/a |
| Test suite | P5, P6 | P5 (grows only) | never |

Every row that says "never" degrades into a liar over time. `ua_check_drift` already
prints `Blast-radius report will be misleading` and then emits the report anyway.

### 1.3 Evidence that "emit a follow-up ticket" does not work
The operator has the `compound-engineering` plugin installed, including `/ce-compound`
and `/ce-compound-refresh`. Across every repo under `~/Desktop/code`, there is no
`CONCEPTS.md` and no `docs/solutions/`. The mechanism exists and has never fired.
A design that routes work to a command the operator does not run is a no-op.

### 1.4 Out of scope (explicitly rejected)
| Rejected | Why |
|---|---|
| Replace the pipeline with Pocock's `grill-with-docs -> to-spec -> to-tickets -> implement -> code-review` | `to-tickets` and its issue-tracker state model solve cross-session / teammate visibility, which the operator did **not** select as a pain. YAGNI. |
| Move state to GitHub/Linear issues | Same reason. ROADMAP.md in the AIR-OS vault stays canonical. |
| Swap P5 executor for Pocock `/implement` | Requires installing all ~40 mattpocock skills, depends on tracker tickets, and forces a rewrite of the `--auto:yes` executor menu and `.claude/.ship-executor` resume logic. |
| Restructure the 9 phases | Operator did not report the flow as too heavy. |

## §2 Goals and non-goals

### 2.1 Goals
- G1. A project's domain vocabulary survives across R-NNN cycles, in git, readable by teammates.
- G2. Vocabulary has a hard size ceiling so it cannot become a per-session token tax.
- G3. Tests attach to declared seams, so refactors do not break them.
- G4. Refactor-only tasks add zero tests.
- G5. Test volume growth is measured and visible on every ship.
- G6. Redundant tests are identified and surfaced, inside `/ship-next`, every qualifying
  ship. **Amended 2026-09-29:** this originally read "actually deleted ... with a
  mechanical safety gate". No coverage-derived gate can establish deletion safety; see
  §7. Automatic deletion moves to its own roadmap item.
- G7. `ponytail` reaches the P5 executor despite its documented subagent limitation.
- G8. The UA knowledge graph is rebuilt before its staleness makes P3/P6 output misleading.

### 2.2 Non-goals
- Not changing P1, P2, P4, P7, P9 core behavior.
- Not changing the `--auto:yes` decision-log or notification transport.
- Not introducing an issue tracker.
- Not adding any new operator-facing slash command.

## §3 Design principles

- **P1. If it is not in `/ship-next`, it does not happen.** No design may discharge a
  responsibility by creating a ticket, a warning, or a recommendation aimed at a
  command the operator does not run.
- **P2. Prefer "automatic and visible" over "manual and silent."** The failure mode in
  this codebase is forgetting, not runaway automation. Default to acting, and surface
  what was done in the P9 notification.
- **P3. Anything read in full costs tokens every session.** Size caps are targets to
  achieve, not thresholds to warn at. There is no archive section inside a file that
  gets fully read.
- **P4. Injection beats activation.** Skills may fail to self-activate in subagents
  (`ponytail` documents this for Cursor `subagentStart`; P5 spawns a fresh subagent
  per task). Render rules to `.ship/*.md` and point the plan's task template at them.
- **P5. Destructive operations need a mechanical gate, not a human gate.** `--auto:yes`
  is the operator's normal mode, so refusing to run unattended is how a mechanism ends
  up never firing.
  **Amended 2026-09-29:** this principle originally named coverage and green tests as
  the verifiable invariants for deletion. They are not: coverage records which lines
  executed, not whether an assertion observed them (§7.1). The principle survives with a
  sharper corollary — *if no mechanical invariant exists, do not perform the destructive
  act at all.* That is why §7 reports rather than deletes.
- **P6. Reuse thresholds and machinery that already exist.** Do not invent a second
  staleness number when `ua_check_drift` already has one.

## §4 CONTEXT.md lifecycle (Gap 1)

### 4.1 Location
- `<repo>/CONTEXT.md` is canonical and git-tracked.
- Mirrored to `<vault>/<project>/CONTEXT.md` via the existing `lib/spec-mirror.sh`,
  which already handles `mkdir -p`, atomic write, and `mirror-source:` injection.
- Rationale matches `2026-06-22-spec-vault-mirror-design.md`: repo canonical so
  teammates get it through git and PR review; vault mirror for mobile reading.

### 4.2 Read (Phase 3, step 0)
Alongside the existing UA pre-brainstorm block:

```bash
if [ -f CONTEXT.md ]; then
  echo "CONTEXT.md present — Read it before brainstorm dialog."
fi
```

No derived file. `CONTEXT.md` is already in its final shape for both human and agent
readers, unlike the UA graph which must be rendered.

### 4.3 Write (Phase 8, inside `/ship-compound`)
After the learning is written, extract domain terms introduced or clarified by this
ship, sourced from the shipped diff and the spec. Append or refine entries, commit,
then mirror. The write is automatic; see §12.2 for why auto-writing a *glossary* is a
different risk class from auto-writing *behavioral rules*.

### 4.4 Size cap and pruning
```
Trigger: line count > 200  OR  entry count > 60
Target:  after pruning, <= 150 lines (25% headroom so pruning is not re-triggered next ship)
Method:  1. merge semantically duplicate entries
         2. delete terms with no grep hit anywhere in the repo
         3. if still over, delete the entries least recently cited by any spec or plan
```
200 lines borrows Anthropic's guidance ceiling for instruction files as an intuition
anchor, not as a measured constant.

**No archive section.** An `## Archive` heading inside `CONTEXT.md` would still be
read in full at P3, paying the token cost while delivering only cosmetic tidiness
(principle P3). Deleted terms are recoverable via `git log -p --follow CONTEXT.md`,
which additionally carries when and why the term was dropped.

### 4.5 `--auto:yes` behavior
- Auto-write: runs.
- Pruning: **does not run.** Consistent with the existing `--discard` / `--auto` mutex
  ("deletion is destructive — never auto"). Over-cap in auto mode emits a WARN, a
  `.ship-auto-decisions.md` entry, and a line in the P9 summary.
- **Amended 2026-09-29:** this originally justified running test pruning in auto on the
  strength of a coverage rollback gate. That gate does not exist any more (§7), so there
  is no asymmetry left: `CONTEXT.md` pruning is human-gated, and §7 deletes nothing at
  all. Both destructive acts are the operator's.

## §5 Seam declaration and TDD discipline (Gap 2, parts 1 and 3)

### 5.1 Phase 3: spec declares seams
Two coordinated changes, neither of which touches a `superpowers` file:
1. `templates/repo/SPEC.md` (ship-workflow owned) gains the section below. That template
   currently supplies frontmatter and then defers with
   `(Use superpowers:brainstorming's spec format from here onward.)`, so a required
   section declared there is additive.
2. P3's invocation of `superpowers:brainstorming` passes `## Seams` as a required output
   section, alongside the spec target and proposal context it already passes.

Kept to three columns deliberately: declaration must cost about 30 seconds or it will be
filled in carelessly.

```markdown
## Seams

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| roadmap-parser | `parse_roadmap(path) -> list[Row]` | valid ROADMAP.md yields ranked Rows; missing field raises ParseError |
```

Governing rule: **tests may assert a seam's behavior and nothing inside it.**

A "negative space" column (what is explicitly *not* guaranteed) was considered and
rejected: useful, but it makes declaration expensive enough to be skipped.

### 5.2 Phase 4: plan tasks label their seam
Each `### Task N:` gains one line:
```
Seam: roadmap-parser
Seam: none (refactor)
```
`Seam: none (refactor)` tasks must add zero tests. This is the concrete form of
Pocock's heterodox position that refactor does not belong inside the TDD loop:
behavior did not change, therefore tests must not change.

### 5.3 Phase 5: `.ship/tdd-rules.md`
`/ship-next` renders this file from the spec's `## Seams` table before invoking the
executor. The plan's task template gains `Read .ship/tdd-rules.md before writing tests.`

Contents: the rendered seam list plus three rules.
```
1. Tests attach only to the seams listed below.
2. `Seam: none` tasks add no tests. Behavior unchanged => tests unchanged.
3. One test, one behavior. Do not pack unrelated assertions into a single test.
```
Rule 3 targets Assertion Roulette, named in arXiv 2603.13724 as a characteristic
smell of agent-written tests and the reason failures are hard to localize.

**Why a file and not a skill:** P5 runs `superpowers:subagent-driven-development`,
which spawns a fresh subagent per task. Skill auto-activation in a subagent is not
controllable. The `.ship/ua-context.md` pattern is already proven in this codebase
(principle P4).

### 5.4 Missing `## Seams`
- `--auto:yes`: P4 refuses to proceed, `exit 2`, with a hint to add the section.
  Mirrors the existing auto pre-flight gate that refuses to run without `↳ done when:`.
- Interactive: WARN only.

## §6 Phase 6 test gates (Gap 2, parts 2 and 4)

### 6.1 Layer one: mechanical checks (new step 0.5, pure git and shell)

**6.1.1 Refactor violation (blocking).**
For each plan task labeled `Seam: none`, inspect its commit. If net added lines under
`tests/` is greater than zero, emit a blocking finding. Deterministic; no LLM needed.

**6.1.2 Test budget, relative to the repo's own baseline.**
`/ship-next` runs across repos with very different testing cultures, so a hardcoded
ratio would misfire. Compare this ship against the repo it is running in:
```
baseline  = repo-wide  test_lines : src_lines
this_ship = this diff  test_lines_added : src_lines_added

this_ship <= 2x baseline   -> pass
2x .. 4x                   -> major
> 4x                       -> blocking
```
A greenfield repo has a baseline near zero, which auto-passes the first ships.

**6.1.3 Trend visibility.**
The P7 commit message gains one line regardless of verdict:
```
Tests: +142 / Src: +310  (ratio 0.46 vs baseline 0.60) OK
```

### 6.2 Layer two: semantic checks (folded into the existing code-review-skill call)
`lib/code-review-parse.sh` gains three categories:
- **seam violation** -> major (test asserts something not in `## Seams`)
- **assertion roulette** -> minor
- **weak assertion** -> minor (`assert x is not None` and similar non-discriminating checks)

Marginal cost is a few extra prompt lines; the LLM review already runs at P6.

### 6.3 Shadow mode for the budget
The `2x` / `4x` values in 6.1.2 are a starting heuristic, not a measured constant, and
they interact with ponytail (see §12.1). For the **first 3 ships**, 6.1.2 reports the
numbers and raises **no** finding.

**Ship count is derived, not stored.** P9 already appends a row per ship to
`docs/learnings/_log.md`; §6.1.3's ratio line is added to that row. Shadow mode is
therefore "fewer than 3 prior rows in `_log.md` carry a ratio field". No counter file,
no per-ship config commit, and the state self-heals if the log is edited.

This matters because `ship-workflow.yml` is **global** (`~/.claude/ship-workflow.yml`,
read by `lib/airos-binding.sh`, `lib/id-gen.sh`, `lib/sync.sh`), so a counter stored
there would be shared across every repo. The multipliers themselves (`2x` / `4x`) *are*
safe to keep global, because §6.1.2's baseline is computed per-repo from the working
tree; the multiplier is a portable ratio, not a repo-specific constant.

## §7 Phase 8.5: test prune report (new phase)

**Amended 2026-09-29 after six acceptance-review rounds. This phase deletes nothing.**

### 7.1 Why the original design was withdrawn
It was specified as a scoped prune behind a gate that required coverage not to fall.
Six rounds of adversarial review found fourteen defects in that gate. The first eleven
were fixable — an unscoped fallback, a fail-open integer comparison, a rounded
percentage, counts that preserve cardinality but not membership, stale reports, missing
validation. Each fix was correct and each was insufficient.

The last three made the reason plain. Coverage records which lines and branches
*executed*; it does not record whether an assertion *observed* them. A test stripped of
its assertions produces coverage identical to one that checks everything. So no value
derived from coverage can establish that deleting a test is safe, and the "known limit"
this spec originally accepted in §7.5 was not a limit but the whole problem.

Establishing assertion strength needs mutation testing — inject a defect, confirm a test
catches it. That is a different tool at a different cost, and it belongs in its own
roadmap item with its own spec and acceptance, not bolted onto this one.

### 7.2 What the phase does now
Identifies prune candidates and records them. Same trigger (the major band P6 already
computed) and same scope (§7.3). It writes `.ship/prune-candidates.md` with one row per
candidate — file, test, category, reason — and P9 surfaces the count in the summary and
the `_log.md` row.

No coverage run, no rollback path, no commit, because nothing changes. The `--auto:yes`
question disappears with the destructive act: a report is safe to produce unattended.

The operator acts on the list. That is a real cost against the original goal, and it is
the honest one: the mechanism that made "delete it for you" safe never existed.

### 7.3 Scope
**Only tests covering modules this ship touched**, derived from
`git diff --name-only ${ORIG_BRANCH}...${BRANCH}`.

Three reasons: scope stays bounded; the context is hot, so judging "these two tests
assert the same thing" is at its most accurate; and across many ships the repo gets
covered incrementally without ever needing a big-bang cleanup.

### 7.4 What is proposed
One row per candidate in `.ship/prune-candidates.md`, in three categories:

1. duplicate coverage: two tests asserting the same behavior
2. seam violations: a test asserting inside a seam rather than at it
3. never-failing tests: an assertion too weak to discriminate any input

Each row carries the file, the test name and one line of reasoning. Nothing is edited.

### 7.5 Safety gate
None, because nothing is destroyed. The gate this section used to specify — tests green
plus coverage not lower — is withdrawn; see §7.1.

### 7.6 `--auto:yes` behavior
**Runs**, and needs no exception now that it destroys nothing.

The original text argued the opposite way round: that the operator's normal mode is
fire-and-forget, so gating pruning on human presence would reproduce the §1.3 failure
where a mechanism exists but never fires, and that the coverage and green-test invariants
made deletion a verifiable refactor rather than an unrecoverable act — the distinction
separating it from `--discard` (principle P5). The first half still holds and is why the
report runs unattended. The second half was wrong, and §7.1 is why.

## §8 ponytail integration

### 8.1 Phase 5 only
`brainstorming` already instructs "YAGNI ruthlessly - remove unnecessary features from
every approach and design", which covers ladder rung 1. Injecting ponytail at P3 would
put two differently-worded versions of the same rule in context, which is exactly the
documented caveman/ponytail conflict shape.

Rungs 2 through 7 are all implementation-time checks. JetBrains' measurement agrees on
where the value is: code fell 31% on larger builds and approximately zero on minimal
tasks.

### 8.2 Mechanism: `lib/ponytail-integration.sh`
Structured as a direct parallel to the existing `lib/ua-integration.sh`:
```bash
ponytail_check_installed   # absent -> silent no-op, never blocks
ponytail_version           # installed plugin version
ponytail_ruleset_sha256    # hash of the source AGENTS.md
ponytail_render_rules      # source AGENTS.md -> .ship/ponytail-rules.md
```
Rules are read from the installed plugin's shipped `AGENTS.md`, not copied into this
repo, so upstream fixes flow through without manual sync.

The plan task template gains `Read .ship/ponytail-rules.md before writing code.`,
alongside the `.ship/tdd-rules.md` line.

### 8.3 Scope boundary this design adds
ponytail's documentation does not address whether the ladder applies to test code.
Rung 1 ("does this need to exist? -> skip it") applied to a test is dangerous, and
JetBrains explicitly noted its benchmark "verifiers score whether a task was completed.
They are not a security, validation or accessibility suite", so ponytail's claim to
preserve error handling and security is unvalidated.

`.ship/ponytail-rules.md` therefore opens with a fixed header:
```
Scope: product code. Test code is out of scope for this ladder and is governed by .ship/tdd-rules.md.
```
Two files, two halves, no overlap.

### 8.4 Version pinning and drift
The global config `~/.claude/ship-workflow.yml` gains (global is correct here: one
ponytail install, one pin):
```yaml
ponytail:
  mode: full           # lite | full | ultra | off
  pinned_version: "4.8.4"
  ruleset_sha256: "..."
```
Every P5: hash the installed ruleset, compare to the pin.
- match -> render silently
- mismatch -> **use the new version**, and surface it:
  - interactive: show the version delta and a rule diff summary, offer
    `[A]ccept and re-pin / [S]kip / [C]ontinue without re-pinning`
  - `--auto:yes`: proceed, log to `.ship-auto-decisions.md`, and include a line in the
    P9 notification: `ponytail 4.8.4 -> 5.0.1, ruleset changed, this ship used the new version`

Hard-pinning with a cached copy was rejected: it forks the ruleset text (losing
upstream fixes) and depends on the operator remembering to bump, which is the §1.3
failure mode (principle P2).

### 8.5 `--auto:yes`
Runs. ponytail is preventive, not destructive; it stops code from being written and
deletes nothing. No gate required.

## §9 Phase 8.7: UA knowledge graph rebuild (new phase)

### 9.1 The broken loop being fixed
`ua_check_drift` warns on every stale run and tells the operator to run `/understand`.
The operator does not run `/understand`. The warning becomes noise, gets ignored, and
the graph keeps rotting while P3 and P6 continue consuming it. Above 50 files the
function itself prints `Blast-radius report will be misleading` and emits the report
anyway.

### 9.2 Not every ship
`/understand` is a full rebuild: project-scanner, batched file-analyzer,
architecture-analyzer, domain-analyzer, graph-reviewer, assemble-reviewer. Most ships
touch a handful of files and leave the graph almost entirely valid. No incremental
refresh exists in the UA plugin; `understand-diff` reads the graph rather than writing
it. So the options are full rebuild or nothing.

### 9.3 Threshold
Reuses `ua_check_drift`'s existing severity boundary rather than inventing a second
number (principle P6):
```
diff_count <= 50  -> skip; P9 summary prints "UA drift 12/50"
diff_count >  50  -> run /understand
```
The threshold is itself the rate limiter; 50-file drift is uncommon.

### 9.4 Placement
After P8.5, before P9. P8.5 no longer commits anything (§7.1), so ordering here is no
longer load-bearing for correctness; it is kept so the rebuilt graph reflects the tree as
P9 will leave it.

### 9.5 `--auto:yes`
Runs. Rebuilding is non-destructive: it produces a new graph and touches no source.
Because it is expensive, the P9 summary flags it explicitly:
`UA KG rebuilt (drift 73/50)`.

## §10 Resulting phase map

```
Phase 1    pre-flight + R-NNN resolution
Phase 1.5  UA drift check
Phase 2    open worktree
Phase 3    brainstorm        <- MOD: load CONTEXT.md; spec declares ## Seams
Phase 4    writing-plans     <- MOD: tasks label Seam:; refuse if ## Seams missing (auto)
Phase 5    executor          <- MOD: render .ship/tdd-rules.md + .ship/ponytail-rules.md
Phase 6    code review       <- MOD: mechanical gates + semantic categories + budget (shadow)
Phase 7    squash merge      <- MOD: commit message carries the test ratio line
Phase 8    ship-compound     <- MOD: write CONTEXT.md, prune if over cap (not in auto)
Phase 8.5  test prune report  <- NEW: scoped, report-only, deletes nothing, runs in auto
Phase 8.7  UA KG rebuild     <- NEW: only when drift > 50, runs in auto
Phase 9    cleanup + notify  <- MOD: summary carries CONTEXT/test/ponytail/UA lines
```

## §11 File change inventory

| File | Change |
|---|---|
| `commands/ship-next.md` | MOD: P3, P4, P5, P6, P7, P8, P9; new P8.5, P8.7 |
| `commands/ship-compound.md` | MOD: CONTEXT.md extraction + cap check |
| `lib/ponytail-integration.sh` | NEW: installed check, version, sha256, render |
| `lib/code-review-parse.sh` | MOD: three new finding categories |
| `lib/context-md.sh` | NEW: read, append, entry count, line count, prune |
| `lib/test-budget.sh` | NEW: baseline ratio, ship ratio, verdict, shadow-mode counter |
| `templates/repo/SPEC.md` | MOD: `## Seams` section |
| `templates/repo/PLAN.md` | MOD: `Seam:` line + two `Read .ship/...` lines in the task block |
| `examples/ship-workflow.example.yml` | MOD: document the global `ponytail:` block + test-budget multipliers (no shipped-count; see §6.3) |
| `SKILL.md` | MOD: §Global config section gains `ponytail:` and test-budget keys |
| `tests/test_ponytail-integration.bats` | NEW |
| `tests/test_context-md.bats` | NEW |
| `tests/test_test-budget.bats` | NEW |
| `tests/test_ship-next-no-ua.bats` | MOD: assert new phases no-op when deps absent |

## §12 Tunable parameters and known risks

### 12.1 ponytail inflates the test-budget ratio (second-order interaction)
The budget in §6.1.2 is `tests_added : src_added`. ponytail exists to shrink `src_added`.
A smaller denominator mechanically raises the ratio, so a successful ponytail run can
push an otherwise healthy ship into the `major` band and needlessly trigger P8.5. The
interaction gets worse the better ponytail performs.

Mitigation: §6.3 shadow mode. Collect 3 ships of real distribution **with ponytail
already active** before setting thresholds. Do not pre-tune.

### 12.2 Auto-writing CONTEXT.md
ETH Zurich (Gloaguen et al.) found LLM-generated agent instruction files reduced success
by roughly 3% and raised cost by over 20%, while human-written ones helped by roughly 4%.
That result concerns *behavioral rules*, which have no ground truth. A glossary entry
written immediately after shipping the code it describes is grounded and verifiable, so
the risk class differs. The §4.4 cap and pruning are the compensating control. **Revisit
if CONTEXT.md quality visibly degrades over the first ~10 ships.**

### 12.3 Parameters to tune after real data
| Parameter | Initial | Basis |
|---|---|---|
| CONTEXT.md trigger | 200 lines / 60 entries | Anthropic instruction-file guidance, borrowed |
| CONTEXT.md target | 150 lines | 25% headroom, chosen |
| test budget major | 2x baseline | placeholder, shadow mode will replace |
| test budget blocking | 4x baseline | placeholder, shadow mode will replace |
| shadow-mode ships | 3 | chosen |
| UA rebuild threshold | 50 files | reused from existing `ua_check_drift` |

### 12.4 Residual risks
- **Seam declaration quality.** A carelessly declared seam makes rule 1 in
  `.ship/tdd-rules.md` useless. The three-column format is a bet that cheap declaration
  beats thorough declaration. Watch whether `--auto:yes` specs produce usable seams.
- **P8.5 deletes nothing, so it carries no deletion risk.** The residual risk moved:
  candidates are surfaced but nothing enforces that the operator reviews them, so test
  debt can still accumulate in plain sight. Withdrawn with the gate: the earlier claim
  that flat coverage bounds the damage of automatic deletion.
- **Two new phases lengthen the auto cycle.** Both are conditional, but a ship that
  triggers both pays for a prune report plus a full UA rebuild. The P9 summary must make this
  cost visible so the thresholds can be raised if it bites.

## §13 Test strategy

- **bats, per new lib script.** Each of `ponytail-integration.sh`, `context-md.sh`,
  `test-budget.sh` gets a bats file covering: dependency absent (silent no-op),
  dependency present, and the boundary condition of its threshold.
- **Absent-dependency regression.** Extend `tests/test_ship-next-no-ua.bats` so a repo
  with no ponytail, no UA, and no `CONTEXT.md` still completes a full cycle unchanged.
  This is the single most important test: all three integrations must be additive.
- **Threshold boundaries.** Explicit cases at 199/200/201 lines, 59/60/61 entries,
  49/50/51 drifted files, and ratio exactly 2x and exactly 4x.
- **P8.5 destroys nothing.** The phase's mechanical half is `prune_report` in
  `lib/prune-report.sh`, so this is a unit test like any other: call the function with
  every verdict against a *dirty* fixture — an unstaged edit, a staged file, an existing
  `.ship/` — and assert the worktree, index, stash list, file hashes and HEAD are
  unchanged. The fixture must be dirty, or `git add`, `checkout`, `restore` and `stash`
  are no-ops that slip through.

  This replaced an extract-the-fences-and-execute-them harness over the command file.
  Four review rounds found defects in that harness rather than in the code it extracted:
  two pattern-matching guards were defeated outright (`/bin/rm`, `git -C . add`,
  `.ship/../tests/x.py`, `sed -e ... -i ''`), the non-major branch was never reached, and
  fences using tildes or four backticks were skipped. A guard that needs its own guard is
  a sign the code is in the wrong place.

- **P8.5 arguments are validated before they reach git.** `git diff "${a}...${b}"` puts
  the argument in git's option position, so a ref beginning with `-` is parsed as a flag:
  `prune_report '--output=tests/pwned' '' major` wrote a file and returned exit 0.
  Assert that git options passed as refs create nothing.

- **P8.5's command-file wiring is exhaustive, not sampled.** Its bash is two statements —
  source the lib, call the function — so assert that every non-comment statement is
  exactly one of those. Fence styles other than plain triple backticks are forbidden in
  that section rather than parsed, so a fence the extractor cannot see cannot exist.
- **Shadow mode.** Assert ships 1 to 3 emit no budget finding and ship 4 does.
- **Seam gate.** Assert `--auto:yes` exits 2 when the spec has no `## Seams`, and that
  interactive mode only warns.
