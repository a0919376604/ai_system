from typer.testing import CliRunner

from devsync.cli import app


def _setup_config(mocker):
    from devsync.config import Defaults, GlobalConfig, ServerConfig

    cfg = GlobalConfig(
        defaults=Defaults(remote_base="/home/leric/code"),
        servers={"dl02": ServerConfig(host="dl02")},
    )
    mocker.patch("devsync.cli.load_global_config", return_value=cfg)
    mocker.patch("devsync.cli.ensure_daemon_running")
    mocker.patch("devsync.cli.ensure_remote_dir")
    mocker.patch("devsync.cli.probe_ssh")
    mocker.patch("devsync.cli._maybe_warn_large")
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[])


def test_start_with_server_only_uses_cwd(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    (tmp_path / "my-repo").mkdir()
    monkeypatch.chdir(tmp_path / "my-repo")
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "dl02", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_with_explicit_path(mocker, tmp_path):
    _setup_config(mocker)
    (tmp_path / "other-repo").mkdir()
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "dl02", str(tmp_path / "other-repo"), "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_with_relative_path(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    (tmp_path / "rel-repo").mkdir()
    monkeypatch.chdir(tmp_path)
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "dl02", "./rel-repo", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_default_server_from_repo_toml(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    repo = tmp_path / "auto"
    repo.mkdir()
    (repo / ".devsync.toml").write_text('default_server = "dl02"\n')
    monkeypatch.chdir(repo)
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_missing_server_and_no_default(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    repo = tmp_path / "no-default"
    repo.mkdir()
    monkeypatch.chdir(repo)

    result = CliRunner().invoke(app, ["start", "--no-ssh"])
    assert result.exit_code != 0
    out = (result.stdout or "") + (result.stderr or "")
    assert "no server" in out.lower() or "no_server" in out.lower()


def test_start_unknown_server_exits_nonzero(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    (tmp_path / "my-repo").mkdir()
    monkeypatch.chdir(tmp_path / "my-repo")

    result = CliRunner().invoke(app, ["start", "ghost", "--no-ssh"])
    assert result.exit_code != 0
    out = (result.stdout or "") + (result.stderr or "")
    assert "ghost" in out.lower() or "unknown" in out.lower()


def test_start_nonexistent_path_exits_nonzero(mocker, tmp_path):
    _setup_config(mocker)
    result = CliRunner().invoke(app, ["start", "dl02", str(tmp_path / "missing"), "--no-ssh"])
    assert result.exit_code != 0
