---
date: {{date}}
updated: {{date}}
type: roadmap-note
id: {{id}}
parent: {{parent}}
tags: [roadmap-note, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-row: {{id}}
proposal-ref: {{proposal_ref}}
status: live
---

## For future Claude
> {{id}} 的入門口袋書 — plain language 解釋這步在做什麼、為什麼做、用到的
> domain 名詞代表什麼。讀者:domain 不熟的 product owner / 新加入的工程師。
> Voice 規則:**不要直接抄 proposal 句子**。Rewrite into plain Chinese。第一次
> 出現的 domain 名詞 inline 定義(例:「SceneEngine(規則層,決定下一個 scene
> 演什麼)」)。避免「整合」「重構」這種抽象動詞,優先具象描述。

## 一句話總結
> {{one_liner}}

## 這步在做什麼
{{plain_what}}

## 為什麼要做這步
- **在 epic 的角色**:{{role_in_epic}}
- **沒做會怎樣**:{{cost_if_skipped}}
- **做完後玩家/系統會感覺到什麼**:{{user_visible_change}}

## 前後關係
- **依賴 (blocked-by)**: {{blocked_by}}
- **解鎖 (unblocks)**: {{unblocks}}
- **同 epic 兄弟**: {{siblings}}

## 用到的 domain 名詞
| 詞 | 是什麼 | 完整定義 |
|---|---|---|
{{glossary_rows}}

## 深入閱讀
{{deeper_reading_links}}
