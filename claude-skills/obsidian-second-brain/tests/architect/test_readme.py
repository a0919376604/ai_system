from pathlib import Path

from scripts.architect.readme import extract_sections

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "readmes"


def test_extract_known_sections_from_full_readme():
    text = (FIXTURE_DIR / "full.md").read_text()
    sections = extract_sections(text)
    assert "Features" in sections
    assert "Fast HTTP client" in sections["Features"]
    assert "Roadmap" in sections
    assert "v2: streaming support" in sections["Roadmap"]
    assert "Coming Soon" in sections
    assert "gRPC adapter" in sections["Coming Soon"]
    assert "Limitations" in sections
    assert "No Windows support" in sections["Limitations"]
    assert "Known Issues" in sections
    assert "Future Work" in sections


def test_empty_readme_returns_empty_dict():
    text = (FIXTURE_DIR / "empty.md").read_text()
    assert extract_sections(text) == {}


def test_section_extraction_is_case_insensitive():
    text = "# Foo\n\n## FEATURES\n\n- one\n\n## roadmap\n\n- two\n"
    sections = extract_sections(text)
    assert "Features" in sections  # normalized to title-case key
    assert "Roadmap" in sections


def test_section_body_excludes_subsequent_h2():
    text = "## Features\n\n- a\n\n## Roadmap\n\n- b\n"
    sections = extract_sections(text)
    assert "Roadmap" not in sections["Features"]
    assert "- a" in sections["Features"]


def test_extended_aliases_for_real_world_readmes():
    """Real-world H2s we see in monorepos: Architecture, Tech Stack, Local Development, etc."""
    text = (
        "## Architecture\n\nLayered.\n\n"
        "## Tech Stack\n\nReact + FastAPI.\n\n"
        "## Project Overview\n\nDoes X.\n\n"
        "## Configuration\n\nUse env.\n\n"
        "## Environment Variables\n\nDB_URL.\n\n"
        "## Local Development\n\nuv sync.\n\n"
        "## Deployment\n\nDocker.\n\n"
        "## Project Structure\n\nTree here.\n\n"
        "## Getting Started\n\nclone + run.\n\n"
        "## Usage\n\nUse it.\n"
    )
    s = extract_sections(text)
    assert "Architecture" in s
    assert "Stack" in s and "React + FastAPI" in s["Stack"]
    assert "Overview" in s and "Does X" in s["Overview"]
    assert "Configuration" in s
    assert "Environment Variables" in s
    assert "Development" in s
    assert "Deployment" in s
    assert "Structure" in s
    assert "Getting Started" in s
    assert "Usage" in s


def test_extract_from_repo_walks_subdir_readmes(tmp_path: Path):
    """extract_from_repo aggregates root README plus known monorepo subdir READMEs."""
    from scripts.architect.readme import extract_from_repo
    (tmp_path / "README.md").write_text("## Features\n\n- root feature\n")
    (tmp_path / "backend").mkdir()
    (tmp_path / "backend" / "README.md").write_text("## Architecture\n\nbackend layered.\n")
    (tmp_path / "frontend").mkdir()
    (tmp_path / "frontend" / "README.md").write_text("## Tech Stack\n\nReact 19\n")
    result = extract_from_repo(tmp_path)
    assert "Features" in result
    assert "backend/Architecture" in result
    assert "frontend/Stack" in result
    assert "React 19" in result["frontend/Stack"]


def test_extract_from_repo_handles_missing_root_readme(tmp_path: Path):
    from scripts.architect.readme import extract_from_repo
    (tmp_path / "backend").mkdir()
    (tmp_path / "backend" / "README.md").write_text("## Features\n\n- only backend\n")
    result = extract_from_repo(tmp_path)
    assert "backend/Features" in result
    assert "Features" not in result
