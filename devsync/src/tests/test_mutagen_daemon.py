from unittest.mock import Mock

import pytest

from devsync.errors import MutagenDaemonError
from devsync.mutagen import daemon_status, ensure_daemon_running


def test_daemon_status_running(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=0, stdout=b"Daemon Running\n", stderr=b""),
    )
    assert daemon_status() is True


def test_daemon_status_not_running(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=1, stdout=b"", stderr=b"daemon not running"),
    )
    assert daemon_status() is False


def test_ensure_daemon_running_starts_when_down(mocker):
    calls = []

    def fake_run(cmd, **kwargs):
        calls.append(cmd)
        if cmd[:3] == ["mutagen", "daemon", "status"]:
            # Down on first call, then up after start
            rc = 1 if len(calls) == 1 else 0
            return Mock(returncode=rc, stdout=b"", stderr=b"")
        if cmd[:3] == ["mutagen", "daemon", "start"]:
            return Mock(returncode=0, stdout=b"", stderr=b"")
        raise AssertionError(f"unexpected: {cmd}")

    mocker.patch("subprocess.run", side_effect=fake_run)
    ensure_daemon_running()
    assert ["mutagen", "daemon", "start"] in calls


def test_ensure_daemon_running_raises_if_start_fails(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=1, stdout=b"", stderr=b"failed"),
    )
    with pytest.raises(MutagenDaemonError):
        ensure_daemon_running()
