"""Detect AI flow subsystems (LangGraph / LangChain / custom-pipeline) in a repo.

A "flow" is more than a one-off LLM call — it has structured nodes (≥ 3), a graph or
pipeline file, and prompt sources. Returned AIFlow records feed `Architecture/ai-flows/`
note generation.

Detection runs over candidate root directories within the repo. Common locations:
- `<repo>/<module>/engines/<framework>/` (e.g. backend/engines/langgraph/)
- `<repo>/<module>/` itself (e.g. modules/qa_to_kb/)
- `<repo>/agents/`, `<repo>/workflows/`
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

NODE_THRESHOLD = 3


@dataclass
class AIFlow:
    slug: str  # ai-flows/<slug>.md filename (ascii lowercase hyphen)
    name: str  # display name (zh-TW or en, free-form)
    framework: str  # langgraph | langchain | custom-pipeline
    root_path: str  # repo-relative posix path (e.g. "backend/engines/langgraph")
    flow_kind: str  # real-time-chat | batch-pipeline | rag | tool-use-agent
    node_count: int
    prompt_files: list[str] = field(default_factory=list)
    state_module: str | None = None
    graph_files: list[str] = field(default_factory=list)
    llm_libs: list[str] = field(default_factory=list)
    confidence: str = "medium"  # stated | high | medium


# ---------- detection orchestrator ----------

def detect_ai_flows(
    repo_root: Path,
    *,
    companion_archetype: bool = False,
) -> list[AIFlow]:
    """Find all AI flow subsystems in this repo.

    Heuristic:
    1. Identify candidate roots (dirs containing graph.py | pipeline.py | agents/ | workflows/).
    2. For each candidate, check framework signal + node count.
    3. Drop candidates failing NODE_THRESHOLD (default 3).
    4. Drop ancestor candidates when a more-specific nested flow also qualified
       (e.g. backend/engines is dropped when backend/engines/langgraph qualifies).

    `companion_archetype=True` (v4.6) signals that this repo was detected as an
    AI-companion archetype (Character / World / Storyline / Memory). In that
    case the custom-pipeline branch's `prompts*` file requirement is waived,
    because companion stacks like ai-eden-service inline their system prompts
    as Python strings inside provider modules instead of using prompts.toml.
    """
    repo_root = repo_root.resolve()
    flows: list[AIFlow] = []
    seen_roots: set[Path] = set()
    deps = _read_project_dependencies(repo_root)

    for candidate_root in _candidate_roots(repo_root):
        if candidate_root in seen_roots:
            continue
        seen_roots.add(candidate_root)
        flow = _classify_candidate(
            candidate_root, repo_root, deps,
            companion_archetype=companion_archetype,
        )
        if flow and flow.node_count >= NODE_THRESHOLD:
            flows.append(flow)
    return _drop_ancestor_duplicates(flows)


def _drop_ancestor_duplicates(flows: list[AIFlow]) -> list[AIFlow]:
    """Drop any flow whose root_path is a strict ancestor of another flow's root_path.

    Example: if both `backend/engines` and `backend/engines/langgraph` qualified,
    the nested one is more specific and the parent is almost certainly a false
    positive caused by stray .py files in the parent dir matching `_AI_DIR_NAMES`.
    """
    roots = [f.root_path for f in flows]
    keep: list[AIFlow] = []
    for flow in flows:
        prefix = flow.root_path + "/"
        if any(other != flow.root_path and other.startswith(prefix) for other in roots):
            continue
        keep.append(flow)
    return keep


# ---------- candidate identification ----------

_AI_DIR_SIGNALS = ("graph.py", "pipeline.py")
_AI_DIR_NAMES = ("agents", "workflows", "engines", "qa_to_kb")
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


def _candidate_roots(repo_root: Path) -> list[Path]:
    """Walk one level into common host module dirs; collect dirs that look AI-ish."""
    candidates: set[Path] = set()
    # Scan up to 4 levels deep to find graph.py / pipeline.py.
    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        if _EXCLUDED_DIRS.intersection(p.parts):
            continue
        depth = len(p.relative_to(repo_root).parts)
        if depth > 5:
            continue
        if p.name in _AI_DIR_SIGNALS:
            candidates.add(p.parent)
        elif p.suffix == ".py" and p.parent.name in _AI_DIR_NAMES:
            candidates.add(p.parent)
    return sorted(candidates)


def _classify_candidate(
    candidate: Path,
    repo_root: Path,
    deps: list[str],
    *,
    companion_archetype: bool = False,
) -> AIFlow | None:
    """Return an AIFlow if `candidate` is a real AI flow root, else None.

    When `companion_archetype=True` (v4.6), the custom-pipeline branch's
    `prompts*` file requirement is waived — companion stacks frequently inline
    system prompts in provider modules instead of using a top-level prompts
    file.
    """
    py_files = [p for p in candidate.rglob("*.py") if not _EXCLUDED_DIRS.intersection(p.parts)]

    has_langgraph_dep = any("langgraph" in d.lower() for d in deps)
    has_langchain_dep = any("langchain" in d.lower() and "langgraph" not in d.lower() for d in deps)
    has_llm_dep = any(
        lib in d.lower()
        for d in deps
        for lib in ("openai", "anthropic", "google.generativeai", "google-generativeai")
    )

    # Check import usage in py_files.
    import_text = "\n".join(_safe_read(p) for p in py_files)
    has_langgraph_import = "from langgraph" in import_text or "import langgraph" in import_text
    has_langchain_import = "from langchain" in import_text and "from langgraph" not in import_text

    # Count nodes.
    node_count = _count_nodes(candidate, import_text)

    # Locate state module, prompts, graph files.
    state_module = _find_state_module(candidate, repo_root)
    prompt_files = _find_prompt_files(candidate, repo_root)
    graph_files = _find_graph_files(candidate, repo_root)
    llm_libs = _used_llm_libs(import_text)

    rel_root = candidate.relative_to(repo_root).as_posix()
    slug = _slugify_root(rel_root)
    name = _display_name(candidate)

    # Classification order: LOCAL evidence beats repo-level dependency lists.
    # A repo's pyproject may declare `langgraph` because ONE subsystem uses it,
    # but other subsystems can be plain custom pipelines (openai-only) - those
    # must classify as custom-pipeline, not langgraph.
    #
    # Within LOCAL evidence, structural signals (pipeline.py + nodes/ + prompts.toml)
    # beat utility-import signals like `from langchain_core.documents import Document`,
    # which appear in plenty of custom pipelines that just use LangChain helper types.
    has_pipeline_file = any(p.name == "pipeline.py" for p in py_files)
    has_nodes_dir = (candidate / "nodes").is_dir()

    # 1) Strong local LangGraph signal (StateGraph / add_node pattern is unmistakable).
    if has_langgraph_import:
        return AIFlow(
            slug=slug, name=name, framework="langgraph", root_path=rel_root,
            flow_kind=_infer_flow_kind(candidate, py_files),
            node_count=node_count, prompt_files=prompt_files,
            state_module=state_module, graph_files=graph_files, llm_libs=llm_libs,
            confidence="stated" if has_langgraph_dep else "high",
        )
    # 2) Strong structural custom-pipeline signal (pipeline.py + prompts + LLM).
    # Checked BEFORE langchain-import because `langchain_core.documents` etc are
    # utility types used widely in non-LangChain-orchestrated pipelines.
    #
    # Custom pipeline: has pipeline.py + LLM signal. Either nodes/ dir OR LLM
    # provider imports in the surrounding files is enough — v4.6 loosened the
    # nodes/ requirement so roll-your-own LLM stacks (like ai-eden-service's
    # app/pipeline.py + app/providers/) get detected.
    has_llm_provider_imports = any(
        lib in import_text
        for lib in ("from openai", "import openai",
                    "from anthropic", "import anthropic",
                    "from google.generativeai", "import google.generativeai",
                    "from langchain_openai", "from langchain_google_genai")
    )
    if (
        has_pipeline_file
        and (has_nodes_dir or has_llm_provider_imports)
        and (has_llm_dep or llm_libs)
        and (
            prompt_files
            or any(p.name.startswith("prompts") for p in py_files)
            or companion_archetype
        )
    ):
        return AIFlow(
            slug=slug, name=name, framework="custom-pipeline", root_path=rel_root,
            flow_kind="batch-pipeline",
            node_count=max(node_count, NODE_THRESHOLD), prompt_files=prompt_files,
            state_module=None, graph_files=[],
            llm_libs=llm_libs, confidence="medium",
        )
    # 3) Moderate local LangChain signal (no structural custom-pipeline pattern).
    if has_langchain_import:
        return AIFlow(
            slug=slug, name=name, framework="langchain", root_path=rel_root,
            flow_kind=_infer_flow_kind(candidate, py_files),
            node_count=node_count, prompt_files=prompt_files,
            state_module=None, graph_files=graph_files, llm_libs=llm_libs,
            confidence="stated" if has_langchain_dep else "high",
        )
    # 4) Fallback: repo-level dep mention only (no local imports). Rare but
    # keeps coverage for projects where graph wiring lives in a different file.
    if has_langgraph_dep:
        return AIFlow(
            slug=slug, name=name, framework="langgraph", root_path=rel_root,
            flow_kind=_infer_flow_kind(candidate, py_files),
            node_count=node_count, prompt_files=prompt_files,
            state_module=state_module, graph_files=graph_files, llm_libs=llm_libs,
            confidence="medium",
        )
    if has_langchain_dep:
        return AIFlow(
            slug=slug, name=name, framework="langchain", root_path=rel_root,
            flow_kind=_infer_flow_kind(candidate, py_files),
            node_count=node_count, prompt_files=prompt_files,
            state_module=None, graph_files=graph_files, llm_libs=llm_libs,
            confidence="medium",
        )
    return None


# ---------- helpers ----------

def _read_project_dependencies(repo_root: Path) -> list[str]:
    """Pull dep names from pyproject.toml + package.json (best-effort)."""
    deps: list[str] = []
    py = repo_root / "pyproject.toml"
    if py.exists():
        try:
            data = tomllib.loads(py.read_text())
            deps.extend(data.get("project", {}).get("dependencies", []))
            dev = data.get("dependency-groups", {}).get("dev", []) or []
            deps.extend(dev if isinstance(dev, list) else [])
        except (tomllib.TOMLDecodeError, OSError):
            pass
    # Also walk monorepo subdirs for nested pyproject.tomls (mirror stack.py pattern).
    for sub in ("backend", "frontend", "modules", "services", "api"):
        sub_py = repo_root / sub / "pyproject.toml"
        if sub_py.exists():
            try:
                data = tomllib.loads(sub_py.read_text())
                deps.extend(data.get("project", {}).get("dependencies", []))
            except (tomllib.TOMLDecodeError, OSError):
                pass
    # Also requirements.txt (some projects use that).
    for req in repo_root.rglob("requirements*.txt"):
        if _EXCLUDED_DIRS.intersection(req.parts):
            continue
        try:
            deps.extend(
                line.strip()
                for line in req.read_text().splitlines()
                if line.strip() and not line.startswith("#")
            )
        except OSError:
            pass
    return deps


_NODE_PATTERN_LG = re.compile(r"\.add_node\s*\(\s*['\"]([^'\"]+)['\"]")
_NODE_PATTERN_PY_FILE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


def _count_nodes(candidate: Path, import_text: str) -> int:
    """Count LangGraph add_node calls OR files under <candidate>/nodes/."""
    count = len(set(_NODE_PATTERN_LG.findall(import_text)))
    if count >= NODE_THRESHOLD:
        return count
    # Fallback: count .py files in <candidate>/nodes/
    nodes_dir = candidate / "nodes"
    if nodes_dir.is_dir():
        return max(
            count,
            sum(
                1
                for p in nodes_dir.rglob("*.py")
                if p.name != "__init__.py" and not _EXCLUDED_DIRS.intersection(p.parts)
            ),
        )
    return count


def _find_state_module(candidate: Path, repo_root: Path) -> str | None:
    for name in ("state.py",):
        for p in candidate.rglob(name):
            if not _EXCLUDED_DIRS.intersection(p.parts):
                return p.relative_to(repo_root).as_posix()
    return None


def _find_prompt_files(candidate: Path, repo_root: Path) -> list[str]:
    out: list[str] = []
    # prompts/*.py
    prompts_dir = candidate / "prompts"
    if prompts_dir.is_dir():
        for p in sorted(prompts_dir.rglob("*.py")):
            if p.name != "__init__.py" and not _EXCLUDED_DIRS.intersection(p.parts):
                out.append(p.relative_to(repo_root).as_posix())
    # prompts.toml / prompts.yaml / prompts.json (any depth within candidate)
    for ext in ("toml", "yaml", "yml", "json"):
        for p in candidate.rglob(f"prompts.{ext}"):
            if not _EXCLUDED_DIRS.intersection(p.parts):
                out.append(p.relative_to(repo_root).as_posix())
    return sorted(set(out))


def _find_graph_files(candidate: Path, repo_root: Path) -> list[str]:
    out: list[str] = []
    for name in ("graph.py",):
        for p in candidate.rglob(name):
            if not _EXCLUDED_DIRS.intersection(p.parts):
                out.append(p.relative_to(repo_root).as_posix())
    graphs_dir = candidate / "graphs"
    if graphs_dir.is_dir():
        for p in sorted(graphs_dir.glob("*.py")):
            if p.name != "__init__.py":
                out.append(p.relative_to(repo_root).as_posix())
    return sorted(set(out))


_LLM_LIB_PATTERNS = (
    ("openai", "openai"),
    ("anthropic", "anthropic"),
    ("google.generativeai", "google-generativeai"),
    ("google_generativeai", "google-generativeai"),
    ("cohere", "cohere"),
    ("bedrock", "boto3-bedrock"),
)


def _used_llm_libs(import_text: str) -> list[str]:
    out: set[str] = set()
    for needle, label in _LLM_LIB_PATTERNS:
        if needle in import_text:
            out.add(label)
    return sorted(out)


def _safe_read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def _slugify_root(rel_root: str) -> str:
    """Convert e.g. 'backend/engines/langgraph' → 'lang-ai-customer' OR 'backend-engines-langgraph'.

    Strategy: last 2 path segments lowercased and hyphenated.
    """
    parts = rel_root.split("/")
    tail = "-".join(parts[-2:]) if len(parts) >= 2 else parts[-1]
    slug = re.sub(r"[^a-z0-9-]+", "-", tail.lower()).strip("-")
    return slug or "unknown-ai-flow"


def _display_name(candidate: Path) -> str:
    # Prefer the candidate dir's basename, capitalized.
    return candidate.name.replace("_", " ").replace("-", " ").title()


def _infer_flow_kind(candidate: Path, py_files: list[Path]) -> str:
    """Heuristic: webhook/handler/route in nearby code → real-time-chat;
    pipeline/worker/job → batch-pipeline; default real-time-chat for langgraph."""
    text = " ".join(_safe_read(p) for p in py_files[:20])
    if any(kw in text.lower() for kw in ("webhook", "websocket", "fastapi", "route", "chat")):
        return "real-time-chat"
    if any(kw in text.lower() for kw in ("pipeline", "worker", "batch", "brpop", "consumer")):
        return "batch-pipeline"
    return "real-time-chat"
