import json
from unittest.mock import patch, MagicMock
from scripts.research import thread_read


def test_thread_read_hn_dispatch(capsys):
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.json.return_value = {"id": 12345, "title": "OP"}
    fake_session = MagicMock()
    fake_session.get.return_value = fake_response

    with patch.object(thread_read.http, "get_session", return_value=fake_session):
        rc = thread_read.main(["thread_read", "https://news.ycombinator.com/item?id=12345"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["host"] == "hackernews"
    assert payload["data"]["id"] == 12345


def test_thread_read_reddit_dispatch(capsys):
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.json.return_value = [{"data": {"children": []}}]
    fake_session = MagicMock()
    fake_session.get.return_value = fake_response

    with patch.object(thread_read.http, "get_session", return_value=fake_session):
        rc = thread_read.main(["thread_read", "https://www.reddit.com/r/python/comments/abc"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["host"] == "reddit"


def test_thread_read_unknown_host_returns_2():
    rc = thread_read.main(["thread_read", "https://example.com/post"])
    assert rc == 2
