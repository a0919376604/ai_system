from pathlib import Path

from scripts.architect.walker import walk_repo


def test_walk_repo_returns_relative_paths(single_lang_python: Path):
    files = walk_repo(single_lang_python)
    assert "pyproject.toml" in files
    assert "src/auth/login.py" in files
    assert "tests/test_login.py" in files


def test_walk_repo_excludes_gitignored(single_lang_python: Path, tmp_path: Path):
    # Create a __pycache__/ in the fixture to verify it's filtered.
    cache = single_lang_python / "__pycache__"
    cache.mkdir(exist_ok=True)
    (cache / "junk.pyc").touch()
    try:
        files = walk_repo(single_lang_python)
        assert not any("__pycache__" in f for f in files)
    finally:
        # Clean up so the fixture is not polluted.
        (cache / "junk.pyc").unlink()
        cache.rmdir()


def test_walk_repo_skips_binary_and_dot_git(single_lang_python: Path):
    files = walk_repo(single_lang_python)
    assert not any(f.startswith(".git/") for f in files)

from scripts.architect.walker import language_stats, git_metadata


def test_language_stats_returns_counts_by_extension(single_lang_python: Path):
    stats = language_stats(single_lang_python)
    # stats is a list of dicts: [{"lang": "python", "files": N, "tokens": T}, ...]
    by_lang = {row["lang"]: row for row in stats}
    assert "python" in by_lang
    assert by_lang["python"]["files"] >= 5
    # Tokens are approximate via len(text) // 4 heuristic.
    assert by_lang["python"]["tokens"] > 0


def test_git_metadata_returns_commit_and_dirty(single_lang_python: Path):
    meta = git_metadata(single_lang_python)
    assert len(meta["commit"]) == 40  # full SHA
    assert meta["dirty"] is False
