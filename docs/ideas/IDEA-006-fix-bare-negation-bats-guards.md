---
date: 2026-11-04
updated: 2026-11-04
type: idea
id: IDEA-006
tags: [idea, ai_system]
ai-first: true
project: "[[ai_system]]"
status: captured
severity: minor
source: ship-next Phase 6
impact: medium
confidence: medium
target-user: ""
dependencies: []
related-roadmap-item: R-032
---

## For future Claude
> IDEA-006: 5 個 bats「不准出現」檢查寫成 `! grep` 卻不在最後一行，永遠不會失敗。
> Why this might matter, who it's for, and the evidence that supports it.

## Summary
P6 pre-existing from R-032: 5 個 bats 測試的 `! grep` 不在測試最後一行、也沒接 `|| return 1`，bats 會忽略它的結果，所以這些「不准出現」的檢查永遠不會失敗：test_roadmap-insert.bats:141、test_refactor-scan.bats:247、test_ship-land.bats:36-37、test_spec-mirror.bats:102。改成 `run ! grep …` 或 `! grep … || return 1`。(pre-existing-key: tests/*.bats:bare-negation-mid-test)

## Problem
P6 pre-existing from R-032: 5 個 bats 測試的 `! grep` 不在測試最後一行、也沒接 `|| return 1`，bats 會忽略它的結果，所以這些「不准出現」的檢查永遠不會失敗：test_roadmap-insert.bats:141、test_refactor-scan.bats:247、test_ship-land.bats:36-37、test_spec-mirror.bats:102。改成 `run ! grep …` 或 `! grep … || return 1`。(pre-existing-key: tests/*.bats:bare-negation-mid-test)

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
