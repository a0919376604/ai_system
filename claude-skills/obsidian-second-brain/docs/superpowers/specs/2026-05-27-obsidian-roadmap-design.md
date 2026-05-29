# obsidian-roadmap — Design Spec

**日期:** 2026-05-27
**狀態:** Draft — 等 user sign-off,之後進 writing-plans
**Branch:** TBD (建議 `feat/obsidian-roadmap`)
**Layer:** Layer 2 (Thinking tools) — synthesis 介於 architect (Layer 1 vault ops) 與 task/board (Layer 2)
**參考:** [eyaltoledano/claude-task-master](https://github.com/eyaltoledano/claude-task-master) (PRD → tasks 模式;我們不直接套用,參考其「AI 解析 → 階層 tasks」概念)
**前置依賴:**
- `/obsidian-architect` 已產出 `Projects/<P>/Architecture/` (本 spec 在 [2026-05-27-obsidian-architect-narrative-design.md](2026-05-27-obsidian-architect-narrative-design.md) 上層)
- `/research-deep` 持續寫 `Research/Deep/` 或 `Projects/<P>/Research/`
- 既有 `/obsidian-task` (T-NNN-slug schema)、`/obsidian-board` (board.md kanban)、`/obsidian-graduate` (Idea → Project)

---

## 1. 動機

目前 vault 有「**累積的知識**」(Research/、Architecture/future.md、Architecture/decisions.md 的 Promote-to-ADR、TODO 群組) 跟「**執行層**」(board.md、Tasks/T-*.md),但缺**中間的策略合成層**。後果:

- 跑完 `/obsidian-architect`,future.md 條列「應該做但還沒做」的事,沒人撿。
- 平日 `/research-deep` 抓的競品/技術調研堆在 Research/Deep/,跟 project gap 沒連起來。
- board.md `## 待辦` 是 0 個 (langlive-line-oa 現況),所有 backlog 留在腦中。

本命令把這三類訊號 (architect gaps + 兩種 research + decisions) 合成成「**Roadmap 主題**」,每個主題對應幾個原子 task,讓 backlog 從隱式變顯式。

不是 task-master 的「PRD in → tasks out」單向流。這是「**已累積的 vault 知識 → 浮現 backlog**」的雙來源融合。

---

## 2. 目標

1. **三層分離。** Architecture 訊號 (descriptive,signal-derived) → `Projects/<P>/Roadmap.md` (prescriptive,curated) → `Tasks/T-*.md` (atomic execution)。
2. **雙來源融合。** 同時吃 architect 信號 (gap / future / decisions) 與 research 累積 (兩階段匹配:keyword prefilter + LLM relevance check)。
3. **Batch review。** Phase 4 給 user 一個 markdown 表格,inline 標記 keep/edit/drop/merge,paste 回來。同步 review,非 plan-mode,跨 adapter 工作。
4. **三 phase 寫入。** Phase 5 寫 `Roadmap.md` + 多個 `Tasks/T-*.md` + append `board.md` cards — 三者一致更新。
5. **Idempotent + refresh-friendly。** 用 `_roadmap.lock.json` 追蹤已 materialize 內容;re-run 識別新 candidate vs 已存在 vs stale。
6. **單一 project per run。** v1 不做跨 project synthesis。
7. **Lang-aware。** 尊重 vault `_CLAUDE.md` `output-lang`;繁中模式下 Roadmap.md heading 跟散文都繁中,task slug 跟 code identifier 保持英文。
8. **Read-only on Architecture/ + Research/。** 本命令不會改架構文件或 research note。

---

## 3. 不做的事

- **不做跨 project synthesis。** Vault-wide / weekly review 留給未來。
- **不做 task 之間的 dependency graph。** 想要的話 user 在 task body 寫「blocked by [[T-005]]」即可。
- **不做精算 effort。** 只給 S/M/L/XL 粗估,人類調。
- **不做自動 scheduling / sprint planning。** Roadmap.md 不分 sprint。
- **不整合 Ideas/ folder。** v2 再看。
- **不修 /research-deep。** 本命令只 read。`--for-project=<P>` flag 加在 research-deep 上是另一個 spec 的事。
- **不破壞既有 Tasks/ + board.md schema。** Phase 5 寫的 T-*.md 與 `/obsidian-task` 寫的 schema 一致;board cards 用相同格式。
- **不重新 train 任何 model。** 純 LLM call + 確定性 helper。

---

## 4. 輸出 layout

```
Projects/langlive-line-oa/
├── Roadmap.md                # 🆕 NEW — 此命令唯一新建檔。策略主題的 curated 視圖。
├── _roadmap.lock.json        # 🆕 NEW — 內部 lockfile,追蹤 theme + task materialization。
├── Architecture/             # 既有,read-only by this command
│   ├── future.md             # ← gap 主訊號
│   ├── roadmap.md            # ← TODO cluster 訊號
│   ├── decisions.md          # ← Promote-to-ADR 候選
│   └── ...
├── Research/                 # 既有,read-only
│   └── 2026-05-15-foo.md     # /research-deep --project=... 寫的
├── Tasks/                    # 既有 schema
│   ├── T-001-<slug>.md       # 🔁 命令新增 T-NNN-slug 檔
│   ├── T-002-<slug>.md
│   └── ...
└── board.md                  # 🔁 命令 append `## 待辦` cards (帶 roadmap-theme label)

外部 (vault root) — read-only signal source:
~/Documents/SecondBrain/Research/
├── Deep/2026-05-*.md         # ambient research-deep 累積
└── Web/2026-05-*.md
```

---

## 5. 新 type values (進 `references/ai-first-rules.md`)

### 5.1 `type: roadmap`

位置:`Projects/<P>/Roadmap.md` (project-level,跟既有 `type: architecture-roadmap` 的 `Architecture/roadmap.md` **刻意不同**)。

必要 frontmatter:
- `type: roadmap`
- `date`、`updated`、`project` (wikilink)
- `lang: zh-TW | en`
- `tags: [roadmap, <project-name>]`
- `ai-first: true`
- `status: active | frozen | archived`
- `last-synthesis: YYYY-MM-DD` (上次 /obsidian-roadmap 跑的日期)
- `themes-count`、`tasks-count` (摘要數字,query-friendly)

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude` — preamble:「這是 curated roadmap。策略主題 → tasks 分解。Signal 來源見每個主題的 evidence。」
- `## 本次合成摘要` (zh-TW) / `## Synthesis summary` — N themes、N tasks、跑了哪些 signal source、哪些 research 被引用
- `## 主題` (zh-TW) / `## Themes` — 對每個主題一個 H3 sub-section:
  ```markdown
  ### 🔴 AI 引擎可插拔化
  **為什麼:** 目前只支援 LangGraph (見 [[modules/backend]]);AGENTS.md 提 pluggable engine 但未落實。
  **Evidence:**
  - [[Architecture/future#期望中的想法]] 第 1 點
  - [[Projects/langlive-line-oa/Research/2026-05-15-engine-comparison]]
  **Effort:** M
  **Tasks:**
  - [[Tasks/T-001-add-engine-adapter-base|T-001 加 EngineAdapter base class]]
  - [[Tasks/T-002-port-langgraph-as-adapter|T-002 把 LangGraph 改為 LangGraphAdapter]]
  - [[Tasks/T-003-engine-registry|T-003 加 EngineRegistry config]]
  - [[Tasks/T-004-engine-switch-integration-test|T-004 切換 engine 整合測試]]
  ```
- `## Stale` (zh-TW: `## 過時主題`) — 之前 materialize 過但本次 re-run 信號消失的主題。標 `status: stale`,不刪。
- `## Related` / `## 相關` — `[[<P>]]`、`[[Architecture/overview]]`、`[[board]]`

整篇是 sentinel-aware,`## 本次合成摘要` 跟 `## 主題` 包在 `@generated`;`@user` 區可放 user 手工加的策略註解。

### 5.2 對既有 type 的影響

- `type: task` (既有) **不改 schema**。Phase 5 寫的 T-*.md 用既有欄位,但 frontmatter 多加可選欄位 `roadmap-theme: "<theme-slug>"` 連回 Roadmap.md。檢查 `/obsidian-task` 是否會誤刪 — 不會 (它 append,不 normalize)。
- `type: board` (既有) **不改 schema**。Phase 5 append cards 時用既有格式,但 card 後面加 ` [theme: <theme-slug>]` 標記。
- `type: architecture-future` / `architecture-roadmap` / `architecture-decisions` — **不變**,本命令只 read。

---

## 6. Lockfile schema

`Projects/<P>/_roadmap.lock.json`:

```json
{
  "schema-version": 1,
  "last-synthesis": "2026-05-27T19:30:00Z",
  "last-architect-commit": "344e321",
  "themes": {
    "ai-engine-pluggability": {
      "title": "AI 引擎可插拔化",
      "first-materialized": "2026-05-27T...",
      "last-refreshed": "2026-05-27T...",
      "signal-source-hash": "sha256:...",
      "tasks": ["T-001", "T-002", "T-003", "T-004"],
      "status": "active"
    }
  },
  "tasks": {
    "T-001": {
      "theme": "ai-engine-pluggability",
      "created": "2026-05-27T...",
      "slug": "add-engine-adapter-base"
    }
  },
  "next-task-id": 5
}
```

Re-run 行為:
- 對每個新 candidate theme,算 signal-hash (gap + research links 序列化的 SHA256)。若 hash 跟 lockfile 對得上某 theme → SKIP (已存在,沒變)。
- 若 hash 變 → 標 `needs-refresh`,review 階段顯示
- 若 lockfile 有但本次 signal 找不到對應 → 標 `stale`,在 Roadmap.md `## 過時主題` 顯示

---

## 7. Pipeline 詳述

### Phase 1:Gap detection (deterministic)

Read these vault files in this order, extracting candidates:

1. `Projects/<P>/Architecture/future.md`:
   - `## 落差分析` / `## Gap analysis` 的每個 bullet → candidate kind=`gap`
   - `## 已知限制` / `## Known limitations` 的每個 bullet → candidate kind=`limitation`
   - `## 期望中的想法` / `## Aspirational ideas` 的每個 bullet → candidate kind=`aspiration`

2. `Projects/<P>/Architecture/decisions.md`:
   - `## 建議升級為 ADR` / `## Promote to ADR` 的每個編號項目 → candidate kind=`promote-to-adr`

3. `Projects/<P>/Architecture/roadmap.md`:
   - `## TODO 群組` 內 frequency >= 2 的 TODO cluster → candidate kind=`todo-cluster`

Each candidate carries `{title, source-wikilink, source-line-anchor, kind, raw-text}`.

Dedup by normalizing title (lowercase + strip emoji + strip 「、」punctuation).

Output: `/tmp/roadmap-<hash>/candidates.json`

### Phase 2:Research linking (deterministic + LLM hybrid)

**2a — Keyword extraction (LLM, batch):**
One LLM call passes all `N` candidate raw-texts, asks: "for each, return 3-5 short keywords (zh-TW or en, whatever matches the text)". Returns `[{candidate-id, keywords: [...]}]`.

**2b — Keyword prefilter (deterministic):**
For each candidate, grep:
- `Projects/<P>/Research/**/*.md`
- `Research/Deep/**/*.md` (last 30 days by mtime)
- `Research/Web/**/*.md` (last 30 days by mtime)

Match if any keyword appears in research note's `topic`, frontmatter `tags`, OR file body. Collect matching research note paths (≤ 10 per candidate to bound LLM cost downstream).

**2c — LLM relevance check (batch):**
For each candidate with N≥1 research matches, one LLM call: gives candidate raw-text + each match's `## Summary` block (max ~5k tokens per match), asks "which matches are genuinely relevant to this candidate? Return JSON `{candidate-id: [relevant-research-wikilink, ...]}`". Drops irrelevant matches.

Output: `/tmp/roadmap-<hash>/linked-candidates.json` with `{candidate-id, evidence: [wikilink, ...]}`.

### Phase 3:Theme synthesis (LLM, single call)

One LLM call:
- Input: linked-candidates.json + `Projects/<P>/Architecture/overview.md` (the MOC, for context) + module manifest (slugs + descriptions)
- Output: JSON of 6-12 themes, each with **fully-specified tasks** (Phase 5 is then purely deterministic):
  ```json
  [{
    "slug": "ai-engine-pluggability",
    "title": "AI 引擎可插拔化",
    "why": "...",
    "priority": "🔴",
    "effort": "M",
    "evidence": ["[[Architecture/future#期望中的想法]] 第 1 點", "[[Projects/<P>/Research/...]]"],
    "candidate-ids": ["gap-3", "promote-to-adr-1"],
    "tasks": [
      {
        "description": "在 backend/engines/ 加 EngineAdapter base class",
        "slug": "add-engine-adapter-base",
        "module-wikilink": "[[modules/backend]]",
        "acceptance-criteria": [
          "`backend/engines/adapter.py` 有 `EngineAdapter` ABC,定義 `chat()` 跟 `stream()`",
          "既有 LangGraph 實作可以 import 並 instantiate 為 adapter (不算 break)"
        ]
      },
      {
        "description": "把 LangGraph 實作改寫為 LangGraphAdapter",
        "slug": "port-langgraph-as-adapter",
        "module-wikilink": "[[modules/backend]]",
        "acceptance-criteria": [
          "原有 langgraph engine 邏輯不動,只包一層 adapter",
          "整合測試通過"
        ]
      }
    ]
  }]
  ```
- LLM 負責產 English-friendly `slug` (檔名用,lowercase + hyphen)。Prompt 範例:「task slug 必須 ascii lowercase + hyphen-separated + ≤ 50 chars + 動詞起頭,例:`add-engine-adapter-base`、`refresh-token-rotation`」。
- Prompt rules: prose zh-TW (lang-aware), task descriptions short (`<` 80 chars,動詞起頭), evidence wikilinks 必須只引用實際存在的 path/anchor。

Output: `/tmp/roadmap-<hash>/themes.json`

### Phase 4:Batch review (sync)

Command body prints a markdown table to the agent's conversation:

```markdown
| # | Action | 主題 | Priority | Effort | Evidence | Tasks |
|---|---|---|---|---|---|---|
| 1 | __ | AI 引擎可插拔化 | 🔴 | M | 2 | 4 |
| 2 | __ | 觀測性補強 (logging + metrics) | 🟡 | M | 3 | 3 |
| 3 | __ | 後台帳號權限 fine-grained | 🟡 | L | 1 | 5 |
...
```

Plus full detail per theme below the table.

User edits the `Action` column inline + pastes back. Allowed values:
- `K` (keep as proposed)
- `D` (drop)
- `M:<other-#>` (merge into theme <other-#>)
- `E` (edit — user provides edited JSON inline below)
- 空欄 = treated as K (default keep)

Claude parses the response. If user provides edits, validates them (slug 唯一、task count ≥ 1)。Loops back with "請確認" 一次最後核對。

### Phase 5:Materialize (deterministic + lockfile update)

For each approved theme — **fully deterministic, no LLM call**:

1. Allocate task IDs from `lockfile.next-task-id`, increment per task.
2. For each task in theme.tasks (LLM in Phase 3 already produced `{description, slug, module-wikilink, acceptance-criteria}`):
   - Use `T-<NNN>-<slug>` (slug is verbatim from Phase 3 output).
   - Validate slug: ascii lowercase + hyphen, ≤ 50 chars. If invalid, fallback to `re.sub(r"[^a-z0-9-]", "-", desc[:50].lower()).strip("-")`.
   - Write `Projects/<P>/Tasks/T-<NNN>-<slug>.md` using `/obsidian-task` schema. Frontmatter additions:
     - `roadmap-theme: "<theme-slug>"`
     - `created-by: "obsidian-roadmap"`
   - Body (assembled from Phase 3 LLM output + deterministic template):
     - `## 給未來 Claude` preamble: 1-2 sentences from task.description + theme context wikilink
     - `## 接受條件` (zh-TW) / `## Acceptance criteria` — `task.acceptance-criteria` bullets verbatim
     - `## 相關`: `[[Roadmap]]`、`[[<theme>]]` (anchor to Roadmap.md heading)、`task.module-wikilink`
3. Compose `Projects/<P>/Roadmap.md` with all kept themes (and update Stale section).
4. Append cards to `Projects/<P>/board.md` `## 待辦` section:
   ```markdown
   - [ ] [[Tasks/T-001-add-engine-adapter-base|加 EngineAdapter base class]] 🔴 [theme: ai-engine-pluggability]
   ```
5. Update `_roadmap.lock.json`.
6. Append daily log entry: `**HH:MM** - roadmap | <P> - synthesized N themes (K new, M refreshed) → N+K tasks`.

---

## 8. Edge cases

| 條件 | 行為 |
|---|---|
| `Architecture/future.md` 不存在 | abort,訊息:`先跑 /obsidian-architect <repo>` |
| Architecture 都有但全部段 `status: insufficient-signal` | Phase 1 候選清單為空 → 進 Phase 2 也是空 → 提早結束,訊息「無候選 — Architecture 訊號不足,建議補 README Limitations / Future Work 段後重跑」 |
| Phase 2 沒任何 research 匹配 | 不阻擋。Phase 3 主題 evidence 區只含 architect wikilinks。標記 `evidence-strength: architect-only` 在主題 frontmatter |
| Phase 4 user paste 回來格式錯 | Claude 顯示「無法 parse 第 N 行」,請 user 重 paste。最多 retry 3 次後 abort |
| Phase 5 寫某 T-*.md 失敗 (e.g. disk full) | rollback 該 theme 的所有 task 寫入 + 不更新 lockfile 該 theme;其他 theme 繼續 |
| `_roadmap.lock.json` schema 不認識 (未來 v2) | 標 schema-version mismatch,abort,提示 user 升 skill |
| user 手動刪了某 T-*.md 但 lockfile 還有 | 下次 re-run 偵測 file 缺,標 `materialize-broken`,問 user 是否 re-create 或從 lockfile 移除 |
| 兩個 theme slug 撞名 | Phase 3 LLM 輸出後 deduplicate,後者加 `-2` 後綴 |

---

## 9. Command flags

```bash
/obsidian-roadmap <project-name>
```

Optional flags:
- `--dry-run` — Phase 1-3 跑完輸出 themes.json,不進 Phase 4。
- `--force` — 忽略 lockfile,所有 theme 視為新候選。
- `--only-themes=<n>` — Phase 3 限制最多 N 個 theme (default: 12)。
- `--skip-research` — Phase 2 跳過,只用 architect 訊號 (快速試)。
- `--lang=<en|zh-TW>` — 覆蓋 vault `_CLAUDE.md output-lang`。
- `--scope-research-days=<n>` — Phase 2b 取最近 N 天 vault research (default: 30)。

省略 `<project-name>` 時:若 pwd 在 `Projects/<P>/` 內,default 該 project;否則 ASK user 哪一個。

---

## 10. 檔案改動清單

| 檔 | 改動 |
|---|---|
| `commands/obsidian-roadmap.md` (新) | 命令 body + 5 phase 流程描述 + flag 文件 |
| `references/ai-first-rules.md` | 加 `type: roadmap` schema + `task.roadmap-theme` 可選欄位文件 |
| `scripts/roadmap_synth.py` (新) | CLI entry,類似 `architect_scan.py` 模式 — orchestrate Phase 1+2 deterministic part |
| `scripts/roadmap/__init__.py` (新) | package |
| `scripts/roadmap/candidates.py` (新) | Phase 1 — gap detection from architect files |
| `scripts/roadmap/research_match.py` (新) | Phase 2 — keyword extraction + prefilter + (output for) LLM relevance |
| `scripts/roadmap/lockfile.py` (新) | `_roadmap.lock.json` read/write + schema validation + theme/task tracking |
| `scripts/roadmap/render.py` (新) | Roadmap.md composer,task note composer,board card formatter |
| `scripts/roadmap/parser.py` (新) | Parse user's review-table response into actions |
| `scripts/architect/lang.py` | 加 heading 對照:`## 主題`、`## 過時主題`、`## 本次合成摘要`、`## 接受條件` |
| `tests/roadmap/test_candidates.py` (新) | Phase 1 detector tests |
| `tests/roadmap/test_research_match.py` (新) | Phase 2 keyword + prefilter tests |
| `tests/roadmap/test_lockfile.py` (新) | lockfile schema tests |
| `tests/roadmap/test_render.py` (新) | renderers tests (Roadmap.md, task, board card) |
| `tests/roadmap/test_parser.py` (新) | review parser tests (好/壞 paste case) |
| `CHANGELOG.md` | 加 entry |
| `SKILL.md` | Layer 2 加 `/obsidian-roadmap` 描述 |
| `README.md` | commands table 加一行 |

---

## 11. Trade-offs 我有意識的點

- **5 phase 比較重 + Phase 4 同步等 user。** Mitigation:5 個 phase 各有 `--only-phase=N` 開關,可獨立除錯;Phase 4 paste 機制簡單;若 user 喜歡 plan mode 之後可加 `--review-mode=plan` flag。
- **`Roadmap.md` 跟 `Architecture/roadmap.md` 名字撞。** 刻意。Roadmap.md (project-level, prescriptive) 跟 Architecture/roadmap.md (signal-derived, descriptive)。Roadmap.md 在 evidence 區會 wikilink 指 Architecture/roadmap.md,反向不會。
- **不修 /research-deep。** v1 read-only,research 沒有 `--for-project=<P>` flag,只能靠 30 天 mtime + keyword 抓 ambient research。會漏一些。v2 應該加 research-deep 的 routing flag,訊號才會準。本 spec 不處理。
- **Lockfile 跟 Architecture lockfile 名字不一樣 (architect 用 `_manifest.lock.json`,roadmap 用 `_roadmap.lock.json`)。** 刻意分開,生命週期不一樣。
- **Task slug 用英文 / pinyin-less transliteration。** 因為要當檔名 + wikilink + grep target。若 user 不喜歡可以手動 rename 但會破 lockfile mapping (lockfile 用 task-id 不用 slug,所以實際上 OK)。
- **Theme priority/effort 是 LLM 拍腦袋給的。** 不精準。User 在 review 階段可改;但長期應該根據 task 完成歷史校準 (v2 idea)。

---

## 12. 驗收條件

跑 `/obsidian-roadmap langlive-line-oa` 對代表性 project 應該滿足:

- [ ] Phase 1:從 Architecture/future.md + decisions.md + roadmap.md 抓出 ≥3 候選
- [ ] Phase 2:對至少 1 個候選找到 ≥1 個 research 匹配並通過 LLM relevance
- [ ] Phase 3:輸出 6-12 個 theme,每個 `evidence` 至少含 1 個 wikilink
- [ ] Phase 4:user 用 K/D/M/E paste 回來,Claude 正確 parse (含「全部 K」case)
- [ ] Phase 5:寫出 `Projects/<P>/Roadmap.md` (新),N 個 `Tasks/T-NNN-*.md`,append `board.md` 對應 cards
- [ ] `_roadmap.lock.json` 寫入,內容含每個 theme 的 signal-hash 跟 tasks list
- [ ] Re-run with no source change → 零修改 (所有 theme signal hash 對得上 → SKIP)
- [ ] Re-run with `--force` → 每個 theme 視為 needs-refresh,進 review
- [ ] `--skip-research` → Phase 2 skip,Roadmap.md 主題 evidence 區只含 architect wikilinks,標 `evidence-strength: architect-only`
- [ ] `--lang=zh-TW` (或 vault 設定) → Roadmap.md / task notes heading 都繁中,code identifier (T-NNN-slug、檔名) 保英文
- [ ] 全測試通過 (`uv run pytest tests/roadmap/`)
- [ ] Adapter build 通過 (`bash scripts/build.sh`),四個 platform 都產出

---

## 13. 開放問題

- 無。本 brainstorm 階段定的:
  - Scope: single project per run — 已核准
  - Layers: Architecture → Roadmap.md → Tasks — 已核准
  - Research scope: project + recent vault-wide,兩階段匹配 — 已核准
  - Review mode: batch paste-back — 已核准
  - Surface: 新命令 `/obsidian-roadmap` — 已核准
