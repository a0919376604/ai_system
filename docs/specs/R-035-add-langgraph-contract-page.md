---
date: 2026-11-04
updated: 2026-11-04
type: spec
id: R-035
tags: [spec, ai_system]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-035
---

## For future Claude
> R-035 adds a `contract` page to `/draw-arch`: the internal seams of a LangGraph graph.
> LangGraph nodes do not import each other; they talk through the shared state. A new stdlib
> script, `lib/contract.py`, resolves every `add_node` to its function through `ast` and
> lists the state fields that function reads and writes. The page shows, for each node:
> - the fields it reads and writes;
> - hot fields, fields read but never written, written but never read, and declared but unused;
> - which nodes are easy to swap;
> - replacement scenarios, written by Claude.

## Decisions

- Door: two-way — a new page type, script and tests inside `claude-skills/draw-arch/`;
  existing pages are byte-identical. (my call)
- The operator asked for 「langraph 內部模組之間的 seams」 after R-034's external seams page.
  The nodes of `lang_ai_customer` import nothing from each other (checked), so the internal
  seam is the state read/write contract, not imports. The proposal was accepted: 「好」.
  (operator)
- Contract per graph node (`add_node` name), not per file: one file holds several nodes,
  and factories build nodes. (my call, grilling Q1)
- Resolution through `ast`, never importing anything. A plain function reference resolves
  directly. A call (factory) resolves to the factory, and then to the inner `def` it
  returns. Names re-exported from a package `__init__.py` are followed, up to 5 hops. A
  node that cannot be resolved is listed as unresolved, never dropped. (my call, Q2)
- Reads are `state["k"]` and `state.get("k")`, where `state` is the function's first
  parameter. Writes are the keys of returned dict literals, plus keys added to a dict
  variable that is returned (`d = {...}`, `d["k"] = …`, `d.update({...})`), plus direct
  `state["k"] = …`. A return the scanner cannot read, or the state passed to a helper call,
  marks the node `partial`, with the reason. The page says the scan is incomplete instead
  of pretending. (my call, Q3; the operator was told this limit before saying 「好」)
- Declared fields come from the state class's annotations (`class AgentState(TypedDict)`),
  named in the spec. They are used for "declared but unused" and to tell external inputs
  apart. (my call, Q4)
- The script computes the facts and Claude writes the judgment. Per node, Claude sets a
  `verdict` (easy/medium/hard, the same words as seams) and a `note`. Scenarios are
  Claude's: a title, the nodes they replace, and a summary. The page derives each
  scenario's "must read / must write" from those nodes. (my call, Q5)
- Hot field means read by 3 or more nodes. (my call, Q6)
- The default topics gain `contract` when the repo has a StateGraph. (my call, Q7)

## Seams

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| page types | spec `page`: adds `contract` | `diagram`/`table`/`cards`/`seams` output is unchanged (golden files and existing tests). |
| contract spec | `graph: {file, state, roots: [dir]}`, `nodes: [{id, kind: node|router, verdict?, note?, file, line, reads: [k], writes: [k], partial: [reason], resolved: bool}]`, `declared: [k]`, `scenarios: [{title, nodes: [id], summary}]` | `graph.file` is repo-relative; `roots` are the import roots (dirs on `sys.path`, e.g. `backend`); `verdict` ∈ easy/medium/hard when present; scenario node ids must exist (`check: edge: unknown scenario node <id>`); duplicate node ids give `check: id: duplicate node <id>`. |
| contract scanner | `python3 lib/contract.py <repo> <spec.json>` | It rewrites the computed fields — node `file`, `line`, `reads`, `writes`, `partial`, `resolved`; `declared`; `repo.commit` — and keeps `verdict`, `note` and `scenarios`. Nodes are listed in `add_node` order, with their ids from the `add_node` string literal. Routers (`add_conditional_edges(src, <Name>, …)`) follow as `kind: router`, one per function, id = function name. When the state is passed to a call that resolves to a function in the repo (a bare name, or `module.func` via `import`/`from … import module`), that helper is analysed too, up to 3 levels deep with a cycle guard: its reads count, its `state[k] = …` writes count, and its returned dict keys count when the caller returns the call. Only unresolvable helpers leave `state passed to …` / `return …(...)` partial reasons. A helper's own unreadable return counts only when the caller returns that call; a router's return is never a partial reason (it names the next node). Unreadable cases are always reported, never dropped: `return <expr>` (bounded source text), `return {**<expr>}`, `<var>.update(<expr>)`, `state used in nested function <name>`, `state rebound` (no reads or writes counted through the rebound name); `return await f(state)` is followed like `return f(state)`. `add_node(fn)` uses the function name as id, `action=`/`path=` keywords are read, and any other `add_node` call yields an unresolved `line-<n>` node. An import resolving outside the repo leaves that name unresolved instead of aborting. `reads`/`writes` are sorted and unique. `partial` reasons are `return <expr>` or `state passed to <callee>`, each in its own sorted list entry. An unresolvable node has `resolved: false` and empty lists. Spec nodes no longer in the graph are dropped; new ones are added with no verdict. Source is never imported or run. A missing repo, spec, graph file or state class exits 2 and writes nothing. Deterministic. |
| contract check | `check.py <spec> --repo <repo>` | Reruns the scan; when any computed node field or `declared` differs it prints `check: contract: stale`. `repo.commit` is not compared, so a commit that leaves the graph untouched does not go stale, as with seams. |
| contract page | `render.py page` | In order: a node table (節點 / 讀 / 寫 / 好不好換 / 說明), whose 讀 and 寫 counts link to `#node-<id>`, where a partial node shows `⚠ 掃描不完整` and an unresolved one shows `⚠ 找不到函式`; field findings (熱點欄位 (≥3 個節點讀), 只讀沒人寫, 只寫沒人讀, 宣告了但沒用), each listing fields with the nodes involved (宣告了但沒用 lists bare field names), or 「沒有」; 只讀沒人寫 and 只寫沒人讀 carry a one-line hint that such fields may be the graph's inputs or outputs; 替換情境, each with its summary, 必須讀 (the union of its nodes' reads minus their writes) and 必須寫 (the union of its nodes' writes); and one `<section id="node-<id>">` per node with its reads, writes, partial reasons and `file:line`. The same offline and escaping rules as every page; below 700 px the tables become cards. |
| index order | `render.py index` | overview, features, seams, contract, jobs first. |
| skill workflow | `SKILL.md` | The contract step: run `contract.py` with the first StateGraph's file, state class and import roots, write a verdict and note per node, write at least three scenarios, then `check.py --repo`. |

## Acceptance

- **AC-1** Given the existing golden files and the table, cards and seams tests, then they
  all still pass unchanged.
- **AC-2** Given a fixture repo (every scanned file starts with `raise SystemExit(9)`):
  - `pkg/state.py` declares `class S(TypedDict)` with `a`, `b`, `c`, `d`, `unused`;
  - `pkg/nodes/__init__.py` re-exports `n1`, `make_n2`, `n3`, `n4` from `.impl`;
  - in `pkg/nodes/impl.py`:
    - `n1(state)` reads `state["a"]` and `state.get("b")` and returns `{"c": 1}`;
    - `make_n2()` returns an inner `def n2(st)` that reads `st["c"]`, builds `out = {}`,
      sets `out["d"] = 1` and returns `out`;
    - `n3(state)` reads `a` and returns `helper(state)`;
    - `n4(state)` reads `a` and sets `state["b"] = 2`;
  - `pkg/graph.py` adds `one`→`n1`, `two`→`make_n2()`, `three`→`n3`, `four`→`n4` and
    `ghost`→`missing_fn`.

  When `contract.py` runs, then `one` reads `[a, b]` and writes `[c]`; `two` reads `[c]` and
  writes `[d]`; `three` reads `[a]` and has partial `["return helper(...)",
  "state passed to helper"]`; `four` writes `[b]`; `ghost` is `resolved: false`. `declared`
  is `[a, b, c, d, unused]`, a second run is byte-identical, a `verdict` survives a re-run,
  and the exit status is never 9.
- **AC-3** Given that output, when `impl.py` changes so that `n1` also reads `d` and the
  change is committed, then `check.py --repo` reports `check: contract: stale`. Before the
  change it exits 0.
- **AC-4** Given that output with a scenario over `[one, two]`, when rendered, then:
  - 熱點欄位 lists `a` (one, three, four);
  - 只寫沒人讀 lists `d` (two);
  - 宣告了但沒用 lists `unused`;
  - the scenario's 必須讀 is `a, b` and its 必須寫 is `c, d`;
  - `three` shows `⚠ 掃描不完整` and `ghost` shows `⚠ 找不到函式`;
  - there is no `<svg`.
- **AC-5** Given an unknown scenario node, a duplicate node id, or `verdict: "maybe"`, then
  each gives its `check:` finding.
- **AC-6** Given a pack with contract, seams, features, jobs, overview and csat, then the
  index order is overview, features, seams, contract, jobs, csat.
- **AC-7** Given spec text with `<script>` and `https://evil.example` in a note and a
  scenario summary, then it renders escaped with no literal external URL.
- **AC-8** (done when) Given langlive-line-oa re-run, then:
  - the vault `contract` page covers every `add_node` of `lang_ai_customer`, with a verdict
    and note on each;
  - it shows the four field findings and at least three scenarios;
  - `check.py --repo` is clean;
  - a screenshot was read.
