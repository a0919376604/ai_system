"""Extract prompt strings from an AI flow root.

Returns ExtractedPrompt records with full body text (for static templates) or
"dynamic" placeholder (when the prompt is assembled programmatically). Each
record carries a source-hash used by the lockfile to detect drift on re-scan.

Extractors run in priority order:
1. toml / yaml / json `prompts.<ext>` config files
2. Python module-level UPPER_CASE constants assigned triple-quoted strings
3. SYSTEM_PROMPT / USER_PROMPT / TEMPLATE_ prefixed constants
4. LangChain ChatPromptTemplate.from_messages([...]) message contents

Dynamic prompts (assembled at runtime via string concat / multi-source build):
We deliberately do NOT trace them and synthesize a "stitched" body — that would
be misleading because the actual runtime content depends on inputs. Instead,
the ai-flow LLM prompt (in sections.py `build_ai_flow_prompt`) is instructed
to look at the source files directly and write a description block, flagging
`Type: dynamic` in the rendered Prompts section.
"""

from __future__ import annotations

import ast
import hashlib
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

_EXCLUDED_DIRS = {
    ".git",
    "node_modules",
    ".venv",
    "venv",
    "dist",
    "build",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    ".mypy_cache",
    ".claude",
    "worktrees",
    "_archive",
}


@dataclass
class ExtractedPrompt:
    name: str
    source: str  # repo-relative `path:line-start-line-end`
    body: str  # full text (static) or description (dynamic)
    is_dynamic: bool
    source_hash: str  # "sha256:<hex>" of `body`
    model_hint: str | None = None
    extraction_method: str = ""  # toml-config | yaml-config | json-config |
    # module-constant | system-prompt-pattern |
    # langchain-chat-prompt-template | dynamic-trace
    extraction_notes: list[str] = field(default_factory=list)


def extract_prompts(flow_root: Path) -> list[ExtractedPrompt]:
    """Run all extractors over a flow root; return deduplicated ExtractedPrompt list."""
    flow_root = flow_root.resolve()
    out: list[ExtractedPrompt] = []
    seen_names: set[str] = set()

    # 1. TOML / YAML / JSON config files
    for ext, extractor in (
        ("toml", _extract_toml),
        ("yaml", _extract_yaml),
        ("yml", _extract_yaml),
        ("json", _extract_json),
    ):
        for cfg in flow_root.rglob(f"prompts.{ext}"):
            if _EXCLUDED_DIRS.intersection(cfg.parts):
                continue
            try:
                items = extractor(cfg, flow_root)
            except Exception:
                items = []
            for item in items:
                if item.name in seen_names:
                    continue
                seen_names.add(item.name)
                out.append(item)

    # 2-3-4. Python files
    for py in flow_root.rglob("*.py"):
        if _EXCLUDED_DIRS.intersection(py.parts) or py.name == "__init__.py":
            continue
        for item in _extract_python(py, flow_root):
            if item.name in seen_names:
                continue
            seen_names.add(item.name)
            out.append(item)
    return out


# ---------- TOML / YAML / JSON ----------

def _hash(body: str) -> str:
    return "sha256:" + hashlib.sha256(body.encode("utf-8")).hexdigest()


def _rel_source(path: Path, flow_root: Path) -> str:
    try:
        return path.relative_to(flow_root).as_posix()
    except ValueError:
        return path.as_posix()


def _extract_toml(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    out: list[ExtractedPrompt] = []
    rel = _rel_source(path, flow_root)
    for name, value in data.items():
        body = _coerce_prompt_value(value)
        if body is None:
            continue
        out.append(ExtractedPrompt(
            name=name,
            source=f"{rel}:1",
            body=body,
            is_dynamic=False,
            source_hash=_hash(body),
            extraction_method="toml-config",
        ))
    return out


def _extract_yaml(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    try:
        import yaml
    except ImportError:
        return []
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    rel = _rel_source(path, flow_root)
    out: list[ExtractedPrompt] = []
    if isinstance(data, dict):
        for name, value in data.items():
            body = _coerce_prompt_value(value)
            if body is None:
                continue
            out.append(ExtractedPrompt(
                name=name, source=f"{rel}:1", body=body, is_dynamic=False,
                source_hash=_hash(body), extraction_method="yaml-config",
            ))
    return out


def _extract_json(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    import json
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    rel = _rel_source(path, flow_root)
    out: list[ExtractedPrompt] = []
    if isinstance(data, dict):
        for name, value in data.items():
            body = _coerce_prompt_value(value)
            if body is None:
                continue
            out.append(ExtractedPrompt(
                name=name, source=f"{rel}:1", body=body, is_dynamic=False,
                source_hash=_hash(body), extraction_method="json-config",
            ))
    return out


def _coerce_prompt_value(value) -> str | None:
    """Config value → prompt body string.  Accepts {template: "..."}, "...", or skips."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if "template" in value and isinstance(value["template"], str):
            return value["template"]
        if "prompt" in value and isinstance(value["prompt"], str):
            return value["prompt"]
        if "text" in value and isinstance(value["text"], str):
            return value["text"]
    return None


# ---------- Python AST extractors ----------

_PROMPT_NAME_RE = re.compile(
    r"^(.*_PROMPT|.*PROMPT_.*|.*_TEMPLATE|TEMPLATE_.*|CHAT_PROMPT|.*_INSTRUCTIONS)$"
)


def _extract_python(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    src = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    rel = _rel_source(path, flow_root)
    out: list[ExtractedPrompt] = []

    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if not isinstance(target, ast.Name):
            continue
        name = target.id

        # Module-level constant pattern: NAME = "..." or NAME = """..."""
        if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            if _looks_like_prompt_name(name) or _looks_like_prompt_body(node.value.value):
                body = node.value.value
                out.append(ExtractedPrompt(
                    name=name,
                    source=f"{rel}:{node.lineno}-{node.end_lineno or node.lineno}",
                    body=body,
                    is_dynamic=False,
                    source_hash=_hash(body),
                    extraction_method=(
                        "module-constant"
                        if _looks_like_prompt_name(name)
                        else "system-prompt-pattern"
                    ),
                ))
            continue

        # LangChain ChatPromptTemplate.from_messages([...])
        lc_body = _try_extract_langchain_chat_prompt(node.value)
        if lc_body is not None:
            out.append(ExtractedPrompt(
                name=name,
                source=f"{rel}:{node.lineno}-{node.end_lineno or node.lineno}",
                body=lc_body,
                is_dynamic=False,
                source_hash=_hash(lc_body),
                extraction_method="langchain-chat-prompt-template",
            ))
    return out


def _looks_like_prompt_name(name: str) -> bool:
    """Is this constant name prompt-shaped?"""
    if not name.isupper():
        return False
    return bool(_PROMPT_NAME_RE.match(name))


def _looks_like_prompt_body(body: str) -> bool:
    """Is this string content prompt-shaped? (long-ish, multi-line, or contains format vars)"""
    if len(body) < 30:
        return False
    if "{" in body and "}" in body:  # f-string-style placeholder
        return True
    if "\n" in body and len(body) > 80:
        return True
    return False


def _try_extract_langchain_chat_prompt(value_node: ast.expr) -> str | None:
    """Look for ChatPromptTemplate.from_messages([...]) and concat SystemMessage/HumanMessage contents."""
    if not isinstance(value_node, ast.Call):
        return None
    func = value_node.func
    # ChatPromptTemplate.from_messages
    if not (isinstance(func, ast.Attribute) and func.attr == "from_messages"):
        return None
    obj = func.value
    obj_name = obj.id if isinstance(obj, ast.Name) else (
        obj.attr if isinstance(obj, ast.Attribute) else ""
    )
    if "ChatPromptTemplate" not in obj_name:
        return None
    if not value_node.args:
        return None
    messages_arg = value_node.args[0]
    if not isinstance(messages_arg, ast.List):
        return None
    parts: list[str] = []
    for elt in messages_arg.elts:
        if not isinstance(elt, ast.Call):
            continue
        cls = elt.func.id if isinstance(elt.func, ast.Name) else (
            elt.func.attr if isinstance(elt.func, ast.Attribute) else ""
        )
        # Extract `content="..."` kwarg
        for kw in elt.keywords:
            if kw.arg == "content" and isinstance(kw.value, ast.Constant) and isinstance(
                kw.value.value, str
            ):
                parts.append(f"[{cls}]\n{kw.value.value}")
    if not parts:
        return None
    return "\n\n".join(parts)
