# Architecture page spec

Save one UTF-8 JSON object per topic as `<topic>.json`. Text is escaped by the
renderer; write literal code-like strings such as `List[str]` or `a<b` in JSON.
Every page shares these fields:

| Field | Meaning |
|---|---|
| `topic` | Required slug matching `^[a-z0-9-]+$`; the page name and deterministic SVG id prefix. |
| `page` | Optional `diagram` (default), `table`, `cards` or `seams`. An unknown type is a schema finding and render exit 2 without output. |
| `title` | Required page and diagram title. |
| `subtitle` | Optional short page subtitle. |
| `repo.name`, `repo.commit` | Required repo name and 7–40 lowercase hex commit; use the full 40-hex commit for delivered packs. |

## diagram

A diagram without `contract` keeps the existing diagram output byte-identical.
Only this type requires `canvas`, `nodes` and `edges`. All coordinates are canvas
units chosen by Claude. Keep ids and coordinates on a re-run. Use numbers for
coordinates, positive sizes, and booleans for switches.

| Field | Meaning |
|---|---|
| `canvas.w`, `canvas.h` | Required positive canvas width and height. |
| `regions` | Optional list of dashed grouping rectangles. |
| `regions[].x`, `y`, `w`, `h` | Rectangle position and positive size. |
| `regions[].color`, `label` | Border/text color as a six-digit hex color (use the palette) and region label; external paint references are rejected. |
| `nodes` | Required list of visible nodes. |
| `nodes[].id` | Required unique drawing id matching `^[A-Za-z0-9_.:-]+$`. |
| `nodes[].graph_id` | Optional graph identity, defaults to `id`. Draw a second END as `id: "END2", graph_id: "END"`; graph comparison collapses the copies. |
| `nodes[].x`, `y`, `w`, `h` | Required position and positive size. |
| `nodes[].kind` | Required `fe`, `be`, `db`, `bus`, `ext`, `sec` or `cloud`; see the style reference. |
| `nodes[].title` | Required title, 13 px. |
| `nodes[].sub`, `port` | Optional subtitle and port, each 10 px. Use one subtitle line. |
| `nodes[].shape` | Optional `box` (default) or `pill`; START/END use pills. |
| `nodes[].lines` | Optional list, at most four short lines of `{ "text": "…", "tone": "body" }`, 10.5 px. |
| `tone` | For node lines and route steps: `body` (default), `cond`, `warn`, or `muted`. |
| `nodes[].dash` | Optional boolean, default false; dashed node border. |
| `nodes[].src` | List of code citations `path:start-end`, backing each node. |
| `edges` | Required list of edges; paths are drawn before nodes. |
| `edges[].from`, `to` | Required existing drawing node ids. |
| `edges[].path` | Required SVG path, restricted to `MLHVCQZmlhvcqz`, digits, spaces, periods, commas and minus signs. |
| `edges[].label`, `lx`, `ly` | Optional label and required center coordinates when a label is present. Box is `text_width(label, 10) + 10` wide and 16 high. |
| `edges[].dash`, `arrow` | Optional booleans, defaults false and true; dashed edge and arrowhead switch. |
| `routes` | Optional route overlays, one extra diagram copy per route. |
| `routes[].name`, `nodes`, `edges` | Name, existing node ids and edge strings such as `a->b`; active nodes/edges are amber, others opacity 0.2. |
| `routes[].badges` | Optional `{ "n": 1, "x": 190, "y": 40 }` entries; numbered circles of radius 11. |
| `routes[].steps` | Optional ordered `{ "title": "…", "note": "…", "tone": "cond" }` entries. |
| `conditions` | Optional table rows in spec order. No rows means no table. |
| `conditions[].node` | Existing id or list of ids, displayed joined by ` / `. |
| `conditions[].does` | What the node does. |
| `conditions[].when` | When it is reached, and which condition leads to which next node. |
| `conditions[].src` | Code citation `path:start-end`. |
| `conditions[].warn` | Optional boolean, default false; true adds the rose ⚠ style only for a cited risk. |
| `legend` | Optional list of `{ "kind": "be", "label": "FAQ · RAG" }` in display order; use it when colors mean something other than the kind (e.g. LangGraph stages). Without it the legend lists the kinds the nodes use, named 前端 / 後端 / 資料庫 / 佇列 / 外部 / 安全 / 雲端. |
| `langgraph.file` | Optional Python StateGraph source, relative to `--repo`; read through AST only. |
| `contract` | Optional node state contract object, rendered as 節點契約 below the condition table; see below. |

The table displays 節點 followed by the three content columns 做什麼 /
什麼條件走到這、離開時往哪 / 程式碼. Optional `regions`, `routes`, `conditions`
and `langgraph` may be omitted entirely. A clean spec has no node overlap,
labels on nodes or other labels, off-canvas nodes, dangling ids or overwide text.

A complete small example, suitable for `check.py` and `render.py page`:

```json
{
  "topic": "overview",
  "title": "Demo 架構",
  "subtitle": "Webhook → PostgreSQL",
  "repo": {"name": "demo", "commit": "0123456789abcdef0123456789abcdef01234567"},
  "canvas": {"w": 600, "h": 300},
  "regions": [{"x": 10, "y": 10, "w": 580, "h": 150, "color": "#fbbf24", "label": "EKS"}],
  "nodes": [
    {"id": "a", "x": 20, "y": 40, "w": 160, "h": 90, "kind": "be", "title": "Webhook", "sub": "api/x.py", "port": "443", "shape": "box", "lines": [{"text": "簽章不對 → 拒絕", "tone": "cond"}], "dash": false, "src": ["api/x.py:1-9"]},
    {"id": "b", "x": 300, "y": 40, "w": 160, "h": 60, "kind": "db", "title": "PostgreSQL", "src": ["db.py:2-8"]}
  ],
  "edges": [{"from": "a", "to": "b", "path": "M180 70 H300", "label": "寫入", "lx": 240, "ly": 60, "dash": false, "arrow": true}],
  "routes": [{"name": "一則訊息", "nodes": ["a", "b"], "edges": ["a->b"], "badges": [{"n": 1, "x": 190, "y": 40}], "steps": [{"title": "打 webhook", "note": "簽章不對就拒絕", "tone": "cond"}]}],
  "conditions": [{"node": ["a", "b"], "does": "收事件並寫入", "when": "簽章對 → 寫入", "src": "api/x.py:1-9", "warn": false}]
}
```

## table

Set `page: "table"` for a catalog such as background jobs. It needs no diagram
fields. Empty `rows` renders the title and footer without a table.

| Field | Meaning |
|---|---|
| `columns` | Required list of `{key, label}` text fields, in display order. A 程式碼 column is appended. |
| `rows` | Required list of rows. Ungrouped rows come first, then groups in first-seen order; rows retain their order inside each group. |
| `rows[].id` | Required unique id matching `^[A-Za-z0-9_.:-]+$`; its anchor is `row-<id>`. |
| `rows[].cells` | Required object mapping column keys to text; missing cells are empty. |
| `rows[].src` | Required code citation text or list of text, joined by ` / `. |
| `rows[].warn` | Optional boolean; true adds a rose ⚠ to the first cell. |
| `rows[].group` | Optional text, used as the group's heading. Below 700 px table rows become cards. |
| `registry` | Optional `{file, call, key?}`; `file` is relative to `--repo` and `key` defaults to `name`. |

With `--repo`, the registry check parses matching `Name` or `Attribute` calls
through AST only. Each literal keyword value needs a matching row id; extra rows
are allowed. Missing rows, absent/non-literal names, missing files and parse
errors are findings. The source is never imported or executed.

```json
{
  "topic": "jobs", "page": "table", "title": "背景程式",
  "repo": {"name": "demo", "commit": "0123456789abcdef0123456789abcdef01234567"},
  "columns": [{"key": "kind", "label": "類型"}, {"key": "schedule", "label": "頻率"}, {"key": "does", "label": "做什麼"}, {"key": "switch", "label": "開關"}],
  "rows": [{"id": "csat_worker", "group": "事件", "cells": {"kind": "consumer", "schedule": "事件觸發", "does": "處理問卷", "switch": "啟用"}, "src": "app/csat.py:1-20"}],
  "registry": {"file": "app/jobs.py", "call": "Meta"}
}
```

## cards

Set `page: "cards"` for a feature catalog. Empty `cards` renders the title and
footer without a grid. Cards use two columns on desktop and one below 700 px.

| Field | Meaning |
|---|---|
| `cards` | Required list, rendered in spec order as one `<article class="card" id="card-<id>">` per entry. |
| `cards[].id` | Required unique id matching `^[A-Za-z0-9_.:-]+$`. |
| `cards[].title`, `does` | Required title and plain-language description. |
| `cards[].entry`, `data` | Optional text displayed with 入口 and 資料 labels. |
| `cards[].src` | Required list of code citation text, joined by ` / `. |
| `cards[].topics` | Optional list of slugs matching `^[a-z0-9-]+$`, linked to `<slug>.html` under 相關頁面. |
| `cards[].jobs` | Optional list of job ids, linked to `jobs.html#row-<id>` under 背景程式. |

The CLI checks links beside the spec: each topic needs `<slug>.json`, and each
job needs a row id in `jobs.json`. An absent or unreadable `jobs.json` has no ids.
Findings are `check: link: missing topic <slug>` and `check: link: missing job <id>`.

## seams

Set `page: "seams"` for an external-system 可替換性 page. It opens with a summary
table 系統 / 能不能換 / 接觸檔 / 漏進核心 / 一句話 in system order; titles link
to each system's section. 接觸檔 counts touchpoint files and 漏進核心 counts files
outside adapters. Each section shows its verdict, summary, 換掉要改 list and
檔案 / 行 / 位置 / 說明 table. Rose ❌ 漏進核心 rows precede ✅ 在 adapter 內
rows, each group sorted by file. Empty touchpoints shows 沒有找到接觸點.
Below 700 px, table rows become cards.

| Field | Meaning |
|---|---|
| `systems` | Required list of external systems, displayed in spec order. |
| `systems[].id` | Required unique id matching `^[A-Za-z0-9_.:-]+$`; its anchor is `sys-<id>`. |
| `systems[].title`, `summary` | Required title and plain-language summary. |
| `systems[].verdict` | Required `easy` (容易換), `medium` (要改一些) or `hard` (很難換). |
| `systems[].change` | Required list of text describing what replacement requires. |
| `systems[].probes` | Required non-empty list of `{kind, pattern}`. `import` matches a package or submodule prefix through AST; `text` is a valid Python regex matched on every source line, including comments and docstrings. |
| `systems[].adapters` | Required list of globs for the files intended to own the integration. |
| `systems[].touchpoints` | Required list of `{file, lines, adapter, note?}`. `file` is repo-relative text, `lines` a list of integers, `adapter` a boolean, and optional `note` text. |
| `exclude` | Optional list of globs excluded from both scanning and the stale check. |

Write the spec, then run
`python3 "$SKILL_DIR/lib/seams.py" "$REPO" "$OUT/seams.json"`.
The scanner reads tracked Python files from `git ls-files`, skipping paths with
`test`/`tests` components and files named `test_*.py` or `*_test.py`. Globs use
`fnmatch` on repo-relative paths. Relative imports never match import probes;
`linebot` matches `linebot.v3.messaging`, but not `linebotx` or `my_linebot`.
A file that cannot parse still gets text probes and is named once on stderr.
Source is never imported or executed.

The scanner rewrites touchpoints sorted by file, with ascending unique lines,
and `repo.commit` from HEAD; it preserves other fields and notes by system id and
file. Missing repo/spec exits 2 without writing. Repeated runs are byte-identical.
Write the verdict, summary, change list and leak notes from these results.
`check.py --repo` repeats the scan and reports `check: seams: stale <id>` for
changed file/lines/adapter sets, ignoring notes. Without `--repo` it checks only
the schema and duplicate ids.

```json
{
  "topic": "seams", "page": "seams", "title": "外部系統可替換性",
  "repo": {"name": "demo", "commit": "0123456789abcdef0123456789abcdef01234567"},
  "exclude": ["vendor/*"],
  "systems": [{
    "id": "line", "title": "LINE", "verdict": "medium",
    "summary": "SDK 集中在 adapter，替換時仍要調整事件格式",
    "change": ["改寫 adapter 的 SDK 呼叫與事件轉換"],
    "probes": [{"kind": "import", "pattern": "linebot"}, {"kind": "text", "pattern": "api\\.line\\.me"}],
    "adapters": ["adapters/*"],
    "touchpoints": [{"file": "adapters/line.py", "lines": [2], "adapter": true, "note": "SDK 入口"}]
  }]
}
```

## contract (diagram object)

Add a `contract` object to the first StateGraph's diagram spec. The 節點契約
section appears after the condition table and before the footer, with three
blocks: highlights, a 節點 / 讀 / 寫 / 好不好換 / 一句話 table, and 替換情境.
Read and write cells use native `<details><summary>count</summary>fields</details>`
with fields joined by `, `; empty lists show `0` without details. Each 一句話
cell shows the note followed by `⚠ 掃描不完整：` and reasons joined by `；`, or
`⚠ 找不到函式` for an unresolved node. Missing verdicts display `—`.
Rows become cards below 700 px. The section stays static and offline.
All fields below are inside `contract`; the diagram's own `nodes` and `edges`
keep their existing meaning.

| Field | Meaning |
|---|---|
| `graph.file` | Required repo-relative Python file containing `add_node` calls. |
| `graph.state` | Required state class name in that file's namespace. |
| `graph.roots` | Required non-empty list of repo-relative import roots, e.g. `["backend"]` or `["."]`. |
| `nodes` | Required list, computed: graph nodes in `add_node` source order, then conditional-edge routers. Node ids come from the string literal name (`add_node("x", fn)` or `action=fn`), the function name for `add_node(fn)`, or `line-<n>` (unresolved) when the name cannot be read. |
| `nodes[].kind` | Required computed `node` or `router`; routers come from `add_conditional_edges(src, fn)` / `path=fn`, one per function, and show （路由） after the id. |
| `nodes[].id` | Required unique id matching `^[A-Za-z0-9_.:-]+$`. |
| `nodes[].file`, `line` | Required computed repo-relative function file and definition line; unresolved nodes use `""` and `0`. |
| `nodes[].reads`, `writes` | Required computed sorted unique lists of state fields. |
| `nodes[].partial` | Required computed sorted unique reasons why scanning is incomplete. |
| `nodes[].resolved` | Required computed boolean; unresolved nodes have empty reads, writes and partial lists. |
| `nodes[].verdict`, `note` | Optional judgment: `easy` (容易換), `medium` (要改一些), `hard` (很難換), and explanation text. |
| `declared` | Required computed sorted unique annotated state-class fields. |
| `highlights` | Required list of text, at most 5 items. Write 3–5 short observations about shared state and replacement effort. |
| `scenarios` | Required list of `{title, nodes: [id]}`; each node id must exist. |

Start `contract.nodes`, `declared`, `highlights` and `scenarios` empty, then run
`python3 "$SKILL_DIR/lib/contract.py" "$REPO" "$OUT/langgraph.json"`
on that diagram spec.
Source is parsed through AST and never imported or executed. Module lookup uses
`graph.roots`; absolute and relative re-exports are followed up to five hops.
Plain functions, async functions and factories returning an inner function are
resolved. Assignments (including partials and lambdas) remain unresolved.

Reads are constant-string subscripts and `.get()` on the first positional
parameter. Writes are constant keys in returned dicts, returned dict variables
(including subscript assignments and `.update()` keys), and direct state
subscript assignments; `**state` spreads are ignored. When the state is passed to
a helper that resolves inside the repo (a bare name or `module.func`), the helper
is analysed too, up to three levels deep with a cycle guard; its reads and
`state[k] = …` writes count, and its returned keys count when the caller returns
the call (awaited or not). What the scanner cannot read becomes a partial reason
instead of a silent gap: `return <expr>` (a call shows `f(...)`), `return {**<expr>}`,
`<var>.update(<expr>)`, `state passed to <callee>` for an unresolvable helper,
`state used in nested function <name>`, `state rebound` (the state name is
reassigned or shadowed; reads and writes through it are then not counted), and
`no state parameter`. A router's return names the next node and is never a reason.

The scanner rewrites `contract.nodes`, `contract.declared` and `repo.commit`
from HEAD, adds new contract nodes, drops removed ones, and keeps verdicts and
notes by node id plus all highlights and scenarios. Diagram nodes, edges and
canvas remain unchanged. Repeated runs are byte-identical. Missing repo, spec,
graph file, state class or contract object, or a non-diagram spec, exits 2 without
changing the spec. `check.py --repo` reruns the scan and reports
`check: contract: stale` when computed facts differ; a commit alone never makes
it stale. Without `--repo` it checks
the schema, duplicate node ids (`check: id: duplicate node <id>`) and scenario
references (`check: edge: unknown scenario node <id>`).

Each replacement scenario uses resolved nodes only and appears as one line:
`<title> → 必須讀 … · 必須寫 …`. 必須讀 is the union of those nodes' reads minus
their writes, and 必須寫 is their write union. Both lists are sorted and show
沒有 when empty. Put useful field observations in the highlights.

```json
{
  "topic": "langgraph", "page": "diagram", "title": "LangGraph",
  "repo": {"name": "demo", "commit": "0123456789abcdef0123456789abcdef01234567"},
  "canvas": {"w": 300, "h": 140},
  "nodes": [{"id": "reply", "kind": "be", "x": 40, "y": 40, "w": 180, "h": 60, "title": "回覆"}],
  "edges": [],
  "contract": {
    "graph": {"file": "app/graph.py", "state": "AgentState", "roots": ["."]},
    "nodes": [{
      "id": "reply", "kind": "node", "file": "app/nodes.py", "line": 12,
      "reads": ["question"], "writes": ["answer"], "partial": [], "resolved": true,
      "verdict": "easy", "note": "只透過兩個 state 欄位溝通"
    }],
    "declared": ["answer", "question", "unused"],
    "highlights": ["回覆節點只讀 question、寫 answer", "unused 尚未使用", "替換時保留問題與答案欄位即可"],
    "scenarios": [{"title": "換掉回覆節點", "nodes": ["reply"]}]
  }
}
```

The pack index places overview, features, seams and jobs first when present,
then every other topic alphabetically. All page types remain static and offline.
