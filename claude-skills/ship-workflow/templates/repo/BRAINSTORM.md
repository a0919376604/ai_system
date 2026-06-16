---
date: {{date}}
updated: {{date}}
type: brainstorm
id: {{id}}
tags: [brainstorm, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-item: {{id}}
spec-path: docs/specs/{{id}}-{{slug}}.md
plan-path: docs/plans/{{id}}-{{slug}}.md
parent: null   # if this is a child of an epic R-NNN, set to that R-NNN
# --- Outcome contract (mirror of ROADMAP entry) -----------------------------
# success-criteria: copied verbatim from the ROADMAP "↳ done when:" annotation.
#   If the ROADMAP entry has no done-when, define one HERE before brainstorming
#   the approach — you can't pick between approaches without an outcome to score
#   them against. Re-sync this string back to ROADMAP after the spec lands.
success-criteria: "<one observable line — CI green, metric threshold, or user-visible behavior>"
# estimated-effort: rough size. d = days, w = weeks. If > 1w, the item is
#   probably still too big and should be decomposed (see /ship-roadmap step 6).
estimated-effort: "<Nd | Nw>"
---

## For future Claude
> {{id}}: brainstorm session for <topic>.
> Captures the design exploration before formal spec.
> **Success criterion (from ROADMAP):** {{success_criteria}}
> Every approach below must be scored against that criterion. If an approach
> can't be evaluated against it, either the approach is too vague or the
> criterion is too vague — refine before continuing.

## Problem Framing
## Approaches Considered
## Selected Approach + Why
## Open Questions Carried Into Spec
