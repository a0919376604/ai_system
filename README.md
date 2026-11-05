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

- **一行裝好**：換新電腦時，ship-workflow 和它需要的 skill、全域設定一次裝好。
- **遠端開發**：在公司的 GPU server 上跑程式時，本機寫的 code 會即時同步過去。
- **手機上看 Roadmap**：Obsidian 外掛「Roadmap 檢視」，一次看一個專案的近況，寫給人看的版本。

## 2. Skills 一覽

`claude-skills/` 裡的六個 skill，`./sync.sh restore` 會全部裝好：

| Skill | 一句話 | 怎麼叫 |
|---|---|---|
| **ship-workflow** | 從 Roadmap 的一列做到 merge 的開發流程；另外附兩個「找出該整頓的地方」的掃描 | `/ship-next`、`/ship-refactor-scan`、`/ship-refactor-brand`、`/ship-idea`… |
| **draw-arch** | 讀程式碼，畫出一包給人看的架構說明（圖、背景程式、功能、可替換性） | `/draw-arch` |
| **pr-review** | 用四個角度 review 一個 PR／MR／branch：程式規範、對照 spec、codex 交叉 review、資安 | `/pr-review [<PR 編號或網址>]` |
| **run-plan** | 把寫好的實作計畫交給 codex 在背景跑完，邊跑邊回報 | `/run-plan <plan.md>` |
| **code-review-skill** | 各語言的 code review 準則，給 `/ship-next` 和 `/pr-review` 用 | 不直接叫 |
| **weekly-report** | 從 git log 整理一週做了什麼 | 「整理這週做的事」 |

### ship-refactor：先找出該整頓的地方，再交給 `/ship-next`

`/ship-next` 只負責「把一列做完」，不會主動告訴你哪裡該重構。ship-refactor 是在它之前的一步：**掃描 → 出報告 → 你挑 → 寫進 Roadmap**，本身不改任何程式碼。

```
/ship-refactor-scan [方向]          /ship-refactor-brand [頁面範圍]
  │ 架構：哪些模組太淺、太黏            │ 品牌：先畫三個品牌方向讓你挑
  ▼                                     ▼ 再盤點不一致的樣式與重複元件
報告兩份（同一個檔名）
  ├── 給人看的 HTML：結論在前，每個候選有前後對照圖
  └── 給 AI 看的 Markdown：證據、檔案、建議做法
  ▼
你挑要做哪幾個（也可以只看報告、不挑）
  ▼
挑中的寫進 Roadmap 🔜 Next（附 done when）  →  之後用 /ship-next R-NNN 實作
```

- **`/ship-refactor-scan`**：照 Matt Pocock 的 *improve-codebase-architecture* 方法。不指定方向時，先挑「最近半年改最多 × 行數最多」的熱點檔案開始看；被你拒絕過的候選會記下來，下次除非問題明顯變嚴重，否則不再提。每個候選列出問題、建議的介面、好處和推薦程度，最後給一個「最推薦先做」。
- **`/ship-refactor-brand`**：給已經上線的網站用。第一步先用 taste v2 畫三個品牌方向的 mockup 讓你挑（之後沿用，說「重選」才重挑）；接著對照選定的方向，盤點字體、顏色、間距、圖示、互動狀態的不一致，以及長得很像卻各寫一份的元件，提出整合方案和遷移順序。
- **寫進 Roadmap 的列**一律帶「先用測試鎖住現有行為、搬結構時不動既有測試、只改結構不改行為」這幾條守則，避免重構順手改壞東西。

報告存在 vault 的 `<專案>/Reports/`。

### draw-arch：讀程式碼，產生一包架構說明

給「想搞懂這個系統」的人看，例如新同事、PM，或是要決定能不能換掉某個外部服務的時候。**Claude 讀程式碼、寫內容與排版；腳本負責畫圖、檢查、掃描事實**，所以數字和程式碼位置不是猜的。

```
/draw-arch [主題…]
  │ 1. 找到目標 repo 和 vault 專案，記下 commit
  │ 2. 追程式碼：從入口、設定一路追到實際的輸入、輸出和副作用，每個節點都附 檔案:行
  │ 3. 寫成 JSON spec（specs/<主題>.json）
  │ 4. check.py 檢查：版面重疊、文字放不下、LangGraph 圖要和程式碼一致、清單不能漏…
  │ 5. render.py 產生 HTML，開 headless Chrome 截圖、看圖修正（最多三輪）
  ▼
<vault 專案>/Architecture/diagrams/
├── README.md   ← 入口：怎麼看、每頁重點、怎麼更新（GitLab 會直接顯示）
├── html/       ← 完整頁面，打開 html/index.html；離線可看、支援手機
└── specs/      ← 來源 JSON
```

預設會產生這幾種頁面：

| 頁面 | 回答什麼問題 | 事實從哪來 |
|---|---|---|
| 系統總覽、訊息流程 | 系統由哪些部分組成？一則訊息怎麼走？ | Claude 追程式碼，每個節點附出處 |
| LangGraph 流程 + 節點契約 | AI 流程有哪些節點？每個節點讀寫哪些欄位、哪個好換？ | `check.py` 對照 AST 驗證圖；`contract.py` 掃每個節點的 state 讀寫 |
| 可替換性（seams） | LINE、Confluence、LLM、向量庫能不能換？哪裡漏進核心？ | `seams.py` 掃 import 和 API 網址，標出在 adapter 內還是漏進核心 |
| 背景程式（jobs） | 到底有幾個背景程式？各做什麼、多久跑一次？ | 對照程式碼裡的登記表，漏列會被抓出來 |
| 功能目錄（features） | 有哪些功能？從哪裡觸發、用到哪些資料？ | Claude 從 API 和前端路由整理 |

**跟程式碼保持一致**：程式改了以後跑 `python3 <skill>/lib/check.py specs/<主題>.json --repo <repo>`，會指出哪一頁過期（背景程式少列、接觸點變了、圖跟程式碼對不上）。重跑 `/draw-arch` 會保留原本的排版，只更新變動的部分。

**放進專案 repo**：draw-arch 只寫進 vault，不直接改目標 repo。要放上 GitLab／GitHub，就把整包複製到該 repo 的 `docs/architecture/` 再開 MR。

## 3. Quick start

```bash
git clone git@github.com:a0919376604/ai_system.git ~/Desktop/code/ai_system
cd ~/Desktop/code/ai_system
./sync.sh restore
```

`restore` 會裝好這些東西：

| repo 內 | 安裝到 | 內容 |
|---|---|---|
| `claude-skills/` | `~/.claude/skills/`（symlink） | 六個 skill：`ship-workflow`、`run-plan`、`code-review-skill`、`pr-review`、`weekly-report`、`draw-arch`（見 [Skills 一覽](#2-skills-一覽)） |
| `claude-skills/ship-workflow/commands/` | `~/.claude/commands/`（symlink） | `/ship-next`、`/ship-compound`、`/ship-idea`、`/ship-land`、`/ship-init`、`/ship-refactor-scan`、`/ship-refactor-brand` |
| `claude-skills/ship-workflow/skills/ship-refactor-brand/` | `~/.codex/skills/ship-refactor-brand`（symlink） | 品牌一致性與共用元件盤點，提出候選供選入 Roadmap |
| `config/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | 全域規則的備份；內容不同時會先問你 |
| `devsync/` | `~/.local/bin/devsync` | 同步到 dl01–dl04 的 CLI，連同 mutagen、uv、SSH 設定 |

> 全部用 symlink 接上，所以本機跑的永遠是這個 checkout。擋路的實體目錄會搬到 `~/.claude/.ai_system-displaced/`，不會被刪掉；重跑不會多改任何東西。

**啟用 ship-workflow：**

```bash
cp ~/.claude/skills/ship-workflow/examples/ship-workflow.example.yml ~/.claude/ship-workflow.yml   # 填入 vault 路徑
```

再安裝 [superpowers](https://github.com/obra/superpowers) plugin，然後在目標 repo 執行 `/ship-init`。

## 4. 使用範例

### 安裝與備份

```bash
./sync.sh status     # 每個連結、設定檔的狀態；有連結不對時 exit 1
./sync.sh backup     # 全域 CLAUDE.md、devsync 設定 → repo
./sync.sh restore    # 接好連結、還原設定檔（--dry-run 只顯示會做什麼）
```

主 checkout 要停在 `main`：本機每個 session 跑的都是這個 checkout，連未提交的修改也算。不在 `main` 或有未提交修改時，`/ship-next` 會警告。

### 找出該重構的地方

```text
/ship-refactor-scan                 # 架構：從熱點檔案找太淺、太黏的模組
/ship-refactor-scan 推播            # 指定方向
/ship-refactor-brand 首頁、會員中心  # 品牌：先挑方向，再盤點不一致與重複元件
```

流程與報告內容見 [ship-refactor](#ship-refactor先找出該整頓的地方再交給-ship-next)。Codex 使用 `$ship-refactor-brand`。

### 畫架構說明

```text
/draw-arch                          # 預設：總覽、功能、可替換性、背景程式、訊息流程、LangGraph
/draw-arch seams jobs               # 只更新指定的頁面
```

說明見 [draw-arch](#draw-arch讀程式碼產生一包架構說明)。

### 用 Roadmap 開發功能

**R-xxx 是什麼**

Roadmap 上每個要做的項目都有一個編號 `R-NNN`（例如 `R-012`），從目前最大的號碼往上加。太大的項目會拆成 `R-012.1`、`R-012.2` 這樣的子項目，原本的 `R-012` 變成 epic，`/ship-next` 自動挑選時會跳過它。

這個編號會貫穿整個流程：worktree、branch、spec、plan、learning 都用它命名，事後從任何一個檔案都能追回同一個項目。另外還有一種編號：`IDEA-NNN` 是還沒排進 Roadmap 的想法（多半是 review 時延後處理的問題）。

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
Later → Next → Now     ← 順序由你決定；brainstorm 會建議把太大的項目拆成幾列
  ▼
/ship-next R-NNN       ← brainstorm → spec → plan → 實作 → review → merge
  │
  ▼
✅ Done                ← review 延後處理的問題變成 IDEA，要不要排進 Roadmap 由你決定
```

**實際操作**

```text
幫我把「客服批次關閉工單」加到 Roadmap  # 配好 R-NNN
/ship-next                              # 取 Now 第一項，做到 merge
/ship-next R-012 --auto:yes             # 指定項目，全自動
/ship-next --adhoc "修 token 外洩"      # 臨時插單
/ship-next --discard R-012              # 放棄並清掉 worktree
```

**走完一套流程後**

- 主 branch 上多一個 squash commit，訊息裡有 done-when、task 清單和 review 結果。
- `docs/learnings/` 多一份 learning（含 Key Decisions）。spec 和 plan 只在進行中存在，收尾時移除；spec 全文留在 vault `Specs/` 和 git 歷史（R-005、R-006）。
- Roadmap 那一列移到 ✅ Done 並標上日期（`mr` 模式先標成 `in-review`）。
- `CONTEXT.md` 補上這次新出現的專案用語；可重用的 pattern 會問你要不要推升到 vault。
- review 時延後處理的 major 問題變成新的 IDEA-NNN（auto 模式全部都會開）。
- worktree 和 branch 都已刪除（`mr` 模式會保留到 `/ship-land`），可以直接接下一個 `/ship-next`。

**Roadmap 機制的好處和缺點**

| 好處 | 缺點 |
|---|---|
| 一個編號追到底：從想法、spec、commit 到 learning 都能用 R-NNN 串起來 | 很吃紀律：描述和 done-when 寫得越模糊，brainstorm 和全自動模式就越容易做偏 |
| 「做完」有明確定義：done-when 讓你和 AI 用同一個標準驗收，全自動模式也有依據 | 排序靠你自己：沒有自動排序，Now 的順序就是你寫的順序 |
| 項目會被逼著變小：brainstorm 會建議拆開太大的項目，拆出來的每一列都必須能驗收 | IDEA 會越積越多：review 自動開的 IDEA 需要定期整理，或標成 `shelved` 擱置 |
| 問題不會被遺忘：延後處理的 review 問題會變成 IDEA，留在 `docs/ideas/` 等你決定 | 編號在本機分配：兩台機器在 Roadmap 同步之前各自開新項目，可能拿到同一個號碼 |

### 手機上看 Roadmap（Obsidian 外掛「Roadmap 檢視」）

ROADMAP.md 是寫給 AI 看的；這個外掛從裡面挑出人需要的部分，即時顯示，手機優先：

- **近況**：進行中／卡住、最近完成（14 天內）、待做（收合）。**全部**：每一項，可搜尋。
- 每一項：中文標題、狀態（完成日期、尚未部署、卡住原因、方案）、ship-next 正在哪個階段、mockup 的「現況」縮圖，點了全螢幕放大（符合寬度／2×／3×）。
- 詳細頁：spec、brainstorm、mockup 的連結，commit／MR，完成條件，給 AI 的原文。
- 檔案一變就重畫，不用產生。ship-next 每到一個階段就寫 `<專案>/ship-status/<R-NNN>.json`。
- 只讀：除了自己的設定（`data.json`）不寫任何檔案。

`./sync.sh restore` 會把外掛複製到 vault 的 `.obsidian/plugins/roadmap-view/`，再到 Obsidian 的「第三方外掛」啟用一次。手機靠 Obsidian Sync：要開「同步已安裝的外掛」與「同步其他類型的檔案」（mockup 是 `.html`、狀態是 `.json`）。

### 遠端開發

```bash
devsync start dl02     # 同步目前目錄到 dl02 並 SSH 進去
devsync ls             # 列出 session
devsync stop my-repo   # 結束
```

## 5. 好處與缺點

**好處**

- **主 branch 很安全**：每個項目都在獨立的 worktree 裡做，merge 前不會動到主 branch。中斷了可以接續，做壞了一行指令就能丟掉。
- **Review 是硬門檻**：blocking 沒歸零就不能 merge。除了 LLM review，還會機械檢查純重構有沒有偷加測試、測試量有沒有超過 repo 自己的基準。
- **經驗會累積**：過去的 learning 會在下次 brainstorm 時被讀回來，專案用語（`CONTEXT.md`）和測試規則（`docs/tdd-rules.md`）也會隨著每個 repo 一起成長。
- **可以無人值守**：`--auto:yes` 可以整晚自己跑，每個自動做的決定都有紀錄，失敗時保留現場並通知你。
- **每一步都留紀錄**：每個項目留一份 learning（含當初的決定和理由）在 repo，spec 全文在 vault，過程在 git 歷史；repo 裡不會堆過時的設計文件。

**缺點**

- **小改動也要走全套**：一行修正一樣會經過 brainstorm、spec、plan、review，花的時間和 token 都多。
- **依賴多**：Obsidian vault、superpowers 少一個就跑不起來。
- **綁我的環境**：只支援 macOS，範例設定寫死我的路徑，devsync 也只連內部的 dl01–dl04。
- **流程由模型執行**：helper script 有 bats 測試，但指令本身是給 Claude 讀的 markdown，每一步有沒有照做，取決於模型。
- **全自動的品質看 Roadmap 寫得多清楚**：`--auto:yes` 遇到問題一律選建議選項，Roadmap 寫得越模糊，做出來的就越可能和你想的不一樣。
- **策略只能在 Obsidian 改**：同步是單向的，直接在 repo 改 ROADMAP 會被擋下來。

## 6. 需求

**必要**：macOS + Homebrew、Claude Code、Obsidian vault、[superpowers](https://github.com/obra/superpowers)、dl01–dl04 的 SSH 帳號（devsync 用）。[code-review-skill](https://github.com/awesome-skills/code-review-skill) 已經收在 repo 裡。

**選用**：

| 項目 | 用途 |
|---|---|
| compound-engineering（`ce-*`） | `/ship-compound` 的自動化 |
| [ponytail](https://github.com/DietrichGebert/ponytail) | executor 的寫碼規則 |
| codex CLI | 第 3 種 executor |
| `gh` / `glab` | `merge_mode: mr` 開 PR/MR |

測試：`bats claude-skills/ship-workflow/tests/`（包含 Roadmap 檢視外掛的 `node --test`，需要 Node 22 以上）

## 7. `/ship-next`

在獨立 worktree（`<repo>-worktrees/R-NNN-<slug>`，branch `ship/R-NNN-<slug>`）裡把一個 Roadmap 項目從 brainstorm 做到 merge，merge 前不會動到主 repo。

| Phase | 做什麼 |
|---|---|
| 1 | 同步 vault、選定 R-NNN |
| 2 | 開 worktree |
| 3 | 讀過去的 learning 和 `CONTEXT.md`，brainstorm 出 spec（必須有 `## Seams`），問題一次問完、每題附建議答案 |
| 4 | 寫 plan |
| 5 | 執行 plan |
| 6 | Code review 加獨立的 security review、Spec review（逐條對照 spec），blocking 必須歸零，最多修 3 輪 |
| 7 | Squash merge，或開 PR/MR |
| 8 | 寫 learning、Roadmap 移到 Done |
| 9 | 刪除 worktree 和 branch |

**Executor（Phase 5）**：1. subagent 逐 task 執行（推薦）　2. 在目前 session 依序執行　3. 交給 codex 背景跑，卡住時自動判斷要修 plan 重跑，還是停下來通知你

**Review（Phase 6）**：除了 LLM review，還會擋兩件事：純重構的 task 新增了測試，以及測試行數比例超過 repo 基準的 4 倍。

**`--auto:yes`**：全程不問問題，適合丟著跑一整晚。項目必須有 `↳ done when:`；問題一律選建議選項；major finding 自動開成 IDEA；3 輪還過不了就中止並保留 worktree。

**`merge_mode: mr`**（寫在 `.claude/ship-config.yml`）：不直接 merge，改成開 PR/MR，review 只帶工作內容；合併後執行 `/ship-land R-NNN`，在 `origin/<base>` 的暫存 worktree 跑 `/ship-compound`，以 `[skip ci]` 推送後清理 branch 和 worktree（R-008）。

**中斷**：重跑 `/ship-next R-NNN` 會從上次的階段接續。

完整定義見 [`ship-next.md`](claude-skills/ship-workflow/commands/ship-next.md)，設計文件在 [`docs/superpowers/specs/`](docs/superpowers/specs/)。
