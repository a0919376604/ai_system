"""v2 → v3 migration helper.

Drops v2 @generated blocks (file-tree noise) and keeps @user blocks (judgment).
Provides plan-then-apply for safety + tar.gz archive as safety net.
"""

from __future__ import annotations

import re
import tarfile
import time
from dataclasses import dataclass, field
from pathlib import Path

# v2 generated block names that v3 supersedes — these get dropped.
V2_GENERATED_BLOCKS_TO_DROP = {
    "what-it-does", "how-it-works", "key-files",
    "depends-on", "consumed-by", "recent-activity",
}

# v3 generated blocks per file type (module-level).
V3_MODULE_BLOCKS = {"scope", "strengths", "weaknesses", "improvements", "dependencies"}

# Sentinel + heading detection.
_GENERATED_RE = re.compile(
    r"(##\s+[^\n]*\n\s*\n?)?"
    r"<!--\s*@generated:start\s+(\S+)\s*-->"
    r".*?"
    r"<!--\s*@generated:end\s+\2\s*-->\n?",
    re.DOTALL,
)
_USER_NAME_RE = re.compile(r"<!--\s*@user:start\s+(\S+)\s*-->")


@dataclass
class MigrationPlan:
    files_to_modify: list[str] = field(default_factory=list)
    # files_to_modify entry -> {"drop": [block_names], "keep": [block_names], "create": [block_names]}
    blocks_per_file: dict[str, dict[str, list[str]]] = field(default_factory=dict)


def plan_v2_to_v3_migration(arch_dir: Path) -> MigrationPlan:
    """Inspect an Architecture/ tree; return what would change without modifying."""
    plan = MigrationPlan()
    if not arch_dir.is_dir():
        return plan
    # Walk Architecture/*.md and Architecture/modules/*.md
    candidates = list(arch_dir.glob("*.md")) + list((arch_dir / "modules").glob("*.md"))
    for f in sorted(candidates):
        rel = str(f.relative_to(arch_dir))
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        drop = []
        for m in _GENERATED_RE.finditer(text):
            block_name = m.group(2)
            if block_name in V2_GENERATED_BLOCKS_TO_DROP:
                drop.append(block_name)
        keep = list(set(_USER_NAME_RE.findall(text)))
        if not drop and not keep:
            continue
        plan.files_to_modify.append(rel)
        # Determine v3 blocks to create per file type.
        if rel.startswith("modules/"):
            create = sorted(V3_MODULE_BLOCKS)
        else:
            # For overview / features / etc. the relevant blocks differ;
            # the command body inserts them. Here we just declare intent.
            create = ["scope", "strengths", "weaknesses", "improvements"]
        plan.blocks_per_file[rel] = {
            "drop": sorted(drop),
            "keep": sorted(keep),
            "create": create,
        }
    return plan


def apply_v2_to_v3_migration(arch_dir: Path, plan: MigrationPlan, dry_run: bool = False) -> None:
    """Drop v2 @generated blocks (and their preceding H2 heading) in place.

    Leaves @user blocks and unrelated content untouched. Caller is responsible
    for backup (call `backup_architecture_dir` first if desired).
    """
    if dry_run:
        return
    for rel in plan.files_to_modify:
        path = arch_dir / rel
        text = path.read_text(encoding="utf-8")
        new_text = _GENERATED_RE.sub(_drop_if_v2, text)
        # Collapse 3+ consecutive blank lines to 2 for tidiness.
        new_text = re.sub(r"\n{3,}", "\n\n", new_text)
        path.write_text(new_text, encoding="utf-8")


def _drop_if_v2(m: re.Match) -> str:
    """Replacement callback for `_GENERATED_RE`. Drops the match if its block
    name is in V2_GENERATED_BLOCKS_TO_DROP, otherwise leaves the original
    text untouched."""
    block_name = m.group(2)
    if block_name in V2_GENERATED_BLOCKS_TO_DROP:
        return ""
    return m.group(0)


def backup_architecture_dir(arch_dir: Path, archive_root: Path | None = None) -> Path:
    """Tar.gz the entire Architecture/ tree to a timestamped path.

    Default archive_root is `<arch_dir>/.._archive/`. Returns the archive path.
    """
    if archive_root is None:
        archive_root = arch_dir.parent / "_archive"
    archive_root.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    archive = archive_root / f"architecture-pre-v3-{ts}.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(arch_dir, arcname=arch_dir.name)
    return archive


V4_FILES_TO_DELETE = (
    "future.md",
    "roadmap.md",
    "jobs.md",
    "api-surface.md",
    "features.md",
    "flows.md",
)


@dataclass
class V3ToV4Plan:
    files_to_delete: list[str] = field(default_factory=list)
    files_to_keep: list[str] = field(default_factory=list)
    known_limitations_to_migrate: str | None = None


_KNOWN_LIM_BLOCK_RE = re.compile(
    r"<!--\s*@generated:start\s+known-limitations\s*-->\n"
    r"(?P<body>.*?)\n"
    r"<!--\s*@generated:end\s+known-limitations\s*-->",
    re.DOTALL,
)


def plan_v3_to_v4_migration(arch_dir: Path) -> V3ToV4Plan:
    """Inspect a v3 Architecture/ tree; return what would change for v4."""
    plan = V3ToV4Plan()
    if not arch_dir.is_dir():
        return plan
    for fname in V4_FILES_TO_DELETE:
        if (arch_dir / fname).is_file():
            plan.files_to_delete.append(fname)
    # Files to keep: top-level .md NOT in delete list, plus modules/*.md
    for f in sorted(arch_dir.glob("*.md")):
        if f.name in V4_FILES_TO_DELETE:
            continue
        plan.files_to_keep.append(f.name)
    for f in sorted((arch_dir / "modules").glob("*.md")) if (arch_dir / "modules").is_dir() else []:
        plan.files_to_keep.append(f"modules/{f.name}")
    # Extract known-limitations from future.md (if present).
    future = arch_dir / "future.md"
    if future.is_file():
        try:
            text = future.read_text(encoding="utf-8")
            m = _KNOWN_LIM_BLOCK_RE.search(text)
            if m:
                plan.known_limitations_to_migrate = m.group("body").strip()
        except UnicodeDecodeError:
            pass
    return plan


def apply_v3_to_v4_migration(arch_dir: Path, plan: V3ToV4Plan, dry_run: bool = False) -> None:
    """Carry out the v3 -> v4 migration.

    1. Merge known-limitations into decisions.md (if present).
    2. Delete the 6 obsolete files.
    Caller should have already called backup_architecture_dir() for safety.
    """
    if dry_run:
        return
    # Step 1: Merge known-limitations into decisions.md.
    if plan.known_limitations_to_migrate:
        _merge_known_limitations_into_decisions(arch_dir, plan.known_limitations_to_migrate)
    # Step 2: Delete obsolete files.
    for fname in plan.files_to_delete:
        target = arch_dir / fname
        if target.is_file():
            target.unlink()


def _merge_known_limitations_into_decisions(arch_dir: Path, body: str) -> None:
    """Append a `## 已知限制 / Known limitations` sentinel block to decisions.md."""
    decisions = arch_dir / "decisions.md"
    if not decisions.is_file():
        return
    text = decisions.read_text(encoding="utf-8")
    # Idempotent: if the block already exists, skip.
    if "@generated:start known-limitations" in text:
        return
    # Detect language from existing decisions.md frontmatter.
    lang = "en"
    if "lang: zh-TW" in text:
        lang = "zh-TW"
    heading_str = "## 已知限制" if lang == "zh-TW" else "## Known limitations"
    # Insert before the "## Related" / "## 相關" heading if present, else append.
    related_marker = "## 相關" if lang == "zh-TW" else "## Related"
    insertion = (
        f"\n{heading_str}\n"
        f"<!-- @generated:start known-limitations -->\n"
        f"{body}\n"
        f"<!-- @generated:end known-limitations -->\n"
    )
    if related_marker in text:
        text = text.replace(related_marker, insertion + "\n" + related_marker, 1)
    else:
        text = text.rstrip() + "\n" + insertion + "\n"
    decisions.write_text(text, encoding="utf-8")
