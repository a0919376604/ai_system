from pathlib import Path

from scripts.roadmap.lockfile import (
    RoadmapLockfile,
    ThemeEntry,
    TaskEntry,
    hash_signal,
    load_lockfile,
    write_lockfile,
)


def test_hash_signal_is_deterministic():
    sig = {"foo": "bar", "evidence": ["a", "b"]}
    assert hash_signal(sig) == hash_signal(sig)


def test_hash_signal_independent_of_dict_order():
    a = hash_signal({"x": 1, "y": 2})
    b = hash_signal({"y": 2, "x": 1})
    assert a == b


def test_lockfile_round_trip(tmp_path: Path):
    lock = RoadmapLockfile(
        schema_version=1,
        last_synthesis="2026-05-27T19:00:00Z",
        last_architect_commit="344e321",
        themes={
            "ai-engine-pluggability": ThemeEntry(
                title="AI 引擎可插拔化",
                first_materialized="2026-05-27T19:00:00Z",
                last_refreshed="2026-05-27T19:00:00Z",
                signal_source_hash="sha256:abc",
                tasks=["T-001", "T-002"],
                status="active",
            ),
        },
        tasks={
            "T-001": TaskEntry(theme="ai-engine-pluggability", created="2026-05-27T19:00:00Z", slug="add-adapter"),
        },
        next_task_id=3,
    )
    target = tmp_path / "_roadmap.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.themes["ai-engine-pluggability"].title == "AI 引擎可插拔化"
    assert loaded.tasks["T-001"].slug == "add-adapter"
    assert loaded.next_task_id == 3


def test_load_missing_returns_none(tmp_path: Path):
    assert load_lockfile(tmp_path / "nope.json") is None


def test_theme_status_options():
    e = ThemeEntry(title="x", first_materialized="t", last_refreshed="t",
                   signal_source_hash="h", tasks=[], status="active")
    assert e.status in ("active", "stale", "needs-refresh")


def test_allocate_task_id(tmp_path: Path):
    """Lockfile helper that returns the next task ID and increments the counter."""
    from scripts.roadmap.lockfile import allocate_task_id
    lock = RoadmapLockfile(schema_version=1, last_synthesis="", last_architect_commit="",
                            themes={}, tasks={}, next_task_id=7)
    tid = allocate_task_id(lock)
    assert tid == "T-007"  # zero-padded to 3 digits
    assert lock.next_task_id == 8

    tid2 = allocate_task_id(lock)
    assert tid2 == "T-008"
    assert lock.next_task_id == 9
