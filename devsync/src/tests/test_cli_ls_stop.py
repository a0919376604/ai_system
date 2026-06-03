from typer.testing import CliRunner

from devsync.cli import app

_SESSION = {
    "name": "ai-eden-service--dl02",
    "labels": {
        "managed-by": "devsync",
        "repo": "ai-eden-service",
        "server": "dl02",
        "worktree": "none",
        "created-at": "2026-06-02T10:00:00Z",
    },
    "alpha": {"url": {"path": "/Users/leric/Desktop/code/ai-eden-service"}},
    "beta": {"url": {"host": "dl02", "path": "/home/leric/code/ai-eden-service"}},
    "status": "Watching for changes",
    "stagedFiles": 0,
}


def test_ls_empty(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[])
    result = CliRunner().invoke(app, ["ls"])
    assert result.exit_code == 0
    assert "no active" in result.stdout.lower() or "no sessions" in result.stdout.lower()


def test_ls_renders_session(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[_SESSION])
    result = CliRunner().invoke(app, ["ls"])
    assert result.exit_code == 0
    assert "ai-eden-service--dl02" in result.stdout


def test_stop_by_repo(mocker):
    term = mocker.patch("devsync.cli.sync_terminate_by_repo")
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[_SESSION])
    result = CliRunner().invoke(app, ["stop", "ai-eden-service"])
    assert result.exit_code == 0
    term.assert_called_once_with("ai-eden-service")


def test_stop_all(mocker):
    term = mocker.patch("devsync.cli.sync_terminate_all_managed")
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[_SESSION])
    result = CliRunner().invoke(app, ["stop", "--all"])
    assert result.exit_code == 0
    term.assert_called_once()


def test_stop_no_args_errors():
    result = CliRunner().invoke(app, ["stop"])
    assert result.exit_code != 0
