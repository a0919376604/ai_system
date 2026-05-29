"""Detect AI memory architecture signals per AI flow.

Pure function. Given a repo root and list of AIFlow records, returns a
dict shaped per the v4.3 spec: per-flow signals + cross-flow summary.

Categories of signal detected:
- Backend: redis / postgres / sqlite / in-memory / file / langchain
- Checkpointer classes (LangGraph Saver subclasses + custom impls)
- Key patterns (string literals near checkpointer construction)
- Reducer funcs + extracted caps (e.g. `result[-N:]`)
- Compaction funcs (summarize / compact / memory_update)

Used by Phase 1 scanner to feed scan_report["ai_memory"]; downstream
LLM synthesis in Phase 3.8 turns this into Architecture/ai-flows/memory.md.
"""
from __future__ import annotations

import re
from pathlib import Path

# ---------- regex patterns ----------

# `from langgraph.checkpoint.X import ...` — captures X.
_LANGGRAPH_CHECKPOINT_RE = re.compile(
    r"from\s+langgraph\.checkpoint\.(?P<backend>\w+)\s+import"
)
# `from langchain.memory import ...`.
_LANGCHAIN_MEMORY_RE = re.compile(
    r"from\s+langchain\.memory\s+import\s+\w+"
)
# `class FooSaver:` or `class FooSaver(BaseSaver):` — captures class name when name ends with "Saver".
_CUSTOM_SAVER_CLASS_RE = re.compile(
    r"class\s+(?P<name>\w*Saver)\b"
)
# `key_prefix=` followed by string literal — captures pattern.
_KEY_PREFIX_RE = re.compile(
    r"key_prefix\s*=\s*['\"](?P<pattern>[^'\"]+)['\"]"
)
# Reducer function defs: spec pattern — `add_messages*` OR `*_reducer`. Tight on
# purpose to avoid matching unrelated functions whose names contain "messages".
_REDUCER_DEF_RE = re.compile(
    r"def\s+(?P<name>add_messages\w*|\w+_reducer)\s*\("
)
# Reducer cap extraction: `result[-N:]` (trailing slice = "keep last N").
_REDUCER_CAP_RE = re.compile(
    r"\w+\s*\[\s*-(?P<n>\d+)\s*:\s*\]"
)
# Compaction function defs: name contains summarize/summarise/compact/memory_update.
_COMPACTION_FUNC_RE = re.compile(
    r"def\s+(?P<name>\w*(?:summari[sz]e|compact|memory_update)\w*)\s*\("
)

_BACKEND_HINTS = {
    "memory": "in-memory",
    "redis": "redis",
    "postgres": "postgres",
    "sqlite": "sqlite",
    "duckdb": "duckdb",
}

# langgraph.checkpoint.<sub> module names that are NOT backends (abstract base
# classes, serializers, etc). Filtered out so they don't pollute `backends`.
_LANGGRAPH_CHECKPOINT_NON_BACKEND = {"base", "serde", "__init__", "abc"}


def detect_memory(repo_root: Path, ai_flows: list) -> dict:
    """Walk each AI flow's root_path; aggregate per-flow + summary memory signals.

    `ai_flows` is a list of objects with `slug: str` and `root_path: str` attrs
    (matches the v4.1 `AIFlow` dataclass; tests use a lightweight shim).
    """
    repo_root = repo_root.resolve()
    per_flow: dict[str, dict] = {}

    for flow in ai_flows:
        flow_dir = repo_root / flow.root_path
        if not flow_dir.is_dir():
            per_flow[flow.slug] = _empty_flow_record()
            continue
        per_flow[flow.slug] = _scan_flow(flow_dir, repo_root)

    memory_flows = sum(1 for v in per_flow.values() if v["has_memory"])
    stateless_flows = len(per_flow) - memory_flows
    all_backends: set[str] = set()
    for v in per_flow.values():
        all_backends.update(v["backends"])

    if not all_backends:
        primary = "none"
        uniform = True
    elif len(all_backends) == 1:
        primary = next(iter(all_backends))
        uniform = True
    else:
        primary = "mixed"
        uniform = False

    return {
        "per_flow": per_flow,
        "summary": {
            "memory_flows": memory_flows,
            "stateless_flows": stateless_flows,
            "primary_backend": primary,
            "uniform_backend": uniform,
        },
    }


def _empty_flow_record() -> dict:
    return {
        "has_memory": False,
        "backends": [],
        "checkpointer_classes": [],
        "checkpointer_sources": [],
        "key_patterns": [],
        "reducer_funcs": [],
        "reducer_caps": [],
        "compaction_funcs": [],
        "compaction_sources": [],
    }


def _scan_flow(flow_dir: Path, repo_root: Path) -> dict:
    backends: set[str] = set()
    checkpointer_classes: list[str] = []
    checkpointer_sources: list[str] = []
    key_patterns: list[str] = []
    reducer_funcs: list[str] = []
    reducer_caps: list[dict] = []
    compaction_funcs: list[str] = []
    compaction_sources: list[str] = []

    for py_file in flow_dir.rglob("*.py"):
        try:
            text = py_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = py_file.relative_to(repo_root).as_posix()

        for m in _LANGGRAPH_CHECKPOINT_RE.finditer(text):
            sub = m.group("backend")
            if sub in _LANGGRAPH_CHECKPOINT_NON_BACKEND:
                continue
            backend_label = _BACKEND_HINTS.get(sub, sub)
            backends.add(backend_label)
        if _LANGCHAIN_MEMORY_RE.search(text):
            backends.add("langchain")
        for m in _CUSTOM_SAVER_CLASS_RE.finditer(text):
            name = m.group("name")
            if name in checkpointer_classes:
                continue
            checkpointer_classes.append(name)
            checkpointer_sources.append(rel)
            lname = name.lower()
            if "redis" in lname:
                backends.add("redis")
            elif "postgres" in lname or "pg" in lname:
                backends.add("postgres")
            elif "sqlite" in lname:
                backends.add("sqlite")
            elif "file" in lname or "disk" in lname:
                backends.add("file")
        for m in _KEY_PREFIX_RE.finditer(text):
            pat = m.group("pattern")
            if pat not in key_patterns:
                key_patterns.append(pat)
        for m in _REDUCER_DEF_RE.finditer(text):
            name = m.group("name")
            if name in reducer_funcs:
                continue
            reducer_funcs.append(name)
            # Look ahead in same module for a `result[-N:]` cap pattern.
            tail = text[m.end():]
            cap_m = _REDUCER_CAP_RE.search(tail[:2000])
            if cap_m:
                reducer_caps.append({
                    "name": name,
                    "limit": int(cap_m.group("n")),
                    "source": rel,
                })
        for m in _COMPACTION_FUNC_RE.finditer(text):
            name = m.group("name")
            if name in compaction_funcs:
                continue
            compaction_funcs.append(name)
            compaction_sources.append(rel)

    has_memory = bool(backends or checkpointer_classes or compaction_funcs)
    return {
        "has_memory": has_memory,
        "backends": sorted(backends),
        "checkpointer_classes": checkpointer_classes,
        "checkpointer_sources": checkpointer_sources,
        "key_patterns": key_patterns,
        "reducer_funcs": reducer_funcs,
        "reducer_caps": reducer_caps,
        "compaction_funcs": compaction_funcs,
        "compaction_sources": compaction_sources,
    }
