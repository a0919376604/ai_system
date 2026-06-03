import json
from unittest.mock import Mock

import pytest

from devsync.mutagen import list_managed_sessions

_FAKE_OUTPUT = json.dumps(
    [
        {
            "identifier": "abc123",
            "name": "ai-eden-service--dl02",
            "labels": {
                "managed-by": "devsync",
                "repo": "ai-eden-service",
                "server": "dl02",
                "worktree": "none",
                "created-at": "2026-06-02T10:00:00Z",
            },
            "alpha": {"url": {"path": "/Users/leric/Desktop/code/ai-eden-service"}},
            "beta": {"url": {"host": "dl02", "path": "/home/leric/code/ai-eden-service"}},
            "status": "Watching for changes",
            "stagedFiles": 0,
        }
    ]
).encode()


def test_list_managed_sessions_parses(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=0, stdout=_FAKE_OUTPUT, stderr=b""),
    )
    sessions = list_managed_sessions()
    assert len(sessions) == 1
    s = sessions[0]
    assert s["name"] == "ai-eden-service--dl02"
    assert s["labels"]["server"] == "dl02"


def test_list_managed_sessions_empty(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=0, stdout=b"[]\n", stderr=b""),
    )
    assert list_managed_sessions() == []


def test_list_managed_sessions_uses_label_selector(mocker):
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return Mock(returncode=0, stdout=b"[]", stderr=b"")

    mocker.patch("subprocess.run", side_effect=fake_run)
    list_managed_sessions()
    assert "--label-selector=managed-by=devsync" in captured["cmd"]


def test_list_managed_sessions_malformed_json_raises(mocker):
    mocker.patch(
        "subprocess.run",
        return_value=Mock(returncode=0, stdout=b"not json", stderr=b""),
    )
    with pytest.raises(RuntimeError, match="parse"):
        list_managed_sessions()
