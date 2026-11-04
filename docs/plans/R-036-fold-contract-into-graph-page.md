# Fold the node contract into the LangGraph diagram page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `contract` page type and render the contract as a short 節點契約 section at the bottom of a diagram page whose spec carries a `contract` object. `contract.py` and the stale check move to that object.

**Architecture:**
- `contract.py` reads and writes `spec["contract"]`, not the top-level spec. `scan()` itself is unchanged.
- `check.py` validates the `contract` object inside diagram specs and runs the stale check there.
- `render_diagram` appends `render_contract_section(spec["contract"])` and uses `CSS + CONTRACT_CSS` only when the spec has a contract.

**Tech Stack:** Python 3.9 stdlib, bats.

**Spec:** `docs/specs/R-036-fold-contract-into-graph-page.md`. Its Seams table is the contract.

## Global Constraints

- Python 3.9 stdlib only. Edit only `claude-skills/draw-arch/`, `claude-skills/ship-workflow/tests/` (test file and fixtures) and `CONTEXT.md`. You are explicitly authorized to edit these skill directories.
- A diagram spec without `contract` must render byte-identically (golden files). So must the table, cards and seams pages.
- Never import or execute scanned source. Scanned fixtures keep their `raise SystemExit(9)` first line.
- Offline output: `esc()`/`attr()`; no `<script`, no `on*=`, no literal `http(s)://`. Verdict values reach classes only through the fixed mapping.
- zh-TW labels exactly: 節點契約 / 節點 / 讀 / 寫 / 好不好換 / 一句話 / 替換情境 / 必須讀 / 必須寫 / 沒有 / 容易換 / 要改一些 / 很難換 / ⚠ 掃描不完整： / ⚠ 找不到函式 / （路由）.
- Tests: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats`.

## Review Focus

1. A diagram spec with `"contract": {}` (an empty object) → `check: schema:` findings, not a crash (Task 1).
2. A node with 0 reads shows `0` with no `<details>` (Task 2, AC-5 variant).
3. A partial reason containing `<` renders escaped inside the 一句話 cell (Task 2, AC-7).
4. A scenario whose nodes write nothing shows `必須寫 沒有` (Task 2).
5. `contract.py` run on a seams/table spec → exit 2, file unchanged (Task 1).

---

### Task 1: Move the contract into diagram specs; remove the contract page type

**Files:** Modify `contract.py`, `check.py`, `render.py` (`PAGES`, dispatch, index rank) and the test file. Remove `render_contract` and the contract-page CSS hook, keeping `node_label`.

**Interfaces:**
- Produces: `check_spec` validates `spec["contract"]` on diagram specs, and `contract.py <repo> <diagram spec>` rewrites `spec["contract"]`.

- [x] **Step 1: Failing tests.** Convert the existing R-035 contract tests to the new shape. `init_lgrepo` now writes `$S/contract.json` as a copy of `$FX/lg.json` plus a `contract` object: `{graph: {file: "pkg/graph.py", state: "S", roots: ["."]}, nodes: [], declared: [], highlights: [], scenarios: []}`. Their assertions read `s["contract"]["nodes"]` instead of `s["nodes"]`, and the facts asserted stay the same. Add these tests:
  - `"AC-2 contract is no longer a page type"`.
  - `"AC-3 contract.py rewrites only the contract object"`: the diagram `nodes`, `edges` and `canvas` are equal before and after; `highlights`, `verdict` and `scenarios` survive.
  - `"contract.py refuses a spec without a contract object"`: try both a diagram spec without it and a seams spec. Each gives exit 2 with the file `cmp`-equal to before.
  - `"AC-6 contract highlights cap and scenario ids"`: 6 highlights give `check: schema:`; an unknown scenario node gives `check: edge: unknown scenario node zzz`; `"contract": {}` gives `check: schema:`.
  - Keep `"AC-4"` (stale after a source change; not stale after an unrelated commit) on the new shape.
  - Delete the tests for the removed contract page: AC-4 page findings, the finding hints, AC-6 index with contract, and AC-7 contract escaping. Task 2 adds their replacements.
- [x] **Step 2: Run** the whole file. The new and converted tests FAIL; everything else passes.
- [x] **Step 3: Implement.**
  - `contract.py`: load the spec. Require `spec.get("page", "diagram") == "diagram"` and a dict `spec["contract"]`, else exit 2. Validate it with `check_spec`, which must pass. Then scan with `spec["contract"]["graph"]` and write the computed fields into `spec["contract"]`, keeping `verdict`/`note` by id plus `highlights` and `scenarios`. Update `repo.commit`.
  - `check.py`: remove the `contract` page branch and validate a diagram spec's optional `contract` with the R-035 rules, plus `highlights` (a list of text, ≤5). The stale check runs on `spec["contract"]` and compares facts only.
  - `render.py`: `PAGES` drops `"contract"`; the index rank becomes overview, features, seams, jobs. Delete `render_contract`.
- [x] **Step 4: Run** the whole file → pass.
- [x] **Step 5: Commit** `refactor(R-036): contract lives in the diagram spec; contract page removed`.

### Task 2: Render the 節點契約 section, plus docs

**Files:** Modify `render.py`, `SKILL.md`, `references/spec-format.md`, `CONTEXT.md` and the test file.

**Interfaces:** Produces `render.render_contract_section(contract: dict) -> list[str]`. `render_diagram` inserts it after the condition table and before the footer, and passes `CSS + CONTRACT_CSS` to `document` only when `spec.get("contract")` exists.

- [x] **Step 1: Failing tests.**
  - `"AC-5 diagram page ends with a short 節點契約 section"`: scan, set the AC-5 values, render, and assert the spec's AC-5 list:
    - order: `class="diagram"` before `<section class="contract">` before `<footer`;
    - the exact `one` 讀 cell: `<details><summary>2</summary>a, b</details>`;
    - `refund`-style zero → `<td data-label="讀">0</td>` (use `ghost`: unresolved, so 0 reads);
    - `⚠ 掃描不完整：return helper(...)；state passed to helper` in `three`'s row;
    - `⚠ 找不到函式` in `ghost`'s row;
    - `route_one（路由）`;
    - the scenario line `換一和二 → 必須讀 a, b · 必須寫 c, d`;
    - no `熱點欄位` and no `id="node-`.
  - `"AC-1 a diagram without contract is byte-identical"` (golden `cmp`, already covered — keep it).
  - `"AC-7 contract section text is escaped and offline"`.
  - `"a scenario that writes nothing shows 沒有"`.
- [x] **Step 2: Run** → FAIL.
- [x] **Step 3: Implement** `render_contract_section` per the spec's contract-section row. The 必須讀 / 必須寫 derivation is R-035's: the reads of the resolved scenario nodes minus their writes, and their writes, both sorted. `CONTRACT_CSS` reuses the `.cat` table rules and the `v-*` tones, and turns rows into cards in the 700 px block. In `<summary>`, show the count; in the body, the fields joined by `, `.
  - **Docs:** SKILL.md gets the contract step from the spec's skill-workflow row. In spec-format.md, the contract section becomes a `contract` object of the diagram spec, with a small example that passes `check.py`. In CONTEXT.md, the `**contract page**` entry becomes `**node contract**`: a section of the LangGraph diagram page.
- [x] **Step 4: Run** the whole file plus `bats tests/test_repo-layout.bats tests/test_sync-install.bats` → pass.
- [x] **Step 5: Commit** `feat(R-036): 節點契約 section at the bottom of the LangGraph diagram page`.

### Task 3 (Claude only — codex stops after Task 2): update the langlive-line-oa pack

Not for the codex executor. Claude:
1. moves the contract into `langgraph.json`;
2. writes 3–5 highlights;
3. turns the scenarios into one-liners;
4. deletes `contract.json`/`contract.html`;
5. runs `contract.py`, `check.py --repo` and the renderer, then rebuilds the index;
6. reads the screenshot (AC-8).

## Execution log

### Task 1

- Baseline: `bats tests/test_draw-arch.bats` passed all 81 tests before changes.
- Red: converted scanner tests and new nested-contract schema tests failed as expected; unrelated tests stayed green. The refusal-without-contract test passed immediately because the old scanner already refused diagram/seams specs.
- Deviation: copy the existing `graph_ok.py` fixture into the scratch `lgrepo` — copying `lg.json` also retains `langgraph.file`, so `check.py --repo` needs that independent AST fixture. Shared fixtures remain unchanged.
- Deviation: migrate the executable contract JSON example and page-type list in `references/spec-format.md` during Task 1 — the existing documentation test otherwise fails as soon as the standalone page type is removed. Remaining documentation changes stay in Task 2.
- Green: all 82 draw-arch tests passed; `scan()` and all preceding analysis helpers remain unchanged.

### Task 2

- Red: all four new section-rendering tests failed before implementation; all 82 Task 1 tests stayed green.
- Deviation: keep the new Bats test names ASCII — `.ship/tdd-rules.md` explicitly requires ASCII names because CJK test names can be silently skipped under some locales. Assertions retain the exact zh-TW labels.
- Deviation: escape the SVG namespace through `attr()` only on diagrams carrying a contract — the new whole-page offline assertion exposed the existing literal `http://www.w3.org/2000/svg`. Encoding its colon preserves the namespace while removing the literal URL; diagrams without a contract keep their frozen bytes. No assertion was loosened.
- Green: `bats tests/test_draw-arch.bats` passed all 86 tests; `bats tests/test_repo-layout.bats tests/test_sync-install.bats` passed all 32 tests. Temporary directories were kept inside this worktree; sync tests used their scratch homes and mock vaults.
- Verified clean/minimal/LangGraph/table/cards/seams fixture output is byte-identical to the pre-task renderer. The R-035 scanner and analysis helpers remain unchanged.
- Tasks 1–2 are complete. Task 3 remains reserved for Claude; no real vault or other checkout was accessed, and nothing was pushed.
- Scoped result: DONE_WITH_CONCERNS solely for the recorded small plan deviations; no failing checks or unresolved implementation issues.
