"""Phase 4 — parse user's batch-review paste back into ReviewActions."""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass
class ReviewAction:
    idx: int                      # 1-indexed theme position from Phase 3 output
    kind: str                     # K | D | M | E
    merge_target: int | None = None   # for M:<n>
    edit_payload: str | None = None   # for E (free-form, parsed downstream)


class ParseError(ValueError):
    pass


_ROW_RE = re.compile(r"^\|\s*(\d+)\s*\|\s*([^|]*?)\s*\|", re.MULTILINE)
_MERGE_RE = re.compile(r"^M\s*:\s*(\d+)\s*$", re.IGNORECASE)


def parse_review_response(paste: str, n_themes: int) -> list[ReviewAction]:
    """Parse the markdown table the user pasted back.

    Rules:
    - A row's Action cell may be empty (defaults to K), or K/D/M:<n>/E.
    - Rows the user deleted from the paste are treated as D.
    - Returns ordered ReviewAction list covering ALL theme indices 1..n_themes.
    """
    seen: dict[int, ReviewAction] = {}
    for m in _ROW_RE.finditer(paste):
        idx = int(m.group(1))
        action_cell = m.group(2).strip()
        if idx < 1 or idx > n_themes:
            # Out-of-range row — ignore (user added junk?).
            continue
        seen[idx] = _parse_action(idx, action_cell, n_themes)

    # Missing rows = dropped.
    out: list[ReviewAction] = []
    for i in range(1, n_themes + 1):
        out.append(seen.get(i, ReviewAction(idx=i, kind="D")))
    return out


def _parse_action(idx: int, cell: str, n_themes: int) -> ReviewAction:
    if cell == "" or cell.upper() == "K":
        return ReviewAction(idx=idx, kind="K")
    if cell.upper() == "D":
        return ReviewAction(idx=idx, kind="D")
    m = _MERGE_RE.match(cell)
    if m:
        target = int(m.group(1))
        if target < 1 or target > n_themes:
            raise ParseError(f"row {idx}: merge target {target} not in 1..{n_themes}")
        if target == idx:
            raise ParseError(f"row {idx}: cannot merge into itself")
        return ReviewAction(idx=idx, kind="M", merge_target=target)
    if cell.upper().startswith("E"):
        # E or "E:<payload>"
        payload = cell[2:] if cell[1:2] == ":" else ""
        return ReviewAction(idx=idx, kind="E", edit_payload=payload.strip() or None)
    raise ParseError(f"row {idx}: invalid action {cell!r}")
