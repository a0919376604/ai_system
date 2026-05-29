# obsidian-architect v4.1 — AI Flows Layer Design Spec

**日期:** 2026-05-28
**狀態:** Draft — 等 user sign-off,之後進 writing-plans
**Branch:** TBD (建議 `feat/architect-v4.1-ai-flows`)
**追加於 v4:** v4 (consolidated report) 是基底;此 spec 加 `architecture-ai-flow` 一層
**Layer:** Layer 1 (Vault Operations)

---

## 1. 動機

v4 把 architect 收斂為 8 個檔的 top-down 報告,但對「AI-heavy project」仍不夠精準。

real-world AI 子系統(LangGraph chat、RAG pipeline、agent worker 等)有自己的關注面:

- **Graph topology** — node 怎麼連、conditional routing 條件
- **State schema** — 流經 graph 的狀態結構
- **Prompts inventory** — 主要 prompts 在哪、用途、版本
- **LLM 設定** — model tier、temperature、fallback chain、latency budget
- **評估 / 觀測** — eval 指標、log/trace、replay
- **AI 特有失敗模式** — hallucination、model drift、API 限流、cost runaway

這些訊息塞進 `modules/<backend>.md` 會喧賓奪主(LangGraph 細節通常比其他 backend 內容還多)。更糟的是,LangGraph + qa-to-kb 兩個 AI 子系統在 langlive 分屬不同 module,但語義上是平行的 AI flow — 該 cross-cut 處理。

v4.1 加一層 `Architecture/ai-flows/<name>.md`,把 AI 子系統當「平行於 module 的 unit」,獨立記錄判斷。

**對沒 AI 的 project**:scanner 偵測 0 個 AI flow → 不產 `ai-flows/` 資料夾 → 零 cost。

---

## 2. 目標

1. **AI 子系統有專屬文件單位.** 新 type `architecture-ai-flow`,vault 路徑 `Projects/<P>/Architecture/ai-flows/<flow-slug>.md`。
2. **判斷導向,跟 module note 一致.** 5 段判斷 (purpose/strengths/weaknesses/improvements/dependencies) + 5 段 AI 特有 (graph/state/prompts/llm/eval)。
3. **Scanner 自動偵測.** 加 `scripts/architect/ai_flow.py` 偵測 LangGraph、LangChain、custom pipeline 三種 AI 子系統模式。
4. **Prompts 全文嵌進 vault,collapsible + per-prompt drift refresh.** AI-first vault 的核心是自包含 context;future-Claude 要懂 AI 行為必須能直接看 prompt,而不是跑去 grep 原始碼。每個 prompt 是獨立 `@generated:start prompt-<slug> source-hash=...` sentinel block,內含 Obsidian collapsible callout(`> [!quote]-`)。Source 內 prompt 改動 → source-hash mismatch → 單一 prompt block 自動 regen,其他不動。動態組合(string concat 拼出)的 prompt 標 dynamic + 列組合 path,不硬抽。
5. **修改 module note 為 1-line wikilink.** modules/backend.md 等不再描述 AI 細節,只說「**AI engine:** [[ai-flows/<name>]]」。
6. **連到 overview MOC + drill-down.** Overview `## Module map` 段每個 AI flow 一行,`## Drill-down entries` 加 `[[ai-flows/...]]` 連結。
7. **`/obsidian-roadmap` 信號源擴展.** Phase 1 candidates 也讀 `ai-flows/*.md` 的 `## 改進機會` block。
8. **Lockfile 不重做.** v4 schema(version 4, frame "report-v4")維持;加 `ai_flows` block 追蹤 ai-flow note material化。
9. **Lang-aware.** 沿用 `_CLAUDE.md output-lang`。
10. **Backward compat.** 沒 AI 的 project / 沒 LangGraph 的 codebase → ai-flows/ 不出現,行為跟 v4 一致。

---

## 3. 不做的事

- **不做 prompt 版本歷史.** Git 已經追了 source 端;vault 只存最近一次掃描的 prompt 全文。歷史對比走 git blame,不在 vault 重做。
- **不對動態組合 prompt 強行還原.** 若 prompt 是 runtime string concat 出來的(例:`f"You are a {persona}, {context}, {format_hint}"` 散 5 處組起),scanner 標 `dynamic` + 列組合的 path:line,不硬塞「合成的全文」進 vault(會誤導)。
- **不解析 LangGraph 圖結構成詳細 control flow.** 圖節點 + edges 用 Mermaid 列出,但不還原所有 conditional logic(那是 code 的工作)。
- **不評估 LLM 答案品質.** 沒 eval framework 整合。只「描述」owner 有沒有設 eval(stated)或推論可能缺(speculation)。
- **不做 prompt template 自動分類.** 若 codebase 有 `system_prompt.py` / `user_prompt.py` / `format_*.py`,scanner 列出但不分類性質。
- **不重做 personas / decisions.** 它們的 schema 跟 v4 一致。
- **不取代 module notes.** modules/backend.md 仍是 backend module 設計判斷,只是 AI 細節下放到 ai-flows/。

---

## 4. 新 type schema:`architecture-ai-flow`

### Frontmatter

```yaml
---
type: architecture-ai-flow
date: 2026-05-28
project: "[[<P>]]"
local-path: "<absolute repo path>"
last-scanned: 2026-05-28
commit: <sha>
sources: ["backend/engines/langgraph/", "backend/engines/langgraph/prompts/"]
ai-framework: "langgraph"           # langgraph | langchain | custom-pipeline | autogen | semantic-kernel | crewai
flow-kind: "real-time-chat"         # real-time-chat | batch-pipeline | rag | tool-use-agent | classification | extraction
maturity: "Beta"                    # Alpha | Beta | GA
confidence: medium                  # stated | high | medium | speculation
lang: zh-TW | en
tags: [architecture, ai-flow, <framework>]
ai-first: true
status: current | scan-failed | insufficient-signal
---
```

### Body sections (en / zh-TW),10 段

```markdown
## For future Claude / ## 給未來 Claude
   2-3 句 preamble

1. ## Purpose / ## 流程目的
   何時觸發、為誰、解什麼、輸出什麼。1 段。

2. ## Graph topology / ## 圖結構
   Mermaid graph TD(node + edge + conditional routing)。
   每個 node 名字後綴 source `path:line`。

3. ## State schema / ## 狀態 schema
   ```python
   class FooState(TypedDict):
       ...
   ```
   Source 連到 `core/state.py:N-M`。

4. ## Prompts / ## Prompts
   每個 prompt 一個 H3 + metadata 4 欄 + per-prompt `@generated` sentinel 包 collapsible
   callout 全文。整體結構:

   ```markdown
   ### intent_classifier
   - **用途:** 把客戶訊息分類為 5 種 intent
   - **Source:** `backend/engines/langgraph/prompts/intent.py:1-25`
   - **Model:** Gemini Flash · T=0.0 · max_tokens=50
   - **Type:** static template  (or: dynamic — see "組合邏輯" below)

   <!-- @generated:start prompt-intent-classifier source-hash=sha256:abc123 -->
   > [!quote]- 完整 prompt
   > ```
   > You are an intent classifier for LangLive's customer service chat.
   > Given a user message in Chinese, classify it into ONE of:
   > - PRODUCT_QUESTION
   > ...
   >
   > User message: {user_message}
   >
   > Return only the intent label.
   > ```
   <!-- @generated:end prompt-intent-classifier -->
   ```

   **Static 規則:** prompt 是 module-level constant 或 config 檔(`prompts.toml`)的 string,
   能直接抽出 → 走 collapsible 全文路徑,source-hash 追 drift。

   **Dynamic 規則:** prompt 在 runtime 用 string concat / 多步驟組合 → 標
   `**Type:** dynamic`,body 列「組合路徑」(例 `system_prompt 在 prompts/system.py 定義
   `_BASE`,加 `persona_block` 在 utils/persona.py:42,在 graph.py:80 拼起」),不硬塞合成全文。

   Format string 的 `{var}` placeholder **保留**,不展開。

5. ## LLM config / ## LLM 設定
   Table: role | model | temperature | fallback | latency budget。

6. ## Evaluation & observability / ## 評估與觀測
   有 eval 嗎(stated / inferred 缺)? metrics? trace? replay?

7. ## Design strengths / ## 設計優點
   v3.1 tight-bullet format(跟 module 一致)。

8. ## Design weaknesses / ## 設計缺點
   含 AI 特有 failure modes:hallucination、model drift、cost、限流、prompt injection 風險

9. ## Improvement opportunities / ## 改進機會
   strict 5-field Imp format(`### Imp N: ...` + Why/Evidence/Effort/Risk/Confidence)

10. ## Dependencies / ## 相依
    Wikilinks only:
    - Host module: `[[modules/<slug>]]`
    - External APIs:Gemini / OpenAI / Anthropic / Bedrock
    - Framework:LangGraph / LangChain
    - Observability:LangSmith / Helicone / Phoenix(若 stated)

## Related / ## 相關
   - [[Architecture/overview]]
   - [[modules/<host-slug>]]
   - [[<P>]]
```

---

## 5. Scanner 偵測:`scripts/architect/ai_flow.py`

### 5.1 偵測規則

逐 candidate AI flow root 偵測。Candidate root = 含一組 AI-pattern 檔案的 directory(`backend/engines/langgraph/`、`modules/qa_to_kb/`、`agents/`、`workflows/` 等)。

**LangGraph confirmation:**
- `langgraph` 在 `requirements.txt` / `pyproject.toml` / `package.json`
- `from langgraph` / `langgraph.graph.StateGraph` import 在任一 .py 檔
- 存在 `graph.py` 或 `graphs/*.py`
- 至少 3 個 node(`nodes/**/*.py` 計數 ≥ 3,或 graph 內 `.add_node()` 呼叫 ≥ 3)

**LangChain confirmation:**
- `langchain` deps + 沒上述 LangGraph 訊號
- chain / pipeline 結構

**Custom pipeline confirmation:**
- `pipeline.py` + `nodes/` (沒 langgraph/langchain deps)
- 多階段執行(stage1, stage2, ... 命名)
- 有 prompt 檔(`prompts.toml`、`prompts.py`、`*prompts/*.py`)
- LLM API 呼叫(`openai`、`anthropic`、`google.generativeai`)

**門檻**:不滿足上述任一 confirmation 規則 → 不算 AI flow。1-2 個 LLM call 散在 module 內 → 不算(那寫進 module 判斷即可)。

### 5.2 AI Flow 資料結構

```python
@dataclass
class AIFlow:
    slug: str                        # ai-flows/<slug>.md filename, 例 "lang-ai-customer"
    name: str                        # display name
    framework: str                   # langgraph | langchain | custom-pipeline | ...
    root_path: str                   # repo-relative,例 "backend/engines/langgraph"
    flow_kind: str                   # real-time-chat | batch-pipeline | rag | tool-use-agent
    node_count: int                  # 偵測到的 node 數
    prompt_files: list[str]          # repo-relative paths
    state_module: str | None         # 例 "backend/engines/langgraph/core/state.py"
    graph_files: list[str]           # 例 ["backend/engines/langgraph/graph.py"]
    llm_libs: list[str]              # 例 ["openai", "google.generativeai", "anthropic"]
    confidence: str                  # stated | high | medium
```

### 5.3 Prompt extraction(`scripts/architect/prompt_extract.py`,新模組)

```python
@dataclass
class ExtractedPrompt:
    name: str                        # variable / constant / config key 名稱
    source: str                      # repo-relative `path:line-start:line-end`
    body: str                        # full prompt text(static)或組合說明(dynamic)
    is_dynamic: bool
    source_hash: str                 # "sha256:<hex>" of `body` field
    model_hint: str | None           # 旁邊 code 推論的 model(`model="gemini-flash"`)
    extraction_method: str           # "module-constant" | "toml-config" | "yaml-config" | "dynamic-trace"
    extraction_notes: list[str]      # warnings / how it was located
```

抽出邏輯(heuristic,按優先序):

1. **`prompts.toml` / `prompts.yaml` / `prompts.json`** — config 檔內 key 即 prompt name,value 即 body。最穩。
2. **`prompts/*.py`** — module-level UPPER_CASE constant 對應 triple-quoted string。第二穩。
3. **AGENT-style `SYSTEM_PROMPT = """..."""`** — 任何 .py 檔的 module-level 多行字串常數,前綴 SYSTEM_PROMPT / USER_PROMPT / TEMPLATE_。
4. **LangGraph / LangChain `ChatPromptTemplate.from_messages([...])`** — 抽 message 內的 SystemMessage / HumanMessage 字面值。
5. **不滿足上述 → 標 `is_dynamic=True`,extraction_notes 列「位於 path:line,但是組合形式」**。

不嘗試:函式內 local string、tool callback 的 inline string、tested via mock 的 fixture prompt。

### 5.4 scan-report.json 加新欄位

```json
{
  "ai_flows": [
    {
      "slug": "lang-ai-customer",
      "framework": "langgraph",
      "prompts": [
        {
          "name": "intent_classifier",
          "source": "backend/engines/langgraph/prompts/intent.py:1-25",
          "body": "You are an intent classifier...",
          "is_dynamic": false,
          "source_hash": "sha256:abc...",
          "model_hint": "gemini-flash",
          "extraction_method": "module-constant"
        }
      ],
      ...
    }
  ]
}
```

---

## 6. Heading map 補項

`scripts/architect/lang.py` 加:

```python
"## Purpose": "## 流程目的",
"## Graph topology": "## 圖結構",
"## State schema": "## 狀態 schema",
"## Prompts": "## Prompts 目錄",
"## LLM config": "## LLM 設定",
"## Evaluation & observability": "## 評估與觀測",
```

(`## Design strengths` / `## Design weaknesses` / `## Improvement opportunities` / `## Dependencies` 已在 v3 加過。)

---

## 7. Sections.py 改動

### 7.1 `_BLOCK_NAMES`

加新 entry:

```python
"ai-flow": (
    "purpose",
    "graph-topology",
    "state-schema",
    "prompts",
    "llm-config",
    "evaluation",
    "strengths",
    "weaknesses",
    "improvements",
    "dependencies",
),
```

### 7.2 `SECTION_TYPES`

```python
"ai-flow": "architecture-ai-flow",
```

### 7.3 `_BLOCK_HEADINGS`

加 5 個新 block heading:

```python
"graph-topology": "## Graph topology",
"state-schema": "## State schema",
"prompts": "## Prompts",
"llm-config": "## LLM config",
"evaluation": "## Evaluation & observability",
```

(`purpose` / `strengths` / `weaknesses` / `improvements` / `dependencies` 已存在。)

### 7.4 新 prompt builder

`build_ai_flow_prompt(*, flow: AIFlow, repomix_packed: str, output_lang: str) -> str`

prompt 強制:
- 不入 prompt 全文,只列 inventory + 用途 + source path:line
- Graph topology 用 Mermaid graph TD,每個 node 標 source
- State schema 抓 TypedDict 定義原 Python 形式
- LLM config 整理成表
- Imps 必須有 Evidence,跟 module 一致

### 7.5 Migration

舊 vault(沒 ai-flows/)首次 v4.1 跑時:
- Scanner 偵測 AI flows
- 若有 ≥ 1 個 → 創 `Architecture/ai-flows/` 資料夾並產 note(s)
- modules/backend.md 等被影響的 module 補 1 行 `**AI engine:** [[ai-flows/<flow>]]`(via @generated:start ai-engine-link block,sentinel-aware)
- 沒 AI 子系統的 project → 完全不創 ai-flows/

不需要 tar.gz 全 backup(v4.1 是純 additive,不刪檔)。但對被改 module 加 1-line wikilink 那段,該 sentinel block 名為 `ai-engine-link`,refresh 可重生。

---

## 8. Lockfile schema 微擴

v4 lockfile 不重做 (version still 4)。加新 entries,含 per-prompt source-hash:

```json
{
  "version": 4,
  "frame": "report-v4",
  "ai_flows": {
    "lang-ai-customer": {
      "signal-hash": "sha256:...",
      "lang": "zh-TW",
      "framework": "langgraph",
      "node-blocks-hash": "sha256:...",
      "last-generated": "2026-05-28T...",
      "prompts": {
        "intent_classifier": {
          "source-hash": "sha256:abc...",
          "source": "backend/engines/langgraph/prompts/intent.py:1-25",
          "is_dynamic": false
        },
        "rag_answer": {
          "source-hash": "sha256:def...",
          "source": "backend/engines/langgraph/prompts/answer.py:30-90",
          "is_dynamic": false
        },
        "safety_check": {
          "source-hash": "sha256:dynamic",
          "source": "(see ai-flow note `## Prompts` body)",
          "is_dynamic": true
        }
      }
    },
    "qa-to-kb": { ... }
  }
}
```

`scripts/architect/lockfile.py` `Lockfile` dataclass 加 `ai_flows: dict = field(default_factory=dict)`。

**Refresh 邏輯:**
- Re-run scan → 每個 prompt 算 source-hash
- 對比 lockfile 該 prompt entry 的 source-hash:
  - 一致 → 跳過該 prompt sentinel,不 regen
  - 不一致(或 prompt 不存在於 lockfile)→ regen 該 prompt sentinel block
- AI flow note 整體 signal-hash 是 prompts source-hash + graph topology + state + LLM config 的綜合 hash
- Dynamic prompts 的 source-hash 是 "sha256:dynamic" 固定值(因為動態無法穩定 hash);它們不參與 drift refresh

`section_signal_was_changed` 加 ai_flows 分支(或拓展為通用 `entry_changed(category, name, ...)`)。

---

## 9. /obsidian-roadmap 改動

`scripts/roadmap/candidates.py` `detect_candidates` 擴展讀檔範圍:

v4: `overview.md`, `modules/*.md`, `decisions.md`
v4.1: + `ai-flows/*.md`(若 dir 存在)

每個 ai-flow note 的 `## 改進機會` block 抓出來,kind="improvement"。Evidence 中通常含 `[[modules/<host>]]` 跟 `[[ai-flows/...]]`,正確標 cross-cut。

---

## 10. Command body 改動

`commands/obsidian-architect.md`:

### 加 Phase 3.7 — AI Flow synthesis(在 module synthesis 之後、overview synthesis 之前)

```markdown
## Phase 3.7: AI Flow synthesis (v4.1)

For each AI flow detected in `scan_report["ai_flows"]`:

1. Run repomix on the flow's `root_path`:
   ```bash
   repomix --include "<root_path>/**" --style xml --compress --top-files-len 30
   ```

2. Build prompt via `build_ai_flow_prompt(flow, repomix_packed, output_lang)`.

3. Invoke LLM. Expect strict JSON with 10 block keys.

4. Validate:
   - `graph-topology` block must contain `\`\`\`mermaid` and `graph TD`
   - `prompts` block must NOT contain full prompt text (only inventory + paths)
     — if it does, ask LLM to retry with stricter "inventory-only" directive
   - `improvements` parse-able via `parse_improvements_block(...)`, ≥ 1 Imp

5. Compose via `compose_note(section="ai-flow", ...)`.

6. Write to `Projects/<P>/Architecture/ai-flows/<flow-slug>.md`.

7. Update lockfile `ai_flows[<slug>]` entry.

8. For each module that hosts an AI flow (e.g. backend hosts `lang-ai-customer`),
   update that module note's `@generated:start ai-engine-link` block:
   ```markdown
   **AI engine:** [[ai-flows/lang-ai-customer]] (LangGraph; real-time chat)
   ```

### 加 overview Phase 4 變化

Overview Module map 段每個有 AI engine 的 module 後加 `+ AI: [[ai-flows/<slug>]]` 標記。

Overview Drill-down entries 段加 `[[ai-flows/...]]` 連結(若 ai-flows/ 資料夾存在)。

### 加 --no-ai-flows flag

`--no-ai-flows` — 即使 scanner 偵測到 AI flow,也不產 ai-flows/ note。給「我不想分這層」的 user。預設 OFF(會產)。

---

## 11. 檔案改動清單

| 檔 | 改動 |
|---|---|
| `scripts/architect/ai_flow.py` (新) | `AIFlow` dataclass + `detect_ai_flows(repo_root) -> list[AIFlow]` + per-framework 偵測子函式 |
| `scripts/architect/prompt_extract.py` (新) | `ExtractedPrompt` dataclass + `extract_prompts(flow_root)` + 4 個 extractor (toml / module-constant / SYSTEM_PROMPT / langchain ChatPromptTemplate) + dynamic detector |
| `scripts/architect/sections.py` | 加 `_BLOCK_NAMES["ai-flow"]` + `SECTION_TYPES["ai-flow"]` + 5 個 `_BLOCK_HEADINGS` + `build_ai_flow_prompt` + `_preamble_for` 加 ai-flow entry |
| `scripts/architect/scan.py` | call `detect_ai_flows`,結果寫進 scan_report["ai_flows"] |
| `scripts/architect/lockfile.py` | `Lockfile.ai_flows` field;`section_signal_was_changed` 擴展 |
| `scripts/architect/lang.py` | 5 個新 heading map entries |
| `scripts/roadmap/candidates.py` | `detect_candidates` 加讀 `ai-flows/*.md` 的 `## 改進機會` |
| `commands/obsidian-architect.md` | Phase 3.7 AI Flow synthesis;Overview phase 加 ai-flow drill-down;`--no-ai-flows` flag |
| `references/ai-first-rules.md` | 加 `architecture-ai-flow` schema |
| `tests/architect/test_ai_flow.py` (新) | detector tests:LangGraph fixture / LangChain fixture / custom-pipeline fixture / non-AI fixture (should detect 0) |
| `tests/architect/test_prompt_extract.py` (新) | extraction tests:toml-config / module-constant / SYSTEM_PROMPT / langchain ChatPromptTemplate / dynamic detection / source-hash 計算 |
| `tests/architect/test_sections.py` | 加 ai-flow block/prompt tests |
| `tests/architect/test_scan.py` | scan_report 含 ai_flows key |
| `tests/roadmap/test_candidates.py` | Phase 1 也讀 ai-flows |
| `CHANGELOG.md` | Unreleased entry |
| `SKILL.md` | Layer 1 architect 描述加 AI flow |
| `README.md` | Commands table 加註 |

---

## 12. Trade-offs(有意識)

- **多了 1 個檔案類別,違反 v4 收斂方向?** 不違反。v4 砍 6 個重複/無用檔;v4.1 加的是 AI 特有判斷,屬於「該獨立的內容」,而不是「散頁拼湊」。對沒 AI 的 project,完全不出現(scanner 偵測 0)。
- **scanner false-positive 風險**(誤判 1-2 個 LLM call 為 AI flow):用「至少 3 個 node」門檻過濾。仍偶有誤判,但偏 false-negative 比 false-positive 安全 — owner 可手動跑 `--with-ai-flow=<root>` 強制標。
- **Prompts 全文入 vault + source-hash drift refresh:** Trade-off 是 vault 內容大(每個 ai-flow note 多 N × prompt-length KB)。對策:(1) collapsible callout 預設收起,讀檔感覺不沉重;(2) per-prompt sentinel + source-hash 讓 refresh 只重生有變的 prompt;(3) 動態組合 prompt 不硬抽,避免「合成的假全文」誤導。對 AI-first vault 自包含原則,full text 比 inventory-only 更對。
- **modules note 加 1-line wikilink** 可能讓 module note 看起來「被切了」 — mitigation:用 `**AI engine:**` 明確 label,長度短(1 line)。
- **`--no-ai-flows` flag** 是逃生口,給 user 不喜歡這層的選擇。

---

## 13. 驗收條件

對 langlive-line-oa 跑 `/obsidian-architect /Users/leric/Desktop/code/langlive-line-oa --refresh`(v4.1)應該:

- [ ] `Architecture/ai-flows/` 資料夾被創建
- [ ] `Architecture/ai-flows/lang-ai-customer.md` 存在,frontmatter `type: architecture-ai-flow`、`ai-framework: langgraph`、`flow-kind: real-time-chat`
- [ ] `Architecture/ai-flows/qa-to-kb.md` 存在,frontmatter `ai-framework: custom-pipeline`、`flow-kind: batch-pipeline`
- [ ] 兩個 ai-flow note 都有 10 段 body(包含 Graph topology 含 Mermaid graph TD、State schema 含 TypedDict、Prompts 段、LLM config 表)
- [ ] **Prompts 段包含每個 prompt 的全文**(via `> [!quote]-` collapsible callout 包在 `@generated:start prompt-<slug> source-hash=...` sentinel)
- [ ] **動態組合 prompt** 不抽全文,標 `Type: dynamic` + 列組合 path
- [ ] 每個 prompt sentinel 的 `source-hash` 在 lockfile `ai_flows[<slug>].prompts[<name>].source-hash` 對應一致
- [ ] 改動 source 端 prompt 文字 + re-run architect → 該 prompt 的 sentinel block 被 regen,其他 prompt block 不動
- [ ] 每個 ai-flow note `## 改進機會` 段 ≥ 2 個 Imp,strict 5-field
- [ ] `modules/backend.md` 含 `**AI engine:** [[ai-flows/lang-ai-customer]]` 一行
- [ ] `modules/modules.md` 含 `**AI engine:** [[ai-flows/qa-to-kb]]` 一行
- [ ] `overview.md` `## Module map` 段每個 AI module 標 `+ AI: [[...]]`
- [ ] `overview.md` `## Drill-down entries` 含 `[[ai-flows/...]]` 連結
- [ ] `_manifest.lock.json` `ai_flows` block 含 2 個 entries
- [ ] `/obsidian-roadmap langlive-line-oa` Phase 1 candidates 包含 ai-flows 的 Imps
- [ ] `--no-ai-flows` 跑同 project → 不產 ai-flows/,modules note 不加 ai-engine-link
- [ ] 全測試通過,4 adapter build OK
- [ ] 對「無 AI codebase」smoke(例 obsidian-second-brain 自己)→ `ai-flows/` 不被創建

---

## 14. 開放問題

無。本 brainstorm 階段所有分岔已決:

- 收容位置:`Architecture/ai-flows/` 平行於 modules/ — 已核准
- 10 段 schema(JTBD / Graph / State / Prompts / LLM / Eval / 優 / 缺 / 改進 / 相依) — 已核准
- Scanner 偵測 3 種框架(LangGraph / LangChain / custom-pipeline) — 隱含核准
- Prompts 全文 + per-prompt sentinel + source-hash drift refresh + collapsible callout — 已核准
- modules/note 加 1-line wikilink — 隱含核准
- Migration purely additive — 隱含核准
- `--no-ai-flows` flag 退場機制 — 隱含核准
- `/obsidian-roadmap` Phase 1 擴展 — 隱含核准
