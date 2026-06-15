---
type: roadmap-proposal
roadmap-id: "R-006"
date: 2026-06-15
updated: 2026-06-15
project: "[[ai-eden-service]]"
audience: self+team
status: draft
sources:
  - "[[Architecture/modules/app-services]]"
  - "[[Architecture/decisions]] L-004"
related-architecture:
  - "[[Architecture/modules/app-services]]"
related-roadmap: [R-001]
confidence: medium
lang: zh-TW
tags: [proposal, "R-006", memory-consolidate, example]
ai-first: true
---

> **Example proposal — Lite size.** Shows the shape of a Lite proposal (single-module,
> effort=M, confidence=medium). Sections §2 / §6 / §7 truncated relative to Full.

## 給未來 Claude (我自己 3 個月後)
> R-006 把「每次 cadence 整本 rewrite LTM」改成「section-diff incremental」。理由是
> token cost 隨 LTM 線性增長,接近 `memory_ltm_char_cap` 時 LLM 會在邊緣切字。

## §1 目標

- **一句話:** LTM consolidate 改 section-by-section incremental,不再整本 rewrite。
- **為什麼是現在:** `memory_ltm_char_cap` 已接近上限的對話案例正在增加(見 [[Architecture/decisions]] L-004)。
- **怎樣算成功:**
  - 平均 consolidate token 成本下降 ≥ 50%
  - 接近 cap 的對話不再出現「LLM 切字」現象
  - retrieval 品質不下降 (eval golden set 不退步)

## §2 現狀 (簡述)
- [[Architecture/modules/app-services]] `memory.py:104-142` 每次整本 rewrite
- Known limitation L-004 已記錄
- N-cycle full rewrite checkpoint 是必要 escape hatch

## §3 提案

```
LTM markdown 結構化成 sections (## 個人 / ## 關係 / ## 共同回憶 / ## 開放問題)。
每次 cadence:
  1. 抓最近 N turn → diff 出新事實
  2. 用 LLM 決定該 fact 屬於哪個 section(便宜 model 即可)
  3. 只 rewrite 該 section,其他 section 不動
  4. 每 K 次 cadence 做一次 full-rewrite checkpoint(防 drift)
```

## §3.x Self-FAQ

### Q1: 為什麼不直接調 `memory_ltm_char_cap` 變大就好?
**答:** cap 變大 = consolidate prompt 變大 = token cost 同比例增加,且 LLM 在大 cap 上 reasoning 品質下降。Section diff 是讓「個別 section 小」而非「總 LTM 大」。

### Q2: section drift 怎麼防?
**答:** 每 K=10 次 cadence 做一次 full rewrite checkpoint。也加 lint 規則「同一 fact 不應出現在兩個 section」。

### Q3: 跟 mem0 backend 衝突嗎?
**答:** 不衝突。mem0 是 fact-level (per fact row);blob LTM 是 narrative summary。本 proposal 只動 blob LTM 路徑。

## §4 取捨

| 選項 | 為什麼不選 |
|---|---|
| A · 維持整本 rewrite,只調 cap | token cost / 品質權衡無解(見 Q1) |
| B · 切完整 vector-LTM | 整個 retrieval pipeline 重寫,太大 |
| **C · Section diff (本提案)** | 漸進改良,可 ab-test,fallback 路徑明確 |

## §5 高層實作

| Phase | 內容 | 時程 | Kill switch |
|---|---|---|---|
| 1 | LTM markdown sections + writer | 3 天 | `EDEN_LTM_SECTIONED=false` |
| 2 | Section-diff consolidator(便宜 LLM 分類) | 4 天 | 同上 |
| 3 | Full-rewrite checkpoint cadence + migration | 3 天 | 同上 |

**總計:** 10 天。

## §6 觀測

- consolidate token cost per cadence (avg / p95)
- LTM size at cap rate
- Retrieval quality (golden set BLEU / recall)

## §7 開放問題
- Section schema 是 hard-coded 還是 per-character override?
- Old-LTM migration:lazy(下次 consolidate 自動切)還是 batch script?

## §8 Cross-links
- ↑ Roadmap: [[ROADMAP]] §R-006
- ← [[Architecture/decisions]] L-004 (Known limitation)
- ⇆ 相關 R-NNN: R-001 (4 層敘事可能會增加 episodic memory 需求,跟 LTM 互動)
