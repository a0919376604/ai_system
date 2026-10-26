---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-017
tags: [learning, ai_system, ship-compound, tdd-rules, lessons, checks]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-017
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> R-017: `/ship-compound` step 6b now turns a ship's lessons into **checks** wherever a
> check can catch them, after pstack `/correct` and Matt Pocock `/retro`.
> - A lesson counts as enforced only once `tdd_rules_prove` shows its check red at the
>   mistake's commit and green on the fix.
> - Rule lines in `docs/tdd-rules.d/` record their enforcer (` · enforced by <check>`),
>   so the fragments double as the rule ↔ enforcer table (`tdd_rules_table`).
> - The Phase 5 executor is handed judgment rules only.
>
> On its own compound it enforced 2 lessons with proven checks and added no text rules.

## What Shipped
- **`lib/tdd-rules.sh`**:
  - `tdd_rules_append <R-NNN> <text> [<enforcer>]`. With an enforcer, an existing
    judgment rule with the same text is promoted in place, keeping its source.
  - `tdd_rules_render`, `tdd_rules_count` and `tdd_rules_over_cap` see judgment rules
    only.
  - New `tdd_rules_table` and `tdd_rules_prove`. `tdd_rules_prove` is a subshell
    function with an EXIT trap, so no worktree is left behind on any path.
- **`commands/ship-compound.md`** step 6b, "Promote lessons into checks":
  - candidates: blocking/major findings and Bugs;
  - the mechanical/judgment split and repeat promotion;
  - levels: architecture first, then a test or lint;
  - a gate only in ai_system;
  - prove, record, and commit as `lesson: <ID>`;
  - print the table.
- **The learning** gains `## Lessons → checks` (template + step 4).
- **Tests**: 659 (+21); one known cwd-guard failure. Plus this ship's own lesson check
  (below).

## Key Decisions
- leric: 「好 開工」. Research item #3.
- The table is the rule fragments themselves, with no new shared file (R-001).
  - This departs from the ROADMAP done-when, which keeps mechanical lessons out of
    `tdd-rules.d`.
  - Enforced rules are listed there, but they are filtered out of what the executor
    reads, so the done-when's intent holds.
- The executor reads judgment rules only, and the cap counts them only.
- The proof is a throwaway worktree at the red ref with the check overlaid. It prints
  the red tail, because an environmental red is the approach's ceiling.
- Compound writes or links the checks and commits them as `lesson: <ID>` before step 9.
- An unprovable check falls back to a judgment rule and is logged.
- Retrofitting the 8 existing rules is a follow-up.
- From the builder check:
  - a check lives in the compounded repo (test or lint), and a `sn_mech_gates` gate only
    in ai_system;
  - promotion rewrites the old line in place, which is safe because compound runs one
    ship at a time after merge (R-008);
  - "major" means 🟡 / `[important]` / `[major]`.

## What Changed From Plan
- Codex (1 round, DONE_WITH_CONCERNS) made three local repairs:
  - the unsourced warning `[ … ] && printf` became an if-block (see Lessons);
  - a non-final `[[ ]]` table assertion gained `|| return 1`;
  - repeated promotion of an unsourced legacy rule wrote a duplicate fragment. Fixed by
    stripping the marker before comparing, with a red→green regression test.
- Review: the code review was inline (2 nits, 1 pre-existing). The Spec review sub-agent
  found "No spec gaps." The security pass found nothing. One attempt.
- Dogfood:
  - `tdd_rules_prove` was run on R-016's real multi-line-quote commit: red at `95c0cb4`,
    green at HEAD, worktree count unchanged.
  - Step 6b ran on this ship as its first real use.

## Bugs
- **The old step 6b's last line `[ -n "$UNSOURCED" ] && printf …` failed its block**
  whenever every rule had a source. It has been on main since R-004's era. Surfaced by
  the new test that executes the block.
- **Promotion of an unsourced legacy rule was not idempotent.** It compared text that
  still held the marker. Caught by codex's final self-review.

## Lessons → checks
- In a bats test, a non-final `[[ ]]` assertion needs `|| return 1`.
  - Enforced by `tests/test_suite-hygiene.bats`.
  - Proof: red at 1bcccbb (exit 1) · green at b078154.
  - The red tail names the fix: "add '|| return 1'".
- A command-file bash block must not end with `[ … ] && cmd`.
  - Enforced by `tests/test_block-endings.bats`, new.
  - Proof: red at 879796f (exit 1) · green at b078154.
  - The red tail cites `ship-compound.md:126`, the old 6b line.
  - This repeats part of R-004's judgment rule. R-004's rule stays judgment, because its
    command-substitution half has no check.

## Reusable Patterns
- **Prove a check on history you already have.** The ship branch and main's previous
  commit are free red refs. `tdd_rules_prove <old-sha> "<cmd>" <check>` turned "this
  test would have caught it" into a recorded fact in about one second.
- **A test that executes a block finds the bugs grep tests hid.** The 6b block's failing
  last line had been there for many ships.

## Technical Debt
- [pre-existing] Without an enforcer, `tdd_rules_append` dedupes by substring
  (`grep -qF`), so a short rule is swallowed by a longer one containing it. The enforcer
  path compares exact text. Key: `claude-skills/ship-workflow/lib/tdd-rules.sh:without
  an enforcer, tdd_rules_append st`. It could not be filed: ai_system has no
  `docs/ideas/`.
- Step 6b's commit block carries literal `<n>`/`<m>` placeholders that the prose asks to
  replace (review nit).
- `sn_ship_body` still has the empty done-when (`grep -A1`) and the hard-coded
  attribution. Both were fixed by hand in this body again.

## Future Follow-ups
- Run step 6b's classification over the 8 existing judgment rules once. Candidates:
  - ASCII bats names (R-013): a hygiene check;
  - the `(( )) &&` half of R-004: extend `test_block-endings`.
- The small `sn_ship_body` fix item: done-when lookup and attribution.
