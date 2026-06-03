import pytest

from devsync.errors import NoSuchRepo
from devsync.repo import RepoSpec, resolve_repo


def test_repospec_from_simple_path(tmp_path):
    d = tmp_path / "my-project"
    d.mkdir()
    spec = RepoSpec.from_path(d)
    assert spec.name == "my-project"
    assert spec.local_path == d.resolve()
    assert spec.is_worktree is False


def test_repospec_from_worktree_path(tmp_path):
    d = tmp_path / "my-project-wt-3"
    d.mkdir()
    spec = RepoSpec.from_path(d)
    assert spec.name == "my-project-wt-3"
    assert spec.is_worktree is True
    assert spec.parent_repo == "my-project"


def test_resolve_repo_none_uses_cwd(tmp_path):
    repo = tmp_path / "my-project"
    repo.mkdir()
    spec = resolve_repo(None, cwd=repo)
    assert spec.name == "my-project"
    assert spec.local_path == repo.resolve()


def test_resolve_repo_absolute_path(tmp_path):
    repo = tmp_path / "alpha"
    repo.mkdir()
    spec = resolve_repo(str(repo))
    assert spec.name == "alpha"
    assert spec.local_path == repo.resolve()


def test_resolve_repo_relative_path(tmp_path, monkeypatch):
    (tmp_path / "beta").mkdir()
    monkeypatch.chdir(tmp_path)
    spec = resolve_repo("./beta")
    assert spec.name == "beta"
    assert spec.local_path == (tmp_path / "beta").resolve()


def test_resolve_repo_tilde_expansion(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    (tmp_path / "gamma").mkdir()
    spec = resolve_repo("~/gamma")
    assert spec.name == "gamma"
    assert spec.local_path == (tmp_path / "gamma").resolve()


def test_resolve_repo_nonexistent_raises(tmp_path):
    with pytest.raises(NoSuchRepo) as exc:
        resolve_repo(str(tmp_path / "does-not-exist"))
    assert "does-not-exist" in str(exc.value)


def test_resolve_repo_file_not_dir_raises(tmp_path):
    f = tmp_path / "afile.txt"
    f.write_text("not a dir")
    with pytest.raises(NoSuchRepo):
        resolve_repo(str(f))
