from pathlib import Path

from scripts.architect.entry_points import detect_entry_points


def test_pyproject_scripts(single_lang_python: Path):
    eps = detect_entry_points(single_lang_python)
    # Expect entry from pyproject.toml [project.scripts]
    paths = [e["path"] for e in eps]
    labels = [e["label"] for e in eps]
    assert any("fixture-cli" in label for label in labels)
    assert any("src/api/routes" in p for p in paths)


def test_package_json_main(monorepo_pnpm: Path):
    eps = detect_entry_points(monorepo_pnpm / "packages" / "web")
    labels = [e["label"] for e in eps]
    paths = [e["path"] for e in eps]
    assert any("main" in label or "web" in label for label in labels)
    assert any("index.js" in p for p in paths)


def test_no_entry_points_when_absent(docs_only_repo: Path):
    eps = detect_entry_points(docs_only_repo)
    assert eps == []
