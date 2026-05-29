import json

from scripts.roadmap.synthesis import build_synthesis_prompt


def test_synthesis_prompt_lists_candidates_with_evidence():
    candidates = [
        {"id": "gap-1", "title": "加 SSO 整合", "kind": "limitation",
         "evidence": ["[[Architecture/future#已知限制]]", "[[Research/Deep/2026-05-15-sso-providers]]"]},
        {"id": "asp-2", "title": "把 AI 引擎抽象成 pluggable adapter", "kind": "aspiration",
         "evidence": ["[[Architecture/future#期望中的想法]]"]},
    ]
    modules_summary = "backend (Python FastAPI), frontend (React 19)"
    prompt = build_synthesis_prompt(
        candidates=candidates,
        modules_summary=modules_summary,
        project="myproj",
        output_lang="zh-TW",
        max_themes=12,
    )
    assert "gap-1" in prompt
    assert "加 SSO 整合" in prompt
    assert "asp-2" in prompt
    assert "[[Research/Deep/2026-05-15-sso-providers]]" in prompt
    assert "myproj" in prompt
    assert "12" in prompt  # max_themes
    # Demands fully-spec'd tasks per spec §7 Phase 3
    assert "acceptance-criteria" in prompt
    assert "slug" in prompt
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt


def test_synthesis_prompt_en_no_zh_directive():
    prompt = build_synthesis_prompt(
        candidates=[],
        modules_summary="",
        project="x",
        output_lang="en",
        max_themes=6,
    )
    assert "English" in prompt or "en" in prompt
    assert "繁體中文" not in prompt
