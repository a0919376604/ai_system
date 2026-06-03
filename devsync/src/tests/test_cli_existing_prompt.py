from typer.testing import CliRunner

from devsync.cli import app


def _setup(mocker, tmp_path):
    from devsync.config import Defaults, GlobalConfig, ServerConfig

    cfg = GlobalConfig(
        defaults=Defaults(remote_base="/home/leric/code"),
        servers={"dl02": ServerConfig(host="dl02")},
    )
    mocker.patch("devsync.cli.load_global_config", return_value=cfg)
    mocker.patch("devsync.cli.ensure_daemon_running")
    mocker.patch("devsync.cli.ensure_remote_dir")
    mocker.patch("devsync.cli.probe_ssh")
    mocker.patch("devsync.cli._maybe_warn_large")  # skip the countdown


def test_existing_session_reuse_default(mocker, tmp_path):
    _setup(mocker, tmp_path)
    (tmp_path / "alpha").mkdir()
    existing = [
        {
            "name": "alpha--dl02",
            "labels": {"managed-by": "devsync", "repo": "alpha", "server": "dl02"},
        }
    ]
    mocker.patch("devsync.cli.list_managed_sessions", return_value=existing)
    create = mocker.patch("devsync.cli.sync_create")

    # Press Enter -> default = reuse
    result = CliRunner().invoke(
        app,
        ["start", "dl02", str(tmp_path / "alpha"), "--no-ssh"],
        input="\n",
    )
    assert result.exit_code == 0
    create.assert_not_called()


def test_existing_session_restart(mocker, tmp_path):
    _setup(mocker, tmp_path)
    (tmp_path / "alpha").mkdir()
    existing = [
        {
            "name": "alpha--dl02",
            "labels": {"managed-by": "devsync", "repo": "alpha", "server": "dl02"},
        }
    ]
    mocker.patch("devsync.cli.list_managed_sessions", return_value=existing)
    term = mocker.patch("devsync.cli.sync_terminate")
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(
        app,
        ["start", "dl02", str(tmp_path / "alpha"), "--no-ssh"],
        input="R\n",
    )
    assert result.exit_code == 0
    term.assert_called_once_with("alpha--dl02")
    create.assert_called_once()


def test_existing_session_cancel(mocker, tmp_path):
    _setup(mocker, tmp_path)
    (tmp_path / "alpha").mkdir()
    existing = [
        {
            "name": "alpha--dl02",
            "labels": {"managed-by": "devsync", "repo": "alpha", "server": "dl02"},
        }
    ]
    mocker.patch("devsync.cli.list_managed_sessions", return_value=existing)
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(
        app,
        ["start", "dl02", str(tmp_path / "alpha"), "--no-ssh"],
        input="c\n",
    )
    assert result.exit_code != 0
    create.assert_not_called()
