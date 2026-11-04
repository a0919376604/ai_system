# draw-arch catalog pages (table · cards · matrix) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `/draw-arch` three non-diagram page types: a `table` page (background jobs, checked against a code registry), a `cards` page (feature catalog), and a `matrix` page (module import coupling computed by a new `modules.py`).

**Architecture:** A new top-level spec field `page` dispatches `check.py` and `render.py` to per-type code. An absent `page` keeps today's diagram path byte-identical. `modules.py` is a stdlib AST scanner; `check.py` imports its `scan()` to detect a stale matrix.

**Tech Stack:** Python 3.9 stdlib only (`ast`, `json`, `pathlib`, `subprocess` for `git rev-parse`), bats.

**Spec:** `docs/specs/R-033-add-arch-pack-catalog-pages.md`. Read it: the Seams table is the contract, and the AC numbers below refer to it.

## Global Constraints

- Python 3.9 stdlib only; no new dependency. Files live in `claude-skills/draw-arch/` (this plan targets a skill directory, which you are explicitly authorized to edit).
- Never import or execute scanned source: `ast` only. Every new fixture that is scanned starts with `raise SystemExit(9)`, and the tests assert the exit status is never 9.
- Output stays offline: no `<script`, no `on*=` attributes, no literal `http://`/`https://` (use the existing `esc()`/`attr()`), deterministic bytes for identical input.
- Diagram output (absent `page` or `page: "diagram"`) is byte-identical to before R-033 (AC-1).
- zh-TW for every visible label. Use the existing palette (`KINDS`, `TONES`) and `CSS` conventions; phone rules go inside the existing `@media (max-width:700px)` block.
- Tests: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats`. Fixtures in `claude-skills/ship-workflow/tests/fixtures/draw-arch/`. Use the file's existing `setup()` vars `$AD`, `$FX`, `$S`.

## Review Focus

1. Empty `rows` / `cards` / `modules` lists → the page renders with its title and footer and no table/grid, and `check.py` exits 0 (Task 1, Task 2, Task 3 tests).
2. A registry call whose `name=` is a variable or f-string → `check: registry: unresolved name at line <n>`, never a silent skip (Task 1).
3. Two roots that both have a child `core` → ids become `<root basename>/core` for both, not a merged module (Task 3).
4. A spec value meant for an inline style (heat shade) comes only from numbers computed by the renderer, never from spec text; a non-integer matrix cell is a schema finding and a render exit 2 (Task 3).
5. A `cards` spec checked with no `jobs.json` beside it but a card with `jobs` → `check: link: missing job <id>` (absent file = no rows) (Task 2).

---

### Task 1: `page` dispatch, `table` page and registry check

**Files:**
- Modify: `claude-skills/draw-arch/lib/render.py`, `claude-skills/draw-arch/lib/check.py`
- Create fixtures: `golden/clean.html`, `golden/minimal.html`, `golden/lg.html`, `jobs.json`, `registry_ok.py` under `tests/fixtures/draw-arch/`
- Test: `claude-skills/ship-workflow/tests/test_draw-arch.bats`

**Interfaces:**
- Produces: `render.PAGES = ("diagram", "table", "cards", "matrix")`; `render.render_page(spec)` dispatches on `spec.get("page", "diagram")`, raising `SpecError("unknown page: …")` for others; `render.render_table(spec) -> str`; `render.src_text(src) -> str` (a string, or a list joined by `" / "`); `check.check_spec(spec, repo=None, spec_dir=None) -> list`; `check.extract_registry(path, call, key) -> (names: list, unresolved_lines: list)`.

- [x] **Step 0: Freeze the golden output (before touching render.py).** Render `clean.json`, `minimal.json`, `lg.json` with the current `render.py page` into `fixtures/draw-arch/golden/<name>.html`, and commit them alone: `git commit -m "test(R-033): freeze diagram golden output"`.
- [x] **Step 1: Write the failing tests.**
  - `"AC-1 diagram output is byte-identical to the frozen golden"`: render each of the three fixtures and `cmp` with its golden; also with `"page": "diagram"` added to `clean.json`.
  - `"AC-2 table page groups rows, marks warn and draws no svg"`: fixture `jobs.json` = `page: table`, `repo` as in `clean.json`, `columns` `[{key:"kind",label:"類型"},{key:"schedule",label:"頻率"},{key:"does",label:"做什麼"}]`, rows `csat_worker` (group `事件`), `dw_sync` (group `排程`, `warn: true`), `media_consumer` (group `事件`), each with `cells` and `src: "app/x.py:1-9"`. Assert: `<h2>事件</h2>` precedes `<h2>排程</h2>` and each appears once; `id="row-csat_worker"` present; exactly one `<tr class="warn"` and one `⚠`; headers `類型`/`頻率`/`做什麼`/`程式碼` in that order; no `<svg`; `check.py "$FX/jobs.json"` exits 0 with no output.
  - `"AC-3 registry check names the missing row and never runs the file"`: `registry_ok.py` = `raise SystemExit(9)` then three calls `Meta(name="csat_worker", …)`, `mod.Meta(name="dw_sync")`, `Meta(name="media_consumer")`, plus `Other(name="ignored")`. With `registry: {file: "registry_ok.py", call: "Meta"}` and all three rows → exit 0 (status ≠ 9). Drop `media_consumer` row → exit 1, output exactly `check: registry: missing row media_consumer`.
  - `"registry call with a non-literal name is reported"`: append `Meta(name=n)` to a copy of the fixture in `$S` → output contains `check: registry: unresolved name at line ` and status 1.
  - `"AC-8 unknown page is a schema finding and writes nothing"`: `page: "bogus"` → check output has `check: schema:` and status 1; `render.py page` exits 2 and the out file does not exist.
  - `"empty table renders title and footer only"`: `rows: []` → render exit 0, `<footer>` present, no `<table`; check exits 0.
- [x] **Step 2: Run** `bats tests/test_draw-arch.bats -f 'AC-2|AC-3|AC-8|non-literal|empty table'` → FAIL (AC-1 passes already).
- [x] **Step 3: Implement.**
  - `render.py`: `render_page` keeps today's body as `render_diagram(spec)`; header (h1 + sub line) and footer are shared so table/cards/matrix reuse them. `render_table`: rows in spec order, grouped by first-seen `group` (rows without a group come first, under no `<h2>`); `<table class="cat">` with `<th>` per column label plus `程式碼`; `<tr id="row-<id>">`, `class="warn"` + `⚠ ` prefix on the first cell for warn rows; missing cell → empty `<td>`. Add `.cat` CSS mirroring `.cond`, and inside the phone block turn `.cat` rows into cards with `td::before{content:attr(data-label)}` where each `<td data-label="<label>">` (escaped via `attr`).
  - `check.py`: `schema_errors` requires `page` ∈ `PAGES` when present; only `diagram` requires `canvas/nodes/edges` and runs the geometry rules; `table` requires `columns` (list of `{key,label}` text) and `rows` (list of `{id, cells: {text}, src}`; `id` matches `^[A-Za-z0-9_.:-]+$`; `warn` boolean; `group` text), duplicate row ids → `check: id: duplicate row <id>`. Registry: `extract_registry` walks `ast.Call`s whose `func` is `Name.id == call` or `Attribute.attr == call`; keyword `key` (default `"name"`) with a `str` `Constant` → name, else its `lineno` → unresolved. Findings in source order of names: `check: registry: missing row <name>`; `check: registry: unresolved name at line <n>`; `check: registry: file not found <path>`; `check: registry: cannot parse <path>: <exc>`. `main` passes `spec_dir=os.path.dirname(os.path.abspath(args.spec))`.
- [x] **Step 4: Run** the whole file `bats tests/test_draw-arch.bats` → all pass.
- [x] **Step 5: Commit** `feat(R-033): table page with registry check`.

### Task 2: `cards` page and link check

**Files:** Modify `render.py`, `check.py`; create fixture `features.json`; test file as above.

**Interfaces:**
- Consumes: Task 1's dispatch, shared header/footer, `src_text`, `check_spec(..., spec_dir)`.
- Produces: `render.render_cards(spec) -> str`.

- [x] **Step 1: Write the failing tests.**
  - `"AC-4 cards link topics and jobs and the check finds dangling links"`: copy `features.json` (one card `csat`: `title`, `does`, `entry`, `data`, `topics: ["csat"]`, `jobs: ["csat_worker"]`, `src: ["app/csat.py:1-20"]`) and `jobs.json` into `$S`, plus a minimal `csat.json` (copy of `minimal.json` with `topic: csat`). Check exits 0; render has `<article class="card" id="card-csat">`, `href="csat.html"`, `href="jobs.html#row-csat_worker"`, labels `入口` and `資料`. Then set `topics: ["nope"]`, `jobs: ["ghost"]` → status 1 with both `check: link: missing topic nope` and `check: link: missing job ghost`.
  - `"cards job link without jobs.json is missing"`: features.json alone in `$S` → `check: link: missing job csat_worker`.
  - `"empty cards renders title and footer only"`.
- [x] **Step 2: Run** `-f 'AC-4|without jobs.json|empty cards'` → FAIL.
- [x] **Step 3: Implement.** Schema: `cards` list of `{id, title, does, src: [text]}` with optional text `entry`/`data` and lists of slugs `topics` (`^[a-z0-9-]+$`) / ids `jobs`; duplicate card id → `check: id: duplicate card <id>`. Link rule runs only when `spec_dir` is given: topic exists iff `<spec_dir>/<slug>.json` is a file; job exists iff it is a row `id` in `<spec_dir>/jobs.json` (unreadable or absent → no ids). Render: grid `<div class="cards">` of `<article class="card" id="card-<id>">` with `<h2>` title, `does` paragraph, `<dl>` rows 入口 / 資料 when present, a links line (`相關頁面` topic links, `背景程式` job links), and `src_text` in muted small text. CSS: two-column grid on desktop, one column in the phone block.
- [x] **Step 4: Run** whole file → pass.
- [x] **Step 5: Commit** `feat(R-033): cards page with link check`.

### Task 3: `modules.py`, `matrix` page and stale check

**Files:** Create `claude-skills/draw-arch/lib/modules.py`, fixture dir `fixtures/draw-arch/modrepo/`; modify `render.py`, `check.py`.

**Interfaces:**
- Produces: `modules.scan(repo: str, roots: list) -> dict` returning `{"modules": [{id, root, files, lines}], "matrix": [[int]], "cycles": [[str]]}`; CLI `python3 modules.py <repo> <out.json> --root <dir> [--root …] [--name <repo name>]`; `render.render_matrix(spec) -> str`.

- [x] **Step 1: Build the fixture** `modrepo/pkg/` (not a git repo; tests `git init` a copy in `$S` and commit it so `repo.commit` resolves): `a/__init__.py` (`raise SystemExit(9)` then `from pkg.b import x`), `b/__init__.py` (`raise SystemExit(9)` then `from ..a import y` and `import os`), `c.py` (`raise SystemExit(9)` then `from pkg.b import x` and `import pkg.b.z`), `b/z.py` (empty), `tests/test_c.py` (`from pkg.c import q`). Root is `pkg`.
- [x] **Step 2: Write the failing tests.**
  - `"AC-5 modules.py counts cross-module imports, finds cycles and skips tests"`: run with `--root pkg --name demo`; assert via python: module ids `["a","b","c"]`, `matrix` a→b 1, b→a 1, c→b 2, rest 0, `cycles == [["a","b"]]`, no id `tests`, `page == "matrix"`, `roots == ["pkg"]`, 40-hex `repo.commit`; status never 9. Second run → `cmp` identical. Edit `modules[0].does = "入口"` and `subtitle = "x"` into the output, re-run → both preserved.
  - `"modules.py with a missing root exits 2 and writes nothing"`.
  - `"two roots with the same child name get prefixed ids"`: roots `pkg` and `other` both containing `core/` → ids `other/core`, `pkg/core`.
  - `"AC-6 matrix page shows fan-in, fan-out and the cycle; check finds a stale matrix"`: render → b's row shows fan-in 2 and fan-out 1 (assert on a `<tr id="mod-b">` row's cells), `a ⇄ b` present, heat cell for c→b carries `style="background:rgba(34,211,238,` and the 0 cells are empty; `check.py --repo` exits 0; append `from pkg.c import q` to `a/__init__.py` → `check: matrix: stale`. A spec with no cycles shows `沒有循環依賴`.
  - `"non-integer matrix cell is refused"`: set one cell to `"9);background:url(//x)"` → check schema finding, render exit 2, no output.
- [x] **Step 3: Run** `-f 'AC-5|AC-6|missing root|same child|non-integer'` → FAIL.
- [x] **Step 4: Implement `modules.py`.**
  - Modules: each immediate child of each root that is a package dir (has any `.py` below it) or a `.py` file other than `__init__.py`; skip names starting with `.`, `__pycache__`, `tests`, `test`; id = child stem, or `<root basename>/<stem>` for every module whose stem appears under 2+ roots. `files`/`lines` count `.py` files below it, skipping test files (`test_*.py`, `*_test.py`, any path part `tests`/`test`).
  - Resolution, per import statement in a module's file: resolve each target to a repo-relative file/dir path, then to the module containing it. Absolute name `x.y.z`: for each root, its dotted prefixes are every suffix of the root's path parts (`backend/app` → `backend.app`, `app`); the name belongs to module M under that root when it equals or starts with `<prefix>.<M>`. `from <prefix> import M` counts M too. Relative imports: resolve against the file's directory (`level` dots), then map the path to a module. One statement counts once per distinct target module; self-imports and unresolved names are ignored.
  - Cycles: strongly connected components of size ≥ 2 over edges with count > 0 (Tarjan or iterative Kosaraju), each sorted, list sorted.
  - CLI: missing root → stderr message, exit 2, no file. Output: `{topic:"modules", page:"matrix", title:"模組耦合", subtitle?, repo:{name, commit}, roots, modules, matrix, cycles}`, `json.dumps(…, ensure_ascii=False, indent=2, sort_keys=False)` + newline; preserve `title`, `subtitle` and per-id `does` from an existing out file.
- [x] **Step 5: Implement the page and check.** Schema: `roots` list of text, `modules` list of `{id, root, files:int, lines:int, does?}`, `matrix` square list of non-negative ints sized to modules, `cycles` list of lists of known ids. `check_spec` with `repo` imports `scan` (same `sys.path` trick as `render`) and compares `modules` (ignoring `does`), `matrix`, `cycles` → one `check: matrix: stale` finding. Render: heat `<table class="heat">` with module ids as row/column headers, cell text = count, `style="background:rgba(34,211,238,<alpha>)"` where `alpha = round(0.15 + 0.6*count/max, 2)` from the renderer's own numbers, empty `<td>` for 0; then a `<table class="cat">` of `<tr id="mod-<id>">` with 模組 / 做什麼 / 檔案 / 行數 / 被依賴 (fan-in) / 依賴 (fan-out); then `<h2>循環依賴</h2>` listing each cycle joined by ` ⇄ `, or `沒有循環依賴`. Wrap the heat table in the existing `pan()` box.
- [x] **Step 6: Run** whole file → pass.
- [x] **Step 7: Commit** `feat(R-033): modules.py and matrix page`.

### Task 4: Index order, skill docs

**Files:** Modify `render.py` (`render_index`), `claude-skills/draw-arch/SKILL.md`, `claude-skills/draw-arch/references/spec-format.md`; tests.

- [x] **Step 1: Failing tests.** `"AC-7 index puts overview, features, modules, jobs first"`: a dir with `jobs.json`, `overview.json` (copy of clean.json with topic overview), `csat.json`, `features.json`, `modules.json` → href order overview, features, modules, jobs, csat. `"AC-9 catalog pages stay offline"`: render jobs/features/modules fixtures with an `https://evil.example` string in a cell, card `does` and module `does` → no `<script`, no ` on[a-z]+=` attribute, no literal `https://`. `"spec-format documents the new page types"`: `spec-format.md` contains `page`, `columns`, `registry`, `cards`, `modules.py`.
- [x] **Step 2: Run** → FAIL (AC-7, docs).
- [x] **Step 3: Implement.** `render_index` sort key: rank 0–3 for `overview, features, modules, jobs`, else 4, then topic. `spec-format.md`: a section per page type with its fields (copy names from the Seams table) and one small `table` example. `SKILL.md` step 2: default topics add `features`, `modules`, `jobs`; new short steps: **modules** — run `python3 "$SKILL_DIR/lib/modules.py" "$REPO" "$OUT/modules.json" --root <each top-level source package>`, then write `does` per module; **jobs** — find the registry (`git grep -nE 'SweeperSpecMeta|add_job|@app.task|create_task|while True'` excluding tests), set `registry`, one row per job with 類型 (consumer / sweeper / cron / LLM 抽取 / 其他), 頻率, 做什麼, 開關; **features** — one card per user-visible feature traced from API routers and jobs, linking topic pages and job rows. Step 5 runs `check.py` for these pages too; the three-round screenshot rule is unchanged.
- [x] **Step 4: Run** whole file → pass; also `bats tests/test_repo-layout.bats tests/test_sync-install.bats`.
- [x] **Step 5: Commit** `feat(R-033): index order and skill docs for catalog pages`.

### Task 5 (Claude only — codex stops after Task 4): regenerate the langlive-line-oa pack

Not for the codex executor. Claude runs `/draw-arch` for `modules`, `jobs`, `features` against `~/Desktop/code/langlive-line-oa` into its vault pack, rebuilds the index, and reads a screenshot of each new page (AC-10).


## Execution log

- Scope: Tasks 1–4 only, inline execution on `ship/R-033-add-arch-pack-catalog-pages`; Task 5 remains reserved for Claude. This section is the execution ledger.
- Pre-flight: Task 1 dispatch/header/footer/src_text/spec_dir feed Tasks 2–3; Task 3 scanner output feeds the matrix page and Task 4 index. Interfaces match the Seams contract.
- Baseline: `bats tests/test_draw-arch.bats` passed 36/36. Test runtime temporary files are kept inside this worktree through `TMPDIR`.
- Task 1 Step 0: froze the three unchanged diagram outputs in commit `67ce8f1` alone.
- Task 1 RED: all five prescribed new behavior tests failed as expected; AC-1 passed immediately against the unchanged renderer. Additional registry/schema/group-order cases also failed before implementation.
- Deviation: catalog CSS is added through a page-specific extension of the existing CSS/phone block — changing the shared CSS would violate AC-1's byte-identical diagram contract.
- Task 1 complete: `bats tests/test_draw-arch.bats` passed 45/45; `git diff --check` passed. Table page, registry AST check, and schema dispatch implemented.

- Task 2 RED: all three prescribed cards tests and the schema/unreadable-jobs cases failed before implementation.
- Task 2 complete: `bats tests/test_draw-arch.bats` passed 50/50; `git diff --check` passed. No additional deviations.

- Deviation: added `raise SystemExit(9)` to the otherwise-empty `modrepo/pkg/b/z.py` and the skipped test fixture — the plan’s global sentinel constraint requires every new scanned-source fixture to start with it.
- Task 3 RED: the five prescribed tests and empty/schema/nested-root cases failed with the scanner absent; after scanner implementation the matrix render/schema tests still failed at their intended seam.
- Task 3 complete: `bats tests/test_draw-arch.bats` passed 58/58; `git diff --check` passed. AST scanner, deterministic CLI, matrix page and stale check implemented.

- Task 4 RED: AC-7 and documentation tests failed before implementation; AC-9 passed immediately using the existing escaping helpers.
- Final independent review: all five Review Focus cases checked; one Important finding reproduced independently at the CLI seam (`--root .` yielded an all-zero matrix). No Critical or Minor findings.
- Deviation: handle the empty dotted prefix for repository-root scanning — the plan's suffix algorithm omitted `--root .`, silently losing absolute imports required by the Seams contract. Added one regression, observed RED, then applied the two-line guard and observed GREEN.
- Final: Ruling: Task 5 real-pack regeneration and screenshot acceptance remain with Claude — explicitly excluded by the executor's scope; cost: real-pack/visual acceptance is still pending that handoff.
- Task 4 complete: `bats tests/test_draw-arch.bats` passed 62/62 and `bats tests/test_repo-layout.bats tests/test_sync-install.bats` passed 32/32 after the review repair, on Python 3.9.6; `git diff --check` passed. Index order, skill workflow and per-page format documentation implemented; the three-round screenshot rule is unchanged.
- Final status: DONE_WITH_CONCERNS (three small plan repairs recorded above; no unresolved review finding). Task 5 was not run. All executor changes remain in this worktree and no remote push was performed.
