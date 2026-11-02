---
date: 2026-11-03
updated: 2026-11-03
type: learning
id: R-029
tags: [learning, ai_system, skill, architecture, diagram, cocoon]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-029
shipped: true
shipped-date: 2026-11-03
---

## For future Claude
> R-029 added `claude-skills/arch-diagram/`, which replaces the deleted `/obsidian-architect`.
> - **How it works.** Claude traces a repo and writes one **diagram spec** (JSON) per topic.
>   `render.py` draws each spec as a Cocoon-style static HTML page; `check.py` gates the spec
>   on structure, overlap, label and text fit, and checks LangGraph topology through the AST.
> - **Output.** Pages go to `<vault project>/Architecture/diagrams/`, plus an `index.html`.
> - **First pack:** langlive-line-oa, with six topics.
>
> **Headline lesson:** tests passed before the page looked right. The renderer met every
> assertion and still looked unlike the chosen mockup: a fixed English legend, titles stuck in
> the top-left corner, and ids in the table. Only rendering the real pack and reading the
> screenshot showed it. A visual deliverable is not done until a screenshot has been read.

## What Shipped
- **`claude-skills/arch-diagram/`:**
  - `SKILL.md`: the `/arch-diagram` workflow — resolve the repo, commit and vault; choose topics;
    trace the code; write the spec; check → render → screenshot, at most three rounds; build the
    index; report.
  - `lib/render.py`, Python 3.9 stdlib only. `page` draws:
    - the diagram, followed by a legend;
    - the route overlays: amber, everything else at 0.2, numbered badges and the steps beside them;
    - a condition table: 節點 / 做什麼 / 什麼條件走到這、離開時往哪 / 程式碼.

    `index` writes the pack index, titled 「架構圖包 · <repo>」. The output has no script, no handler
    and no external URL; all text is escaped; identical input gives byte-identical output.
  - `lib/check.py`, with rules `schema` `id` `edge` `bounds` `overlap` `label` `fit` and
    `langgraph`. The LangGraph rule reads the file through `ast` only and never imports or runs it.
  - `references/spec-format.md` (every field, plus one example that the tests check and render)
    and `references/cocoon-style.md` (palette and rules, with the MIT credit to Cocoon AI).
- **Install:** `sync.sh` links six skills, adding `weekly-report` and `arch-diagram`. `weekly-report`
  had been committed in a025cfc without the rule, so `test_repo-layout` was red on main. CLAUDE.md
  says six, and CONTEXT.md has four new terms.
- **Tests:** `test_arch-diagram.bats` has 33 tests, and the scoped suite is 62/62.
- **The real pack**, in the vault at `langlive-line-oa/Architecture/diagrams/`, at commit 6a7e40e:
  - overview, with the ①–⑧ message route;
  - one LINE message, as step cards;
  - `lang_ai_customer`: 19 nodes and 33 edges, matching the AST;
  - QA→KB S0–S5;
  - CSAT;
  - 轉真人.

## Key Decisions
- **What was asked.** 「想增加一個 skill 是可以描述現階段架構圖的」, starting with langlive-line-oa.
  Then 「砍掉原本的 obsidian-architect 重做 它搞得太複雜了」. The command, about 7,400 lines of Python
  and its tests were deleted outside this repo. The backup is
  `~/.claude/backups/obsidian-architect-20261102.tgz`, and `/obsidian-roadmap`'s two shared
  modules moved into `scripts/roadmap/`.
- **HTML is needed for presentations** (「我就是需要簡報啊」). GitLab's HTML view was not the target.
- **archify was tried on three line-oa diagrams and rejected for drawing.** Its architecture
  drawing was not better, its side cards were cluttered, and its sequence diagram was unreadable.
  Cocoon's hand-placed drawing was preferred.
- **Option B of the Cocoon pack mockup was chosen.** Each topic gets its own diagram, with a
  three-column condition table and ⚠ only for a cited risk. Option A's ①–⑧ route is kept as an
  overlay on the overview.
- **The pack goes into the vault first** and moves into the repo once the operator confirms it is
  used. Re-runs are not automatic yet.
- **Door: two-way.**
- **Claude's calls:**
  - A JSON spec plus a renderer, rather than raw SVG.
  - Python 3.9 stdlib, static HTML.
  - LangGraph topology from the AST.
  - Estimated text widths, with the screenshot catching what the estimate misses.
- **From the builder check:** AC-9 and AC-10 blocked the merge, and Claude ran them in the
  worktree through script paths relative to SKILL.md. One condition row may cover several nodes.
  Default flows skip test directories.
- **From the real run:**
  - The legend is the spec's own, or only the kinds the nodes use, named in zh-TW.
  - Node text follows the mockup: titles bold and white, centred when the node has no lines.
  - The table names nodes by title.
  - The index title is zh-TW.
  - Six LangGraph titles failed `fit`; the fix was wider nodes, because the rule was right.

## What Changed From Plan
- **Codex hardened three things on its own:**
  - only six-digit hex region colours, because `url(https://…)` passed validation;
  - topic slugs are enforced in `render.py` too;
  - the colon in URL-looking text is entity-encoded so no literal external URL appears.
- **Task 7 (Claude only) added four renderer fixes with tests first:** the legend, the node text
  layout, titled table rows and the zh index title.
- `/tmp` was wiped once during the archify trial, which cost one rebuild. Nothing in the repo
  depended on it.

## Bugs
- **The renderer met the plan and did not match the mockup.** It had an English legend listing all
  seven kinds, titles in the top-left in the stroke colour, and ids such as `t_ai` in the table.
  The plan's tests asserted structure, not look.
- **IDEA files had never been used in ai_system.** There was no `docs/ideas/`, and
  `id-gen.sh idea` returned IDEA-001 three times in a row, because it reserves nothing. The three
  were numbered by hand.

## Lessons → checks
- Before calling a visual deliverable done, render the real output and Read a screenshot against the chosen mockup — judgment
- When a test pins rendering details, declare that guarantee in the spec's Seams first — judgment

## Reusable Patterns
- **Content by the model, layout by the model, drawing by code.** Claude writes a small JSON with
  coordinates, and a deterministic renderer plus a checker make the output consistent and
  re-runnable. The renderer has no layout engine, so the hand-placed quality survives.
- **Prove "never executes" with a fixture whose first line is `raise SystemExit(9)`.** Then assert
  that the exit status is never 9.
- **Compare a diagram against the code, not against prose.** Static extraction such as LangGraph's
  `add_node` and `add_edge` gives a set comparison that a review cannot.

## Technical Debt
- **IDEA-001:** `check.py` skips non-literal LangGraph forms without saying so. These are
  `add_node(fn)`, `set_entry_point`, `add_edge([a,b], c)` and `add_sequence`, and a correct diagram
  of such a graph fails. line-oa uses only literal forms.
- **IDEA-002:** the node-text test pins pixels that the spec's Seams table does not declare.
- **IDEA-003:** `nodes[].graph_id` is implemented but missing from the spec contract.
- **Nits from review:**
  - route copies leave regions at full opacity;
  - a non-string legend `kind` makes `check.py` crash;
  - there is no vertical fit check;
  - SKILL.md should use `git grep` for `StateGraph(`;
  - `claude-skills/ship-workflow/SKILL.md` and its README still say four skills.

## Future Follow-ups
- Draw the remaining features when they are needed: push, the customer centre and VIP, the
  dashboard and CS KPI, insights, ES search.
- Move the line-oa pack into the repo's `docs/architecture/` once the operator confirms it is used.
- The line-oa findings from the trial are worth verifying and filing in line-oa:
  - the per-user lock's TTL of 60 s is shorter than the AI's 90 s limit, and the lock is released
    without an owner check;
  - LINE SDK calls are synchronous inside async code in the webhook's process;
  - the dead `intent_merge → vision_synthesis` edge;
  - QA→KB auto-publishes without human review.
