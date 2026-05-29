from pathlib import Path

from scripts.architect.personas import (
    Persona,
    collect_persona_signal,
    build_personas_prompt,
    render_personas_section,
)


def test_collect_persona_signal_prefers_readme_explicit_section(tmp_path: Path):
    """If README has '## Personas' or '## 使用者型態', use it as the canonical source."""
    (tmp_path / "README.md").write_text(
        "## Personas\n\n- Admin: 後台主管\n- Agent: 客服第一線\n\n## Other\nfoo\n"
    )
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is True
    assert "Admin" in sig.raw_text or "後台主管" in sig.raw_text


def test_collect_persona_signal_zh_tw_alias(tmp_path: Path):
    """`## 使用者型態` is treated as the same section."""
    (tmp_path / "README.md").write_text("## 使用者型態\n\n- 客服管理員\n- LINE 終端使用者\n")
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is True


def test_collect_persona_signal_falls_back_to_inferred(tmp_path: Path):
    """No explicit section -> has_explicit_section is False; raw_text empty."""
    (tmp_path / "README.md").write_text("# Project\n\nDoes things.\n")
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is False
    assert sig.raw_text == ""


def test_collect_persona_signal_missing_readme(tmp_path: Path):
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is False


def test_build_personas_prompt_demands_structured_output_zh_tw():
    prompt = build_personas_prompt(
        project="myproj",
        readme_excerpt="(no personas section)",
        agents_md_excerpt="Admin uses /admin endpoints.",
        features_summary="Provides admin dashboard, chat workspace.",
        output_lang="zh-TW",
    )
    assert "myproj" in prompt
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Demands the schema fields.
    for field in ("誰", "目標", "觸點", "頻率", "主要痛點"):
        assert field in prompt, f"missing required persona field {field!r}"


def test_render_personas_section_outputs_h2_then_h3_per_persona():
    personas = [
        Persona(slug="admin",
                title="後台管理員 (Admin Manager)",
                who="後台主管,監督客服團隊",
                goals=["看整體 ticket 健康度", "調度 agent"],
                touchpoints=["/admin/dashboard", "/admin/metrics"],
                frequency="每天",
                pain_points=["沒有 SLA 警示", "無法批次 reassign ticket"],
                confidence="stated"),
        Persona(slug="agent",
                title="客服 agent",
                who="客服第一線",
                goals=["回覆 ticket"],
                touchpoints=["/chat/workspace"],
                frequency="每天",
                pain_points=["Customer history 不易展開"],
                confidence="medium"),
    ]
    rendered = render_personas_section(personas, lang="zh-TW")
    assert "### 後台管理員 (Admin Manager)" in rendered
    assert "**誰:** 後台主管" in rendered
    assert "**目標:**" in rendered
    assert "/admin/dashboard" in rendered
    assert "**主要痛點:**" in rendered
    assert "_confidence: stated_" in rendered or "stated" in rendered
    # Second persona present
    assert "### 客服 agent" in rendered
