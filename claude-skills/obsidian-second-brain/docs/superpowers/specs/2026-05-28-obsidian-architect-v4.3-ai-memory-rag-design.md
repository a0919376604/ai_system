# obsidian-architect v4.3 — AI memory + RAG cross-flow notes Design

**Status:** Draft — ready for review
**Date:** 2026-05-28
**Author:** brainstormed with user (Eugeniu)
**Related specs:**
- [2026-05-28-obsidian-architect-v4.1-ai-flows-design.md](./2026-05-28-obsidian-architect-v4.1-ai-flows-design.md) — v4.1 AI flow layer (per-flow notes)
- [2026-05-28-obsidian-architect-v4.2-features-design.md](./2026-05-28-obsidian-architect-v4.2-features-design.md) — v4.2 features lens
- v4 consolidated report spec — referenced as base

---

## Goal

When `/obsidian-architect` detects ≥1 AI flow in a repo, additionally produce **two cross-flow notes**:

- `Projects/<P>/Architecture/ai-flows/memory.md` — AI memory architecture across all flows (lifecycle / TTL / compaction / context window / long-term vs short-term split)
- `Projects/<P>/Architecture/ai-flows/rag.md` — Retrieval-augmented generation cross-flow pipeline (ingest → vector store → retrieve, embedding alignment, eval)

Both files focus on **cross-flow concerns and lifecycle** — the angle the v4.1 per-flow note can't carry because it scopes to one subsystem at a time.

## Why this matters (motivating examples from langlive-line-oa)

- **Embedding misalignment shipped silently.** `modules-qa-to-kb` uses OpenAI `text-embedding-3-small`; `engines-langgraph` uses Google `text-embedding-004`. Vector spaces don't align. The v4.1 per-flow notes individually note their own provider; only a cross-flow `rag.md` makes this mismatch jump out (and the `embedding-aligned: false` frontmatter field is what surfaces it to DataView).
- **No TTL on long-running session state.** `SimpleRedisSaver(key_prefix="simple_ckpt_v2")` has no documented expiry. Per-flow note says "Redis checkpointer"; cross-flow `memory.md` says "no eviction policy detected" as a first-class lifecycle concern.
- **No retrieval eval.** Both flows touch RAG but no metric tracks recall@k change after KB updates. `rag.md` `## Evaluation` becomes the single source of truth for "do we know if our RAG works?".

## Non-goals

- NOT replacements for per-flow `ai-flows/<slug>.md`. Those still own `state-schema`, `llm-config`, `prompts`, `graph-topology` at flow scope. memory.md and rag.md wikilink OUT to per-flow detail rather than duplicate.
- NOT documentation of the `langchain.memory.*` API or `chromadb` API. We document THIS PROJECT'S memory + RAG patterns, not the libraries.
- NOT per-flow files. The user explicitly chose "two files" (cross-cutting). Multi-flow projects get one memory.md covering all of them.
- NOT triggered by `--frame=judgment` or `--frame=description` (legacy). v4.3 is `report-v4` only.

## Trigger conditions

| AI flow signal state | memory.md | rag.md |
|---|---|---|
| 0 AI flows detected | SKIP | SKIP |
| ≥1 AI flow, 0 memory signals | WRITE (acknowledges all-stateless) | per-rag-rule |
| ≥1 AI flow, ≥1 memory signal | WRITE | per-rag-rule |
| ≥1 AI flow, 0 vector store + 0 embedding lib | per-memory-rule | WRITE (acknowledges no-RAG; useful negative finding) |
| ≥1 AI flow, ≥1 RAG signal | per-memory-rule | WRITE |

Default ON. Flags `--no-ai-memory` and `--no-ai-rag` disable per-file.

## Frame & file shape

**Files:** `Projects/<P>/Architecture/ai-flows/memory.md` and `Projects/<P>/Architecture/ai-flows/rag.md`
**Types (frontmatter):** `architecture-ai-memory` and `architecture-ai-rag` (two NEW SECTION_TYPES)
**Frame:** stays `report-v4` (no lockfile schema bump; additive slots `ai_memory` + `ai_rag` on `Lockfile`)
**Lang:** respects vault `output-lang`

## Frontmatter

`memory.md`:

```yaml
---
type: architecture-ai-memory
date: YYYY-MM-DD
project: "[[<P>]]"
local-path: "/abs/path/to/repo"           # or repo: "<url>"
last-scanned: YYYY-MM-DD
commit: <sha>
sources: ["scan: ai_memory", "ai-flows: <slug1>, <slug2>, ...", "manifest: modules"]
confidence: high                          # high when concrete checkpointer detected; medium when inferred
lang: zh-TW
tags: [architecture, ai-memory]
ai-first: true
status: current
memory-flows: 1                           # number of AI flows with detected memory
stateless-flows: 1                        # number of AI flows with NO memory
backend: "redis"                          # primary backend; "mixed" if multiple; "none" if all stateless
---
```

`rag.md`:

```yaml
---
type: architecture-ai-rag
date: YYYY-MM-DD
project: "[[<P>]]"
local-path: "/abs/path/to/repo"
last-scanned: YYYY-MM-DD
commit: <sha>
sources: ["scan: ai_rag", "ai-flows: <slug1>, <slug2>, ...", "manifest: modules"]
confidence: high
lang: zh-TW
tags: [architecture, ai-rag]
ai-first: true
status: current
rag-flows-read: 1                         # number of flows doing retrieve
rag-flows-write: 1                        # number of flows doing ingest
vector-store: "weaviate"                  # primary store; "mixed" / "none"
embedding-aligned: false                  # true if write-side and read-side use same embedding model; null when only one side exists
---
```

The `embedding-aligned` field is the **money-shot** for cross-project DataView ("show all my projects where embedding-aligned: false").

## Body block design

### memory.md (11 blocks)

| # | Block name | H2 (zh-TW) | H2 (en) | Content |
|---|---|---|---|---|
| 1 | `summary` | `## 摘要` | `## Summary` | 1 paragraph. Which flows have memory (wikilinks), which are stateless, backend in one line, policy one line. |
| 2 | `flow-memory-map` | `## 各流程記憶機制` | `## Per-flow memory map` | Markdown table: Flow \| Has memory \| Backend \| Scope \| Persistence \| Wikilink to `[[ai-flows/<slug>]]`. |
| 3 | `backend-and-storage` | `## 儲存層` | `## Backend & storage` | Backend per flow (Redis / Postgres / file / in-memory), serializer (msgpack/JSON/pickle), key pattern, encryption-at-rest, backup policy. Each fact cites `code:path:line` from scanner. |
| 4 | `scope-and-lifecycle` | `## 範疇與生命週期` | `## Scope & lifecycle` | session-scoped vs user-scoped vs request-scoped. Creation/destruction trigger. Orphan cleanup job (exists? where?). **TTL & eviction policy** — when undetected, state plainly "no TTL / eviction policy detected". |
| 5 | `context-window-management` | `## Context window 管理` | `## Context window management` | Reducer pattern (`add_messages_limited` etc.), max-tokens, truncation strategy, fallback when exceeded. |
| 6 | `compaction-strategy` | `## 壓縮策略` | `## Compaction strategy` | When summarizer triggers; which prompt (wikilink to `[[ai-flows/<slug>#Prompts]]`); frequency; storage path. |
| 7 | `long-term-vs-short` | `## 長期 vs 短期記憶` | `## Long-term vs short-term memory` | Resumable session state vs cross-session knowledge. When NO long-term memory exists, plainly state so. |
| 8 | `strengths` | `## 設計優點` | `## Memory strengths` | 3-5 tight PM-aware bullets. |
| 9 | `weaknesses` | `## 設計缺點 / 風險` | `## Memory weaknesses` | Failure modes: unbounded growth / race conditions / serializer drift / cross-worker inconsistency / silent eviction. |
| 10 | `improvements` | `## 改進機會` | `## Memory improvements` | 3-5 ImprovementItem (`Why / Evidence / Effort / Risk / Confidence`). |
| 11 | `dependencies` | `## 相依` | `## Dependencies` | Wikilinks only. |

### rag.md (11 blocks)

| # | Block name | H2 (zh-TW) | H2 (en) | Content |
|---|---|---|---|---|
| 1 | `summary` | `## 摘要` | `## Summary` | Which flows read, which write, vector store, primary embedding, **embedding-aligned flag** explicit one-liner. |
| 2 | `rag-data-flow` | `## RAG 資料流` | `## RAG data flow` | ONE Mermaid graph: ingest pipeline (writer flow) → vector store → retrieve (reader flow). |
| 3 | `ingest-pipeline` | `## Ingest 管線` | `## Ingest pipeline` | Write side: chunking (splitter type, size, overlap), embedding provider/model/dims, upsert pattern, schema, re-index trigger. |
| 4 | `vector-store-config` | `## Vector store 設定` | `## Vector store config` | Store choice, schema, multi-tenancy, index versioning, capacity bound. |
| 5 | `retrieve-strategy` | `## Retrieve 策略` | `## Retrieve strategy` | Read side: search backend (hybrid α / BM25 / vector-only), top-k, rerank lib, MMR, metadata filter. |
| 6 | `embedding-providers` | `## Embedding providers` | `## Embedding providers` | Per-flow: lib + model + dims. **Vector space consistency check** — if write+read models differ, ⚠️ explicit. |
| 7 | `evaluation` | `## 評估` | `## Evaluation` | recall@k metrics, hit-rate tracking, golden-set, link to `evaluation/` sub-module if present. When absent, `> [!warning] 無 retrieve eval`. |
| 8 | `strengths` | `## 設計優點` | `## RAG strengths` | 3-5 tight bullets. |
| 9 | `weaknesses` | `## 設計缺點 / 風險` | `## RAG weaknesses` | Common: vector space mismatch / no eval / no incremental update / stale chunks. |
| 10 | `improvements` | `## 改進機會` | `## RAG improvements` | 3-5 ImprovementItem. |
| 11 | `dependencies` | `## 相依` | `## Dependencies` | Wikilinks only. |

### Voice constraints (both files)

- **No invention.** If a scanner field is `null` / `[]` / `false`, the prose MUST acknowledge absence verbatim (e.g. "未偵測到 TTL policy" — not "TTL likely 1h"). Hallucinated TTLs are worse than acknowledged unknowns.
- **Per-flow inventory must wikilink out** to `[[ai-flows/<slug>#<heading>]]` rather than rewriting `state-schema` or `llm-config`. memory.md's value-add is the LIFECYCLE LENS; rag.md's is the PIPELINE LENS.
- **When `embedding_aligned: false`** in rag.md: `## Embedding providers` MUST contain a ⚠️ row flagging the mismatch; `## 設計缺點` MUST include a bullet calling out the consequence; `## 改進機會` MUST include an Imp to align providers (`Confidence: stated`).
- **Code identifiers (paths, function names, env vars, model strings) stay English** even in zh-TW vaults. Prose around them is translated.

## Scanner additions

`scan_report.json` gains two top-level keys: `ai_memory` and `ai_rag`. Detection lives in two new pure-function helpers:

```python
# scripts/architect/ai_memory_detect.py
def detect_memory(repo_root: Path, ai_flows: list[AIFlow]) -> dict: ...

# scripts/architect/ai_rag_detect.py
def detect_rag(repo_root: Path, ai_flows: list[AIFlow]) -> dict: ...
```

### `detect_memory` return shape

```jsonc
{
  "per_flow": {
    "<flow-slug>": {
      "has_memory": true,
      "backends": ["redis"],                                   // {"redis","postgres","sqlite","file","in-memory","langchain"}
      "checkpointer_classes": ["SimpleRedisSaver"],            // class names imported / declared
      "checkpointer_sources": ["backend/.../simple_redis_saver.py:1"],
      "key_patterns": ["simple_ckpt_v2"],                      // string literals near checkpointer construction
      "reducer_funcs": ["add_messages_limited"],
      "reducer_caps": [{"name": "add_messages_limited", "limit": 100, "source": "..."}],
      "compaction_funcs": ["session_summary"],
      "compaction_sources": ["backend/.../utils/session_summary.py"]
    }
  },
  "summary": {
    "memory_flows": 1,
    "stateless_flows": 1,
    "primary_backend": "redis",                                // or "mixed" / "none"
    "uniform_backend": true                                    // true iff all memory flows use same backend
  }
}
```

### `detect_memory` patterns

| Backend | Detection pattern |
|---|---|
| LangGraph `MemorySaver` (in-memory) | `from langgraph.checkpoint.memory import MemorySaver` or class instantiation |
| LangGraph Redis | `from langgraph.checkpoint.redis import` OR class `*RedisSaver` (handles `SimpleRedisSaver` custom impls) |
| LangGraph Postgres | `from langgraph.checkpoint.postgres import` OR class `PostgresSaver` |
| LangGraph SQLite | `from langgraph.checkpoint.sqlite import` |
| Custom checkpointer | Class in flow's root that exposes `put` / `get` / `list` async methods AND is referenced as `checkpointer=` kwarg in graph compile |
| LangChain memory | `from langchain.memory import` (matches `ConversationBufferMemory`, `ConversationSummaryMemory`, etc.) |

Reducer detection: regex `r"def\s+(add_messages\w*|\w+_reducer)\s*\("` in state module files.

Reducer cap detection: when a reducer body contains `result[-N:]` or `result[:N]` or `if len(result) > N:`, extract `N` as the cap.

Compaction detection: function names matching `r"\b(summarize|compact|summary|memory_update)\b"` in flow's `utils/` or `nodes/` subfolders.

### `detect_rag` return shape

```jsonc
{
  "per_flow": {
    "<flow-slug>": {
      "role": "read",                                          // "read" | "write" | "both" | "none"
      "vector_stores": ["weaviate"],                           // {"weaviate","chromadb","pinecone","qdrant","pgvector","lancedb","faiss"}
      "vector_store_sources": ["backend/.../weaviate_*.py"],
      "embedding_libs": ["google_generativeai"],
      "embedding_models": ["models/text-embedding-004"],
      "embedding_dims": null,                                  // when extractable from constants
      "retrieve_params": {"hybrid_alpha": 0.8, "top_k": 12, "rerank_top_k": 6},
      "rerank_libs": ["jina-reranker"],
      "chunking": null                                          // or {"strategy": "...", "size": N, "overlap": N, "source": "..."}
    }
  },
  "summary": {
    "read_flows": 1,
    "write_flows": 1,
    "vector_stores": ["weaviate"],
    "embedding_aligned": false,
    "alignment_mismatch": [
      {"write": {"flow": "modules-qa-to-kb", "model": "text-embedding-3-small"},
       "read":  {"flow": "engines-langgraph", "model": "models/text-embedding-004"}}
    ]
  }
}
```

### `detect_rag` patterns

| Signal | Pattern |
|---|---|
| Vector store libs | imports of `weaviate`, `chromadb`, `pinecone`, `qdrant_client`, `lancedb`, `faiss`, `langchain_weaviate.vectorstores`, `pgvector` |
| Embedding libs | `OpenAIEmbeddings`, `GoogleGenerativeAIEmbeddings`, `CohereEmbeddings`, `langchain_openai`, `sentence_transformers` |
| Embedding model strings | regex match on `r"(text-embedding-[0-9a-z\-]+|models/text-embedding-[0-9a-z\-]+|all-MiniLM-[0-9a-z\-]+|embedding-[a-z0-9\-]+)"` in source files |
| Chunking | imports of `RecursiveCharacterTextSplitter`, `CharacterTextSplitter`, `SemanticSplitterNodeParser`; OR functions named `chunk_*` / `*_chunker` that return lists |
| Rerank | imports of `JinaReranker`, `CohereRerank`, `sentence_transformers.CrossEncoder` |
| Retrieve params | regex `r"(top_k|hybrid_alpha|alpha|fetch_k|rerank_num)\s*=\s*([0-9.]+|\w+)"` in retrieve calls |

### Read/write role classifier

```text
For each flow:
  if any embed call (`embed_documents` / `embed_query`) AND any upsert (`.add` / `.upsert` / `.add_documents`):
    role = "write"
  if any search call (`.similarity_search` / `.hybrid` / `.search` / `.query`):
    role |= "read"   # may be both
  if role unset:
    role = "none"
```

### `embedding_aligned` computation

```text
write_models = union of embedding_models from all flows where role contains "write"
read_models  = union of embedding_models from all flows where role contains "read"

if write_models is empty OR read_models is empty:
    embedding_aligned = null   # only one side exists; not applicable
elif write_models == read_models:
    embedding_aligned = true
else:
    embedding_aligned = false
    alignment_mismatch = pairs of (write_flow, write_model, read_flow, read_model)
```

### Scanner integration

`scripts/architect/scan.py` after `detect_ai_flows(...)` call:

```python
from scripts.architect.ai_memory_detect import detect_memory
from scripts.architect.ai_rag_detect import detect_rag

scan_report["ai_memory"] = detect_memory(repo_root, scan_report["ai_flows"])
scan_report["ai_rag"]    = detect_rag(repo_root, scan_report["ai_flows"])
```

When `ai_flows == []`, both helpers return `{"per_flow": {}, "summary": {...zeros...}}` and downstream synthesis is skipped.

## LLM synthesis (Phase 3.8 + 3.9)

Two new prompt builders in `sections.py`:

```python
def build_ai_memory_prompt(
    *,
    project: str,
    ai_memory_signals: dict,          # scan_report["ai_memory"]
    ai_flows_summary: dict,            # list of {slug, framework, root_path} for cross-link integrity
    output_lang: str,
) -> str: ...

def build_ai_rag_prompt(
    *,
    project: str,
    ai_rag_signals: dict,              # scan_report["ai_rag"]
    ai_flows_summary: dict,
    output_lang: str,
) -> str: ...
```

Both return strings instructing the LLM to emit strict JSON with the 11 block keys defined in their respective `_BLOCK_NAMES` entry.

Critical rules baked into prompts:
1. NO invention. If a signal field is empty/null/false, prose must say so.
2. Wikilink-out per-flow detail to `[[ai-flows/<slug>#<heading>]]` rather than rehash.
3. When `embedding_aligned: false`, weaknesses and improvements blocks MUST flag the mismatch (rag.md only).
4. PM-friendly enough that a tech lead reading without deep AI background gets the lifecycle/pipeline story.
5. Mermaid diagrams in `rag-data-flow` block must include source `path` annotations on each node.

## Composer + extra frontmatter

```python
def compose_ai_memory_note(
    *, project, repo_label, commit, signal_sources, confidence,
    output_lang, generated_blocks,
    memory_flows: int, stateless_flows: int, backend: str,
) -> str:
    note = compose_note(section="ai-memory", project=project, ...)
    extra_fm = (
        f"memory-flows: {memory_flows}\n"
        f"stateless-flows: {stateless_flows}\n"
        f'backend: "{backend}"\n'
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)


def compose_ai_rag_note(
    *, project, repo_label, commit, signal_sources, confidence,
    output_lang, generated_blocks,
    rag_flows_read: int, rag_flows_write: int, vector_store: str,
    embedding_aligned: bool | None,
) -> str:
    note = compose_note(section="ai-rag", project=project, ...)
    aligned_value = "null" if embedding_aligned is None else str(embedding_aligned).lower()
    extra_fm = (
        f"rag-flows-read: {rag_flows_read}\n"
        f"rag-flows-write: {rag_flows_write}\n"
        f'vector-store: "{vector_store}"\n'
        f"embedding-aligned: {aligned_value}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

## Lockfile additions

Two new optional slots on the `Lockfile` dataclass (additive — no schema bump):

```python
@dataclass
class Lockfile:
    # ... existing fields ...
    ai_memory: dict = field(default_factory=dict)
    ai_rag: dict = field(default_factory=dict)
```

Slot contents per synthesis:

```jsonc
{
  "ai_memory": {
    "signal-hash": "sha256:...",
    "lang": "zh-TW",
    "last-generated": "YYYY-MM-DD",
    "commit": "<sha>",
    "memory_flows": 1,
    "stateless_flows": 1,
    "backend": "redis"
  },
  "ai_rag": {
    "signal-hash": "sha256:...",
    "lang": "zh-TW",
    "last-generated": "YYYY-MM-DD",
    "commit": "<sha>",
    "rag_flows_read": 1,
    "rag_flows_write": 1,
    "vector_store": "weaviate",
    "embedding_aligned": false
  }
}
```

## Refresh logic

`memory.md` signal hash composition:
- SHA-256 over canonical JSON of `scan_report["ai_memory"]`
- PLUS each AI flow's `state-schema` block content hash from its `ai-flows/<slug>.md` (because memory shape changes when state shape changes)

`rag.md` signal hash composition:
- SHA-256 over canonical JSON of `scan_report["ai_rag"]`
- PLUS each AI flow's `llm-config` block content hash (embedding model lives there)

When signal-hash unchanged AND file exists AND not `--force`/`--refresh`: skip synthesis.

## Roadmap (`/obsidian-roadmap`) integration

`detect_candidates` extends to walk both new files when present:

| Block parsed | Candidate type | Default priority |
|---|---|---|
| `ai-flows/memory.md` `## 改進機會` | `ai-memory-improvement` | `normal` |
| `ai-flows/rag.md` `## 改進機會` | `ai-rag-improvement` | **`high` when Evidence references `embedding-aligned: false` mismatch OR `evaluation` absence; `normal` otherwise** |

Dedup pass from v4.2 (Evidence wikilink overlap) extends transparently — no special-case code needed.

## Command surface

`/obsidian-architect` flags (additive to v4.1 + v4.2):

- `--no-ai-memory` — skip Phase 3.8. Default OFF.
- `--no-ai-rag` — skip Phase 3.9. Default OFF.
- `--skip-sections=ai-memory,ai-rag` — symmetric alias.
- `--ai-memory-only` / `--ai-rag-only` — diagnostic, runs Phase 1 + 3.7 (for cross-link integrity) + target phase only.

## Phase ordering in command body

Existing v4 + v4.1 + v4.2 phases plus two new:

```text
... Phase 1 (scan) ...
... Phase 1.5 / 1.6 (migrations) ...
... Phase 2 (manifest review) ...
... Phase 3 (modules) ...
... Phase 3.5 (decisions / personas) ...
... Phase 3.5.5 (features.md, v4.2) ...
... Phase 3.7 (per-flow ai-flows/<slug>.md, v4.1) ...
*** NEW: Phase 3.8 (ai-flows/memory.md, v4.3) ***
*** NEW: Phase 3.9 (ai-flows/rag.md, v4.3) ***
... Phase 4 (overview.md) ...
... Hub note + activity log ...
```

Phase 3.8 / 3.9 MUST run AFTER Phase 3.7 so per-flow notes exist for cross-link integrity check. If a wikilink to `[[ai-flows/<slug>]]` in the new file would dangle, log a warning (don't fail).

## Hub note + overview drill-down

After Phase 3.9 succeeds, idempotent updates:

- Project hub `## 架構` block: add line `- AI memory + RAG 深判斷 (v4.3): [[Architecture/ai-flows/memory]] | [[Architecture/ai-flows/rag]]`
- `overview.md ## 想深讀的入口`: add line `- **AI 跨流程深判斷:** [[ai-flows/memory]] (lifecycle + TTL + compaction) | [[ai-flows/rag]] (data flow + embedding 對齊)`

Both edits sentinel-aware (no duplicate insertion on re-run).

## Migration / existing-vault handling

- v4.x vault without memory.md / rag.md: Phase 3.8 / 3.9 writes the files. No migration.
- v4.x vault with these files already: signal-hash comparison; refresh or skip.
- v3 / v2 vaults: existing v3→v4 / v2→v3 migrations don't touch ai-flows/. After upgrade, next scan writes them.
- Lockfile schema not bumped. `Lockfile.load()` must tolerate missing `ai_memory` / `ai_rag` keys (default to `{}`).

## Overlap safety (sanity check against v4.1 per-flow note)

Explicit rule: blocks here are LIFECYCLE / PIPELINE / CROSS-FLOW. Not state shape, not graph topology, not prompt text. Where overlap is unavoidable, the new file wikilinks IN to ai-flow rather than copies.

| v4.1 ai-flow block | v4.3 memory.md or rag.md analog | Resolution |
|---|---|---|
| `state-schema` | None — memory.md does NOT repeat state shape | Wikilink: `[[ai-flows/<slug>#State schema]]` from `flow-memory-map` table row |
| `llm-config` (embedding model row) | rag.md `embedding-providers` | rag.md aggregates across flows + adds alignment check; per-flow detail stays in ai-flow |
| `evaluation` (eval framework presence) | rag.md `evaluation` | rag.md focuses RAG eval specifically (recall@k); ai-flow's eval is broader (intent classification eval, LLM judge, etc.) — distinct concerns |
| `dependencies` | both new files have own `dependencies` block | Wikilinks differ — ai-flow points to host module; memory/rag point to all involved flows + decisions |

## Tests (TDD coverage required)

`tests/architect/test_ai_memory_detect.py`:
1. `detect_memory` recognizes `SimpleRedisSaver` custom class as redis backend.
2. `detect_memory` recognizes `from langgraph.checkpoint.memory import MemorySaver` as in-memory.
3. `detect_memory` returns `has_memory=false` when flow has no checkpointer.
4. `detect_memory` extracts reducer cap from `result[-100:]` pattern.
5. `detect_memory.summary.uniform_backend` is `true` iff all flows share one backend.

`tests/architect/test_ai_rag_detect.py`:
6. `detect_rag` classifies a flow with `.similarity_search` calls as `role: read`.
7. `detect_rag` classifies a flow with `.add_documents` calls as `role: write`.
8. `detect_rag` extracts `top_k=12, hybrid_alpha=0.8` from retrieve calls.
9. `detect_rag` extracts embedding model string `text-embedding-3-small` from source.
10. `detect_rag.summary.embedding_aligned=false` when write model != read model.
11. `detect_rag.summary.embedding_aligned=null` when only one side exists.
12. `detect_rag` returns empty per_flow when ai_flows is empty.

`tests/architect/test_features.py` (new tests in existing file, or new test_ai_memory_compose.py):
13. `build_ai_memory_prompt` requires all 11 block keys in returned JSON instructions.
14. `build_ai_memory_prompt` instructs LLM to wikilink-out to `[[ai-flows/<slug>]]` for state-schema.
15. `build_ai_rag_prompt` emits explicit warning instruction when `embedding_aligned=false`.
16. `compose_ai_memory_note` emits `memory-flows` / `stateless-flows` / `backend` extra frontmatter before `ai-first: true`.
17. `compose_ai_rag_note` emits `embedding-aligned: false` when bool, `embedding-aligned: null` when None.

`tests/architect/test_lockfile.py`:
18. Lockfile round-trips `ai_memory` and `ai_rag` slots cleanly.

`tests/architect/test_lang.py`:
19. Heading map includes 6 new keys: Per-flow memory map, Backend & storage, Scope & lifecycle, Context window management, Compaction strategy, Long-term vs short-term, RAG data flow, Ingest pipeline, Vector store config, Retrieve strategy.

`tests/roadmap/test_candidates.py`:
20. `detect_candidates` walks `ai-flows/memory.md` and picks up `ai-memory-improvement` candidates.
21. `detect_candidates` walks `ai-flows/rag.md`; embedding-aligned-evidence raises priority to `high`.

End-to-end smoke (Task in plan, not unit test):
22. Run scanner against `langlive-line-oa`; verify `ai_memory.per_flow["engines-langgraph"].has_memory == true` and `ai_rag.summary.embedding_aligned == false`.

## Out of scope (deferred)

- **Live recall@k measurement.** This spec documents whether eval EXISTS, not measures it. Wiring a real eval harness is a separate `/obsidian-rag-eval` command.
- **Cross-project memory/RAG comparison dashboard.** Frontmatter has the fields ready (`memory-flows`, `embedding-aligned`); DataView template is its own task.
- **Auto-suggest embedding migration patches.** rag.md flags misalignment as Imp; actual code change is owner's call.
- **Memory provider abstraction layer.** Refactor recommendation may surface as an Imp; not an architect concern.

## File-level shape preview (langlive case, illustrative)

`Architecture/ai-flows/memory.md`:

```markdown
---
type: architecture-ai-memory
...
memory-flows: 1
stateless-flows: 1
backend: "redis"
---

## 給未來 Claude
本檔是 AI 記憶層的跨流程深判斷:lifecycle、TTL、compaction。Per-flow state shape 請見 [[Architecture/ai-flows/<slug>#State schema]]。

## 摘要
<!-- @generated:start summary -->
1 個 flow 有 memory ([[ai-flows/engines-langgraph]]),1 個無 ([[ai-flows/modules-qa-to-kb]],檔案落地式)。Backend: Redis 透過 SimpleRedisSaver,key prefix `simple_ckpt_v2`,**無 TTL / eviction policy 偵測到**。
<!-- @generated:end summary -->

## 各流程記憶機制
<!-- @generated:start flow-memory-map -->
| Flow | 有 memory | Backend | Scope | Persistence | 詳細 |
| --- | --- | --- | --- | --- | --- |
| engines-langgraph | ✅ | redis | session (thread_id) | SimpleRedisSaver 跨 worker | [[ai-flows/engines-langgraph#State schema]] |
| modules-qa-to-kb | ❌ stateless | — | per-stage file | stage{N}/all.json | [[ai-flows/modules-qa-to-kb#State schema]] |
<!-- @generated:end flow-memory-map -->

(... 9 more blocks ...)
```

`Architecture/ai-flows/rag.md`:

```markdown
---
type: architecture-ai-rag
...
rag-flows-read: 1
rag-flows-write: 1
vector-store: "weaviate"
embedding-aligned: false
---

## 摘要
<!-- @generated:start summary -->
2 個 AI flow 構成完整 RAG pipeline。Write 端: [[ai-flows/modules-qa-to-kb]] 用 OpenAI `text-embedding-3-small` 寫 Weaviate。Read 端: [[ai-flows/engines-langgraph]] 用 Google `text-embedding-004` 查 Weaviate。**⚠️ embedding 不對齊** — 寫端與讀端使用不同 provider,vector space 不一致,recall 受影響。
<!-- @generated:end summary -->

(... 10 more blocks ...)
```

## Success criteria

This design ships when:

- [x] User approved location + trigger (Section 1).
- [x] User approved block taxonomy (Section 2).
- [x] User approved scanner + LLM + lockfile + roadmap design (Section 3).
- [ ] Spec self-review passes.
- [ ] User reviews this written spec.
- [ ] Implementation plan written via `writing-plans` skill.
- [ ] Implementation lands; `langlive-line-oa` smoke produces `memory.md` flagging "no TTL detected" and `rag.md` flagging `embedding-aligned: false`.
