from devsync.config import (
    Defaults,
    GlobalConfig,
    RepoConfig,
    ServerConfig,
    resolve_effective_config,
)


def _global_cfg() -> GlobalConfig:
    return GlobalConfig(
        defaults=Defaults(
            code_root="/Users/leric/Desktop/code",
            remote_base="/home/leric/code",
            ignore=["*.pyc"],
        ),
        servers={
            "dl01": ServerConfig(host="dl01"),
            "dl02": ServerConfig(host="dl02", remote_base="/data/leric"),
        },
    )


def test_remote_path_from_defaults_when_repo_silent():
    cfg = resolve_effective_config(
        global_cfg=_global_cfg(),
        repo_cfg=RepoConfig(),
        repo_name="ai-eden-service",
        server_name="dl01",
    )
    assert cfg.remote_path == "/home/leric/code/ai-eden-service"
    assert cfg.host == "dl01"
    assert cfg.sync_mode == "one-way-replica"


def test_server_overrides_remote_base():
    cfg = resolve_effective_config(
        global_cfg=_global_cfg(),
        repo_cfg=RepoConfig(),
        repo_name="ai-eden-service",
        server_name="dl02",
    )
    assert cfg.remote_path == "/data/leric/ai-eden-service"


def test_repo_overrides_remote_path_absolutely():
    cfg = resolve_effective_config(
        global_cfg=_global_cfg(),
        repo_cfg=RepoConfig(remote_path="/srv/custom/x"),
        repo_name="ai-eden-service",
        server_name="dl02",
    )
    assert cfg.remote_path == "/srv/custom/x"


def test_ignore_is_additive():
    cfg = resolve_effective_config(
        global_cfg=_global_cfg(),
        repo_cfg=RepoConfig(ignore=["models/", "*.ckpt"]),
        repo_name="x",
        server_name="dl01",
    )
    # Defaults ignore (["*.pyc"]) + repo additions
    assert "*.pyc" in cfg.ignore
    assert "models/" in cfg.ignore
    assert "*.ckpt" in cfg.ignore
