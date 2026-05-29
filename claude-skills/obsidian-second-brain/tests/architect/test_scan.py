from pathlib import Path

from scripts.architect.scan import run_phase_one, ScanResult


def test_phase_one_produces_manifest_and_report(single_lang_python: Path):
    result: ScanResult = run_phase_one(single_lang_python)
    assert result.manifest.version == 1
    assert len(result.manifest.modules) >= 3  # auth, db, api
    assert result.manifest.last_scan["commit"]  # has commit hash
    assert "files" in result.scan_report
    assert "languages" in result.scan_report
    assert "entry_points" in result.scan_report
    assert "external_deps" in result.scan_report


def test_phase_one_deterministic(single_lang_python: Path):
    r1 = run_phase_one(single_lang_python)
    r2 = run_phase_one(single_lang_python)
    # Same commit + same scanner version -> same manifest.
    assert r1.manifest.last_scan["commit"] == r2.manifest.last_scan["commit"]
    assert [m["slug"] for m in r1.manifest.modules] == [m["slug"] for m in r2.manifest.modules]


def test_scan_report_includes_narrative_signals(tmp_path: Path):
    """Phase 1 scan-report must now carry README sections, CHANGELOG, TODOs,
    ADRs, stack, and API surface — even if some are empty."""
    import subprocess
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    (tmp_path / "README.md").write_text("# X\n\n## Features\n\n- alpha\n")
    (tmp_path / "CHANGELOG.md").write_text("# Changelog\n\n## Unreleased\n\n- soon\n")
    (tmp_path / "ARCHITECTURE.md").write_text("# Architecture\n\nNotes.\n")
    (tmp_path / "pyproject.toml").write_text('[project]\nname = "x"\ndependencies = ["fastapi"]\n')
    (tmp_path / "main.py").write_text("# TODO: do thing\nprint('hi')\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "init"], check=True)

    from scripts.architect.scan import run_phase_one
    result = run_phase_one(tmp_path)
    sr = result.scan_report
    assert "readme_sections" in sr
    assert "Features" in sr["readme_sections"]
    assert "changelog" in sr
    assert sr["changelog"]["unreleased"] is not None
    assert "decision_docs" in sr
    assert any(d["kind"] == "architecture-doc" for d in sr["decision_docs"])
    assert "stack" in sr
    assert sr["stack"]["primary-language"] == "Python"
    assert "todos" in sr
    assert "api_surface" in sr


def test_scan_report_includes_ai_flows(tmp_path: Path):
    import subprocess
    from scripts.architect.scan import run_phase_one
    # Build a git repo with LangGraph signature.
    (tmp_path / ".git").mkdir()
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\ndependencies = ["langgraph>=0.2"]\n'
    )
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "graph.py").write_text(
        'from langgraph.graph import StateGraph\n'
        'g = StateGraph(dict)\n'
        'g.add_node("a", lambda s: s)\n'
        'g.add_node("b", lambda s: s)\n'
        'g.add_node("c", lambda s: s)\n'
    )
    (tmp_path / "app" / "prompts").mkdir()
    (tmp_path / "app" / "prompts" / "p.py").write_text(
        'P_PROMPT = """Hello {name}, you are an assistant."""\n'
    )
    # Init git so walker.git_metadata doesn't crash.
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "init"], check=True)

    result = run_phase_one(tmp_path)
    assert "ai_flows" in result.scan_report
    assert len(result.scan_report["ai_flows"]) == 1
    flow = result.scan_report["ai_flows"][0]
    assert flow["framework"] == "langgraph"
    # Prompts extracted into the flow record
    assert "prompts" in flow
    prompt_names = {p["name"] for p in flow["prompts"]}
    assert "P_PROMPT" in prompt_names


def test_scan_report_ai_flows_empty_for_non_ai_project(tmp_path: Path):
    import subprocess
    from scripts.architect.scan import run_phase_one
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\ndependencies = ["flask"]\n'
    )
    (tmp_path / "main.py").write_text('print("hi")\n')
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "init"], check=True)

    result = run_phase_one(tmp_path)
    assert result.scan_report["ai_flows"] == []
