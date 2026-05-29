import pytest

from scripts.roadmap.parser import (
    ReviewAction,
    parse_review_response,
    ParseError,
)


def test_parses_keep_all_default():
    """A row with empty action column defaults to K (keep)."""
    paste = """\
| # | Action | 主題 | Priority | Effort | Evidence | Tasks |
|---|---|---|---|---|---|---|
| 1 |  | AI 引擎可插拔化 | 🔴 | M | 2 | 4 |
| 2 |  | 觀測性補強 | 🟡 | M | 3 | 3 |
"""
    actions = parse_review_response(paste, n_themes=2)
    assert actions == [ReviewAction(idx=1, kind="K"), ReviewAction(idx=2, kind="K")]


def test_parses_explicit_kdme():
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | K | A |
| 2 | D | B |
| 3 | M:1 | C |
| 4 | E | D |
"""
    actions = parse_review_response(paste, n_themes=4)
    assert actions[0].kind == "K"
    assert actions[1].kind == "D"
    assert actions[2].kind == "M"
    assert actions[2].merge_target == 1
    assert actions[3].kind == "E"


def test_dropped_rows_dont_appear():
    """User physically deleted row 3 from the paste -> treated as D."""
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | K | A |
| 2 | K | B |
"""
    actions = parse_review_response(paste, n_themes=3)
    assert {a.idx for a in actions if a.kind == "K"} == {1, 2}
    assert any(a.idx == 3 and a.kind == "D" for a in actions)


def test_merge_target_must_exist():
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | M:99 | A |
"""
    with pytest.raises(ParseError, match="merge target 99 not in 1..1"):
        parse_review_response(paste, n_themes=1)


def test_invalid_action_value_raises():
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | XYZ | A |
"""
    with pytest.raises(ParseError, match="row 1.*invalid action 'XYZ'"):
        parse_review_response(paste, n_themes=1)
