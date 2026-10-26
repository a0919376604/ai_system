---
date: 2026-10-27
updated: 2026-10-27
type: learning
id: R-025
tags: [learning, ai_system, ship-workflow, refactoring, pocock, roadmap]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-025
shipped: true
shipped-date: 2026-10-27
---

## For future Claude
> R-025 added `/ship-refactor-scan [<direction>]`, ship-workflow's sixth command. It runs Matt
> Pocock's `improve-codebase-architecture` from verbatim copies in `templates/pocock/`. Upstream
> sets `disable-model-invocation: true`, so ship cannot call the skill.
>
> The command, in four steps:
> 1. Scopes the scan by `rs_hotspots`: 6-month churn × lines at HEAD.
> 2. Writes Pocock's HTML report to `<vault project>/Reports/`.
> 3. Has the operator pick cards.
> 4. Turns the picks into 🔜 Next rows through `rs_write_rows` and
>    `roadmap-insert.sh --next`. Every row's done-when carries three refactor guardrails.
>
> Its first real run, on langlive-line-oa, wrote **R-259**: the dashboard's in-memory/SQL
> double implementation.

## What Shipped
- **`templates/pocock/`:**
  - `improve-codebase-architecture/{SKILL,HTML-REPORT}.md` and
    `codebase-design/{SKILL,DEEPENING}.md`, byte-identical to `mattpocock/skills@5beb35b0`;
  - `LICENSE.upstream`;
  - `SOURCE.md`, holding each file's blob sha. A bats test re-hashes them.
- **`commands/ship-refactor-scan.md`:** steps 0–4, with Pocock's Process changed in four
  named places:
  - C1: hotspots set the scope, and earlier rejections are read first.
  - C2: the report goes to the vault, cards are `id="c<N>"`, and the header holds the hotspot
    table.
  - C3: `CONTEXT.md` stands in for `GLOSSARY.md`.
  - C4: no grilling; ship-next Phase 3 does it.
- **`lib/refactor-scan.sh`:**
  - `rs_hotspots [months] [top]`: a TSV of score, churn, lines and path. Lines come from one
    `git grep -I -c '' HEAD`.
  - `rs_done_when <outcome> [<reason>]`: the outcome plus the three guardrails, and
    `Door: one-way — …` when a reason is given.
  - `rs_write_rows <roadmap> <report>`: reads a TSV rows file, validates every line before
    any reservation, reserves IDs in order, inserts in reverse so Next reads in order,
    chains `after` rows to the previous ID and links each report card. It runs under bash
    and zsh.
- **`lib/roadmap-insert.sh --next`:** inserts under `## 🔜 Next` with no `status=`. With no
  Next heading it exits 1 and leaves the file untouched.
- **Install and docs:** `sync.sh` `COMMANDS` gained the command; `SKILL.md`, `README.md` and
  `CLAUDE.md` now say six commands.
- **Tests:** 738 (+20); the one known cwd-guard failure remains.

## Key Decisions
- leric:
  - 「我希望他是 ship workflow 的體系之一」: a ship command, not a separate skill.
  - 「我希望他是有整合 improve-codebase-architecture skill的」: Pocock's method is the core.
  - Dead-code scanning was dropped from v1.
  - 「R25 auto」.
- **Vendor, don't call.** Upstream is user-invocable only. The files are kept verbatim and
  checked against their shas, so a re-vendor is a reviewed diff, as with R-003's security
  prompt.
- **Rejected candidates go to `<vault>/Reports/refactor-scan-rejected.md`, not
  `CONTEXT.md`.**
  - This departs from the ROADMAP done-when, whose two clauses conflicted: "the scan must not
    change the repo" against "record rejections in CONTEXT.md".
  - `CONTEXT.md` is the capped vocabulary file.
  - The intent, that the next scan does not re-suggest a rejection, holds.
- **The guardrails are sequenced with Pocock's "replace, don't layer".**
  - `DEEPENING.md` says old shallow tests "become waste … delete them". That conflicts with
    "never change existing tests".
  - So: pin behaviour at the new interface first; leave existing tests untouched and green
    while structure moves; delete the replaced tests last, in their own commit.
- **A wide refactor is three top-level rows** (expand / migrate / contract), not epic
  children. `--mark-review` matches only top-level rows, so mr-mode repos would fail at
  Phase 8 on a child.
- **"Read-only" covers steps 0–2** (builder check).
  - Step 3 writes rows the way `/ship-next --adhoc` does: sync, reserve, insert, sync.
    That refreshes `docs/product/` and the gitignored `.claude/.id-reservations`.
  - Step 4 compares `git status` outside `docs/product/`.
- **Sync before reserving** (builder check): `id-gen.sh` reads the repo mirror, not the vault.
- **Rows go in a TSV file kept next to the report,** not a here-doc. Each command block runs
  in a fresh shell, and the file is the record of what was written.
- **AC-11 was run by Claude after the executor:** it needs judgment, and it writes a real row
  into line-oa's ROADMAP.
- Door: two-way.

## What Changed From Plan
- **Codex** (1 round, DONE_WITH_CONCERNS) recorded four local repairs:
  - `GIT_CEILING_DIRECTORIES` in the non-repo test, because the scratch dir sits inside the
    worktree;
  - `${G1}`-style braces next to full-width punctuation, which bash misparsed;
  - a zsh run of step 3;
  - `test_repo-layout.bats`'s command allow-list gained the sixth command.
- **Review:**
  - Attempt 1: the code review (inline) had 3 nits. The Spec review found 1 blocker (Bugs).
    It was fixed inline with TDD, at the size R-016 set as precedent, instead of a codex
    fix-plan.
  - Attempt 2: no spec gaps.
  - Security pass: 4 candidates, all below confidence 8 (the highest was 4), so none
    reported.
- **AC-11 on line-oa:**
  - Hotspots: `Admin.jsx`, `admin_dashboard.py`, `line_service.py` …
  - A time-boxed Explore sub-agent returned 5 cards. Spot checks held: 11
    `if store is not None`, the code's own 「雙實作」 warning at line 1196, and 65
    monkeypatches.
  - The report was saved as `Reports/refactor-scan-2026-10-27-0317.html`.
  - The pick became R-259. Step 4 printed `repo unchanged outside docs/product/`.

## Bugs
- **`rs_hotspots` counted lines on disk, not at HEAD** (`[spec:wrong]`, Spec review attempt
  1).
  - It ran `wc -l` on each `git ls-files` path.
  - So an uncommitted edit changed a file's count, and a file deleted on disk but tracked at
    HEAD vanished.
  - Fixed with one `git grep -I -c '' HEAD`. This also removed a `wc` fork per tracked file:
    the line-oa run takes 0.12 s.

## Lessons → checks
- A repo scan measures the committed tree (HEAD), never the working tree — enforced by
  `tests/test_refactor-scan.bats` "rs_hotspots: lines come from HEAD, not the working tree"
  · proof: red at 87bdffb (exit 1) · green at 1eef83a.

## Reusable Patterns
- **Vendor a user-only upstream skill and name your changes.** Keep the files byte-identical,
  record blob shas in `SOURCE.md` with a test that re-hashes them, and let the command list
  its deltas (C1–C4). A later upstream bump is then `diff` plus re-hash.
- **A builder check pays off on specs that touch shared machinery.** It found that "read-only"
  collided with `sync.sh` and `id-gen.sh` side effects that nobody had listed in the spec.
- **Spot-check an explorer's numbers before writing them into a report.** Here they held, but
  one test path was wrong (`tests/` rather than `tests/workers/`).

## Technical Debt
- **`roadmap-insert.sh` passes the row line and done-when through `awk -v`,** so a literal
  `\n` in a field becomes a line break in ROADMAP.md.
  - This was already true for DESC on main. `rs_write_rows` now makes it reachable from text
    an LLM writes (security finder, confidence 4).
  - Fix: pass them through `ENVIRON`, as `EXPLAIN_LINE` already is.
- [pre-existing] `roadmap-insert.sh --mark-review` matches top-level rows only. Worked around
  here; children in mr repos would still fail.
- The step-0 status snapshot uses a predictable `${TMPDIR:-/tmp}` path (security nit,
  confidence 2). On macOS, TMPDIR is per-user.
- The HTML report has no instruction to escape text taken from the repo (security nit,
  confidence 2).
- Review nits:
  - from a linked worktree, `lib/sync.sh` skips the mirror, so `id-gen` reads a stale copy;
  - `rs_done_when` exits 2 without a message.
- The commit title is the whole ROADMAP row, here over 400 characters. This is the existing
  `sn_ship_body` convention.

## Future Follow-ups
- `/ship-next R-259` in langlive-line-oa is the first refactor through the guardrails.
  - Watch whether Phase 3 resolves the in-memory tests cleanly: they are the "replaced
    shallow tests".
  - `admin_dashboard.py` is not in `one_way_paths`, so it auto-merges after CI. Cards 2 and 4
    touch `line_service.py` and would open a review.
- Dead-code scanning (vulture, knip) as its own item.
- Re-vendor when `mattpocock/skills` changes `improve-codebase-architecture`, by diffing
  against the `SOURCE.md` shas.
