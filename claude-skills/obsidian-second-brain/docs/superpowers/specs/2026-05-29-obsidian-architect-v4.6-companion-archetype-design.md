# obsidian-architect v4.6 — AI Companion Archetype (4-layer schema) Design

**Status:** Draft — ready for review
**Date:** 2026-05-29
**Author:** brainstormed with user (Eugeniu)
**Related:**
- v4.1 ai-flow per-subsystem schema (`scripts/architect/ai_flow.py` detector + sections.py 10-block schema)
- v4.3 ai-memory + ai-rag cross-flow schemas
- v4.2 features.md PM lens
- v4.5 architect+board merge
- Research dossiers in `Projects/ai-eden-service/Research/` informing the 4-layer pattern

---

## Goal

Extend `/obsidian-architect` so AI companion-bot projects (Character Card / World / Storyline / Memory archetype) get **5 dedicated Architecture/ai-flows/ notes** instead of being missed by the LangGraph-shaped v4.1 detector. Fix the detector bug that gave `ai-eden-service` "0 AI flows detected" despite the project having LLMs + 4 distinct AI layers.

## Why

**Driving evidence:** `ai-eden-service` shows the full 4-layer pattern in code:
- `app/characters/definitions/` — Character Card layer
- `app/characters/worlds/` — World layer
- `app/characters/storyline.py` + `storyline_dsl.py` — Storyline layer
- `app/store.py` + `app/providers/` — Memory + LLM layer

But `/obsidian-architect` ran against it and reported "0 AI flows detected (project rolls its own state-inference; no LangGraph)". The v4.1 `detect_ai_flows` only looks for `graph.py` / `pipeline.py` in `agents/workflows/engines/qa_to_kb/` dirs, plus LangGraph imports — none of which match this project.

Beyond the detector bug, the 4-layer pattern is a **recognized domain archetype** (per the user's 5 research dossiers covering LunaTalk / Narratium / Replika / Companion-vs-Story-RPG / generic companion build blueprint). Documenting Character / World / Storyline as first-class lenses gives owners much better coverage than shoehorning them into the existing v4.1 ai-flow's 10 generic blocks.

## Non-goals

- NOT replacing v4.1 ai-flow schema. LangGraph / LangChain / custom-pipeline projects keep using `ai-flows/<slug>.md`. The new 4-layer schema is **additive** and triggered only when companion archetype is detected.
- NOT replacing v4.3 `memory.md`. The Memory layer reuses the existing `architecture-ai-memory` schema verbatim — no new section type for it.
- NOT inventing the 4 layers' content for projects that lack code evidence. Frontmatter override CAN force the schema to render, but content blocks honor the "no invention" rule from earlier v4.x specs.
- NOT changing `/obsidian-board`, `/obsidian-research(-deep)`, `/obsidian-brainstorm`, or `/obsidian-roadmap` command bodies. Scope is `/obsidian-architect` only.
- NOT renaming `local-path` frontmatter or any existing schema key.

## Scope

Touches **only** `/obsidian-architect` skill family:

1. **Detector** — `scripts/architect/ai_flow.py` loosens custom-pipeline branch; NEW `scripts/architect/companion_detect.py` adds 4-layer evidence walks + archetype gate.
2. **Sections** — 4 new SECTION_TYPES in `sections.py` (`character-card`, `world`, `storyline`, `companion-overview`); 4 new builders + 4 new composers; ~20 new heading mappings.
3. **Scanner** — `scan.py` adds `ai_companion` top-level key; lockfile gains `ai_companion: dict` slot.
4. **Command body** — Phase 3.7.5 inserted between v4.1 ai-flow and v4.3 ai-memory phases; `--no-companion` / `--companion-only` flags.
5. **Roadmap** — `detect_candidates` walks 3 new files (`character-card.md`, `world.md`, `storyline.md`) + cross-layer Evidence priority bump on `companion-overview.md`.
6. **Docs** — `references/ai-first-rules.md` 4 new schemas; SKILL / README / CHANGELOG.

## 4-layer file shape

When archetype = `ai-companion`, the following files land in `Projects/<P>/Architecture/ai-flows/`:

| File | New in v4.6 | Reuses |
|---|---|---|
| `character-card.md` | ✅ (9 blocks) | — |
| `world.md` | ✅ (10 blocks) | — |
| `storyline.md` | ✅ (11 blocks) | — |
| `companion-overview.md` | ✅ (9 blocks, cross-cutting) | — |
| `memory.md` | — | v4.3 `architecture-ai-memory` |
| `<flow-slug>.md` (per-subsystem) | — | v4.1 `architecture-ai-flow` (still produced if Phase 3.7 detects something) |

For hybrid projects (companion + langgraph engine), all of the above coexist.

## Frontmatter shape (new section types)

Each layer carries the standard v4-frontmatter PLUS layer-specific fields:

**`character-card.md`:**
```yaml
type: architecture-character-card
layer: character-card
depends-on: ["world", "storyline"]
mutated-by: []                          # cards are typically static
card-count: 6                           # number of character definitions detected
schema-version: v1                      # extracted from schema.py if versioned
```

**`world.md`:**
```yaml
type: architecture-world
layer: world
depends-on: []                          # base layer
mutated-by: ["storyline"]               # storyline writes world state
world-count: 1                          # # of distinct worlds
mutable: true                           # whether world state changes at runtime
```

**`storyline.md`:**
```yaml
type: architecture-storyline
layer: storyline
depends-on: ["character-card", "world"]
mutated-by: ["memory"]                  # memory persists storyline state
dsl-format: "ai-eden-storyline-dsl-v1"  # extracted from DSL file or "none"
branch-count: 4                         # branches detected, or null
```

**`companion-overview.md`:**
```yaml
type: architecture-companion-overview
layer: overview
layers-stable: 2                        # # of layers with confidence=high
layers-wip: 1                           # # with confidence=medium
layers-missing: 1                       # # with confidence=speculation
archetype: ai-companion
```

The `depends-on` / `mutated-by` fields are constant for the 4 layers (not project-specific) — they encode the canonical companion-bot dependency graph.

## Body block design

### `character-card.md` — 9 blocks

| # | Block | H2 (zh-TW / en) | Content rules |
|---|---|---|---|
| 1 | `summary` | `## 摘要` / `## Summary` | 1 paragraph. Card count, format, customization model, prompt binding. |
| 2 | `card-schema` | `## Card schema` | Data-structure definition + validation rules. Cite `code:path:line`. |
| 3 | `definitions-inventory` | `## 角色定義清單` / `## Definitions inventory` | Markdown table: Name \| Source \| Key traits \| Active. |
| 4 | `prompt-template-binding` | `## Prompt template 綁定` / `## Prompt template binding` | How card → system prompt; variables; full prompt body in `> [!quote]-` callout. |
| 5 | `versioning-and-overrides` | `## 版本與覆寫` / `## Versioning & overrides` | Schema evolution; user-customization paths. |
| 6 | `strengths` | `## 設計優點` / `## Character-card strengths` | 3-5 PM-aware bullets. |
| 7 | `weaknesses` | `## 設計缺點 / 風險` / `## Character-card weaknesses` | Failure modes. |
| 8 | `improvements` | `## 改進機會` / `## Character-card improvements` | ImprovementItem shape. |
| 9 | `dependencies` | `## 相依` / `## Dependencies` | Wikilinks. |

### `world.md` — 10 blocks

| # | Block | H2 | Content rules |
|---|---|---|---|
| 1 | `summary` | `## 摘要` / `## Summary` | World count, static-vs-mutable split, multi-world. |
| 2 | `world-schema` | `## World schema` | Data structure. |
| 3 | `lore-inventory` | `## Lore 清單` / `## Lore inventory` | Static content index. |
| 4 | `world-state` | `## 動態 world state` / `## Mutable world state` | Mutable fields, persistence store. |
| 5 | `loading-strategy` | `## 載入策略` / `## Loading strategy` | When loaded into LLM context, cache, token budget. |
| 6 | `mutation-rules` | `## 變動規則` / `## Mutation rules` | Who mutates, when, conflict resolution. |
| 7 | `strengths` | `## 設計優點` / `## World strengths` | |
| 8 | `weaknesses` | `## 設計缺點 / 風險` / `## World weaknesses` | World-state corruption / consistency / token explosion. |
| 9 | `improvements` | `## 改進機會` / `## World improvements` | |
| 10 | `dependencies` | `## 相依` / `## Dependencies` | |

### `storyline.md` — 11 blocks

| # | Block | H2 | Content rules |
|---|---|---|---|
| 1 | `summary` | `## 摘要` / `## Summary` | DSL shape, storyline count, branching, state. |
| 2 | `storyline-dsl` | `## Storyline DSL` | Grammar + example. Cite parser location. |
| 3 | `state-machine` | `## 狀態機` / `## State machine` | States, transitions, triggers. Mermaid state diagram. |
| 4 | `progression-rules` | `## 推進規則` / `## Progression rules` | Beat advancement triggers (intimacy gate / event / time). |
| 5 | `branching-logic` | `## 分支邏輯` / `## Branching logic` | Choice points, decision trees, user-input vs LLM-chosen. |
| 6 | `persistence` | `## 持久化` / `## Persistence` | Storyline state store, cross-session continuity. |
| 7 | `authoring-workflow` | `## 創作流程` / `## Authoring workflow` | Creator workflow, edit-reload, testing tools. |
| 8 | `strengths` | `## 設計優點` / `## Storyline strengths` | |
| 9 | `weaknesses` | `## 設計缺點 / 風險` / `## Storyline weaknesses` | DSL escape, state drift, authoring barrier. |
| 10 | `improvements` | `## 改進機會` / `## Storyline improvements` | |
| 11 | `dependencies` | `## 相依` / `## Dependencies` | |

### `companion-overview.md` — 9 blocks (cross-cutting)

| # | Block | H2 | Content rules |
|---|---|---|---|
| 1 | `summary` | `## 摘要` / `## Summary` | Archetype detected; 4 layers one-line each. |
| 2 | `four-layer-diagram` | `## 4 層依賴圖` / `## Four-layer dependency diagram` | ONE Mermaid: Character ↔ World ↔ Storyline ↔ Memory + LLM provider. |
| 3 | `data-flow` | `## 每輪資料流` / `## Per-turn data flow` | User turn → which layers consult in what order → prompt assembly → LLM → mutations. |
| 4 | `bind-points` | `## 層間綁定` / `## Bind points` | Cross-layer contracts; each binding lists owner. |
| 5 | `layer-maturity-table` | `## 各層成熟度` / `## Layer maturity table` | Table: Layer \| Status (✅/⚠️/❌) \| Wikilink \| Primary risk. |
| 6 | `strengths` | `## Companion 整體優點` / `## Companion-level strengths` | Cross-layer PM-aware. |
| 7 | `weaknesses` | `## Companion 整體缺點 / 風險` / `## Companion-level weaknesses` | |
| 8 | `improvements` | `## Companion 改進方向` / `## Companion improvements` | Cross-layer ImprovementItem (avoid duplicating single-layer Imps). |
| 9 | `dependencies` | `## 相依` / `## Dependencies` | |

### Voice constraints (all 4 new section types)

- **No invention** — empty signal → state absence explicitly (e.g. "未偵測到 storyline DSL")
- **Wikilink out for per-layer detail** in companion-overview — do not rehash
- **Full prompt body in `> [!quote]-` collapsible callout** when a system prompt is detected (same as v4.1 ai-flow `prompts` block)
- **Cross-layer references via wikilinks** — `[[ai-flows/world#World state]]` etc., never a short description

## Detection

### `scripts/architect/companion_detect.py` (new module)

```python
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class LayerEvidence:
    present: bool
    root_paths: list[str] = field(default_factory=list)
    artifact_files: list[str] = field(default_factory=list)
    storyline_dsl_file: str | None = None
    llm_libs: list[str] = field(default_factory=list)
    confidence: str = "medium"   # 'speculation' | 'medium' | 'high' | 'stated'


@dataclass
class CompanionDetection:
    archetype: str                            # 'ai-companion' | 'none'
    confidence: str                           # 'stated' | 'high' | 'medium'
    layers: dict[str, LayerEvidence]
    triggers: list[str]


def detect_companion_archetype(
    repo_root: Path,
    hub_frontmatter: dict | None = None,
) -> CompanionDetection: ...
```

**Heuristic rules (return `archetype="ai-companion"`):**

1. **Frontmatter override** — `hub_frontmatter.get("archetype") == "ai-companion"` → return with `confidence="stated"` and force all 4 layers `present=True` (even if evidence weak).
2. **Auto-detect** — Both **character-card** AND **storyline** evidence found → return with `confidence="high"` (character-card alone is too weak; many projects have personas but no storyline).
3. Otherwise → `archetype="none"`.

**Layer-specific evidence patterns:**

| Layer | Triggers |
|---|---|
| `character-card` | Dir named `characters/` / `personas/` / `bots/` / `companions/` contains ≥1 `.py`, `.json`, or `.yaml` definition file |
| `world` | Dir named `worlds/` / `world_*/` / `lore/` exists with ≥1 content file |
| `storyline` | File matching `storyline*.py`, `plot*.py`, `narrative*.py`, OR `*_dsl.py` containing keyword `storyline` / `plot` / `beat` / `progression` |
| `memory` | Reuse v4.3 `detect_memory()` — `has_memory == True` |

Each `LayerEvidence.confidence`:
- `stated` — frontmatter override forced this layer
- `high` — primary signal hit (dir name + file count ≥ 1)
- `medium` — partial signal (single file or borderline naming)
- `speculation` — only present because override forced, no code evidence

### `scripts/architect/ai_flow.py` (modified)

Loosen `custom-pipeline` branch in `_classify_candidate`:

```python
# Before:
if has_pipeline_file and has_nodes_dir and (has_llm_dep or llm_libs) and prompt_files:
    return AIFlow(framework="custom-pipeline", ...)

# After:
if (
    has_pipeline_file
    and (has_nodes_dir or has_llm_provider_imports)
    and (prompt_files or has_companion_archetype_signal)
):
    return AIFlow(framework="custom-pipeline", ...)
```

Where `has_llm_provider_imports = "openai" in import_text or "anthropic" in import_text or "google.generativeai" in import_text or "langchain_openai" in import_text or "langchain_google_genai" in import_text` and `has_companion_archetype_signal` is passed in from `companion_detect.detect_companion_archetype` result.

This unblocks `ai-eden-service/app/pipeline.py` from being detected as a real ai-flow (in addition to the companion-archetype detection).

## Scanner integration

`scan_report` gains one new top-level key:

```jsonc
{
  ... existing v4.1-v4.5 keys ...,
  "ai_companion": {
    "archetype": "ai-companion",
    "confidence": "high",
    "triggers": [
      "characters/ + storyline.py detected at app/characters/"
    ],
    "layers": {
      "character-card": {
        "present": true,
        "root_paths": ["app/characters/definitions/"],
        "artifact_files": ["app/characters/schema.py", "app/characters/loader.py"],
        "confidence": "high"
      },
      "world": {
        "present": true,
        "root_paths": ["app/characters/worlds/"],
        "artifact_files": ["app/characters/worlds/example.json"],
        "confidence": "high"
      },
      "storyline": {
        "present": true,
        "storyline_dsl_file": "app/characters/storyline_dsl.py",
        "artifact_files": ["app/characters/storyline.py"],
        "confidence": "high"
      },
      "memory": {
        "present": true,
        "confidence": "medium"
      }
    }
  }
}
```

When `archetype == "none"`, the key is still present but `layers` map all entries `present=False`.

## LLM synthesis (Phase 3.7.5)

`sections.py` gains 4 new builders:

```python
def build_character_card_prompt(*, project, layer_evidence, repomix_packed, output_lang) -> str: ...
def build_world_prompt(*, project, layer_evidence, repomix_packed, output_lang) -> str: ...
def build_storyline_prompt(*, project, layer_evidence, repomix_packed, output_lang) -> str: ...
def build_companion_overview_prompt(
    *, project, ai_companion_signals,
    layer_summaries,                      # dict mapping layer name → freshly-written summary
    repomix_packed, output_lang,
) -> str: ...
```

Each builder asks for strict JSON output with the layer's block keys. Critical rules echoed from v4.1/v4.3:

1. NO invention. Empty signal → acknowledge absence.
2. Wikilink-out per-layer detail when crossing into another layer.
3. Full prompt body in collapsible callout when system prompts detected.
4. PM voice for strengths / weaknesses; technical for schema / state-machine.

4 new composers in `sections.py` merge layer-specific frontmatter:

```python
def compose_character_card_note(*, ..., card_count: int, schema_version: str | None) -> str: ...
def compose_world_note(*, ..., world_count: int, mutable: bool) -> str: ...
def compose_storyline_note(*, ..., dsl_format: str | None, branch_count: int | None) -> str: ...
def compose_companion_overview_note(
    *, ..., layers_stable: int, layers_wip: int, layers_missing: int,
) -> str: ...
```

## Lockfile

`Lockfile` gains one additive field:

```python
@dataclass
class Lockfile:
    # ... existing fields ...
    ai_companion: dict = field(default_factory=dict)
```

Slot shape:

```jsonc
{
  "ai_companion": {
    "archetype": "ai-companion",
    "confidence": "high",
    "layers": {
      "character-card": {
        "signal-hash": "sha256:...",
        "lang": "zh-TW",
        "last-generated": "YYYY-MM-DD",
        "commit": "<sha>",
        "card-count": 6,
        "schema-version": "v1"
      },
      "world": { "signal-hash": "...", ... },
      "storyline": { "signal-hash": "...", "dsl-format": "ai-eden-storyline-dsl-v1", ... },
      "companion-overview": {
        "signal-hash": "...",
        "layers-stable": 2,
        "layers-wip": 1,
        "layers-missing": 1
      }
    }
  }
}
```

`memory` stays in the existing `ai_memory` slot (v4.3) — not duplicated here.

## Refresh logic

Each layer's `signal-hash` composition:

- `character-card`: SHA-256 over `ai_companion.layers["character-card"]` + each definitions file's mtime
- `world`: same shape, over world data files
- `storyline`: SHA-256 over storyline DSL file content (not mtime — DSL content is what matters)
- `companion-overview`: SHA-256 over the 4 per-layer signal-hashes (regenerates when any layer regenerates)

If a layer's `signal-hash` is unchanged AND the file exists AND not `--force`: skip its synthesis on this scan.

## Phase ordering in command body

```
Phase 1: scan (existing)
Phase 1.5/1.6: migrations (existing)
Phase 2: manifest review (existing)
Phase 3: per-module synthesis (existing)
Phase 3.5: decisions + personas (existing)
Phase 3.5.5: features.md (v4.2)
Phase 3.7: ai-flows per-subsystem (v4.1)
*** NEW Phase 3.7.5: Companion archetype synthesis (v4.6) ***
Phase 3.8: ai-memory cross-flow (v4.3)
Phase 3.9: ai-rag cross-flow (v4.3)
Phase 4: overview synthesis (v4)
Phase 7: board refresh (v4.5)
```

**Phase 3.7.5 algorithm:**

1. Skip if `--no-companion` OR `scan_report["ai_companion"]["archetype"] == "none"`.
2. For each layer in `["character-card", "world", "storyline"]`:
   - Skip if signal-hash unchanged + file exists
   - Repomix root_paths for that layer → `build_<layer>_prompt(...)` → invoke LLM → strict-JSON response → `compose_<layer>_note(...)` → write
3. After 3 layers complete, build `companion-overview` using the per-layer freshly-written summaries:
   - `compose_companion_overview_note(...)` → write to `ai-flows/companion-overview.md`
4. Update `lockfile.ai_companion` with new signal-hashes + frontmatter counts.

## Command flags

New flags on `/obsidian-architect`:

- `--no-companion` — skip Phase 3.7.5 entirely (even if archetype detected). Default OFF.
- `--companion-only` — diagnostic; runs Phase 1 + 3.7.5 only. Useful for iterating on the new prompts.

## Hub + overview drill-down

After Phase 3.7.5 succeeds, idempotent edits:

- Project hub `## 架構` block adds line:
  ```
  - AI 陪伴 4 層深判斷 (v4.6): [[Architecture/ai-flows/companion-overview]] | [[Architecture/ai-flows/character-card]] | [[Architecture/ai-flows/world]] | [[Architecture/ai-flows/storyline]] (+ memory in v4.3 line)
  ```
- `Architecture/overview.md ## 想深讀的入口` drill-down block adds line:
  ```
  - **AI 陪伴 4 層深判斷:** [[ai-flows/companion-overview]] (4-layer dep + data flow) | per-layer: [[ai-flows/character-card]] | [[ai-flows/world]] | [[ai-flows/storyline]]
  ```

Both sentinel-aware.

## Roadmap candidate detector

`scripts/roadmap/candidates.py:_extract_ai_cross_flow_candidates` extended to walk 3 new files:

| Block | Candidate type | Default priority | Priority bump |
|---|---|---|---|
| `ai-flows/character-card.md ## 改進機會` | `companion-character-improvement` | `normal` | — |
| `ai-flows/world.md ## 改進機會` | `companion-world-improvement` | `normal` | — |
| `ai-flows/storyline.md ## 改進機會` | `companion-storyline-improvement` | `normal` | — |
| `ai-flows/companion-overview.md ## Companion 改進方向` | `companion-improvement` | `normal` | **`high` when Evidence cites ≥ 2 layer wikilinks** (cross-layer Imps are high-leverage) |

Dedup rule from v4.2 / v4.5 stays: when candidates share Evidence wikilinks, source priority is `Brainstorms/` > `features.md` > `companion-overview.md` cross-layer > per-layer companion files > architecture-inferred.

## Tests (TDD coverage required)

`tests/architect/test_companion_detect.py` — **8 tests**:

1. `test_detect_companion_when_character_and_storyline_present` — both layers' signals → archetype=ai-companion, confidence=high.
2. `test_detect_no_companion_when_only_character` — character but no storyline → archetype=none.
3. `test_detect_no_companion_when_only_storyline` — storyline but no character → archetype=none.
4. `test_frontmatter_override_forces_archetype` — `archetype: ai-companion` in hub frontmatter → archetype=ai-companion, confidence=stated, all 4 layers present.
5. `test_world_layer_optional` — character + storyline (no world dir) → archetype=ai-companion but `world.present=False`.
6. `test_storyline_dsl_file_recognized` — file ending in `_dsl.py` with storyline keyword → storyline_dsl_file populated.
7. `test_layer_evidence_artifact_files_populated` — schema.py / loader.py / definitions/ all captured.
8. `test_detect_with_alt_directory_names` — `personas/` + `bots/` + `companions/` all alias for character-card; `lore/` aliases for world.

`tests/architect/test_companion_sections.py` — **12 tests**:

9-12. Section type registration + block names + heading mappings for all 4 new types.
13-16. `build_<layer>_prompt` produces strict-JSON instructions with all expected block keys.
17-20. `compose_<layer>_note` emits layer-specific extra frontmatter before `ai-first: true`.

`tests/architect/test_ai_flow.py` — **2 new tests**:

21. `test_custom_pipeline_no_nodes_dir_with_llm_imports` — `pipeline.py` + `openai` import without `nodes/` → still detects as custom-pipeline.
22. `test_ai_flow_classification_with_companion_signal` — companion signal flag passes through to AIFlow result.

`tests/architect/test_lockfile.py` — **1 new test**:

23. `test_lockfile_ai_companion_slot_round_trip` — `ai_companion` field round-trips through save/load.

`tests/roadmap/test_candidates.py` — **3 new tests**:

24-25. `detect_candidates` walks each new file's `## 改進機會` block.
26. `companion-overview.md` Imp citing ≥ 2 layer wikilinks → priority `high`.

End-to-end smoke (Task in plan):

27. Run `/obsidian-architect /Users/leric/Desktop/code/ai-eden-service --companion-only` → verify 4 new files written + lockfile updated + archetype=ai-companion detected.

## Migration / existing-vault handling

- ai-eden-service vault has NO existing `ai-flows/` notes → Phase 3.7.5 writes 4 new files cleanly.
- langlive-line-oa vault has `ai-flows/engines-langgraph.md` + `modules-qa-to-kb.md` (v4.1) + `memory.md` + `rag.md` (v4.3). Companion detector sees no character/storyline signal → archetype=none → Phase 3.7.5 SKIPS. No change to langlive's vault.
- Lockfile additive field; older lockfiles load with `ai_companion={}` default.

## Out-of-scope (deferred)

- **Multi-archetype projects** (e.g., a project that's BOTH companion AND LangGraph customer service in same repo) — both schemas can produce files; no special merging.
- **Per-character `character-card-<slug>.md` files** — current design has ONE `character-card.md` summarizing all definitions. If a project has 20+ characters, per-card detail belongs in code, not architecture/.
- **Storyline visualizer / React Flow integration** — out of architect's scope; that's a runtime tool.
- **Automatic prompt extraction from character cards** — v4.1 ai-flow's prompt extraction helper (`prompt_extract.py`) only handles 4 static-extractor formats; extending it to JSON / YAML character cards is a future enhancement.
- **DataView dashboard for layer maturity across vault** — frontmatter fields ready (`layers-stable`, `confidence`); DataView template is its own task.

## File-level shape preview (ai-eden, illustrative)

`Architecture/ai-flows/companion-overview.md`:

```markdown
---
type: architecture-companion-overview
...
archetype: ai-companion
layers-stable: 2          # character-card, world
layers-wip: 1             # storyline
layers-missing: 1         # memory
...
---

## 摘要
<!-- @generated:start summary -->
ai-eden-service 為 AI 陪伴 archetype。4 層偵測:
- ✅ [[ai-flows/character-card]] (6 cards, schema v1, stable)
- ✅ [[ai-flows/world]] (1 world, mutable, stable)
- ⚠️ [[ai-flows/storyline]] (custom DSL `ai-eden-storyline-dsl-v1`, WIP — branching logic incomplete)
- ❌ [[ai-flows/memory]] (轉述 v4.3 偵測:無 persistent memory layer 偵測到)
<!-- @generated:end summary -->

## 4 層依賴圖
... Mermaid ...

## 每輪資料流
... user input → character.load → world.fetch → storyline.peek → prompt.assemble → LLM → memory.write ...
```

## Success criteria

- [x] Brainstorm + design approved
- [ ] Spec self-review pass
- [ ] User reviews this spec
- [ ] Implementation plan via `writing-plans` skill
- [ ] Implementation lands: detector fix + 4 new schemas + Phase 3.7.5 + lockfile slot + roadmap walk; ai-eden-service smoke produces 4 new files; langlive-line-oa unaffected (archetype=none); 23+ new tests pass; 4 adapters build
