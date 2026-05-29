from pathlib import Path

from scripts.architect.sections import (
    SECTION_NAMES,
    build_prompt,
    collect_signals,
    compose_note,
    signal_hash,
)


def test_signal_hash_is_deterministic():
    sig = {"foo": "bar", "list": [1, 2, 3]}
    assert signal_hash(sig) == signal_hash(sig)


def test_signal_hash_changes_on_value_change():
    a = signal_hash({"k": "v1"})
    b = signal_hash({"k": "v2"})
    assert a != b


def test_signal_hash_independent_of_dict_order():
    a = signal_hash({"a": 1, "b": 2})
    b = signal_hash({"b": 2, "a": 1})
    assert a == b


def test_section_names_constant():
    assert SECTION_NAMES == ("api-surface", "features", "decisions", "roadmap", "future")


def test_collect_signals_features():
    scan_report = {
        "readme_sections": {"Features": "- alpha\n- beta"},
        "api_surface": {"cli_commands": [{"name": "foo", "description": "do foo", "source": "src/cli.py:1"}],
                        "http_routes": [], "exports": [], "env_vars": [], "detection_status": "complete"},
        "decision_docs": [],
        "changelog": {"unreleased": None, "recent_versions": []},
        "todos": {},
        "stack": {},
    }
    manifest_modules = [{"slug": "cli", "description": "CLI front-end", "paths": ["src/cli.py"]}]
    sig = collect_signals("features", scan_report, manifest_modules)
    assert sig["readme_features"] == "- alpha\n- beta"
    assert sig["cli_commands"][0]["name"] == "foo"
    assert sig["modules"][0]["slug"] == "cli"


def test_collect_signals_roadmap_pulls_changelog_and_todos():
    scan_report = {
        "readme_sections": {"Roadmap": "- streaming"},
        "changelog": {"unreleased": "- soon", "recent_versions": [{"version": "0.1.0", "date": "2026-01-01", "body": "init"}]},
        "todos": {"cli": [{"path": "src/cli.py", "line": 1, "kind": "TODO", "label": "roadmap", "text": "rate-limit"}]},
    }
    sig = collect_signals("roadmap", scan_report, manifest_modules=[])
    assert sig["readme_roadmap"] == "- streaming"
    assert sig["changelog_unreleased"] == "- soon"
    assert sig["roadmap_todos"][0]["text"] == "rate-limit"


def test_build_prompt_en_lists_section_and_signals():
    prompt = build_prompt(
        section="features",
        signal={"readme_features": "- alpha", "cli_commands": [], "http_routes": [], "modules": []},
        output_lang="en",
        project="myproj",
    )
    assert "features" in prompt
    assert "English" in prompt or "en" in prompt
    assert "readme_features" in prompt


def test_build_prompt_zh_tw_demands_chinese_body_and_lists_dont_translate_rules():
    prompt = build_prompt(
        section="roadmap",
        signal={"readme_roadmap": "- streaming"},
        output_lang="zh-TW",
        project="myproj",
    )
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Spec §16.5 — must mention not-translating code identifiers.
    assert "code identifier" in prompt.lower() or "識別" in prompt or "檔名" in prompt


def test_compose_note_wraps_sentinels(tmp_path: Path):
    note = compose_note(
        section="features",
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        signal_sources=["README.md", "src/cli.py"],
        confidence="high",
        output_lang="en",
        generated_blocks={"summary": "We do X.", "capability-inventory": "- alpha\n- beta"},
    )
    assert note.startswith("---\n")
    assert "type: architecture-features" in note
    assert "lang: en" in note
    assert "## For future Claude" in note
    assert "<!-- @generated:start summary -->" in note
    assert "We do X." in note
    assert "<!-- @generated:end summary -->" in note
    assert "<!-- @generated:start capability-inventory -->" in note


def test_compose_note_zh_tw_uses_translated_headings():
    note = compose_note(
        section="features",
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        signal_sources=["README.md"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks={"summary": "做 X"},
    )
    assert "## 給未來 Claude" in note
    assert "## For future Claude" not in note
    assert "lang: zh-TW" in note


def test_compose_note_emits_h2_heading_before_each_block_en():
    """Each @generated block must be preceded by its canonical H2 heading,
    so Obsidian's outline + wikilink anchors work and the body is human-readable."""
    note = compose_note(
        section="api-surface",
        project="x",
        repo_label="github.com/x/y",
        commit="a",
        signal_sources=["a"],
        confidence="high",
        output_lang="en",
        generated_blocks={
            "summary": "API surface for x.",
            "interface-overview": "5 routes grouped by prefix.",
            "env-overview": "3 env vars grouped by prefix.",
        },
    )
    # H2 heading appears before each sentinel start.
    for h2, block in [
        ("## Summary", "summary"),
        ("## Interface overview", "interface-overview"),
        ("## Environment variables overview", "env-overview"),
    ]:
        assert h2 in note, f"missing H2 heading {h2!r}"
        # Heading must come before the sentinel start, not after.
        h2_idx = note.index(h2)
        sentinel_idx = note.index(f"<!-- @generated:start {block} -->")
        assert h2_idx < sentinel_idx, f"{h2!r} appears after its sentinel"


def test_compose_note_h2_headings_translate_to_zh_tw():
    note = compose_note(
        section="api-surface",
        project="x",
        repo_label="github.com/x/y",
        commit="a",
        signal_sources=["a"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks={
            "summary": "x 的介面",
            "interface-overview": "依前綴分組",
            "env-overview": "依前綴分組",
        },
    )
    # zh-TW headings appear; English originals must NOT appear in body.
    assert "## 摘要" in note
    assert "## 介面類型概觀" in note
    assert "## 環境變數概觀" in note
    assert "## Interface overview" not in note
    assert "## Environment variables overview" not in note


def test_compose_note_skips_h2_when_block_body_is_empty():
    """If a block has no body, neither the H2 nor the sentinels should appear."""
    note = compose_note(
        section="features",
        project="x",
        repo_label="github.com/x/y",
        commit="a",
        signal_sources=["a"],
        confidence="high",
        output_lang="en",
        generated_blocks={"summary": "Yes."},  # capability-map + notable-details intentionally omitted
    )
    assert "## Summary" in note
    assert "## Capability map" not in note
    assert "## Notable details" not in note
    assert "<!-- @generated:start capability-map -->" not in note


def test_repo_label_local_prefix_yields_local_path_field():
    from scripts.architect.sections import _repo_yaml_lines
    lines = _repo_yaml_lines("local: /Users/leric/Desktop/code/x")
    assert lines == ['local-path: "/Users/leric/Desktop/code/x"']


def test_repo_label_bare_abs_path_yields_local_path_field():
    from scripts.architect.sections import _repo_yaml_lines
    lines = _repo_yaml_lines("/abs/path/to/repo")
    assert lines == ['local-path: "/abs/path/to/repo"']


def test_repo_label_url_yields_quoted_repo_field():
    from scripts.architect.sections import _repo_yaml_lines
    lines = _repo_yaml_lines("github.com/x/y")
    assert lines == ['repo: "github.com/x/y"']


def test_compose_note_emits_no_double_colon_in_frontmatter():
    """The "repo: local: /path" YAML bug must not regress."""
    note = compose_note(
        section="module",
        project="x",
        repo_label="local: /tmp/foo",
        commit="a",
        signal_sources=["a"],
        confidence="medium",
        output_lang="zh-TW",
        generated_blocks={"scope": "test"},
    )
    # Extract frontmatter block.
    fm = note.split("---", 2)[1]
    # No line should have the pattern "key: word: " (double-colon-with-bare-value).
    for line in fm.splitlines():
        # Allow values that are quoted (real YAML strings).
        if ":" in line and line.count(":") > 1:
            # Must be quoted past the first colon.
            value = line.split(":", 1)[1].strip()
            assert value.startswith('"') and value.endswith('"'), \
                f"unquoted multi-colon in YAML: {line!r}"


def test_compose_note_insufficient_signal_status():
    note = compose_note(
        section="future",
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        signal_sources=[],
        confidence="low",
        output_lang="en",
        generated_blocks={},
        status="insufficient-signal",
    )
    assert "status: insufficient-signal" in note


def test_module_for_path_returns_slug():
    from scripts.architect.sections import module_for_path
    manifest = [
        {"slug": "auth", "paths": ["src/auth"]},
        {"slug": "api", "paths": ["src/api/routes.py"]},
    ]
    assert module_for_path("src/auth/login.py", manifest) == "auth"
    assert module_for_path("src/api/routes.py", manifest) == "api"
    assert module_for_path("random/orphan.py", manifest) is None


def test_render_signals_reviewed_en():
    from scripts.architect.sections import render_signals_reviewed
    out = render_signals_reviewed(
        sources=["CHANGELOG.md", "README.md#Roadmap"],
        todo_counts={"cli": 3, "api": 1},
        lang="en",
    )
    assert "CHANGELOG.md" in out
    assert "README.md#Roadmap" in out
    assert "cli: 3 TODOs" in out


def test_render_signals_reviewed_zh():
    from scripts.architect.sections import render_signals_reviewed
    out = render_signals_reviewed(sources=["CHANGELOG.md"], todo_counts={"cli": 2}, lang="zh-TW")
    assert "cli:" in out
    assert "2" in out


def test_gap_analysis_lists_mentioned_but_not_detected():
    from scripts.architect.sections import gap_analysis
    readme_features = "- Streaming HTTP\n- Plugin system\n- gRPC adapter\n"
    api = {
        "cli_commands": [],
        "http_routes": [{"method": "GET", "path": "/items"}],
        "exports": [{"symbol": "plugin_register", "kind": "named", "source": ""}],
        "env_vars": [],
    }
    gaps = gap_analysis(readme_features=readme_features, api_surface=api)
    # plugin_register suggests plugin system is implemented; streaming and gRPC are not.
    text = "\n".join(gaps)
    assert "Streaming" in text or "streaming" in text
    assert "gRPC" in text


def test_gap_analysis_empty_when_no_readme_features():
    from scripts.architect.sections import gap_analysis
    assert gap_analysis(readme_features="", api_surface={}) == []


def test_compose_function_note_en():
    from scripts.architect.sections import compose_function_note
    note = compose_function_note(
        project="myproj",
        repo_label="github.com/x/y",
        module_slug="cli",
        name="run",
        signature="def run(args: list[str]) -> int",
        source_file="src/cli.py",
        line_range="42-58",
        commit="abc1234",
        output_lang="en",
        generated_blocks={"what-it-does": "Entry point for CLI."},
    )
    assert "type: architecture-function" in note
    assert "module-slug: cli" in note
    assert "## Signature" in note
    assert "def run(args: list[str]) -> int" in note
    assert "Entry point for CLI." in note


def test_compose_function_note_zh_tw_translates_headings():
    from scripts.architect.sections import compose_function_note
    note = compose_function_note(
        project="myproj",
        repo_label="github.com/x/y",
        module_slug="cli",
        name="run",
        signature="def run() -> int",
        source_file="src/cli.py",
        line_range="42-58",
        commit="abc1234",
        output_lang="zh-TW",
        generated_blocks={"what-it-does": "CLI 入口點。"},
    )
    assert "## 函式簽章" in note
    assert "## 功能說明" in note


def test_compose_overview_en_emits_report():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        stack={"primary-language": "Python", "frameworks": ["FastAPI"]},
        output_lang="en",
        modules=[{"slug": "cli", "display_name": "CLI"}, {"slug": "api", "display_name": "API"}],
        entry_points=[{"path": "src/cli.py", "label": "pyproject.scripts.run", "kind": "pyproject"}],
        generated_blocks={
            "purpose": "We do things.",
            "layer-map": "```mermaid\ngraph TD\n  A --> B\n```",
            "external-deps": "- FastAPI 0.110",
            "key-abstractions": "- Module",
        },
    )
    assert "type: architecture-overview" in note
    assert "report-style: true" in note
    assert "moc-style:" not in note
    assert "primary-language: Python" in note
    assert "## Purpose & audience" in note
    assert "## Module map" in note
    assert "[[modules/cli]]" in note
    assert "[[modules/api]]" in note
    assert "[[decisions]]" in note


def test_ai_flow_section_type_registered():
    from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS
    assert SECTION_TYPES.get("ai-flow") == "architecture-ai-flow"
    expected = ("ai-purpose", "graph-topology", "state-schema", "prompts",
                "llm-config", "evaluation", "strengths", "weaknesses",
                "improvements", "dependencies")
    assert _BLOCK_NAMES["ai-flow"] == expected
    for block in ("ai-purpose", "graph-topology", "state-schema", "prompts", "llm-config", "evaluation"):
        assert block in _BLOCK_HEADINGS, f"missing heading mapping for block {block}"


def test_ai_flow_preamble_en_and_zh():
    from scripts.architect.sections import _preamble_for
    en_text = _preamble_for("ai-flow", "en")
    zh_text = _preamble_for("ai-flow", "zh-TW")
    assert "ai" in en_text.lower() or "llm" in en_text.lower()
    assert "AI" in zh_text or "LLM" in zh_text or "Prompts" in zh_text


def test_compose_overview_zh_tw_translates_and_omits_empty_stack():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        stack={},  # empty -> no stack block in frontmatter
        output_lang="zh-TW",
        modules=[],
        entry_points=[],
        generated_blocks={},
    )
    assert "## 給未來 Claude" in note
    assert "## 這是什麼 / 為誰服務" in note
    assert "## 模組地圖" in note
    assert "stack:" not in note  # empty stack omitted per spec §5.7


def test_module_v3_block_names_are_judgment_focused():
    """v3 drops what-it-does/how-it-works/key-files; adds scope/strengths/weaknesses/improvements."""
    from scripts.architect.sections import _BLOCK_NAMES
    assert "module" in _BLOCK_NAMES
    names = set(_BLOCK_NAMES["module"])
    assert {"scope", "strengths", "weaknesses", "improvements", "dependencies"} <= names
    assert "key-files" not in names
    assert "what-it-does" not in names


def test_module_block_headings_translate():
    """Each v3 module block must have a heading entry."""
    from scripts.architect.sections import _BLOCK_HEADINGS
    from scripts.architect.lang import heading
    for block in ("scope", "strengths", "weaknesses", "improvements", "dependencies"):
        h_en = _BLOCK_HEADINGS[block]
        assert heading(h_en, "zh-TW") != h_en, f"{block} heading {h_en!r} has no zh-TW mapping"


def test_module_prompt_demands_judgment_not_description():
    """v3 module prompt must NOT ask for file lists; MUST ask for strengths/weaknesses/improvements."""
    from scripts.architect.sections import build_module_prompt
    prompt = build_module_prompt(
        module_slug="backend",
        repomix_packed="(packed code goes here)",
        agents_md_excerpt="(AGENTS.md excerpt)",
        output_lang="zh-TW",
    )
    # Must not ask for file listings
    assert "key files" not in prompt.lower()
    assert "list of files" not in prompt.lower()
    # Must ask for judgment blocks
    assert "strengths" in prompt
    assert "weaknesses" in prompt
    assert "improvement" in prompt.lower()
    # Each Imp must demand Evidence
    assert "evidence" in prompt.lower() or "Evidence" in prompt
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt


def test_module_prompt_en_no_chinese_directive():
    from scripts.architect.sections import build_module_prompt
    prompt = build_module_prompt(
        module_slug="backend",
        repomix_packed="",
        agents_md_excerpt="",
        output_lang="en",
    )
    assert "繁體中文" not in prompt
    assert "Evidence" in prompt or "evidence" in prompt


def test_module_prompt_demands_evidence_required_for_each_improvement():
    from scripts.architect.sections import build_module_prompt
    prompt = build_module_prompt(
        module_slug="backend", repomix_packed="", agents_md_excerpt="", output_lang="en",
    )
    # Prompt must say: if you can't cite evidence, don't include that improvement.
    assert "do not" in prompt.lower() or "skip" in prompt.lower() or "drop" in prompt.lower()
    # And mention the required Imp fields explicitly.
    for field in ("Why", "Evidence", "Effort", "Risk", "Confidence"):
        assert field in prompt, f"missing required Imp field {field!r}"


def test_render_improvement_block_uses_strict_h3_format():
    from scripts.architect.sections import render_improvements_block, ImprovementItem
    items = [
        ImprovementItem(
            title="Extract EventConsumer to separate worker container",
            why="API process shares CPU with event loop; peak traffic blocks request handling.",
            evidence=["[[Architecture/decisions#Event routing principle]]",
                      "`backend/main.py:120`"],
            effort="M",
            risk_if_not_done="During campaigns LINE webhook backlog grows; admin UI lags.",
            confidence="medium",
        ),
    ]
    rendered = render_improvements_block(items, lang="en")
    assert "### Imp 1: Extract EventConsumer to separate worker container" in rendered
    assert "- **Why:** API process shares CPU" in rendered
    assert "- **Evidence:**" in rendered
    assert "[[Architecture/decisions#Event routing principle]]" in rendered
    assert "`backend/main.py:120`" in rendered
    assert "- **Effort:** M" in rendered
    assert "- **Risk if not done:**" in rendered
    assert "- **Confidence:** medium" in rendered


def test_render_improvement_block_zh_tw():
    from scripts.architect.sections import render_improvements_block, ImprovementItem
    items = [
        ImprovementItem(
            title="拆 EventConsumer 為獨立 worker",
            why="API 跟 EventConsumer 共用 process",
            evidence=["[[Architecture/decisions]]"],
            effort="M",
            risk_if_not_done="流量峰值 API 飆延遲",
            confidence="medium",
        ),
    ]
    rendered = render_improvements_block(items, lang="zh-TW")
    assert "### Imp 1: 拆 EventConsumer 為獨立 worker" in rendered
    assert "**為什麼:**" in rendered
    assert "**證據:**" in rendered
    assert "**Effort:** M" in rendered
    assert "**未做的風險:**" in rendered
    assert "**Confidence:** medium" in rendered


def test_parse_improvements_block_round_trips_render():
    from scripts.architect.sections import (
        render_improvements_block, parse_improvements_block, ImprovementItem,
    )
    items = [
        ImprovementItem(
            title="A",
            why="Because.",
            evidence=["[[X]]", "`y.py:1`"],
            effort="S",
            risk_if_not_done="Bad.",
            confidence="high",
        ),
        ImprovementItem(
            title="B",
            why="Why B.",
            evidence=["[[Z]]"],
            effort="L",
            risk_if_not_done="Worse.",
            confidence="speculation",
        ),
    ]
    rendered = render_improvements_block(items, lang="en")
    parsed = parse_improvements_block(rendered)
    assert len(parsed) == 2
    assert parsed[0].title == "A"
    assert parsed[0].effort == "S"
    assert parsed[0].evidence == ["[[X]]", "`y.py:1`"]
    assert parsed[1].title == "B"
    assert parsed[1].confidence == "speculation"


def test_parse_improvements_block_zh_tw_labels():
    from scripts.architect.sections import parse_improvements_block
    text = (
        "### Imp 1: 拆 EventConsumer 為獨立 worker\n"
        "- **為什麼:** API 跟 EventConsumer 共用 process\n"
        "- **證據:** [[Architecture/decisions]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 流量峰值 API 飆延遲\n"
        "- **Confidence:** medium\n"
    )
    items = parse_improvements_block(text)
    assert len(items) == 1
    assert items[0].title == "拆 EventConsumer 為獨立 worker"
    assert items[0].effort == "M"
    assert items[0].confidence == "medium"


def test_parse_improvements_block_skips_malformed():
    """An Imp with fewer than 5 required fields is dropped, not partially parsed."""
    from scripts.architect.sections import parse_improvements_block
    text = (
        "### Imp 1: Good one\n"
        "- **Why:** w\n"
        "- **Evidence:** [[E]]\n"
        "- **Effort:** S\n"
        "- **Risk if not done:** r\n"
        "- **Confidence:** high\n"
        "\n"
        "### Imp 2: Missing fields\n"
        "- **Why:** only this\n"
    )
    items = parse_improvements_block(text)
    assert len(items) == 1
    assert items[0].title == "Good one"


def test_enforce_improvements_cap_drops_extras():
    """When LLM returns 6 Imps but cap is 4, keep highest-confidence + first ones."""
    from scripts.architect.sections import ImprovementItem, enforce_improvements_cap
    items = [
        ImprovementItem(title=f"Imp {i}", why="w", evidence=["[[e]]"],
                        effort="M", risk_if_not_done="r",
                        confidence="medium" if i % 2 else "stated")
        for i in range(6)
    ]
    capped = enforce_improvements_cap(items, max_n=4)
    assert len(capped) == 4
    # Higher-confidence items should win over lower if cap forces choice.
    titles = [c.title for c in capped]
    # At least one `stated` confidence Imp survives.
    assert any(c.confidence == "stated" for c in capped)


def test_enforce_evidence_required_drops_imps_without_evidence():
    from scripts.architect.sections import ImprovementItem, enforce_evidence_required
    items = [
        ImprovementItem(title="A", why="w", evidence=["[[x]]"], effort="S",
                        risk_if_not_done="r", confidence="stated"),
        ImprovementItem(title="B", why="w", evidence=[], effort="S",
                        risk_if_not_done="r", confidence="stated"),
    ]
    filtered = enforce_evidence_required(items, require=True)
    assert len(filtered) == 1
    assert filtered[0].title == "A"
    # With require=False, both survive (debug mode).
    assert len(enforce_evidence_required(items, require=False)) == 2


def test_overview_v4_block_names_are_top_down_report():
    """v4 overview has 8 body sections matching the top-down report structure."""
    from scripts.architect.sections import _BLOCK_NAMES
    assert "overview" in _BLOCK_NAMES
    expected = (
        "purpose",
        "system-diagram",
        "stack-summary",
        "capabilities",
        "flows",
        "module-map",
        "cross-cutting-improvements",
        "drill-down",
    )
    assert _BLOCK_NAMES["overview"] == expected, \
        f"v4 overview should have these 8 blocks in order, got: {_BLOCK_NAMES['overview']}"


def test_deprecated_section_types_marked():
    """v4.2 marks 5 deprecated SECTION_TYPES entries (still callable for backward compat)."""
    from scripts.architect.sections import SECTION_TYPES, DEPRECATED_SECTIONS
    for s in ("api-surface", "roadmap", "future", "jobs", "flows"):
        assert s in SECTION_TYPES, f"{s} still in SECTION_TYPES (kept for backward compat)"
        assert s in DEPRECATED_SECTIONS, f"{s} should be in DEPRECATED_SECTIONS"


def test_compose_overview_v4_emits_8_body_sections_zh_tw():
    """v4 overview writes a self-contained report, not a MOC."""
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x",
        repo_label="local: /tmp/x",
        commit="abc1234",
        stack={"primary-language": "Python", "frameworks": ["FastAPI"]},
        output_lang="zh-TW",
        modules=[
            {"slug": "backend", "display_name": "Backend"},
            {"slug": "frontend", "display_name": "Frontend"},
        ],
        entry_points=[],
        generated_blocks={
            "purpose": "Project does Y for Z personas.",
            "system-diagram": "```mermaid\ngraph TD\n  A-->B\n```",
            "capabilities": "### Auth\n- login\n### Webhook\n- LINE webhook",
            "flows": "### Flow 1: foo\n```mermaid\nsequenceDiagram\n```\n",
            "cross-cutting-improvements": "### Imp 1: ...",
        },
    )
    # frontmatter
    assert "type: architecture-overview" in note
    assert "report-style: true" in note
    assert "moc-style:" not in note  # v3 marker absent
    # 8 H2 sections (zh-TW)
    assert "## 給未來 Claude" in note
    assert "## 這是什麼 / 為誰服務" in note
    assert "## 系統架構圖" in note
    assert "## 技術棧" in note
    assert "## 核心能力" in note
    assert "## 核心使用流程" in note
    assert "## 模組地圖" in note
    assert "## 跨模組改進機會" in note
    assert "## 想深讀的入口" in note
    # Module-map section auto-renders deterministic wikilinks (independent of LLM blocks)
    assert "[[modules/backend]]" in note
    assert "[[modules/frontend]]" in note
    # Drill-down section lists deterministic wikilinks
    assert "[[decisions]]" in note
    assert "[[personas]]" in note


def test_compose_overview_v4_en():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x",
        repo_label="github.com/x/y",
        commit="abc1234",
        stack={"primary-language": "Python"},
        output_lang="en",
        modules=[{"slug": "backend", "display_name": "Backend"}],
        entry_points=[],
        generated_blocks={"purpose": "Does X.", "system-diagram": "```mermaid\ngraph TD\n  A\n```"},
    )
    for h in [
        "## For future Claude",
        "## Purpose & audience",
        "## System diagram",
        "## Stack",
        "## Capabilities",
        "## Flows",
        "## Module map",
        "## Cross-cutting improvements",
        "## Drill-down entries",
    ]:
        assert h in note, f"missing heading {h!r}"


def test_compose_overview_v4_module_map_renders_each_module_one_line():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x",
        repo_label="local: /tmp/x",
        commit="a",
        stack={},
        output_lang="zh-TW",
        modules=[
            {"slug": "backend", "display_name": "Backend"},
            {"slug": "frontend", "display_name": "Frontend"},
            {"slug": "services", "display_name": "Services"},
        ],
        entry_points=[],
        generated_blocks={},
    )
    # Each module appears as a one-line bullet with its wikilink.
    assert "[[modules/backend]]" in note
    assert "[[modules/frontend]]" in note
    assert "[[modules/services]]" in note


def test_compose_overview_v4_drill_down_links_to_keep_files():
    """Drill-down section links to overview/decisions/personas/Roadmap (the v4 keep set)."""
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x", repo_label="local: /tmp/x", commit="a",
        stack={}, output_lang="zh-TW", modules=[], entry_points=[],
        generated_blocks={},
    )
    drill_section = note[note.index("## 想深讀的入口"):]
    assert "[[decisions]]" in drill_section
    assert "[[personas]]" in drill_section
    assert "[[Roadmap]]" in drill_section  # produced by /obsidian-roadmap
    # Does NOT link to obsolete files
    for obsolete in ("api-surface", "features", "future", "roadmap", "jobs", "flows"):
        assert f"[[{obsolete}]]" not in drill_section, \
            f"drill-down should not reference deleted v3 file {obsolete!r}"


def test_build_overview_prompt_v4_demands_report_blocks():
    from scripts.architect.sections import build_overview_prompt
    prompt = build_overview_prompt(
        project="myproj",
        modules_summary="backend, frontend, services",
        agents_md_excerpt="Tech Stack: FastAPI, React.",
        readme_excerpt="LINE OA admin tool.",
        personas_summary="Admin, Agent, End-user",
        per_module_improvements_summary="See modules/*.md improvements",
        output_lang="zh-TW",
    )
    # Demands the 5 LLM block names
    assert "purpose" in prompt
    assert "system-diagram" in prompt or "system_diagram" in prompt
    assert "capabilities" in prompt
    assert "flows" in prompt
    assert "cross-cutting-improvements" in prompt or "cross_cutting" in prompt
    # Demands Mermaid in system-diagram
    assert "mermaid" in prompt.lower()
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Cross-cutting Imps must follow strict 5-field format
    for field in ("Why", "Evidence", "Effort", "Risk", "Confidence"):
        assert field in prompt


def test_compose_note_warns_on_deprecated_section(caplog):
    """Calling compose_note(section='features'|etc.) still works but logs a deprecation warning."""
    import logging
    from scripts.architect.sections import compose_note
    with caplog.at_level(logging.WARNING):
        note = compose_note(
            section="api-surface",
            project="x",
            repo_label="local: /tmp/x",
            commit="a",
            signal_sources=[],
            confidence="medium",
            output_lang="en",
            generated_blocks={"summary": "Test"},
        )
    assert "deprecated" in caplog.text.lower()
    assert "api-surface" in caplog.text.lower()
    # Note still produced (backward compat).
    assert "type: architecture-api-surface" in note


def test_compose_decisions_emits_known_limitations_block():
    from scripts.architect.sections import compose_note
    note = compose_note(
        section="decisions",
        project="x",
        repo_label="local: /tmp/x",
        commit="a",
        signal_sources=[],
        confidence="medium",
        output_lang="zh-TW",
        generated_blocks={
            "summary": "Decisions index.",
            "stack-rationale": "- React + FastAPI",
            "known-limitations": "- backend/.env deprecated\n- plain-text password fallback",
        },
    )
    assert "## 已知限制" in note
    assert "@generated:start known-limitations" in note
    assert "backend/.env deprecated" in note


def test_resolve_frame_default_is_report():
    from scripts.architect.sections import resolve_frame
    assert resolve_frame(None) == "report"
    assert resolve_frame("report") == "report"
    assert resolve_frame("judgment") == "judgment"
    assert resolve_frame("description") == "description"


def test_resolve_frame_invalid_falls_back_to_report():
    from scripts.architect.sections import resolve_frame
    assert resolve_frame("vibe-driven") == "report"
    assert resolve_frame("") == "report"


def test_build_ai_flow_prompt_demands_required_blocks():
    from scripts.architect.sections import build_ai_flow_prompt
    prompt = build_ai_flow_prompt(
        flow_slug="lang-ai-customer",
        flow_name="LangAI Customer Chat",
        framework="langgraph",
        flow_kind="real-time-chat",
        prompts_inventory=[
            {"name": "intent_classifier", "source": "backend/engines/langgraph/prompts/intent.py:1-25",
             "body": "You are an intent classifier...\n", "is_dynamic": False, "source_hash": "sha256:abc"},
        ],
        state_module="backend/engines/langgraph/core/state.py",
        graph_files=["backend/engines/langgraph/graph.py"],
        repomix_packed="(repomix packed content)",
        output_lang="zh-TW",
    )
    assert "lang-ai-customer" in prompt
    assert "langgraph" in prompt
    # Demands 10 block keys
    for block in ("ai-purpose", "graph-topology", "state-schema", "prompts",
                  "llm-config", "evaluation", "strengths", "weaknesses",
                  "improvements", "dependencies"):
        assert block in prompt, f"prompt should mention block {block}"
    # Prompts section instructions
    assert "collapsible" in prompt.lower() or "callout" in prompt.lower()
    assert "[!quote]" in prompt  # Obsidian callout syntax mentioned
    # Forbid full prompt body invention for dynamic prompts
    assert "dynamic" in prompt.lower()
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Imp 5-field
    for field in ("Why", "Evidence", "Effort", "Risk", "Confidence"):
        assert field in prompt


def test_build_ai_flow_prompt_en_no_chinese():
    from scripts.architect.sections import build_ai_flow_prompt
    prompt = build_ai_flow_prompt(
        flow_slug="x", flow_name="X", framework="langgraph", flow_kind="real-time-chat",
        prompts_inventory=[], state_module=None, graph_files=[],
        repomix_packed="", output_lang="en",
    )
    assert "繁體中文" not in prompt
    assert "English" in prompt or "en" in prompt


def test_render_prompts_block_static_creates_collapsible_callout():
    from scripts.architect.sections import render_prompts_block
    inventory = [
        {
            "name": "intent_classifier",
            "source": "backend/engines/langgraph/prompts/intent.py:1-25",
            "body": "You are an intent classifier.\nUser: {user_message}\n",
            "is_dynamic": False,
            "model_hint": "gemini-flash",
        },
    ]
    annotations = {
        "intent_classifier": {"purpose": "把客戶訊息分類", "type_note": ""},
    }
    rendered = render_prompts_block(inventory, annotations, lang="zh-TW")
    # H3 + metadata + sentinel + callout
    assert "### intent_classifier" in rendered
    assert "**用途:**" in rendered or "**Purpose:**" in rendered
    assert "**Source:** `backend/engines/langgraph/prompts/intent.py:1-25`" in rendered
    assert "**Model:** gemini-flash" in rendered
    assert "**Type:** static template" in rendered
    assert "<!-- @generated:start prompt-intent-classifier -->" in rendered
    assert "<!-- @generated:end prompt-intent-classifier -->" in rendered
    assert "> [!quote]- 完整 prompt" in rendered
    assert "You are an intent classifier" in rendered
    assert "{user_message}" in rendered  # preserved


def test_render_prompts_block_dynamic_omits_collapsible_callout():
    from scripts.architect.sections import render_prompts_block
    inventory = [
        {
            "name": "build_system_prompt",
            "source": "agent.py:10",
            "body": "Assembled from _BASE + persona block at utils/persona.py:42 + tools list at runtime.",
            "is_dynamic": True,
            "model_hint": "gpt-4o",
        },
    ]
    annotations = {"build_system_prompt": {"purpose": "Runtime-assembled system prompt", "type_note": "Dynamic"}}
    rendered = render_prompts_block(inventory, annotations, lang="zh-TW")
    assert "### build_system_prompt" in rendered
    assert "**Type:** dynamic" in rendered
    # NO collapsible callout for dynamic
    assert "[!quote]" not in rendered
    # But still wrapped in sentinel for refresh
    assert "<!-- @generated:start prompt-build-system-prompt -->" in rendered
    # And the description IS visible (not hidden)
    assert "Assembled from _BASE" in rendered


def test_render_prompts_block_empty_inventory():
    from scripts.architect.sections import render_prompts_block
    rendered = render_prompts_block([], {}, lang="zh-TW")
    assert "(no static prompts extracted)" in rendered or "未偵測到 prompts" in rendered


def test_format_ai_engine_link_for_module():
    from scripts.architect.sections import format_ai_engine_link
    line = format_ai_engine_link(
        flow_slug="lang-ai-customer",
        framework="langgraph",
        flow_kind="real-time-chat",
        lang="zh-TW",
    )
    # Sentinel-wrapped, 1-line wikilink
    assert "<!-- @generated:start ai-engine-link -->" in line
    assert "<!-- @generated:end ai-engine-link -->" in line
    assert "[[ai-flows/lang-ai-customer]]" in line
    assert "langgraph" in line.lower()
    assert "real-time-chat" in line.lower()
    # User-facing label
    assert "**AI engine:**" in line


def test_format_ai_engine_link_en():
    from scripts.architect.sections import format_ai_engine_link
    line = format_ai_engine_link(
        flow_slug="qa-to-kb", framework="custom-pipeline",
        flow_kind="batch-pipeline", lang="en",
    )
    assert "[[ai-flows/qa-to-kb]]" in line
    assert "custom-pipeline" in line.lower()
