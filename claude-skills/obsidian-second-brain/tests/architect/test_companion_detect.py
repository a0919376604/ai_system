"""Tests for scripts.architect.companion_detect.detect_companion_archetype."""
from __future__ import annotations

from pathlib import Path

from scripts.architect.companion_detect import (
    detect_companion_archetype,
    CompanionDetection,
    LayerEvidence,
)


def test_detect_companion_when_character_and_storyline_present(tmp_path: Path):
    """Both layers' signals → archetype=ai-companion, confidence=high."""
    chars = tmp_path / "app" / "characters"
    chars.mkdir(parents=True)
    (chars / "definitions").mkdir()
    (chars / "definitions" / "alice.json").write_text('{"name":"Alice"}', encoding="utf-8")
    (chars / "storyline.py").write_text(
        "# Storyline DSL\ndef beat(name): pass\n", encoding="utf-8"
    )

    result = detect_companion_archetype(repo_root=tmp_path, hub_frontmatter=None)
    assert isinstance(result, CompanionDetection)
    assert result.archetype == "ai-companion"
    assert result.confidence == "high"
    assert result.layers["character-card"].present is True
    assert result.layers["storyline"].present is True


def test_detect_no_companion_when_only_character(tmp_path: Path):
    """Character but NO storyline → archetype=none (generic LLM wrapper)."""
    chars = tmp_path / "app" / "characters"
    chars.mkdir(parents=True)
    (chars / "definitions").mkdir()
    (chars / "definitions" / "alice.json").write_text('{}', encoding="utf-8")
    # No storyline file.

    result = detect_companion_archetype(repo_root=tmp_path, hub_frontmatter=None)
    assert result.archetype == "none"


def test_detect_no_companion_when_only_storyline(tmp_path: Path):
    """Storyline but NO characters → archetype=none."""
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "storyline_dsl.py").write_text(
        "# storyline things\n", encoding="utf-8"
    )

    result = detect_companion_archetype(repo_root=tmp_path, hub_frontmatter=None)
    assert result.archetype == "none"


def test_frontmatter_override_forces_archetype(tmp_path: Path):
    """`archetype: ai-companion` in hub frontmatter forces detection."""
    # Empty repo (no character / storyline dirs).
    result = detect_companion_archetype(
        repo_root=tmp_path,
        hub_frontmatter={"archetype": "ai-companion"},
    )
    assert result.archetype == "ai-companion"
    assert result.confidence == "stated"
    # All 4 layers marked present (even with no code evidence — confidence speculation).
    for layer_name in ("character-card", "world", "storyline", "memory"):
        assert result.layers[layer_name].present is True


def test_world_layer_optional(tmp_path: Path):
    """character + storyline present, world dir missing → archetype=ai-companion
    but world.present=False."""
    chars = tmp_path / "app" / "personas"
    chars.mkdir(parents=True)
    (chars / "alice.yaml").write_text("name: Alice\n", encoding="utf-8")
    (tmp_path / "app" / "storyline_engine.py").write_text(
        "# beat / storyline / progression engine\n", encoding="utf-8"
    )
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.archetype == "ai-companion"
    assert result.layers["character-card"].present is True
    assert result.layers["storyline"].present is True
    assert result.layers["world"].present is False


def test_storyline_dsl_file_recognized(tmp_path: Path):
    """A file ending in `_dsl.py` with storyline keyword → storyline_dsl_file populated."""
    chars = tmp_path / "characters"
    chars.mkdir()
    (chars / "alice.json").write_text("{}", encoding="utf-8")
    (tmp_path / "story_dsl.py").write_text(
        "# DSL for storyline + beat + progression\n", encoding="utf-8"
    )
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.layers["storyline"].storyline_dsl_file == "story_dsl.py"


def test_detect_with_alt_directory_names(tmp_path: Path):
    """`personas/` / `bots/` / `companions/` all alias for character-card."""
    bots = tmp_path / "bots"
    bots.mkdir()
    (bots / "bot1.json").write_text("{}", encoding="utf-8")
    (tmp_path / "storyline.py").write_text("# storyline beat\n", encoding="utf-8")
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.archetype == "ai-companion"
    assert "bots" in result.layers["character-card"].root_paths[0]


def test_no_archetype_when_storyline_keyword_missing_in_file(tmp_path: Path):
    """File named `storyline.py` but content doesn't contain the keyword → not a storyline."""
    chars = tmp_path / "characters"
    chars.mkdir()
    (chars / "alice.json").write_text("{}", encoding="utf-8")
    (tmp_path / "storyline.py").write_text(
        "# this file is named storyline but content unrelated\n"
        "def hello(): pass\n",
        encoding="utf-8",
    )
    # Filename pattern matches but content has 'storyline' keyword in comment too...
    # Adjust: use a filename that matches AND content without keyword.
    (tmp_path / "storyline.py").write_text(
        "def hello(): pass\n",
        encoding="utf-8",
    )
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.archetype == "none"
