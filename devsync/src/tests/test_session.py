from devsync.repo import RepoSpec
from devsync.session import SessionSpec, session_name


def test_session_name_simple():
    assert session_name("ai-eden-service", "dl02") == "ai-eden-service--dl02"


def test_session_name_worktree_name_preserved():
    assert session_name("ai-eden-service-wt-1", "dl02") == "ai-eden-service-wt-1--dl02"


def test_session_spec_labels_include_required_keys(tmp_path):
    (tmp_path / "ai-eden-service").mkdir()
    repo = RepoSpec.from_path(tmp_path / "ai-eden-service")
    spec = SessionSpec(repo=repo, server_name="dl02")
    labels = spec.labels()
    keys = {k for k, _ in labels}
    assert {"managed-by", "repo", "server", "worktree", "created-at"} <= keys
    assert ("managed-by", "devsync") in labels
    assert ("worktree", "none") in labels


def test_session_spec_labels_worktree_name(tmp_path):
    (tmp_path / "ai-eden-service-wt-3").mkdir()
    repo = RepoSpec.from_path(tmp_path / "ai-eden-service-wt-3")
    spec = SessionSpec(repo=repo, server_name="dl02")
    labels = dict(spec.labels())
    assert labels["worktree"] == "ai-eden-service-wt-3"
    assert labels["repo"] == "ai-eden-service-wt-3"
