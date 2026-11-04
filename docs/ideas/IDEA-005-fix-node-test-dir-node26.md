---
date: 2026-11-04
updated: 2026-11-04
type: idea
id: IDEA-005
tags: [idea, ai_system]
ai-first: true
project: "[[ai_system]]"
status: captured
severity: minor
source: ship-next R-031 baseline
impact: medium
confidence: medium
target-user: ""
dependencies: []
related-roadmap-item: R-031
---

## For future Claude
> IDEA-005: <one-line summary>
> Why this might matter, who it's for, and the evidence that supports it.

## Summary
Node 26 的 node --test 不再接受目錄參數：test_repo-layout.bats 的 plugin 測試（node --test obsidian-roadmap-view/test/）與 CLAUDE.md 的指令都要改成 glob（obsidian-roadmap-view/test/*.test.js）

## Problem
Node 26 的 node --test 不再接受目錄參數：test_repo-layout.bats 的 plugin 測試（node --test obsidian-roadmap-view/test/）與 CLAUDE.md 的指令都要改成 glob（obsidian-roadmap-view/test/*.test.js）。plugin 本身 73/73 通過，只是 bats 的呼叫方式在 Node 26 下壞掉。

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
