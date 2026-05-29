# obsidian-architect 敘事化升級 — Design Spec

**日期:** 2026-05-27
**狀態:** Draft — 等 user sign-off,之後進 writing-plans
**Branch:** TBD (建議 `feat/architect-narrative`)
**部分取代:** `2026-05-26-obsidian-architect-design.md` (v1 設計 — folder layout、manifest pipeline、sentinel refresh 保留;output surface 擴充)
**參考:** [project-to-obsidian-1](https://mcpmarket.com/zh/tools/skills/project-to-obsidian-1) (MOC 風格、API surface 提取、function-level deep notes 概念)
**Layer:** Layer 1 (Vault Operations)

---

## 1. 動機 (為什麼要改)

v1 的 `/obsidian-architect` 提供了 deterministic scanner 加 per-module synthesis。實際 dogfood 後痛點是 **「工程師視角,沒產品故事」**。未來的 Claude 讀 `Architecture/overview.md` 加 `modules/` 拿到的是 file tree、dependency graph、per-module 的「做什麼」段落,但永遠學不到:

- **這 codebase 對 user 究竟做了什麼** (capability、CLI/HTTP surface、public API)
- **它要往哪去** (CHANGELOG Unreleased、README roadmap、TODO 群組)
- **為什麼長這樣** (核心 tech decision、stack 選擇、ADR)
- **缺什麼** (gap、north-star、limitation)

參考 skill `project-to-obsidian` 展示了缺的 pattern:MOC 風格的 overview、結構化的 API surface 參考表、選擇性的 function-level deep note、frontmatter 顯式標 stack。

本 spec **保留 v1 pipeline** (Phase 1 scan、Phase 2 manifest review、Phase 3 per-module、lockfile、sentinel、refresh 保留 user 編輯),**新增** 4 個敘事段落 + 1 個 API surface 參考 + 1 個可選 function 層、MOC 化的 overview、顯式 stack metadata。

---

## 2. 目標

1. **結構之上加敘事。** 同一個指令額外產出 `features.md`、`roadmap.md`、`decisions.md`、`future.md`、`api-surface.md`,與既有的 `overview.md`、`data-flow.md`、`modules/` 並存。
2. **Overview 變成 MOC。** `overview.md` 帶 elevator pitch、stack frontmatter、wikilinks;內容下放給 deep note。未來 Claude 要 grep 某一段絕不需要掃整個 architecture。
3. **Section 各自獨立 refresh。** 每個敘事 note 有自己的 `@generated` sentinel block,自己的 source signal hash diff。roadmap 變了不會讓 features regenerate。
4. **只用 local 訊號。** 來源限定 README、CHANGELOG、docs/、source code、git log、TODO/FIXME 聚合、ADR 檔、package metadata。不打 GitHub API、不需 auth、離線可跑。
5. **缺訊號要透明,不能幻覺。** 某段沒 signal 時,note 仍寫出 (讓 wikilink 解得到),但 body 講清楚、frontmatter 標 `confidence: low` 或 `status: insufficient-signal`,絕不編造 roadmap。
6. **Function-level 是 opt-in。** `--functions=public` flag 才產 `Architecture/functions/<module>/<func>.md`。預設關 (YAGNI)。只挑 public surface:出現在 `__all__`、default export、CLI handler、route handler 的符號。
7. **跨 adapter 相容。** 指令文字保持 platform-neutral。新 `type:` 值寫進 `references/ai-first-rules.md`。
8. **輸出語言可配置。** Vault 層級可設 `output-lang: zh-TW`,architect 寫進 vault 的所有 note 散文、heading 用繁中,但 code identifier (module slug、function name、import path、檔名) 跟機讀 schema (frontmatter key、enum value、sentinel) 維持英文。`--lang=` flag 可單次覆蓋。

---

## 3. 不做的事

- **不整合 GitHub / Linear / Notion。** v1 只用 local 檔。跨來源整合留給後續。
- **不做自動 refresh / 排程 agent。** 跟 v1 一樣,user 手動觸發。
- **Function-level 預設不做。** 除非每次明確 opt-in。
- **不用 LLM 純推 stack。** Stack frontmatter 是 best-effort 從 package metadata 抽。不確定就略,不猜。
- **不重做 v1。** Phase 1 scan、manifest、lockfile、sentinel、per-module pipeline、hub note 區塊 — 全保留。本 spec 是 additive。
- **不在 `Architecture/` 之外新增 note type。** `Decisions/`、`Ideas/` hub folder 不動。`Architecture/decisions.md` 是 synthesis index;要升級成正式 ADR 仍走 `/obsidian-adr`。

---

## 4. 最終 Output layout

```
Projects/<P>/Architecture/
├── overview.md            # 改:MOC 風格,stack frontmatter,內容下放
├── features.md            # 新:capability 敘事,連到 api-surface
├── api-surface.md         # 新:CLI / HTTP / exports / env 結構化表
├── roadmap.md             # 新:從 CHANGELOG / README / TODOs 合成
├── decisions.md           # 新:key technical decision 索引 (synthesis,非完整 ADR)
├── future.md              # 新:gap、north-star、limitation、未實作的提及
├── data-flow.md           # 不動:可選 Mermaid sequence
├── functions/             # 新,可選:--functions=public 才有
│   └── <module-slug>/
│       └── <function>.md
├── modules/<slug>.md      # 不動
├── _manifest.yml          # 不動
└── _manifest.lock.json    # 擴充:也追蹤 section-level hash
```

---

## 5. 新 `type:` 值 (加到 `references/ai-first-rules.md`)

每個都遵守 AI-first 契約:`## For future Claude` preamble、`ai-first: true`、project wikilink、`last-scanned`、`commit`、`tags`、sentinel 包住的 `@generated` block、有合成成分的加 `confidence` 欄位。

### 5.1 `type: architecture-features`

位置:`Projects/<P>/Architecture/features.md`。

必要 frontmatter:`type`、`date`、`project`、`repo`、`last-scanned`、`commit`、`sources` (實際讀的檔的 list)、`confidence: high | medium | low`、`tags: [architecture, features]`、`ai-first: true`、`status: current | insufficient-signal | scan-failed`。

Body section 順序:`## For future Claude`、`## Summary` (1-2 句)、`## Capability map` (依群組列 bullet,wikilink 到 [[api-surface]] 跟 [[modules/<slug>]])、`## Notable details` (bullet 塞不下的補充,可選)、`## Related`。

### 5.2 `type: architecture-roadmap`

位置:`Projects/<P>/Architecture/roadmap.md`。

Frontmatter 同 features 形狀,`tags: [architecture, roadmap]`。`confidence: stated` 如果 CHANGELOG/README 明說、`medium` 如果是 TODO 外推、`low` 如果沒 signal。

Body section:`## For future Claude`、`## Summary`、`## Near term` (CHANGELOG Unreleased + README "Coming Soon")、`## Trajectory` (近 3 版 CHANGELOG,動向)、`## TODO clusters` (按 module 群組過的 TODO,僅當有意義時呈現)、`## Signals reviewed` (透明列出實際解析的檔)、`## Related`。

### 5.3 `type: architecture-decisions`

位置:`Projects/<P>/Architecture/decisions.md`。

Frontmatter 同形狀,`tags: [architecture, decisions]`。`confidence` 是 per-bullet 標的,所以文件層級的 `confidence` 取所有明確 decision 的最低值。

Body section:`## For future Claude`、`## Stack rationale` (每個 top-level tech 一個 bullet,帶 `(stated | inferred)` 標記跟來源)、`## Detected ADRs` (連到 `docs/adr/**` 既有檔,每個一句綜述)、`## Pattern decisions` (scanner 偵測到的架構 pattern — adapter、plugin、repository、event-sourced 等,每個 `(inferred from X)`)、`## Commit-message decisions` (commit message 中記錄了明確選擇的高信號訊息)、`## Promote to ADR` (建議跑 `/obsidian-adr` 的清單)、`## Related`。

### 5.4 `type: architecture-future`

位置:`Projects/<P>/Architecture/future.md`。

同形狀,`tags: [architecture, future]`。`confidence: speculation` 是預設;只有 README 明確「Future Work」/「Limitations」段為來源時才能升 `stated`。

Body section:`## For future Claude`、`## Summary`、`## Known limitations` (從 README + module 的 `scan-truncated`)、`## Gap analysis` (README 提到但 scanner 在 code 中找不到的能力)、`## Aspirational ideas` (TODOs 標 `future:` / `idea:`,以及高頻 TODO 群組但 roadmap 沒列的)、`## Related`。

### 5.5 `type: architecture-api-surface`

位置:`Projects/<P>/Architecture/api-surface.md`。

必要 frontmatter:同形狀,`tags: [architecture, api-surface]`,加 `detection-status: complete | partial | none` 標 scanner 對 surface 提取的信心。

Body section:`## For future Claude`、`## CLI commands` (表:Command / Description / Source / Module wikilink)、`## HTTP routes` (表:Method / Path / Handler / Module)、`## Public exports` (表:Symbol / Kind / Source / Module)、`## Environment variables` (表:Var / Required / Default / Used by)、`## Related`。空表略,不留空欄。

### 5.6 `type: architecture-function` (可選層)

位置:`Projects/<P>/Architecture/functions/<module-slug>/<func-slug>.md`。

僅在傳 `--functions=public` 時產生。資格規則:
- 符號出現在 `__all__` (Python) 或為 named / default export (JS/TS/Go)
- 符號註冊為 CLI subcommand handler (argparse subparser / click group / cobra command)
- 符號註冊為 route handler (FastAPI route decorator / Express handler / Next.js page)
- 資格判斷邏輯在 `scripts/architect/public_surface.py`

必要 frontmatter:`type: architecture-function`、`date`、`project`、`repo`、`module-slug` (父 module)、`display-name`、`signature`、`source-file`、`line-range`、`last-scanned`、`commit`、`tags: [architecture, function]`、`ai-first: true`、`status: current | deprecated`。

Body section:`## For future Claude`、`## Signature` (verbatim code block)、`## What it does` (1-2 句合成)、`## Inputs and outputs`、`## Behavior notes` (side effect、error path、code 中可見的 edge case)、`## Callers` (自動偵測 uplink 到其他 function / module)、`## Related`。

### 5.7 Overview frontmatter 擴充

`type: architecture-overview` 維持既有 shape,新增可選的 `moc-style: true` 跟 `stack` 區塊:

```yaml
stack:
  primary-language: TypeScript
  frameworks: [Next.js 14, Prisma 5, tRPC]
  build: pnpm + turbo
  test: vitest
  deploy: Vercel
```

Stack 偵測是 best-effort。Scanner 沒把握的欄位略過 (絕不猜)。來源:`package.json`、`pyproject.toml`、`Cargo.toml`、`go.mod`、`Gemfile`,加上 root config 檔 (`next.config.js`、`vite.config.ts`、`turbo.json` 等)。**不請 LLM 推 stack。**

---

## 6. Source signal 對照表

Per-section 的 signal 收集在 Phase 1 (scanner) 完成,寫進 `scan-report.json`。Phase 3.5 的合成器只讀自己這段需要的。

| Section | Signals |
|---|---|
| **features.md** | README 的 "Features" / "Capabilities" 段;從 `api-surface.md` 來的 CLI 命令清單;從 `api-surface.md` 來的 HTTP route;module manifest `description` 欄;`docs/` 頂層檔 |
| **api-surface.md** | argparse / click / typer / cobra / oclif / commander 的 CLI parser;FastAPI / Flask / Express / Next.js / Gin route decorator;`__all__`、`module.exports`、`index.{js,ts}` 的 named/default export;`os.getenv` / `process.env` / `Deno.env` 呼叫 |
| **roadmap.md** | `CHANGELOG.md` Unreleased + 最近 3 個版本區塊;README "Roadmap" / "Coming Soon" 段;按 module + 頻率聚合的 TODO;近 90 天 commit message 帶 `next:`、`wip:`、`plan:` 前綴的 |
| **decisions.md** | `docs/adr/**`、`docs/decisions/**`、`architecture/decisions/**` 檔;ARCHITECTURE.md / DESIGN.md;package metadata 的主要 dependencies;commit message 含 "decided"、"chose"、"switched from"、"moved to"、"replaced X with Y" 模式;從 module manifest 偵測到的架構 pattern (adapter、plugin、repository) |
| **future.md** | 按 module + label 聚合的 TODO/FIXME (`future:`、`idea:`、`someday:`);README "Limitations" / "Known Issues" / "Future Work" 段;README 提到但 `api-surface.md` 沒偵測到的能力;標 `scan-truncated: true` 的 module |

---

## 7. Pipeline

在 v1 的 Phase 3 (per-module) 跟 Phase 4 (overview) 之間插入 Phase 3.5。

```
Phase 1: Deterministic scan
   - 既有 repo walk、manifest proposal、scan-report.json
   - 新:收集 README section、CHANGELOG 區塊、TODO 聚合、
        ADR 發現、stack 偵測、API surface 提取
   - 輸出:/tmp/architect-<hash>/scan-report.json (擴充 schema)

Phase 2: Manifest review (不動)

Phase 3: Per-module synthesis (不動)

Phase 3.5 (新): Per-section synthesis
   順序 (每步是獨立 LLM call,只給對應 context):
     a. api-surface.md       - deterministic 優先;LLM 只摘 description
     b. features.md          - 吃 api-surface + module manifest + README
     c. decisions.md         - 吃 ADR + ARCHITECTURE.md + deps + commits
     d. roadmap.md           - 吃 CHANGELOG + README + TODO 群組
     e. future.md            - 吃 TODOs + README limitations + gap analysis
                                (依賴 features.md 跟 roadmap.md 的輸出)
   若 --functions=public:
     f. Architecture/functions/<module>/<func>.md 對每個合格符號

Phase 4: Overview synthesis
   - 改寫:MOC 風格。Body 委派給 wikilink。Frontmatter 帶 stack。
   - 讀每個 section 的 `## Summary` 區塊加 module wikilink。

Phase 5: data-flow (可選,不動)
```

每個 Phase 3.5 步驟:
1. 從 `scan-report.json` 讀自己需要的 signal 子集。
2. 對 signal 子集算 hash。
3. 讀既有 note (若有) 跟 `_manifest.lock.json` 的 section hash。
4. 若 signal hash 跟 lockfile 對得上,`decide_section_refresh()` 回傳 skip (除非 `--force` 或 `--refresh`)。
5. 生成 `@generated` block、保留 `@user` block、寫 note。
6. 用新 hash 跟 timestamp 更新 lockfile section entry。

失敗隔離:某 section 合成爆掉時,寫入該 note 帶 `status: scan-failed`、body 記錄錯誤、pipeline 繼續跑。其他 section 不受影響。

---

## 8. Refresh 模型 — 擴充的 lockfile

`_manifest.lock.json` 加一個 `sections` 區塊:

```json
{
  "schema-version": 2,
  "commit": "<sha>",
  "modules": { "<slug>": { "paths-hash": "...", "note-blocks": { ... } } },
  "sections": {
    "features":     { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", "last-generated": "2026-05-27T..." },
    "roadmap":      { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", "last-generated": "..." },
    "decisions":    { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", "last-generated": "..." },
    "future":       { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", "last-generated": "..." },
    "api-surface":  { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", "last-generated": "..." },
    "overview":     { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", "last-generated": "..." }
  },
  "functions": {
    "<module>/<func>": { "source-hash": "...", "last-generated": "..." }
  }
}
```

`schema-version` 從 1 升 2。Migration:v2 首次跑到 v1 lockfile 時,把所有 section entry 當成 missing (各 regenerate 一次),既有 module entry 原樣保留。

---

## 9. 缺訊號處理

| 條件 | 行為 |
|---|---|
| README 沒 Roadmap / Coming Soon 段 | roadmap.md:body 開頭 `> No explicit roadmap signal found.`;有 CHANGELOG 標 `confidence: medium`、沒有則 `low` |
| 沒 CHANGELOG | roadmap.md 的 `sources` 排除 CHANGELOG;"Trajectory" 段略 |
| 沒 ADR 也沒 ARCHITECTURE.md | decisions.md:略「Detected ADRs」段;只保留「Stack rationale」+「Pattern decisions」;`confidence: medium` |
| 沒 TODO 也沒 Limitations 段 | future.md:只有 Gap analysis 有東西時才寫;全空就 `status: insufficient-signal` |
| CLI / route / export 偵測通通沒抓到 | api-surface.md:略空表;`detection-status: none`;body 開頭 `> No public API surface detected.` |
| Stack 偵測找不到任何可辨識的 config | overview frontmatter 的 `stack` 區塊整段略 (不留空欄) |
| 某段 LLM 合成失敗 | 該 note:`status: scan-failed`、body 紀錄錯誤;pipeline 繼續 |

**沒有 section 會被靜默跳過。** 每個 note 都寫出,讓 overview 的 MOC wikilink 一定解得到。

---

## 10. Overview MOC 改寫

Body section 順序:

1. `## For future Claude` — 明說「這是 MOC,跟連結走」
2. `## Purpose` — 一段,從 README + features.md 的 `## Summary` 合成
3. `## Stack` — bullet,鏡 frontmatter 的 stack 區塊,後綴 `(see [[Architecture/decisions]] for rationale)`
4. `## Capability MOC` — 4 個 wikilink:[[Architecture/features]]、[[Architecture/roadmap]]、[[Architecture/decisions]]、[[Architecture/future]]
5. `## API surface` (zh-TW: `## API 介面`) — 單 wikilink 到 [[Architecture/api-surface]]
6. `## Structure MOC` — wikilink 到 data-flow (若有)、module list、entry point
7. `## Layer map` — v1 留下,單一 Mermaid diagram
8. `## External dependencies` — v1 留下
9. `## Key abstractions` — v1 留下,精簡
10. `## Related`

所有合成 block 仍包在 `@generated` sentinel 內。

---

## 11. Hub note 區塊更新

`Projects/<P>/<P>.md` 的 `## Architecture` 區塊:

**en 模式:**

```markdown
## Architecture

- Overview: [[Architecture/overview]] (last scanned 2026-05-27 @ `<sha>`)
- Capabilities: [[Architecture/features]] | [[Architecture/api-surface]]
- Direction: [[Architecture/roadmap]] | [[Architecture/future]]
- Rationale: [[Architecture/decisions]]
- Modules: N active, M deprecated
- Refresh: `/obsidian-architect <repo-path> --refresh`
```

**zh-TW 模式:**

```markdown
## 架構

- 總覽: [[Architecture/overview]] (上次掃描 2026-05-27 @ `<sha>`)
- 能力: [[Architecture/features]] | [[Architecture/api-surface]]
- 方向: [[Architecture/roadmap]] | [[Architecture/future]]
- 理由: [[Architecture/decisions]]
- 模組: N active, M deprecated
- 重新整理: `/obsidian-architect <repo-path> --refresh`
```

Idempotent:存在則 in-place 取代;否則 append。跟 v1 行為一致。

**跨 command 過渡期注意:** hub note 同時被 `/obsidian-project`、`/obsidian-board` 等其他 command 寫入,那些 command 尚未支援 `output-lang` 前,hub 內可能英中混雜。Architect 只負責自己這一塊 (`## 架構`),其他段落不動。詳見 §16.7。

---

## 12. 指令介面 — Flag

保留 v1 flag:`--project=<P>`、`--refresh`、`--dry-run`、`--force`。

新增:
- `--functions=<mode>` 其中 mode 為 `off` (預設)、`public`。`off` 完全略 Phase 3.5 step f。`public` 只對符合 5.6 資格的符號產 function note。
- `--skip-sections=<csv>` — 例:`--skip-sections=roadmap,future` 跳過個別 section synthesis。對 subset 快速迭代有用。
- `--only-sections=<csv>` — 反向,給 `/architect --refresh --only-sections=roadmap` 這種精準更新。
- `--lang=<code>` — `zh-TW` 或 `en`。覆蓋 `_CLAUDE.md` 的 `output-lang`。Lockfile 的 `lang` 欄位變動會觸發 section regenerate。

解析規則:`--only-sections` 同時傳就蓋過 `--skip-sections`。`--only-sections` 設了的話,modules 跟 overview 也會跳過,除非明確列出。`--lang` 的優先序:CLI flag > `_CLAUDE.md` `output-lang` > 預設 `en`。

---

## 13. 檔案改動清單

| 檔案 | 改動 |
|---|---|
| `commands/obsidian-architect.md` | 加 Phase 3.5;重寫 Phase 4 overview synthesis 為 MOC 風格;說明新 flag 含 `--lang`;更新 hub section 模板;讀 `_CLAUDE.md` 抓 `output-lang` |
| `references/ai-first-rules.md` | 加 5 個新 `type:` 條目 (features、roadmap、decisions、future、api-surface),1 個可選 (function);文件化 overview stack frontmatter 新增;**加 §16.6 語言總則跟 §16.8 雙語 heading 對照表** |
| `scripts/architect_scan.py` | 擴充 scan 收 README section、CHANGELOG 解析、TODO 聚合、ADR 發現、stack 偵測、API surface 提取;吐擴充版 `scan-report.json` |
| `scripts/architect/sections.py` (新) | 每個 section 一個合成器 entry,帶聚焦 context 的 prompt 模板;**prompt 模板接受 `output_lang` 參數,內含 §16.5 的明確語言指示**;signal 子集 hashing;跟 sentinel module 整合 |
| `scripts/architect/api_surface.py` (新) | Deterministic CLI / route / export / env 偵測器,涵蓋支援的語言跟 framework |
| `scripts/architect/public_surface.py` (新) | `--functions=public` 的資格邏輯 |
| `scripts/architect/refresh.py` | 加 `decide_section_refresh()`;lockfile schema 升 v2;migration path;**lockfile `lang` 欄位變動視為 signal 變動** |
| `scripts/architect/manifest.py` 或新增 `stack.py` | Stack 偵測,從 package metadata (best-effort,無 LLM) |
| `scripts/architect/lang.py` (新) | `resolve_output_lang(cli_flag, vault_root) -> "zh-TW" | "en"`;讀 `_CLAUDE.md`;heading 對照表載入 (來源:`ai-first-rules.md`) |
| `CHANGELOG.md` | 一筆 Unreleased:「Architect 現在會產 Features、Roadmap、Decisions、Future、API Surface note;overview 變 MOC;`--functions=public` 開啟 function-level 層;**`--lang=zh-TW` / vault `output-lang` 支援繁中輸出**」 |
| `SKILL.md` | 更新 Layer 1 architect 描述,提及敘事 section 跟語言切換 |
| `README.md` | Commands table 那列更新;簡短一段講敘事輸出跟語言支援 |

---

## 14. 取捨 (有意識的決定)

- **每次 run 更多 LLM call。** 每個 section 獨立 call (5 base + 1 若開 functions)。緩解:per-section signal hash 表示 signal 沒變的 call 在 refresh 時整個 skip;`--skip-sections` / `--only-sections` 給外科手術式迭代。成本是刻意的:獨立 call 給乾淨的失敗隔離跟更緊湊的 context。
- **推論內容有風險。** roadmap 跟 future 段倚賴 TODO / commit-message 啟發法,有可能幻覺。緩解:note-level confidence 欄位、行內 `(inferred from X at path:line)` 標記、透明的「Signals reviewed」段列出 scanner 實際讀了哪些檔。
- **Per-section 檔不會自動扁平化進 hub folder。** `Architecture/decisions.md` 是 synthesis index,不是完整 ADR;`Architecture/future.md` 是 gap analysis,不是已升級的 idea。Architecture/ 樹擁有合成、可再生的內容;升級到 `Decisions/` (完整 ADR) 或 `Ideas/` (curated idea) 分別走 `/obsidian-adr` 跟 `/obsidian-graduate`。這是刻意的分離。
- **Lockfile migration。** schema-version 從 1 升 2 強迫 v2 第一次 run 全 section regenerate。Module entry 保留,所以 per-module 成本不變。

---

## 15. 驗收條件

對代表性 project 跑 `/obsidian-architect <repo>` 後產出應該滿足:

- [ ] `overview.md` 帶 `moc-style: true`、填好的 `stack` 區塊 (或無法偵測就略)、body 主要是 wikilink
- [ ] `features.md` 列出 capability,至少一個 wikilink 進 `api-surface.md` 跟 modules
- [ ] `api-surface.md` 對有 CLI 或 HTTP endpoint 的 project 至少一個非空表;對純 library (兩者都沒) 標 `detection-status: none`
- [ ] `roadmap.md` 即使沒 signal 也有「Signals reviewed」段
- [ ] `decisions.md` 至少有 Stack rationale;偵測到明確選擇時帶「Promote to ADR」建議
- [ ] `future.md` 沒 signal 時標 `status: insufficient-signal`,有 signal 就有內容
- [ ] Hub note 的 `## Architecture` 區塊更新,含全部 5 個新 wikilink
- [ ] Source 沒變時 re-run 不動任何 note (所有 section signal hash 對齊)
- [ ] 帶 `--refresh` re-run 只 regenerate signal hash 變了的 section
- [ ] 對小 library 跑 `--functions=public` 至少產一個 `Architecture/functions/<module>/<func>.md`
- [ ] `--only-sections=roadmap` 只 regenerate `roadmap.md`,modules 跟 overview 不動
- [ ] Adapter build (`bash scripts/build.sh`) 通過;新指令文字在 `dist/codex-cli`、`dist/gemini-cli`、`dist/opencode` 不需 per-platform fork
- [ ] 在 `_CLAUDE.md` 設 `output-lang: zh-TW` 後跑 `/obsidian-architect`,所有 section 的 heading 跟散文皆繁中,但 module slug、檔名、函式名、wikilink 路徑、frontmatter key/enum、sentinel 註解保持英文
- [ ] `--lang=en` flag 可覆蓋 vault 設定,單次跑出全英輸出
- [ ] 從 `zh-TW` 切回 `en` (反之亦然) 觸發所有 section regenerate (lockfile `lang` hash 變動)
- [ ] 繁中 note 的推論標記長相為 `(推論自 src/foo.py:42)`,不是 `(inferred from src/foo.py:42)` 也不是 `(推論自 來源/foo.py:42)`

---

## 16. 語言處理 (Output localization)

### 16.1 設計原則

**「專有名詞跟機讀格式英文,其他都中文」**。語言切換不破壞 AI-first 機讀契約,只翻譯人類閱讀的散文與 heading。

### 16.2 翻譯與不翻譯的元素

| 元素 | output-lang: zh-TW 時 | 理由 |
|---|---|---|
| Body 散文 (Summary、敘事段、bullet 內容) | 繁中 | 人類閱讀主體 |
| Section heading (`## 功能說明`) | 繁中 | 整篇統一 |
| `## 給未來 Claude` preamble heading | 繁中 (`## 給未來 Claude`) | 同上 |
| Mermaid diagram 內節點文字 | 繁中 | 圖中文字屬散文 |
| Inline 推論標記 | 繁中前綴 + 英文路徑 (`(推論自 src/foo.py:42)`) | 描述中文,路徑英文 |
| Recency marker | 英文 (`(as of 2026-04, https://...)`) | vault 通用慣例,跨 command 一致 |
| **Code identifier** (module slug、function name、class name、變數、檔名、import path) | **英文** | 永遠對應原始碼,不翻 |
| **Frontmatter key** (`type`、`tags`、`status`、`confidence`、`sources`) | **英文** | 機讀 schema |
| **Frontmatter enum 值** (`current`、`high`、`scan-failed`、`architecture-features`) | **英文** | 穩定 schema,跨工具解析 |
| **Wikilink 路徑** (`[[Architecture/features]]`、`[[modules/cli]]`) | **英文** | 對應檔名 |
| **Wikilink 顯示文字** (`[[modules/cli|CLI 模組]]`) | 繁中 alias 可用 | display 是散文 |
| **Sentinel 註解** (`<!-- @generated:start summary -->`) | **英文** | 機器辨識符號 |
| **Table 欄位 header** (`Command / Description / Source / Module`) | 繁中 (`指令 / 說明 / 來源 / 模組`) | 散文 |
| Table 內 cell:命令字串、檔案路徑 | 英文 (原樣) | code identifier |
| Table 內 cell:描述欄 | 繁中 | 散文 |
| CLI command 字串本身 | 英文 (`/obsidian-architect`) | 對應實際指令 |
| Heading 中夾雜的專有名詞 | 原樣保留 (`## 給未來 Claude`、`## API surface 表`) | 約定俗成的英文名 |

**判斷捷徑:** 「這串字 grep 進 source code 找得到對應嗎?」找得到就保留英文 (是 code identifier);找不到就是描述/敘事,翻成繁中。

### 16.3 配置機制

**Vault 全域預設:** `_CLAUDE.md` 加一行:

```markdown
- output-lang: zh-TW   # 預設,可設 en
```

Architect 讀 vault root 的 `_CLAUDE.md`,parse 出該設定。沒設就預設 `en` (向後相容)。

**單次覆蓋:** `--lang=zh-TW | en` 命令 flag。優先序:CLI flag > `_CLAUDE.md` > 預設 `en`。

**Project 層級覆蓋 (非目標):** 不開 `Projects/<P>/<P>.md` 加 `output-lang` 的口,以免一個 vault 內混語言。如未來需要,additive。

### 16.4 Lockfile 紀錄

`_manifest.lock.json` 在 `sections` 跟 `modules` entry 加 `lang` 欄位:

```json
"features": { "signal-hash": "...", "lang": "zh-TW", "note-blocks-hash": "...", ... }
```

語言切換 = signal 視同變動 = 該 section regenerate。避免半中半英的混雜輸出。

### 16.5 LLM Prompt 處理

`scripts/architect/sections.py` 的合成器在組 prompt 時加一個 `output_lang` 變數,prompt 模板裡明確指示:

> 你正在為一份 Obsidian 筆記合成「{section}」段內容。輸出語言:**繁體中文 (Traditional Chinese, zh-TW)**。
> 必須保留英文的元素:檔案路徑、變數名、函式名、類別名、import path、CLI 命令字串、URL、frontmatter key、enum 值、wikilink 內的檔名段。
> 其餘的散文、heading、表頭、推論說明用繁中。範例:
> - ✅ `從 `src/cli.py:42` 的 `argparse` 解析器推論而來`
> - ❌ `From src/cli.py:42's argparse parser inferred`
> - ❌ `從來源/cli.py:42 的 引數解析器 推論而來` (path 跟 library 名被翻了)

### 16.6 ai-first-rules.md 更新

加一個總則:

> **語言:** 預設英文。若 vault `_CLAUDE.md` 設 `output-lang: zh-TW`,所有 note 的散文、heading、人類閱讀文字改用繁中,但 frontmatter key、enum 值、wikilink 路徑、sentinel 註解、code identifier 維持英文。`## For future Claude` heading 在 zh-TW 模式下對應 `## 給未來 Claude`。`## Related` 對應 `## 相關`。其他 heading 由各 type 自行規範雙語版本。

並在每個 `type:` 條目加雙語 heading 對照:

```
type: architecture-features
  Body 順序 (en): ## For future Claude, ## Summary, ## Capability map, ## Notable details, ## Related
  Body 順序 (zh-TW): ## 給未來 Claude, ## 摘要, ## 能力地圖, ## 補充細節, ## 相關
```

### 16.7 跨 command 一致性 (非本 spec 目標)

`output-lang` 設在 vault 根層,理論上其他 command (`/obsidian-project`、`/obsidian-daily` 等) 也該尊重。**本 spec 只實作 architect 端**;其他 command 漸進式採用同 pattern。這是有意識的範疇限制 — 一次改一個,避免 vault 內全面混語言過渡期。

### 16.8 Heading 對照表 (architect 各 type)

| Type | English heading | 繁中 heading |
|---|---|---|
| 通用 | `## For future Claude` | `## 給未來 Claude` |
| 通用 | `## Summary` | `## 摘要` |
| 通用 | `## Related` | `## 相關` |
| overview | `## Purpose` | `## 用途` |
| overview | `## Stack` | `## 技術棧` |
| overview | `## Capability MOC` | `## 能力地圖 MOC` |
| overview | `## Structure MOC` | `## 結構地圖 MOC` |
| overview | `## API surface` | `## API 介面` |
| overview | `## Layer map` | `## 分層圖` |
| overview | `## External dependencies` | `## 外部相依` |
| overview | `## Key abstractions` | `## 核心抽象` |
| features | `## Capability map` | `## 能力地圖` |
| features | `## Notable details` | `## 補充細節` |
| roadmap | `## Near term` | `## 近期` |
| roadmap | `## Trajectory` | `## 軌跡` |
| roadmap | `## TODO clusters` | `## TODO 群組` |
| roadmap | `## Signals reviewed` | `## 已檢視訊號` |
| decisions | `## Stack rationale` | `## 技術棧理由` |
| decisions | `## Detected ADRs` | `## 已偵測的 ADR` |
| decisions | `## Pattern decisions` | `## 模式決定` |
| decisions | `## Commit-message decisions` | `## Commit 訊息決定` |
| decisions | `## Promote to ADR` | `## 建議升級為 ADR` |
| future | `## Known limitations` | `## 已知限制` |
| future | `## Gap analysis` | `## 落差分析` |
| future | `## Aspirational ideas` | `## 期望中的想法` |
| api-surface | `## CLI commands` | `## CLI 命令` |
| api-surface | `## HTTP routes` | `## HTTP 路由` |
| api-surface | `## Public exports` | `## 公開匯出` |
| api-surface | `## Environment variables` | `## 環境變數` |
| modules | `## What it does` | `## 功能說明` |
| modules | `## How it works` | `## 運作方式` |
| modules | `## Key files` | `## 重點檔案` |
| modules | `## Depends on` | `## 相依於` |
| modules | `## Consumed by` | `## 被誰使用` |
| modules | `## Recent activity` | `## 近期活動` |
| function | `## Signature` | `## 函式簽章` |
| function | `## What it does` | `## 功能說明` |
| function | `## Inputs and outputs` | `## 輸入輸出` |
| function | `## Behavior notes` | `## 行為註記` |
| function | `## Callers` | `## 呼叫者` |
| hub | `## Architecture` | `## 架構` |
| hub 行 | `- Overview` | `- 總覽` |
| hub 行 | `- Capabilities` | `- 能力` |
| hub 行 | `- Direction` | `- 方向` |
| hub 行 | `- Rationale` | `- 理由` |
| hub 行 | `- Modules` | `- 模組` |
| hub 行 | `- Refresh` | `- 重新整理` |
| hub 行 | `last scanned` | `上次掃描` |

此表進 `references/ai-first-rules.md` 當權威來源。

### 16.9 範例:繁中模式下的 features.md

```markdown
---
type: architecture-features
date: 2026-05-27
project: "[[obsidian-second-brain]]"
repo: github.com/eugeniughelbur/obsidian-second-brain
last-scanned: 2026-05-27
commit: a1b2c3d
sources: [README.md, src/cli.py, commands/]
confidence: high
lang: zh-TW
tags: [architecture, features]
ai-first: true
status: current
---

## 給未來 Claude
這個檔列出本 codebase 對使用者提供的能力。具體的 CLI / HTTP / export 表格在 [[Architecture/api-surface]],模組層級在 [[Architecture/modules]]。

<!-- @generated:start summary -->
## 摘要

`obsidian-second-brain` 是一個跨 CLI 的 skill,把任何 Obsidian vault 變成 AI-first 的第二大腦。共 32 個 slash command,分四層運作:vault management、thinking tools、research toolkit、scheduled agents。
<!-- @generated:end summary -->

<!-- @generated:start capability-map -->
## 能力地圖

### Vault 管理
- 透過 `/obsidian-init` 初始化 vault (見 [[modules/init]])
- 透過 `/obsidian-daily` 維護每日筆記 (見 [[modules/daily]])
- 透過 [[Architecture/api-surface#CLI 命令]] 中列出的命令操作 board、人物、決策

### 思考工具
- `/obsidian-challenge` 對既有筆記做反論 (推論自 `commands/obsidian-challenge.md`)
- `/obsidian-emerge` 從多筆 idea 萃取主題

### 研究工具組
- `/research`、`/research-deep` 從免費來源拉論文 (見 [[modules/research]])

### 排程代理
- 透過 cron 觸發 `/obsidian-reconcile` 自動對齊 vault (見 [[modules/scheduled]])
<!-- @generated:end capability-map -->

## 相關
- [[Architecture/overview]]
- [[Architecture/api-surface]]
- [[obsidian-second-brain]]
```

注意:`/obsidian-init`、`README.md`、`src/cli.py`、`commands/obsidian-challenge.md`、wikilink 路徑、`type` / `confidence` / `lang` 等 enum 值都保持英文。

---

## 17. 待解問題

無。所有設計分岔在 brainstorm 階段已解:

- Layout:Approach A (獨立 section 檔 + MOC overview) — 已核准
- Source 資料:local-only — 已核准
- Refresh:sentinel block regenerate 配 hash diff — 已核准
- 參考 skill 整合:完整 v2 (MOC、api-surface、可選 functions) — 已核准
- Function-level:opt-in flag,預設關 — 已核准
- Stack 偵測:best-effort,不確定就略 — 已核准
- 輸出語言:vault 全域 `output-lang` + `--lang=` flag,專有名詞英文其他繁中 — 已核准
