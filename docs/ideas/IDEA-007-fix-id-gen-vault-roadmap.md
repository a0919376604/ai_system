---
date: 2026-11-04
updated: 2026-11-04
type: idea
id: IDEA-007
tags: [idea, ai_system]
ai-first: true
project: "[[ai_system]]"
status: captured
severity: minor
source: ship-next Phase 1 during R-033
impact: medium
confidence: medium
target-user: ""
dependencies: []
related-roadmap-item: R-033
---

## For future Claude
> IDEA-007: id-gen.sh 不看 vault ROADMAP 與其他 checkout 的保留，會發出重複的 R-NNN / IDEA-NNN。
> Why this might matter, who it's for, and the evidence that supports it.

## Summary
id-gen.sh roadmap 不掃 vault ROADMAP，也不看其他 checkout 的 .claude/.id-reservations：在 ai_system-wt-1 用 --adhoc 拿到的 R-032 和 main checkout 先保留的 R-032（ship-refactor-brand 那列）撞號，只好手動改成 R-033。ROADMAP 只在 vault 的 repo（沒有 docs/product/ROADMAP.md）會重複發生。同一輪 id-gen.sh idea 也回 IDEA-006，而 main 已有 IDEA-006。

## Problem
id-gen.sh roadmap 不掃 vault ROADMAP，也不看其他 checkout 的 .claude/.id-reservations：在 ai_system-wt-1 用 --adhoc 拿到的 R-032 和 main checkout 先保留的 R-032（ship-refactor-brand 那列）撞號，只好手動改成 R-033。ROADMAP 只在 vault 的 repo（沒有 docs/product/ROADMAP.md）會重複發生。同一輪 id-gen.sh idea 也回 IDEA-006，而 main 已有 IDEA-006。

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
