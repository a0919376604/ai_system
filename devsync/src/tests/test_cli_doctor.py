from typer.testing import CliRunner

from devsync.cli import app


def test_doctor_happy_path(mocker, tmp_path):
    # Mock global config to return 2 servers
    from devsync.config import Defaults, GlobalConfig, ServerConfig

    cfg = GlobalConfig(
        defaults=Defaults(code_root=str(tmp_path), remote_base="/srv"),
        servers={"dl01": ServerConfig(host="dl01"), "dl02": ServerConfig(host="dl02")},
    )
    mocker.patch("devsync.cli.load_global_config", return_value=cfg)
    mocker.patch("devsync.cli.daemon_status", return_value=True)
    mocker.patch("devsync.cli.probe_ssh")  # silent success

    result = CliRunner().invoke(app, ["doctor"])
    assert result.exit_code == 0
    assert "dl01" in result.stdout
    assert "dl02" in result.stdout
    assert "running" in result.stdout


def test_doctor_reports_unreachable(mocker, tmp_path):
    from devsync.config import Defaults, GlobalConfig, ServerConfig
    from devsync.errors import ServerUnreachable

    cfg = GlobalConfig(
        defaults=Defaults(code_root=str(tmp_path), remote_base="/srv"),
        servers={"dl01": ServerConfig(host="dl01")},
    )
    mocker.patch("devsync.cli.load_global_config", return_value=cfg)
    mocker.patch("devsync.cli.daemon_status", return_value=True)
    mocker.patch(
        "devsync.cli.probe_ssh",
        side_effect=ServerUnreachable("dl01", "dl01", "timeout"),
    )

    result = CliRunner().invoke(app, ["doctor"])
    # Doctor still exits 0 to show the report; the report itself surfaces failure.
    assert "unreachable" in result.stdout
    assert "timeout" in result.stdout
