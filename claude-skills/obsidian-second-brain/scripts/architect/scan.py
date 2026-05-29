"""Phase 1 orchestrator: tie walker + repomix + entry_points + deps + proposal
plus narrative-signal detectors into a single deterministic output.
"""

from __future__ import annotations

import subprocess
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path

from scripts.architect.adr import discover_decision_docs
from scripts.architect.ai_flow import detect_ai_flows
from scripts.architect.api_surface import detect_api_surface
from scripts.architect.changelog import load_changelog
from scripts.architect.commit_decisions import extract_commit_decisions
from scripts.architect.deps import detect_external_deps
from scripts.architect.entry_points import detect_entry_points
from scripts.architect.git_history import last_touch_map
from scripts.architect.manifest import Manifest
from scripts.architect.prompt_extract import extract_prompts
from scripts.architect.proposal import propose_modules_with_heuristics
from scripts.architect.readme import extract_from_repo
from scripts.architect.research_walker import collect_research_excerpts
from scripts.architect.repomix import pack_repo_metadata
from scripts.architect.stack import detect_stack
from scripts.architect.todos import aggregate_todos
from scripts.architect.walker import git_metadata, language_stats, walk_repo

SCANNER_VERSION = "0.2.0"


@dataclass
class ScanResult:
    manifest: Manifest
    scan_report: dict


def run_phase_one(repo_root: Path, vault_project_dir: Path | None = None) -> ScanResult:
    repo_root = repo_root.resolve()

    files = walk_repo(repo_root)
    languages = language_stats(repo_root)
    git_meta = _git_metadata_or_unknown(repo_root)
    entry_points = detect_entry_points(repo_root)
    external_deps = detect_external_deps(repo_root)
    modules = propose_modules_with_heuristics(repo_root, entry_points=entry_points)
    pack_meta = pack_repo_metadata(repo_root)

    primary_language = languages[0]["lang"] if languages else "unknown"

    manifest = Manifest(
        version=1,
        repo={
            "name": repo_root.name,
            "root": str(repo_root),
            "primary_language": primary_language,
            "languages": languages,
        },
        last_scan={
            "date": date.today().isoformat(),
            "commit": git_meta["commit"][:7] + ("+dirty" if git_meta["dirty"] else ""),
            "dirty": git_meta["dirty"],
            "scanner_version": SCANNER_VERSION,
        },
        modules=modules,
    )

    # Narrative signal collection.
    # extract_from_repo aggregates root README plus monorepo subdir READMEs
    # (backend/, frontend/, services/, etc.) so monorepos surface richer signal.
    readme_sections = extract_from_repo(repo_root)
    changelog = load_changelog(repo_root)
    decision_docs = [asdict(d) for d in discover_decision_docs(repo_root)]
    stack = detect_stack(repo_root)
    module_paths_map = {m["slug"]: m.get("paths", []) for m in modules}
    todos = {
        slug: [asdict(t) for t in items]
        for slug, items in aggregate_todos(repo_root, module_paths_map).items()
    }
    api_surface = detect_api_surface(repo_root)
    commit_decisions = [asdict(c) for c in extract_commit_decisions(repo_root, limit=200)]

    # AI flow detection + per-flow prompt extraction (v4.1).
    ai_flow_records = list(detect_ai_flows(repo_root))
    ai_flows_data: list[dict] = []
    for flow in ai_flow_records:
        flow_dict = {
            "slug": flow.slug,
            "name": flow.name,
            "framework": flow.framework,
            "root_path": flow.root_path,
            "flow_kind": flow.flow_kind,
            "node_count": flow.node_count,
            "prompt_files": flow.prompt_files,
            "state_module": flow.state_module,
            "graph_files": flow.graph_files,
            "llm_libs": flow.llm_libs,
            "confidence": flow.confidence,
            "prompts": [asdict(p) for p in extract_prompts(repo_root / flow.root_path)],
        }
        ai_flows_data.append(flow_dict)

    # v4.3 — cross-flow AI memory + RAG signals.
    from scripts.architect.ai_memory_detect import detect_memory
    from scripts.architect.ai_rag_detect import detect_rag

    ai_memory_data = detect_memory(repo_root, ai_flow_records)
    ai_rag_data = detect_rag(repo_root, ai_flow_records)

    scan_report = {
        "files": files,
        "languages": languages,
        "entry_points": entry_points,
        "external_deps": external_deps,
        "pack_metadata": pack_meta,
        "git": git_meta,
        "scanner_version": SCANNER_VERSION,
        # Narrative additions.
        "readme_sections": readme_sections,
        "changelog": _changelog_to_dict(changelog),
        "decision_docs": decision_docs,
        "stack": stack,
        "todos": todos,
        "api_surface": _api_surface_to_dict(api_surface),
        "commit_decisions": commit_decisions,
        "ai_flows": ai_flows_data,
        # v4.3 — cross-flow lenses.
        "ai_memory": ai_memory_data,
        "ai_rag": ai_rag_data,
    }
    _add_features_inputs(scan_report, repo_root, vault_project_dir)

    return ScanResult(manifest=manifest, scan_report=scan_report)


def build_scan_report(repo_root: Path, vault_project_dir: Path | None = None) -> dict:
    """Build and return only the scan-report dict.

    This is a thin v4.2 convenience wrapper for tests and command snippets that
    do not need the manifest object.
    """
    return run_phase_one(repo_root, vault_project_dir=vault_project_dir).scan_report


def _git_metadata_or_unknown(repo_root: Path) -> dict:
    """Return git metadata, or a stable placeholder for non-git test fixtures."""
    try:
        return git_metadata(repo_root)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {"commit": "unknown", "dirty": False}


def _add_features_inputs(
    report: dict,
    repo_root: Path,
    vault_project_dir: Path | None,
) -> None:
    """Add v4.2 features.md inputs to `report` in place."""
    agents_path = repo_root / "AGENTS.md"
    agents_text = ""
    if agents_path.exists():
        try:
            agents_text = agents_path.read_text(encoding="utf-8")[:20_000]
        except (OSError, UnicodeDecodeError):
            agents_text = ""
    report["agents_md_text"] = agents_text

    if vault_project_dir is not None and Path(vault_project_dir).exists():
        report["research_excerpts"] = collect_research_excerpts(Path(vault_project_dir))
    else:
        report["research_excerpts"] = []

    surface = report.get("api_surface", {}) or {}
    surface_files: set[str] = set()
    for route in surface.get("http_routes", []):
        f = _surface_file(route)
        if f:
            surface_files.add(f)
    for cmd in surface.get("cli_commands", []):
        f = _surface_file(cmd)
        if f:
            surface_files.add(f)
    for exp in surface.get("exports", []):
        f = _surface_file(exp)
        if f:
            surface_files.add(f)
    if not surface_files:
        surface_files = {
            f for f in report.get("files", []) if Path(f).suffix.lower() in {".py", ".js", ".ts", ".tsx"}
        }
    report["git_last_touch"] = last_touch_map(repo_root, sorted(surface_files))


def _surface_file(entry: dict) -> str:
    """Return file path from api_surface entry with either `file` or `source` shape."""
    file_value = entry.get("file")
    if file_value:
        return file_value
    source = entry.get("source") or ""
    if ":" not in source:
        return source
    return source.rsplit(":", 1)[0]


def _changelog_to_dict(cl) -> dict:
    if cl is None:
        return {"unreleased": None, "recent_versions": []}
    return {
        "unreleased": cl.unreleased,
        "recent_versions": [asdict(v) for v in cl.recent_versions],
    }


def _api_surface_to_dict(surf) -> dict:
    return {
        "cli_commands": [asdict(c) for c in surf.cli_commands],
        "http_routes": [asdict(r) for r in surf.http_routes],
        "exports": [asdict(e) for e in surf.exports],
        "env_vars": [asdict(v) for v in surf.env_vars],
        "detection_status": surf.detection_status,
    }
