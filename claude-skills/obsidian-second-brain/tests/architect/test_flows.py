from pathlib import Path

from scripts.architect.flows import (
    Flow,
    collect_flow_signal,
    build_flows_prompt,
    render_flows_section,
)


def test_collect_flow_signal_finds_user_flows_section(tmp_path: Path):
    (tmp_path / "README.md").write_text(
        "## User flows\n\n1. LINE message arrives -> webhook -> queue -> agent UI\n"
    )
    sig = collect_flow_signal(tmp_path)
    assert sig.has_explicit_section is True
    assert "LINE" in sig.raw_text


def test_collect_flow_signal_zh_alias(tmp_path: Path):
    (tmp_path / "README.md").write_text("## 使用路徑\n\n- A -> B -> C\n")
    sig = collect_flow_signal(tmp_path)
    assert sig.has_explicit_section is True


def test_collect_flow_signal_no_match(tmp_path: Path):
    (tmp_path / "README.md").write_text("# x")
    sig = collect_flow_signal(tmp_path)
    assert sig.has_explicit_section is False


def test_build_flows_prompt_demands_friction_assessment():
    prompt = build_flows_prompt(
        project="myproj",
        personas_summary="Admin, Agent",
        api_surface_summary="115 routes, 8 main groups.",
        readme_excerpt="",
        agents_md_excerpt="",
        output_lang="en",
    )
    assert "myproj" in prompt
    # Each flow must include a Mermaid block and friction assessment.
    assert "mermaid" in prompt.lower()
    assert "friction" in prompt.lower()


def test_render_flows_section_with_mermaid():
    flows = [
        Flow(slug="ticket-handling",
             title="客服 ticket 處理",
             personas=["客服 agent", "客服管理員"],
             steps_mermaid="sequenceDiagram\n  participant U as User\n  U->>L: msg",
             friction_assessment=["webhook->queue 速度 OK", "agent UI 無 typing indicator"],
             maturity="GA",
             related_modules=["[[modules/backend]]", "[[modules/frontend]]"],
             confidence="stated"),
    ]
    rendered = render_flows_section(flows, lang="zh-TW")
    assert "### 客服 ticket 處理" in rendered
    assert "```mermaid" in rendered
    assert "sequenceDiagram" in rendered
    assert "agent UI 無 typing indicator" in rendered
    assert "**Maturity:** GA" in rendered
    assert "[[modules/backend]]" in rendered
