from unittest.mock import Mock

import pytest

from devsync.mutagen import sync_terminate, sync_terminate_by_repo


def test_sync_terminate_by_name(mocker):
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return Mock(returncode=0, stdout=b"", stderr=b"")

    mocker.patch("subprocess.run", side_effect=fake_run)
    sync_terminate("ai-eden-service--dl02")
    assert captured["cmd"] == ["mutagen", "sync", "terminate", "ai-eden-service--dl02"]


def test_sync_terminate_by_repo_uses_selector(mocker):
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return Mock(returncode=0, stdout=b"", stderr=b"")

    mocker.patch("subprocess.run", side_effect=fake_run)
    sync_terminate_by_repo("ai-eden-service")
    cmd = captured["cmd"]
    assert "--label-selector=managed-by=devsync,repo=ai-eden-service" in cmd


def test_sync_terminate_failure_raises(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=1, stdout=b"", stderr=b"no such session"),
    )
    with pytest.raises(RuntimeError, match="terminate"):
        sync_terminate("ghost")
