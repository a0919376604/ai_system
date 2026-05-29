import json
from unittest.mock import patch

from scripts.research import research as research_entry
from scripts.research.lib.result import Result


def _stub(name, items):
    cls = type(f"_Stub{name}", (), {})
    inst = cls()
    inst.name = name
    inst.search = lambda q, n=10, _items=items: _items
    return inst


def test_research_entry_emits_json_to_stdout(capsys):
    fake_results = [Result(source="hackernews", title="t", url="https://x")]
    with patch.object(
        research_entry,
        "_default_sources",
        return_value=[_stub("hackernews", fake_results), _stub("arxiv", [])],
    ):
        rc = research_entry.main(["research", "claude code"])
    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert payload["topic"] == "claude code"
    assert payload["stats"]["sources_attempted"] == 2
    assert any(r["title"] == "t" for r in payload["results"])


def test_research_academic_flag_uses_academic_sources(capsys):
    with patch.object(
        research_entry, "_academic_sources", return_value=[_stub("arxiv", [])]
    ) as ms:
        research_entry.main(["research", "deep learning", "--academic"])
    ms.assert_called_once()
