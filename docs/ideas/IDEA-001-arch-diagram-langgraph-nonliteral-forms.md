---
date: 2026-11-03
updated: 2026-11-03
type: idea
id: IDEA-001
tags: [idea, ai_system]
ai-first: true
project: "[[ai_system]]"
status: captured
severity: major
source: code-review-skill auto-run during R-029
impact: medium
confidence: medium
target-user: ""
dependencies: []
related-roadmap-item: R-029
---

## For future Claude
> IDEA-001: <one-line summary>
> Why this might matter, who it's for, and the evidence that supports it.

## Summary
P6 major from R-029: arch-diagram check.py LangGraph AST extraction silently skips add_node(fn), set_entry_point/set_finish_point, add_edge([a,b], c), add_sequence and non-literal first args — a correct diagram of such a graph fails with 'extra node/edge' and Claude may delete true nodes; map these forms and report anything else as unresolved (check.py:~159)

## Problem
P6 major from R-029: arch-diagram check.py LangGraph AST extraction silently skips add_node(fn), set_entry_point/set_finish_point, add_edge([a,b], c), add_sequence and non-literal first args — a correct diagram of such a graph fails with 'extra node/edge' and Claude may delete true nodes; map these forms and report anything else as unresolved (check.py:~159)

## Target User
## Evidence
<observations, support tickets, user quotes — with dates>

## Impact
<expected magnitude + reasoning>

## Confidence
<stated | high | medium | speculation — and why>

## Dependencies
<technical or organizational>

## Risks
## Possible Roadmap Item
<what an R-NNN version of this would look like>
