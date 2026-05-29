import subprocess
from pathlib import Path

from scripts.architect.commit_decisions import extract_commit_decisions


def _git_repo(tmp_path: Path, commits: list[tuple[str, str]]):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    for fname, msg in commits:
        (tmp_path / fname).write_text("x")
        subprocess.run(["git", "-C", str(tmp_path), "add", fname], check=True)
        subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", msg], check=True)


def test_matches_decided(tmp_path: Path):
    _git_repo(tmp_path, [
        ("a.txt", "feat: add a"),
        ("b.txt", "chore: decided to use Postgres over MySQL"),
        ("c.txt", "fix: typo"),
    ])
    decisions = extract_commit_decisions(tmp_path, limit=10)
    assert any("decided to use Postgres" in d.message for d in decisions)


def test_matches_switched_chose_replaced(tmp_path: Path):
    _git_repo(tmp_path, [
        ("a", "switched from yarn to pnpm"),
        ("b", "chose Redis for cache"),
        ("c", "replaced flask with fastapi"),
        ("d", "moved to monorepo"),
    ])
    msgs = [d.message for d in extract_commit_decisions(tmp_path, limit=10)]
    assert len(msgs) == 4


def test_ignores_unrelated(tmp_path: Path):
    _git_repo(tmp_path, [("a", "bump version"), ("b", "wip")])
    assert extract_commit_decisions(tmp_path, limit=10) == []
