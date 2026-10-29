---
id: R-028
date: 2026-10-29
project: ai_system
---

# R-028：run-plan 全域模型設定

## What Shipped

新增 `/run-plan-model [model]` 與 `/run-plan model [model]`。Sol 對應 `gpt-6.1-sol`，Astra 對應 `gpt-6-astra`；無參數查詢，reset 回復 Codex 設定。設定跨專案共用，只影響之後啟動的 run-plan。

## Key Decisions

- 設定存於 `${XDG_CONFIG_HOME:-$HOME/.config}/run-plan/model`，不修改 Codex config.toml、外層對話模型或 reasoning effort。
- 啟動時讀取快照，以獨立 argv 傳入 `--model`；metadata 記錄啟動當下設定。
- 新 slash skill 放在 run-plan 之下，由 sync.sh 安裝 Claude 與跨 runtime 連結，不新增頂層目錄。加入 Discord visibility 與可選參數，供 bot 重新載入指令時探索。

## What Changed From Plan

本機落地與安裝；沒有推送遠端或重啟 Discord bot。

## Bugs

完整套件指出新增 Bats 的兩個 `[[ ]]` 斷言缺少明確失敗返回，已修正並重跑 hygiene 與相關 27 項測試。

## Lessons → checks

- 設定成功不代表啟動使用它：測試擷取實際 launch 區塊，以替代 Codex 程序驗證 argv、stdin 與 metadata。
- 安裝成功不代表 Discord 可發現：skill 必須包含 `discord-visible: true` 與 argument hint。

## Reusable Patterns

專用執行器的偏好使用獨立設定檔；原子寫入、啟動快照與 argv 傳遞，避免修改外層設定及 shell 注入。

## Technical Debt

套件原有 cwd-guard 與四頂層目錄檢查失敗：前者為 repo 已記錄的 worktree 問題，後者因 baseline 已有 weekly-report。未修改這些不相關測試。

## Future Follow-ups

模型帳號可用性由實際啟動時的 Codex 判定；設定驗證不呼叫付費推論。
