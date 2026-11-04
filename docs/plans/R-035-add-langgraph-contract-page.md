# draw-arch LangGraph node-contract page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `contract` page to `/draw-arch`. A new `lib/contract.py` resolves each LangGraph `add_node` to its function through `ast` and records the state fields it reads and writes; `check.py --repo` reports staleness; `render.py` draws the node table, field findings, scenarios and per-node sections.

**Architecture:** `contract.scan(repo, graph) -> dict` is shared by the CLI and `check.py` (the same pattern as `seams.scan`). `render_contract` derives the findings and the scenarios' must-read/must-write lists from the computed fields.

**Tech Stack:** Python 3.9 stdlib (`ast`, `json`, `subprocess` for `git rev-parse`), bats.

**Spec:** `docs/specs/R-035-add-langgraph-contract-page.md`. Its Seams table is the contract.

## Global Constraints

- Python 3.9 stdlib only. Edit only `claude-skills/draw-arch/`, `claude-skills/ship-workflow/tests/` (test file and fixtures) and `CONTEXT.md`. You are explicitly authorized to edit these skill directories.
- Never import or execute scanned source. Every scanned fixture file starts with `raise SystemExit(9)`; tests assert the status is never 9.
- `diagram`/`table`/`cards`/`seams` output stays byte-identical. Golden files and existing tests must pass untouched. Reuse `SEAMS_CSS` (or derive from it) for the contract page; do not edit the CSS the other pages use.
- Offline output via the existing `esc()`/`attr()`; no `<script`, no `on*=`, no literal `http(s)://`; deterministic bytes. Verdict values reach class names only after mapping through the fixed dict (`v-easy` etc.), and render refuses others (exit 2), as seams does.
- zh-TW labels exactly: 節點 / 讀 / 寫 / 好不好換 / 說明 / ⚠ 掃描不完整 / ⚠ 找不到函式 / 熱點欄位 / 只讀沒人寫 / 只寫沒人讀 / 宣告了但沒用 / 沒有 / 替換情境 / 必須讀 / 必須寫 / 容易換 / 要改一些 / 很難換.
- Tests: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats`.

## Review Focus

1. A node bound with `functools.partial(fn, …)` or a lambda → `resolved: false`, not a crash (Task 1 test).
2. Re-exports that loop (`a` re-exports from `b`, which re-exports from `a`) stop at 5 hops → `resolved: false` (Task 1).
3. A node function with `**kwargs` and no positional parameter → no reads, plus partial reason `no state parameter` (Task 1).
4. A `return {**state, "k": v}` dict → writes `k` only; the `**state` spread is ignored (Task 1).
5. An async node (`async def`) resolves like a sync one (Task 1).

---

### Task 1: `contract.py`, the contract schema and the stale check

**Files:** Create `claude-skills/draw-arch/lib/contract.py` and the fixture dir `tests/fixtures/draw-arch/lgrepo/`. Modify `render.py` (only `PAGES`: add `"contract"`), `check.py` and the test file.

**Interfaces:**
- Produces:
  - `contract.scan(repo: str, graph: dict) -> {"nodes": [{id, file, line, reads, writes, partial, resolved}], "declared": [k]}`, with nodes in `add_node` order;
  - CLI `python3 contract.py <repo> <spec.json>`;
  - `check_spec` handles `page: contract`.

- [x] **Step 1: Fixture** `lgrepo/` (tests copy it to `$S/repo`, then `git init` and commit), exactly as AC-2 describes. Also add, for the Review Focus:
  - `n5 = functools.partial(n1)` in `impl.py`, re-exported and added as `five`;
  - `async def n6(state)` reading `a` and returning `{**state, "c": 1}`, added as `six`;
  - `def n7(**kw)` returning `{}`, added as `seven`;
  - a re-export loop `pkg/loop_a.py` ↔ `pkg/loop_b.py` for name `looped`, added as `eight`.

  `graph.py` imports nodes as `from pkg.nodes import n1, make_n2, …` with `roots: ["."]`.
- [x] **Step 2: Failing tests.**
  - `"AC-2 contract.py resolves nodes and lists reads, writes and partial reasons"`: assert the AC-2 values for one–four and ghost, then the Review Focus:
    - `five` and `eight` are `resolved: false`;
    - `six` reads `[a]` and writes `[c]`;
    - `seven` has partial `["no state parameter"]`;
    - `declared` is `["a","b","c","d","unused"]`;
    - a second run passes `cmp`;
    - setting `verdict: "easy"` on `one` survives a re-run;
    - the status is never 9.
  - `"contract.py with a missing graph file or state class exits 2 and writes nothing"`.
  - `"AC-3 check reports a stale contract"`: clean → exit 0 with no output; after adding `state["d"]` to `n1` and committing → `check: contract: stale`.
  - `"AC-5 contract schema findings"`: unknown scenario node gives `check: edge: unknown scenario node zzz`; a duplicate node gives `check: id: duplicate node one`; `verdict: "maybe"` gives `check: schema:`.
- [x] **Step 3: Run** `-f 'AC-2 contract|AC-3 check reports a stale contract|AC-5 contract|missing graph'` → FAIL.
- [x] **Step 4: Implement `contract.py`.**
  - **Module lookup:** a dotted name `x.y` resolves under each root to `<root>/x/y.py` or `<root>/x/y/__init__.py`.
  - **Name resolution:** `resolve(module_file, name, hops)`:
    - a top-level `def`/`async def` named `name` → that node;
    - an `ImportFrom` in the module that binds `name` → recurse into the target module (absolute imports through the roots; relative imports against the file's package);
    - more than 5 hops, an `Assign` binding, or not found → unresolved.
  - **Graph walk:** walk `graph.file` for `<x>.add_node(<str>, <expr>)` calls in source order:
    - a `Name` expression → resolve it in the graph file's own namespace (its imports, or a local def);
    - a `Call` whose `func` is a `Name` → resolve the factory, then take the inner `def` named by the factory's `return <Name>`;
    - anything else → unresolved.
  - **Analysis of the function:** the state parameter is the first positional parameter. Without one → partial `no state parameter`.
    - Reads: `Subscript` (Load) on that name with a `str` `Constant` key, and `<name>.get(<str>)`.
    - Writes:
      - keys of `return <Dict>` (`str` constant keys only; `**` entries ignored);
      - for `return <Name>` where that name is assigned a `Dict` in the function: its constant keys, plus `<Name>["k"] = …` and `<Name>.update({...})`/`update(k=…)` keys;
      - `<state>["k"] = …` anywhere.
    - Partial reasons: `return <callee>(...)` for a returned call (the callee is the dotted name of `func`, or `call` if that is complex), or `return <ClassName of node>` for other unreadable returns; and `state passed to <callee>` for any call taking the state name as a positional or keyword argument. Ignore `.get`/`.items`-style method calls on the state itself.
  - **Declared fields:** the annotated names in `class <graph.state>` in any module under the roots that `graph.file` imports it from. Resolve it like a node name, but with a `ClassDef`. Missing → exit 2.
  - **Output:** `file` is repo-relative and `line` is the def line. Write back with `json.dumps(…, ensure_ascii=False, indent=2) + "\n"`. Keep `verdict`/`note` by node id and keep `scenarios`. Set `repo.commit` from `git rev-parse HEAD`.
  - **Check:** the `contract` schema follows the spec's contract-spec row. With `repo`, compare `scan()` against the spec's computed fields → `check: contract: stale`.
- [x] **Step 5: Run** the whole file → pass.
- [x] **Step 6: Commit** `feat(R-035): contract.py scanner and contract check`.

### Task 2: The contract page, index order and docs

**Files:** Modify `render.py`, `SKILL.md`, `references/spec-format.md`, `CONTEXT.md` and the test file.

**Interfaces:** Consumes Task 1's spec shape. Produces `render.render_contract(spec) -> str`.

- [x] **Step 1: Failing tests.**
  - `"AC-4 contract page shows nodes, field findings and scenarios"`: use the AC-2 output with the scenario `{title:"換掉一和二", nodes:["one","two"], summary:"s"}` and assert the AC-4 values. A field finding row is the field followed by its nodes, e.g. `a` with `one, three, four` in node order. The 必須讀 text is `a, b` and the 必須寫 text is `c, d`. Also assert `id="node-one"`, the `⚠ 掃描不完整` text in `three`'s row, `⚠ 找不到函式` in `ghost`'s row, and no `<svg`.
  - `"AC-6 index puts overview, features, seams, contract, jobs first"`.
  - `"AC-7 contract text is escaped and offline"`.
- [x] **Step 2: Run** → FAIL.
- [x] **Step 3: Implement.**
  - **`render_contract`**, using the spec's order:
    1. The node table, with classes `cat sum`.
    2. The four findings, each as `<h3>` + `<ul>`. Read and write sets come from resolved nodes only. A hot field is read by ≥3 nodes. 只讀沒人寫 is a read never written by any node. 只寫沒人讀 is a write never read. 宣告了但沒用 is a declared field neither read nor written. Each item lists the field, then ` — ` and its nodes in node order.
    3. 替換情境: an `<h3>` with the title, the summary, then 必須讀 (the union of the reads of its nodes minus the union of their writes, sorted, joined by `, `, or 沒有) and 必須寫 (the union of their writes, sorted).
    4. A section per node: reads, writes, partial reasons and `file:line`.
  - Verdict labels and classes are the seams ones; a missing verdict shows `—`.
  - **Index rank:** overview, features, seams, contract, jobs.
  - **SKILL.md:** the contract step, following the spec's skill-workflow row.
  - **spec-format.md:** a contract section with a small example that passes `check.py`.
  - **CONTEXT.md:** one English entry, `**contract page**`.
- [x] **Step 4: Run** the whole file plus `bats tests/test_repo-layout.bats tests/test_sync-install.bats` → pass.
- [x] **Step 5: Commit** `feat(R-035): contract page, index order and docs`.

### Task 3 (Claude only — codex stops after Task 2): regenerate the langlive-line-oa contract page

Not for the codex executor. Claude writes `contract.json` for `backend/engines/langgraph/graphs/lang_ai_customer.py` (state `AgentState`, roots `["backend"]`), runs `contract.py`, writes the verdicts, notes and ≥3 scenarios, renders it, rebuilds the index and reads the screenshot (AC-8).

## Execution log

- Scope: Tasks 1–2 only, on `ship/R-035-add-langgraph-contract-page`; Task 3 remains reserved for Claude.
- Pre-flight: Task 2 consumes Task 1's scanner schema directly; no interface conflict. Existing worktree is isolated; no branch change needed.
- Baseline: draw-arch, repo-layout and sync-install tests passed (95/95). Test scratch directories and temporary files stay inside this worktree.
- Task 1 RED: five new scanner/check tests failed because `contract.py` did not exist. The missing-input test passed immediately with Python's exit 2, as permitted by the execution instructions.
- Task 1: scanner, schema and stale check implemented. The additional lambda review-focus check passed immediately against the implemented unresolved-expression behavior.
- Task 1 GREEN: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats` passed (70/70), including unchanged golden tests.
- Deviation: Task 2's hotspot expectation includes `six` after `one, three, four` — the required async review fixture also reads `a`, and the Seams contract requires listing every resolved reader in node order.
- Task 2 RED: the contract-page and escaping tests failed with `unknown page: contract`; index ordering and the missing contract example also failed. Invalid-verdict rejection already passed through Task 1's schema, as permitted.
- Task 2 GREEN: `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats` passed (75/75); `bats tests/test_repo-layout.bats tests/test_sync-install.bats` passed (32/32).
- Visual verification: rendered scanner fixture output and inspected desktop and 390 px iframe screenshots inside the worktree; responsive cards, findings, scenarios, node details and footer were readable. Task 3's real-repo/vault output was not accessed.
- Final review: independent read-only reviewer found same-name partial rebinding and omitted commit comparison. Both were reproduced by new failing tests before corrections.
- Deviation: the Task 2 commit includes a local correction to Task 1's resolver — pre-check assignment bindings so `n1 = functools.partial(n1)` cannot resolve to the earlier function definition, as Review Focus 1 requires.
- Deviation: the Task 2 commit includes a local correction to Task 1's stale check — compare `repo.commit` with HEAD as well as node facts and declared fields, because the Seams contract includes it among computed fields.
- Final review scope: Task 3/AC-8 remains excluded by the user's scope. Dynamic execution, arbitrary alias/dataflow analysis, keyword-form registrations and multiple-graph selection remain outside the documented AST patterns; no broader analyzer was added.
- Final review fixes GREEN: both regression tests failed before the fixes and passed afterward; final `bats tests/test_draw-arch.bats` passed (77/77), and `bats tests/test_repo-layout.bats tests/test_sync-install.bats` passed (32/32), 109 total. No deferred findings.
- Result: DONE_WITH_CONCERNS for Tasks 1–2; deviations are listed above. Task 3 was not run. No push, branch switch, amendment or hook bypass.
