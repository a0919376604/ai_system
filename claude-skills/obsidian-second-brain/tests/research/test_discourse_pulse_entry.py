import json
from unittest.mock import patch
from scripts.research import discourse_pulse


def test_discourse_pulse_runs(capsys):
    with patch.object(discourse_pulse, "HackerNewsSource") as _a, \
         patch.object(discourse_pulse, "RedditSource") as _b, \
         patch.object(discourse_pulse, "LobstersSource") as _c, \
         patch.object(discourse_pulse, "DevToSource") as _d:
        for cls in (_a, _b, _c, _d):
            cls.return_value.name = "stub"
            cls.return_value.search = lambda *args, **kw: []
        rc = discourse_pulse.main(["discourse_pulse", "rust async"])
    assert rc in (0, 1)
    payload = json.loads(capsys.readouterr().out)
    assert payload["topic"] == "rust async"
