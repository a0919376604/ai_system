---
date: 2026-11-04
updated: 2026-11-04
type: learning
id: R-033
tags: [learning, ai_system, draw-arch, architecture, catalog]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-033
shipped: true
shipped-date: 2026-11-04
---

## For future Claude
> R-033 gave `/draw-arch` three non-diagram page types, picked by a spec field `page`.
> - `table`: background programs, checked against a code registry through `ast`.
> - `cards`: one card per feature, with links to topic pages and job rows.
> - `matrix`: module import coupling, computed by the new `lib/modules.py`.
>
> A spec without `page` renders byte-identically to before, and golden files under
> `tests/fixtures/draw-arch/golden/` pin that.
>
> **Headline lesson:** the screenshot again found what 63 green tests did not. The jobs
> table had no name column, because the row id lived only in the anchor. The matrix never
> said which way it reads, and a seven-module cycle printed as `a ⇄ b ⇄ … ⇄ g`, which reads
> as a chain of pairs.

## What Shipped
- **`render.py`**
  - `page` dispatch: `diagram` (default) / `table` / `cards` / `matrix`.
  - Shared header and footer.
  - `CATALOG_CSS` extends the frozen diagram CSS. Only catalog pages use it, so diagram
    bytes stay unchanged.
  - The index lists overview, features, modules and jobs first.
- **`check.py`**
  - Per-page schemas.
  - `registry: {file, call, key?}` compares every literal `name=` of the call in the
    file, read through `ast`, with the rows. It reports `missing row` and
    `unresolved name at line`.
  - `check: link:` reports missing topics or job rows beside the spec.
  - `check: matrix: stale` recomputes the matrix with `--repo`.
  - `check: id: duplicate row|card|module`.
- **`modules.py <repo> <out> --root …`**
  - A module is each child of a root.
  - It counts import statements between modules, both absolute (the root also acts as a
    `sys.path` entry) and relative.
  - Cycles are the strongly connected sets of 2+ modules.
  - Test directories and files are skipped.
  - A re-run keeps `does`, `title` and `subtitle`.
- **Docs and tests**
  - SKILL.md step 2 adds the features, modules and jobs topics; spec-format.md documents
    every page type.
  - `test_draw-arch.bats` went from 36 to 65 tests.
- **The real pack for langlive-line-oa (vault, `6a7e40e`)**
  - modules: seven modules, all in one import cycle. Lower layers import upward:
    `core → domain` 12, `core → langgraph` 9, `domain → api` 4, `workers → api` 3.
  - jobs: 51 background programs. 30 are registered in `sweeper_specs.py`, which the
    registry check keeps clean; 21 run outside it. One row carries ⚠: `bucket_naming_cron`
    imports a script that is no longer in git.
  - features: 33 cards.

## Key Decisions
- **Ship all three as one row:** the operator, 「三點一起開成一列吧」.
- **Trigger:** the line-oa pack could not say how many modules there are, which background
  programs run, or how many features exist (operator).
- **One features page with cards,** not a page per feature; at 30+ features, separate pages
  rot (my call).
- **Module numbers come from a script,** never from reading. `ast` only, the same as the
  LangGraph check (my call).
- **A module is a child of a root the caller names.** The granularity comes from the roots;
  there is no `--depth` flag (my call).
- **Coupling is counts, fan-in/fan-out and cycles.** There are no derived scores (my call).
- **Jobs completeness is checked against the code's registry.** Rows outside the registry
  are allowed (my call).
- **A top-level `page` field.** Only `diagram` needs canvas, nodes and edges (my call).
- **The table is generic** (spec-named columns), not jobs-only (my call).
- **Index order:** overview, features, modules, jobs first (my call).
- **A re-run keeps** `does`, `title` and `subtitle` (my call).
- **Claude regenerates the real pack** after the build and reads screenshots (my call).
- **Door: two-way.** The change is additive inside `claude-skills/draw-arch/`, and diagram
  output is byte-identical.

## What Changed From Plan
- **Codex ran Tasks 1–4 in one round, DONE_WITH_CONCERNS.** It made three repairs:
  - Catalog CSS became a page-specific extension, because changing the shared CSS would have
    broken AC-1.
  - It added `raise SystemExit(9)` sentinels to every scanned fixture.
  - It handled `--root .`: the empty dotted prefix was missing.
- **Task 5 (Claude) added two things after reading the screenshots:**
  - Renderer: the matrix caption `列 → 欄`, normal styling for the fan-out column, and big
    cycles worded as 「N 個模組互相循環：…」.
  - Data: a 名稱 column on the jobs page, with 未登記 folded into it.
- **Review attempt 1 had 0 blocking and 2 important findings.** Both were reproduced and
  fixed in the ship instead of becoming IDEAs:
  - `--root src` gave an all-zero matrix;
  - roots sharing a basename, or a `foo.py` next to `foo/`, gave duplicate module ids.
- **Landing took two tries.** `sn_door` printed `mr` while the repo's `merge_mode` is
  squash, so landing first targeted `main`. That failed, because the main checkout holds
  `main`. It then squash-landed onto `ai_system-wt-1`.

## Bugs
- **`modules.py` resolved absolute imports only against dotted suffixes of the root path.**
  A src-layout root (`--root src`, `import foo`) matched nothing, and `check.py` called the
  all-zero matrix fresh.
- **Module ids were disambiguated with the root's basename.** Two roots ending in `pkg`
  collided, and so did a file next to a same-named package. Nothing checked for duplicates.
- **`id-gen.sh roadmap` handed out R-032 a second time.** It scans neither the vault ROADMAP
  nor the other checkouts' reservations. `id-gen.sh idea` likewise returned IDEA-006, which
  main already had. Filed as IDEA-007.

## Lessons → checks
- Derive an id from a path with the full relative path, not its basename, and reject duplicate ids in the checker — enforced by `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats -f 'stay unique|src layout'` · proof: red at c6fb884 (exit 1) · green at 526477c
- Give every catalog row a visible name column; an identifier that lives only in an anchor or attribute is invisible to the reader — judgment

## Reusable Patterns
- **Check a list against the code's own registry,** an `ast` read of the registering call's
  literal key. It turns "did we list everything?" from a review question into a check, the
  same move as the LangGraph topology check.
- **Freeze golden HTML before extending a renderer,** in a commit of its own. Byte-identical
  then becomes a `cmp`, not a claim.
- **Extend shared CSS by string replace into a page-specific copy.** The frozen pages never
  see the new rules.

## Technical Debt
- **Nits from review, not taken:**
  - the registry parse misses `ValueError` (a NUL byte gives a traceback);
  - `registry.file` is not confined to `--repo`;
  - an unreachable `unknown page` raise;
  - ungrouped table rows always render first;
  - several tests pin CSS text or bundle assertions (`[seam-violation]` / `[assertion-roulette]`);
  - the spec-format doc test greps words that already existed.
- **The jobs page's 名稱 column wraps identifiers mid-word.**
- **The bare root prefix lets a root child named like a stdlib module capture that import.**
  This is commented in `modules.py`.

## Future Follow-ups
- IDEA-007: `id-gen.sh` should scan the vault ROADMAP and every checkout's reservations.
- **line-oa, worth verifying and filing there:**
  - `bucket_naming_cron` fails on import;
  - several `kill_switch_env` values may never be read by the engine;
  - registry schedules that differ from real behaviour (`metrics_aggregator`,
    `kb_sub_type_merge`, `dw_*`);
  - the layering cycle `core → domain/langgraph`, `domain/workers → api`.
- **A second modules page at `--root backend/app/domain`.** It holds 191 files, but a heat
  table that large needs a different view.
