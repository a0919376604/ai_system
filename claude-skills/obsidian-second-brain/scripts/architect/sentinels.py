"""Parse and render @generated / @user sentinel blocks in note bodies.

Sentinels:
    <!-- @generated:start <name> -->
    ...body...
    <!-- @generated:end <name> -->

    <!-- @user:start <name> -->
    ...body...
    <!-- @user:end <name> -->

Generated blocks are LLM territory: refresh overwrites the body.
User blocks are never touched.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass
class GeneratedBlock:
    name: str
    body: str


@dataclass
class UserBlock:
    name: str
    body: str


@dataclass
class PlainText:
    body: str


_GEN_RE = re.compile(
    r"<!--\s*@generated:start\s+(?P<name>[\w-]+)\s*-->\n"
    r"(?P<body>.*?)\n"
    r"<!--\s*@generated:end\s+(?P=name)\s*-->",
    re.DOTALL,
)

_USER_RE = re.compile(
    r"<!--\s*@user:start\s+(?P<name>[\w-]+)\s*-->\n"
    r"(?P<body>.*?)\n"
    r"<!--\s*@user:end\s+(?P=name)\s*-->",
    re.DOTALL,
)


def parse_blocks(text: str) -> list:
    """Return ordered list of GeneratedBlock | UserBlock | PlainText spanning the text."""
    # Combine both regexes into one pass with named alternation.
    spans: list[tuple[int, int, object]] = []
    for m in _GEN_RE.finditer(text):
        spans.append((m.start(), m.end(), GeneratedBlock(name=m.group("name"), body=m.group("body"))))
    for m in _USER_RE.finditer(text):
        spans.append((m.start(), m.end(), UserBlock(name=m.group("name"), body=m.group("body"))))
    spans.sort(key=lambda s: s[0])

    out: list = []
    cursor = 0
    for start, end, block in spans:
        if start > cursor:
            plain = text[cursor:start]
            if plain.strip():
                out.append(PlainText(body=plain))
        out.append(block)
        cursor = end
    tail = text[cursor:]
    if tail.strip():
        out.append(PlainText(body=tail))
    return out


def render_block(block) -> str:
    """Render a block back to markdown text (round-trip)."""
    if isinstance(block, GeneratedBlock):
        return (
            f"<!-- @generated:start {block.name} -->\n"
            f"{block.body}\n"
            f"<!-- @generated:end {block.name} -->"
        )
    if isinstance(block, UserBlock):
        return (
            f"<!-- @user:start {block.name} -->\n"
            f"{block.body}\n"
            f"<!-- @user:end {block.name} -->"
        )
    if isinstance(block, PlainText):
        return block.body
    raise TypeError(f"Unknown block type: {type(block)}")
