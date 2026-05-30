"""Resolve the output language for architect-generated notes.

Precedence: CLI flag > vault _CLAUDE.md `- output-lang: <code>` line > default 'en'.
"""

from __future__ import annotations

import re
from pathlib import Path

SUPPORTED_LANGS = ("en", "zh-TW")
DEFAULT_LANG = "en"

_OUTPUT_LANG_RE = re.compile(r"^\s*-\s*output-lang:\s*([A-Za-z0-9_-]+)\s*$", re.MULTILINE)


def resolve_output_lang(cli_flag: str | None, vault_root: Path) -> str:
    """Return the effective output language code.

    Args:
        cli_flag: value of `--lang=` passed to the command, or None.
        vault_root: directory containing `_CLAUDE.md`.

    Returns 'en' on any invalid or missing signal.
    """
    if cli_flag and cli_flag in SUPPORTED_LANGS:
        return cli_flag
    claude_md = vault_root / "_CLAUDE.md"
    if claude_md.exists():
        m = _OUTPUT_LANG_RE.search(claude_md.read_text(encoding="utf-8"))
        if m and m.group(1) in SUPPORTED_LANGS:
            return m.group(1)
    return DEFAULT_LANG


HEADING_MAP: dict[str, dict[str, str]] = {
    # Universal headings reused across types.
    "## For future Claude": {"en": "## For future Claude", "zh-TW": "## 給未來 Claude"},
    "## Summary": {"en": "## Summary", "zh-TW": "## 摘要"},
    "## Related": {"en": "## Related", "zh-TW": "## 相關"},
    # Overview headings.
    "## Purpose": {"en": "## Purpose", "zh-TW": "## 流程目的"},
    "## Stack": {"en": "## Stack", "zh-TW": "## 技術棧"},
    "## Capability MOC": {"en": "## Capability MOC", "zh-TW": "## 能力地圖 MOC"},
    "## Structure MOC": {"en": "## Structure MOC", "zh-TW": "## 結構地圖 MOC"},
    "## API surface": {"en": "## API surface", "zh-TW": "## API 介面"},
    "## Layer map": {"en": "## Layer map", "zh-TW": "## 分層圖"},
    "## External dependencies": {"en": "## External dependencies", "zh-TW": "## 外部相依"},
    "## Key abstractions": {"en": "## Key abstractions", "zh-TW": "## 核心抽象"},
    # features.md
    "## Capability map": {"en": "## Capability map", "zh-TW": "## 能力地圖"},
    "## Notable details": {"en": "## Notable details", "zh-TW": "## 補充細節"},
    # roadmap.md
    "## Near term": {"en": "## Near term", "zh-TW": "## 近期"},
    "## Trajectory": {"en": "## Trajectory", "zh-TW": "## 軌跡"},
    "## TODO clusters": {"en": "## TODO clusters", "zh-TW": "## TODO 群組"},
    "## Signals reviewed": {"en": "## Signals reviewed", "zh-TW": "## 已檢視訊號"},
    # decisions.md
    "## Stack rationale": {"en": "## Stack rationale", "zh-TW": "## 技術棧理由"},
    "## Detected ADRs": {"en": "## Detected ADRs", "zh-TW": "## 已偵測的 ADR"},
    "## Pattern decisions": {"en": "## Pattern decisions", "zh-TW": "## 模式決定"},
    "## Commit-message decisions": {"en": "## Commit-message decisions", "zh-TW": "## Commit 訊息決定"},
    "## Promote to ADR": {"en": "## Promote to ADR", "zh-TW": "## 建議升級為 ADR"},
    # future.md
    "## Known limitations": {"en": "## Known limitations", "zh-TW": "## 已知限制"},
    "## Gap analysis": {"en": "## Gap analysis", "zh-TW": "## 落差分析"},
    "## Aspirational ideas": {"en": "## Aspirational ideas", "zh-TW": "## 期望中的想法"},
    # api-surface.md
    "## CLI commands": {"en": "## CLI commands", "zh-TW": "## CLI 命令"},
    "## HTTP routes": {"en": "## HTTP routes", "zh-TW": "## HTTP 路由"},
    "## Public exports": {"en": "## Public exports", "zh-TW": "## 公開匯出"},
    "## Environment variables": {"en": "## Environment variables", "zh-TW": "## 環境變數"},
    # modules (existing, restated for translation table completeness).
    "## What it does": {"en": "## What it does", "zh-TW": "## 功能說明"},
    "## How it works": {"en": "## How it works", "zh-TW": "## 運作方式"},
    "## Key files": {"en": "## Key files", "zh-TW": "## 重點檔案"},
    "## Depends on": {"en": "## Depends on", "zh-TW": "## 相依於"},
    "## Consumed by": {"en": "## Consumed by", "zh-TW": "## 被誰使用"},
    "## Recent activity": {"en": "## Recent activity", "zh-TW": "## 近期活動"},
    # function notes.
    "## Signature": {"en": "## Signature", "zh-TW": "## 函式簽章"},
    "## Inputs and outputs": {"en": "## Inputs and outputs", "zh-TW": "## 輸入輸出"},
    "## Behavior notes": {"en": "## Behavior notes", "zh-TW": "## 行為註記"},
    "## Callers": {"en": "## Callers", "zh-TW": "## 呼叫者"},
    # roadmap (project-level, by /obsidian-roadmap)
    "## Themes": {"en": "## Themes", "zh-TW": "## 主題"},
    "## Stale themes": {"en": "## Stale themes", "zh-TW": "## 過時主題"},
    "## Synthesis summary": {"en": "## Synthesis summary", "zh-TW": "## 本次合成摘要"},
    "## Acceptance criteria": {"en": "## Acceptance criteria", "zh-TW": "## 接受條件"},
    "## Evidence": {"en": "## Evidence", "zh-TW": "## 佐證"},
    "## Why": {"en": "## Why", "zh-TW": "## 為什麼"},
    # v3 judgment-driven frame
    "## Design strengths": {"en": "## Design strengths", "zh-TW": "## 設計優點"},
    "## Design weaknesses": {"en": "## Design weaknesses", "zh-TW": "## 設計缺點 / 風險"},
    "## Improvement opportunities": {"en": "## Improvement opportunities", "zh-TW": "## 改進機會"},
    "## Module responsibility": {"en": "## Module responsibility", "zh-TW": "## 模組職責"},
    "## Overall flow": {"en": "## Overall flow", "zh-TW": "## 整體流程"},
    "## Capability scope": {"en": "## Capability scope", "zh-TW": "## 能力範圍"},
    "## Journey": {"en": "## Journey", "zh-TW": "## 旅程"},
    "## Personas": {"en": "## Personas", "zh-TW": "## 使用者型態"},
    "## Jobs to be done": {"en": "## Jobs to be done", "zh-TW": "## Jobs to be Done"},
    "## Flows": {"en": "## Flows", "zh-TW": "## 核心使用流程"},
    "## Dependencies and consumers": {"en": "## Dependencies and consumers", "zh-TW": "## 相依與被誰使用"},
    "## Interface overview": {"en": "## Interface overview", "zh-TW": "## 介面類型概觀"},
    "## Environment variables overview": {"en": "## Environment variables overview", "zh-TW": "## 環境變數概觀"},
    # v4 consolidated-report frame (overview top-down sections)
    "## Purpose & audience": {"en": "## Purpose & audience", "zh-TW": "## 這是什麼 / 為誰服務"},
    "## System diagram": {"en": "## System diagram", "zh-TW": "## 系統架構圖"},
    "## Capabilities": {"en": "## Capabilities", "zh-TW": "## 核心能力"},
    "## Module map": {"en": "## Module map", "zh-TW": "## 模組地圖"},
    "## Cross-cutting improvements": {"en": "## Cross-cutting improvements", "zh-TW": "## 跨模組改進機會"},
    "## Drill-down entries": {"en": "## Drill-down entries", "zh-TW": "## 想深讀的入口"},
    # v4.1 ai-flow body sections
    "## Graph topology": {"en": "## Graph topology", "zh-TW": "## 圖結構"},
    "## State schema": {"en": "## State schema", "zh-TW": "## 狀態 schema"},
    "## Prompts": {"en": "## Prompts", "zh-TW": "## Prompts"},
    "## LLM config": {"en": "## LLM config", "zh-TW": "## LLM 設定"},
    "## Evaluation & observability": {
        "en": "## Evaluation & observability",
        "zh-TW": "## 評估與觀測",
    },
    # v4.2 features.md (product-PM lens)
    "## Capability inventory": {"en": "## Capability inventory", "zh-TW": "## 能力清單"},
    "## Product coverage": {"en": "## Product coverage", "zh-TW": "## 產品覆蓋度"},
    "## Limitations": {"en": "## Limitations", "zh-TW": "## 產品邊界"},
    "## Missing features": {
        "en": "## Missing features",
        "zh-TW": "## 可加 features (gap analysis)",
    },
    "## Doc sync actions": {"en": "## Doc sync actions", "zh-TW": "## 文件補補丁"},
    # v4.3 memory.md cross-flow lens
    "## Per-flow memory map": {"en": "## Per-flow memory map", "zh-TW": "## 各流程記憶機制"},
    "## Backend & storage": {"en": "## Backend & storage", "zh-TW": "## 儲存層"},
    "## Scope & lifecycle": {"en": "## Scope & lifecycle", "zh-TW": "## 範疇與生命週期"},
    "## Context window management": {
        "en": "## Context window management",
        "zh-TW": "## Context window 管理",
    },
    "## Compaction strategy": {"en": "## Compaction strategy", "zh-TW": "## 壓縮策略"},
    "## Long-term vs short-term memory": {
        "en": "## Long-term vs short-term memory",
        "zh-TW": "## 長期 vs 短期記憶",
    },
    # v4.3 rag.md cross-flow lens
    "## RAG data flow": {"en": "## RAG data flow", "zh-TW": "## RAG 資料流"},
    "## Ingest pipeline": {"en": "## Ingest pipeline", "zh-TW": "## Ingest 管線"},
    "## Vector store config": {"en": "## Vector store config", "zh-TW": "## Vector store 設定"},
    "## Retrieve strategy": {"en": "## Retrieve strategy", "zh-TW": "## Retrieve 策略"},
    # v4.4 brainstorm (project interview output)
    "## Session context": {"en": "## Session context", "zh-TW": "## 對話脈絡"},
    "## Opening provocations": {
        "en": "## Opening provocations",
        "zh-TW": "## 開場 provocations",
    },
    "## Drilled explorations": {
        "en": "## Drilled explorations",
        "zh-TW": "## 深挖紀錄",
    },
    "## Distilled improvements": {
        "en": "## Distilled improvements",
        "zh-TW": "## 提煉的 Imps",
    },
    "## Hypotheses to validate": {
        "en": "## Hypotheses to validate",
        "zh-TW": "## 待驗證假設",
    },
    "## Parked": {"en": "## Parked", "zh-TW": "## 暫不討論"},
    "## Open questions": {"en": "## Open questions", "zh-TW": "## 仍不清楚"},
    "## Meta reflection": {"en": "## Meta reflection", "zh-TW": "## 自我覆盤"},
    # v4.6 companion archetype (Character Card / World / Storyline / cross-cutting)
    "## Card schema": {"en": "## Card schema", "zh-TW": "## Card schema"},
    "## Definitions inventory": {
        "en": "## Definitions inventory", "zh-TW": "## 角色定義清單",
    },
    "## Prompt template binding": {
        "en": "## Prompt template binding", "zh-TW": "## Prompt template 綁定",
    },
    "## Versioning & overrides": {
        "en": "## Versioning & overrides", "zh-TW": "## 版本與覆寫",
    },
    "## World schema": {"en": "## World schema", "zh-TW": "## World schema"},
    "## Lore inventory": {"en": "## Lore inventory", "zh-TW": "## Lore 清單"},
    "## Mutable world state": {
        "en": "## Mutable world state", "zh-TW": "## 動態 world state",
    },
    "## Loading strategy": {"en": "## Loading strategy", "zh-TW": "## 載入策略"},
    "## Mutation rules": {"en": "## Mutation rules", "zh-TW": "## 變動規則"},
    "## Storyline DSL": {"en": "## Storyline DSL", "zh-TW": "## Storyline DSL"},
    "## State machine": {"en": "## State machine", "zh-TW": "## 狀態機"},
    "## Progression rules": {"en": "## Progression rules", "zh-TW": "## 推進規則"},
    "## Branching logic": {"en": "## Branching logic", "zh-TW": "## 分支邏輯"},
    "## Persistence": {"en": "## Persistence", "zh-TW": "## 持久化"},
    "## Authoring workflow": {
        "en": "## Authoring workflow", "zh-TW": "## 創作流程",
    },
    "## Four-layer dependency diagram": {
        "en": "## Four-layer dependency diagram", "zh-TW": "## 4 層依賴圖",
    },
    "## Per-turn data flow": {
        "en": "## Per-turn data flow", "zh-TW": "## 每輪資料流",
    },
    "## Bind points": {"en": "## Bind points", "zh-TW": "## 層間綁定"},
    "## Layer maturity table": {
        "en": "## Layer maturity table", "zh-TW": "## 各層成熟度",
    },
}


def heading(key: str, lang: str) -> str:
    """Translate a canonical (English) heading to the given language.

    Unknown keys pass through unchanged so the caller fails loud at render time.
    """
    return HEADING_MAP.get(key, {}).get(lang, key)
