from pathlib import Path

from scripts.architect.adr import discover_decision_docs


def test_finds_docs_adr(tmp_path: Path):
    adr_dir = tmp_path / "docs" / "adr"
    adr_dir.mkdir(parents=True)
    (adr_dir / "0001-use-postgres.md").write_text("# Use Postgres\n\nWe chose Postgres because...\n")
    (adr_dir / "0002-switch-to-pnpm.md").write_text("# Switch to pnpm\n\n...\n")
    docs = discover_decision_docs(tmp_path)
    paths = [d.path for d in docs]
    assert "docs/adr/0001-use-postgres.md" in paths
    assert "docs/adr/0002-switch-to-pnpm.md" in paths


def test_finds_architecture_md(tmp_path: Path):
    (tmp_path / "ARCHITECTURE.md").write_text("# Architecture\n\nWe use hexagonal architecture.\n")
    docs = discover_decision_docs(tmp_path)
    titles = [d.title for d in docs]
    assert "Architecture" in titles


def test_finds_design_md(tmp_path: Path):
    (tmp_path / "DESIGN.md").write_text("# Design\n\nDesign notes.\n")
    docs = discover_decision_docs(tmp_path)
    titles = [d.title for d in docs]
    assert "Design" in titles


def test_returns_empty_when_no_docs(tmp_path: Path):
    assert discover_decision_docs(tmp_path) == []


def test_kind_classification(tmp_path: Path):
    (tmp_path / "docs" / "adr").mkdir(parents=True)
    (tmp_path / "docs" / "adr" / "0001-foo.md").write_text("# foo")
    (tmp_path / "ARCHITECTURE.md").write_text("# Architecture")
    docs = {d.kind for d in discover_decision_docs(tmp_path)}
    assert "adr" in docs
    assert "architecture-doc" in docs


def test_agents_md_is_discovered_as_agent_doc(tmp_path: Path):
    """AGENTS.md is the canonical 'for AI agents' instruction file in many repos."""
    (tmp_path / "AGENTS.md").write_text(
        "# AGENTS.md\n\n## Project Overview\n\nDoes X.\n\n## Tech Stack\n\nFastAPI + React.\n"
    )
    docs = discover_decision_docs(tmp_path)
    assert len(docs) == 1
    assert docs[0].path == "AGENTS.md"
    assert docs[0].kind == "agent-doc"


def test_claude_md_is_discovered_as_agent_doc(tmp_path: Path):
    """CLAUDE.md (Claude Code convention) shares the agent-doc role."""
    (tmp_path / "CLAUDE.md").write_text("# CLAUDE.md\n\n## How this repo works\n\nFoo.\n")
    docs = discover_decision_docs(tmp_path)
    assert len(docs) == 1
    assert docs[0].path == "CLAUDE.md"
    assert docs[0].kind == "agent-doc"


def test_agent_doc_does_not_pick_up_vault_marker(tmp_path: Path):
    """A vault's _CLAUDE.md (leading underscore) is operating manual, not a repo decision doc."""
    (tmp_path / "_CLAUDE.md").write_text("# vault operating manual")
    docs = discover_decision_docs(tmp_path)
    assert all(d.path != "_CLAUDE.md" for d in docs)
