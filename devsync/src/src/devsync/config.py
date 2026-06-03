"""Configuration models and loaders for devsync.

Layers (highest precedence first):
  1. CLI flags
  2. <repo>/.devsync.toml (RepoConfig)
  3. [servers.<name>] (ServerConfig overrides)
  4. [defaults] (Defaults)
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from devsync.errors import DevsyncError

DEFAULT_IGNORE = [
    ".DS_Store",
    "*.pyc",
    "__pycache__/",
    ".venv/",
    "node_modules/",
    ".pytest_cache/",
    ".ruff_cache/",
    "*.ckpt",
    "*.pt",
    "*.bin",
    "*.safetensors",
    "*.parquet",
]


class _Strict(BaseModel):
    """Base with extra=forbid so typos surface as ValidationError."""

    model_config = ConfigDict(extra="forbid")


class Defaults(_Strict):
    code_root: str
    remote_base: str
    sync_mode: Literal["one-way-replica", "one-way-safe", "two-way-resolved", "two-way-safe"] = (
        "one-way-replica"
    )
    ignore_vcs: bool = True
    ignore: list[str] = Field(default_factory=lambda: list(DEFAULT_IGNORE))
    ssh_after_start: bool = True


class ServerConfig(_Strict):
    host: str
    remote_base: str | None = None  # if None, falls back to defaults.remote_base


class GlobalConfig(_Strict):
    defaults: Defaults
    servers: dict[str, ServerConfig]


class RepoConfig(_Strict):
    """Per-repo overrides (~/<repo>/.devsync.toml). Every field is optional."""

    default_server: str | None = None
    remote_path: str | None = None  # absolute path; overrides <remote_base>/<repo_name>
    ignore: list[str] = Field(default_factory=list)  # additive to defaults.ignore
    symlink_mode: Literal["ignore", "portable", "posix-raw"] | None = None


GLOBAL_CONFIG_PATH = Path.home() / ".config" / "devsync" / "config.toml"


def load_global_config(path: Path = GLOBAL_CONFIG_PATH) -> GlobalConfig:
    """Load and validate the global config file."""
    try:
        with path.open("rb") as f:
            data = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise DevsyncError(f"Invalid TOML in {path}: {e}") from e
    return GlobalConfig(**data)


def load_repo_config(repo_dir: Path) -> RepoConfig:
    """Load <repo>/.devsync.toml if present; else return all-defaults RepoConfig."""
    p = repo_dir / ".devsync.toml"
    if not p.exists():
        return RepoConfig()
    try:
        with p.open("rb") as f:
            data = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise DevsyncError(f"Invalid TOML in {p}: {e}") from e
    return RepoConfig(**data)


class EffectiveConfig(_Strict):
    """Final flattened config used by `mutagen sync create`.

    Produced by merging Defaults + ServerConfig + RepoConfig + CLI flags.
    """

    host: str
    remote_path: str
    sync_mode: str
    ignore_vcs: bool
    ignore: list[str]
    symlink_mode: str = "portable"
    ssh_after_start: bool


def resolve_effective_config(
    *,
    global_cfg: GlobalConfig,
    repo_cfg: RepoConfig,
    repo_name: str,
    server_name: str,
) -> EffectiveConfig:
    """Merge layers in spec-defined precedence (highest->lowest):
    repo_cfg > server overrides > defaults.

    CLI flag overrides should be applied to the returned object by the caller.
    """
    from devsync.errors import NoSuchServer

    defaults = global_cfg.defaults
    server = global_cfg.servers.get(server_name)
    if server is None:
        raise NoSuchServer(server_name, list(global_cfg.servers.keys()))

    # remote_path precedence
    if repo_cfg.remote_path:
        remote_path = repo_cfg.remote_path
    else:
        base = server.remote_base or defaults.remote_base
        remote_path = f"{base.rstrip('/')}/{repo_name}"

    # ignore is additive
    ignore = list(defaults.ignore) + list(repo_cfg.ignore)

    return EffectiveConfig(
        host=server.host,
        remote_path=remote_path,
        sync_mode=defaults.sync_mode,
        ignore_vcs=defaults.ignore_vcs,
        ignore=ignore,
        symlink_mode=repo_cfg.symlink_mode or "portable",
        ssh_after_start=defaults.ssh_after_start,
    )
