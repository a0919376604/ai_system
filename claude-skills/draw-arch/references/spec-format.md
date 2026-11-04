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

An absent `page` or `page: "diagram"` keeps the existing diagram output unchanged.
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

The pack index places overview, features, seams and jobs first when present,
then every other topic alphabetically. All page types remain static and offline.
