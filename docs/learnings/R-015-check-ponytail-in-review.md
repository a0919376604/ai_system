---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-015
tags: [learning, ai_system, ship-next, ponytail, dependencies, review]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-015
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> Phase 6 now checks ponytail compliance two ways: the reviewer tags over-engineering
> `[ponytail:delete|stdlib|native|yagni|shrink]` (counted as PONYTAIL_COUNT, logged, never
> blocking alone), and a mechanical gate blocks a new dependency unless the spec's Decisions
> say `New dependency: <name>`. Layer 3 (`/ponytail-audit`, `/ponytail-debt`) stays manual.

## What Shipped
- `sn_new_deps` + `_sn_dep_names` (lib/ship-next.sh); gate section (d) in `sn_mech_gates`; ponytail tags in review-extra-checks; `PONYTAIL_COUNT` in code-review-parse; count in the ship log row and summary.

## Key Decisions
- Measure first: ponytail findings never block on their own (my call). Trend the count now that codex reads the ladder (R-014).
- Explicit marker for dependencies, whole-name match, several names per line (my call).

## What Changed From Plan
- Three review rounds reshaped dependency detection: diff-line matching → parsed dependency sections at merge-base vs head; then continuation lines, extras brackets, comments, dependency-groups, PEP 503 names, CRLF, non-ASCII paths, marker normalization.

## Bugs
- Matching manifests line by line cannot tell a dependency from a classifier, a script or an engine — parse the sections instead.
- A test that passes "by coincidence" (`httpx[http2]` dodged the bug a plain `httpx>=` hit): cover the most common form first.

## Reusable Patterns
- **Verify a detector on the repo's real history** before trusting it: running `sn_new_deps` over line-oa's dependency commits confirmed hits and a version-bump non-hit.

## Technical Debt
- Without jq, package.json is skipped with a WARN (fail-open).
- Ponytail compliance is still review judgement plus one mechanical rule.
