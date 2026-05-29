---
type: architecture-future
date: 2026-05-27
lang: zh-TW
confidence: speculation
status: current
---

## 給未來 Claude
Project A 的 gap 分析。

## 已知限制

- 沒有 SSO 整合 (stated: AGENTS.md)
- 後台只支援單一語言 (stated)

## 落差分析

- README 提到 streaming API,但 api-surface 沒對應 endpoint
- README 提到 plugin system,但 exports 中找不到 plugin_register

## 期望中的想法

- 把 AI 引擎抽象成 pluggable adapter (inferred from AGENTS.md)
- 加 webhook signature verification (suggested)
