---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-021
tags: [learning, ai_system, ship-next, merge, door, pr-body]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-021
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> R-021: each ship has a door (Matt Pocock `pr` skill, Merge Danger).
> - The door comes from the spec's Decisions `Door:` line; a missing line is one-way.
> - Mechanical signals escalate it to one-way, never the other way: migrations, new
>   dependencies, deploy/CI files, and base-branch `one_way_paths`.
>
> Routing:
> - A squash repo with a two-way door squashes.
> - An mr repo with a two-way door gets auto-merge, but only once its pipeline is
>   running or passed.
> - A one-way door always opens a review, in every repo.
>
> The body is Summary / Evidence / Merge Danger + Ship details. R-021 itself was one-way:
> it went through GitHub PR #1, and leric merged it (squash `1ff4a07`) after review.

## What Shipped
- **`lib/merge-mode.sh`:** `merge_mode` honours `SHIP_MERGE_MODE`;
  `forge_automerge_cmd`; `_sn_mr_iid`.
- **`lib/ship-next.sh`:**
  - `_sn_glob_match`, a bash `case` so zsh callers match too;
  - `_sn_one_way_paths`;
  - `sn_door`, which writes the safe values first;
  - `sn_auto_merge`, gated on pipeline status;
  - `sn_land` auto-merge and a door-aware failure message;
  - `sn_cleanup` loads state;
  - the Pocock body;
  - `door=` in the log, and the `• door:` summary line.
- **`ship-next.md`:**
  - Phase 3 requires `Door:`;
  - Phase 7 steps 0 (`sn_door`) and 0.5 (`.ship/pr-head.md`);
  - Phases 8 and 9 use the per-ship mode.
- **`SPEC.md` and the README.**

## Key Decisions
- leric: 「好 照建議」.
  - Two-way doors in mr repos auto-merge after CI.
  - The built-in signals, plus line-oa's paths.
  - R-021 runs `--auto:yes`.
- A missing door is one-way, and signals only escalate.
- A version bump is not a signal; a new dependency is.
- The per-ship mode lives in state and is honoured by `merge_mode()`.
- Auto-merge waits for a pipeline. glab merges at once when none is running.
- The agent writes Summary and Evidence; Merge Danger is computed.
- From the builder check:
  - R-021 landed by hand through a PR, because the live ship-next was still the old one;
  - a one-way ship with no forge stops rather than squashing.

## What Changed From Plan
- Review attempt 1 (inline code review + Spec review sub-agent) found 4 blocking and 1
  important. A codex fix-plan (attempt 2) closed them all; attempt 2 was clean.
- The spec was corrected after review: glab takes the MR iid, and this ship's own Door
  line had to start with `Door:` to count.

## Bugs
- **glab takes no URL.** `glab mr view [<id | branch>]`. The first version passed the
  MR URL, so auto-merge would never have been set on line-oa. The stub accepted
  anything, so the test pinned the assumption. This is the same class `forge_mr_cmd`'s
  comment records.
- **`sn_door` failed open.** An early return left no mode, so a squash repo squashed.
  It now writes the safe values first.
- **A quoted `` `Door: two-way` `` in Decisions could lower the door.** Only lines that
  start with `Door:` count now, and one-way wins.
- **A failed or canceled pipeline counted as "a pipeline".** glab would then merge at
  once. Auto-merge is now set only for running/pending/…/success.
- **A repo without `origin` stopped with no word about the one-way door.** (Spec review)

## Lessons → checks
- A forge-CLI stub must reject what the real CLI rejects: glab takes an MR iid, never a
  URL.
  - Enforced by `tests/test_ship-next-door.bats::a pipeline: auto-merge is set`.
  - Proof: red at aa0f6a4 (exit 1) · green at 1ff4a07.
- A safety gate writes its safe outcome before any check that can fail.
  - Enforced by `tests/test_ship-next-door.bats::failed door check persists safe routing`.
  - Proof: red at aa0f6a4 (exit 1) · green at 1ff4a07.
- A gate may lower a safety level only on explicit evidence. Judgment.

## Reusable Patterns
- **Check the real CLI's `--help` before trusting a stub.** Both glab defects (the
  invented flag earlier, the URL argument now) were invisible to permissive stubs.
- **A gate that can lower a safety level should only lower it on explicit evidence.**
  Anything ambiguous escalates.

## Technical Debt
- [pre-existing] The auto summary's first line says "shipped (squash <sha>)" for an mr
  ship. Not filed: ai_system has no `docs/ideas/`.
- Reasons are split on "; ", so a Door reason containing "; " becomes two bullets.
- The gh auto-merge path relies on branch protection to wait for checks. No GitHub
  repo uses mr mode today.

## Future Follow-ups
- A line-oa MR adding `one_way_paths` (push/broadcast, auth/webhook, deletion jobs,
  entrypoints) to its tracked `.claude/ship-config.yml`.
- Refine "every migration is one-way" with data, since additive migrations roll back.
