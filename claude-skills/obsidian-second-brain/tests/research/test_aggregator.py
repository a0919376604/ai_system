# tests/research/test_aggregator.py
from scripts.research.lib.aggregator import aggregate
from scripts.research.lib.result import Result


class _Stub:
    def __init__(self, name, results=None, raise_exc=None):
        self.name = name
        self._results = results or []
        self._raise = raise_exc

    def search(self, query, n=10):
        if self._raise:
            raise self._raise
        return self._results


def test_aggregator_collects_from_all_sources():
    a = _Stub("a", results=[Result(source="a", title="t1", url="https://a")])
    b = _Stub("b", results=[Result(source="b", title="t2", url="https://b")])
    out = aggregate("topic", [a, b])
    assert out["stats"]["sources_attempted"] == 2
    assert out["stats"]["sources_succeeded"] == 2
    assert out["stats"]["results_total"] == 2
    titles = {r["title"] for r in out["results"]}
    assert titles == {"t1", "t2"}


def test_aggregator_tolerates_exception_in_source():
    a = _Stub("a", results=[Result(source="a", title="t1", url="https://a")])
    b = _Stub("b", raise_exc=RuntimeError("boom"))
    out = aggregate("topic", [a, b])
    assert out["stats"]["sources_succeeded"] == 1
    assert "b" in out["warnings"][0]
    assert len(out["results"]) == 1


def test_aggregator_marks_success_when_three_succeed():
    sources = [
        _Stub("s1", results=[Result(source="s1", title="x", url="https://x")]),
        _Stub("s2", results=[Result(source="s2", title="x", url="https://x")]),
        _Stub("s3", results=[Result(source="s3", title="x", url="https://x")]),
        _Stub("s4", raise_exc=RuntimeError("dead")),
    ]
    out = aggregate("topic", sources)
    assert out["stats"]["success"] is True


def test_aggregator_marks_partial_when_under_three_succeed():
    sources = [
        _Stub("s1", results=[Result(source="s1", title="x", url="https://x")]),
        _Stub("s2", raise_exc=RuntimeError("dead")),
        _Stub("s3", raise_exc=RuntimeError("dead")),
    ]
    out = aggregate("topic", sources)
    assert out["stats"]["success"] is False
