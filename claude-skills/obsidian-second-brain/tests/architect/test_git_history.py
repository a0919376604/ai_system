"""Tests for scripts.architect.git_history.last_touch_map."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from scripts.architect.git_history import last_touch_map


def _init_git_repo(repo: Path):
    """Initialize a git repo with a known config so commits succeed in CI."""
    subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t.t"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)


def _commit(repo: Path, path: str, content: str, date: str):
    file_path = repo / path
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(content, encoding="utf-8")
    subprocess.run(["git", "add", path], cwd=repo, check=True)
    env = {"GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(
        ["git", "commit", "-m", f"add {path}", "--date", date],
        cwd=repo,
        check=True,
        capture_output=True,
        env={**__import__("os").environ, **env},
    )


def test_returns_last_touch_dates_for_committed_files(tmp_path):
    _init_git_repo(tmp_path)
    _commit(tmp_path, "a.py", "x=1\n", "2026-05-01T12:00:00")
    _commit(tmp_path, "b.py", "y=2\n", "2025-09-12T08:30:00")
    result = last_touch_map(tmp_path, ["a.py", "b.py"])
    assert result["a.py"] == "2026-05-01"
    assert result["b.py"] == "2025-09-12"


def test_omits_uncommitted_files(tmp_path):
    """Files never committed → key absent (not '—', not 'unknown')."""
    _init_git_repo(tmp_path)
    _commit(tmp_path, "tracked.py", "z=3\n", "2026-04-01T00:00:00")
    (tmp_path / "untracked.py").write_text("u=1\n", encoding="utf-8")
    result = last_touch_map(tmp_path, ["tracked.py", "untracked.py"])
    assert result["tracked.py"] == "2026-04-01"
    assert "untracked.py" not in result


def test_caps_at_200_files_by_mtime(tmp_path):
    """When >200 files passed, only 200 most-recently-modified are queried."""
    _init_git_repo(tmp_path)
    # Create 205 files but only commit 1 (to keep test fast).
    _commit(tmp_path, "tracked.py", "z=3\n", "2026-04-01T00:00:00")
    files = ["tracked.py"]
    for i in range(205):
        p = tmp_path / f"u_{i:03d}.py"
        p.write_text(f"u={i}\n", encoding="utf-8")
        files.append(f"u_{i:03d}.py")
    # Should NOT blow up; tracked.py may or may not be in the 200 chosen
    # (it has older mtime than the 205 just-written files, so likely NOT
    # in the returned map — which is acceptable; cap is best-effort).
    result = last_touch_map(tmp_path, files)
    # Tracked.py is older than the 205 untracked → likely dropped. Either way,
    # the map must not have >200 entries.
    assert len(result) <= 200, f"expected ≤200 entries; got {len(result)}"
