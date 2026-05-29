from pathlib import Path

from scripts.architect.jobs import (
    Job,
    collect_job_signal,
    build_jobs_prompt,
    render_jobs_section,
)


def test_collect_job_signal_finds_jtbd_section(tmp_path: Path):
    (tmp_path / "README.md").write_text(
        "## Jobs to be done\n\n"
        "- When admin sees a complaint, they want to triage quickly.\n"
        "- When agent receives a ticket, they want full context.\n"
    )
    sig = collect_job_signal(tmp_path)
    assert sig.has_explicit_section is True
    assert "triage" in sig.raw_text


def test_collect_job_signal_zh_alias(tmp_path: Path):
    (tmp_path / "README.md").write_text("## 使用者工作\n\n- Foo\n")
    sig = collect_job_signal(tmp_path)
    assert sig.has_explicit_section is True


def test_collect_job_signal_no_section(tmp_path: Path):
    (tmp_path / "README.md").write_text("# Project\n")
    sig = collect_job_signal(tmp_path)
    assert sig.has_explicit_section is False


def test_build_jobs_prompt_includes_persona_context_and_demands_maturity():
    prompt = build_jobs_prompt(
        project="myproj",
        personas_summary="Admin, Agent",
        features_summary="Admin dashboard.",
        readme_excerpt="",
        agents_md_excerpt="",
        output_lang="en",
    )
    assert "myproj" in prompt
    assert "Admin" in prompt
    # Each job MUST declare maturity.
    assert "maturity" in prompt.lower()
    assert "Alpha" in prompt and "Beta" in prompt and "GA" in prompt
    # Friction points required.
    assert "friction" in prompt.lower()


def test_render_jobs_section_groups_by_persona():
    jobs = [
        Job(slug="triage-complaint",
            persona="客服管理員",
            jtbd="當客戶投訴,管理員想快速分派處理",
            maturity="Beta",
            friction_points=["缺 priority 標籤", "無 SLA timer"],
            related_features=["[[features#Admin Dashboard]]"],
            related_flows=["[[flows#Ticket Handling]]"],
            confidence="medium"),
        Job(slug="answer-ticket",
            persona="客服 agent",
            jtbd="當收到 ticket,agent 想看完整 context 後回覆",
            maturity="GA",
            friction_points=["Customer history 展開要兩步"],
            related_features=["[[features#Conversation Workspace]]"],
            related_flows=["[[flows#Ticket Handling]]"],
            confidence="stated"),
    ]
    rendered = render_jobs_section(jobs, lang="zh-TW")
    # Persona acts as visual grouping.
    assert "**Persona:** 客服管理員" in rendered or "**使用者:** 客服管理員" in rendered
    assert "**JTBD:**" in rendered or "**目標:**" in rendered
    # Maturity label visible.
    assert "Beta" in rendered
    assert "GA" in rendered
    # Friction points list.
    assert "缺 priority 標籤" in rendered


def test_render_jobs_section_en():
    jobs = [Job(slug="x", persona="Admin", jtbd="Do X", maturity="Alpha",
                friction_points=["a"], related_features=[], related_flows=[],
                confidence="speculation")]
    rendered = render_jobs_section(jobs, lang="en")
    assert "**Persona:** Admin" in rendered
    assert "**JTBD:** Do X" in rendered
    assert "Alpha" in rendered
