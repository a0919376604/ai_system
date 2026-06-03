from unittest.mock import Mock

import pytest

from devsync.errors import ServerUnreachable
from devsync.server import probe_ssh


def test_probe_ssh_succeeds_when_ssh_returns_zero(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=0, stdout=b"hostname-dl02\n", stderr=b""),
    )
    # Should return without raising
    probe_ssh("dl02", "dl02")


def test_probe_ssh_raises_unreachable_on_nonzero(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=255, stdout=b"", stderr=b"Connection refused"),
    )
    with pytest.raises(ServerUnreachable) as exc:
        probe_ssh("dl02", "192.168.90.32")
    assert "dl02" in str(exc.value)
    assert "192.168.90.32" in str(exc.value)


def test_probe_ssh_uses_batchmode_and_timeout(mocker):
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return Mock(returncode=0, stdout=b"", stderr=b"")

    mocker.patch("subprocess.run", side_effect=fake_run)
    probe_ssh("dl01", "dl01")
    cmd = captured["cmd"]
    assert "-o" in cmd
    assert "BatchMode=yes" in cmd
    assert any("ConnectTimeout" in arg for arg in cmd)
