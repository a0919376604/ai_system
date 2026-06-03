from typer.testing import CliRunner

from devsync.cli import app

_SESSION = {"name": "alpha--dl02", "labels": {"managed-by": "devsync", "repo": "alpha"}}


def test_status_prints_raw(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[_SESSION])
    mocker.patch("devsync.cli.sync_status_raw", return_value="Status: Watching")
    result = CliRunner().invoke(app, ["status", "alpha"])
    assert result.exit_code == 0
    assert "Watching" in result.stdout


def test_flush_calls_mutagen(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[_SESSION])
    flush_mock = mocker.patch("devsync.cli.sync_flush")
    result = CliRunner().invoke(app, ["flush", "alpha"])
    assert result.exit_code == 0
    flush_mock.assert_called_once_with("alpha--dl02")


def test_status_no_session(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[])
    result = CliRunner().invoke(app, ["status", "alpha"])
    assert result.exit_code != 0
