# Pack layout README.md + html/ + specs/ with a generated README — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `render.py readme <pack>`, which builds README.md from `<pack>/specs/*.json`, and switch SKILL.md to the three-entry pack layout.

**Architecture:** A new `render_readme(specs: list) -> str` lives in render.py. It reuses the index order and the page-type data that is already in each spec. `main` gains the `readme` subcommand. SKILL.md's paths move to `specs/` and `html/`.

**Tech Stack:** Python 3.9 stdlib, bats.

**Spec:** `docs/specs/R-037-add-pack-readme-layout.md`. The Seams table there is the contract.

## Global Constraints

- Python 3.9 stdlib only. Edit only `claude-skills/draw-arch/`, `claude-skills/ship-workflow/tests/` (the test file and fixtures) and `CONTEXT.md`. You are explicitly authorized to edit these skill directories.
- `page`, `index`, `check.py`, `seams.py` and `contract.py` are unchanged; golden files and every existing test must pass untouched.
- README text uses the zh-TW wording from the spec's readme-content row exactly: 架構圖包, 怎麼看這包, 每一頁, 怎麼更新, 系統 / 能不能換 / 接觸檔 / 漏進核心, 容易換 / 要改一些 / 很難換, 共 N 個：, 節點契約重點, `<group>：N 個`, 其他.
- Markdown-escape all spec text: `\`, `` ` ``, `*`, `_`, `[`, `]`, `<`, `>` and `|` get a backslash. Fixed text and generated links are not escaped. Link targets use only the validated topic slug.
- The output is deterministic and ends with exactly one newline.
- Tests: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats`.

## Review Focus

1. A spec without `subtitle` → no empty subtitle line (Task 1).
2. A seams spec with zero systems → the table header still appears, with no rows (Task 1).
3. A pack with only one diagram → the README still has all three `##` sections (Task 1).
4. A spec file whose `topic` differs from its filename → the link uses `topic`, the same as `index` does (Task 1).
5. Non-ASCII titles with Markdown characters, e.g. `A_B*C` → `A\_B\*C` (Task 1, AC-4).

---

### Task 1: `render.py readme`

**Files:** Modify `claude-skills/draw-arch/lib/render.py` and the test file.

**Interfaces:**
- `render.render_readme(specs: list) -> str`
- `render.md_escape(text: str) -> str`
- CLI: `render.py readme <pack dir>`, which reads `<pack>/specs/*.json` and writes `<pack>/README.md`. The usage line adds `| readme <pack dir>`.

- [x] **Step 1: Failing tests.**
  - `"AC-2 readme summarises every page and links html/"`: build `$S/pack/specs/` exactly as AC-2 describes, then assert each AC-2 value. Seams rows use the system titles from the fixture: titles `LINE` and `資料倉儲`.
  - `"AC-3 readme without specs or with a bad spec exits 2 and writes nothing"`.
  - `"AC-4 readme escapes spec text"`: put the AC-4 string into a subtitle, a card title, a seams system title and a highlight. Assert there is no `<script>`, no `](https://`, and every table row has exactly 5 unescaped `|` characters.
  - `"readme handles a lone diagram and a missing subtitle"`, covering Review Focus 1–4.
- [x] **Step 2: Run** `-f 'readme'` → FAIL.
- [x] **Step 3: Implement.**
  - Reuse the index sort key, with topic validation. Verdict labels come from the seams mapping.
  - Group counts follow first-seen order; a row without a group counts under `其他`.
  - Commit line: distinct `repo.commit[:7]` values, sorted and joined by `, `.
  - Write the fixed texts as module constants.
- [x] **Step 4: Run** the whole file → pass.
- [x] **Step 5: Commit** `feat(R-037): render.py readme builds the pack's README from its specs`.

### Task 2: SKILL.md layout and docs

**Files:** Modify `claude-skills/draw-arch/SKILL.md`, `references/spec-format.md` (one short "Pack layout" section), `CONTEXT.md` (refine the `architecture pack` entry), and the test file.

- [x] **Step 1: Failing test** `"AC-5 SKILL describes the README + html/ + specs/ layout"`. Assert that SKILL.md contains `README.md`, `html/`, `specs/` and `render.py" readme`, and that no line contains `specs/$topic.html` or `"$OUT/$topic.html"`.
- [x] **Step 2: Run** → FAIL.
- [x] **Step 3: Implement.**
  - Update every path in SKILL.md: specs go to `"$OUT/specs/<topic>.json"`, pages to `"$OUT/html/<topic>.html"`, and the index to `"$OUT/html/index.html"` from `"$OUT/specs"`. Step 6 adds `python3 "$SKILL_DIR/lib/render.py" readme "$OUT"`.
  - Step 1 adds `mkdir -p "$OUT/specs" "$OUT/html"`.
  - The report step links README.md first.
- [x] **Step 4: Run** the whole file plus `bats tests/test_repo-layout.bats tests/test_sync-install.bats` → pass.
- [x] **Step 5: Commit** `docs(R-037): pack layout README.md + html/ + specs/ in SKILL and references`.

### Task 3 (Claude only; codex stops after Task 2): migrate the langlive-line-oa vault pack

Codex does not run this task. Claude moves the vault pack into `specs/` and `html/`, re-renders every page and the index, runs `render.py readme`, runs `check.py --repo` on every spec, reads README.md and a screenshot of `html/index.html` (AC-6), and removes stray files from the top level.

## Execution log

- Pre-flight: Tasks 1–2 share the `readme <pack>` CLI and the `specs/` → `html/` + `README.md` layout; their interfaces agree with the spec's Seams table. Task 3 is excluded.
- Baseline: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats` passed 87/87.
- Task 1 RED: `bats tests/test_draw-arch.bats -f 'readme'` failed on the missing subcommand. AC-3 and the invalid-topic rejection test passed immediately because the existing usage rejection already exits 2 without writing output.
- Deviation: Markdown escaping also prefixes `(` and `)` with a backslash — escaping only the listed characters leaves the literal `](https://` substring forbidden by Task 1's AC-4 assertion. Escaping parentheses preserves displayed text and satisfies that assertion without weakening it. Cost if wrong: extra valid Markdown escapes in the generated source.
- Task 1 complete: `bats tests/test_draw-arch.bats` passed 94/94; all 87 existing tests and shared fixtures remain unchanged.
- Task 2 RED: `bats tests/test_draw-arch.bats -f 'AC-5 SKILL'` failed because SKILL.md lacked `README.md`.
- Task 2 complete: `bats tests/test_draw-arch.bats tests/test_repo-layout.bats tests/test_sync-install.bats` passed 127/127 on Python 3.9.6. Task 1 commit: `c7319c5`.
- Compatibility: compared the baseline renderer at `273fdde` directly with the implementation; six fixture pages and their index are byte-identical. Existing tests and fixtures were not edited.
- Final review: independent read-only reviewer found no Critical, Important or Minor issues and checked all five Review Focus items.
- Final: Ruling: an existing empty `specs/` may generate an empty-pack README, consistent with the existing index behavior and the Seams contract; a missing `specs/` still exits 2. Cost if wrong: an unintentionally empty pack gets a README instead of an error.
- Task 3 and AC-6 remain reserved for Claude; no migration, vault access, push or branch switch was performed.
