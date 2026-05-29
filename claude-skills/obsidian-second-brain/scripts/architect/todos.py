"""Aggregate TODO / FIXME comments across the repo, grouped by module.

Each TODO is parsed for an optional label (e.g. `TODO(future): foo`) and the
free-text body. Output is suitable for roadmap.md and future.md synthesis.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_TEXT_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs", ".rb", ".java",
    ".kt", ".swift", ".c", ".cc", ".cpp", ".h", ".hpp", ".cs", ".php",
    ".sh", ".bash", ".zsh", ".lua", ".sql", ".md", ".yaml", ".yml", ".toml",
}
_MAX_FILE_BYTES = 512 * 1024

_TODO_RE = re.compile(
    r"(?P<kind>TODO|FIXME|XXX|HACK)"
    r"(?:\((?P<label>[a-zA-Z_-]+)\))?"
    r"\s*[:\-]?\s*"
    r"(?P<text>.+?)$",
    re.IGNORECASE | re.MULTILINE,
)


@dataclass
class TodoItem:
    path: str         # repo-relative
    line: int
    kind: str         # TODO / FIXME / XXX / HACK
    label: str | None  # roadmap / future / idea / etc., or None
    text: str


def aggregate_todos(repo_root: Path, module_paths: dict[str, list[str]]) -> dict[str, list[TodoItem]]:
    """Walk the repo and group TODO items by module slug.

    Args:
        repo_root: absolute path to repo.
        module_paths: {module_slug: [repo-relative paths]} from manifest.

    Returns: {module_slug: [TodoItem]}.  Files not under any module land in
    the special bucket "_unmapped".
    """
    repo_root = repo_root.resolve()
    by_module: dict[str, list[TodoItem]] = {slug: [] for slug in module_paths}
    by_module["_unmapped"] = []
    for file in _iter_text_files(repo_root):
        rel = file.relative_to(repo_root).as_posix()
        slug = _which_module(rel, module_paths)
        try:
            text = file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for m in _TODO_RE.finditer(text):
            line_no = text[: m.start()].count("\n") + 1
            by_module[slug].append(
                TodoItem(
                    path=rel,
                    line=line_no,
                    kind=m.group("kind").upper(),
                    label=(m.group("label") or "").lower() or None,
                    text=m.group("text").strip(),
                )
            )
    # Drop empty buckets.
    return {k: v for k, v in by_module.items() if v}


def _iter_text_files(repo_root: Path):
    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        if ".git" in p.parts or "node_modules" in p.parts or ".venv" in p.parts:
            continue
        if p.suffix.lower() not in _TEXT_EXTENSIONS:
            continue
        try:
            if p.stat().st_size > _MAX_FILE_BYTES:
                continue
        except OSError:
            continue
        yield p


def _which_module(rel_path: str, module_paths: dict[str, list[str]]) -> str:
    for slug, paths in module_paths.items():
        for prefix in paths:
            if rel_path == prefix or rel_path.startswith(prefix.rstrip("/") + "/"):
                return slug
    return "_unmapped"
