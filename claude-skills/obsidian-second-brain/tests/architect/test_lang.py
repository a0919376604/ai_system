from pathlib import Path

from scripts.architect.lang import resolve_output_lang


def test_cli_flag_wins(tmp_path: Path):
    (tmp_path / "_CLAUDE.md").write_text("- output-lang: en\n")
    assert resolve_output_lang(cli_flag="zh-TW", vault_root=tmp_path) == "zh-TW"


def test_claude_md_when_no_flag(tmp_path: Path):
    (tmp_path / "_CLAUDE.md").write_text("Some prelude.\n- output-lang: zh-TW\nMore.\n")
    assert resolve_output_lang(cli_flag=None, vault_root=tmp_path) == "zh-TW"


def test_default_en_when_no_signal(tmp_path: Path):
    assert resolve_output_lang(cli_flag=None, vault_root=tmp_path) == "en"


def test_invalid_lang_falls_back_to_en(tmp_path: Path):
    (tmp_path / "_CLAUDE.md").write_text("- output-lang: klingon\n")
    assert resolve_output_lang(cli_flag=None, vault_root=tmp_path) == "en"


def test_supported_langs_constant():
    from scripts.architect.lang import SUPPORTED_LANGS
    assert set(SUPPORTED_LANGS) == {"en", "zh-TW"}


def test_heading_returns_zh_for_known_key():
    from scripts.architect.lang import heading
    assert heading("## Summary", "zh-TW") == "## 摘要"
    assert heading("## CLI commands", "zh-TW") == "## CLI 命令"


def test_heading_returns_en_for_en_lang():
    from scripts.architect.lang import heading
    assert heading("## Summary", "en") == "## Summary"


def test_heading_passes_through_unknown_key():
    from scripts.architect.lang import heading
    assert heading("## Unknown thing", "zh-TW") == "## Unknown thing"


def test_heading_map_covers_all_required_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## For future Claude", "## Summary", "## Related",
        "## Purpose", "## Stack", "## Capability MOC", "## Structure MOC",
        "## API surface", "## Layer map", "## External dependencies", "## Key abstractions",
        "## Capability map", "## Notable details",
        "## Near term", "## Trajectory", "## TODO clusters", "## Signals reviewed",
        "## Stack rationale", "## Detected ADRs", "## Pattern decisions",
        "## Commit-message decisions", "## Promote to ADR",
        "## Known limitations", "## Gap analysis", "## Aspirational ideas",
        "## CLI commands", "## HTTP routes", "## Public exports", "## Environment variables",
        "## What it does", "## How it works", "## Key files", "## Depends on",
        "## Consumed by", "## Recent activity",
        "## Signature", "## Inputs and outputs", "## Behavior notes", "## Callers",
    }
    missing = required - set(HEADING_MAP.keys())
    assert not missing, f"missing heading keys: {missing}"


def test_heading_map_includes_roadmap_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Themes": "## 主題",
        "## Stale themes": "## 過時主題",
        "## Synthesis summary": "## 本次合成摘要",
        "## Acceptance criteria": "## 接受條件",
        "## Evidence": "## 佐證",
        "## Why": "## 為什麼",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_v3_judgment_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Design strengths": "## 設計優點",
        "## Design weaknesses": "## 設計缺點 / 風險",
        "## Improvement opportunities": "## 改進機會",
        "## Module responsibility": "## 模組職責",
        "## Overall flow": "## 整體流程",
        "## Capability scope": "## 能力範圍",
        "## Journey": "## 旅程",
        "## Personas": "## 使用者型態",
        "## Jobs to be done": "## Jobs to be Done",
        "## Flows": "## 核心使用流程",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_v4_report_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Purpose & audience": "## 這是什麼 / 為誰服務",
        "## System diagram": "## 系統架構圖",
        "## Capabilities": "## 核心能力",
        "## Flows": "## 核心使用流程",
        "## Module map": "## 模組地圖",
        "## Cross-cutting improvements": "## 跨模組改進機會",
        "## Drill-down entries": "## 想深讀的入口",
        "## Known limitations": "## 已知限制",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_v4_2_features_keys():
    """v4.2 features.md introduces 5 new H2 headings (product-PM lens)."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Capability inventory": "## 能力清單",
        "## Product coverage": "## 產品覆蓋度",
        "## Limitations": "## 產品邊界",
        "## Missing features": "## 可加 features (gap analysis)",
        "## Doc sync actions": "## 文件補補丁",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_ai_flow_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Purpose": "## 流程目的",
        "## Graph topology": "## 圖結構",
        "## State schema": "## 狀態 schema",
        "## Prompts": "## Prompts",
        "## LLM config": "## LLM 設定",
        "## Evaluation & observability": "## 評估與觀測",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_v4_3_keys():
    """v4.3 introduces 10 new H2 headings across memory.md + rag.md."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        # memory.md
        "## Per-flow memory map": "## 各流程記憶機制",
        "## Backend & storage": "## 儲存層",
        "## Scope & lifecycle": "## 範疇與生命週期",
        "## Context window management": "## Context window 管理",
        "## Compaction strategy": "## 壓縮策略",
        "## Long-term vs short-term memory": "## 長期 vs 短期記憶",
        # rag.md
        "## RAG data flow": "## RAG 資料流",
        "## Ingest pipeline": "## Ingest 管線",
        "## Vector store config": "## Vector store 設定",
        "## Retrieve strategy": "## Retrieve 策略",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_brainstorm_keys():
    """v1 brainstorm introduces 8 new H2 headings."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Session context": "## 對話脈絡",
        "## Opening provocations": "## 開場 provocations",
        "## Drilled explorations": "## 深挖紀錄",
        "## Distilled improvements": "## 提煉的 Imps",
        "## Hypotheses to validate": "## 待驗證假設",
        "## Parked": "## 暫不討論",
        "## Open questions": "## 仍不清楚",
        "## Meta reflection": "## 自我覆盤",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en


def test_heading_map_includes_v4_6_companion_keys():
    """v4.6 introduces 14 new H2 headings across the 4 companion section types."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Card schema": "## Card schema",
        "## Definitions inventory": "## 角色定義清單",
        "## Prompt template binding": "## Prompt template 綁定",
        "## Versioning & overrides": "## 版本與覆寫",
        "## World schema": "## World schema",
        "## Lore inventory": "## Lore 清單",
        "## Mutable world state": "## 動態 world state",
        "## Loading strategy": "## 載入策略",
        "## Mutation rules": "## 變動規則",
        "## Storyline DSL": "## Storyline DSL",
        "## State machine": "## 狀態機",
        "## Progression rules": "## 推進規則",
        "## Branching logic": "## 分支邏輯",
        "## Persistence": "## 持久化",
        "## Authoring workflow": "## 創作流程",
        "## Four-layer dependency diagram": "## 4 層依賴圖",
        "## Per-turn data flow": "## 每輪資料流",
        "## Bind points": "## 層間綁定",
        "## Layer maturity table": "## 各層成熟度",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
