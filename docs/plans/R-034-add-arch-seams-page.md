# draw-arch seams page (replaces the module matrix) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete `/draw-arch`'s `matrix` page and `modules.py`, and add a `seams` page: one section per external system, whose touchpoints are found by a new `lib/seams.py` and re-verified by `check.py --repo`.

**Architecture:** `seams.py` scans `git ls-files '*.py'` with per-system probes (`ast` imports, line regexes) and writes `touchpoints` into the spec. `check.py` imports the same scan function to detect staleness. `render.py` gains `render_seams`. All of `matrix` goes.

**Tech Stack:** Python 3.9 stdlib only (`ast`, `re`, `fnmatch`, `subprocess` for `git ls-files` / `git rev-parse`), bats.

**Spec:** `docs/specs/R-034-add-arch-seams-page.md`. Its Seams table is the contract; AC numbers below refer to it.

## Global Constraints

- Python 3.9 stdlib only. Edit only `claude-skills/draw-arch/`, `claude-skills/ship-workflow/tests/` (test file and fixtures), `docs/tdd-rules.d/R-033.md` and `CONTEXT.md`. You are explicitly authorized to edit these skill directories.
- Never import or execute scanned source. Every scanned fixture file starts with `raise SystemExit(9)`, and tests assert the status is never 9.
- Offline output: use the existing `esc()`/`attr()`; no `<script`, no `on*=`, no literal `http(s)://`; deterministic bytes.
- `diagram`/`table`/`cards` output must stay byte-identical. The golden files and existing table/cards tests must keep passing untouched.
- zh-TW visible labels exactly as the spec writes them: 系統 / 能不能換 / 接觸檔 / 漏進核心 / 一句話 / 容易換 / 要改一些 / 很難換 / 換掉要改 / 檔案 / 行 / 位置 / 說明 / ❌ 漏進核心 / ✅ 在 adapter 內 / 沒有找到接觸點.
- Tests: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats`. Use the file's `$AD`, `$FX`, `$S`.

## Review Focus

1. A text probe that matches inside a comment or docstring still counts, because it is a line regex. The spec allows this; do not try to filter (Task 2 test pins a comment hit).
2. A file that fails to parse (e.g. Python 2 syntax) → text probes still hit, import probes skipped, file named once on stderr, exit 0 (Task 2).
3. An `import` probe `linebot` must not hit `linebotx` or `my_linebot` (Task 2, AC-3).
4. `from . import linebot` (relative) is not an import of the `linebot` package → no hit (Task 2).
5. A seams spec whose `exclude` covers a file drops it from touchpoints and from the stale check alike (Task 2).

---

### Task 1: Delete the matrix page and `modules.py`

**Files:** Delete `claude-skills/draw-arch/lib/modules.py` and `tests/fixtures/draw-arch/modrepo/`. Modify `render.py`, `check.py`, `SKILL.md`, `references/spec-format.md`, `test_draw-arch.bats`, `docs/tdd-rules.d/R-033.md`, `CONTEXT.md`.

**Interfaces:**
- Produces: `render.PAGES = ("diagram", "table", "cards", "seams")`. `seams` is accepted by the dispatch, but until Task 3 it is unimplemented: render exits 2.

- [x] **Step 1: Failing test** `"AC-2 matrix is no longer a page type"`. A minimal spec with `page: "matrix"`, `roots`/`modules`/`matrix`/`cycles` fields → `check.py` status 1 with a line starting `check: schema:`; `render.py page` status 2 and no output file; `[ ! -e "$AD/modules.py" ]`; `! grep -rq 'modules.py' "$AD/../SKILL.md" "$AD/../references"`.
- [x] **Step 2: Run** `bats tests/test_draw-arch.bats -f 'AC-2 matrix'` → FAIL.
- [x] **Step 3: Implement.**
  - Delete `modules.py`, `render_matrix`, `cycle_text`, the `.heat`/`.mods` CSS rules, the `matrix` schema and check branches, and the `modules` index rank.
  - Delete every test listed by `grep -n '^@test' tests/test_draw-arch.bats | grep -iE 'modul|matrix|cycle|src layout|stay unique|same child|non-integer|nested root|repository itself'`, plus their helpers (`init_modrepo`, `make_modules`, `mutate_matrix`) and the `modrepo` fixture.
  - Change the AC-7 index test from R-033 to expect the `modules` slot to be gone: overview, features, jobs, csat. Task 3 adds seams.
  - Remove the modules step from `SKILL.md` and the matrix section from `spec-format.md`.
  - In `docs/tdd-rules.d/R-033.md`, drop the ` · enforced by …` suffix from the path-derived-id rule. Its check is deleted, so it becomes a judgment rule; keep the text and `← R-033`.
  - In `CONTEXT.md`, delete the `**module matrix**` entry.
- [x] **Step 4: Run** the whole file → all pass. `bats tests/test_tdd-rules.bats` also passes.
- [x] **Step 5: Commit** `refactor(R-034): remove the matrix page and modules.py`.

### Task 2: `seams.py`, the seams schema and the stale check

**Files:** Create `claude-skills/draw-arch/lib/seams.py` and fixture dir `tests/fixtures/draw-arch/seamrepo/`. Modify `check.py` and the test file.

**Interfaces:**
- Produces: `seams.scan(repo: str, systems: list, exclude: list) -> dict` mapping `system id -> [{"file", "lines", "adapter"}]`; CLI `python3 seams.py <repo> <spec.json>`; `check.check_spec(..., repo)` handles `page: seams`.

- [x] **Step 1: Fixture** `seamrepo/` (tests copy it to `$S/repo`, `git init`, commit). Each file's first line is `raise SystemExit(9)`:
  - `core/a.py`: line 2 `import linebot.v3.messaging`, line 3 `URL = "https://api.line.me/x"`, line 4 `# calls api.line.me too`, line 5 `from . import linebot`.
  - `adapters/line.py`: line 2 `from linebot import X`.
  - `core/b.py`: line 2 `import linebotx`, line 3 `import my_linebot`.
  - `core/py2.py`: line 2 `print "api.line.me"`.
  - `tests/test_a.py`: line 2 `import linebot`.
  - `vendor/x.py`: line 2 `import linebot`.

  A spec fixture `seams.json` (page `seams`, `exclude: ["vendor/*"]`) has system `line` (`verdict: hard`, `summary`, `change: ["…"]`, probes `[{kind:"import",pattern:"linebot"},{kind:"text",pattern:"api\\.line\\.me"}]`, `adapters: ["adapters/*"]`, `touchpoints: []`) and system `dw` (`easy`, probe `import pymysql`, no adapters).
- [x] **Step 2: Failing tests.**
  - `"AC-3 seams.py finds import and text touchpoints, marks adapters, skips tests and excludes"`: run `seams.py "$S/repo" "$S/seams.json"`. Status ≠ 9 and 0. stderr names `core/py2.py` exactly once. `line` touchpoints == `[{file:"adapters/line.py",lines:[2],adapter:true},{file:"core/a.py",lines:[2,3,4],adapter:false},{file:"core/py2.py",lines:[2],adapter:false}]`. `dw` == `[]`. `repo.commit` is 40-hex. A second run is byte-identical (`cmp`). Set `note: "x"` on the `core/a.py` touchpoint, re-run → the note survives.
  - `"seams.py with a missing repo or spec exits 2 and writes nothing"`.
  - `"AC-4 check reports a stale system after the code changes"`: after the scan, `check.py --repo` exits 0 with no output. Append `import linebot` to `core/b.py` and commit → status 1, output exactly `check: seams: stale line`.
  - `"AC-6 seams schema findings"`: one mutation per run — duplicate system id → `check: id: duplicate system line`; `verdict: "maybe"` → `check: schema:`; `probes: []` → `check: schema:`; text pattern `(` → `check: schema:`.
- [x] **Step 3: Run** `-f 'AC-3|AC-4|AC-6|missing repo or spec'` → FAIL.
- [x] **Step 4: Implement `seams.py`.**
  - Files: `git -C <repo> ls-files -z '*.py'`, minus test paths (any path part `tests`/`test`, or basename `test_*.py`/`*_test.py`) and `exclude` globs (`fnmatch.fnmatch` on the posix relative path), sorted.
  - Import probe: walk the `ast`. `Import` → each `alias.name`. `ImportFrom` with `level == 0` → `node.module`. A hit is `name == pattern` or `name.startswith(pattern + ".")`, recorded at `node.lineno`. `ImportFrom` with `level > 0` never hits.
  - Text probe: `re.search` per line, 1-based.
  - Parse failure: skip import probes for that file and print `seams: cannot parse <file>` once to stderr.
  - `adapter` = any adapter glob matches.
  - Write back with `json.dumps(…, ensure_ascii=False, indent=2) + "\n"`. Keep notes keyed by `(system id, file)`. Update `repo.commit` with `git rev-parse HEAD`.
  - Missing repo/spec → stderr, exit 2.
- [x] **Step 5: Implement the check.** Schema for `page: seams`, per the spec's seams-spec row: `systems` list; `id` regex and unique; `title`/`summary` text; `verdict` in `("easy","medium","hard")`; `change` a list of text; `probes` non-empty with `kind` in `("import","text")` and `pattern` text, where text patterns must `re.compile`; `adapters` a list of text; `touchpoints` a list of `{file: text, lines: list of int, adapter: bool, note?: text}`; `exclude` an optional list of text. With `repo`: `scan()` and compare per system on `(file, lines, adapter)` → `check: seams: stale <id>`. Scan errors → `check: seams: cannot scan <msg>`.
- [x] **Step 6: Run** the whole file → pass.
- [x] **Step 7: Commit** `feat(R-034): seams.py scanner and seams check`.

### Task 3: The seams page, index order and docs

**Files:** Modify `render.py`, `SKILL.md`, `references/spec-format.md`, `CONTEXT.md` and the test file.

**Interfaces:** Consumes Task 2's spec shape. Produces `render.render_seams(spec) -> str`.

- [x] **Step 1: Failing tests.**
  - `"AC-5 seams page leads with a summary and lists leaks first"`: a spec with systems `line` (`hard`, touchpoints: one `adapter:true` `adapters/line.py` [2], one `adapter:false` `core/a.py` [2,3], the adapter one listed first) and `dw` (`easy`, `[]`). Assert:
    - the summary `<table>` comes before `<section id="sys-line">`;
    - its rows read `line`'s title, `很難換`, `2`, `1` and then `dw`'s title, `容易換`, `0`, `0`;
    - in `sys-line`, the index of `❌ 漏進核心` < the index of `✅ 在 adapter 內`, and `core/a.py` shows lines `2, 3`;
    - `sys-dw` contains `沒有找到接觸點`;
    - `換掉要改` is present; there is no `<svg`.
  - `"AC-7 index puts overview, features, seams, jobs first"`: replace the Task 1 version with order overview, features, seams, jobs, csat.
  - `"AC-8 seams text is escaped and offline"`: put `<script>alert(1)</script> https://evil.example` in summary, change and a note → no `<script>alert`, no `https://`, no ` on[a-z]+=`.
- [x] **Step 2: Run** → FAIL.
- [x] **Step 3: Implement.**
  - `render_seams`: the summary table (class `cat`; 系統 / 能不能換 / 接觸檔 / 漏進核心 / 一句話, where 接觸檔 = number of touchpoint files and 漏進核心 = number with `adapter:false`; the system title links to `#sys-<id>`).
  - Then per system: `<section id="sys-<id>">` with `<h2>` title + verdict label, the summary paragraph, `<h3>換掉要改</h3><ul>`, and a `cat` table 檔案 / 行 / 位置 / 說明. Leaked rows first, then adapter rows, each group in file order; leaked rows get `class="warn"`; lines are joined by `, `.
  - Verdict labels: `{"easy":"容易換","medium":"要改一些","hard":"很難換"}`.
  - Index rank: overview, features, seams, jobs.
  - `SKILL.md` step 2: the default topics are features, seams, jobs. Add a **seams** step:
    1. list the external systems from manifests, config keys and SDK imports;
    2. per system, write `probes` (SDK import prefixes, API hosts / REST paths as regex) and `adapters` (the files meant to own it);
    3. run `python3 "$SKILL_DIR/lib/seams.py" "$REPO" "$OUT/seams.json"`;
    4. from the touchpoints, write `verdict`, `summary`, `change` and notes on leaks;
    5. re-run `check.py --repo`.
  - `spec-format.md`: a seams section with the fields and one small example (it must pass `check.py` without `--repo`).
  - `CONTEXT.md`: add `- **seams page** — …` defining the 可替換性 page, probes, adapters and leaks (one entry).
- [x] **Step 4: Run** the whole file plus `bats tests/test_repo-layout.bats tests/test_sync-install.bats` → pass.
- [x] **Step 5: Commit** `feat(R-034): seams page, index order and docs`.

### Task 4 (Claude only — codex stops after Task 3): regenerate the langlive-line-oa pack

Not for the codex executor. Claude deletes `modules.json`/`modules.html` from the vault pack, writes `seams.json` (LINE, Confluence, LLM providers, Weaviate, data warehouse), runs `seams.py`, writes the verdicts, renders, rebuilds the index and reads the screenshot (AC-9).

## Execution log

- Baseline: draw-arch (65), tdd-rules (26), repo-layout (11), sync-install (21): 123/123 passed before implementation.
- Pre-flight: Tasks 1→2 share the page dispatch; `seams` is accepted in Task 1 and gains its schema/check in Task 2. Tasks 1→3 share the index; Task 3 inserts seams. Tasks 2→3 share the systems/touchpoints shape; all fields agree with the spec's Seams contract.
- Task 1 RED: `bats tests/test_draw-arch.bats -f 'AC-2 matrix'` failed because matrix was still accepted.
- Deviation: retain the three unused `.heat`/`.mods` rules in the frozen table/cards CSS — deleting them changes the output bytes, violating the spec's unchanged-output contract. The matrix renderer, scanner, schema and checks are removed; the seams page will omit these selectors.
- Deviation: remove matrix setup/assertions from the shared catalog-offline test and the removed scanner entry from the documentation allow-list — these call sites are outside the plan's test-name grep and otherwise require the deleted scanner; existing table/cards assertions remain intact.
- Task 1 compatibility baseline (SHA-256): clean `f52a0bdeb4c0eee87c11176b8aaf0a4edb47a65a8ef70f212f16c0bd6241e874`; minimal `bcb0ee4ad3febaf6d5dc1eedc6ef2385643a1d82d8720fcf36531b1f3117cae1`; jobs `fa4bdd5dae0a7a427e78363a6cdf647620a68426e33479d12d26885bb4b27809`; features `740451f20bf31f50f9b256b8643ccc51d5e2fdc5a3ff0be4ecef8c4d4cb9e5d0`.
- Task 1 complete: `bats tests/test_draw-arch.bats tests/test_tdd-rules.bats` → 80/80 passed; all four compatibility hashes unchanged.
- Task 2 RED: the prescribed filter ran 6 tests: the three new scanner/staleness/schema tests failed; the missing-input test passed immediately because Python also exits 2 for the absent script (per the plan's fail-first exception).
- Deviation: suppress the shared scanner's parse warnings during checker recomputation — the same fixture intentionally contains Python 2 syntax, while the plan requires a clean check to have no output and a stale check to print exactly one finding. The scanner CLI still prints each parse warning once.
- Task 2 test harness: declared Bats 1.5.0 as required by its `--separate-stderr` warning, matching existing repository test files.
- Task 2 complete: `bats tests/test_draw-arch.bats` → 58/58 passed.
- Task 3 RED: the page/index/escaping/documentation filter ran 6 tests; the five changed/new behaviors failed as expected (missing renderer, old index order and missing seams docs/example).
- Task 3 GREEN: `bats tests/test_draw-arch.bats` → 61/61 passed; `bats tests/test_repo-layout.bats tests/test_sync-install.bats` → 32/32 passed. All four compatibility hashes remain unchanged, and seams CSS contains no legacy heat/mods selectors.
- Task 3 visual QA: rendered only worktree fixtures and read desktop (1280 px) and 375 px iframe screenshots; summary, leak order/rose rows, empty state and phone cards are readable. Task 4 and the real vault pack were not touched.
- Deviation: also catch `OverflowError` when validating text regexes — `a{4294967296}` fails to compile in Python 3.9 and previously escaped as a traceback instead of the contracted `check: schema:` finding. Reproduced in memory and by the expanded AC-6 test (RED), then caught alongside `re.error` (GREEN).
- Final whole-change review: independent read-only reviewer approved Tasks 1–3 with no outstanding findings; independently reproduced and verified the regex-overflow repair, checked 112 schema type boundaries, and compared all four HTML fixtures byte-for-byte with `27ceab4`.
- Final review ruling: the five Review Focus behaviors stand as contracted, including comment text hits and parse-failure text-only scanning — changing them would lose or invent touchpoints.
- Final review ruling: retain the frozen table/cards CSS for byte compatibility and omit it from seams, as documented above — the cost is three unused rules in legacy page bytes.
- Final review ruling: leave non-UTF-8 decoding behavior unchanged; the scanner fails explicitly rather than skipping unreadable source — supporting legacy encodings is outside this plan; such a repository currently needs UTF-8 source before scanning succeeds.
- Final review ruling: Task 4 and AC-9 for the real vault pack remain reserved for Claude — Tasks 1–3 do not establish that real-pack acceptance.
- Task 3 complete: `bats tests/test_draw-arch.bats tests/test_tdd-rules.bats tests/test_repo-layout.bats tests/test_sync-install.bats` → 119/119 passed after the regex repair; `git diff --check` passed. No deferred minor findings.
