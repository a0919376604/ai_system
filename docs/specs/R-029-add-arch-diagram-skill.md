---
date: 2026-11-03
updated: 2026-11-03
type: spec
id: R-029
status: draft
tags: [spec, ai_system, skill, architecture, diagram]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-029
related-specs: [R-004, R-027]
mockup: "Proposals/mockups/R-029-cocoon-architecture-pack-mockup.html (option B)"
supersedes: null
---

## For future Claude
> R-029 adds a fifth skill, `claude-skills/arch-diagram/`. `/arch-diagram` draws an
> **architecture pack** for a repo: Cocoon-style HTML diagrams written into the vault project's
> `Architecture/diagrams/`. There are three steps:
> - **Claude decides the content.** It reads the code at the current commit, decides each
>   diagram's content and layout, and writes one **diagram spec** JSON per topic.
> - **`render.py` turns a spec into HTML.** Each spec becomes one standalone HTML page;
>   `render.py index` writes the pack's `index.html`.
> - **`check.py` gates every spec before it is rendered.** It checks structure, overlaps and
>   text fit. For a LangGraph topic it also checks that every node and edge matches the
>   StateGraph, read with the AST.
>
> The first real run is langlive-line-oa, with six topics: overview, one LINE message,
> LangGraph flow, QA→KB, CSAT and 轉真人.

## §1 Problem
The operator wants a skill that shows a project's current architecture, starting with
langlive-line-oa. What was tried on 2026-11-02:

- **`/obsidian-architect`.** The operator deleted it as too complex: an 860-line command and
  ~7,400 lines of Python. A backup is at `~/.claude/backups/obsidian-architect-20261102.tgz`.
  This happened outside this repo.
- **A Cocoon-style trial** (`Proposals/mockups/R-029-add-arch-diagram-skill-mockup.html`).
  The operator liked the drawing. It lacked a diagram of one LINE message, the QA→KB
  pipeline and per-feature diagrams, and its node notes were too thin.
- **archify trial.** Three diagrams in `langlive-line-oa/Architecture/archify/`. The operator
  judged them worse:
  - the architecture drawing was not better;
  - the side cards were too much and cluttered: "可以專門說每一個的 node 的條件是什麼就好";
  - the sequence diagram of one LINE message was unreadable for people.

The operator picked option B of `Proposals/mockups/R-029-cocoon-architecture-pack-mockup.html`:
each topic gets its own Cocoon diagram, and diagrams that explain nodes get a three-column
condition table.

## §2 Goals, non-goals
**Goals**
- G1. `/arch-diagram [<topic>…]` run in a repo writes one HTML page per topic, plus
  `index.html`, into `<vault project>/Architecture/diagrams/`. All pages are in Cocoon style.
- G2. **The first batch for langlive-line-oa has six topics:**
  - overview, with the one-message route drawn on it as ①–⑧;
  - one LINE message, as plain-language step cards;
  - the `lang_ai_customer` LangGraph flow with its condition table;
  - the QA→KB pipeline S0–S5;
  - CSAT;
  - 轉真人.
- G3. **The condition table has exactly three columns:** 做什麼 / 什麼條件走到這、離開時往哪 /
  程式碼. A row is marked ⚠ only when the source shows a real risk.
- G4. **Every claim is backed by the code.** Nodes and table rows cite `path:line` at the
  commit the pack records. LangGraph nodes and edges come from the AST, not from Claude.
- G5. **A re-run updates the pack.** It reuses each topic's saved spec, so positions stay put,
  and it reports what changed.
- G6. **Install.** `sync.sh` links `arch-diagram`. The R-004 rule and the layout tests say
  six skills, because `weekly-report`, added in a025cfc without the rule, is folded in here.

**Non-goals**
- The interactive page (option C). Output is static HTML: no JS and no external URLs.
- Writing into the target repo. Moving the pack into the repo is a later decision (Q4).
- Re-running automatically (no `/ship-compound` hook) and drawing every feature. Topics
  beyond the first batch are added by naming them.
- archify, UA and Mermaid. archify stays installed but this skill does not call it. UA is not
  read: it is stale (line-oa's is 826 commits behind) and cannot be cited.
- Sequence, ERD and class diagram types.

**Anti-goals**
- Cards that say everything (the archify problem). Each node shows its title, a short
  subtitle and at most four lines; detail goes in the condition table.
- A page that only renders with network access, or that runs code.

## §3 Design
### 3.1 Layout
```
claude-skills/arch-diagram/
  SKILL.md                    # /arch-diagram workflow (§3.5)
  lib/render.py               # spec → page HTML; directory → index.html
  lib/check.py                # spec validation, geometry, LangGraph comparison
  references/spec-format.md   # the diagram spec, field by field, with one small example
  references/cocoon-style.md  # palette, typography, layout rules; MIT credit to Cocoon AI
```
- **Python 3.9 standard library only** (macOS `/usr/bin/python3`). Python 3.9 rules out
  `match` and `X | Y` type syntax.
- **Tests** live in `claude-skills/ship-workflow/tests/test_arch-diagram.bats`, so the one
  `bats tests/` run covers them. Fixtures go in `tests/fixtures/arch-diagram/`.

### 3.2 Diagram spec (one JSON file per topic)
```json
{
  "topic": "langgraph",
  "title": "lang_ai_customer · LangGraph 流程",
  "subtitle": "backend/engines/langgraph/graphs/lang_ai_customer.py · 19 個節點 · 33 條邊",
  "repo": {"name": "langlive-line-oa", "commit": "<40-hex>"},
  "canvas": {"w": 1200, "h": 690},
  "regions": [{"x": 450, "y": 150, "w": 480, "h": 470, "color": "#fbbf24", "label": "AWS EKS · namespace ai"}],
  "nodes": [{"id": "rerank", "x": 70, "y": 370, "w": 140, "h": 46, "kind": "be",
             "title": "rerank", "sub": "Jina rerank", "port": "", "shape": "box",
             "lines": [{"text": "條件：…", "tone": "cond"}], "dash": false,
             "src": ["backend/engines/langgraph/nodes/lang_ai_customer/process.py:93-180"]}],
  "edges": [{"from": "rerank", "to": "vision_synthesis", "path": "M210 393 H240 V463 H260",
             "label": "有圖片", "lx": 240, "ly": 425, "dash": false, "arrow": true}],
  "routes": [{"name": "一則 LINE 訊息怎麼走", "nodes": ["…"], "edges": ["a->b"],
              "badges": [{"n": 1, "x": 200, "y": 62}],
              "steps": [{"title": "LINE 打我們的 webhook", "note": "簽章不對就拒絕", "tone": "cond"}]}],
  "conditions": [{"node": "rerank", "does": "重新排序",
                  "when": "有待處理圖片 → vision_synthesis，否則 → faq_gen",
                  "src": "lang_ai_customer.py:48-91", "warn": false}],
  "langgraph": {"file": "backend/engines/langgraph/graphs/lang_ai_customer.py"}
}
```
- **`kind`** is one of `fe` `be` `db` `bus` `ext` `sec` `cloud`. Each maps to a Cocoon fill
  and stroke, and the page legend names them.
- **`tone`** is one of `body` `cond` (amber), `warn` (rose) or `muted`.
- **`shape`** is `box` or `pill`. START and END are pills.
- **`conditions[].node`** is one node id or a list of ids, for nodes that share one row such as
  `small_talk_gen / complaint_gen / ending_gen`. `check.py` resolves every id.
- **Optional fields:** `routes`, `conditions` and `langgraph`. Every coordinate is in canvas
  units; Claude chooses them, nothing is laid out automatically.
- **Coordinates and ids are kept on a re-run** (G5).

### 3.3 `render.py`
- **`render.py page <spec.json> <out.html>`** writes one standalone HTML page, in this order:
  1. the title, then the subtitle with the repo name and short commit;
  2. the diagram as inline SVG (dark Cocoon theme, grid background, arrow markers);
  3. per route, a copy of the diagram with the route's nodes and edges in amber at full
     opacity, everything else at 0.2, the numbered badges, and the steps list beside it;
  4. the condition table, three columns plus the node id, with ⚠ rows in rose;
  5. a footer naming the commit.

  Every node carries `data-node="<id>"` and every edge `data-edge="<from>-><to>"`. All
  spec text is HTML-escaped. The output contains no `<script>`, no event handlers and no
  `http(s)://` except SVG namespaces. Identical input gives identical bytes.
- **`render.py index <dir> <out.html>`** lists every `*.json` spec in `<dir>`: the overview
  first, then the rest by `topic`. Each entry shows its title and subtitle and links to its
  page.
- **Exit codes:** 0 on success; 2 on bad arguments or a spec that is not valid JSON.

### 3.4 `check.py`
`check.py <spec.json> [--repo <path>]` prints one `check: <rule>: <detail>` line per finding.
It exits 0 when there are none, 1 when there are findings, and 2 on bad arguments.

| Rule | Finds |
|---|---|
| `schema` | a missing required field, an unknown `kind`, `tone` or `shape`, or a non-positive size |
| `id` | a duplicate node id |
| `edge` | an edge, route or condition naming a node that does not exist |
| `bounds` | a node outside the canvas |
| `overlap` | two node rectangles that intersect |
| `label` | an edge label box (estimated width × 16) that intersects a node, or another label |
| `fit` | a node's title, subtitle or line wider than the node minus 24 px (estimated: CJK 1.0 em, others 0.62 em) |
| `langgraph` | with `--repo` and a `langgraph.file`: the node or edge set differs from the StateGraph. Missing and extra items are each named. |

- **The LangGraph comparison** reads the file with `ast` and never imports or runs it.
- **Nodes** come from `add_node(<str>, …)`.
- **Edges** come from `add_edge(a, b)` and from each key→target pair in the `add_conditional_edges`
  mapping dict. START and END are matched by name.
- **A conditional edge without a mapping dict** cannot be resolved statically, so it is reported
  as `langgraph: unresolved conditional edge from <node>` rather than guessed.

### 3.5 `/arch-diagram` workflow (SKILL.md)
1. **Resolve.**
   - **Scripts** are called by their path relative to SKILL.md's own directory
     (`<skill dir>/lib/render.py`), so the copy in a worktree runs before it is installed.
   - **Repo:** cwd or the argument.
   - **Commit:** `git rev-parse HEAD`. Note any dirty paths, and never cite them.
   - **Output directory:** `$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Architecture/diagrams/`.
     `--out <dir>` overrides it. With neither, stop and ask.
2. **Topics.** Use the topics named in the arguments. With none:
   - if the output directory already holds specs, re-run those;
   - otherwise use the default first batch: overview, message route, and one flow per
     `StateGraph(` found in the repo outside test directories. Ask before adding pipelines,
     features, or a second StateGraph. line-oa has three; the first batch draws only
     `lang_ai_customer`.
3. **Trace each topic in the code.**
   - Start from entry points, manifests and deployment files.
   - Follow imports and call sites to the actual input, output or side effect.
   - Record `path:line` ranges while reading.
   - **Never read** `env.json`, `.env*` or key files. Template key names are allowed.
   - Topics are independent, so one subagent per topic is allowed.
4. **Write the spec** following `references/spec-format.md` and `references/cocoon-style.md`.
   - Message-style topics are step cards: a numbered title, then 白話 lines with `cond` and
     `warn` tones. They are not sequence diagrams.
   - A condition row says when the node is reached and where it goes next, with `src`.
   - `warn: true` only when the cited code shows the risk.
5. **Check, render, look; at most three rounds.**
   1. Run `check.py --repo` and fix every finding.
   2. Run `render.py page`.
   3. Take a full-page headless Chrome screenshot, Read it, and fix the layout.

   After the third round, deliver and list what is still off.
6. **Index:** run `render.py index`.
7. **Report:** links to the pages, the commit, what was simplified or uncertain, and on a
   re-run what changed per topic.

### 3.6 Install and docs
- **`sync.sh`:** `SKILLS=(ship-workflow run-plan code-review-skill pr-review weekly-report arch-diagram)`,
  and the help line lists six.
- **CLAUDE.md:** the R-004 rule lists six skills.
- **Tests:** `test_repo-layout.bats` and `test_sync-install.bats` expect the six directories.
- **CONTEXT.md** gains these terms:
  - architecture pack
  - diagram spec
  - condition table
  - route overlay

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| page render | `render.py page <spec> <out>` → exit 0 | sections in §3.3 order; `data-node` / `data-edge` on every node and edge; text escaped; no script, handler or external URL; byte-identical for identical input; invalid JSON → exit 2 |
| route overlay | spec `routes[]` | one extra diagram copy per route: route nodes and edges at full opacity in amber, the rest at 0.2, one badge per `badges[]` item, steps listed in order |
| condition table | spec `conditions[]` | a table with columns 節點 / 做什麼 / 什麼條件走到這、離開時往哪 / 程式碼, one row per entry in spec order; 節點 shows each id's node title; `warn: true` rows and only those carry the ⚠ style |
| legend | spec `legend[]` | the spec's `{kind, label}` list in order; without it, the kinds the nodes use, named 前端 / 後端 / 資料庫 / 佇列 / 外部 / 安全 / 雲端 |
| index | `render.py index <dir> <out>` | one entry per `*.json` in `<dir>`: overview first, then by `topic`; each links `<topic>.html` |
| spec check | `check.py <spec> [--repo <path>]` | one `check: <rule>: …` line per finding for the §3.4 rules; exit 0 clean, 1 findings, 2 usage |
| LangGraph comparison | `check.py --repo` with `langgraph.file` | node and edge sets from the AST (no import), START/END by name; each missing and extra item named; unmapped conditional edge reported, not guessed |
| install | `./sync.sh restore` | links `~/.claude/skills/arch-diagram` and `~/.claude/skills/weekly-report` into the checkout |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | the fixture spec with two nodes, one edge, one route and two conditions (one `warn`) | `render.py page` twice | the two outputs are byte-identical; they have the §3.3 sections in order, `data-node` for both nodes, `data-edge="a->b"`, one route copy with one badge, and a 4-column table whose ⚠ style is on exactly one row |
| AC-2 | a spec whose title is `<script>alert(1)</script>` | `render.py page` | the output contains `&lt;script&gt;`, no `<script`, no `on…=` handler and no `http(s)://` outside SVG namespaces |
| AC-3 | a file that is not JSON | `render.py page` | exit 2 and no output file |
| AC-4 | a directory holding `overview.json`, `csat.json` and `langgraph.json` | `render.py index` | three entries in the order overview, csat, langgraph, each linking its `.html` |
| AC-5 | fixture specs that each break one rule: duplicate id, dangling edge, node off canvas, two overlapping nodes, a label on a node, a title too wide, an unknown kind | `check.py` on each | exit 1, with exactly the matching `check: <rule>:` line; the clean fixture → exit 0 with no output |
| AC-6 | a fixture graph file using `add_node`, `add_edge` and `add_conditional_edges` with a mapping dict, whose first line is `raise SystemExit(9)` | `check.py --repo` with a matching spec / one edge missing / one extra node | exit 0 / exit 1 naming the missing edge / exit 1 naming the extra node. The file is never run: exit 9 never happens |
| AC-7 | a fixture graph with an `add_conditional_edges` call that has no mapping dict | `check.py --repo` | `check: langgraph: unresolved conditional edge from <node>` and exit 1 |
| AC-8 | a scratch HOME | `./sync.sh restore` | `~/.claude/skills/arch-diagram` and `~/.claude/skills/weekly-report` link into the checkout; the layout tests pass with six skills; CLAUDE.md says six |
| AC-9 | langlive-line-oa at its HEAD, with the vault binding | Claude runs `/arch-diagram` for the six first-batch topics | `Architecture/diagrams/` holds six pages, six specs and `index.html`. Every spec passes `check.py --repo`; the LangGraph spec matches 19 nodes / 33 edges. The overview has the ①–⑧ message route; the message topic is step cards. The pages open offline. langlive-line-oa's working tree is unchanged |
| AC-10 | the AC-9 pack, after one node's position and subtitle are edited in a spec copy to simulate drift | Claude re-runs `/arch-diagram` | the other nodes keep their coordinates, and the report names the changed topic and node |

## §5 Rollout
1. **Before the merge, AC-9 and AC-10 run in this worktree.** After the executor's tasks,
   Claude runs the skill from the worktree's `claude-skills/arch-diagram/`, as R-027's
   AC-10 did. Codex cannot read screenshots, so this step is Claude's. What the real pack
   exposes, such as a `fit` estimate rejecting a good layout, feeds the Phase 6 review
   loop.
2. Land on main.
3. `./sync.sh restore` links `arch-diagram` and `weekly-report`.
4. The pack stays in the vault. Moving it into line-oa's repo is a later decision.

## Decisions
**Operator decisions (2026-11-02 → 03)**
- 「想增加一個 skill 是可以描述現階段架構圖的」, starting with langlive-line-oa.
- 「我想砍掉原本的 obsidian-architect 重做 它搞得太複雜了」. Deleted outside this repo
  with a backup; `/obsidian-roadmap`'s two shared modules moved into `scripts/roadmap/`, and
  its 120 tests pass.
- HTML is needed for presentations (「我就是需要簡報啊」). GitLab's HTML view is not the
  target.
- **archify was tried and rejected for drawing.** The architecture drawing was not better, the
  supplementary cards were cluttered, and the sequence diagram was unreadable. Cocoon's
  drawing was preferred.
- **Option B of the Cocoon pack mockup:** one dedicated diagram per topic, plus a condition
  table. Option A's ①–⑧ route is kept as an overlay on the overview.
- **The first batch is six topics:** overview, one message, LangGraph, QA→KB, CSAT and 轉真人.
- **The condition table is fixed at three columns,** with ⚠ only for a real risk.
- **The pack goes into the vault first.** It moves into the repo once the operator confirms it
  is used.
- Door: two-way — it adds a skill directory, two links and a rule line; a revert removes them
  all, and nothing outside the vault is written by the skill.

**Claude's calls** (the operator can override)
- **Claude writes a JSON spec and `render.py` draws it.** Claude does not write raw SVG. The
  spec makes the style consistent across pages, the output deterministic, `check.py`
  possible, and a re-run able to keep coordinates. Claude still chooses every coordinate,
  which is what makes Cocoon look good.
- **Python 3.9 standard library, no dependencies.** The repo already avoids npm dependencies,
  and macOS ships python3.
- **Static HTML, no JS.** Pages must open offline in Obsidian and a browser, and match the
  vault mockup convention.
- **The LangGraph topology comes from the AST and is compared in `check.py`.** It is the one
  place where the diagram can be proven complete (the trial matched 33/33 edges).
- **`weekly-report` is folded into the six-skill rule.** It was committed without the rule, so
  `test_repo-layout` is red on main.
- **Geometry checks use estimated text widths,** and the screenshot review catches what
  estimates miss. A real text-measurement engine would need a browser dependency.

**From the real run on line-oa (AC-9, AC-10)**
- **The legend is the spec's own, or only the kinds used, in zh-TW.** A fixed English list of all seven kinds
  misled on the LangGraph page, where colours mean stages.
- **Node text follows the mockup.** Titles are bold white; a node without lines is centred, and a node with
  lines reads left-aligned.
- **The table names nodes by title,** and the first column no longer breaks ids mid-word. Ids such as
  `t_ai` mean nothing to a reader.
- **The index title is 「架構圖包 · <repo>」.**
- **The checker's `fit` rule caught six LangGraph titles too wide.** The fix was wider nodes, not a smaller
  font: the rule did its job.

**From the builder check**
- **AC-9 and AC-10 block the merge.** Claude runs them in the worktree after the executor,
  using script paths relative to SKILL.md (`sync.sh restore` refuses linked worktrees).
- **One condition row may cover several nodes** (`node` is an id or a list), as in the
  chosen mockup.
- **Default flows skip test directories;** line-oa's first batch draws only
  `lang_ai_customer`, and the operator is asked before the other two StateGraphs.
