# obsidian-architect v3 — Judgment-Driven Reframe Design Spec

**日期:** 2026-05-27
**狀態:** Draft — 等 user sign-off,之後進 writing-plans
**Branch:** TBD (建議 `feat/architect-v3-judgment`)
**取代:** v2 的「narrative on top of file-tree」框架
**部分修正:** `2026-05-27-obsidian-roadmap-design.md` Phase 1 訊號源(轉用 `## 改進機會` blocks)
**Layer:** Layer 1 (Vault Operations)

---

## 1. 動機 — 一個根本洞察

v2 的 architect 命令(剛上線的版本)花了大量 LLM 預算在「描述程式碼結構」 — `backend/` 下有哪些檔、哪個 module 用什麼 framework、route table 有 N 條。實際 dogfood 後發現:

**這些資訊 codebase 本身就有。** 當 future-Claude 需要知道 `backend/main.py` 做什麼,他直接 `Read backend/main.py` 就行。在 vault 裡寫一份「file location 目錄」是 redundant — 訊號密度低、噪音極高。

**真正有價值、codebase 沒有記錄的,是「人類設計判斷」:**
- 整體架構為什麼這樣設計,有哪些優點?
- 哪裡有 design smell、tech debt、scaling risk?
- 哪些是 high-leverage 的改進機會?

這些是專家走進 codebase 一個月之後才會說出來的,不是隨便 `Read backend/main.py` 能看到的。

v3 把 architect 從 **transcriber**(描述程式碼結構)轉成 **critic**(產生設計判斷)。

順帶效益:**`/obsidian-roadmap` 的訊號源變超乾淨**。每個 architect 檔的「改進機會」段就是 roadmap candidate,不用再做 gap inference。

---

## 2. 目標

1. **Judgment over description.** 每個 architect 檔的 body 由「整體流程 / 優點 / 缺點 / 改進機會」四段組成。File path 列表整個從 vault 移除。
2. **改進機會 = roadmap signal.** 每個 Imp 必含 Why / Evidence / Effort / Risk-if-not-done / Confidence,直接可被 `/obsidian-roadmap` Phase 1 消費,免去 gap inference。
3. **每個 Imp 必有 Evidence.** Evidence 是 wikilink 到 decision、commit、AGENTS.md 段、或 module note,不是 file path。若 LLM 想不出 evidence 就不寫該 Imp。這強制與 reality grounded。
4. **加 product-eye 三檔.** 從前一輪 brainstorm:`personas.md`、`jobs.md`、`flows.md`。同樣 judgment-driven 框架(per persona / per job / per flow 都有 優/缺/改進)。
5. **保留 sentinel + lockfile + 多 adapter.** v2 的核心機制不動,只換 prompt 跟輸出 schema。
6. **Lang-aware.** 繼續尊重 `_CLAUDE.md output-lang`;繁中模式下 heading / 散文繁中,code identifier 在 Evidence 段仍可英文(因為是 grep 對象)。

---

## 3. 不做的事

- **不再列檔案路徑作為主要內容.** Module note 不再有「重點檔案」段。Evidence 引用 code 時用 wikilink 或 inline `\`backend/auth.py:42\`` 點到精確位置,但不做「這個 module 有哪些檔案」清單。
- **不重做 v2 scanner.** Phase 1 scan (manifest detection、API surface extraction、stack detection、TODO aggregation) 都保留 — 它們產生機讀資料供 LLM 在 critique 時當 grounding。
- **不刪 api-surface.md** — reframe 成「公開介面 high-level 概觀 + 連到 `/tmp/...scan-report.json` 完整表」。對外介面**是**產品事實,只是不用人類讀 115 條 route table。
- **不做 per-Imp 一檔.** 改進機會留在 module/overview/feature 等檔內部的段,不爆檔。Roadmap 會把它們合成 theme,該升級為獨立 task/ADR 時走既有 `/obsidian-roadmap` + `/obsidian-task` + `/obsidian-adr` 路徑。
- **不修 lockfile / sentinel schema.** Block name 改變(新 block: `strengths`, `weaknesses`, `improvements` 取代或補充 `what-it-does` / `how-it-works` / `key-files`),但 sentinel 機制不動,refresh-preserves-user-edits 行為一樣。
- **不重做 /obsidian-roadmap Phase 5.** 只改 Phase 1 訊號源(從 architect 檔的 `## 改進機會` block 抓),Phase 2-5 不動。

---

## 4. 新 output layout(flatter than v2)

```
Projects/<P>/Architecture/
├── overview.md           # 整體架構流程 + 全局 優/缺/改進
├── modules/
│   ├── backend.md        # 模組職責 + 優/缺/改進(不列檔)
│   ├── frontend.md
│   └── ...
├── personas.md           # 🆕 user 型態 + per persona 痛點
├── jobs.md               # 🆕 Jobs-to-be-done + per job maturity + friction
├── flows.md              # 🆕 端到端 flow + per flow 優/缺/改進
├── features.md           # 改:純 capability 描述 + per capability 優/缺/改進,無 file path
├── api-surface.md        # 改:high-level 介面類型概觀,完整 table 留在 scan-report.json
├── decisions.md          # 既有,本身判斷型 — 微調:加 per-decision「Risk if not committed」
├── future.md             # 既有,本身判斷型 — 微調:每個 idea 補 Evidence
├── roadmap.md            # 既有,descriptive signal(TODO clusters 等),不變
├── _manifest.yml         # 不動
└── _manifest.lock.json   # 不動
```

v2 跟 v3 對比:

| | v2 | v3 |
|---|---|---|
| Folder | `Architecture/` flat + `modules/` 子層 | 同(沒拆 product/code) |
| modules/X.md 內容 | 功能說明 + 運作方式 + 重點檔案 + 相依 + 被用 + 近期活動 | 模組職責 + 整體運作 + 設計優點 + 設計缺點 + 改進機會 + 相依 + 被用 |
| Product layer | 無 | `personas.md` + `jobs.md` + `flows.md` |
| Roadmap signal | 從 `future.md`(gap analysis 推論) | 從每個 architect 檔的 `## 改進機會` block(LLM 已 grounded 在 evidence) |

---

## 5. 統一 schema:每個 architect 檔的 body

### 5.1 通用 5 段 + tail

```markdown
## 給未來 Claude
(preamble,3-4 句)

## 整體流程 / 模組職責 / 能力範圍 / 旅程
(視 file type 命名;1-2 段 + 必要時 Mermaid)
<!-- @generated:start scope -->...<!-- @generated:end scope -->

## 設計優點
- 點 1(具體 + Evidence)
- 點 2
<!-- @generated:start strengths -->...<!-- @generated:end strengths -->

## 設計缺點 / 風險
- 點 1(含 impact)
- 點 2
<!-- @generated:start weaknesses -->...<!-- @generated:end weaknesses -->

## 改進機會   ← 🌟 roadmap signal
### Imp 1: <短句標題>
- **Why:** ...
- **Evidence:** [[wikilink]] / `path:line` / commit SHA
- **Effort:** S | M | L | XL
- **Risk if not done:** ...
- **Confidence:** stated | high | medium | speculation

### Imp 2: ...
<!-- @generated:start improvements -->...<!-- @generated:end improvements -->

## 相依於 / 被誰使用
- [[wikilinks only]] —— 不寫 file path
<!-- @generated:start dependencies -->...<!-- @generated:end dependencies -->

## 相關
- (其他 architect 檔的 wikilinks)
```

### 5.2 per-type 變化

**overview.md** 的「整體流程」段:全項目 Mermaid + 段描述

**modules/X.md** 的「模組職責」段:1 段;不再有「Key files」/「重點檔案」

**features.md** 的「能力範圍」段:依 capability area 分 H3,每個 capability 自帶 mini 優/缺/改進(嵌套 H3 → H4 結構)

**flows.md** 的「旅程」段:依 flow 分 H3,每個 flow 一個 Mermaid sequence + 自帶 優/缺/改進

**jobs.md** 的「能力範圍」段:依 persona × job matrix,每個 job 帶 Maturity (Alpha/Beta/GA) + 自帶 優/缺/改進

**personas.md** 結構不同:per persona H2,內含「誰」「目標」「觸點」「頻率」「主要痛點」,不需要強制 5 段(persona 本身不是設計物,不需要 critique)

**decisions.md / future.md / roadmap.md / api-surface.md** 維持 v2 的 schema,但 features.md 已被 reframe 為純 capability。改動最小化以減少 migration 成本。

---

## 6. 「改進機會」內容怎麼來?

`scripts/architect/sections.py` 的 prompt builder (`build_prompt`) 替每種 type 加新指令,例 module:

> 你正在為 `<module>` 撰寫架構判斷文件。
> Codebase 已被 repomix 打包進 context。AGENTS.md / CLAUDE.md / README.md 摘要在下。
>
> 請產出 4 個 block,每個是 markdown 字串:
> 1. `scope` — 1-2 段描述這個模組的職責、邊界。**不要列檔案**;若要 cite,用 `\`path:line\`` inline 形式,不要表列。
> 2. `strengths` — 3-5 個 bullet,每個 ≤ 2 句,含具體 Evidence(commit SHA / decision wikilink / AGENTS.md 段引用)
> 3. `weaknesses` — 3-5 個 bullet,每個含 impact 描述(例:「流量峰值時 API latency 飆」),不只是「不夠好」
> 4. `improvements` — **2-4** 個改進機會,每個必含 Why / Evidence / Effort / Risk-if-not-done / Confidence。如果想不出 Evidence,**不要** 寫該 Imp(不允許速食 idea)
>
> 評斷品質而非範疇:寧少而精,不多而泛。

每個 improvement 的 markdown 格式被嚴格定義(見 §5.1),Phase 1 of `/obsidian-roadmap` 用簡單 regex 解析。

---

## 7. /obsidian-roadmap Phase 1 改動

**現行 Phase 1**(`scripts/roadmap/candidates.py`)讀 3 個 architect 檔的 5 個段:
- future.md 的 落差分析 / 已知限制 / 期望中的想法
- decisions.md 的 建議升級為 ADR
- roadmap.md 的 TODO 群組

**v3 Phase 1** 改讀(加上 v3 新出的 improvement blocks):
- 每個 architect 檔的 `## 改進機會` / `## Improvements` 段(overview、所有 modules/X、features、flows、jobs)
- 仍讀 future.md 的「已知限制」(那段不是改進機會,是現況限制)
- 仍讀 decisions.md 的「建議升級為 ADR」(decision 升級也是 roadmap signal)
- 不再讀 future.md 的「期望中的想法」/「落差分析」(被 architect 各檔的 improvement 取代)
- TODO 群組仍讀,當作補充信號

Phase 1 解析 improvement 時保留 `Why / Evidence / Effort / Risk-if-not-done` 等 metadata 進 Candidate dataclass,Phase 3 LLM synthesis 可以直接用,不用重 prompt 推估 effort/priority。

`Candidate` dataclass 微擴:

```python
@dataclass
class Candidate:
    id: str
    title: str
    source_wikilink: str
    source_line: int
    kind: str          # improvement | limitation | promote-to-adr | todo-cluster
    raw_text: str
    # v3 additions (optional, populated when source is a structured improvement):
    why: str | None = None
    evidence: list[str] = field(default_factory=list)
    effort: str | None = None   # S | M | L | XL
    risk_if_not_done: str | None = None
    confidence: str | None = None
```

---

## 8. Sentinel block 改名 + 遷移

v2 的 module note 用 sentinels:`what-it-does`、`how-it-works`、`key-files`、`depends-on`、`consumed-by`、`recent-activity`、`related`。

v3 用:`scope`、`strengths`、`weaknesses`、`improvements`、`dependencies`、`related`(無 `recent-activity` —— git log 留在 architect 報告 stdout,不污染 vault note;若 user 想要可手動 `@user` block 加)。

**遷移行為(乾淨重寫,不要又胖又雜):**
1. 首次 v3 跑到 v2 lockfile (`schema-version: 2`) 跟既有 module notes:
   - **`@generated:start <v2-name>` block 整段移除** — 那些是上次自動生成的 file-tree 噪音(`what-it-does` / `how-it-works` / `key-files` / `depends-on` / `consumed-by` / `recent-activity`),整個 v3 的設計目的就是不要這些;留著違背初衷。
   - **`@user:start <name>` block 完全保留** — 任何 user 手動 wrap 的內容都是判斷,不洗。
   - **新 v3 block 寫入** — `scope` / `strengths` / `weaknesses` / `improvements` / `dependencies` 5 個 `@generated` block。
   - 結果:per-module note 大小從 v2 ~5KB → v3 ~5-8KB(同等級,但內容是判斷不是 file listing)。
2. **`--dry-run` 顯示 migration plan** — 先列要刪哪些 v2 block、保留哪些 user block、新生哪些 v3 block,user 確認後才執行。`--force` 跳過確認。
3. **Lockfile bump 到 `schema-version: 3`**,`frame: "judgment-v3"` 標記。Lockfile 也 prune 掉只追蹤 v2 block hash 的 entry。
4. **safety net**:在執行 migration 之前,把 `Architecture/` 整 tar 到 `_archive/architecture-pre-v3-<timestamp>.tar.gz`(gitignored,純 local 安全網);若 v3 結果不滿意,可以解壓回滾。Disk cost ~50KB per project。

---

## 9. Personas / Jobs / Flows signal 來源

跟前一輪 brainstorm 一樣的 hybrid C+A 策略:

1. **明確段優先:** README / AGENTS.md / CLAUDE.md 若有 `## Personas` / `## User Flows` / `## Jobs to be Done` / `## 使用者型態` / `## 使用路徑`,直接抓並標 `confidence: stated`
2. **LLM 推論次之:** 沒明確段時,LLM 從 README + AGENTS.md + features + recent commits 推論;標 `confidence: medium`
3. **強制 callout 警示:** `confidence: medium` 的整檔開頭加 OFM callout:`> [!warning]+ 本檔大半為 LLM 推論,owner 校對前不可作為正式產品 spec`

`scripts/architect/readme.py` 加新 alias:
- `personas`、`user types`、`使用者型態`、`使用者角色` → "Personas"
- `user flows`、`user journeys`、`使用路徑`、`使用流程` → "Flows"
- `jobs to be done`、`jtbd`、`user jobs` → "Jobs"

---

## 10. api-surface.md reframe

**舊 (v2):** 17KB,115 條 HTTP route table + 343 個 export table + 236 個 env var table,人類讀不下去。

**新 (v3):** 不再列每個 endpoint。改為**介面分類 + 設計判斷**:

```markdown
## 給未來 Claude

## 介面類型概觀

### 公開 HTTP API
- 規模:115 條 route(完整清單見 `/tmp/architect-<hash>/scan-report.json`)
- 主要分組:auth / admin / chat / ai-engine / webhook
- 對外消費者:[[modules/frontend]] (SPA via CORS)、LINE 平台 (webhook 回呼)
- **設計優點:** 一致 dependency-injection auth gate (`get_current_user`),路徑命名分組清楚
- **設計缺點:** 部分 admin 端點仍 plain-text password fallback;沒有 API versioning prefix
- **改進機會 → 見 [[overview#改進機會]]、[[modules/backend#改進機會]]**

### 環境變數
- 規模:236 個 reference
- 主要分群:Redis 連線、LLM API keys、Confluence、SSO
- **重要 gotchas:**
  - `backend/.env` 已棄用(AGENTS.md 警告)
  - Confluence 設定刻意拆兩處(url 在 `langlive-line-oa.json`,api_key 在 `env.json`)
- **改進機會 → 統一 Confluence schema validation(見 [[modules/backend#改進機會]] Imp 3)**

### CLI / 公開 export
- 本系統為純 web admin tool,無 CLI 命令層
- Python `__all__` 等 export 主要供 backend 內部 import,不對外公開
```

完整 table 在 `/tmp/architect-<hash>/scan-report.json` 維持機讀,給 `/obsidian-roadmap` 與其他工具 query。Vault note 變人讀友好 + judgment-laden。

---

## 11. 命令 flag 變化

新增 / 變動:
- `--frame=<judgment|description>` — 預設 `judgment`(v3 行為);`description` 走舊 v2 行為作為 fallback,允許不愛 critique 風格的 user 切回去
- `--improvements-per-file=<N>` — 上限 4(預設),可降低到 2 給輕量 project
- `--require-evidence` — 預設 true;若關閉允許 LLM 寫 Imp 不附 Evidence(不建議,除錯用)

既有 flag(`--project=`、`--refresh`、`--dry-run`、`--force`、`--functions=`、`--skip-sections=`、`--only-sections=`、`--lang=`)維持。

---

## 12. 檔案改動清單

| 檔 | 改動 |
|---|---|
| `commands/obsidian-architect.md` | Phase 3 module synthesis prompt 改 judgment 框架;Phase 3.5 加 personas/jobs/flows synthesis;Phase 4 overview synthesis prompt 改 judgment 框架;migration 章節 |
| `references/ai-first-rules.md` | 加 3 個新 type:`architecture-personas`、`architecture-jobs`、`architecture-flows`;改 `architecture-module` body schema(scope/strengths/weaknesses/improvements);改 `architecture-features` body schema |
| `scripts/architect/sections.py` | 改 `_BLOCK_NAMES` per section:加 strengths / weaknesses / improvements / scope;改 `build_prompt` per section:加 critique directive、Evidence 強制要求 |
| `scripts/architect/personas.py` (新) | per-persona signal collector;讀 README + AGENTS.md 明確段或 LLM 推論 |
| `scripts/architect/jobs.py` (新) | per-job signal collector |
| `scripts/architect/flows.py` (新) | per-flow signal collector |
| `scripts/architect/api_surface_render.py` | 改 render:不再 dump 完整 table,改 high-level 分類概觀 + 統計 |
| `scripts/architect/lang.py` | 加 heading entries:`設計優點 / 設計缺點 / 改進機會 / 模組職責 / 整體流程 / 風險 / 期望成熟度` 等;persona / job / flow 相關 heading |
| `scripts/architect/lockfile.py` | bump schema 到 v3;migration v2→v3 對舊 module note 的 sentinel block 重新分類(`@generated` → `@user`) |
| `scripts/architect/refresh.py` | `decide_module_refresh()` 對 v3 frame 增加 force-regenerate 行為(v2 sentinel names 跟 v3 不同,首次跑必 regenerate 但保留舊內容) |
| `scripts/roadmap/candidates.py` | 加 `parse_improvements_block(text) -> list[ImprovementCandidate]`;Phase 1 改讀 architect 各檔的 `## 改進機會` 段;`Candidate` dataclass 加 v3 optional 欄位 |
| `tests/architect/test_sections.py` | 新增 critique frame tests(strengths/weaknesses/improvements block 存在、Evidence 必填規則) |
| `tests/architect/test_personas.py`、`test_jobs.py`、`test_flows.py` (新) | 各 signal collector tests |
| `tests/architect/test_api_surface_render.py` | rewrite — 新「分類概觀」格式 |
| `tests/architect/test_lockfile.py` | v3 schema migration tests |
| `tests/roadmap/test_candidates.py` | 新測:從 architect `## 改進機會` block 抓 ImprovementCandidate |
| `CHANGELOG.md` | 一筆 Unreleased entry,標 v3 frame change |
| `SKILL.md` | 更新 Layer 1 architect 描述 |
| `README.md` | 更新 architect 段落 |

---

## 13. 取捨我有意識的點

- **LLM 主觀性提高:** Critique 不像 file listing 那麼客觀。三道防線:(1) Evidence 必填規則,(2) `confidence` 標籤,(3) sentinel-aware refresh 讓 user 在 `@user` block 標明哪些 LLM 判斷有問題、`@generated` regen 不會洗掉 user 注釋。
- **檔案大小:** Migration 後 module note 約 5-8KB(跟 v2 持平或略少),因為 v2 的 file-listing 整段移除,新加的 strengths/weaknesses/improvements 雖然較有料但長度可控。**淨減少噪音、提升訊號密度。**
- **API surface 完整 table 從 vault 移走:** 對需要「我想看 endpoint /admin/X 是不是真的存在」的 user,改為 grep `/tmp/architect-<hash>/scan-report.json` 或開實際 source。Trade-off:vault note 更精簡,但臨時查找需要原始檔。可接受 — Architecture/ 不該變成 reference card。
- **Migration 是乾淨切換:** v2 `@generated` block 整段移除,只保留 `@user` block(若有)。安全網是 tar.gz 備份;若不滿意可解壓回滾。一週過渡期的「舊+新並存」問題不存在。
- **personas / jobs / flows 可能 hallucinate:** Owner 校對前不應視為 product spec。callout 警示 + confidence:medium 是緩解,不是消除。

---

## 14. 驗收條件

對 `langlive-line-oa` 跑 `/obsidian-architect /Users/leric/Desktop/code/langlive-line-oa --refresh`(v3 frame)應該:

- [ ] `Architecture/modules/backend.md` 不再有 `## 重點檔案` / `## Key files` 段
- [ ] `Architecture/modules/backend.md` 有 `## 改進機會` / `## Improvements` 段,含 ≥ 2 個 Imp,每個 Imp 含 Why/Evidence/Effort/Risk/Confidence 五欄
- [ ] 每個 Imp 的 Evidence 欄不為空(LLM 若想不出 Evidence 該 Imp 不生)
- [ ] `Architecture/overview.md` 同樣有 `## 改進機會` 段針對全項目層面的設計
- [ ] `Architecture/personas.md` 存在,≥ 2 個 persona
- [ ] `Architecture/jobs.md` 存在,≥ 3 個 JTBD,每個含 maturity (Alpha/Beta/GA)
- [ ] `Architecture/flows.md` 存在,≥ 2 個 flow,每個含 Mermaid + Friction 評估
- [ ] `Architecture/features.md` body 不含任何 `backend/foo.py` 形式 path(只能在 Evidence wikilink 中出現)
- [ ] `Architecture/api-surface.md` < 5KB(從 17KB 瘦身),改成分類概觀
- [ ] 既有 v2 `@generated` sentinel block(`what-it-does`、`key-files` 等)被移除;`@user` block(若有)完整保留;`_archive/` 內有 tar.gz 備份
- [ ] `_manifest.lock.json` schema-version=3
- [ ] `/obsidian-roadmap <P>` Phase 1 candidates 數 ≥ v2 跑出的數(因為現在每個 module 都有 2-4 個 Imp,訊號比 future.md gap 多)
- [ ] 跑 `--frame=description` 退回 v2 行為(backward compat 驗證)
- [ ] 全測試通過 (`uv run pytest tests/architect/ tests/roadmap/`)
- [ ] Adapter build 通過 (`bash scripts/build.sh`),4 個 platform 都產出

---

## 15. 開放問題

無。本 brainstorm 階段定:
- Frame:judgment-driven,file-location 出局 — 已核准
- Folder layout:flat,不拆 product/code — 已核准
- Product layer:personas + jobs + flows 全加 — 已核准
- Roadmap signal source:改抓 `## 改進機會` block — 已核准
- Migration:v2 `@generated` block 整段移除 + tar.gz 備份 + `--dry-run` 確認 plan — 隱含核准
- Lockfile bump:schema-version v2 → v3 — 隱含核准
