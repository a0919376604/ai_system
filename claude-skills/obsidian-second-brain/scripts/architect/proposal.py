"""Module proposal heuristics.

Inputs: repo path. Output: list of proposed module dicts ready for
inclusion in _manifest.yml. Pure function, no I/O beyond reading the
repo filesystem.

Module dict shape:
    {"slug": str, "display_name": str, "paths": [str], "role": str,
     "excluded": bool, "description": None, "pattern": None}
"""

from __future__ import annotations

import re
from pathlib import Path

# Folders that become modules with excluded=True. They show up in
# overview narrative but no per-module note is generated.
#
# Principle: anything that is not source code belongs here. The walker
# filters most of these from file traversal already, but proposal.py
# still sees the folder exists at the top level and would otherwise emit
# a module entry. We mark them excluded so the overview can still mention
# them (e.g. "this repo ships docs/ and tests/") without spawning a note.
SKIP_AS_MODULE = {
    # Tests
    "tests", "test", "__tests__", "spec",
    # Docs
    "docs", "documentation",
    # Examples
    "examples", "example",
    # CI config (hidden folders are filtered earlier; listed for explicitness)
    ".github", ".gitlab",
    # Build output
    "dist", "build", "target", "out", "bin", "obj",
    # Dependency directories (sometimes checked in, e.g. node_modules in lockfile-less repos)
    "node_modules", "vendor", "venv", "env", "virtualenv",
    # Runtime data
    "logs", "log", "reports", "tmp", "temp", "cache",
    # Test coverage artefacts
    "coverage", "htmlcov", ".nyc_output",
}

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def _slugify(name: str) -> str:
    s = _SLUG_RE.sub("-", name.lower()).strip("-")
    return s or "module"


def _candidate_roots(repo_root: Path) -> list[Path]:
    """Where to look for top-level modules.

    If src/ exists and contains folders, that's the module root.
    Otherwise the repo root itself.
    """
    src = repo_root / "src"
    if src.is_dir() and any(p.is_dir() for p in src.iterdir()):
        return [src]
    return [repo_root]


def propose_modules(repo_root: Path) -> list[dict]:
    """Default proposal: one module per first-level folder under the module root."""
    repo_root = repo_root.resolve()
    roots = _candidate_roots(repo_root)
    modules: list[dict] = []
    seen: set[str] = set()

    for root in roots:
        for entry in sorted(root.iterdir()):
            if not entry.is_dir():
                continue
            if entry.name.startswith("."):
                continue
            slug = _slugify(entry.name)
            if slug in seen:
                continue
            seen.add(slug)
            rel_path = entry.relative_to(repo_root).as_posix() + "/"
            modules.append({
                "slug": slug,
                "display_name": entry.name.replace("-", " ").replace("_", " ").title(),
                "paths": [rel_path],
                "role": "other",
                "excluded": entry.name in SKIP_AS_MODULE,
                "description": None,
                "pattern": None,
            })
    return modules

import json

from scripts.architect.walker import walk_repo


def propose_modules_with_heuristics(repo_root: Path, entry_points: list[dict] | None = None) -> list[dict]:
    """Run the full proposal pipeline: monorepo -> default -> flat-fallback -> merge -> split."""
    repo_root = repo_root.resolve()

    # 1. Monorepo detection short-circuits the rest.
    workspaces = _detect_workspaces(repo_root)
    if workspaces:
        return _monorepo_proposal(repo_root, workspaces)

    # 2. Start with default.
    modules = propose_modules(repo_root)

    # 3. Flat-repo fallback.
    non_skip = [m for m in modules if not m["excluded"]]
    if len(non_skip) < 3:
        modules = _flat_repo_proposal(repo_root, modules)

    # 4. Merge small siblings.
    modules = _merge_small_siblings(repo_root, modules)

    # 5. Tag dense folders for split.
    if entry_points:
        modules = _split_dense_folder(repo_root, modules, entry_points)

    return modules


def _detect_workspaces(repo_root: Path) -> list[str]:
    """Detect monorepo workspaces from pnpm/yarn/npm/cargo/go config.

    Returns the list of workspace member directory paths (relative).
    Empty list means not a monorepo.
    """
    # pnpm
    pnpm = repo_root / "pnpm-workspace.yaml"
    if pnpm.exists():
        import yaml
        data = yaml.safe_load(pnpm.read_text()) or {}
        patterns = data.get("packages", [])
        return _expand_workspace_globs(repo_root, patterns)

    # npm/yarn workspaces in package.json
    pkg = repo_root / "package.json"
    if pkg.exists():
        data = json.loads(pkg.read_text())
        ws = data.get("workspaces")
        if isinstance(ws, list):
            return _expand_workspace_globs(repo_root, ws)
        if isinstance(ws, dict) and "packages" in ws:
            return _expand_workspace_globs(repo_root, ws["packages"])

    # Cargo workspace
    cargo = repo_root / "Cargo.toml"
    if cargo.exists():
        try:
            import tomllib  # type: ignore[import-not-found]
        except ImportError:
            import tomli as tomllib  # type: ignore[no-redef]
        data = tomllib.loads(cargo.read_text())
        members = data.get("workspace", {}).get("members", [])
        return _expand_workspace_globs(repo_root, members)

    return []


def _expand_workspace_globs(repo_root: Path, patterns: list[str]) -> list[str]:
    """Expand patterns like 'packages/*' into concrete relative directory paths."""
    import fnmatch

    out: list[str] = []
    for pattern in patterns:
        if "*" in pattern:
            base = pattern.split("*")[0].rstrip("/")
            base_path = repo_root / base
            if base_path.is_dir():
                for sub in sorted(base_path.iterdir()):
                    if sub.is_dir() and fnmatch.fnmatch(sub.name, pattern.split("/")[-1]):
                        out.append(sub.relative_to(repo_root).as_posix())
        else:
            full = repo_root / pattern
            if full.is_dir():
                out.append(pattern)
    return out


def _monorepo_proposal(repo_root: Path, workspaces: list[str]) -> list[dict]:
    modules: list[dict] = []
    for ws_path in workspaces:
        slug = _slugify(Path(ws_path).name)
        modules.append({
            "slug": slug,
            "display_name": Path(ws_path).name.replace("-", " ").replace("_", " ").title(),
            "paths": [ws_path + "/"],
            "role": "other",
            "excluded": False,
            "description": None,
            "pattern": None,
        })
    return modules


def _flat_repo_proposal(repo_root: Path, base: list[dict]) -> list[dict]:
    """Add a 'core' module covering the repo root files, alongside any folders."""
    # Keep non-skip folder modules; prepend a 'core' module for root-level files.
    folder_modules = base
    core = {
        "slug": "core",
        "display_name": "Core",
        "paths": ["./"],
        "role": "core",
        "excluded": False,
        "description": None,
        "pattern": None,
    }
    return [core] + folder_modules

def _folder_token_count(repo_root: Path, folder_rel: str) -> int:
    """Approximate token count of all files under a given folder."""
    from scripts.architect.walker import EXT_TO_LANG, _approx_tokens, walk_repo

    base = folder_rel.rstrip("/")
    total = 0
    for rel in walk_repo(repo_root):
        if rel == base or rel.startswith(base + "/"):
            path = repo_root / rel
            try:
                total += _approx_tokens(path.read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                continue
    return total


def _folder_primary_language(repo_root: Path, folder_rel: str) -> str:
    """Primary language of a folder by file count of recognised extensions."""
    from scripts.architect.walker import EXT_TO_LANG, walk_repo

    base = folder_rel.rstrip("/")
    counts: dict[str, int] = {}
    for rel in walk_repo(repo_root):
        if rel == base or rel.startswith(base + "/"):
            ext = Path(rel).suffix.lower()
            lang = EXT_TO_LANG.get(ext, "other")
            counts[lang] = counts.get(lang, 0) + 1
    if not counts:
        return "unknown"
    return max(counts.items(), key=lambda kv: kv[1])[0]


def _merge_small_siblings(repo_root: Path, modules: list[dict], threshold: int = 2000) -> list[dict]:
    """Propose merging adjacent modules that share a primary language and are each below `threshold` tokens.

    Returns a new list. Original input is not mutated. Conservative: only merges
    pairs of modules whose paths are siblings at the same depth and where neither
    is excluded.
    """
    if len(modules) < 2:
        return list(modules)

    enriched = []
    for m in modules:
        if m["excluded"] or len(m["paths"]) != 1:
            enriched.append((m, None, None))
            continue
        folder = m["paths"][0]
        tokens = _folder_token_count(repo_root, folder)
        lang = _folder_primary_language(repo_root, folder)
        enriched.append((m, tokens, lang))

    merged: list[dict] = []
    skip_next = False
    for i, (m, tokens, lang) in enumerate(enriched):
        if skip_next:
            skip_next = False
            continue
        if i + 1 < len(enriched):
            n_mod, n_tokens, n_lang = enriched[i + 1]
            if (
                tokens is not None and n_tokens is not None
                and tokens < threshold and n_tokens < threshold
                and lang == n_lang and lang != "unknown"
                and _merge_family(m["slug"]) == _merge_family(n_mod["slug"])
            ):
                combined = {
                    "slug": f"{m['slug']}-{n_mod['slug']}",
                    "display_name": f"{m['display_name']} + {n_mod['display_name']}",
                    "paths": sorted(m["paths"] + n_mod["paths"]),
                    "role": m["role"],
                    "excluded": False,
                    "description": None,
                    "pattern": None,
                    "merge_hint": True,
                }
                merged.append(combined)
                skip_next = True
                continue
        merged.append(m)
    return merged


def _merge_family(slug: str) -> str:
    """Return a conservative family key for merge candidates."""
    return re.split(r"[-_]", slug, maxsplit=1)[0]


def _split_dense_folder(
    repo_root: Path, modules: list[dict], entry_points: list[dict], file_threshold: int = 30
) -> list[dict]:
    """Tag modules whose single folder is large AND has multiple entry points as 'split_hint'.

    v1 does not auto-split (path layouts vary too much per ecosystem). Instead
    the module dict is marked so Phase 2 can prompt the user.
    """
    from scripts.architect.walker import walk_repo

    out: list[dict] = []
    for m in modules:
        if m["excluded"] or len(m["paths"]) != 1:
            out.append(m)
            continue
        base = m["paths"][0].rstrip("/")
        file_count = sum(
            1 for rel in walk_repo(repo_root)
            if rel == base or rel.startswith(base + "/")
        )
        ep_in_module = sum(
            1 for ep in entry_points
            if ep["path"].startswith(base + "/") or ep["path"] == base
        )
        if file_count > file_threshold and ep_in_module > 1:
            tagged = dict(m)
            tagged["split_hint"] = True
            out.append(tagged)
        else:
            out.append(m)
    return out
