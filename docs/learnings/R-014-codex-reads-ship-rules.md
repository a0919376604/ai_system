---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-014
tags: [learning, ai_system, run-plan, codex, ponytail]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-014
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> codex never has the ponytail plugin; it gets the ladder as `.ship/ponytail-rules.md`, rendered by
> ship-next Phase 5. Since R-014 the run-plan prompt header tells codex to read that file and
> `.ship/tdd-rules.md` before the first task, whatever the plan says.

## What Shipped
- One conditional instruction in run-plan Step 2's prompt header; a test that runs the block.

## Key Decisions
- Conditional ("if they exist") so /run-plan still works outside ship-next (my call).

## Bugs
- Rules rendered for an executor were only as reliable as the plan text that pointed at them.

## Reusable Patterns
- **Put "read these inputs" in the executor's fixed prompt, not in each generated plan.** Generated text varies; the header does not.

## Technical Debt
- Still advisory: no review step checks ponytail compliance.
