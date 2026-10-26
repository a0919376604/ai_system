---
date: 2026-10-27
updated: 2026-10-27
type: spec
id: R-019
status: draft
tags: [ship-next, review, codex, cross-model]
ai-first: true
---

## For future Claude
> When codex executes a plan, Claude's Phase 6 review is already a second model. When
> the executor is Claude (the small-change lane, executor 1 or 2), Claude reviews its
> own code. R-019 adds a codex review for those ships, after pstack's `interrogate`:
> "The adversarial signal comes from model diversity". Its findings join the code
> review's report, so they count and block like any other.
>
> A finding both models raised is marked `[both]`. That is the highest-signal finding.

## Facts (from real runs of codex-cli 0.162.1, 2026-10-27)
- `codex review --base <branch>` reviews the branch against `<branch>`. A custom
  `[PROMPT]` is rejected together with `--base` or `--commit`.
- stdout is the final message only; the session transcript goes to stderr.
- With findings, stdout has a `Full review comments:` line followed by blocks like:
  ```
  - [P1] Include the first item in the cart total — /private/tmp/r019-bug-repo/pay.py:3-3
    For any nonempty cart, `items[1:]` excludes …
  ```
- Without findings it is one prose paragraph (e.g. "No actionable regressions were
  identified…") and has no `Full review comments:` line.
- Paths are absolute and may be the resolved form: `/private/tmp`, not `/tmp`.

## Goals
- **G1.** `sn_cross_review <worktree> <review_out>`:
  - It does nothing, and prints `cross-review: skipped — codex wrote this code`, when
    the worktree's `.claude/.ship-executor` is `3`.
  - Otherwise it runs `codex review --base "$ORIG_BRANCH" -c model_reasoning_effort="high"`
    in the worktree, with stdin from `/dev/null`, under `timeout 600` when `timeout`
    exists.
  - It converts each `- [Pn] <title> — <path>:<a>-<b>` block into our format and
    **appends** it to `<review_out>`:
    - `P0`/`P1` → `🔴 [blocking] [codex] <title> — <relpath>:<a>`;
    - `P2` → `🟡 [important] [codex] …`;
    - `P3` → `🟢 [nit] [codex] …`;
    - the block's description lines follow, indented 3 spaces;
    - `<relpath>` is the path with the worktree prefix removed, in both its logical and
      `pwd -P` forms.
  - A codex finding gets `[both]` after `[codex]` when a line already in `<review_out>`
    cites the same `<relpath>:<n>` with `n` within `[a-3, b+3]`.
  - It persists `CROSS_REVIEW` = `skipped` | `unavailable` | `ran`, `CROSS_REVIEW_COUNT`
    and `CROSS_REVIEW_BOTH`.
- **G2.** When codex is missing, exits non-zero, times out or prints nothing, it prints
  `WARN: cross-review unavailable — <reason>`, leaves `<review_out>` unchanged, sets
  `CROSS_REVIEW=unavailable` and returns 0. The ship goes on.
- **G3.** Phase 6 runs it as step 1.3, after the code review writes `$REVIEW_OUT` and
  before the parse, on every attempt.
- **G4.** The log row gains `xreview=<count>/<both>` (or `xreview=skipped|unavailable`),
  and the auto summary gains `• cross-review (codex): …`.

## Non-goals
- A custom review prompt (the CLI forbids it with `--base`).
- Cross-review when codex was the executor.
- Changing `code-review-parse.sh`. `[codex]` lines use the existing severity tags.

## Decisions
- leric, 2026-10-27: 「R19 auto」.
- My call (auto Q1): `P0`/`P1` block, `P2` is important, `P3` is a nit. P1 is the gate
  in gstack's `/codex` too.
- My call (auto Q2): the findings append to the code review report, so one count and
  the existing fix-plan path cover them.
- My call (auto Q3): `[both]` means the same file within ±3 lines of the codex range.
  It is a cheap, explainable match.
- My call (auto Q4): an unavailable codex warns and the ship continues, as the done-when
  says.
- Facts were taken from real runs, not assumed, after R-021/R-023 showed that a stub
  can hide a CLI's real behaviour.
- Door: two-way — it adds a review step and never removes one; a revert walks it back.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_cross_review` | `sn_cross_review <worktree> <review_out>` (reads state) | As G1 and G2. It returns 0 in every non-crashing case, and never removes lines from `<review_out>`. |
| `sn_log` / `sn_summary` | existing | Default row has `xreview=…`; summary has `• cross-review (codex): …` |
| ship-next Phase 6 | command text | Step 1.3 calls `sn_cross_review "$WORKTREE" "$REVIEW_OUT"` before the parse. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | executor `2`; a stub `codex` printing the real sample (a P1 at `<wt>/pay.py:3-3`, a P2 at `<wt>/pay.py:8-8`); `review_out` holding `🟢 [nit] pay.py:4 — style` | `sn_cross_review` | `review_out` gains `🔴 [blocking] [codex] [both] Include the first item in the cart total — pay.py:3` and `🟡 [important] [codex] Restore the zero floor for refund balances — pay.py:8`, each followed by its indented description; state `CROSS_REVIEW=ran`, `CROSS_REVIEW_COUNT=2`, `CROSS_REVIEW_BOTH=1` |
| AC-2 | the stub prints paths under the `pwd -P` form of the worktree | `sn_cross_review` | the paths are still relative |
| AC-3 | the stub prints only "No actionable regressions were identified…" | `sn_cross_review` | `review_out` is unchanged; `CROSS_REVIEW=ran`, `CROSS_REVIEW_COUNT=0` |
| AC-4 | executor `3` | `sn_cross_review` | the stub is never called; `review_out` is unchanged; `CROSS_REVIEW=skipped` |
| AC-5 | no `codex` on PATH / the stub exits 1 / the stub prints nothing | `sn_cross_review` | returns 0, output has `cross-review unavailable`, `review_out` is unchanged, `CROSS_REVIEW=unavailable` |
| AC-6 | AC-1's appended report | `code-review-parse.sh` | `BLOCKING_COUNT` counts the codex P1 |
| AC-7 | state `CROSS_REVIEW=ran CROSS_REVIEW_COUNT=2 CROSS_REVIEW_BOTH=1` | `sn_log` default row / `sn_summary` | `xreview=2/1` / `• cross-review (codex): 2 finding(s), 1 also found by code review` |
| AC-8 | ship-next.md | Phase 6 read | a step `1.3.` calls `sn_cross_review "$WORKTREE" "$REVIEW_OUT"`; the loop comments name it before the parse |
| AC-9 | the full suite | `bats tests/` | green apart from the known cwd-guard failure |
