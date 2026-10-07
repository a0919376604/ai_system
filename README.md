# ai_system

讓 AI 把一個功能從「一句話的需求」一路做到「merge 進主程式」的開發工作流。

## 1. 介紹

**這套在做什麼**

你只要說一句「幫我把 XXX 加到 Roadmap」，再下 `/ship-next`，AI 就會像一個守規矩的工程師，把這個功能從頭做完：

1. **先想清楚**：跟你確認需求，寫下設計
2. **再排計畫**：把工作拆成一個個小任務
3. **動手做**：逐一實作，一邊寫測試
4. **自己把關**：做完先 code review，有嚴重問題就自己修，沒修好不會 merge
5. **收尾**：merge 回主程式、更新 Roadmap、記下這次學到的事

整個過程都在獨立的工作區裡進行，做壞了也不會影響主程式。

**你負責什麼**

只有兩件事：**決定要做什麼**，以及**說清楚怎樣算做完**。其他的交給 AI。想看過程，可以每一步都確認；不想看，可以讓它整晚自己跑。

**經驗會累積**

每做完一個功能，踩過的坑、專案用語、測試規則都會被記下來，下一個功能開始前先讀。同樣的錯不會一直犯。

**附帶的功能**

- **一行裝回整套環境**：換新電腦時，所有 AI 工具和設定一次還原。
- **遠端開發**：在公司的 GPU server 上跑程式時，本機寫的 code 會即時同步過去。

## 2. Quick start

```bash
git clone git@github.com:a0919376604/ai_system.git ~/Desktop/code/ai_system
cd ~/Desktop/code/ai_system
./sync.sh restore
```

`restore` 會裝好這些東西：

| repo 內 | 安裝到 | 內容 |
|---|---|---|
| `claude-skills/` | `~/.claude/skills/` | ship-workflow、gstack（`/browse`、`/qa`、`/review` 等 40 多個）、`run-plan`、Obsidian 工具 |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 每個 session 都會載入的全域規則 |
| `devsync/` | `~/.local/bin/devsync` | 同步到 dl01–dl04 的 CLI，連同 mutagen、uv、SSH 設定 |

> 已經在用的機器請加 `--update`，否則本機比較新的檔案（例如升級過的 gstack）會被 repo 的舊版蓋掉。

**啟用 ship-workflow：**

```bash
cp ~/.claude/skills/ship-workflow/examples/ship-workflow.example.yml ~/.claude/ship-workflow.yml   # 填入 vault 路徑
git clone https://github.com/awesome-skills/code-review-skill ~/.claude/skills/code-review-skill
```

再安裝 [superpowers](https://github.com/obra/superpowers) plugin，然後在目標 repo 執行 `/ship-init`。

## 3. 使用範例

### 同步 skills

```bash
./sync.sh status     # 看差異
./sync.sh backup     # 本機 → repo（鏡像，會刪除本機已刪的檔案）
./sync.sh restore    # repo → 本機
```

### 用 Roadmap 開發功能

**R-xxx 是什麼**

Roadmap 上每個要做的項目都有一個編號 `R-NNN`（例如 `R-012`），從目前最大的號碼往上加。太大的項目會拆成 `R-012.1`、`R-012.2` 這樣的子項目，原本的 `R-012` 變成 epic，`/ship-next` 自動挑選時會跳過它。

這個編號會貫穿整個流程：worktree、branch、spec、plan、learning 都用它命名，事後從任何一個檔案都能追回同一個項目。另外還有兩種編號：`IDEA-NNN` 是還沒排進 Roadmap 的想法（多半是 review 時延後處理的問題），`D-NNN` 是架構決策。

**Roadmap 長什麼樣**

`ROADMAP.md` 的正本放在 Obsidian vault 的 `10 Projects/<repo>/`，repo 裡的 `docs/product/ROADMAP.md` 是自動同步的副本。內容分成四區：

| 區塊 | 意思 |
|---|---|
| 🔥 Now | 正在做的 3–5 項，`/ship-next` 從這裡挑 |
| 🔜 Next | 已經想清楚，隨時可以開始 |
| 🕐 Later | 有價值但還沒排程 |
| ✅ Done | 做完的項目，保留當歷史 |

一列的寫法如下。描述用動詞開頭，`↳ done when:` 寫一個看得到的完成條件：

```markdown
- [ ] **R-012** 讓客服可以批次關閉工單 · est=3d
    ↳ explain: [[Roadmap-Notes/R-012-bulk-close-tickets]]
    ↳ done when: 一次選 50 張工單關閉，全部狀態更新並寫入 audit log
```

**怎麼提一個項目**

直接用一句話跟 Claude 說就好：

```text
幫我把「客服可以批次關閉工單」加到 Roadmap
```

Claude 會配一個新的 R-NNN 並寫進 Roadmap。順便說清楚怎樣算做完（例如「一次關 50 張都要成功」），它會一起寫成 `↳ done when:`，之後才能用 `--auto:yes` 全自動跑。

要馬上開始做的臨時需求，用 `/ship-next --adhoc "<描述>"`：配好編號放進 Now 之後，直接進入開發。

**開發機制**

```
「幫我把 XXX 加到 Roadmap」
  │ 配一個新的 R-NNN
  ▼
Later → Next → Now     ← /ship-roadmap 排序；太大的標 ⚠️ 並建議拆成子項目
  │ （選用）/ship-explain 寫白話說明、/ship-propose 寫提案
  ▼
/ship-next R-NNN       ← brainstorm → spec → plan → 實作 → review → merge
  │
  ▼
✅ Done                ← review 延後處理的問題變成 IDEA，下次 /ship-roadmap 會建議排進來
```

`/ship-roadmap` 每次都會重新讀策略文件、還沒擱置的 IDEA、已接受的決策和最近 30 天的 learning，依「影響 × 相依性」重新排序。Now 最多放 5 項，缺少 `↳ done when:` 的項目會被特別標出來。

**實際操作**

```text
幫我把「客服批次關閉工單」加到 Roadmap  # 配好 R-NNN
/ship-roadmap                           # 重新排序
/ship-next                              # 取 Now 第一項，做到 merge
/ship-next R-012 --auto:yes             # 指定項目，全自動
/ship-next --adhoc "修 token 外洩"      # 臨時插單
/ship-next --discard R-012              # 放棄並清掉 worktree
```

**走完一套流程後**

- 主 branch 上多一個 squash commit，訊息裡有 done-when、task 清單和 review 結果。
- `docs/` 下多一組文件：brainstorm、spec、plan、learning。
- Roadmap 那一列移到 ✅ Done 並標上日期（`mr` 模式先標成 `in-review`）。
- `CONTEXT.md` 補上這次新出現的專案用語；可重用的 pattern 會問你要不要推升到 vault。
- review 時延後處理的 major 問題變成新的 IDEA-NNN（auto 模式全部都會開）。
- worktree 和 branch 都已刪除（`mr` 模式會保留到 `/ship-land`），可以直接接下一個 `/ship-next`。

**Roadmap 機制的好處和缺點**

| 好處 | 缺點 |
|---|---|
| 一個編號追到底：從想法、spec、commit 到 learning 都能用 R-NNN 串起來 | 很吃紀律：描述和 done-when 寫得越模糊，brainstorm 和全自動模式就越容易做偏 |
| 「做完」有明確定義：done-when 讓你和 AI 用同一個標準驗收，全自動模式也有依據 | 排序品質看 `ce-strategy`：沒裝 compound-engineering 時改由 Claude 在對話中排序，結果比較不穩定 |
| 項目會被逼著變小：太大的會被標 ⚠️，拆出來的每個子項目都必須能驗收 | IDEA 會越積越多：review 自動開的 IDEA 需要定期整理，或標成 `shelved` 擱置 |
| 問題不會被遺忘：延後處理的 review 問題會變成 IDEA，下次排 Roadmap 時再被看到 | 編號在本機分配：兩台機器在 Roadmap 同步之前各自開新項目，可能拿到同一個號碼 |

### 遠端開發

```bash
devsync start dl02     # 同步目前目錄到 dl02 並 SSH 進去
devsync ls             # 列出 session
devsync stop my-repo   # 結束
```

## 4. 好處與缺點

**好處**

- **主 branch 很安全**：每個項目都在獨立的 worktree 裡做，merge 前不會動到主 branch。中斷了可以接續，做壞了一行指令就能丟掉。
- **Review 是硬門檻**：blocking 沒歸零就不能 merge。除了 LLM review，還會機械檢查純重構有沒有偷加測試、測試量有沒有超過 repo 自己的基準。
- **經驗會累積**：過去的 learning 會在下次 brainstorm 時被讀回來，專案用語（`CONTEXT.md`）和測試規則（`docs/tdd-rules.md`）也會隨著每個 repo 一起成長。
- **可以無人值守**：`--auto:yes` 可以整晚自己跑，每個自動做的決定都有紀錄，失敗時保留現場並通知你。
- **每一步都留紀錄**：每個項目都有 brainstorm、spec、plan、learning，事後查得到當初為什麼這樣做。
- **看得到影響範圍**：搭配 Understand-Anything，review 時知道這次改動會波及哪些模組。

**缺點**

- **小改動也要走全套**：一行修正一樣會經過 brainstorm、spec、plan、review，花的時間和 token 都多。
- **依賴多**：Obsidian vault、superpowers、code-review-skill 少一個就跑不起來。
- **綁我的環境**：只支援 macOS，範例設定寫死我的路徑，devsync 也只連內部的 dl01–dl04。
- **流程由模型執行**：helper script 有 bats 測試，但指令本身是給 Claude 讀的 markdown，每一步有沒有照做，取決於模型。
- **全自動的品質看 Roadmap 寫得多清楚**：`--auto:yes` 遇到問題一律選建議選項，沒有寫 `↳ explain:` 或提案時，做出來的可能和你想的不一樣。
- **策略只能在 Obsidian 改**：同步是單向的，直接在 repo 改 ROADMAP 會被擋下來。
- **Knowledge graph 很貴**：大型 repo 第一次跑 `/understand` 會消耗大量 token。

## 5. 需求

**必要**：macOS + Homebrew、Claude Code、Obsidian vault、[superpowers](https://github.com/obra/superpowers)、[code-review-skill](https://github.com/awesome-skills/code-review-skill)、bun（gstack 用）、dl01–dl04 的 SSH 帳號（devsync 用）

**選用**：

| 項目 | 用途 |
|---|---|
| compound-engineering（`ce-*`） | `/ship-roadmap`、`/ship-compound` 的自動化 |
| [understand-anything](https://github.com/Lum1104/Understand-Anything) | 影響範圍分析、knowledge graph 自動重建（見第 6 節） |
| [ponytail](https://github.com/DietrichGebert/ponytail) | executor 的寫碼規則 |
| codex CLI | 第 3 種 executor |
| `gh` / `glab` | `merge_mode: mr` 開 PR/MR |

測試：`bats claude-skills/ship-workflow/tests/`

## 6. `/ship-next`

在獨立 worktree（`<repo>-worktrees/R-NNN-<slug>`，branch `ship/R-NNN-<slug>`）裡把一個 Roadmap 項目從 brainstorm 做到 merge，merge 前不會動到主 repo。

| Phase | 做什麼 |
|---|---|
| 1 | 同步 vault、選定 R-NNN |
| 2 | 開 worktree |
| 3 | 讀過去的 learning 和 `CONTEXT.md`，brainstorm 出 spec（必須有 `## Seams`） |
| 4 | 寫 plan |
| 5 | 執行 plan |
| 6 | Code review，blocking 必須歸零，最多修 3 輪 |
| 7 | Squash merge，或開 PR/MR |
| 8 | 寫 learning、Roadmap 移到 Done |
| 9 | 刪除 worktree 和 branch |

**Executor（Phase 5）**：1. subagent 逐 task 執行（推薦）　2. 在目前 session 依序執行　3. 交給 codex 背景跑，卡住時自動判斷要修 plan 重跑，還是停下來通知你

**Review（Phase 6）**：除了 LLM review，還會擋兩件事：純重構的 task 新增了測試，以及測試行數比例超過 repo 基準的 4 倍。

**`--auto:yes`**：全程不問問題，適合丟著跑一整晚。項目必須有 `↳ done when:`；問題一律選建議選項；major finding 自動開成 IDEA；3 輪還過不了就中止並保留 worktree。

**`merge_mode: mr`**（寫在 `.claude/ship-config.yml`）：不直接 merge，改成開 PR/MR，review 合併後執行 `/ship-land R-NNN` 收尾。

**中斷**：重跑 `/ship-next R-NNN` 會從上次的階段接續。

**Understand-Anything 整合**：repo 有 `.ua/knowledge-graph.json` 時自動啟用，沒有就安靜跳過。

| 時機 | 做什麼 |
|---|---|
| `/ship-init --with-ua` | 提示你對 repo 跑 `/understand`，建立 knowledge graph |
| `/ship-roadmap` | 用 graph 輔助排序，並判斷項目是否太大（橫跨 3 個以上模組） |
| Phase 1.5 | graph 比 HEAD 舊時發出警告 |
| Phase 6 | 用 `/understand-diff` 產出影響範圍報告（受影響的模組、層級、風險評估），再比對 vault 的 `REMINDERS.md`，一起交給 reviewer |
| Phase 8 | `/ship-compound` 用影響範圍草擬一份 case 筆記，並問你要不要新增 REMINDERS 規則 |
| Phase 8.7 | graph 落後超過 50 個檔案時，自動重跑 `/understand` |

完整定義見 [`ship-next.md`](claude-skills/ship-workflow/commands/ship-next.md)，設計文件在 [`docs/superpowers/specs/`](docs/superpowers/specs/)。
