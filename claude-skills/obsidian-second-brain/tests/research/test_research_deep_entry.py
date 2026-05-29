import json
from unittest.mock import patch

from scripts.research import research_deep
from scripts.research.lib.result import Result


def _stub(name, items):
    cls = type(f"_Stub{name}", (), {})
    inst = cls()
    inst.name = name
    inst.search = lambda q, n=10, _items=items: _items
    return inst


def test_research_deep_aggregates_multiple_queries(capsys):
    items = [Result(source="hackernews", title="t", url="https://x")]
    with patch.object(
        research_deep, "_default_sources", return_value=[_stub("hackernews", items)]
    ):
        rc = research_deep.main(["research_deep", "q1", "q2", "q3"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["sub_queries"] == ["q1", "q2", "q3"]
    assert len(payload["per_query"]) == 3
