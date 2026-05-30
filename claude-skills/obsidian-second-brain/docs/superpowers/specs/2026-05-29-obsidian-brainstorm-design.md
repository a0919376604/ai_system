# `/obsidian-brainstorm` Design

**Status:** Draft — ready for review
**Date:** 2026-05-29
**Author:** brainstormed with user (Eugeniu)
**Related specs:**
- v4.x architect specs (Architecture/* 是本命令的主要讀取對象)
- `/obsidian-roadmap` (本命令輸出的下游消費者)

---

## Goal

新增一個 slash command `/obsidian-brainstorm <project>`,用於使用者「卡住、不知道下一步該做什麼」時,由 Claude **訪談式 brainstorm**:Claude 讀完 vault 全部 project 素材後,主動丟出 4-6 個大膽推測(provocations),引導使用者反應與深挖,最後蒸餾成 roadmap-ready 的 ImprovementItem + 待驗證假設,寫進 `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`,並被 `/obsidian-roadmap` 自動撿走。

## 為什麼這個命令值得存在

**現有 thinking 類命令的缺口:**

| 既有命令 | 訊號方向 | 缺口 |
|---|---|---|
| `/obsidian-decide` | 從對話抽決定 | 假設 decision 已產生;不會主動引發決定 |
| `/obsidian-challenge` | 對抗一個既有想法 | 必須先有想法才能 challenge |
| `/idea-discovery` | 跨 vault + 外部 surface 5 個 candidates | 偏 read-only;不 interview 使用者 |
| `/research-deep` | 從外部抓資料進 vault | 不消化使用者腦袋 |
| `/obsidian-architect` | 從 code 推架構 | 看不見使用者的 tacit knowledge |

**真正的缺口:** 沒有命令是「Claude 問使用者問題,把使用者腦中尚未寫下的 insight 蒸餾進 vault」。本命令填補這個缺口。

## Non-goals

- 不是 `/obsidian-challenge` 的延伸 — 那是 red-team 既有想法,本命令是生成新方向
- 不是 `/research-deep` 的取代 — research 跑外部,brainstorm 跑 vault + 使用者
- 不是 `/obsidian-architect` 的部分 — 架構是 code 反映,brainstorm 是 tacit knowledge
- 不把 distilled-imps 直接寫進 features.md / decisions.md — 那會 churn 既有檔。蒸餾結果只進 Brainstorms/`<date>-<slug>`.md;後續成熟內容由 `/obsidian-graduate` 顯式遷移
- 不支援 multi-project 一次 brainstorm — 一次一個專案,避免脈絡混雜

## Frame

**命令:** `/obsidian-brainstorm <project>`(短別名 `/obsidian-bs`)

**參數:** 專案名(`Projects/` 下資料夾)。若 `pwd` 在 `Projects/<P>/` 內預設 `<P>`,否則詢問。

**可選旗標:**

- `--topic="<種子>"` — 收窄 provocation 焦點。例:`--topic="客戶流失"`,Claude 開場 6 個都圍繞流失主題
- `--lens=gap|persona|trend|premortem|mix` — provocation 風味偏重;預設 `mix`(每種角度 1-2 個,共 4-6 個)
- `--depth=quick|medium|deep` — `quick`=只開場 + 反應(預設 10 分鐘);`medium`=drill 1-2 個(30 分鐘);`deep`=全 drill(60+ 分鐘)
- `--lang=zh-TW|en` — 覆寫 vault 預設語言
- `--research-window-days=N` — 讀 `Projects/<P>/Research/` 的時間窗,預設 30 天

## Lens 角度定義(provocation 風味)

| Lens | 來源訊號 | 範例 |
|---|---|---|
| `gap` | Architecture/overview.md `## 跨模組改進機會` + features.md `## 改進機會` + ai-flows/*.md `## 改進機會` | 「3 個 cross-cutting Imp 都點到 X 模組,但 board 沒人在動 — 是否該優先?」 |
| `persona` | personas.md persona 痛點 + features.md `## 產品覆蓋度` 的 ❌/⚠️ 標記 | 「客服管理員痛點段明示『無即時 SLA 警示』,你卻 3 個月沒動 — 是否真的不重要?」 |
| `trend` | Research/*.md 在窗內的內容 + 競品 / 趨勢 | 「[[Research/2026-04-line-bot-trends]] 列了競品 X 新功能 Y,你完全沒對應」 |
| `premortem` | decisions.md `## 已知限制` + 邏輯推理 | 「6 個月後此 product 死了,死因 top 3:(1) 客戶要 multi-channel 你只有 LINE (2) ... (3) ...」 |

**`mix` 預設配方:** 1-2 gap + 1-2 persona + 1-2 trend + 1 premortem,合計 4-6 個。Claude 依 vault 訊號豐富度自動微調(若 Research/ 空則 trend 改為 0,空額補 gap)。

## 對話流程(6 個 phase)

### Phase 0: Pre-flight

- 確認 vault 根有 `_CLAUDE.md`,沒有則 abort
- 確認 `Projects/<P>/` 存在;沒有則建議跑 `/obsidian-project <P>` 先
- 建立 `Projects/<P>/Brainstorms/`(若無)
- 解析 `output_lang`(`--lang` flag > vault `_CLAUDE.md`)

### Phase 1: Vault 讀取(deterministic, no LLM)

Claude 自己 read 以下檔案,組成 `BrainstormContext` dict 給 Phase 2 用:

```jsonc
{
  "project_slug": "langlive-line-oa",
  "scan_window_days": 30,
  "architecture_imps": [
    {"title": "...", "why": "...", "evidence": "[[modules/backend#...]]",
     "source": "Architecture/overview.md#cross-cutting-improvements",
     "lens_hint": "gap"}
  ],
  "personas_pains": [
    {"persona": "客服管理員", "pain": "沒有即時 SLA 警示",
     "source": "Architecture/personas.md#客服管理員"}
  ],
  "known_limitations": [
    {"text": "單一 channel...",
     "source": "Architecture/decisions.md#known-limitations"}
  ],
  "missing_features": [
    {"title": "Multi-channel inbox", "rationale": "...",
     "confidence": "speculation",
     "source": "Architecture/features.md#missing-features"}
  ],
  "recent_research": [
    {"title": "LINE bot 2026 趨勢", "first_para": "...", "tags": ["competitor"],
     "date": "2026-04-15", "source": "Research/2026-04-line-bot-trends.md"}
  ],
  "in_flight_board": [
    {"title": "WebSocket 斷線重連", "source": "board.md#待辦"}
  ],
  "owner_recent_focus": [
    "v4.3 architect 加 memory.md + rag.md",
    "發現 embedding alignment 是 P0"
  ],
  "past_brainstorms": [
    {"file": "Brainstorms/2026-05-15-vision-q3.md",
     "open_questions": ["客服多語系 vs multi-channel,哪個先?"],
     "parked_titles": ["Shift handoff workflow", "..."]}
  ]
}
```

讀取規則:

- `Architecture/overview.md` — 取 `## 跨模組改進機會` block 內容(已是 ImprovementItem shape,直接 parse)
- `Architecture/features.md` — 取 `## 改進機會` 與 `## 可加 features` 兩個 block
- `Architecture/ai-flows/*.md` — 每個檔的 `## 改進機會` block(包含 per-flow、memory.md、rag.md)
- `Architecture/personas.md` — 前 4KB,撈出每個 persona 的痛點段
- `Architecture/decisions.md` — `## 已知限制` block
- `Projects/<P>/Research/` — mtime 在 `--research-window-days` 內的 .md;每檔取 frontmatter title + first paragraph + tags + date
- `Projects/<P>/board.md` — `## 待辦` 段內所有卡片標題(避免推已在做的事)
- `Logs/YYYY-MM-DD.md` 最近 7 天 — 提取與本 project 有關的條目(透過 `[[<P>]]` wikilink 比對)
- `Projects/<P>/Brainstorms/*.md` 過去 session — 提取 `## 仍不清楚` + `## 暫不討論`(讓 parked 越累積越突出)

**Past brainstorms 的特殊邏輯:** 若同一主題的 `parked` 出現 ≥3 次(用 fuzzy title 比對),在 BrainstormContext 標 `repeat_count: N`,Phase 2 開場時用 `🔁 第 N 次出現` 提示使用者「這事一直被擱著」。

### Phase 2: 開場 provocations(LLM, 一次性 message)

Claude 用 `BrainstormContext` + `--lens` 配方 + `--topic` seed 產 4-6 個 provocations。

每個 provocation **必含**:
- 標題(≤ 30 字)
- **為什麼**(1-2 句)
- **證據**(wikilink 到 vault 真實檔;若 lens=`premortem` 純推理則標 `(speculation, no evidence)`)
- **Lens**(gap / persona / trend / premortem)
- **Confidence**(`speculation` / `stated` / `hypothesis`)

**Confidence 三態定義:**
- `stated` — 證據在 vault 已寫明(例:features.md missing-features 已列)
- `hypothesis` — 有 vault 證據但有推理跳躍(例:trend 推測競品反應)
- `speculation` — 純推理,無 vault 直接證據(例:premortem 死因推測)

**Provocation 風格:**
- **大膽** — 願意推測使用者沒想到的方向,而非保守列既存事實
- **必標 lens + confidence** — 使用者一眼看出哪個是事實基礎、哪個是推測
- **必有證據 wikilink 或標 `(speculation)`** — 不發明 vault 沒有的引用
- **零廢話** — 不要「這個值得思考」「我覺得很有趣」這類填充

整個 Phase 2 是**一個 chat message** 含全部 4-6 個 provocations,標號 P1-P6。

### Phase 3: 使用者反應(chat)

使用者用編號回應:
- `drill P2, P5` — 標記要深挖的
- `kill P1` — 否決(會保留在輸出檔但標 killed)
- `park P3 P4` — 擱置不討論(會進 `parked` block;若是第 ≥3 次出現會有提示)
- `P6 改成 X` — 改寫一個 provocation,改寫後等同 drilled
- `none` — 全部都不感興趣,結束 session(寫一個 minimal 檔記 4-6 個 provocations 全 killed)

Claude 確認解析,進 Phase 4。

### Phase 4: 深挖(LLM, 多輪 chat)

對每個 drilled provocation,Claude 問 2-4 個 follow-up,**一次一題**(不一次丟全部),從以下池子挑 + 視情境臨場加問:

- 「如果這 ship 了,1 個月 / 6 個月後成功是什麼樣子?」
- 「最有風險的假設是什麼?」
- 「你要從誰那裡偷時間 / 預算?」
- 「最小可推翻它的測試是什麼?」(導向 hypothesis)
- 「誰會反對?他們的合理擔憂是什麼?」
- 「3 個月後客戶才看到效果,你撐得住嗎?」
- 「跟 board 上 X / Y 衝突,如何排序?」

**Quote capture rule:** 使用者每答完一題,Claude 標出哪一句是「verbatim quote 值得留下」(用 `> ` 引用),哪些是 paraphrase。寫檔時 verbatim quote 必須一字不改保留;paraphrase 可精簡。

### Phase 5: 蒸餾 + 寫檔(LLM)

Claude 從 drilled-explorations 提煉:

- **distilled-imps** — 每個 drilled provocation → 0-2 個 ImprovementItem(`為什麼 / 證據 / Effort / 未做的風險 / Confidence`)+ 對哪個 module 開門 wikilink
- **hypotheses** — 提到「我猜...」「如果...就...」「不確定...」的內容 → hypothesis shape(假設 + 驗證方式 + kill criterion + owner)
- **open-questions** — session 結束使用者還沒答出來的問題

用 `scripts.architect.sections.compose_brainstorm_note(...)`(新增)寫檔。檔名 slug 由 Claude 從 session 主軸自動推導(`vision-q3`、`customer-churn`、`shift-handoff`),hyphen-case ascii-lowercase。

### Phase 6: Hub + 日誌更新

- `Logs/YYYY-MM-DD.md ## Activity` 加一行(idempotent):
  ```
  **HH:MM** — brainstorm | <P> — <slug> — N imps + M hypotheses drilled
  ```
- 專案 hub `<P>.md` 加 `## Brainstorms` 區塊(sentinel-aware,初次跑時建立):
  ```markdown
  ## Brainstorms

  <!-- @generated:start brainstorms-section -->
  - 最近 session: [[Brainstorms/2026-05-29-vision-q3]] (5 imps + 2 hypotheses)
  - 全部 sessions: [[Brainstorms/]] folder (按日期 sort)
  - 新 session: `/obsidian-brainstorm <P>`
  - 餵 Roadmap: `/obsidian-roadmap <P>` (自動拾取 status≠actioned 的 brainstorms)
  <!-- @generated:end brainstorms-section -->
  ```
- 不更新 `Architecture/overview.md` 的 drill-down — Brainstorms 不屬於架構層

## 輸出檔 Schema

**位置:** `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`

**Frontmatter:**

```yaml
---
type: project-brainstorm
date: 2026-05-29
project: "[[<project-name>]]"
mode: generate                       # generate (本命令固定;留欄位以兼容未來 sharpen mode)
lens-mix: ["gap", "persona", "trend", "premortem"]   # 該 session 實際用到的 lens
depth: medium                        # quick | medium | deep
status: fresh                        # fresh | reviewed | actioned (人手調整)
session-duration-min: 28
provocations-opened: 5
provocations-drilled: 2
imps-distilled: 3
hypotheses-raised: 2
related: ["[[Architecture/overview]]", "[[Architecture/features]]", "[[Architecture/ai-flows/rag]]"]
sources: ["Architecture/*", "Research/*", "board.md", "recent Logs"]
lang: zh-TW
tags: [brainstorm, project]
ai-first: true
---
```

**Body — 9 個 @generated block:**

| # | Block | H2 (zh-TW) | H2 (en) | 內容 |
|---|---|---|---|---|
| 1 | `context` | `## 對話脈絡` | `## Session context` | 1 段:session 觸發原因、Claude 讀了哪些 vault 段(條列 wikilink)、使用者進來時的狀態(若有提及) |
| 2 | `opening-provocations` | `## 開場 provocations` | `## Opening provocations` | 4-6 個 H3,每個含 為什麼 / 證據(wikilink)/ Lens / Confidence / 使用者反應(`drilled` / `killed` / `parked`)。**全部保留** — 即便被殺也留 trail |
| 3 | `drilled-explorations` | `## 深挖紀錄` | `## Drilled explorations` | 每個 drilled provocation 一個 H3,內含 Claude 的 follow-up Q + 使用者答的精要(verbatim quote 用 `> ` 引述,paraphrase 不引述)+ 結論 |
| 4 | `distilled-imps` | `## 提煉的 Imps` | `## Distilled improvements` | 3-5 個 H3 ImprovementItem(`為什麼 / 證據 / Effort / 未做的風險 / Confidence`)+ 對哪個 module 開門 wikilink。`/obsidian-roadmap` 直接抓這 block |
| 5 | `hypotheses` | `## 待驗證假設` | `## Hypotheses to validate` | 每個 H3 含 假設 + 驗證方式(實驗 / 訪客戶 / metric 觀察) + kill criterion + owner |
| 6 | `parked` | `## 暫不討論` | `## Parked` | 開場時被 user 標 `parked` 的 provocations 收集這。若是 ≥3 次重複出現的主題,標 `🔁 第 N 次出現` |
| 7 | `open-questions` | `## 仍不清楚` | `## Open questions` | session 結束後 user 還沒答的問題、待找資料 / 訪客戶的事 |
| 8 | `meta-reflection` | `## 自我覆盤` | `## Meta reflection` | 1-3 條:這 session 哪個 lens 最有效?哪個 provocation 引爆最多後續想法?下次該換什麼角度? |
| 9 | `dependencies` | `## 相關連結` | `## Dependencies` | Wikilinks only — 引用到的所有 vault 檔案(Architecture/* / Research/* / personas 條目 / decisions / 其他 brainstorms) |

**內容紀律:**

- **絕不發明 vault 證據** — 每個 provocation / Imp / hypothesis 的 Evidence 欄要嘛是真的 wikilink,要嘛標 `Confidence: speculation` + 寫「無 vault 證據,純推測」
- **保留使用者原話** — drilled-explorations 區的引述用 `> ` 區隔
- **不刪 killed provocations** — opening-provocations 區保留全部 4-6 個的全文,只在 `使用者反應` 欄標 `killed`

## Roadmap 整合

`scripts/roadmap/candidates.py:detect_candidates` 多走一個 folder:

```python
# v4.4 — Brainstorms session output
brainstorms_dir = project_dir / "Brainstorms"
if brainstorms_dir.is_dir():
    for bs_path in sorted(brainstorms_dir.glob("*.md")):
        text = bs_path.read_text(encoding="utf-8")
        # status: actioned 則跳過 (已被處理過)
        if _frontmatter_status(text) == "actioned":
            continue
        # distilled-imps → 一般 candidate
        imp_body = _extract_generated_block(text, "distilled-imps")
        if imp_body:
            for imp in parse_improvements_block(imp_body):
                priority = "low" if imp.confidence in ("hypothesis", "speculation") else "normal"
                candidates.append(_candidate_from_imp(
                    imp,
                    source=f"Brainstorms/{bs_path.name}#distilled-imps",
                    candidate_type="brainstorm-imp",
                    priority=priority,
                ))
        # hypotheses → 另一種 candidate type
        hyp_body = _extract_generated_block(text, "hypotheses")
        if hyp_body:
            for hyp in parse_hypothesis_block(hyp_body):
                candidates.append(_candidate_from_hypothesis(
                    hyp,
                    source=f"Brainstorms/{bs_path.name}#hypotheses",
                    candidate_type="brainstorm-hypothesis",
                    priority="low",   # 假設要先驗證,不直接做
                ))
```

**Dedup 規則新增條目:** 當 brainstorm 候選與 architecture / features / ai-flow 候選共享 Evidence wikilink 時,**brainstorm-imp 勝出**(因為它是 user-confirmed,前者是 Claude-inferred)。具體實作:`_dedup_candidates` 加一條規則 — 比 evidence wikilink overlap 時,`source` 以 `Brainstorms/` 起頭者保留,其他源被 dedupe 掉。

**Priority 規則:**
- `confidence: stated` 的 brainstorm-imp → priority `normal`(可直接進 roadmap)
- `confidence: hypothesis` 或 `speculation` 的 brainstorm-imp → priority `low`(roadmap 排末段,owner 校對後可手動 promote)
- 所有 brainstorm-hypothesis → priority `low`(明確需驗證後才動)

## Graduation 流程(命運四選一)

session 結束後的 brainstorm 檔有 4 種演化方向:

1. **distilled-imps 被 `/obsidian-roadmap` 採用** → 寫成 T-NNN task → owner 把 brainstorm 檔 frontmatter 改 `status: actioned`(下次 detect_candidates 略過)
2. **hypothesis 被 `/research-deep` 拿去驗證** → 產生 `Research/<topic>.md` → owner 手動把 hypothesis frontmatter 加 `validated: true/false`(或留著待驗證)
3. **open-questions 累積成下次 brainstorm 的開場素材** → Phase 1 的 `past_brainstorms.open_questions` 自動拾取
4. **parked provocations 累計重複度** — Phase 1 偵測同一主題 ≥3 次 `parked`,下次開場標 `🔁 第 N 次出現` 提醒 owner 別再擱置

## 跨命令職責邊界

| 命令 | 觸發場景 | 輸入 | 輸出 |
|---|---|---|---|
| `/obsidian-architect` | code 重大變化後 | codebase | `Architecture/*`(8+ 個檔) |
| `/obsidian-brainstorm` | **「不知道下一步該做啥」** | Vault 全部 + 使用者腦袋 | `Brainstorms/<date>-<slug>.md` |
| `/obsidian-challenge` | 紅隊一個既有想法 | 想法 + vault 過去 | 紅隊報告(日誌,不寫 project 檔) |
| `/research-deep` | 要從外部抓 fact | seed query | `Research/<topic>.md` |
| `/obsidian-roadmap` | 規劃下個 sprint | Architecture/* + Research/* + Brainstorms/* | `Roadmap.md` + `T-NNN` tasks + board |
| `/obsidian-decide` | 對話剛做完決定 | 當前 chat | `decisions.md` 寫一條 |
| `/obsidian-adr` | 形式化重大決定 | 一個決定 | `Decisions/ADR-NNN.md` |

新命令的差異化:**唯一 interview user**(其他都是 Claude 讀資料 / 等使用者主動陳述)。

## Tech Stack 與既有 plumbing 重用

- **無新 Python module 需求** — Phase 1 是純 markdown 讀取(用既有的檔案讀 + 簡單 frontmatter 解析),Phase 2-6 是 LLM chat + 寫檔
- 唯一需要新增:`scripts/architect/sections.py` 加 `parse_hypothesis_block`(類似既有 `parse_improvements_block`,但解析 hypothesis shape 含 `assumption / validation / kill_criterion / owner`),與 `compose_brainstorm_note`(類似 `compose_features_note`,把 9 個 block + frontmatter 組起來)
- 重用既有 `_extract_generated_block` / `parse_improvements_block` / `_BLOCK_HEADINGS` / `_BLOCK_NAMES` 結構
- Lang.py 加 9 個新 heading 對應:`## Session context` / `## Opening provocations` / `## Drilled explorations` / `## Distilled improvements` / `## Hypotheses to validate` / `## Parked` / `## Open questions` / `## Meta reflection` / `## Dependencies`

## sections.py 註冊新 section type

```python
SECTION_TYPES["brainstorm"] = "project-brainstorm"

_BLOCK_NAMES["brainstorm"] = (
    "context",
    "opening-provocations",
    "drilled-explorations",
    "distilled-imps",
    "hypotheses",
    "parked",
    "open-questions",
    "meta-reflection",
    "dependencies",
)
```

`compose_brainstorm_note(...)` 接收標準參數 + extra frontmatter:`mode`, `lens-mix`, `depth`, `status`, `session-duration-min`, `provocations-opened/drilled`, `imps-distilled`, `hypotheses-raised`。

## Hypothesis block shape

```markdown
### H1: 客服自助 Rich Menu 能降 ticket 量 30%
- **假設:** LINE Rich Menu 加 5 個自助 FAQ 入口後,客服 ticket 量在 4 週內降 ≥ 30%
- **驗證方式:** 灰度部署到 20% 用戶,4 週後比較對照組 ticket 量
- **kill criterion:** 降幅 < 10% 或客戶滿意度同步下降
- **owner:** [[people/客服 lead]]
- **status:** unvalidated
```

`parse_hypothesis_block` 把上面解成 dict list。已驗證的 hypothesis 由 owner 手動把 status 改 `validated-true` / `validated-false`。

## 排除掉的設計(deliberate non-features)

- ❌ **自動觸發 brainstorm**(例如每週一推) — 本命令是 owner 主動觸發;自動會稀釋訊號
- ❌ **多人協作 brainstorm** — 一個 session 一個 owner
- ❌ **brainstorm 結果自動寫進 features.md** — graduation 必須人手介入
- ❌ **Brainstorm 之間自動連結** — `past_brainstorms` 是 Phase 1 讀取輸入,不是寫進新檔的雙向連結
- ❌ **語音 brainstorm** — 純文字
- ❌ **匯出成簡報** — 留給未來 `/obsidian-export`

## Tests

`tests/architect/test_brainstorm.py`(新增):

1. `test_brainstorm_section_type_present` — `SECTION_TYPES["brainstorm"] == "project-brainstorm"`
2. `test_brainstorm_block_names_v1` — 9 個 block 名稱與順序正確
3. `test_brainstorm_block_headings_registered` — 9 個 heading 都在 `_BLOCK_HEADINGS`
4. `test_parse_hypothesis_block_extracts_fields` — 假設 / 驗證 / kill criterion / owner 都解出
5. `test_parse_hypothesis_block_ignores_non_h3` — 純文字段跳過
6. `test_compose_brainstorm_note_emits_extra_frontmatter` — `mode` / `lens-mix` / `depth` / `provocations-opened` 等都進 frontmatter

`tests/architect/test_lang.py` 加一個:

7. `test_heading_map_includes_brainstorm_keys` — 9 個新 heading zh-TW 對應正確

`tests/roadmap/test_candidates.py` 加兩個:

8. `test_detect_candidates_walks_brainstorms_dir` — `Brainstorms/*.md` 的 `distilled-imps` 被撿
9. `test_detect_candidates_brainstorm_with_actioned_status_skipped` — frontmatter `status: actioned` 的 brainstorm 不再被當 candidate
10. `test_dedup_brainstorm_beats_architecture` — 兩個 candidate 共享 evidence wikilink 時,`source` 含 `Brainstorms/` 者勝

End-to-end:

11. 對 langlive 跑 `/obsidian-brainstorm langlive-line-oa --depth=quick`,驗證:
    - Phase 1 讀到 architecture / features / ai-flows imps + Research(空)+ Logs
    - Phase 2 產出 4-6 個 provocations(混合 lens)
    - Phase 5 寫檔結構正確
    - Phase 6 Hub `## Brainstorms` 區出現

## Open questions resolved

- **Q: 為什麼選 "每次 session 一個 timestamp 檔" 而不是 append 到單一 `Insights.md`?**
  A: 保留 per-session frontmatter(mood / depth / lens mix)+ 對話脈絡;graduate 時容易抽單一 session 不污染 history
- **Q: provocation 數量為什麼是 4-6 個?**
  A: 4 個能覆蓋 4 個 lens 各 1 個;6 個是上限避免使用者 overwhelm(認知負擔測試)。實際數量讓 Claude 依 vault 訊號豐富度動態調整
- **Q: brainstorm-imp 在 roadmap 怎麼贏過 architecture-imp?**
  A: dedup pass 偏好 `Brainstorms/` source — 因為 user-confirmed > Claude-inferred
- **Q: 三態 confidence(speculation / hypothesis / stated)為什麼這樣切?**
  A: 對應到 `roadmap candidate priority`:stated → normal,hypothesis/speculation → low。讓 owner 一眼分辨「該做的」與「該驗證的」

## Out of scope (deferred)

- **`--mode=sharpen` (對既有想法 sharpen)** — frontmatter 留欄位,但本 release 不實作;未來 v2
- **Brainstorm 結果可視化** — graph view 跨 session 看主題演化,留給 `/obsidian-visualize`
- **`/obsidian-graduate` 接 Brainstorm → Architecture/decisions 的自動化** — 未來增強;v1 必須人手 promote

## Success criteria

設計完成的條件:

- [x] 使用者確認 mode = "Brainstorm 生成"
- [x] 使用者確認輸出位置 = `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`
- [x] 使用者確認開場節奏 = 一次性丟 4-6 個 provocations
- [ ] Spec self-review pass
- [ ] User reviews this spec
- [ ] Implementation plan via `writing-plans` skill
- [ ] Implementation lands;langlive smoke 跑得通
