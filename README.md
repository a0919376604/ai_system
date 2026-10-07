# ai_system

我的 AI 開發工作流，集中放在一個 repo：Claude Code 的 skills、全域 `CLAUDE.md`，以及連到內部 dev server 的同步工具 devsync。換新 Mac 時，clone 下來跑一行指令就能裝回整套環境。

- [1. 介紹](#1-介紹)
- [2. Quick start](#2-quick-start)
- [3. 使用範例](#3-使用範例)
- [4. 需求](#4-需求)
- [5. `/ship-next` 詳解](#5-ship-next-詳解)

---

## 1. 介紹

這個 repo 有三個部分，由根目錄的 `sync.sh` 負責搬到本機對應的位置：

| 部分 | repo 內位置 | 安裝到 | 用途 |
|---|---|---|---|
| Claude Code skills | `claude-skills/` | `~/.claude/skills/` | 所有 slash command 和 skill |
| 全域指示 | `CLAUDE.md` | `~/.claude/CLAUDE.md` | 每個 Claude Code session 都會載入的規則 |
| devsync | `devsync/` | `~/.local/bin/devsync`、`~/.config/devsync/config.toml` | 用 Mutagen 把本機 repo 單向即時同步到 dl01–dl04，並直接 SSH 進去 |

`sync.sh` 是雙向的：`backup` 把本機的 skills 收回 repo，`restore` 把 repo 的內容裝到本機。

### 裡面有哪些 skills

**開發流程**

- **`ship-workflow`**：從 Roadmap 一路走到 merge 的產品開發流程，提供 10 個 `/ship-*` 指令。核心是 `/ship-next`，見[第 5 節](#5-ship-next-詳解)。
- **`run-plan`**：把寫好的實作計畫交給 `codex exec` 在背景跑完。`/ship-next` 的第 3 種 executor 用的就是它。
- **`update-specification`**：用 `REQ-NNN` / `AC-NNN` 等編號格式改寫專案的 `spec/` 文件。

**gstack（v1.26.2.0，上游套件原樣備份）**

`gstack/` 本體，加上它展開的 40 多個 skill，例如 `/browse`、`/qa`、`/review`、`/ship`、`/investigate`、`/office-hours`、`/plan-eng-review`、`/design-review`、`/codex`、`/careful`。要升級請用 `/gstack-upgrade`，不要手改。

**Obsidian 與網頁工具**

- `obsidian-second-brain`：把 Obsidian vault 當第二大腦操作，`/ship-research` 會用到。
- `obsidian-cli`、`obsidian-markdown`、`obsidian-bases`、`json-canvas`：讀寫 vault 的各種格式。
- `defuddle`：把網頁轉成乾淨的 markdown。

### 目錄結構

```
ai_system/
├── sync.sh                  # backup / restore / status
├── CLAUDE.md                # → ~/.claude/CLAUDE.md
├── claude-skills/           # → ~/.claude/skills/
│   ├── ship-workflow/
│   │   ├── commands/        # 10 個 /ship-* 指令（/ship-init 會複製到目標 repo）
│   │   ├── lib/             # 指令呼叫的 shell helper，每支都有 bats 測試
│   │   ├── templates/       # repo 端與 Obsidian 端的文件範本
│   │   ├── references/      # 流程圖、escape hatch、ce-* 對照表
│   │   └── tests/           # bats
│   ├── gstack/ …
│   └── …
├── devsync/
│   ├── bootstrap.sh         # 7 步驟安裝器（restore 最後會自動執行）
│   ├── config.toml          # → ~/.config/devsync/config.toml
│   └── src/                 # devsync CLI 原始碼（Python）
└── docs/superpowers/        # 各功能的設計 spec 與實作 plan
```

---

## 2. Quick start

### 新 Mac 第一次安裝

```bash
git clone git@github.com:a0919376604/ai_system.git ~/Desktop/code/ai_system
cd ~/Desktop/code/ai_system
./sync.sh restore --dry-run   # 先看會寫入哪些檔案
./sync.sh restore             # 確認 [y/N] 後開始安裝
```

`restore` 依序做這幾件事：

1. 把 `claude-skills/` 複製到 `~/.claude/skills/`。不會刪除本機多出來的檔案，也會保留 `node_modules/`、`bin/`。
2. 覆蓋 `~/.claude/CLAUDE.md` 和 `~/.config/devsync/config.toml`。
3. 如果 gstack 還沒有 `node_modules`，問你要不要裝依賴。
4. 執行 `devsync/bootstrap.sh`：安裝 mutagen 和 uv、安裝 devsync CLI、產生 SSH key、寫入 `~/.ssh/config`，再對 dl01–dl04 各跑一次 `ssh-copy-id`（每台輸入一次密碼）。

`bootstrap.sh` 可以重複執行，已完成的步驟會直接跳過。加 `--yes` 可以略過密碼以外的所有確認。

> **已經在用的機器要注意**：rsync 預設會用 repo 的版本覆蓋本機檔案，即使本機的比較新。如果你在這台機器升級過 gstack，或改過 skill 卻還沒 `backup`，請改用：
>
> ```bash
> ./sync.sh restore --update   # 本機比較新的檔案會保留
> ```

### 啟用 ship-workflow

1. 建立全域設定，填入 Obsidian vault 路徑（`airos_vault`）和放程式碼的根目錄（`code_root`）：

   ```bash
   cp ~/.claude/skills/ship-workflow/examples/ship-workflow.example.yml ~/.claude/ship-workflow.yml
   ```

2. 安裝 `/ship-next` Phase 6 必需的 code review skill：

   ```bash
   git clone https://github.com/awesome-skills/code-review-skill ~/.claude/skills/code-review-skill
   ```

3. 在 Claude Code 安裝 [superpowers](https://github.com/obra/superpowers) plugin。brainstorm、寫 plan、建立 worktree、執行 plan 都靠它。
4. 進到要用的 repo，在 Claude Code 裡執行 `/ship-init`。

---

## 3. 使用範例

### 在兩台機器之間同步 skills

```bash
# A 機：改了 skill 之後
cd ~/Desktop/code/ai_system
./sync.sh status              # 看本機和 repo 差在哪
./sync.sh backup              # ~/.claude/skills → claude-skills/
git add -A && git commit -m "sync skills" && git push

# B 機
cd ~/Desktop/code/ai_system
git pull && ./sync.sh restore
```

`backup` 是鏡像（`rsync --delete`）：本機刪掉的 skill，repo 裡也會跟著刪。symlink 會展開成實體檔案，所以 repo 搬到別台機器也能用。

### 用 ship-workflow 做一個功能

在目標 repo 的 Claude Code 裡：

```text
/ship-init                          # 每個 repo 只需一次：建 docs/ 資料夾、複製指令、建 Obsidian 策略檔
/ship-idea 讓客服可以批次關閉工單      # 記下想法 → docs/ideas/IDEA-NNN-*.md
/ship-roadmap                       # 重排 ROADMAP 的 Now / Next / Later
/ship-next                          # 取 Now 的第一項，從 brainstorm 一路做到 merge
```

`/ship-next` 常用的變化：

```text
/ship-next R-012                    # 指定要做哪一項
/ship-next R-012 --auto:yes         # 全自動，過程不問任何問題（該項必須有 ↳ done when:）
/ship-next --adhoc "修 token 外洩"   # 臨時插單：配一個新的 R-NNN 放進 Now，接著直接做
/ship-next --resume R-012           # 接續上次中斷的 worktree
/ship-next --discard R-012          # 放棄：刪除 worktree、branch 和 vault 裡的 spec 副本
/ship-land R-012                    # merge_mode: mr 時，等 review 合併後收尾
```

其他指令：

| 指令 | 用途 |
|---|---|
| `/ship-decision <主題>` | 記錄架構決策 → `docs/decisions/D-NNN-*.md` |
| `/ship-propose [R-NNN]` | brainstorm 之前，先為 Roadmap 項目寫一份提案 |
| `/ship-research <主題>` | 先查 vault 再做深度研究，結果存回 Obsidian |
| `/ship-explain [R-NNN]` | 用白話解釋某個 Roadmap 項目到底要做什麼 |
| `/ship-compound` | 寫 learning、把 pattern 推升到 vault、把項目移到 Done（`/ship-next` 會在 Phase 8 自動呼叫） |

`/ship-roadmap`、`/ship-init`、`/ship-propose` 會改到主 branch 的共用狀態，所以在 `ship/*` worktree 裡會拒絕執行。

### 用 devsync 在遠端 server 上開發

```bash
cd ~/Desktop/code/my-repo
devsync start dl02            # 開始把目前目錄同步到 dl02，並 SSH 進去
devsync start dl02 --no-ssh   # 只同步，不 SSH
devsync ls                    # 列出所有同步中的 session
devsync ssh my-repo           # 重新 SSH 進已存在的 session
devsync flush my-repo         # 立刻強制同步一次
devsync stop my-repo          # 結束一個 session（--all 結束全部）
devsync doctor                # 檢查 daemon 和 4 台 server 是否都連得到
```

repo 裡放 `.devsync.toml` 並設定 `default_server = "dl02"`，就可以省略 server 參數。更多細節（含 NAS 權限問題）見 [`devsync/README.md`](devsync/README.md)。

---

## 4. 需求

### 必要

| 項目 | 用在哪 |
|---|---|
| macOS + Homebrew | `bootstrap.sh` 用 brew 裝套件；`/ship-next` 用 `osascript` 發桌面通知 |
| Claude Code | 所有 skill |
| git、rsync、bash | `sync.sh` 與 ship-workflow 的 helper |
| Obsidian vault | ship-workflow 的 Vision / Strategy / Roadmap 都放在 vault 裡，路徑設在 `~/.claude/ship-workflow.yml` |
| [superpowers](https://github.com/obra/superpowers) plugin | `/ship-next` 的 worktree、brainstorm、writing-plans、executor |
| [code-review-skill](https://github.com/awesome-skills/code-review-skill) | `/ship-next` Phase 6 的 review gate，沒裝會在 Phase 6 停下並提示安裝 |
| bun ≥ 1.0 | gstack |
| Python ≥ 3.11、uv、mutagen | devsync（uv 和 mutagen 由 `bootstrap.sh` 自動安裝） |
| dl01–dl04 的 SSH 帳號 | devsync |

### 選用（沒有也能跑，功能會降級）

| 項目 | 有裝時多了什麼 |
|---|---|
| compound-engineering plugin（`ce-*`） | `/ship-roadmap` 排序、`/ship-compound` 寫 learning 會交給它；沒裝就改在對話中手動完成 |
| [understand-anything](https://github.com/Lum1104/Understand-Anything) plugin | `/ship-next` 會讀 `.ua/knowledge-graph.json`，在 brainstorm、review、收尾時提供影響範圍分析 |
| [ponytail](https://github.com/DietrichGebert/ponytail) plugin | Phase 5 會把它的規則交給 executor；沒裝時會明確印出「沒有套用」 |
| codex CLI | `/ship-next` 第 3 種 executor（`/run-plan`） |
| `gh` 或 `glab` | `merge_mode: mr`，用來開 GitHub PR 或 GitLab MR |
| bats | 跑 ship-workflow 的測試 |

### 跑測試

```bash
bats claude-skills/ship-workflow/tests/              # ship-workflow
cd devsync/src && uv run --extra dev pytest          # devsync
```

---

## 5. `/ship-next` 詳解

`/ship-next` 把 ROADMAP「🔥 Now」裡的一個項目，從 brainstorm 一路做到 merge 回原本的 branch。所有工作都在一個獨立的 git worktree 裡進行，merge 之前主 repo 完全不會被動到。

| | 命名規則 |
|---|---|
| worktree | `<repo 的上層目錄>/<repo>-worktrees/R-NNN-<slug>` |
| branch | `ship/R-NNN-<slug>` |
| slug | 從 Roadmap 描述取 3–5 個英文字，kebab-case，盡量以動詞開頭（例：`wire-scene-engine`） |

### 開始之前

- 在**主 repo 的根目錄**執行，不要在 worktree 裡。
- 這個 repo 已經跑過 `/ship-init`。
- Roadmap 項目建議寫成這樣。`↳ done when:` 定義「做完」是什麼樣子，`--auto:yes` 模式下是必填：

  ```markdown
  - [ ] **R-012** 讓客服可以批次關閉工單
      ↳ explain: [[r-012-bulk-close-tickets]]
      ↳ done when: 一次選 50 張工單關閉，全部狀態更新並寫入 audit log
  ```

沒有指定 R-NNN 時，會從「Now」挑排名第一的項目：跳過 epic，子項目依 `.M` 由小到大，再以 impact 和相依性決定先後。

### 九個階段

| Phase | 做什麼 | 產出 / commit |
|---|---|---|
| **1 Pre-flight** | 解析參數；把 vault 的策略檔同步到 repo；決定 R-NNN；`--auto:yes` 時檢查 `↳ done when:`；計算 worktree 路徑，已存在就問要不要接續 | — |
| **1.5 UA drift** | knowledge graph 落後 HEAD 時印警告，不會擋 | — |
| **2 開 worktree** | 用 `superpowers:using-git-worktrees` 從目前 branch 開出 worktree，並 cd 進去 | — |
| **3 Brainstorm** | 先讀背景資料：UA 影響範圍、`CONTEXT.md` 的專案用語、slug 命中的過去 learning（≤ 3 篇全讀，太多只列檔名）、已 accepted 的提案。接著跑 `superpowers:brainstorming`，spec **必須**有 `## Seams` 表，宣告這次新增或改動的邊界。spec 另存一份到 vault 的 `Specs/` | `docs/brainstorms/`、`docs/specs/` → `brainstorm+spec: R-NNN <slug>` |
| **4 Plan** | Seam 檢查（沒有 `## Seams`：互動模式警告，auto 模式拒絕），再用 `superpowers:writing-plans` 寫 plan | `docs/plans/` → `plan: R-NNN <slug>` |
| **5 執行** | 選 executor（見下方），把 TDD 規則和 ponytail 規則寫到 `.ship/`，交給 executor 照 plan 逐 task 實作 | 每個 task 至少一個 commit |
| **6 Review** | 先跑機械檢查，再用 code-review-skill review `git diff <原 branch>...HEAD`。有 blocking 就產生 fix-plan 交回 executor，最多 3 輪 | `docs/plans/R-NNN-<slug>-review-fix-N.md` |
| **7 Land** | `squash`（預設）：在原 branch 做 squash merge。`mr`：push branch 並開 PR/MR | 一個 squash commit，或一個 PR/MR |
| **8 Compound** | 呼叫 `/ship-compound`：寫 learning、把 pattern 推升到 vault、Roadmap 項目移到 Done（`mr` 模式標成 `in-review`）、更新 `CONTEXT.md` | `docs/learnings/R-NNN-*.md` |
| **8.5 測試報告** | 統計測試的改動量，列出可以刪的測試候選。**只產報告，不刪任何檔案** | `.ship/prune-candidates.md` |
| **8.7 UA 重建** | knowledge graph 落後超過 50 個檔案時，重新跑 `/understand` | — |
| **9 清理** | 保存 codex 執行紀錄；移除 worktree 和 branch（`mr` 模式保留）；在 `_log.md` 記一行；auto 模式發完成通知 | `log: ship R-NNN` |

### 三種 executor（Phase 5）

| # | 方式 | 說明 |
|---|---|---|
| 1 | Subagent-driven（推薦，auto 模式固定用這個） | `superpowers:subagent-driven-development`。每個 task 交給一個新的 subagent，task 之間做 review。進度寫在 `.superpowers/sdd/<plan>/progress.md`，subagent 中途消失時只損失一個 task |
| 2 | Inline | `superpowers:executing-plans`。在目前 session 依序執行，分批設 checkpoint |
| 3 | Codex `/run-plan` | 在背景交給 codex 跑，`/ship-next` 負責監督（見下） |

**Codex 的監督規則**：codex 結束後先判斷結果再決定下一步。

- `done` / `done_with_concerns`：記錄這一輪，進入 Phase 6。
- `infra`（環境問題）：直接停下並通知，**不計入重試次數**。
- `blocked`：讀 codex 的報告，歸成三類之一：

  | 類別 | 判斷依據 | 處理 |
  |---|---|---|
  | plan defect | plan 寫的步驟本身錯了、模糊或做不到 | 修 plan，從卡住的 task 重跑 |
  | executor error | plan 沒錯，是 codex 做偏了 | plan 不改，附修正說明重跑 |
  | spec-level | 問題在做法本身行不通，不只是某一步 | **停下來通知你** |

  判斷不出來時一律當 spec-level：要不要改變軟體該做的事，不是 executor 能決定的。最多重跑 3 次，每一輪紀錄都存在 `.ship/codex-rounds.md`。session 重啟後會重新接上還在跑的 codex，不會重複啟動。

### Review gate（Phase 6）

review 結果分成 blocking / major / minor / praise 四級。**blocking 必須是 0 才能 merge。**

除了 LLM review，還有兩項純 git 計算的機械檢查，結果也算 blocking：

- **Refactor 不能加測試**：plan 裡標成 `Seam: none` 的 task（純重構）如果新增了測試行，算 blocking。
- **測試預算**：這次 ship 的「測試行數 ÷ 程式行數」跟這個 repo 自己的基準比。超過 4 倍算 blocking，超過 2 倍算 major（倍數可在 `test_budget:` 設定）。每個 repo 的前 3 次 ship 只報告、不擋，先累積基準。

reviewer 另外會幫 finding 加上三種標記：`[seam-violation]`（測試斷言了 `## Seams` 沒宣告的東西）、`[assertion-roulette]`（一個測試塞了好幾個不相關的斷言）、`[weak-assertion]`（永遠不會失敗的斷言）。

3 輪後仍有 blocking 時：

- **互動模式**：問你要再跑一輪 `[Y]`、暫停自己修 `[n]`，還是放棄 `[abort]`。
- **auto 模式**：中止。worktree 和 branch 保留，主 branch 不動，並發通知告訴你怎麼接續。

blocking 清空後處理 major：互動模式逐條問你要現在修、開成 IDEA，還是略過；auto 模式全部自動開成 `IDEA-NNN`，不會略過任何一條。

### `--auto:yes` 全自動模式

適合丟著讓它跑一整晚。和互動模式的差別：

- 項目**必須**有 `↳ done when:`；缺 `↳ explain:` 或提案只會警告。
- spec 沒有 `## Seams` 會在 Phase 4 拒絕繼續。
- brainstorm 的每個問題都選第 1 個選項（也就是建議選項），spec 和 plan 的 review 自動通過。
- executor 固定用 1（subagent-driven）。
- 每個自動做的決定都記在 `<worktree>/.claude/.ship-auto-decisions.md`。
- 結束時（成功或中止）會發通知：從 Discord 啟動的就回 Discord，否則發 push notification，同時跳 macOS 桌面通知。
- 不能和 `--discard` 一起用，刪除不允許自動執行。

### `merge_mode`：直接合併或開 review

在目標 repo 的 `.claude/ship-config.yml` 設定：

```yaml
merge_mode: mr   # 預設是 squash
```

| | `squash`（預設） | `mr` |
|---|---|---|
| Phase 7 | 在原 branch 做 squash merge | push branch，用 `gh`（GitHub）或 `glab`（GitLab）開 PR/MR |
| Roadmap 狀態 | Done | `in-review` |
| worktree / branch | Phase 9 刪除 | 保留，review 可能要求修改 |
| 收尾 | 不用做什麼 | review 合併後執行 `/ship-land R-NNN` |

squash commit 訊息和 PR/MR 描述內容相同：done-when、task 清單、review 各級數量、測試行數比、spec 和 plan 的路徑。

### 中斷與接續

worktree 會一直留著，重新執行 `/ship-next R-NNN` 回答 `Y`，或直接用 `--resume R-NNN`。它會依現有狀態自動跳到該繼續的階段：

| worktree 裡已經有 | 從這裡繼續 |
|---|---|
| `docs/specs/R-NNN-<slug>.md` | Phase 4（寫 plan） |
| `docs/plans/R-NNN-<slug>.md` | Phase 5（執行） |
| 比原 branch 多 2 個以上 commit | Phase 6（review） |

brainstorm 方向完全跑偏時，用 `/ship-next --discard R-NNN` 整個丟掉重來。

### 產出的檔案

**進 git 的（repo 端）**

```
docs/
├── brainstorms/R-NNN-<slug>.md
├── specs/R-NNN-<slug>.md
├── plans/R-NNN-<slug>.md          (+ -review-fix-N.md)
├── learnings/R-NNN-*.md
├── learnings/_log.md              # 每次 ship 一行：review 結果、測試比例、codex 輪數
└── tdd-rules.md                   # 這個 repo 自己累積的測試規則（上限 20 條）
```

**Obsidian vault 端**：`Specs/R-NNN-<slug>.md`（spec 的副本，不進 git）。

**worktree 內的暫存檔**（`.ship/`，Phase 9 會跟著 worktree 一起刪掉）：`ua-context.md`、`tdd-rules.md`、`ponytail-rules.md`、`ua-diff-report.md`、`review-extra-checks.md`、`codex-rounds.md`、`prune-candidates.md`。codex 紀錄會先複製到 `/tmp/ship-R-NNN-codex-rounds.md` 再刪。

### 常見失敗

| 狀況 | 處理 |
|---|---|
| 建 worktree 失敗（工作區有未提交的修改） | `git stash` 後重跑 `/ship-next R-NNN` |
| brainstorm 中途 Ctrl-C | worktree 還在：`/ship-next R-NNN` 接續，或 `--discard` 丟掉 |
| executor 中途失敗 | 錯誤記在 plan 的 `## Execution log`，worktree 保留 |
| 沒裝 code-review-skill | Phase 6 停下並印出安裝指令，裝好後重跑會從 Phase 6 接續 |
| merge 回原 branch 衝突 | 中止 merge、worktree 保留，rebase 後再試 |
| 清理失敗（worktree 有未提交的修改） | 印出路徑，請你 `git status` 檢查後手動移除 |

### 設計文件

- [`docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`](docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md)：整體架構
- [`docs/superpowers/specs/2026-06-21-ship-next-mega-command-design.md`](docs/superpowers/specs/2026-06-21-ship-next-mega-command-design.md)：`/ship-next` 一條龍設計
- [`docs/superpowers/specs/2026-06-22-ship-next-auto-yes-design.md`](docs/superpowers/specs/2026-06-22-ship-next-auto-yes-design.md)：`--auto:yes`
- [`docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md`](docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md)：`CONTEXT.md`、Seams、測試預算
- [`docs/superpowers/specs/2026-10-02-codex-supervise-loop-design.md`](docs/superpowers/specs/2026-10-02-codex-supervise-loop-design.md)：codex 監督迴圈
- 完整指令定義：[`claude-skills/ship-workflow/commands/ship-next.md`](claude-skills/ship-workflow/commands/ship-next.md)
