from pathlib import Path

from scripts.architect.proposal import propose_modules


def test_default_proposal_one_per_top_folder(single_lang_python: Path):
    modules = propose_modules(single_lang_python)
    slugs = sorted(m["slug"] for m in modules)
    # src/ contains auth, db, api -> 3 modules (default looks inside src/ if it exists)
    assert "auth" in slugs
    assert "db" in slugs
    assert "api" in slugs


def test_tests_folder_excluded(single_lang_python: Path):
    modules = propose_modules(single_lang_python)
    by_slug = {m["slug"]: m for m in modules}
    # tests/ appears with excluded=True, but not omitted entirely
    if "tests" in by_slug:
        assert by_slug["tests"]["excluded"] is True


def test_role_defaults_to_other(single_lang_python: Path):
    modules = propose_modules(single_lang_python)
    for m in modules:
        if not m["excluded"]:
            assert m["role"] in {"surface", "core", "adapter", "infra", "data", "docs", "other"}

from scripts.architect.proposal import propose_modules_with_heuristics


def test_flat_repo_fallback(flat_repo: Path):
    modules = propose_modules_with_heuristics(flat_repo)
    slugs = [m["slug"] for m in modules]
    # Flat layout produces a single "core" module covering the root.
    assert "core" in slugs


def test_monorepo_workspaces(monorepo_pnpm: Path):
    modules = propose_modules_with_heuristics(monorepo_pnpm)
    slugs = sorted(m["slug"] for m in modules)
    assert "web" in slugs
    assert "api" in slugs


def test_polyglot_proposal(polyglot_repo: Path):
    modules = propose_modules_with_heuristics(polyglot_repo)
    slugs = sorted(m["slug"] for m in modules if not m["excluded"])
    # python/, web/, scripts/ are top-level
    assert "python" in slugs
    assert "web" in slugs


def test_docs_only_warning_signal(docs_only_repo: Path):
    modules = propose_modules_with_heuristics(docs_only_repo)
    # docs/ excluded, scripts/ kept. Function still returns modules; the
    # "mostly docs" warning is emitted by scan.py, not proposal.py.
    slugs = [m["slug"] for m in modules]
    assert "scripts" in slugs

from scripts.architect.proposal import _merge_small_siblings, _split_dense_folder


def test_merge_small_siblings_combines_two_tiny_python_folders(tmp_path: Path):
    # Build a tiny synthetic repo: two sibling folders, both small, same language.
    (tmp_path / "small_a").mkdir()
    (tmp_path / "small_a" / "x.py").write_text("def a(): return 1\n")
    (tmp_path / "small_b").mkdir()
    (tmp_path / "small_b" / "y.py").write_text("def b(): return 2\n")
    (tmp_path / "pyproject.toml").write_text("[project]\nname='t'\nversion='0.1'\n")

    base = [
        {"slug": "small-a", "display_name": "Small A", "paths": ["small_a/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
        {"slug": "small-b", "display_name": "Small B", "paths": ["small_b/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
    ]
    merged = _merge_small_siblings(tmp_path, base)
    # Expect a single merged module covering both folders.
    assert len(merged) == 1
    assert sorted(merged[0]["paths"]) == ["small_a/", "small_b/"]


def test_merge_keeps_large_modules_separate(tmp_path: Path):
    # Folder A is big enough not to merge.
    (tmp_path / "big").mkdir()
    (tmp_path / "big" / "f.py").write_text("x = 1\n" * 600)  # well over 2000 tokens
    (tmp_path / "small").mkdir()
    (tmp_path / "small" / "g.py").write_text("y = 2\n")

    base = [
        {"slug": "big", "display_name": "Big", "paths": ["big/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
        {"slug": "small", "display_name": "Small", "paths": ["small/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
    ]
    out = _merge_small_siblings(tmp_path, base)
    assert len(out) == 2  # untouched


def test_split_dense_folder_with_multiple_entry_points(tmp_path: Path):
    # Build a folder with 35 files and two entry-point-like markers.
    fold = tmp_path / "dense"
    fold.mkdir()
    for i in range(35):
        (fold / f"f{i}.py").write_text("x = 1\n")
    (fold / "cli_a.py").write_text("def main_a(): pass\n")
    (fold / "cli_b.py").write_text("def main_b(): pass\n")

    base = [{"slug": "dense", "display_name": "Dense", "paths": ["dense/"],
             "role": "other", "excluded": False, "description": None, "pattern": None}]
    entry_points = [
        {"path": "dense/cli_a.py", "label": "ep_a", "kind": "pyproject"},
        {"path": "dense/cli_b.py", "label": "ep_b", "kind": "pyproject"},
    ]
    out = _split_dense_folder(tmp_path, base, entry_points)
    # Expect at least a split proposal (two sub-modules or marker telling caller to split).
    # For v1 implementation we simply tag the module dict with split_hint: True.
    assert out[0].get("split_hint") is True


def test_dependency_and_runtime_dirs_are_excluded(tmp_path: Path):
    """Folders that hold deps, build output, runtime data, or test-coverage
    artefacts should appear as excluded modules (so overview can still
    reference them), never as active modules with their own note.

    Regression test for the langlive-line-oa scan where node_modules,
    logs, reports leaked through as active modules.
    """
    # Real source folder we want kept.
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "a.py").write_text("x = 1\n")

    # Folders that should be excluded.
    excluded_folders = [
        "node_modules",   # JS deps
        "vendor",         # Go / PHP deps
        "venv",           # python deps
        "env",            # python deps
        "logs", "log",    # runtime logs
        "reports",        # runtime reports
        "tmp",            # scratch
        "coverage",       # test coverage output
        ".nyc_output",    # nyc coverage output (hidden — already filtered earlier, but listed for safety)
    ]
    for name in excluded_folders:
        (tmp_path / name).mkdir()
        (tmp_path / name / "marker.txt").write_text("x")

    modules = propose_modules(tmp_path)
    by_slug = {m["slug"]: m for m in modules}

    # src is a real module.
    assert "src" in by_slug, "src/ should appear as a real module"
    assert by_slug["src"]["excluded"] is False

    # Each non-hidden folder above should appear (slugified) with excluded=True.
    # Hidden folders (starting with .) are filtered out entirely upstream — they
    # never become module candidates, so we do not assert their presence.
    expected_excluded_slugs = {
        "node-modules", "vendor", "venv", "env",
        "logs", "log", "reports", "tmp", "coverage",
    }
    for slug in expected_excluded_slugs:
        assert slug in by_slug, f"{slug} should appear as a module entry"
        assert by_slug[slug]["excluded"] is True, (
            f"{slug} should be excluded (dependency/runtime/build dir)"
        )
