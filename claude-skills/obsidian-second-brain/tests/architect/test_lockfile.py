from pathlib import Path

from scripts.architect.lockfile import Lockfile, field_was_user_edited, hash_value, write_lockfile, load_lockfile


def test_hash_is_stable():
    assert hash_value("hello") == hash_value("hello")
    assert hash_value("hello") != hash_value("world")


def test_field_user_edited_detection(tmp_path: Path):
    lock = Lockfile(version=1, scanner_version="0.1.0", fields={
        "modules.auth.display_name": {"hash": hash_value("Auth"), "value": "Auth"}
    }, note_blocks={})
    # Current manifest still has the LLM-written value: not user-edited.
    assert field_was_user_edited(lock, "modules.auth.display_name", current_value="Auth") is False
    # Current manifest has a different value: user edited it.
    assert field_was_user_edited(lock, "modules.auth.display_name", current_value="Authentication") is True


def test_lockfile_round_trip(tmp_path: Path):
    lock = Lockfile(
        version=1,
        scanner_version="0.1.0",
        fields={"modules.auth.role": {"hash": hash_value("core"), "value": "core"}},
        note_blocks={"modules/auth.md": {"what-it-does": {"hash": hash_value("paragraph")}}},
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.fields["modules.auth.role"]["value"] == "core"
    assert loaded.note_blocks["modules/auth.md"]["what-it-does"]["hash"] == hash_value("paragraph")


def test_v2_lockfile_round_trip_with_sections(tmp_path: Path):
    from scripts.architect.lockfile import Lockfile, hash_value, load_lockfile, write_lockfile
    lock = Lockfile(
        version=2,
        scanner_version="0.2.0",
        fields={},
        note_blocks={},
        sections={
            "features": {"signal-hash": hash_value("sig"), "lang": "zh-TW",
                         "note-blocks-hash": hash_value("nb"), "last-generated": "2026-05-27T10:00:00Z"},
        },
        functions={
            "cli/main": {"source-hash": hash_value("src"), "last-generated": "2026-05-27T10:00:00Z"},
        },
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.version == 4
    assert loaded.sections["features"]["lang"] == "zh-TW"
    assert loaded.functions["cli/main"]["source-hash"].startswith("sha256:")


def test_v1_lockfile_migrates_on_load(tmp_path: Path):
    """Loading a v1 lockfile should yield version=4 with empty sections/functions."""
    import json
    from scripts.architect.lockfile import load_lockfile
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 1,
        "scanner_version": "0.1.0",
        "fields": {"modules.auth.role": {"hash": "sha256:abc", "value": "core"}},
        "note_blocks": {"modules/auth.md": {"what-it-does": {"hash": "sha256:def"}}},
    }))
    loaded = load_lockfile(target)
    assert loaded.version == 4
    assert loaded.sections == {}
    assert loaded.functions == {}
    # Preserved.
    assert loaded.fields["modules.auth.role"]["value"] == "core"


def test_section_signal_was_changed(tmp_path: Path):
    from scripts.architect.lockfile import Lockfile, hash_value, section_signal_was_changed
    lock = Lockfile(
        version=2,
        scanner_version="0.2.0",
        fields={},
        note_blocks={},
        sections={"roadmap": {"signal-hash": hash_value("X"), "lang": "en",
                              "note-blocks-hash": "", "last-generated": ""}},
        functions={},
    )
    # Signal matches and lang matches: unchanged.
    assert section_signal_was_changed(lock, "roadmap", current_signal="X", current_lang="en") is False
    # Signal differs.
    assert section_signal_was_changed(lock, "roadmap", current_signal="Y", current_lang="en") is True
    # Lang differs (counts as changed).
    assert section_signal_was_changed(lock, "roadmap", current_signal="X", current_lang="zh-TW") is True
    # Missing section: changed (treat as first-run).
    assert section_signal_was_changed(lock, "features", current_signal="anything", current_lang="en") is True


def test_v3_schema_with_frame_marker(tmp_path: Path):
    """v3 adds a `frame` field declaring which architect version produced this lockfile."""
    import json
    from scripts.architect.lockfile import Lockfile, load_lockfile, write_lockfile
    lock = Lockfile(
        version=3,
        scanner_version="0.3.0",
        fields={},
        note_blocks={},
        sections={},
        functions={},
        frame="judgment-v3",
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    data = json.loads(target.read_text())
    assert data["frame"] == "judgment-v3"
    loaded = load_lockfile(target)
    assert loaded.frame == "judgment-v3"
    assert loaded.version == 4


def test_v2_lockfile_migrates_to_v3_on_load(tmp_path: Path):
    """Loading a v2 lockfile should yield version=4 with frame='description-v2' (legacy marker)."""
    import json
    from scripts.architect.lockfile import load_lockfile, CURRENT_SCHEMA
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 2,
        "scanner_version": "0.2.0",
        "fields": {},
        "note_blocks": {},
        "sections": {"features": {"signal-hash": "sha256:abc", "lang": "en"}},
        "functions": {},
    }))
    loaded = load_lockfile(target)
    assert loaded.version == CURRENT_SCHEMA == 4
    # v2 entries preserved; frame defaults to legacy marker.
    assert loaded.sections["features"]["signal-hash"] == "sha256:abc"
    assert loaded.frame == "description-v2"


def test_v4_schema_with_report_frame(tmp_path: Path):
    """v4 lockfile defaults to frame='report-v4'."""
    import json
    from scripts.architect.lockfile import Lockfile, load_lockfile, write_lockfile, CURRENT_SCHEMA
    assert CURRENT_SCHEMA == 4
    lock = Lockfile(
        version=4,
        scanner_version="0.4.0",
        fields={},
        note_blocks={},
        sections={"overview": {"signal-hash": "sha256:abc", "lang": "zh-TW"}},
        functions={},
        frame="report-v4",
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.version == 4
    assert loaded.frame == "report-v4"


def test_v3_lockfile_migrates_to_v4(tmp_path: Path):
    """Loading a v3 lockfile yields version=4 with frame preserved (judgment-v3)."""
    import json
    from scripts.architect.lockfile import load_lockfile, CURRENT_SCHEMA
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 3,
        "scanner_version": "0.3.0",
        "fields": {},
        "note_blocks": {},
        "sections": {"features": {"signal-hash": "x", "lang": "zh-TW"}},
        "functions": {},
        "frame": "judgment-v3",
    }))
    loaded = load_lockfile(target)
    assert loaded.version == CURRENT_SCHEMA == 4
    assert loaded.frame == "judgment-v3"  # preserved until v4 migration runs
    assert loaded.sections["features"]["signal-hash"] == "x"


def test_v2_lockfile_still_migrates_through_to_v4(tmp_path: Path):
    """A pre-v3 vault should still load (frame defaults to description-v2)."""
    import json
    from scripts.architect.lockfile import load_lockfile
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 2,
        "scanner_version": "0.2.0",
        "fields": {},
        "note_blocks": {},
        "sections": {},
        "functions": {},
    }))
    loaded = load_lockfile(target)
    assert loaded.version == 4
    assert loaded.frame == "description-v2"


def test_lockfile_has_ai_flows_field(tmp_path: Path):
    """v4.1 — Lockfile has an `ai_flows` dict tracking per-flow + per-prompt source-hash."""
    import json
    from scripts.architect.lockfile import Lockfile, load_lockfile, write_lockfile
    lock = Lockfile(
        version=4,
        scanner_version="0.4.1",
        fields={},
        note_blocks={},
        sections={},
        functions={},
        frame="report-v4",
        ai_flows={
            "lang-ai-customer": {
                "signal-hash": "sha256:abc",
                "lang": "zh-TW",
                "framework": "langgraph",
                "node-blocks-hash": "sha256:def",
                "last-generated": "2026-05-28T10:00:00Z",
                "prompts": {
                    "intent_classifier": {
                        "source-hash": "sha256:p1",
                        "source": "backend/engines/langgraph/prompts/intent.py:1-25",
                        "is_dynamic": False,
                    },
                    "rag_answer": {
                        "source-hash": "sha256:p2",
                        "source": "backend/engines/langgraph/prompts/answer.py:30-90",
                        "is_dynamic": False,
                    },
                    "safety_check": {
                        "source-hash": "sha256:dynamic",
                        "source": "(see ai-flow note `## Prompts` body)",
                        "is_dynamic": True,
                    },
                },
            },
        },
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert "lang-ai-customer" in loaded.ai_flows
    assert loaded.ai_flows["lang-ai-customer"]["framework"] == "langgraph"
    assert loaded.ai_flows["lang-ai-customer"]["prompts"]["intent_classifier"]["source-hash"] == "sha256:p1"
    assert loaded.ai_flows["lang-ai-customer"]["prompts"]["safety_check"]["is_dynamic"] is True


def test_load_v4_lockfile_without_ai_flows_yields_empty_dict(tmp_path: Path):
    """Old v4 lockfile (no ai_flows key) should still load — ai_flows defaults to {}."""
    import json
    from scripts.architect.lockfile import load_lockfile
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 4,
        "scanner_version": "0.4.0",
        "fields": {},
        "note_blocks": {},
        "sections": {},
        "functions": {},
        "frame": "report-v4",
    }))
    loaded = load_lockfile(target)
    assert loaded.ai_flows == {}


def test_ai_flow_prompt_drift_helper():
    """Lockfile helper: detect whether a prompt's source-hash changed."""
    from scripts.architect.lockfile import Lockfile, ai_flow_prompt_changed
    lock = Lockfile(
        version=4, scanner_version="0.4.1",
        fields={}, note_blocks={}, sections={}, functions={}, frame="report-v4",
        ai_flows={
            "lang-ai-customer": {
                "prompts": {
                    "intent_classifier": {"source-hash": "sha256:old"},
                },
            },
        },
    )
    # Same hash → not changed
    assert ai_flow_prompt_changed(lock, "lang-ai-customer", "intent_classifier", "sha256:old") is False
    # Different hash → changed
    assert ai_flow_prompt_changed(lock, "lang-ai-customer", "intent_classifier", "sha256:new") is True
    # Missing prompt → changed (treat as first-time-generated)
    assert ai_flow_prompt_changed(lock, "lang-ai-customer", "new_prompt", "sha256:anything") is True
    # Missing flow → changed
    assert ai_flow_prompt_changed(lock, "nonexistent-flow", "intent_classifier", "sha256:x") is True


def test_lockfile_sections_features_slot_round_trip(tmp_path):
    """sections.features round-trips through Lockfile.save → load with v4.2 fields."""
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.sections["features"] = {
        "signal-hash": "sha256:abc123",
        "lang": "zh-TW",
        "last-generated": "2026-05-29",
        "commit": "deadbeef",
        "feature-count": 32,
        "deprecated-count": 3,
        "doc-sync-score": 0.87,
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)

    loaded = Lockfile.load(p)
    assert loaded.sections["features"]["feature-count"] == 32
    assert loaded.sections["features"]["doc-sync-score"] == 0.87
    assert loaded.sections["features"]["signal-hash"] == "sha256:abc123"


def test_lockfile_ai_memory_slot_round_trip(tmp_path):
    """sections.ai_memory round-trips through Lockfile.save → load (v4.3)."""
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.ai_memory = {
        "signal-hash": "sha256:abc",
        "lang": "zh-TW",
        "last-generated": "2026-05-29",
        "commit": "d4f5",
        "memory_flows": 1,
        "stateless_flows": 1,
        "backend": "redis",
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)
    loaded = Lockfile.load(p)
    assert loaded.ai_memory["memory_flows"] == 1
    assert loaded.ai_memory["backend"] == "redis"


def test_lockfile_ai_rag_slot_round_trip(tmp_path):
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.ai_rag = {
        "signal-hash": "sha256:def",
        "lang": "zh-TW",
        "last-generated": "2026-05-29",
        "commit": "d4f5",
        "rag_flows_read": 1,
        "rag_flows_write": 1,
        "vector_store": "weaviate",
        "embedding_aligned": False,
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)
    loaded = Lockfile.load(p)
    assert loaded.ai_rag["embedding_aligned"] is False
    assert loaded.ai_rag["vector_store"] == "weaviate"


def test_lockfile_ai_companion_slot_round_trip(tmp_path):
    """sections.ai_companion round-trips through Lockfile.save → load (v4.6)."""
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.ai_companion = {
        "archetype": "ai-companion",
        "confidence": "high",
        "layers": {
            "character-card": {
                "signal-hash": "sha256:abc", "lang": "zh-TW",
                "last-generated": "2026-05-29", "commit": "deadbeef",
                "card-count": 6, "schema-version": "v1",
            },
            "companion-overview": {
                "signal-hash": "sha256:def", "layers-stable": 2,
                "layers-wip": 1, "layers-missing": 1,
            },
        },
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)
    loaded = Lockfile.load(p)
    assert loaded.ai_companion["archetype"] == "ai-companion"
    assert loaded.ai_companion["layers"]["character-card"]["card-count"] == 6
    assert loaded.ai_companion["layers"]["companion-overview"]["layers-stable"] == 2
