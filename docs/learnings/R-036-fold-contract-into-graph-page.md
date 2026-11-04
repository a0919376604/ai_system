---
date: 2026-11-04
updated: 2026-11-04
type: learning
id: R-036
tags: [learning, ai_system, draw-arch, langgraph, simplification]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-036
shipped: true
shipped-date: 2026-11-04
---

## For future Claude
> R-036 folded the R-035 node contract into the LangGraph diagram page as a short 節點契約
> section with three parts:
> - 3–5 highlights;
> - a node table whose field lists open through native `<details>`;
> - one line per replacement scenario, showing field counts that also open.
>
> The separate `contract` page, the four field-finding lists and the per-node sections are
> gone. `contract.py` now rewrites `spec["contract"]` inside the diagram spec.
>
> **Headline lesson:** put an analysis on the page it explains, and lead with conclusions,
> not lists. R-035 was correct but read as a second report about a diagram the reader
> could not see. The operator: 「可以附在 langraph那篇報告裡面的下面 而且有點太複雜」.

## What Shipped
- A diagram spec gains an optional `contract` object:
  `{graph, nodes, declared, highlights (≤5), scenarios: [{title, nodes}]}`.
- `contract.py` refuses any other spec, so it cannot touch the diagram fields.
- `check.py` validates the object and runs the stale check on facts only. A failed scan is
  reported as a finding, so it no longer hides the diagram's own findings.
- `render_diagram` appends the 節點契約 section after the condition table.
  `CONTRACT_CSS` is added only to pages that carry a contract, so other pages are
  byte-identical.
- The `contract` page type and its index slot are removed. The docs and the
  CONTEXT entry (`node contract`) are updated.
- Tests: 87 in `test_draw-arch.bats`.
- The langlive-line-oa pack:
  - `contract.json` and `contract.html` are deleted;
  - `langgraph.html` now ends with 5 highlights, 25 node and router rows, and 4 one-line
    scenarios.

## Key Decisions
- **The operator's call:** fold the contract into the graph page and simplify it. My proposal
  was accepted with 「好」.
- **My calls:**
  - Highlights come first and absorb the useful field findings: hot fields, platform leaks
    and the reset node.
  - Field names sit inside `<details>`, so the page needs no script.
  - Each scenario is one line.
  - Partial reasons go in the 一句話 cell.
  - The contract CSS is added only where a contract exists.
- Door: two-way.

## What Changed From Plan
- Codex ran Tasks 1–2 in one round, DONE_WITH_CONCERNS. It made 4 deviations:
  - a scratch copy of `graph_ok.py`;
  - the spec-format example migrated early;
  - ASCII test names, per the tdd rules;
  - the SVG `xmlns` encoded through `attr()` on contract pages only. Browsers decode it, and
    the diagram still renders.
- In Task 3, screenshots led to four fixes:
  - the scenario lines listed 25 field names, so I made them collapsible counts;
  - the count and verdict columns wrapped, so I set nowrap;
  - `<details>` broke the inline flow, so I used `display:inline-block`;
  - the summary had lost its marker, so I added a dotted underline.
- Review attempt 1 found 2 important issues, both reproduced and fixed in bbe6db1:
  - the nowrap applied to whole cells, so expanded lists blew out the table;
  - an early return in check.py hid the diagram's findings.

  The attempt-2 recheck was clean.

## Bugs
- A whole-cell `white-space:nowrap` also applied to the expanded `<details>` content.
- `return [...]` from a sub-check inside a shared `check_spec` discarded the diagram's own findings.
- Chrome renders `<details>` and `<summary>` as block-level even with `display:inline`;
  `inline-block` keeps them in the line.
- A 9000 px headless window screenshotted the top of the page blank; 4200 px worked. Size the
  window to the content.

## Lessons → checks
- A sub-check inside a shared checker records its failure as a finding and keeps going; it never returns early over the caller's findings — enforced by `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats -f 'does not hide'` · proof: red at fb4fe21 (exit 1) · green at 1c4df75
- Put an analysis on the page it explains and lead with 3–5 conclusions; long lists go behind a click — judgment

## Reusable Patterns
- Native `<details>` gives progressive disclosure with no script. Use it for counts that
  open to names, and make the summary look clickable when its marker is hidden.
- Keep a renderer's feature-specific CSS off pages that don't use the feature. Byte parity
  for every other page then comes for free.

## Technical Debt
- Review nits not taken:
  - the `xmlns` encoding asymmetry between pages with and without a contract;
  - the node column is cramped when every `<details>` is open at once;
  - some tests pin CSS text;
  - the R-035 contract nits carry over (see the R-035 learning).

## Future Follow-ups
- Apply the same 「conclusions first, details behind a click」 trim to the seams and jobs
  pages if they feel long.
