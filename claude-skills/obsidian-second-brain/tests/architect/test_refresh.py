from pathlib import Path

import pytest

from scripts.architect.refresh import RefreshAction, decide_module_refresh


def test_new_module_regenerates(single_lang_python: Path):
    action = decide_module_refresh(
        module={"slug": "newmod", "paths": ["src/newmod/"]},
        lockfile_modules={},
        old_commit=None,
        new_commit="abc",
        repo_root=single_lang_python,
        force=False,
    )
    assert action == RefreshAction.GENERATE


def test_path_change_regenerates(single_lang_python: Path):
    action = decide_module_refresh(
        module={"slug": "auth", "paths": ["src/auth-new/"]},
        lockfile_modules={"auth": {"paths": ["src/auth/"]}},
        old_commit="abc",
        new_commit="def",
        repo_root=single_lang_python,
        force=False,
    )
    assert action == RefreshAction.REGENERATE


def test_force_always_regenerates(single_lang_python: Path):
    action = decide_module_refresh(
        module={"slug": "auth", "paths": ["src/auth/"]},
        lockfile_modules={"auth": {"paths": ["src/auth/"]}},
        old_commit="abc",
        new_commit="abc",
        repo_root=single_lang_python,
        force=True,
    )
    assert action == RefreshAction.REGENERATE


def test_unchanged_module_skips(single_lang_python: Path):
    # Same commit, same paths, no force: skip.
    action = decide_module_refresh(
        module={"slug": "auth", "paths": ["src/auth/"]},
        lockfile_modules={"auth": {"paths": ["src/auth/"]}},
        old_commit="abc",
        new_commit="abc",
        repo_root=single_lang_python,
        force=False,
    )
    assert action == RefreshAction.SKIP


def test_decide_section_refresh_first_run():
    from scripts.architect.lockfile import Lockfile
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0")
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="en", force=False, refresh_flag=False)
    assert action == RefreshAction.GENERATE


def test_decide_section_refresh_unchanged_skips():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(
        version=2,
        scanner_version="0.2.0",
        sections={"features": {"signal-hash": hash_value("X"), "lang": "en",
                                "note-blocks-hash": "", "last-generated": ""}},
    )
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="en", force=False, refresh_flag=False)
    assert action == RefreshAction.SKIP


def test_decide_section_refresh_signal_changed():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0",
                    sections={"features": {"signal-hash": hash_value("X"), "lang": "en", "note-blocks-hash": "", "last-generated": ""}})
    action = decide_section_refresh(lock, section="features", current_signal="Y", current_lang="en", force=False, refresh_flag=False)
    assert action == RefreshAction.REGENERATE


def test_decide_section_refresh_lang_changed():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0",
                    sections={"features": {"signal-hash": hash_value("X"), "lang": "en", "note-blocks-hash": "", "last-generated": ""}})
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="zh-TW", force=False, refresh_flag=False)
    assert action == RefreshAction.REGENERATE


def test_decide_section_refresh_force_always_regenerates():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0",
                    sections={"features": {"signal-hash": hash_value("X"), "lang": "en", "note-blocks-hash": "", "last-generated": ""}})
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="en", force=True, refresh_flag=False)
    assert action == RefreshAction.REGENERATE
