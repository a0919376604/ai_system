# tests/research/test_result.py
import json
from scripts.research.lib.result import Result, encode_results


def test_result_round_trips_through_json():
    r = Result(
        source="arxiv",
        title="A paper",
        url="https://arxiv.org/abs/2305.06564",
        abstract="An abstract.",
        authors=["Alice", "Bob"],
        year=2023,
    )
    out = json.dumps([r], default=encode_results)
    parsed = json.loads(out)
    assert parsed[0]["source"] == "arxiv"
    assert parsed[0]["title"] == "A paper"
    assert parsed[0]["authors"] == ["Alice", "Bob"]
    assert parsed[0]["snippet"] is None  # unset fields default to None


def test_result_partial_fields_only():
    """Web results don't have abstract/authors — those stay None."""
    r = Result(
        source="duckduckgo",
        title="Page",
        url="https://example.com",
        snippet="Some snippet.",
    )
    out = json.loads(json.dumps([r], default=encode_results))
    assert out[0]["abstract"] is None
    assert out[0]["authors"] is None
    assert out[0]["snippet"] == "Some snippet."
