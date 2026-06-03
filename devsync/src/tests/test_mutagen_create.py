from pathlib import Path
from unittest.mock import Mock

import pytest

from devsync.config import EffectiveConfig
from devsync.errors import SessionAlreadyExists
from devsync.mutagen import build_create_argv, sync_create
from devsync.repo import RepoSpec
from devsync.session import SessionSpec


def _spec(tmp_path: Path) -> SessionSpec:
    (tmp_path / "alpha-repo").mkdir()
    return SessionSpec(repo=RepoSpec.from_path(tmp_path / "alpha-repo"), server_name="dl02")


def _cfg() -> EffectiveConfig:
    return EffectiveConfig(
        host="dl02",
        remote_path="/home/leric/code/alpha-repo",
        sync_mode="one-way-replica",
        ignore_vcs=True,
        ignore=["*.pyc", "*.ckpt"],
        symlink_mode="portable",
        ssh_after_start=True,
    )


def test_build_create_argv_has_session_name(tmp_path):
    argv = build_create_argv(_spec(tmp_path), _cfg())
    assert "--name=alpha-repo--dl02" in argv


def test_build_create_argv_includes_labels(tmp_path):
    argv = build_create_argv(_spec(tmp_path), _cfg())
    # Each label is passed as `--label k=v`
    joined = " ".join(argv)
    assert "managed-by=devsync" in joined
    assert "repo=alpha-repo" in joined
    assert "server=dl02" in joined


def test_build_create_argv_endpoints(tmp_path):
    argv = build_create_argv(_spec(tmp_path), _cfg())
    # Last 2 positional args are alpha (local abs path) and beta (host:remote)
    assert argv[-2] == str((tmp_path / "alpha-repo").resolve())
    assert argv[-1] == "dl02:/home/leric/code/alpha-repo"


def test_build_create_argv_each_ignore_pattern(tmp_path):
    argv = build_create_argv(_spec(tmp_path), _cfg())
    assert "--ignore=*.pyc" in argv
    assert "--ignore=*.ckpt" in argv


def test_sync_create_raises_session_already_exists(mocker, tmp_path):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(
            returncode=1,
            stdout=b"",
            stderr=b"unable to create session: session with name 'alpha-repo--dl02' already exists",
        ),
    )
    with pytest.raises(SessionAlreadyExists):
        sync_create(_spec(tmp_path), _cfg())
