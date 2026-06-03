import pytest
from pydantic import ValidationError

from devsync.config import Defaults, GlobalConfig, RepoConfig, ServerConfig, load_global_config
from devsync.errors import DevsyncError


def test_defaults_has_sensible_values():
    d = Defaults(
        code_root="/Users/leric/Desktop/code",
        remote_base="/home/leric/code",
    )
    assert d.sync_mode == "one-way-replica"
    assert d.ignore_vcs is True
    assert ".DS_Store" in d.ignore
    assert d.ssh_after_start is True


def test_server_config_minimal():
    s = ServerConfig(host="dl02")
    assert s.host == "dl02"
    assert s.remote_base is None  # falls back to defaults


def test_global_config_loads_servers_dict():
    cfg = GlobalConfig(
        defaults=Defaults(
            code_root="/tmp/code",
            remote_base="/srv/code",
        ),
        servers={"dl01": ServerConfig(host="dl01"), "dl02": ServerConfig(host="dl02")},
    )
    assert set(cfg.servers.keys()) == {"dl01", "dl02"}


def test_repo_config_all_optional():
    rc = RepoConfig()
    assert rc.default_server is None
    assert rc.remote_path is None
    assert rc.ignore == []


def test_global_config_rejects_unknown_field():
    with pytest.raises(ValidationError):
        GlobalConfig(
            defaults=Defaults(code_root="/x", remote_base="/y"),
            servers={},
            unknown_field="boom",
        )


def test_load_global_config_wraps_toml_parse_error(tmp_path):
    bad = tmp_path / "bad.toml"
    bad.write_text("this = is = invalid toml\n")
    with pytest.raises(DevsyncError, match="Invalid TOML"):
        load_global_config(path=bad)
