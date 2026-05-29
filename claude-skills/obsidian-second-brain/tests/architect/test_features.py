"""v4.2 features.md tests."""
from __future__ import annotations

from scripts.architect.sections import (
    DEPRECATED_SECTIONS,
    SECTION_TYPES,
    _BLOCK_HEADINGS,
    _BLOCK_NAMES,
)


def test_features_section_not_deprecated_in_v4_2():
    """v4.2 un-deprecates features. compose_note(section='features') should NOT
    log a deprecation warning."""
    assert "features" not in DEPRECATED_SECTIONS, (
        "features must be removed from DEPRECATED_SECTIONS in v4.2"
    )


def test_features_section_type_present():
    assert SECTION_TYPES["features"] == "architecture-features"


def test_features_v4_2_block_names():
    """v4.2 features has 10 @generated blocks in a specific order."""
    expected = (
        "summary",
        "capability-inventory",
        "product-coverage",
        "limitations",
        "strengths",
        "weaknesses",
        "missing-features",
        "improvements",
        "doc-sync-actions",
        "dependencies",
    )
    assert _BLOCK_NAMES["features"] == expected


def test_features_v4_2_block_headings_present():
    """Every block name in features has a heading in _BLOCK_HEADINGS."""
    for block_name in _BLOCK_NAMES["features"]:
        assert block_name in _BLOCK_HEADINGS, f"missing heading for {block_name}"


def test_features_new_block_headings_text():
    """v4.2 introduces 4 new block headings not used elsewhere."""
    assert _BLOCK_HEADINGS["capability-inventory"] == "## Capability inventory"
    assert _BLOCK_HEADINGS["product-coverage"] == "## Product coverage"
    assert _BLOCK_HEADINGS["limitations"] == "## Limitations"
    assert _BLOCK_HEADINGS["missing-features"] == "## Missing features"
    assert _BLOCK_HEADINGS["doc-sync-actions"] == "## Doc sync actions"


def test_scan_report_includes_agents_md_text(tmp_path):
    """build_scan_report exposes raw AGENTS.md text (capped 20KB)."""
    from scripts.architect.scan import build_scan_report

    (tmp_path / "AGENTS.md").write_text("# Agents\nLine 1\nLine 2\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("# R", encoding="utf-8")
    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "agents_md_text" in report
    assert "Agents" in report["agents_md_text"]
    assert len(report["agents_md_text"]) <= 20_000


def test_scan_report_research_excerpts_when_vault_project_dir_passed(tmp_path):
    """When --vault-project-dir given, scan walks Research/ for excerpts."""
    from scripts.architect.scan import build_scan_report

    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    vault_proj = tmp_path / "vault_proj"
    research = vault_proj / "Research"
    research.mkdir(parents=True)
    (research / "X.md").write_text(
        "---\ntitle: X\ndate: 2026-05-01\ntags: []\n---\n\nResearch para.\n",
        encoding="utf-8",
    )
    report = build_scan_report(tmp_path, vault_project_dir=vault_proj)
    excerpts = report["research_excerpts"]
    assert len(excerpts) == 1
    assert excerpts[0]["title"] == "X"


def test_scan_report_research_excerpts_empty_when_dir_missing(tmp_path):
    """When --vault-project-dir not passed, research_excerpts = []."""
    from scripts.architect.scan import build_scan_report

    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert report["research_excerpts"] == []


def test_scan_report_git_last_touch_keyed_by_path(tmp_path):
    """build_scan_report adds git_last_touch dict for api_surface files."""
    import subprocess
    from scripts.architect.scan import build_scan_report

    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "main.py").write_text("def hello(): pass\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init", "--date", "2026-05-15T00:00:00"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        env={**__import__("os").environ,
             "GIT_AUTHOR_DATE": "2026-05-15T00:00:00",
             "GIT_COMMITTER_DATE": "2026-05-15T00:00:00"},
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "git_last_touch" in report
    # main.py was committed → must have a date.
    assert report["git_last_touch"].get("main.py") == "2026-05-15"


def test_build_features_prompt_requires_10_block_keys():
    """Prompt instructs LLM to return strict JSON with all 10 block keys."""
    from scripts.architect.sections import build_features_prompt

    prompt = build_features_prompt(
        project="P",
        readme_sections={"Features": "Auth, KB"},
        agents_md_text="Routing table here.",
        changelog={"unreleased": []},
        api_surface_summary="3 HTTP routes, 0 CLI",
        modules_summary="backend, frontend",
        personas_summary="(no personas yet)",
        research_excerpts=[],
        output_lang="zh-TW",
    )
    for key in (
        "summary",
        "capability-inventory",
        "product-coverage",
        "limitations",
        "strengths",
        "weaknesses",
        "missing-features",
        "improvements",
        "doc-sync-actions",
        "dependencies",
    ):
        assert key in prompt, f"prompt must mention block key {key!r}"


def test_build_features_prompt_capability_inventory_is_structured_list():
    """capability-inventory must be requested as STRUCTURED LIST not markdown table."""
    from scripts.architect.sections import build_features_prompt

    prompt = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="", personas_summary="",
        research_excerpts=[], output_lang="zh-TW",
    )
    assert "structured list" in prompt.lower() or "list of dict" in prompt.lower(), (
        "prompt should ask LLM to return capability-inventory as structured list"
    )
    assert "code_anchors" in prompt
    assert "doc_anchors" in prompt


def test_build_features_prompt_research_excerpts_listed_when_present():
    """When research_excerpts non-empty, prompt body lists title + first_para."""
    from scripts.architect.sections import build_features_prompt

    prompt = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="", personas_summary="",
        research_excerpts=[
            {"path": "Research/x.md", "title": "X trend",
             "first_para": "X paragraph", "tags": [], "date": "2026-04-01"}
        ],
        output_lang="zh-TW",
    )
    assert "X trend" in prompt
    assert "X paragraph" in prompt


def test_build_features_prompt_personas_directive_only_when_provided():
    """product-coverage block directive references personas only when summary non-empty."""
    from scripts.architect.sections import build_features_prompt

    no_p = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="", personas_summary="",
        research_excerpts=[], output_lang="zh-TW",
    )
    with_p = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="",
        personas_summary="Persona Mary: shift handoff job",
        research_excerpts=[], output_lang="zh-TW",
    )
    assert "Persona Mary" in with_p
    assert "Persona Mary" not in no_p


def test_render_features_inventory_marks_online_when_anchor_in_api_surface():
    """LLM row with code_anchor matching api_surface → status=online."""
    from scripts.architect.sections import render_features_inventory

    inventory = [
        {
            "name": "Login",
            "description": "Admin login",
            "code_anchors": ["backend/app/api/auth.py:/login"],
            "doc_anchors": ["README.md#Auth"],
            "module": "backend",
        }
    ]
    api_surface = {
        "http_routes": [{"path": "/login", "method": "POST",
                          "file": "backend/app/api/auth.py"}],
        "cli_commands": [],
        "exports": [],
    }
    git_last_touch = {"backend/app/api/auth.py": "2026-05-20"}
    md, summary = render_features_inventory(inventory, api_surface, git_last_touch)
    assert "| online |" in md
    assert "2026-05-20" in md
    assert summary["online"] == 1
    assert summary["deprecated"] == 0


def test_render_features_inventory_marks_deprecated_when_no_anchor_matches():
    """LLM row with code_anchor NOT in api_surface → status=deprecated."""
    from scripts.architect.sections import render_features_inventory

    inventory = [
        {
            "name": "Old endpoint",
            "description": "removed",
            "code_anchors": ["backend/api/old.py:/v1/old"],
            "doc_anchors": ["README.md#Legacy"],
            "module": "backend",
        }
    ]
    api_surface = {"http_routes": [], "cli_commands": [], "exports": []}
    md, summary = render_features_inventory(inventory, api_surface, {})
    assert "| deprecated |" in md
    # Last touch column for deprecated is em-dash.
    assert "| — |" in md or "| - |" in md
    assert summary["online"] == 0
    assert summary["deprecated"] == 1


def test_render_features_inventory_last_touch_unknown_for_missing_git_key():
    """When code_anchor's file isn't in git_last_touch, last_touch column = 'unknown'."""
    from scripts.architect.sections import render_features_inventory

    inventory = [
        {
            "name": "Recent",
            "description": "x",
            "code_anchors": ["backend/app/new.py:/new"],
            "doc_anchors": [],
            "module": "backend",
        }
    ]
    api_surface = {
        "http_routes": [{"path": "/new", "method": "POST",
                          "file": "backend/app/new.py"}],
        "cli_commands": [],
        "exports": [],
    }
    md, _ = render_features_inventory(inventory, api_surface, git_last_touch={})
    assert "unknown" in md


def test_compute_doc_sync_score_basic_ratio():
    from scripts.architect.sections import compute_doc_sync_score

    rendered_rows = [
        {"name": "A", "status": "online", "doc_anchors": ["README.md#A"]},
        {"name": "B", "status": "online", "doc_anchors": ["AGENTS.md L1"]},
        {"name": "C", "status": "online", "doc_anchors": []},
        {"name": "D", "status": "deprecated", "doc_anchors": ["README.md#D"]},
    ]
    score = compute_doc_sync_score(rendered_rows)
    # 3 online; 2 have ≥1 doc → 2/3 ≈ 0.67
    assert score == 0.67


def test_compute_doc_sync_score_zero_online_returns_zero():
    from scripts.architect.sections import compute_doc_sync_score

    rendered_rows = [{"name": "X", "status": "deprecated", "doc_anchors": []}]
    assert compute_doc_sync_score(rendered_rows) == 0.0


def test_compose_features_note_emits_extra_frontmatter():
    """compose_features_note (or equivalent helper) merges feature-count /
    deprecated-count / doc-sync-score into the frontmatter."""
    from scripts.architect.sections import compose_features_note

    blocks = {
        "summary": "summary text",
        "capability-inventory": "| C | D | online | 2026-05 | — | — | [[modules/backend]] |",
        "product-coverage": "",
        "limitations": "- 只支援 LINE",
        "strengths": "- **完整 lifecycle.**",
        "weaknesses": "- **單一 channel.**",
        "missing-features": "### A\n- **為什麼:** x",
        "improvements": "### Imp 1\n- **為什麼:** y",
        "doc-sync-actions": "### 清除\n- [ ] x",
        "dependencies": "- [[Architecture/overview]]",
    }
    note = compose_features_note(
        project="P",
        repo_label="local: /tmp/p",
        commit="abc1234",
        signal_sources=["README.md"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks=blocks,
        feature_count=1,
        deprecated_count=0,
        doc_sync_score=0.84,
    )
    assert "feature-count: 1" in note
    assert "deprecated-count: 0" in note
    assert "doc-sync-score: 0.84" in note
    # Frontmatter merged BEFORE `ai-first: true`.
    fm_section = note.split("---", 2)[1]
    assert "feature-count: 1" in fm_section
    assert "ai-first: true" in fm_section
    assert fm_section.index("feature-count") < fm_section.index("ai-first")


def test_parse_doc_actions_block_extracts_checkbox_lines():
    from scripts.architect.sections import parse_doc_actions_block

    body = (
        "### 清除 deprecated 殘留\n"
        "- [ ] Remove `/old-endpoint` mention from README.md L42-48\n"
        "- [ ] Remove deprecated CLI `archive-tickets` from AGENTS.md\n"
        "\n"
        "### 補缺 doc\n"
        "- [ ] Add `Knowledge Base` README section listing /kb-candidates/*\n"
    )
    actions = parse_doc_actions_block(body)
    assert len(actions) == 3
    assert actions[0]["group"] == "清除 deprecated 殘留"
    assert "Remove `/old-endpoint`" in actions[0]["text"]
    assert actions[2]["group"] == "補缺 doc"


def test_parse_doc_actions_block_ignores_non_checkbox_bullets():
    from scripts.architect.sections import parse_doc_actions_block

    body = (
        "### 清除\n"
        "- regular bullet, ignored\n"
        "- [ ] checkbox line, kept\n"
    )
    actions = parse_doc_actions_block(body)
    assert len(actions) == 1
