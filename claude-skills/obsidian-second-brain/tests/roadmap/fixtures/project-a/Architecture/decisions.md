---
type: architecture-decisions
date: 2026-05-27
lang: zh-TW
status: current
---

## 給未來 Claude
Project A 的決定索引。

## 建議升級為 ADR

1. **為什麼 Redis Cluster 而不是 PostgreSQL 主要資料層** — AGENTS.md 暗示但未詳述。
2. **事件分流標準** — 為什麼有些走 stream,有些直接寫 Redis。
3. **TanStack Query 遷移策略** — Phase 3 分批遷移的決定。

## 已知限制

- 沒有 SSO 整合 (stated: AGENTS.md)
- 後台只支援單一語言 (stated)
