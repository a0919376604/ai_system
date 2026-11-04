---
date: 2026-11-04
updated: 2026-11-04
type: spec
id: R-034
tags: [spec, ai_system]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-034
---

## For future Claude
> R-034: replace `/draw-arch`'s module matrix page with a **seams** (可替換性) page.
> Each external system (LINE, Confluence, the LLM providers, Weaviate, the data
> warehouse…) gets a verdict (how hard it is to replace), every touchpoint in the code
> as `file:lines`, a mark for whether that touchpoint sits in an adapter or has leaked
> into the core, and what to change to swap it. A stdlib script finds the touchpoints;
> Claude writes the verdicts.

## Decisions

- Door: two-way — the change stays inside `claude-skills/draw-arch/`; removing the
  matrix page and adding the seams page are both reverted by one revert. (my call)
- The operator's question was not "who imports whom" but "can I add Discord next to LINE,
  can I swap Confluence for another editor". The R-033 matrix could not answer it:
  「module 耦合性那篇寫得不好」. Industry practice for that question is ports & adapters
  plus change-scenario review (ATAM) plus fitness functions. (operator + my research)
- Delete the matrix page entirely: `modules.py`, its page type, checks, tests and docs.
  (operator: 「矩陣頁 刪掉」)
- Cover every external system, not only LINE and Confluence: LLM providers, Weaviate and
  the data warehouse too. (operator: 「外部系統清單 要包含」)
- Touchpoints come from a script, never from Claude's reading. Claude declares each system's
  probes (import prefixes, text patterns) and adapter paths; `seams.py` finds every hit.
  `check.py --repo` reruns the scan, so the page cannot go stale silently. This acts as the
  fitness function. (my call, grilling Q1)
- Probes come in two kinds: `import` (an `ast` import of a module or its submodules,
  anywhere in the file) and `text` (a regex per source line, for hosts like `api.line.me`
  or REST paths). There is no call-graph analysis. (my call, Q2)
- Touchpoints are grouped by file, with the line numbers listed. A line-level table would
  run to hundreds of rows. (my call, Q3)
- Python files only (`git ls-files '*.py'`), skipping test paths, matching what the other
  scanners do. (my call, Q4)
- The verdict is one of three words: `easy` 容易換 / `medium` 要改一些 / `hard` 很難換,
  plus Claude's summary and change list. There is no numeric score. (my call, Q5)
- The R-033 enforced rule about path-derived ids loses its check with `modules.py`. It stays
  as a judgment rule. (my call, Q6)
- The real line-oa pack is regenerated and its screenshot read by Claude after the build.
  (my call, Q7)

## Seams

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| page types | spec `page`: `diagram` \| `table` \| `cards` \| `seams` | `matrix` is no longer a page type: `check.py` reports it as `check: schema:` and `render.py page` exits 2 without output. `diagram`, `table` and `cards` output is unchanged (golden files and existing tests). |
| seams spec | `systems: [{id, title, verdict, summary, change: [text], probes: [{kind: "import"\|"text", pattern}], adapters: [glob], touchpoints: [{file, lines: [int], adapter: bool, note?}]}]`, optional top-level `exclude: [glob]` | `id` matches `^[A-Za-z0-9_.:-]+$` and is unique (`check: id: duplicate system <id>`); `verdict` ∈ `easy`/`medium`/`hard`; `probes` is non-empty; a `text` pattern must compile as a Python regex (`check: schema:` otherwise). |
| seams scanner | `python3 lib/seams.py <repo> <spec.json>` | Rewrites `touchpoints` for every system and `repo.commit` (HEAD of `<repo>`), keeping everything else and each touchpoint's `note` by `(system, file)`. Scans `git ls-files '*.py'` minus test paths (`tests`/`test` dirs, `test_*.py`, `*_test.py`) and `exclude` globs. An `import` probe hits a line whose `import`/`from … import` names the pattern module or a submodule (`linebot` hits `linebot.v3.messaging`, not `linebotx`). A `text` probe hits each line where the regex matches. `adapter` is true when the file matches any of the system's `adapters` globs (`fnmatch` on the repo-relative path). Touchpoints are sorted by file, with lines ascending and unique. A file that fails to parse (including a NUL byte) gets text probes only and is named once on stderr (`seams: cannot parse <file>`); a file that cannot be read as UTF-8, or is missing, is skipped and named (`seams: cannot read <file>`). Line numbers count `\n` only. Source is never imported or run. A missing repo or spec exits 2 and writes nothing. Deterministic. |
| seams check | `check.py <spec> --repo <repo>` | Recomputes the touchpoints exactly as the scanner does. For each system whose `file`/`lines`/`adapter` set differs: `check: seams: stale <id>`. Without `--repo`, schema only. |
| seams page | `render.py page` | Opens with a summary table: 系統 / 能不能換 / 接觸檔 / 漏進核心 / 一句話, one row per system in spec order; 能不能換 shows 容易換 / 要改一些 / 很難換 with class `v-easy` / `v-medium` / `v-hard`, the same class on the section heading's verdict. Then one `<section id="sys-<id>">` per system: an `<h2>` with the verdict, the summary, a 換掉要改 list, and a touchpoint table 檔案 / 行 / 位置 / 說明. Leaked rows (`❌ 漏進核心`, rose) come before adapter rows (`✅ 在 adapter 內`); a system with no touchpoints shows 「沒有找到接觸點」. Same offline rules as every page: no `<script`, no `on*=` attributes, no literal external URL, all text escaped. Below 700 px, rows become cards. |
| index order | `render.py index` | overview, features, seams, jobs first, then the rest by topic. |
| skill workflow | `SKILL.md` step 2 | The default topics are features, seams and jobs; `modules` is gone. The seams step: list the external systems from manifests/config/imports, write probes and adapters per system, run `seams.py`, then write the verdict, summary, change list and notes from the touchpoints. |

## Acceptance

- **AC-1** Given the R-033 golden files and the table/cards fixtures, when rendered, then the
  output is unchanged.
- **AC-2** Given `page: "matrix"`, then `check.py` reports a `check: schema:` finding and
  `render.py page` exits 2 without writing. `lib/modules.py` no longer exists, and no test,
  doc or SKILL step mentions `modules.py`.
- **AC-3** Given a fixture repo:
  - `core/a.py` has `raise SystemExit(9)`, `import linebot.v3.messaging` on line 2 and
    `URL = "https://api.line.me/x"` on line 3;
  - `adapters/line.py` has `from linebot import X`;
  - `core/b.py` has `import linebotx`;
  - `tests/test_a.py` has `import linebot`.

  With system `line`, probes `import linebot` and `text api\.line\.me`, and adapters
  `adapters/*`, `seams.py` writes touchpoints
  `[{file: "adapters/line.py", lines: [1], adapter: true}, {file: "core/a.py", lines: [2, 3], adapter: false}]`.
  The exit status is never 9. A second run is byte-identical. A `note` added to `core/a.py`
  survives a re-run.
- **AC-4** Given that output, when a probe line is added to `core/b.py` and the change is
  committed, then `check.py --repo` reports `check: seams: stale line`. Before the change it
  exits 0.
- **AC-5** Given a seams spec with systems `line` (`hard`, one leak, one adapter) and `dw`
  (`easy`, no touchpoints), when rendered:
  - the summary table lists line then dw, with 很難換 / 容易換 and counts 2 / 1 and 0 / 0;
  - `<section id="sys-line">` lists the `❌ 漏進核心` row before the `✅ 在 adapter 內` row;
  - `sys-dw` shows 沒有找到接觸點;
  - there is no `<svg`.
- **AC-6** Given a duplicate system id, an unknown verdict, empty probes, or a text pattern
  `(`, then each gives its `check:` finding.
- **AC-7** Given a pack with `seams`, `features`, `jobs`, `overview`, `csat`, then the index
  order is overview, features, seams, jobs, csat.
- **AC-8** Spec text containing `<script>` and `https://evil.example` in summary, change and
  note renders escaped, with no literal external URL.
- **AC-9** (done when) Given langlive-line-oa re-run with `/draw-arch`:
  - the vault pack has no `modules` page;
  - `seams` has sections for LINE, Confluence, LLM providers, Weaviate and the data
    warehouse, each with a verdict, file:line touchpoints marked adapter or leak, and a
    change list;
  - `check.py --repo` is clean;
  - a screenshot was read.
