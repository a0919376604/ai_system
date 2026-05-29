"""Per-module refresh decision.

Pure decision function. Does not write files. Caller (scan.py or
slash command body) acts on the returned RefreshAction.
"""

from __future__ import annotations

import subprocess
from enum import Enum
from pathlib import Path


class RefreshAction(str, Enum):
    GENERATE = "generate"        # new module, no prior note
    REGENERATE = "regenerate"    # existing module changed
    SKIP = "skip"                # unchanged, only frontmatter touched


def decide_module_refresh(
    module: dict,
    lockfile_modules: dict,
    old_commit: str | None,
    new_commit: str,
    repo_root: Path,
    force: bool = False,
) -> RefreshAction:
    """Decide what to do with this module in the current refresh run.

    Args:
        module: current manifest module dict (slug, paths, ...).
        lockfile_modules: mapping {slug: {"paths": [...], ...}} from lockfile.
        old_commit: commit hash of last successful scan (None on first run).
        new_commit: commit hash of current scan.
        repo_root: repo path for git diff.
        force: --force flag bypasses skip logic.
    """
    slug = module["slug"]
    if slug not in lockfile_modules:
        return RefreshAction.GENERATE

    if force:
        return RefreshAction.REGENERATE

    old_paths = sorted(lockfile_modules[slug].get("paths", []))
    new_paths = sorted(module.get("paths", []))
    if old_paths != new_paths:
        return RefreshAction.REGENERATE

    if old_commit and new_commit and old_commit != new_commit:
        if _paths_changed_between_commits(repo_root, old_commit, new_commit, new_paths):
            return RefreshAction.REGENERATE

    return RefreshAction.SKIP


def _paths_changed_between_commits(
    repo_root: Path, old_commit: str, new_commit: str, paths: list[str]
) -> bool:
    """True iff git diff <old>..<new> -- <paths> reports any change."""
    cmd = ["git", "-C", str(repo_root), "diff", "--quiet", f"{old_commit}..{new_commit}", "--"] + paths
    result = subprocess.run(cmd, capture_output=True)
    # `git diff --quiet` exits 0 on no change, 1 on changes.
    return result.returncode == 1


def decide_section_refresh(
    lock,
    *,
    section: str,
    current_signal: str,
    current_lang: str,
    force: bool = False,
    refresh_flag: bool = False,
) -> RefreshAction:
    """Decide what to do with a narrative-section note.

    - First run (no lockfile entry): GENERATE
    - --force: REGENERATE always
    - signal or lang differs: REGENERATE
    - otherwise: SKIP

    `refresh_flag` is reserved for future per-section --refresh semantics; today
    it is treated identically to no flag (skip on unchanged signal).
    """
    from scripts.architect.lockfile import section_signal_was_changed
    if force:
        return RefreshAction.REGENERATE
    if section_signal_was_changed(lock, section, current_signal=current_signal, current_lang=current_lang):
        record = lock.sections.get(section)
        return RefreshAction.GENERATE if record is None else RefreshAction.REGENERATE
    return RefreshAction.SKIP


def render_hub_architecture_block(
    *,
    commit: str,
    last_scanned: str,
    modules_active: int,
    modules_deprecated: int,
    repo_path: str,
    lang: str,
) -> str:
    """Render the `## Architecture` block written into Projects/<P>/<P>.md."""
    if lang == "zh-TW":
        return "\n".join([
            "## 架構",
            "",
            f"- 總覽: [[Architecture/overview]] (上次掃描 {last_scanned} @ `{commit}`)",
            f"- 能力: [[Architecture/features]] | [[Architecture/api-surface]]",
            f"- 方向: [[Architecture/roadmap]] | [[Architecture/future]]",
            f"- 理由: [[Architecture/decisions]]",
            f"- 模組: {modules_active} active, {modules_deprecated} deprecated",
            f"- 重新整理: `/obsidian-architect {repo_path} --refresh`",
        ])
    return "\n".join([
        "## Architecture",
        "",
        f"- Overview: [[Architecture/overview]] (last scanned {last_scanned} @ `{commit}`)",
        f"- Capabilities: [[Architecture/features]] | [[Architecture/api-surface]]",
        f"- Direction: [[Architecture/roadmap]] | [[Architecture/future]]",
        f"- Rationale: [[Architecture/decisions]]",
        f"- Modules: {modules_active} active, {modules_deprecated} deprecated",
        f"- Refresh: `/obsidian-architect {repo_path} --refresh`",
    ])
