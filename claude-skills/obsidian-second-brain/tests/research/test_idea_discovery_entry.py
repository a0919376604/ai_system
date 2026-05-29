import json
from unittest.mock import patch
from scripts.research import idea_discovery


def test_idea_discovery_runs(capsys):
    with patch.object(idea_discovery, "ArxivSource") as _a, \
         patch.object(idea_discovery, "HackerNewsSource") as _h:
        for cls in (_a, _h):
            cls.return_value.name = "stub"
            cls.return_value.search = lambda *args, **kw: []
        rc = idea_discovery.main(["idea_discovery", "gap1", "gap2"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["gaps"] == ["gap1", "gap2"]
    assert len(payload["per_gap"]) == 2
