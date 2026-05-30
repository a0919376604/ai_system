"""Tests for scripts.board.refresh.refresh_board."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from scripts.board.refresh import _FRONTMATTER_LAST_REFRESH_RE, RefreshResult, refresh_board


def test_refresh_returns_skipped_when_no_board_md(tmp_path: Path):
    """When Projects/<P>/board.md doesn't exist -> status='skipped'."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    # No board.md exists -- only hub note.
    (proj_dir / "myproject.md").write_text(
        "---\nlocal-path: /tmp/myrepo\n---\n", encoding="utf-8"
    )

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert isinstance(result, RefreshResult)
    assert result.status == "skipped"
    assert "no board.md" in result.message.lower()
    assert result.project_slug == "myproject"


def _init_repo(repo: Path) -> None:
    subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)


def _commit(repo: Path, path: str, content: str, message: str, date: str) -> None:
    p = repo / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    subprocess.run(["git", "add", path], cwd=repo, check=True)
    env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(
        ["git", "commit", "-m", message, "--date", date],
        cwd=repo,
        check=True,
        capture_output=True,
        env=env,
    )


def test_refresh_walks_git_log_when_signals_none(tmp_path: Path):
    """signals=None -> helper walks git log itself; populates new_items."""
    # Project skeleton.
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n\n"
        "## 待辦\n- placeholder\n",
        encoding="utf-8",
    )

    # Repo with one commit AFTER last-refresh.
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "add a", "2026-05-15T12:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.status == "ok"
    assert result.last_refresh_before == "2026-05-01T00:00:00"
    titles = [item.get("title", "") for item in result.new_items]
    assert any("add a" in t for t in titles), f"expected commit picked up; got {titles}"


def test_refresh_full_mode_ignores_last_refresh(tmp_path: Path):
    """full=True walks ALL git history regardless of last-refresh timestamp."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2030-01-01T00:00:00\n---\n",
        encoding="utf-8",
    )

    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "old commit", "2026-01-01T00:00:00")

    # Without full=True the future timestamp would exclude everything.
    result = refresh_board(project_dir=proj_dir, signals=None, full=True)
    assert result.status == "ok"
    titles = [item.get("title", "") for item in result.new_items]
    assert any("old commit" in t for t in titles), (
        f"full mode should include pre-last-refresh commits; got {titles}"
    )


def test_refresh_classifies_commit_on_main_as_done(tmp_path: Path):
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n\n## 待辦\n- old item\n",
        encoding="utf-8",
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "feat: shipped feature A", "2026-05-15T12:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.status == "ok"
    assert result.done_count >= 1, f"commit on main should be Done; got {result.done_count}"


def test_refresh_classifies_brainstorm_branch_as_in_progress(tmp_path: Path):
    """Commits visible only on brainstorm/* branches are In Progress."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n", encoding="utf-8"
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "initial", "2026-05-10T00:00:00")
    # Make a brainstorm branch with a NEW commit.
    subprocess.run(
        ["git", "checkout", "-b", "brainstorm/foo"], cwd=repo, check=True, capture_output=True
    )
    _commit(repo, "b.py", "y=2\n", "wip: trying foo", "2026-05-16T00:00:00")
    subprocess.run(["git", "checkout", "main"], cwd=repo, check=True, capture_output=True)

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.in_flight_count >= 1, (
        f"brainstorm/* commit should be In Progress; got {result.in_flight_count}"
    )


def test_refresh_clusters_into_existing_buckets_by_keyword(tmp_path: Path):
    """Items whose title contains a keyword from existing H2 bucket -> that bucket.
    Unmatched -> ## Misc / Untriaged.
    """
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    # Existing buckets: "## Auth" and "## Billing".
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n\n"
        "## Auth\n- existing auth item\n\n"
        "## Billing\n- existing billing item\n",
        encoding="utf-8",
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "auth.py", "x=1\n", "fix auth bug", "2026-05-15T00:00:00")
    _commit(repo, "billing.py", "x=2\n", "add billing feature", "2026-05-15T01:00:00")
    _commit(repo, "other.py", "x=3\n", "tweak something random", "2026-05-15T02:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert "Auth" in result.buckets, f"got {result.buckets}"
    assert "Billing" in result.buckets
    assert "Misc / Untriaged" in result.buckets


def test_refresh_with_signals_reuses_caller_data(tmp_path: Path):
    """When signals={...} provided, helper uses items from there -- skips git walks."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        "---\nlocal-path: /nonexistent/path\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n", encoding="utf-8"
    )

    # Architect passes pre-collected items.
    signals = {
        "git_commits": [
            {
                "title": "feat: pre-collected",
                "kind": "commit",
                "when": "2026-05-15T00:00:00",
                "source": "commit deadbeef",
                "refs": "HEAD -> main",
            },
        ],
        "spec_files": [],
        "plan_files": [],
    }
    result = refresh_board(project_dir=proj_dir, signals=signals, full=False)
    assert result.status == "ok"
    assert result.done_count == 1
    titles = [item["title"] for item in result.new_items]
    assert "feat: pre-collected" in titles


def test_refresh_writes_updated_last_refresh_to_frontmatter(tmp_path: Path):
    """After refresh, board.md frontmatter has updated last-refresh timestamp."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\ntotal: 0\n---\n\n"
        "## 待辦\n- old\n",
        encoding="utf-8",
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "do thing", "2026-05-15T00:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.status == "ok"
    # Read board back; last-refresh should be NEWER than before.
    new_text = (proj_dir / "board.md").read_text(encoding="utf-8")
    new_ts = _FRONTMATTER_LAST_REFRESH_RE.search(new_text).group("ts").strip()
    assert new_ts > "2026-05-01T00:00:00", f"new last-refresh should be later; got {new_ts}"
    assert new_ts == result.last_refresh_after
