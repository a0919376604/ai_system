# ai_system

我的 AI 開發環境備份：Claude Code skills、全域 `CLAUDE.md`、devsync。新 Mac clone 下來跑一行就能裝回來。

## 1. 介紹

| 部分 | 位置 | 安裝到 | 用途 |
|---|---|---|---|
| Skills | `claude-skills/` | `~/.claude/skills/` | 所有 slash command |
| 全域指示 | `CLAUDE.md` | `~/.claude/CLAUDE.md` | 每個 session 都會載入 |
| devsync | `devsync/` | `~/.local/bin/devsync` | 把 repo 即時同步到 dl01–dl04 並 SSH 進去 |

主要 skills：

- **ship-workflow**：從 Roadmap 到 merge 的開發流程，核心是 `/ship-next`，並整合 Understand-Anything 分析改動的影響範圍（見第 6 節）
- **gstack**：`/browse`、`/qa`、`/review`、`/investigate` 等 40 多個 skill（上游套件，用 `/gstack-upgrade` 升級）
- **其他**：`run-plan`（交給 codex 背景執行）、`obsidian-*`、`update-specification`、`defuddle`

## 2. Quick start

```bash
git clone git@github.com:a0919376604/ai_system.git ~/Desktop/code/ai_system
cd ~/Desktop/code/ai_system
./sync.sh restore
```

`restore` 會把 skills 和設定檔複製到本機，再跑 `devsync/bootstrap.sh` 安裝 mutagen、uv、devsync 並設定 SSH。

> 已經在用的機器請加 `--update`，否則本機比較新的檔案（例如升級過的 gstack）會被 repo 的舊版蓋掉。

**啟用 ship-workflow：**

```bash
cp ~/.claude/skills/ship-workflow/examples/ship-workflow.example.yml ~/.claude/ship-workflow.yml   # 填入 vault 路徑
git clone https://github.com/awesome-skills/code-review-skill ~/.claude/skills/code-review-skill
```

再安裝 [superpowers](https://github.com/obra/superpowers) plugin，然後在目標 repo 執行 `/ship-init`。

## 3. 使用範例

**同步 skills**

```bash
./sync.sh status     # 看差異
./sync.sh backup     # 本機 → repo（鏡像，會刪除本機已刪的檔案）
./sync.sh restore    # repo → 本機
```

**開發一個功能**

```text
/ship-idea 讓客服可以批次關閉工單     # 記下想法
/ship-roadmap                      # 重排 Roadmap
/ship-next                         # 取 Now 第一項，做到 merge
/ship-next R-012 --auto:yes        # 指定項目，全自動
/ship-next --adhoc "修 token 外洩"  # 臨時插單
/ship-next --discard R-012         # 放棄並清掉 worktree
```

**遠端開發**

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
