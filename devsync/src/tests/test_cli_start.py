from typer.testing import CliRunner

from devsync.cli import app


def _setup_config(mocker, tmp_path):
    from devsync.config import Defaults, GlobalConfig, ServerConfig

    cfg = GlobalConfig(
        defaults=Defaults(code_root=str(tmp_path), remote_base="/home/leric/code"),
        servers={"dl02": ServerConfig(host="dl02")},
    )
    mocker.patch("devsync.cli.load_global_config", return_value=cfg)
    mocker.patch("devsync.cli.ensure_daemon_running")
    mocker.patch("devsync.cli.ensure_remote_dir")
    mocker.patch("devsync.cli.probe_ssh")
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[])  # no existing session


def test_start_creates_session(mocker, tmp_path):
    _setup_config(mocker, tmp_path)
    (tmp_path / "my-repo").mkdir()
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "my-repo", "dl02", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_ambiguous_repo_exits_nonzero(mocker, tmp_path):
    _setup_config(mocker, tmp_path)
    (tmp_path / "alpha-service").mkdir()
    (tmp_path / "alpha-service-wt-1").mkdir()

    result = CliRunner().invoke(app, ["start", "alpha", "dl02", "--no-ssh"])
    assert result.exit_code != 0
    assert "ambiguous" in result.stdout.lower() or "ambiguous" in result.stderr.lower()


def test_start_unknown_server_exits_nonzero(mocker, tmp_path):
    _setup_config(mocker, tmp_path)
    (tmp_path / "my-repo").mkdir()

    result = CliRunner().invoke(app, ["start", "my-repo", "ghost", "--no-ssh"])
    assert result.exit_code != 0
