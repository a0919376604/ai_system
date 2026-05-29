from pathlib import Path

from scripts.architect.changelog import parse_changelog

FIXTURE = Path(__file__).parent / "fixtures" / "changelogs" / "keepachangelog.md"


def test_parses_unreleased_block():
    cl = parse_changelog(FIXTURE.read_text())
    assert cl.unreleased is not None
    assert "Foo" in cl.unreleased
    assert "Crash on startup" in cl.unreleased


def test_parses_bracketed_unreleased_block():
    cl = parse_changelog("# Changelog\n\n## [Unreleased]\n\n- Foo\n")
    assert cl.unreleased is not None
    assert "Foo" in cl.unreleased


def test_recent_versions_up_to_three():
    cl = parse_changelog(FIXTURE.read_text())
    assert len(cl.recent_versions) == 3
    assert cl.recent_versions[0].version == "0.3.0"
    assert cl.recent_versions[0].date == "2026-05-20"
    assert "WASM" in cl.recent_versions[0].body


def test_empty_changelog():
    cl = parse_changelog("# Changelog\n\nNothing yet.\n")
    assert cl.unreleased is None
    assert cl.recent_versions == []


def test_missing_file_returns_none_via_loader(tmp_path: Path):
    from scripts.architect.changelog import load_changelog
    assert load_changelog(tmp_path) is None
