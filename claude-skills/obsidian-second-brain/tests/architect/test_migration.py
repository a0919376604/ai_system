import tarfile
from pathlib import Path

from scripts.architect.migration import (
    MigrationPlan,
    plan_v2_to_v3_migration,
    apply_v2_to_v3_migration,
    backup_architecture_dir,
)


def _setup_v2_architecture(arch_root: Path):
    """Create a synthetic v2 layout: modules/X.md with @generated blocks."""
    (arch_root / "modules").mkdir(parents=True)
    (arch_root / "modules" / "backend.md").write_text(
        "---\ntype: architecture-module\n---\n\n"
        "## For future Claude\nPreamble.\n\n"
        "## What it does\n"
        "<!-- @generated:start what-it-does -->\n"
        "It does backend things.\n"
        "<!-- @generated:end what-it-does -->\n\n"
        "## Key files\n"
        "<!-- @generated:start key-files -->\n"
        "- backend/main.py\n"
        "- backend/app.py\n"
        "<!-- @generated:end key-files -->\n\n"
        "## User notes\n"
        "<!-- @user:start user-notes -->\n"
        "This module has a tricky lifecycle, see ADR-007.\n"
        "<!-- @user:end user-notes -->\n"
    )


def test_plan_lists_blocks_to_drop_keep_and_archive(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    plan = plan_v2_to_v3_migration(arch)
    assert plan.files_to_modify == ["modules/backend.md"]
    backend_blocks = plan.blocks_per_file["modules/backend.md"]
    # v2 generated blocks slated for removal.
    assert "what-it-does" in backend_blocks["drop"]
    assert "key-files" in backend_blocks["drop"]
    # User block preserved.
    assert "user-notes" in backend_blocks["keep"]


def test_apply_strips_generated_keeps_user_blocks(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    plan = plan_v2_to_v3_migration(arch)
    apply_v2_to_v3_migration(arch, plan, dry_run=False)
    text = (arch / "modules" / "backend.md").read_text()
    # @generated blocks dropped along with their headings.
    assert "@generated:start what-it-does" not in text
    assert "@generated:start key-files" not in text
    assert "It does backend things." not in text
    assert "backend/main.py" not in text
    # @user block kept verbatim.
    assert "@user:start user-notes" in text
    assert "see ADR-007" in text
    # Preamble heading and YAML survive.
    assert "## For future Claude" in text


def test_dry_run_does_not_modify_files(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    before = (arch / "modules" / "backend.md").read_text()
    plan = plan_v2_to_v3_migration(arch)
    apply_v2_to_v3_migration(arch, plan, dry_run=True)
    after = (arch / "modules" / "backend.md").read_text()
    assert before == after


def test_backup_creates_tarball(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    archive = backup_architecture_dir(arch)
    assert archive.exists()
    assert archive.suffix == ".gz"
    # tar.gz contains the architecture tree.
    with tarfile.open(archive, "r:gz") as tf:
        names = tf.getnames()
        assert any("modules/backend.md" in n for n in names)


def test_plan_lists_v3_blocks_to_create(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    plan = plan_v2_to_v3_migration(arch)
    expected_v3 = {"scope", "strengths", "weaknesses", "improvements", "dependencies"}
    actual = set(plan.blocks_per_file["modules/backend.md"]["create"])
    assert expected_v3 <= actual, f"missing v3 blocks: {expected_v3 - actual}"


def _setup_v3_architecture(arch_root: Path):
    """Create a synthetic v3 layout: 14 files including the 6 to-be-deleted."""
    (arch_root / "modules").mkdir(parents=True)
    (arch_root / "overview.md").write_text(
        "---\ntype: architecture-overview\nmoc-style: true\n---\n\n"
        "## For future Claude\nMOC\n"
    )
    (arch_root / "future.md").write_text(
        "---\ntype: architecture-future\n---\n\n"
        "## 給未來 Claude\nGap analysis.\n\n"
        "## 已知限制\n"
        "<!-- @generated:start known-limitations -->\n"
        "- backend/.env deprecated\n"
        "- plain-text password fallback\n"
        "<!-- @generated:end known-limitations -->\n\n"
        "## 落差分析\nthings.\n"
    )
    (arch_root / "decisions.md").write_text(
        "---\ntype: architecture-decisions\n---\n\n"
        "## 給未來 Claude\nDecisions index.\n\n"
        "## 技術棧理由\n"
        "<!-- @generated:start stack-rationale -->\n- React + FastAPI\n<!-- @generated:end stack-rationale -->\n"
    )
    for fname in ("roadmap.md", "jobs.md", "api-surface.md", "features.md", "flows.md", "personas.md"):
        (arch_root / fname).write_text(f"---\ntype: architecture-{fname.replace('.md', '')}\n---\n\nbody\n")
    for slug in ("backend", "frontend"):
        (arch_root / "modules" / f"{slug}.md").write_text(
            f"---\ntype: architecture-module\n---\n\n## 模組職責\nx\n"
        )


def test_v3_to_v4_plan_lists_6_files_to_delete(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    expected_deletes = {"future.md", "roadmap.md", "jobs.md", "api-surface.md", "features.md", "flows.md"}
    assert set(plan.files_to_delete) == expected_deletes


def test_v3_to_v4_plan_keeps_overview_modules_decisions_personas(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    kept = set(plan.files_to_keep)
    assert "overview.md" in kept
    assert "decisions.md" in kept
    assert "personas.md" in kept
    assert "modules/backend.md" in kept
    assert "modules/frontend.md" in kept


def test_v3_to_v4_plan_extracts_known_limitations_from_future(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    assert plan.known_limitations_to_migrate is not None
    assert "backend/.env deprecated" in plan.known_limitations_to_migrate
    assert "plain-text password fallback" in plan.known_limitations_to_migrate


def test_v3_to_v4_apply_deletes_obsolete_files(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration, apply_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    apply_v3_to_v4_migration(arch, plan, dry_run=False)
    for fname in ("future.md", "roadmap.md", "jobs.md", "api-surface.md", "features.md", "flows.md"):
        assert not (arch / fname).exists(), f"{fname} should have been deleted"
    # Files to keep still present.
    assert (arch / "overview.md").exists()
    assert (arch / "decisions.md").exists()
    assert (arch / "personas.md").exists()
    assert (arch / "modules" / "backend.md").exists()


def test_v3_to_v4_apply_merges_known_limitations_into_decisions(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration, apply_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    apply_v3_to_v4_migration(arch, plan, dry_run=False)
    decisions_text = (arch / "decisions.md").read_text(encoding="utf-8")
    # Known limitations block now present in decisions.md
    assert "@generated:start known-limitations" in decisions_text
    assert "backend/.env deprecated" in decisions_text


def test_v3_to_v4_dry_run_does_not_modify(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration, apply_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    before_future = (arch / "future.md").read_text()
    before_decisions = (arch / "decisions.md").read_text()
    plan = plan_v3_to_v4_migration(arch)
    apply_v3_to_v4_migration(arch, plan, dry_run=True)
    assert (arch / "future.md").exists()
    assert (arch / "future.md").read_text() == before_future
    assert (arch / "decisions.md").read_text() == before_decisions
