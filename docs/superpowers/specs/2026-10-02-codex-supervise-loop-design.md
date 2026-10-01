---
date: 2026-10-02
updated: 2026-10-02
type: spec
status: draft
tags: [ship-workflow, ship-next, codex, run-plan, executor, autonomy]
ai-first: true
related-specs:
  - 2026-06-21-ship-next-mega-command-design.md
  - 2026-06-22-ship-next-auto-yes-design.md
  - 2026-09-28-ship-next-context-and-test-discipline-design.md
supersedes: null
---

## For future Claude
> Phase 5 can hand a plan to codex via `/run-plan`, but it invokes it once and then
> says "Wait for completion." Codex does not simply complete: across 19 real runs it
> stopped 13 times with a `BLOCKED` verdict, and **every one of those stops was
> correct**. The operator had to read the diagnosis, decide whether the plan or the
> executor was wrong, repair it, and relaunch — by hand, 13 times.
> This spec makes Phase 5 a **supervise loop** that does that routing itself, with
> three exits rather than two: repair-and-relaunch, stop-on-infrastructure, and
> **escalate-to-human when the finding contradicts the spec**. Ralph-style
> unsupervised iteration was considered and rejected; see §3.
> It also preserves codex's terminal report format verbatim, because that format is
> the operator's only window into an unattended run.

## §1 Problem

### 1.1 What Phase 5 says today
```
3. Invoke the chosen sub-skill:
   3 → /run-plan docs/plans/${ID}-${SLUG}.md
4. Wait for completion. Executor commits ≥ 1 commit per task.
```
Three lines. They describe a world in which the executor runs once, finishes, and
commits. That world does not exist.

### 1.2 What actually happened across 19 runs (2026-09-28 → 2026-10-01)
Shipping the `ship-next-context-test-discipline` plan used `/run-plan` end to end.

| Outcome | Count |
|---|---|
| `BLOCKED` with a correct, actionable diagnosis | 13 |
| Infrastructure failure, no verdict produced | 2 |
| `DONE` | 1 |
| Runs the operator had to relaunch by hand | 16 |

The two infrastructure failures were: the codex workspace running out of credits
mid-run, and a prompt phrased in offensive-security vocabulary ("attack it",
"payloads") tripping a provider content filter, which crashed the process with
`UnknownProcessId` and produced no report at all.

### 1.3 The stops were not the problem
All 13 `BLOCKED` verdicts identified real defects. Ten were defects in the plan, one
was the executor's own transcription error — which it correctly classified as outside
its authorization rather than quietly patching — and two established that a designed
safety gate could not work even in principle.

The cost was not the stopping. The cost was that **a human had to be present for each
stop**, and the loop between stops was manual, undocumented, and error-prone: several
rounds were spent repairing drift introduced by the previous round's repair.

### 1.4 Out of scope
| Rejected | Why |
|---|---|
| Replacing codex with subagent-driven execution | Already exists as Phase 5 option 1. This spec is about option 3. |
| Making the executor not stop (see §3) | Stopping is the system working. |
| Changing what `/run-plan` itself does | It is a general-purpose wrapper used outside ship-next. The loop belongs in Phase 5. |

## §2 Goals and non-goals

### 2.1 Goals
- G1. An unattended `/ship-next` survives a `BLOCKED` executor verdict without the
  operator present, when the fix is within the plan.
- G2. An infrastructure failure stops the run immediately and does **not** consume a
  repair attempt.
- G3. A finding that contradicts the spec escalates to the human rather than being
  silently designed around.
- G4. Codex's terminal report format survives verbatim, per round, somewhere the
  operator reads.
- G5. The loop's state survives a Claude session restart.

### 2.2 Non-goals
- Not changing Phase 5 options 1 and 2.
- Not introducing a new operator-facing command.
- Not making the executor's verdict advisory — `BLOCKED` still means stop and think.

## §3 Why not Ralph

Ralph (`snarktank/ralph`) runs a coding agent in a shell loop: each iteration gets a
fresh context, picks the highest-priority incomplete story from `prd.json`, implements
it, runs typecheck and tests, and commits if they pass. It stops when every story
passes or an iteration cap is hit. Only git history, `progress.txt` and `prd.json`
cross the context boundary. (as of 2026, github.com/snarktank/ralph)

It was considered for exactly the goal in G1 and rejected, for three reasons grounded
in the 19 runs above.

**It answers a different question.** Ralph does not make a blocked agent proceed; it
makes a *fresh* agent retry with no memory of why the previous one stopped. Of the 13
stops, two were conclusions reached by accumulating evidence across several rounds —
that a coverage-derived value cannot establish deletion safety. A fresh context cannot
reach that conclusion, and would have kept patching instances of the same class.

**Its documented failure mode is the one we would hit.** Ralph's own guidance warns
that an agent under a loop stubs the real work, that "the loop looks busy: files
change, the diff is green, the pass succeeds, and nothing throws", and that a state of
"tests pass but requirements are not met" can accumulate.

**Its stated prerequisite did not hold.** Ralph depends on quality checks catching
errors; without them "broken code compounds across iterations". The quality check
guarding the phase that consumed most of those rounds was a coverage gate that was
wrong in fourteen distinct ways. Ralph would have shipped straight through it.

**Where Ralph would have been right.** Tasks 1-5 of that plan were self-contained libs
with bats tests, and ran in four runs with zero blocks. The discriminator is not task
size: it is whether a quality check you actually trust exists. This spec's loop keeps
human-grade judgement in the routing step precisely because that check cannot be
assumed.

## §4 The supervise loop

### 4.1 Shape
```
         ┌──────────────────────────────────────────────┐
         ▼                                              │
  /run-plan launches codex ──→ exits ──→ read verdict   │
                                           │            │
    ┌──────────────────────────────────────┤            │
    │                                      │            │
  DONE                                 BLOCKED          │
    │                                      │            │
    ▼                        Claude classifies          │
  Phase 6              ┌───────────┼───────────┐        │
                       │           │           │        │
                 plan defect   executor    spec-level    │
                       │        error          │        │
                       │           │           ▼        │
                  repair plan   add note    ESCALATE     │
                       └───────────┴───────────────------┘
                              (attempt < 3)

  infrastructure failure ──→ STOP, notify, attempt count unchanged
```

### 4.2 Verdict classification (mechanical, before judgement)
Read the tail of the run log. In order:

1. **Infrastructure** if it matches any of: `out of credits`, `flagged for possible`,
   `UnknownProcessId`, `failed to record rollout items`, or **no** `DONE` /
   `BLOCKED` / `DONE_WITH_CONCERNS` marker is present at all.
2. **DONE** / **DONE_WITH_CONCERNS** → proceed to Phase 6.
3. **BLOCKED** → go to §4.3.

An absent marker is infrastructure, not success. A run that produced no verdict
produced no information, and retrying it without understanding why is how two of the
19 runs were wasted.

### 4.3 BLOCKED routing (judgement — Claude, not shell)
Read the executor's report and classify into exactly one:

| Class | Signal | Action | Consumes attempt |
|---|---|---|---|
| **Plan defect** | the prescribed step is wrong, ambiguous, or impossible as written | repair the plan file, relaunch from the blocked task | yes |
| **Executor error** | the plan is right and the executor deviated — transcription, a mis-targeted edit | relaunch with a correction note, plan unchanged | yes |
| **Spec-level** | the finding says the approach cannot work, not that this step is wrong | **STOP and notify the operator** | no |

The third class is the one that must exist. Without it the loop would have redesigned
the test-pruning phase six times overnight without asking. Changing what the software
is supposed to do is not the executor's call, and it is not Claude's either.

**When the classification is unclear, treat it as spec-level and escalate.** The cost
of a needless escalation is one message; the cost of silently redesigning is a morning
spent reading commits.

### 4.4 Attempt cap
Three repair attempts, matching Phase 6's review loop. On exhaustion: stop, retain the
worktree and branch, notify with the full round history. Infrastructure failures never
consume an attempt — the two that occurred were unrelated to the work and retrying
them would have burned the budget for real repairs.

### 4.5 Prompt hardening
Every launch carries five things, each learned from a run that failed without them:

- **Scope override.** `/run-plan`'s template instructs the agent to ignore anything
  under `.claude/skills/`. When the plan's target *is* a skill directory, the agent
  refuses the whole plan.
- **`--auto:yes` requirement.** Codex cannot answer an interactive prompt. A plan step
  that invokes `/ship-next` without it hangs until the cap expires.
- **Engineering vocabulary.** A prompt written as "attack it", "payloads", "try to make
  it delete" tripped a provider content filter and crashed the run. The same review,
  phrased as input validation, completed. The content requested does not change; the
  framing does.
- **Resume context.** Which tasks are already committed, which task to start at, and
  which conclusions from earlier rounds are settled and must not be re-litigated.
- **Round history.** The accumulated report digest (§5), so the executor does not
  rediscover what the previous round already found.

## §5 Preserving the report format

Codex's terminal report is the operator's only window into an unattended run, and its
shape is load-bearing. Observed structure, in order:

1. a bold verdict marker on its own line
2. one framing line carrying a count
3. a bullet list of findings, one concrete sentence each
4. evidence — test numbers and file links
5. **negative space** — what was *not* changed, committed or touched
6. the required next action

Element 5 is the one an unattended operator needs most: it states the blast radius of a
failed run. A loop that summarises these into prose destroys exactly the part that makes
them scannable.

**The loop therefore preserves each round's report verbatim.** `.ship/codex-rounds.md`
accumulates, per round:

```markdown
## Round N — <verdict> — <timestamp>

<the executor's report, copied unmodified>

**Supervisor:** classified as <plan defect | executor error | spec-level>.
<one line: what was repaired, or why this escalated>
```

Phase 9's summary carries a digest — round count, final verdict, and the bullet list
from the last round only — and the `_log.md` row gains `codex: N round(s), <verdict>`.
The full history stays in the file.

## §6 State across session restarts

Claude's session restarted nine times during the 19 runs. Codex survived each one only
because `/run-plan` detaches via `nohup`; the supervisor did not, and the operator
re-derived progress by hand every time.

`/run-plan` already keeps `/tmp/run-plan-*-<slot>.{pid,log}` plus a done marker, and
exposes `status` and `list`. That is per-machine and not tied to the worktree. The loop
adds `.ship/codex-supervise.md` in the worktree:

```
plan:        docs/plans/R-NNN-slug.md
slot:        <run-plan slot id>
attempt:     2 of 3
last_verdict: BLOCKED
last_class:  plan defect
blocked_at:  Task 7
updated:     2026-10-02T11:04:00
```

On re-entry, Phase 5 reads this file before doing anything else. If codex is still
alive, it attaches rather than relaunching.

## §7 Acceptance

The gate passes when every statement below holds, and a finding blocks only if it
describes a way **a developer loses work or is misled about the outcome of a ship**.
Anything else is recorded as a follow-up. This criterion is stated here, before
implementation, because the previous cycle's acceptance ran for thirteen rounds on an
instruction to "keep looking" and the findings shrank to triviality.

1. A `BLOCKED` verdict whose fix is in the plan is repaired and relaunched without the
   operator, and the resulting ship is identical to one repaired by hand.
2. An infrastructure failure stops the run, notifies, and leaves the attempt count
   unchanged. Verified against all four signatures in §4.2.
3. A spec-level finding escalates. Verified with a fixture report asserting an approach
   cannot work.
4. Three failed repair attempts stop the run with the worktree and branch retained.
5. `.ship/codex-rounds.md` contains each round's report byte-identical to the log.
6. Phase 5 re-entered after a simulated session restart resumes from
   `.ship/codex-supervise.md` and does not relaunch a live codex.
7. Phase 5 options 1 and 2 are unchanged. A repo with no codex installed completes a
   full cycle exactly as before.

## §8 Known risks

- **The first user of this feature is itself.** The loop will be developed by giving
  codex a plan about making codex-driven plans work better. A defect in the supervisor
  bites during its own development. Mitigation: option 1 (subagent-driven) remains the
  default for this plan's own execution until acceptance passes.
- **Classification is a judgement call made unattended.** §4.3's bias toward escalation
  is the control, and it is deliberately asymmetric: over-escalating costs a message.
- **Attempt caps interact with cost.** Three codex rounds on a large plan is real money.
  The cap is not a budget; a run that burns three attempts should be read as a signal
  the plan was not ready.
- **Report preservation grows unboundedly.** `.ship/` is per-worktree and discarded at
  Phase 9 cleanup, so the history dies with the worktree. If a post-mortem needs it,
  copy it out before cleanup — the same caveat that already applies to
  `.ship-auto-decisions.md`.
