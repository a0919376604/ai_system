"""Extract recognized sections from a README.

Returns a dict {canonical_section_name: body_text} where canonical names are
title-case strings drawn from a fixed alias map. Unknown sections are ignored.

`extract_from_repo` aggregates root README plus known monorepo subdirectory
READMEs (backend, frontend, services, apps, packages, etc.). Subdir sections
are keyed as `<subdir>/<canonical>` so they can be cited independently.
"""

from __future__ import annotations

import re
from pathlib import Path

# Map of lowercase alias -> canonical title-case name.
_ALIASES = {
    # Existing narrative-friendly sections.
    "features": "Features",
    "capabilities": "Features",
    "roadmap": "Roadmap",
    "coming soon": "Coming Soon",
    "upcoming": "Coming Soon",
    "limitations": "Limitations",
    "known issues": "Known Issues",
    "known limitations": "Limitations",
    "future work": "Future Work",
    "future": "Future Work",
    "what's next": "Future Work",
    # Real-world monorepo / app README sections.
    "architecture": "Architecture",
    "design": "Architecture",
    "tech stack": "Stack",
    "stack": "Stack",
    "technology stack": "Stack",
    "project overview": "Overview",
    "overview": "Overview",
    "about": "Overview",
    "configuration": "Configuration",
    "config": "Configuration",
    "environment variables": "Environment Variables",
    "env variables": "Environment Variables",
    "env vars": "Environment Variables",
    "local development": "Development",
    "development": "Development",
    "running locally": "Development",
    "deployment": "Deployment",
    "docker deployment": "Deployment",
    "deploying": "Deployment",
    "project structure": "Structure",
    "structure": "Structure",
    "directory structure": "Structure",
    "repo structure": "Structure",
    "getting started": "Getting Started",
    "quick start": "Getting Started",
    "quickstart": "Getting Started",
    "installation": "Getting Started",
    "install": "Getting Started",
    "usage": "Usage",
    "how to use": "Usage",
    "examples": "Usage",
}

_H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)

# Subdirs to probe for additional READMEs. Mirrors stack.py's _MONOREPO_PROBES
# so detection is consistent across signal types.
_README_PROBES = (
    "backend", "frontend", "api", "web", "server", "client", "app", "core",
    "services", "apps", "packages",
)


def extract_sections(text: str) -> dict[str, str]:
    """Return {canonical_name: body} for every recognized H2 in `text`.

    Body is the raw text between this H2 and the next H2 (or EOF), stripped.
    """
    matches = list(_H2_RE.finditer(text))
    if not matches:
        return {}
    out: dict[str, str] = {}
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        canonical = _ALIASES.get(title)
        if canonical is None:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        out[canonical] = text[body_start:body_end].strip()
    return out


def extract_from_repo(repo_root: Path) -> dict[str, str]:
    """Aggregate README sections from root plus monorepo subdir READMEs.

    Root-level sections appear under their canonical name (e.g. "Features").
    Subdir sections appear prefixed with the subdir name (e.g. "backend/Architecture").
    """
    repo_root = repo_root.resolve()
    out: dict[str, str] = {}

    root_readme = repo_root / "README.md"
    if root_readme.exists():
        try:
            for k, v in extract_sections(root_readme.read_text(encoding="utf-8")).items():
                out[k] = v
        except UnicodeDecodeError:
            pass

    for sub in _README_PROBES:
        sub_readme = repo_root / sub / "README.md"
        if not sub_readme.is_file():
            continue
        try:
            sections = extract_sections(sub_readme.read_text(encoding="utf-8"))
        except UnicodeDecodeError:
            continue
        for k, v in sections.items():
            out[f"{sub}/{k}"] = v

    return out
