"""Lockfile: hash-based tracking of LLM-written content.

For each LLM-written manifest field, note section, and narrative-section
generated note, we store a SHA-256 hash so refresh can decide regenerate
vs preserve.

Schema versions:
  v1: fields + note_blocks (modules only).
  v2: adds `sections` (per-section narrative notes) and `functions`
      (optional --functions=public layer). Loading v1 silently migrates.
  v3: adds `frame` marker (`description-v2` legacy vs `judgment-v3`).
  v4: default frame is `report-v4`; old frames are preserved on load.
  v4.1: adds `ai_flows` tracking per-flow + per-prompt source hashes.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

CURRENT_SCHEMA = 4


@dataclass
class Lockfile:
    version: int
    scanner_version: str
    fields: dict = field(default_factory=dict)
    note_blocks: dict = field(default_factory=dict)
    sections: dict = field(default_factory=dict)
    functions: dict = field(default_factory=dict)
    frame: str = "description-v2"  # description-v2 (legacy) | judgment-v3
    ai_flows: dict = field(
        default_factory=dict
    )  # v4.1 — per-flow + per-prompt source-hash tracking
    # v4.3 — cross-flow AI memory + RAG lenses (additive; no schema bump)
    ai_memory: dict = field(default_factory=dict)
    ai_rag: dict = field(default_factory=dict)

    def save(self, path: Path) -> None:
        write_lockfile(self, path)

    @classmethod
    def load(cls, path: Path) -> "Lockfile | None":
        return load_lockfile(path)


def hash_value(s: str) -> str:
    """Return 'sha256:<hex>' for stable comparison."""
    return "sha256:" + hashlib.sha256(s.encode("utf-8")).hexdigest()


def load_lockfile(path: Path) -> Lockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    incoming_version = data.get("version", 1)
    # Frame default based on which version produced the file.
    # Lets the v3->v4 migration step (later) detect and rewrite frame after upgrading content.
    if "frame" in data:
        frame = data["frame"]
    elif incoming_version >= 4:
        frame = "report-v4"
    elif incoming_version == 3:
        frame = "judgment-v3"
    else:
        frame = "description-v2"
    return Lockfile(
        version=CURRENT_SCHEMA,
        scanner_version=data.get("scanner_version", "0.0.0"),
        fields=data.get("fields", {}),
        note_blocks=data.get("note_blocks", {}),
        sections=data.get("sections", {}),
        functions=data.get("functions", {}),
        frame=frame,
        ai_flows=data.get("ai_flows", {}),
        ai_memory=data.get("ai_memory", {}),
        ai_rag=data.get("ai_rag", {}),
    )


def write_lockfile(lock: Lockfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = asdict(lock)
    payload["version"] = CURRENT_SCHEMA
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))


def field_was_user_edited(lock: Lockfile, field_key: str, current_value: str) -> bool:
    """True iff the current value differs from the LLM-written value recorded in the lockfile.

    If the field is not in the lockfile (e.g. first-run), returns False
    (treat as LLM-territory; safe because lockfile will be updated on first write).
    """
    record = lock.fields.get(field_key)
    if record is None:
        return False
    return record["hash"] != hash_value(current_value)


def section_signal_was_changed(
    lock: Lockfile, section_name: str, current_signal: str, current_lang: str
) -> bool:
    """True iff the section's signal hash or lang differs from the lockfile entry.

    Missing section returns True (first-run = changed = should regenerate).
    """
    record = lock.sections.get(section_name)
    if record is None:
        return True
    if record.get("lang") != current_lang:
        return True
    return record.get("signal-hash") != hash_value(current_signal)


def ai_flow_prompt_changed(
    lock: Lockfile, flow_slug: str, prompt_name: str, current_source_hash: str
) -> bool:
    """True iff the prompt's source-hash differs from what the lockfile recorded.

    Missing flow or missing prompt entry also counts as "changed" (treat as first-time
    materialization → regenerate the sentinel block).
    """
    flow = lock.ai_flows.get(flow_slug, {})
    prompts = flow.get("prompts", {})
    record = prompts.get(prompt_name)
    if record is None:
        return True
    return record.get("source-hash") != current_source_hash
