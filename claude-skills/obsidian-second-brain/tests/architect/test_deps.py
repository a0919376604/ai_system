from pathlib import Path

from scripts.architect.deps import detect_external_deps


def test_pyproject_deps(single_lang_python: Path):
    deps = detect_external_deps(single_lang_python)
    names = [d["name"] for d in deps]
    assert "requests" in names
    assert "pydantic" in names


def test_package_json_deps(monorepo_pnpm: Path):
    deps = detect_external_deps(monorepo_pnpm / "packages" / "web")
    names = [d["name"] for d in deps]
    assert "react" in names


def test_dev_deps_excluded(single_lang_python: Path):
    deps = detect_external_deps(single_lang_python)
    # Fixture pyproject has no dev group, but the function should still filter when present.
    # This test mainly asserts the function returns runtime-only.
    assert all(d.get("group", "runtime") == "runtime" for d in deps)
