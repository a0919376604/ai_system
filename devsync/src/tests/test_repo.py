import pytest

from devsync.errors import AmbiguousRepo, NoSuchRepo
from devsync.repo import RepoSpec, resolve_repo


def test_repospec_from_simple_path(tmp_path):
    d = tmp_path / "my-project"
    d.mkdir()
    spec = RepoSpec.from_path(d)
    assert spec.name == "my-project"
    assert spec.local_path == d
    assert spec.is_worktree is False


def test_repospec_from_worktree_path(tmp_path):
    # Worktree convention: <repo>-wt-N
    d = tmp_path / "my-project-wt-3"
    d.mkdir()
    spec = RepoSpec.from_path(d)
    assert spec.name == "my-project-wt-3"  # name as-is
    assert spec.is_worktree is True
    assert spec.parent_repo == "my-project"


def test_resolve_repo_exact_match(tmp_path):
    (tmp_path / "alpha").mkdir()
    (tmp_path / "beta").mkdir()
    spec = resolve_repo("alpha", code_root=tmp_path)
    assert spec.name == "alpha"


def test_resolve_repo_from_cwd_when_arg_none(tmp_path):
    repo = tmp_path / "my-project"
    repo.mkdir()
    spec = resolve_repo(None, code_root=tmp_path, cwd=repo)
    assert spec.name == "my-project"


def test_resolve_repo_fuzzy_single_match(tmp_path):
    (tmp_path / "ai-eden-service").mkdir()
    (tmp_path / "langlive-line-oa").mkdir()
    spec = resolve_repo("eden", code_root=tmp_path)
    assert spec.name == "ai-eden-service"


def test_resolve_repo_ambiguous_raises(tmp_path):
    (tmp_path / "ai-eden-service").mkdir()
    (tmp_path / "ai-eden-service-wt-1").mkdir()
    with pytest.raises(AmbiguousRepo) as exc:
        resolve_repo("ai-eden", code_root=tmp_path)
    assert "ai-eden-service" in exc.value.matches
    assert "ai-eden-service-wt-1" in exc.value.matches


def test_resolve_repo_no_match_raises(tmp_path):
    (tmp_path / "alpha").mkdir()
    with pytest.raises(NoSuchRepo):
        resolve_repo("zzz", code_root=tmp_path)
