# R-029 arch-diagram skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add `claude-skills/arch-diagram/`. Claude writes one diagram spec (JSON) per topic, `render.py` turns each into a standalone Cocoon-style HTML page plus an index, and `check.py` gates every spec.

**Architecture:** There are two stdlib Python CLIs in `claude-skills/arch-diagram/lib/`. `render.py` owns the palette, text-width estimate and HTML output. `check.py` imports those constants from `render.py`, validates spec structure and geometry, and compares a LangGraph spec with the StateGraph read through `ast`. `SKILL.md` holds the workflow Claude follows. Tests are bats files in the ship-workflow suite, which call the CLIs with `python3`.

**Tech Stack:** Python 3.9 standard library (`json`, `ast`, `html`, `re`, `sys`, `pathlib`), bats, bash.

**Spec:** `docs/specs/R-029-add-arch-diagram-skill.md`. The visual reference is the vault mockup `Proposals/mockups/R-029-cocoon-architecture-pack-mockup.html`, option B.

## Global Constraints
- **Python 3.9 standard library only.** No `match` statements, no `X | Y` type unions, no third-party imports.
- **Output is static HTML.** It contains no `<script>`, no `on…=` handlers, and no `http://` or `https://` except the SVG/XHTML namespace URIs (`http://www.w3.org/…`).
- **All spec text is escaped** with `html.escape(..., quote=True)` before it reaches HTML or an attribute.
- **Identical spec gives byte-identical HTML.** No timestamps, random ids or dict-order dependence: SVG ids derive from `topic` plus a fixed index.
- **Palette, verbatim from the spec:**
  - `kind` → (fill, stroke):
    - `fe` (`rgba(8,51,68,0.4)`, `#22d3ee`)
    - `be` (`rgba(6,78,59,0.4)`, `#34d399`)
    - `db` (`rgba(76,29,149,0.4)`, `#a78bfa`)
    - `bus` (`rgba(251,146,60,0.3)`, `#fb923c`)
    - `ext` (`rgba(30,41,59,0.5)`, `#94a3b8`)
    - `sec` (`rgba(136,19,55,0.4)`, `#fb7185`)
    - `cloud` (`rgba(120,53,15,0.3)`, `#fbbf24`)
  - **Background and arrows:** background `#020617`, a 40 px grid in `#1e293b`, arrows `#64748b`, route highlight `#fbbf24`.
- **Line tones:** `body` `#cbd5e1`, `cond` `#fcd34d`, `warn` `#fb7185`, `muted` `#94a3b8`.
- **Text-width estimate:** a character with `ord(c) > 0x2E80` is 1.0 em, every other character 0.62 em.
  - **Font sizes:** title 13, sub and port 10, lines 10.5, edge labels 10.
  - **Label box:** `text_width(label, 10) + 10` wide and 16 high, centred on (`lx`, `ly`).
- **The condition table has columns 節點 / 做什麼 / 什麼條件走到這、離開時往哪 / 程式碼.** Only `warn: true` rows carry `class="warn"` and the ⚠ prefix.
- **Tests follow the suite's rules:**
  - `[ … ]` assertions with `|| return 1`, never bare `[[ ]]`, as `test_suite-hygiene.bats` enforces;
  - scratch dirs come from `make_scratch`;
  - run scoped bats only: `cd claude-skills/ship-workflow && bats tests/test_arch-diagram.bats tests/test_repo-layout.bats tests/test_sync-install.bats`.
- **The skill never reads** `env.json`, `.env*` or key files of a target repo, and never writes into a target repo.

## Review Focus
1. **Spec text with `&`, `"`, `<` or `>`** in a title, a line, a condition or an edge label. These come from code-like text such as `List[str]` and `a<b`. The page shows them literally, and attributes stay well-formed. *Test: Task 1, `escapes code-like text in text and attributes`.*
2. **An edge `path` that is not SVG path data,** for example `M0 0" onload="x`. `check.py` reports `schema` and `render.py` still escapes it. *Tests: Task 3 `bad path`; Task 1 `escapes code-like text…`.*
3. **A spec with no `routes`, no `conditions` and no `regions`.** The page renders the diagram only, with no empty headings and no empty table. *Test: Task 1, `minimal spec renders without optional sections`.*
4. **A `conditions[].node` list** such as `["a","b"]`. The table shows `a / b`, and `check.py` resolves every id. *Tests: Task 1 fixture row; Task 3 `dangling condition id in a list`.*
5. **Output and spec paths containing spaces,** like the vault's `10 Projects/…`. Both CLIs read and write them. *Test: Task 2, `index and page handle paths with spaces`.*

---

### Task 1: `render.py page`

**Files:**
- Create: `claude-skills/arch-diagram/lib/render.py`
- Create: `claude-skills/ship-workflow/tests/fixtures/arch-diagram/clean.json`
- Create: `claude-skills/ship-workflow/tests/fixtures/arch-diagram/minimal.json`
- Test: `claude-skills/ship-workflow/tests/test_arch-diagram.bats`

**Interfaces:**
- Produces, in `render.py`:
  - `KINDS: dict[str, tuple[str, str]]`
  - `TONES: dict[str, str]`
  - `SHAPES = ("box", "pill")`
  - `text_width(s: str, size: float) -> float`
  - `label_box(edge: dict) -> tuple[float, float, float, float]` returning (x, y, w, h)
  - `load_spec(path: str) -> dict`, which raises `SpecError` when the file is unreadable or not JSON
  - `render_svg(spec: dict, uid: str, route: dict | None = None) -> str` (typed `Optional[dict]` for 3.9)
  - `render_page(spec: dict) -> str`
- CLI: `python3 render.py page <spec.json> <out.html>`. Exit 0; exit 2 on bad arguments or `SpecError`, with no output file written.
- **The graph identity of a node** is `node.get("graph_id", node["id"])`. Task 4 uses it, and it lets START/END be drawn twice with distinct `id`s.

**Fixture `clean.json`:**
- `topic` `"demo"`, `title` `"Demo 架構"`, `subtitle` `"測試用"`.
- `repo` `{"name":"demo","commit":"0123456789abcdef0123456789abcdef01234567"}`, `canvas` `{"w":600,"h":300}`.
- One region: `{"x":10,"y":10,"w":580,"h":120,"color":"#fbbf24","label":"EKS"}`.
- Nodes:
  - `a`: be, at (20, 40), 160 × 60, `title` `"Webhook"`, `sub` `"api/x.py"`, `lines` `[{"text":"條件：簽章不對 → 拒絕","tone":"cond"}]`, `src` `["api/x.py:1-9"]`.
  - `b`: db, at (300, 40), 160 × 60, `title` `"PostgreSQL"`.
- Edge: `a → b`, `path` `"M180 70 H300"`, `label` `"寫入"`, `lx` 240, `ly` 60.
- Route `{"name":"一則訊息","nodes":["a","b"],"edges":["a->b"],"badges":[{"n":1,"x":190,"y":40}],"steps":[{"title":"打 webhook","note":"簽章不對就拒絕","tone":"cond"}]}`.
- Conditions:
  - `{"node":"a","does":"收事件","when":"簽章對 → 排隊","src":"api/x.py:1-9","warn":false}`
  - `{"node":["a","b"],"does":"寫入","when":"重複 → 略過","src":"x.py:2-3","warn":true}`

**Fixture `minimal.json`:** the same top-level fields with nodes `a` and `b` and the edge only: no `regions`, `routes` or `conditions`.

- [x] **Step 1: Write the failing tests** in `test_arch-diagram.bats`:
  - **Setup:** `load helpers`; `AD="$SHIP_SKILL_ROOT/../arch-diagram/lib"`; `FX="$SHIP_SKILL_ROOT/tests/fixtures/arch-diagram"`; `S="$(make_scratch arch-diagram)"`.
  - **`page is deterministic and has every section in order`:**
    - Render `clean.json` twice; `cmp` passes.
    - The byte offsets of `<h1`, `class="diagram"`, `class="route"`, `<table class="cond"` and `<footer` increase in that order.
    - `grep -c 'data-node="a"'` ≥ 1, and `data-edge="a->b"` is present.
    - Exactly one `class="badge"` in the route section.
    - The table header row holds exactly the four column names.
    - `grep -c 'class="warn"'` = 1.
    - The list row renders `a / b`.
    - The footer contains the full 40-hex commit.
  - **`escapes code-like text in text and attributes`:** copy `clean.json` with python, setting:
    - `title` = `<script>alert(1)</script>`;
    - node `a`'s `sub` = `List[str] & "q"`;
    - the edge `path` = `M0 0" onload="x`.

    Then render and assert:
    - the output contains `&lt;script&gt;` and `&amp;`;
    - `grep -c '<script'` = 0;
    - `grep -cE ' on[a-z]+=' ` = 0;
    - `grep -oE 'https?://[^"]*' | grep -v '^http://www.w3.org/'` is empty.
  - **`minimal spec renders without optional sections`:** render `minimal.json`. The output has no `class="route"`, no `<table` and no empty `<h2></h2>`.
  - **`not-JSON input exits 2 and writes nothing`:** `echo '{nope' > $S/bad.json`; `run python3 "$AD/render.py" page "$S/bad.json" "$S/out.html"`; `status` = 2; `[ ! -e "$S/out.html" ]`.

- [x] **Step 2: Run to verify they fail.** Run `cd claude-skills/ship-workflow && bats tests/test_arch-diagram.bats`. Expected: all fail, because `render.py` is missing.

- [x] **Step 3: Implement `render.py`** with the interfaces above.
  - **Page order (spec §3.3):**
    1. `<h1>` title;
    2. `<p class="sub">` subtitle · repo name · `commit[:7]`;
    3. `<section class="diagram">` with `render_svg(spec, f"{topic}-0")`;
    4. per route `i`, a `<section class="route">` with `<h2>` name, `render_svg(spec, f"{topic}-r{i}", route)` and an `<ol class="steps">` (each `<li>` has the title and the note in its tone colour);
    5. a `<table class="cond">` when `conditions` is non-empty;
    6. `<footer>` with the full commit.
  - **SVG:** node rects, as in the mockup, with an opaque `#0f172a` under-rect, then the kind fill, a 1.5 px stroke and `rx` 6; a pill gets `rx = h/2`. Regions are dashed `8,4`. Edges are drawn before nodes and carry `marker-end` unless `arrow` is false.
  - **Route copies:** nodes and edges not in the route get `opacity="0.2"`; route edges are drawn in `#fbbf24` at 2.2 px with an amber marker. Each badge is `<g class="badge">`: a circle of r = 11 and its number.
  - **CSS:** inline `<style>` only. Use a monospace system font stack (`'JetBrains Mono',SFMono-Regular,Menlo,'PingFang TC',monospace`) and no web font.
  - **Writing:** write the output with `encoding="utf-8"` only after the whole page string is built.

- [x] **Step 4: Run to verify they pass.** Run `bats tests/test_arch-diagram.bats`. Expected: 4 tests pass.

- [x] **Step 5: Commit**
```bash
git add claude-skills/arch-diagram/lib/render.py claude-skills/ship-workflow/tests/test_arch-diagram.bats claude-skills/ship-workflow/tests/fixtures/arch-diagram/
git commit -m "feat(R-029): render.py page — diagram spec to Cocoon-style HTML"
```

### Task 2: `render.py index`

**Files:**
- Modify: `claude-skills/arch-diagram/lib/render.py`
- Test: `claude-skills/ship-workflow/tests/test_arch-diagram.bats`

**Interfaces:**
- Consumes: `load_spec`, `SpecError` (Task 1).
- Produces: `render_index(specs: list) -> str`.
- CLI: `python3 render.py index <dir> <out.html>`.
  - It reads every `*.json` directly in `<dir>`.
  - Order: `topic == "overview"` first, then the rest sorted by `topic`.
  - Each entry is `<a href="<topic>.html">` with the title and subtitle.
  - A file that fails `load_spec` → exit 2, naming the file on stderr, and no output written.

- [x] **Step 1: Write the failing tests:**
  - **`index lists overview first then by topic`:** in `$S/pack/`, write copies of `clean.json` with `topic` set to `overview`, `csat` and `langgraph`, as `overview.json`, `csat.json` and `langgraph.json`. Render the index. The offsets of `href="overview.html"`, `href="csat.html"` and `href="langgraph.html"` increase in that order, and `grep -c 'href="'` = 3.
  - **`index refuses an unreadable spec`:** add `$S/pack/broken.json` containing `{x`. Expect exit 2, `broken.json` named in the output, and no index file.
  - **`index and page handle paths with spaces`:** use `$S/10 Projects/pack/` with one spec. Both `page` and `index` write into that directory, and both files exist.
- [x] **Step 2: Run to verify they fail.** Run `bats tests/test_arch-diagram.bats -f index`. Expected: FAIL.
- [x] **Step 3: Implement `render_index` and the `index` subcommand** in `render.py`.
- [x] **Step 4: Run to verify they pass.** Run `bats tests/test_arch-diagram.bats`. Expected: all pass.
- [x] **Step 5: Commit**
```bash
git add claude-skills/arch-diagram/lib/render.py claude-skills/ship-workflow/tests/test_arch-diagram.bats
git commit -m "feat(R-029): render.py index — pack index page"
```

### Task 3: `check.py` structure and geometry rules

**Files:**
- Create: `claude-skills/arch-diagram/lib/check.py`
- Test: `claude-skills/ship-workflow/tests/test_arch-diagram.bats`

**Interfaces:**
- Consumes: `KINDS`, `TONES`, `SHAPES`, `text_width`, `label_box`, `load_spec` and `SpecError` from `render.py`. Import them with `sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))`.
- Produces:
  - `check_spec(spec: dict, repo: str | None = None) -> list[str]`, returning finding lines `check: <rule>: <detail>`;
  - CLI `python3 check.py <spec.json> [--repo <path>]`, which prints the findings and exits 0 with none, 1 with findings, or 2 on bad arguments or `SpecError`.
- **Rule details:**
  - **`schema`:** the required top-level fields (`topic`, `title`, `repo.name`, `repo.commit`, `canvas.w`, `canvas.h`, `nodes`, `edges`). Also:
    - node `id`, `x`, `y`, `w`, `h`, `kind`, `title`, and edge `from`, `to`, `path`;
    - `topic` matches `^[a-z0-9-]+$` and every `id` matches `^[A-Za-z0-9_.:-]+$`;
    - `repo.commit` matches `^[0-9a-f]{7,40}$`;
    - `kind`, `tone` and `shape` are in their sets, and `w`, `h`, `canvas.w`, `canvas.h` are > 0;
    - `path` matches `^[MLHVCQZmlhvcqz0-9 .,-]+$`.
  - **`id`:** a duplicate node `id`.
  - **`edge`:** an edge `from`/`to`, a route node, a route edge string `a->b` that is not an existing edge, or a condition node or list item that does not exist.
  - **`bounds`:** `x < 0`, `y < 0`, `x + w > canvas.w` or `y + h > canvas.h`.
  - **`overlap`:** two node rectangles with positive-area intersection. Touching edges are fine.
  - **`label`:** an edge label box with positive-area intersection with any node, or with another label box.
  - **`fit`:** `text_width(title, 13)`, `text_width(sub, 10)`, `text_width(port, 10)` or `text_width(line.text, 10.5)` greater than `w - 24`.

- [x] **Step 1: Write the failing tests.**
  - **Helper:** `mutate <python-expr>` loads `clean.json` as `s` in python, applies the expression, and writes `$S/m.json`.
  - **Cases:**
    - **`clean spec passes`:** `check.py clean.json` → exit 0, empty output.
    - **`duplicate id`:** `s['nodes'].append(dict(s['nodes'][0], x=20, y=200))` → exit 1, and the output contains `check: id:`.
    - **`dangling edge`:** `s['edges'][0]['to']='zz'` → `check: edge:`.
    - **`dangling condition id in a list`:** `s['conditions'][1]['node']=['a','zz']` → `check: edge:`.
    - **`off canvas`:** `s['nodes'][1]['x']=500` → `check: bounds:`.
    - **`overlapping nodes`:** `s['nodes'][1].update(x=150, y=90)` → `check: overlap:`.
    - **`label on a node`:** `s['edges'][0]['lx']=100` → `check: label:`.
    - **`title too wide`:** `s['nodes'][0]['title']='這是一個非常非常非常非常長的標題文字'` → `check: fit:`.
    - **`unknown kind`:** `s['nodes'][0]['kind']='xx'` → `check: schema:`.
    - **`bad path`:** `s['edges'][0]['path']='M0 0\" onload=\"x'` → `check: schema:`.
  - **Each broken case asserts** exit 1, at least one `check: <its rule>:` line, and no line of any
    other rule: `grep '^check: ' | grep -v '^check: <rule>:'` is empty. A dangling edge also
    breaks the route's `a->b`, so `edge` may fire twice.
- [x] **Step 2: Run to verify they fail.** Run `bats tests/test_arch-diagram.bats -f check`. Expected: FAIL, because `check.py` is missing.
- [x] **Step 3: Implement `check.py`** for the rules above. Findings come out in rule order (`schema`, `id`, `edge`, `bounds`, `overlap`, `label`, `fit`). When `schema` has findings, stop after it: later rules would crash on missing fields.
- [x] **Step 4: Run to verify they pass.** Run `bats tests/test_arch-diagram.bats`. Expected: all pass.
- [x] **Step 5: Commit**
```bash
git add claude-skills/arch-diagram/lib/check.py claude-skills/ship-workflow/tests/test_arch-diagram.bats
git commit -m "feat(R-029): check.py — schema, ids, edges, bounds, overlap, labels, fit"
```

### Task 4: `check.py` LangGraph comparison

**Files:**
- Modify: `claude-skills/arch-diagram/lib/check.py`
- Create: `claude-skills/ship-workflow/tests/fixtures/arch-diagram/graph_ok.py`
- Create: `claude-skills/ship-workflow/tests/fixtures/arch-diagram/graph_unmapped.py`
- Create: `claude-skills/ship-workflow/tests/fixtures/arch-diagram/lg.json`
- Test: `claude-skills/ship-workflow/tests/test_arch-diagram.bats`

**Interfaces:**
- Produces: `extract_graph(path: str) -> tuple[set, set, list]`, returning node names, `(src, dst)` edge pairs, and the source nodes of unresolved conditional edges.
- **What it reads:**
  - It parses with `ast.parse` only and never imports.
  - It walks `ast.Call` whose `func` is an `ast.Attribute` named `add_node`, `add_edge` or `add_conditional_edges`.
  - **Node names:** a string `Constant`, or a `Name` `START`/`END` mapped to `"START"`/`"END"`.
  - **Conditional edges:** the mapping is the third positional argument or the `path_map=` keyword, as an `ast.Dict`. Each value becomes an edge `src → value`. A missing or non-Dict mapping appends `src` to the unresolved list.
- **What it compares** (in `check_spec`, when `repo` is given and `spec["langgraph"]["file"]` exists):
  - It resolves the file against `repo`.
  - Node set: the spec's graph identities minus `START`/`END`, against `extract_graph` nodes.
  - Edge set: the spec edges mapped through each endpoint's graph identity, against `extract_graph` edges.
  - Findings, sorted:
    - `check: langgraph: missing node X`
    - `check: langgraph: extra node X`
    - `check: langgraph: missing edge A->B`
    - `check: langgraph: extra edge A->B`
    - `check: langgraph: unresolved conditional edge from X`
  - A missing graph file → `check: langgraph: file not found <path>`.

**Fixtures:**
- **`graph_ok.py`:** first line `raise SystemExit(9)`, then `from langgraph.graph import StateGraph, START, END`, `g = StateGraph(dict)`, `g.add_node("a", f)`, `g.add_node("b", f)`, `g.add_edge(START, "a")`, `g.add_conditional_edges("a", route, {"go": "b", "stop": END})`, `g.add_edge("b", END)`.
- **`graph_unmapped.py`:** the same, but the conditional call is `g.add_conditional_edges("a", route)` and there is a plain `g.add_edge("a", "b")`.
- **`lg.json`:**
  - `canvas` 900×300;
  - pill `START` (ext) at (10,120,70,30), be `a` at (120,110,140,50), be `b` at (320,40,140,50), pill `END` (ext) at (560,120,70,30), and pill `END2` (ext, `graph_id` `"END"`) at (560,200,70,30);
  - edges `START→a` `M80 135 H120`, `a→b` `M260 125 H290 V65 H320` labelled `go`, `a→END2` `M260 145 H290 V215 H560` labelled `stop`, and `b→END` `M460 65 H520 V135 H560`;
  - `langgraph` `{"file":"graph_ok.py"}`.

- [x] **Step 1: Write the failing tests:**
  - **`langgraph spec matching the AST passes without running the file`:** `check.py lg.json --repo "$FX"` → status 0, and status is never 9.
  - **`langgraph missing edge is named`:** remove `b→END` from a copy of the spec → status 1; the output contains `check: langgraph: missing edge b->END`.
  - **`langgraph extra node is named`:** add node `c` (be, at (700,40,140,50)) → status 1; the output contains `check: langgraph: extra node c`.
  - **`unmapped conditional edge is reported`:** point a copy's `langgraph.file` at `graph_unmapped.py` and drop the `a→END2` edge → the output contains `check: langgraph: unresolved conditional edge from a`; status 1.
- [x] **Step 2: Run to verify they fail.** Run `bats tests/test_arch-diagram.bats -f langgraph`. Expected: FAIL.
- [x] **Step 3: Implement `extract_graph`** and the comparison in `check.py`.
- [x] **Step 4: Run to verify they pass.** Run `bats tests/test_arch-diagram.bats`. Expected: all pass.
- [x] **Step 5: Commit**
```bash
git add claude-skills/arch-diagram/lib/check.py claude-skills/ship-workflow/tests/test_arch-diagram.bats claude-skills/ship-workflow/tests/fixtures/arch-diagram/
git commit -m "feat(R-029): check.py compares a LangGraph spec with the StateGraph AST"
```

### Task 5: `SKILL.md` and references

**Files:**
- Create: `claude-skills/arch-diagram/SKILL.md`
- Create: `claude-skills/arch-diagram/references/spec-format.md`
- Create: `claude-skills/arch-diagram/references/cocoon-style.md`
- Test: `claude-skills/ship-workflow/tests/test_arch-diagram.bats`

**Interfaces:**
- Consumes: the CLIs from Tasks 1–4, called as `python3 "<skill dir>/lib/render.py"` and `python3 "<skill dir>/lib/check.py"`, where `<skill dir>` is the directory holding this SKILL.md.

**Content:**
- **`SKILL.md`** has frontmatter `name: arch-diagram` and a `description` that says it draws a Cocoon-style architecture pack into the vault project's `Architecture/diagrams/`. Its body is spec §3.5 steps 1–7, written as instructions, including:
  - the `airos-binding.sh project_path` resolution, the `--out` override, and stopping to ask when neither works;
  - the default topics: overview, message route, one flow per `StateGraph(` outside test directories, asking before others;
  - the no-secrets rule and dirty-path note;
  - step cards for message topics; three-column conditions; `warn` only when the cited code shows the risk;
  - check → render → full-page headless Chrome screenshot (`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --window-size=1280,<h> --screenshot=<png> "file://<url-encoded path>"`) → Read, for at most three rounds;
  - `render.py index`;
  - the report contents;
  - on a re-run, editing the saved spec in place and listing the changes.
- **`spec-format.md`** documents every field of spec §3.2, including `graph_id`, `conditions[].node` as an id or a list, `tone`, `shape`, `dash` and `arrow`. It has one complete fenced ```json example.
- **`cocoon-style.md`** holds the palette, the tones and the font stack from Global Constraints, plus these layout rules:
  - edges are drawn before nodes;
  - a ≥ 30 px gap between nodes;
  - labels sit on straight segments;
  - one subtitle line, at most four `lines`;
  - message topics are numbered step cards in a snake layout.

  It ends with the credit line `Palette and design rules adapted from Cocoon AI's architecture-diagram-generator (MIT License).`

- [x] **Step 1: Write the failing tests:**
  - **`skill files exist and the spec-format example passes check.py`:**
    - `SKILL.md` contains `name: arch-diagram`.
    - Both references exist.
    - Extract the first ```json block of `spec-format.md` with awk into `$S/example.json`; `check.py` on it → status 0.
    - `render.py page` on it → status 0.
    - `cocoon-style.md` contains `MIT License`.
- [x] **Step 2: Run to verify it fails.** Run `bats tests/test_arch-diagram.bats -f skill`. Expected: FAIL.
- [x] **Step 3: Write the three files** as described.
- [x] **Step 4: Run to verify it passes.** Run `bats tests/test_arch-diagram.bats`. Expected: all pass.
- [x] **Step 5: Commit**
```bash
git add claude-skills/arch-diagram/SKILL.md claude-skills/arch-diagram/references/ claude-skills/ship-workflow/tests/test_arch-diagram.bats
git commit -m "feat(R-029): arch-diagram SKILL.md, spec format and Cocoon style references"
```

### Task 6: Install, rule and docs: six skills

**Files:**
- Modify: `sync.sh`. Change the line `SKILLS=(ship-workflow run-plan code-review-skill pr-review)` and the help line that lists the skills.
- Modify: `CLAUDE.md`. Change line 3–4, the R-004 rule sentence, and line 11, the `./sync.sh restore` link list.
- Modify: `CONTEXT.md`. Append four terms.
- Modify: `claude-skills/ship-workflow/tests/test_repo-layout.bats` (header comment and the test on lines 8–11).
- Modify: `claude-skills/ship-workflow/tests/test_sync-install.bats`. Change the setup `mkdir` on line 15–16, the skill loop on line 56, the test name, and the `ls` expectation on line 107.

**Changes:**
- **`sync.sh`:** `SKILLS=(ship-workflow run-plan code-review-skill pr-review weekly-report arch-diagram)`. The help line reads `install ai_system (ship-workflow + run-plan + code-review-skill + pr-review + weekly-report + arch-diagram)`.
- **CLAUDE.md:** the rule names the six skills — `ship-workflow`, plus `run-plan`, `code-review-skill`, `pr-review`, `weekly-report` and `arch-diagram` — and nothing else (R-004, R-029). The restore line lists the six.
- **CONTEXT.md**, one bullet each, in the file's existing style:
  - **architecture pack:** the HTML pages plus `index.html` that `/arch-diagram` writes into `<vault project>/Architecture/diagrams/` (R-029).
  - **diagram spec:** one JSON per topic: nodes, edges and coordinates chosen by Claude, rendered by `render.py`, gated by `check.py`.
  - **condition table:** the three-column table under a diagram: 做什麼 / 什麼條件走到這、離開時往哪 / 程式碼, ⚠ only for a cited risk.
  - **route overlay:** a copy of a diagram with one route's nodes and edges in amber, the rest at 0.2, plus numbered badges and steps.

- [x] **Step 1: Update the two tests first:**
  - **`test_repo-layout.bats`:** the expected `ls` string becomes `arch-diagram code-review-skill pr-review run-plan ship-workflow weekly-report `. The test name and header say six skills.
  - **`test_sync-install.bats`:**
    - setup also `mkdir`s `$R/claude-skills/weekly-report` and `$R/claude-skills/arch-diagram`;
    - the restore test loops over all six and is renamed to say 6 skills;
    - the line-107 expectation becomes the same six-name string.
  - **New test in `test_repo-layout.bats`, `CLAUDE.md names the six skills`:** `grep -F 'weekly-report' CLAUDE.md` and `grep -F 'arch-diagram' CLAUDE.md` both succeed on the R-004 rule line.
- [x] **Step 2: Run to verify they fail on the sync and doc parts.** Run `bats tests/test_repo-layout.bats tests/test_sync-install.bats`. Expected: the restore-loop test and the CLAUDE.md test fail. The layout test now passes, because both directories exist after Task 5.
- [x] **Step 3: Edit `sync.sh`, `CLAUDE.md` and `CONTEXT.md`** as listed.
- [x] **Step 4: Run the scoped suite.** Run `cd claude-skills/ship-workflow && bats tests/test_arch-diagram.bats tests/test_repo-layout.bats tests/test_sync-install.bats`. Expected: all pass.
- [x] **Step 5: Commit**
```bash
git add sync.sh CLAUDE.md CONTEXT.md claude-skills/ship-workflow/tests/test_repo-layout.bats claude-skills/ship-workflow/tests/test_sync-install.bats
git commit -m "feat(R-029): install arch-diagram and weekly-report; R-004 rule says six skills"
```

### Task 7: Real run on langlive-line-oa (AC-9, AC-10) — CLAUDE ONLY

> **Codex / any non-Claude executor: SKIP THIS TASK.** It needs Claude to trace code across six topics, read headless-Chrome screenshots and fix layouts. Stop after Task 6 and report done.

**Files:**
- Writes only into the vault: `/Users/leric/Documents/SecondBrain/10 Projects/langlive-line-oa/Architecture/diagrams/`.
- May modify `render.py` / `check.py` with a test, if the real run exposes a bug.

**Steps:**
- [ ] **Step 1:** Follow the worktree's `claude-skills/arch-diagram/SKILL.md` against `/Users/leric/Desktop/code/langlive-line-oa`, calling the scripts by their worktree paths, for the six topics `overview`, `message`, `langgraph`, `qa-to-kb`, `csat` and `handoff`. Earlier work can be reused:
  - the mockup's coordinates for overview, message, QA→KB and CSAT;
  - the archify run's conditions for LangGraph, from `/tmp/archify-line-oa/langgraph/candidate.json` if it still exists.

  Every fact is re-checked against line-oa HEAD.
- [ ] **Step 2:** Every spec passes `check.py --repo /Users/leric/Desktop/code/langlive-line-oa`, and the LangGraph spec reports no findings (19 nodes, 33 edges). Render each page, take a full-page screenshot, Read it, and fix it, for at most three rounds. Then run `render.py index`.
- [ ] **Step 3 (AC-10):** Copy `overview.json` aside, move one node's `x` by 40 and change its `sub`, then re-run the skill for `overview`. Every other node's coordinates are unchanged, and the report names the topic and the node. Restore the original.
- [ ] **Step 4:** `git -C /Users/leric/Desktop/code/langlive-line-oa status --short` shows the same four dirty paths as before (`docs/product/ROADMAP.md`, `.impeccable/`, `.ua/`, `frontend/.claude/`).
- [ ] **Step 5:** Commit any `render.py` / `check.py` fixes together with their tests: `fix(R-029): <what the real run exposed>`.

## Execution log

- Task 1: page tests RED (3 fail, 1 pass) → GREEN (4/4). The fail-first invalid-JSON test passed immediately because the missing script also exits 2; accepted per executor instructions.
- Task 2: index tests RED (3 fail) → GREEN (7/7 page and index tests).
- Task 3: checker tests RED (10 fail) → GREEN (17/17); broken fixtures report only their intended rule.
- Task 4: LangGraph tests RED (3 fail, matching-spec test passes before comparison exists) → GREEN (21/21); fixtures with SystemExit(9) were parsed, never executed.
- Task 5: skill/reference example test RED → GREEN (22/22), including checking and rendering the complete JSON example.
- Task 6: layout/install tests RED at the expected installer and CLAUDE.md assertions → GREEN (51/51 scoped tests before final review).
- Final read-only review: reproduced the external SVG paint finding. No other major failures or deferred minor findings; Task 7 was excluded by the executor instructions.
- Deviation: added six-digit hex-color checks in check.py and direct rendering — a region color containing url(https://…) passed validation and violated the plan's offline/no-external-URL requirement.
- Deviation: enforce the existing topic slug format in page/index rendering — malformed topics could create external index links or SVG resource identifiers when rendering directly.
- Deviation: encode URL scheme colons as HTML entities in spec text — preserves visible text while satisfying the plan's prohibition on literal external URLs in HTML.
- Final repair verification: five regression tests observed RED → GREEN; the prescribed scoped suite passes 56/56. git diff --check is clean. Local review repairs are grouped into the Task 6 commit to preserve one commit per task.
- Task 7: skipped entirely as instructed (CLAUDE ONLY); AC-9/AC-10 real-pack validation remains for Claude.
- Result: DONE_WITH_CONCERNS, solely for the three small local deviations recorded above. Tasks 1–6 are complete; no push or branch change.
