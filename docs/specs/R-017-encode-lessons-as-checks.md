---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-017
status: draft
tags: [ship-compound, tdd-rules, lessons, checks]
ai-first: true
---

## For future Claude
> `/ship-compound` step 6b turned a ship's lessons into one-line text rules in
> `docs/tdd-rules.d/`, and Phase 5 handed those rules to the executor to read. Nothing
> fails when an agent skips a rule.
>
> R-017 follows pstack's `/correct` and Matt Pocock's `/retro`:
> - A lesson a check can catch becomes a check: a test, a lint rule or an
>   `sn_mech_gates` gate. It is proven red on the real mistake and green on the fix.
> - Only judgment calls stay as text.
> - Every rule line records what enforces it, so the rule files are also the
>   rule ↔ enforcer table.
> - The executor reads only the judgment rules.
>
> Research: vault `10 Projects/ai_system/Research/pocock-pstack-into-ship-workflow.md`
> §3.

## Goals
- **G1.** Compound sorts this ship's lessons into *mechanical* and *judgment*. The
  lessons come from the blocking and important review findings, and from the learning's
  Bugs section.
  - **Mechanical** means a fixed pattern a check can detect.
  - **Judgment** is everything else.
- **G2.** Every mechanical lesson ends in a check, proven red on the mistake and green
  on the fix with `tdd_rules_prove`. The proof line goes into the learning.
- **G3.** Rule lines in `docs/tdd-rules.d/<R-NNN>.md` carry their enforcer
  (`· enforced by <check>`) or none (judgment). `tdd_rules_table` prints the
  rule ↔ enforcer table.
- **G4.** The executor's rendered rules (`.ship/tdd-rules.md`) list judgment rules only.
  The cap counts judgment rules only.

## Non-goals
- Retrofitting the 8 rules already in ai_system's `docs/tdd-rules.d/`. That is a
  follow-up: run the same classification over them once.
- Changing Phase 6 or its fix-plans. Fix-plans already start from a failing test, and
  that test is usually the check a lesson links to.
- A separate table file. The rule fragments are the table, kept one file per ship so
  that parallel reviews never conflict on it (R-001).

## Anti-goals
- **A "proof" that is green on the mistake.** A check that does not fail without the
  fix is not an enforcer. It stays a judgment rule.
- **Compound landing an unproven check on the base branch.** Checks written at compound
  bypass Phase 6. The red/green proof is what stands in for that review.

## Design

### Rule lines (lib/tdd-rules.sh)
- `tdd_rules_append <R-NNN> <text> [<enforcer>]`:
  - with an enforcer it writes `- <text> ← <R-NNN> · enforced by <enforcer>`;
  - without one it writes `- <text> ← <R-NNN>`, unchanged from today;
  - it stays idempotent on `<text>`;
  - given an enforcer, when `<text>` already exists as a judgment rule in any fragment
    (or the legacy file), it rewrites that line in place to add
    ` · enforced by <enforcer>`. The line keeps its original `← R-NNN` source. This is
    how a repeated mistake promotes an old rule. An already-enforced line is left as it
    is.
- **A judgment rule** is a rule bullet with no ` · enforced by ` marker.
  - `tdd_rules_render`'s "Learned in this repo" section lists judgment rules only.
  - `tdd_rules_count`, and therefore `tdd_rules_over_cap`, count judgment rules only.
    The cap exists to bound what the executor reads.
  - `tdd_rules_unsourced` still checks every rule.
- **`tdd_rules_table`** prints a markdown table `| Rule | Enforced by | Source |` with
  one row per rule bullet, in `tdd_rules_files` order.
  - The `Enforced by` cell is the enforcer, or `judgment`.
  - `Source` is the `R-NNN` after `←`, or `—` when the rule has none.
  - With no rules it prints nothing.

### Proof (lib/tdd-rules.sh)
`tdd_rules_prove <red-ref> <check-command> <check-path>...`, run from the repo root:
1. Adds a temporary detached worktree at `<red-ref>`. That is the commit with the
   mistake, normally the parent of the fix commit.
2. Copies each `<check-path>` from the current working tree into it, so the check
   exists but the fix does not.
3. Runs `bash -c "<check-command>"` there. It must exit non-zero.
4. Runs the same command in the current working tree. It must exit 0.
5. Removes the temporary worktree on every path, failure included.
6. Output:
   - **Success:** exit 0 and one line,
     `proof: red at <red sha7> (exit <n>) · green at <HEAD sha7>`, followed by the red
     run's last 3 output lines, indented. A red that failed for an environmental reason
     (a missing dependency) is visible to whoever reads it.
   - **Check passes at `<red-ref>`:** non-zero and `check does not fail on the mistake`.
   - **Check fails in the working tree:** non-zero and `check fails on the fix`.
   - **`<red-ref>` does not resolve or no path is given:** non-zero and a usage message.

### Compound step 6b becomes "Promote lessons into checks"
- **Candidates.** This ship's blocking and major findings (🔴/`[blocking]`, and
  🟡/`[important]`/`[major]`) from
  `/tmp/ship-next-{review,spec,security}-<ID>-*.md`, when present, and the learning's
  Bugs. Keep only lessons that could recur: a class, not a one-off typo.
- **Classify each candidate.**
  - **Mechanical:** a fixed syntactic pattern, a banned call, a file-location rule, a
    format, a behaviour a test can pin.
  - **Judgment:** everything else.
  - An existing judgment rule that this ship's mistake repeats is promoted to
    mechanical now.
- **Mechanical, highest level that works.**
  - **Architecture:** remove the second way, so the mistake cannot be written.
  - **A check, in the repo being compounded:** a test or a lint rule. Its failure
    message names the fix. A new `sn_mech_gates` gate is an option only when that repo
    is ai_system itself, because the gate lives in the shared skill. It is then proven
    by the bats test that exercises it.
  - Usually the fix's regression test already is the check, and the lesson just links
    to it.
  - Prove it with `tdd_rules_prove`, then record it with
    `tdd_rules_append "$ID" "<rule>" "<check>"`.
  - When the proof fails, the lesson becomes a judgment rule instead. In auto mode,
    log that with `auto-decision-log.sh … "P8" "lesson kept as judgment — proof failed"`.
- **Judgment:** `tdd_rules_append "$ID" "<rule>"`, as today.
- **Commit, when this step changed anything.**
  `git add -- <check files> docs/tdd-rules.d && git commit -m "lesson: ${ID} — <n> check(s), <m> judgment rule(s)"`.
  Commit before step 9, so the checks are reviewable as their own commit.
- **Print `tdd_rules_table`.** The existing over-cap and unsourced warnings stay.

### Learning
`templates/repo/LEARNING.md` and step 4's section list gain `## Lessons → checks`, one
line per lesson:
- `- <rule> — enforced by <check> · proof: red at … · green at …`, or
- `- <rule> — judgment`.

## Decisions
- leric, 2026-10-26: 「好 開工」 starts R-017. The research recommends this item as #3.
- My call (auto Q1): the table is the rule fragments themselves. Each line gains
  ` · enforced by <check>`, and `tdd_rules_table` renders the view.
  - A separate table file would be one more shared file (R-001's parallel-MR lesson).
  - Departure from the ROADMAP's done-when: it says mechanical lessons stay out of
    `docs/tdd-rules.d`. Here they are listed there with their enforcer, but they are
    filtered out of what the executor reads. That keeps the intent: no text rule to
    read for a lesson a check enforces.
- My call (auto Q2): the executor reads judgment rules only. The cap counts judgment
  rules only, because the cap bounds executor context.
- My call (auto Q3): the proof runs in a throwaway worktree at the red ref with the
  check overlaid. It prints the red run's tail, because an environmental failure is
  this approach's ceiling.
- My call (auto Q4): compound writes or links the checks and commits them as
  `lesson: <ID>` before step 9.
- My call (auto Q5): an unprovable check falls back to a judgment rule and is logged.
- My call (builder check): a check lives in the compounded repo, as a test or a lint
  rule. A `sn_mech_gates` gate only in ai_system, proven through its bats test.
- My call (builder check): promoting an existing judgment rule rewrites its line in
  place and keeps its source. In mr mode compound runs after the merge, one ship at a
  time (R-008), so the in-place edit does not bring back the parallel-review conflict.
- My call (builder check): "major" is what the parser counts as major: 🟡,
  `[important]`, `[major]`.
- My call (auto Q6): retrofitting existing rules is a follow-up.
- My call (auto Q7): the learning records each lesson's outcome under
  `## Lessons → checks`.
- The two `sn_ship_body` defects R-016 found (empty done-when, hard-coded attribution)
  are not folded in here. They are a separate small item.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `tdd_rules_append` | `tdd_rules_append <R-NNN> <text> [<enforcer>]` | Appends `- <text> ← <R-NNN>`, plus ` · enforced by <enforcer>` when given, to `docs/tdd-rules.d/<R-NNN>.md`. It is a no-op when `<text>` is already a rule, except with an enforcer on an existing judgment line, which it rewrites in place to add the marker and keep its source. Returns 2 for a non-R id or empty text. |
| `tdd_rules_render` | existing | "Learned in this repo" lists only bullets without ` · enforced by `. Universal rules and seams are unchanged. |
| `tdd_rules_count` / `tdd_rules_over_cap` | existing | Count only bullets without ` · enforced by `. |
| `tdd_rules_table` | `tdd_rules_table` (cwd in a repo) | Prints `\| Rule \| Enforced by \| Source \|`, a separator row, and one row per rule bullet in `tdd_rules_files` order. The enforcer, or `judgment`. The R-NNN, or `—`. Prints nothing when there are no rules. |
| `tdd_rules_prove` | `tdd_rules_prove <red-ref> <cmd> <path>...` (cwd repo root) | Exit 0 and `proof: red at <sha7> (exit <n>) · green at <sha7>` when `<cmd>` fails at `<red-ref>` with the paths overlaid and passes in the working tree. Non-zero with `check does not fail on the mistake`, `check fails on the fix`, or a usage message otherwise. Never leaves a worktree behind. Same results under bash and zsh. |
| ship-compound step 6b | command text | Names the mechanical/judgment split, the levels (architecture before a check), the repeat promotion, `tdd_rules_prove`, the three-argument `tdd_rules_append`, the `lesson: ${ID}` commit and `tdd_rules_table`. |
| `LEARNING.md` | template | Has a `## Lessons → checks` section, and step 4's list names it. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a repo | `tdd_rules_append R-9 "Quote X." "tests/t.bats::quotes"` | `docs/tdd-rules.d/R-9.md` holds `- Quote X. ← R-9 · enforced by tests/t.bats::quotes`; a second call adds nothing |
| AC-1b | `docs/tdd-rules.d/R-3.md` holds `- Quote X. ← R-3` | `tdd_rules_append R-9 "Quote X." "tests/t.bats::quotes"` | `R-3.md` now holds `- Quote X. ← R-3 · enforced by tests/t.bats::quotes`; no `R-9.md` line is added; a repeat call changes nothing |
| AC-2 | fragments with one enforced rule and one judgment rule | `tdd_rules_render` / `tdd_rules_count` | the render lists only the judgment rule; the count is `1` |
| AC-3 | the AC-2 fragments plus a legacy rule with no source | `tdd_rules_table` | a header, a separator, and three rows: the enforcer, `judgment`, `judgment`; sources `R-…`, `R-…`, `—` |
| AC-4 | a scratch repo: commit A where `f.sh` prints `bad`, commit B where it prints `good`; an uncommitted `check.sh` asserting `good` | `tdd_rules_prove A "sh check.sh" check.sh` at B | exit 0; output starts with `proof: red at <A sha7> (exit 1) · green at <B sha7>` |
| AC-5 | the same repo, check `true` | `tdd_rules_prove A "sh check.sh" check.sh` | non-zero; `check does not fail on the mistake` |
| AC-6 | the same repo, a check that fails at B | `tdd_rules_prove A …` | non-zero; `check fails on the fix` |
| AC-7 | any AC-4..6 run, an unresolvable ref, or no path | after it returns | `git worktree list` shows the same entries as before; a bad ref or no path gives non-zero with a usage message |
| AC-8 | AC-4 | run under `zsh -c` | same result as bash |
| AC-9 | ship-compound.md | step 6b is read | it contains `tdd_rules_prove`, `tdd_rules_table`, `enforced`, `judgment`, `lesson: ${ID}`, and the three-argument `tdd_rules_append` form |
| AC-10 | LEARNING.md and step 4 | read | both name `## Lessons → checks` / `Lessons → checks` |
| AC-11 | the full suite | `bats tests/` | green apart from the known cwd-guard failure in a linked worktree |

## Left to the builder
- How `tdd_rules_prove` captures the red run's output (a temp file is fine).
- The exact prose of step 6b, within the Design above.
