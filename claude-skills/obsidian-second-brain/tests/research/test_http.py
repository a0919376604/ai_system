# tests/research/test_http.py
import responses
from scripts.research.lib.http import get_session, polite_user_agent


def test_polite_user_agent_includes_contact():
    ua = polite_user_agent("test-client/1.0", contact_email="me@example.com")
    assert "test-client/1.0" in ua
    assert "mailto:me@example.com" in ua


def test_polite_user_agent_without_contact():
    ua = polite_user_agent("test-client/1.0", contact_email=None)
    assert ua == "test-client/1.0"


@responses.activate
def test_session_retries_on_5xx():
    responses.add(responses.GET, "https://api.example.com/x", status=503)
    responses.add(responses.GET, "https://api.example.com/x", status=503)
    responses.add(responses.GET, "https://api.example.com/x", json={"ok": True}, status=200)

    sess = get_session(retries=3, backoff=0.0)
    r = sess.get("https://api.example.com/x", timeout=5)
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    assert len(responses.calls) == 3


@responses.activate
def test_session_gives_up_after_retries():
    for _ in range(4):
        responses.add(responses.GET, "https://api.example.com/x", status=503)

    sess = get_session(retries=3, backoff=0.0)
    r = sess.get("https://api.example.com/x", timeout=5)
    assert r.status_code == 503
