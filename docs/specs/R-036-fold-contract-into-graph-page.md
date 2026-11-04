---
date: 2026-11-04
updated: 2026-11-04
type: spec
id: R-036
tags: [spec, ai_system]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-036
---

## For future Claude
> R-036 moves the R-035 LangGraph node contract from its own `contract` page into the
> LangGraph diagram page, as a short 節點契約 section at the bottom of that page. The section
> has Claude's highlights, one table row per node (fields hidden in a native `<details>`),
> and one line per replacement scenario. The four field-finding lists and the per-node
> sections are gone. `contract.py` and the stale check stay; they now read and write the
> diagram spec's `contract` object.

## Decisions

- Door: two-way. The change stays inside `claude-skills/draw-arch/`, diagram pages without a
  contract are byte-identical, and one revert restores R-035. (my call)
- The operator, on the R-035 page: 「這篇 contract 報告 可以附在 langraph那篇報告裡面的下面 而且有點太複雜」.
  The proposal (fold it in; keep highlights, a node table with expandable fields, and one
  line per scenario; drop the finding lists, node sections and the separate page) was
  accepted: 「好」. (operator)
- `contract` page type removed entirely, along with its index slot. (operator, as proposed)
- Highlights are 3–5 lines written by Claude and placed first. The useful field findings
  (hot fields, platform leaks, reset node) go into them instead of into lists. (my call)
- Field names live in `<details><summary>N</summary>a, b, c</details>`: native HTML, no
  script, so the offline rule holds. (my call)
- A scenario is one line: `<title> → 必須讀 a, b · 必須寫 c`, derived from its nodes as in
  R-035. The scenario `summary` field is dropped. (my call)
- The partial warning moves into the 一句話 cell: `⚠ 掃描不完整：<reasons joined by ；>`,
  so a reader still sees why. An unresolved node shows `⚠ 找不到函式`. (my call)
- Contract CSS is appended only to pages that carry a contract, which keeps every other
  page's bytes unchanged. (my call)

## Seams

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| page types | `page` ∈ `diagram`/`table`/`cards`/`seams` | `contract` is not a page type: `check.py` gives `check: schema:` and `render.py page` exits 2 without output. Pages without a `contract` object (all golden files, table, cards and seams fixtures) are byte-identical to before. |
| diagram contract | diagram spec optional `contract: {graph: {file, state, roots}, nodes: [{id, kind, file, line, reads, writes, partial, resolved, verdict?, note?}], declared: [k], highlights: [text], scenarios: [{title, nodes: [id]}]}` | Same node rules as R-035 (`kind` node/router, `verdict` easy/medium/hard, duplicate ids, unknown scenario node). `highlights` is a list of text, at most 5 items (`check: schema:` otherwise). |
| contract scanner | `python3 lib/contract.py <repo> <diagram spec.json>` | Rewrites the computed fields inside `spec["contract"]` (nodes and declared) and `repo.commit`, keeping `verdict`, `note`, `highlights` and `scenarios`, with the same resolution and partial rules as R-035. A spec without a `contract` object exits 2 and writes nothing. |
| contract check | `check.py <spec> --repo <repo>` | For a diagram spec with `contract`: `check: contract: stale` when computed facts differ, and never because of the commit alone. |
| contract section | `render.py page` on a diagram spec with `contract` | After the condition table and before the footer, a `<section class="contract">` with `<h2>節點契約</h2>`, then three blocks in order: (1) the highlights as `<ul>`; (2) a table 節點 / 讀 / 寫 / 好不好換 / 一句話, one row per node in spec order, where routers carry （路由）, 讀 and 寫 are each a `<details><summary>count</summary>fields joined by ", "</details>` (or `0` with no `<details>`), the verdict uses the `v-easy`/`v-medium`/`v-hard` tone and label (`—` when absent), and 一句話 is the note, with the partial or unresolved warning after it; (3) `<h3>替換情境</h3>` with one `<li>` per scenario reading `<title> → 必須讀 X · 必須寫 Y`, where X and Y are each `<details><summary>N 個欄位</summary>fields joined by ", "</details>` (or 沒有 for an empty side), so a long interface stays one short line. Counts and the verdict do not wrap. No `<script`, no `on*=`, no literal external URL. Below 700 px the table becomes cards. |
| index | `render.py index` | overview, features, seams, jobs first; there is no contract slot. |
| skill workflow | `SKILL.md` | The contract step writes the `contract` object into the first StateGraph's diagram spec, runs `contract.py` on that spec, then writes 3–5 highlights, verdicts, notes and scenarios. |

## Acceptance

- **AC-1** Given the golden files and the table, cards and seams tests, then output is unchanged.
- **AC-2** Given `page: "contract"`, then `check.py` reports `check: schema:` and `render.py`
  exits 2 with no output.
- **AC-3** Given the R-035 `lgrepo` fixture and a diagram spec (copy of `lg.json`) carrying
  `contract`, when `contract.py` runs, then `spec["contract"]["nodes"]` matches the R-035
  facts (for example `one` reads `[a, b]` and writes `[c]`), while `highlights`, `verdict`
  and `scenarios` survive a re-run and the diagram fields are untouched. A spec without
  `contract` exits 2 and is unchanged.
- **AC-4** Given that spec, after a source change: `check.py --repo` reports
  `check: contract: stale`. After an unrelated commit it does not.
- **AC-5** Given that spec with highlights `["h1","h2"]`, `verdict: "easy"` on `one` and the
  scenario `{title: "換一和二", nodes: ["one","two"]}`, when rendered, then the page has, in order:
  the diagram, the condition table (if any), `<section class="contract">` with `h1`, `h2`, a
  row for `one` whose 讀 is `<details><summary>2</summary>a, b</details>` and whose verdict is
  容易換, `three` with `⚠ 掃描不完整：`, `ghost` with `⚠ 找不到函式`,
  `route_one（路由）`, and `換一和二 → 必須讀 <details><summary>2 個欄位</summary>a, b</details> · 必須寫 <details><summary>2 個欄位</summary>c, d</details>`. There is no 熱點欄位
  heading and no `id="node-` anchors.
- **AC-6** Given more than 5 highlights, or an unknown scenario node, each gives its `check:` finding.
- **AC-7** Given highlight, note and scenario-title text containing `<script>` and
  `https://evil.example`, then it renders escaped with no literal external URL.
- **AC-8** (done when) Given langlive-line-oa re-run, then:
  - `contract.json` and `contract.html` are gone from the vault, and the index has no contract entry;
  - `langgraph.html` ends with 節點契約: 3–5 highlights, every `add_node` and router row
    with a verdict and note, and the scenarios as one line each;
  - `check.py --repo` is clean;
  - a screenshot was read.
