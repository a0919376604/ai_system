# Diagram spec

Save one UTF-8 JSON object per topic as `<topic>.json`. All coordinates are canvas
units chosen by Claude. Keep ids and coordinates on a re-run. Use numbers for
coordinates, positive sizes, and booleans for switches. Text is escaped by the
renderer; write literal code-like strings such as `List[str]` or `a<b` in JSON.

| Field | Meaning |
|---|---|
| `topic` | Required slug matching `^[a-z0-9-]+$`; the page name and deterministic SVG id prefix. |
| `title` | Required page and diagram title. |
| `subtitle` | Optional short page subtitle. |
| `repo.name`, `repo.commit` | Required repo name and 7–40 lowercase hex commit; use the full 40-hex commit for delivered packs. |
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
