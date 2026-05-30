"""Detect AI companion-bot archetype (Character Card / World / Storyline / Memory).

Auto-detect rule: BOTH character-card AND storyline signals must be present.
This avoids false positives on generic LLM-wrapper projects that have only
persona definitions.

Frontmatter override: `archetype: ai-companion` in project hub forces all 4
layers present with confidence='stated' regardless of code evidence. Used for
projects with non-standard directory names.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


# Alias dir names per layer.
_CHARACTER_DIR_NAMES = ("characters", "personas", "bots", "companions")
_WORLD_DIR_NAMES = ("worlds", "lore")          # also matches "world_*"
_STORYLINE_FILENAME_PATTERNS = (
    r"^storyline",
    r"^plot",
    r"^narrative",
    r"^script",
    r".*_dsl\.py$",
)
_STORYLINE_KEYWORDS = ("storyline", "plot", "beat", "progression")

# Files extensions that count as definition payloads.
_DEFINITION_EXTS = (".py", ".json", ".yaml", ".yml")


@dataclass
class LayerEvidence:
    present: bool = False
    root_paths: list[str] = field(default_factory=list)
    artifact_files: list[str] = field(default_factory=list)
    storyline_dsl_file: str | None = None
    llm_libs: list[str] = field(default_factory=list)
    confidence: str = "medium"   # 'speculation' | 'medium' | 'high' | 'stated'


@dataclass
class CompanionDetection:
    archetype: str                            # 'ai-companion' | 'none'
    confidence: str                           # 'stated' | 'high' | 'medium'
    layers: dict[str, LayerEvidence] = field(default_factory=dict)
    triggers: list[str] = field(default_factory=list)


def detect_companion_archetype(
    repo_root: Path,
    hub_frontmatter: dict | None = None,
) -> CompanionDetection:
    repo_root = repo_root.resolve()

    char_ev = _detect_character_layer(repo_root)
    world_ev = _detect_world_layer(repo_root)
    storyline_ev = _detect_storyline_layer(repo_root)
    # Memory layer: defer to v4.3 detect_memory (lightly invoked).
    memory_ev = _detect_memory_layer_stub(repo_root)

    layers = {
        "character-card": char_ev,
        "world": world_ev,
        "storyline": storyline_ev,
        "memory": memory_ev,
    }

    # Frontmatter override.
    if hub_frontmatter and hub_frontmatter.get("archetype") == "ai-companion":
        for ev in layers.values():
            ev.present = True
            ev.confidence = "stated" if ev.root_paths else "speculation"
        return CompanionDetection(
            archetype="ai-companion",
            confidence="stated",
            layers=layers,
            triggers=["frontmatter override: archetype: ai-companion"],
        )

    # Auto-detect: character AND storyline both required.
    if char_ev.present and storyline_ev.present:
        triggers = [f"character dir {char_ev.root_paths[0]}",
                    f"storyline file {storyline_ev.artifact_files[0]}"]
        return CompanionDetection(
            archetype="ai-companion", confidence="high",
            layers=layers, triggers=triggers,
        )

    return CompanionDetection(archetype="none", confidence="medium", layers=layers)


def _detect_character_layer(repo_root: Path) -> LayerEvidence:
    ev = LayerEvidence()
    for dir_name in _CHARACTER_DIR_NAMES:
        for d in repo_root.rglob(dir_name):
            if not d.is_dir() or any(part.startswith(".") for part in d.parts):
                continue
            payload = [
                p for p in d.rglob("*")
                if p.is_file() and p.suffix in _DEFINITION_EXTS
                and "__pycache__" not in p.parts
            ]
            if not payload:
                continue
            ev.present = True
            ev.confidence = "high"
            ev.root_paths.append(d.relative_to(repo_root).as_posix())
            for f in payload[:5]:
                ev.artifact_files.append(f.relative_to(repo_root).as_posix())
            return ev
    return ev


def _detect_world_layer(repo_root: Path) -> LayerEvidence:
    ev = LayerEvidence()
    for dir_name in _WORLD_DIR_NAMES + ("world_*",):
        for d in repo_root.rglob(dir_name):
            if not d.is_dir() or any(part.startswith(".") for part in d.parts):
                continue
            payload = [
                p for p in d.rglob("*")
                if p.is_file() and p.suffix in _DEFINITION_EXTS
            ]
            if not payload:
                continue
            ev.present = True
            ev.confidence = "high"
            ev.root_paths.append(d.relative_to(repo_root).as_posix())
            for f in payload[:5]:
                ev.artifact_files.append(f.relative_to(repo_root).as_posix())
            return ev
    return ev


def _detect_storyline_layer(repo_root: Path) -> LayerEvidence:
    ev = LayerEvidence()
    patterns = [re.compile(p) for p in _STORYLINE_FILENAME_PATTERNS]
    for py in repo_root.rglob("*.py"):
        if any(part.startswith(".") or part == "__pycache__" for part in py.parts):
            continue
        name = py.name
        if any(p.match(name) for p in patterns):
            # Confirm keyword presence inside file.
            try:
                text = py.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if any(kw in text.lower() for kw in _STORYLINE_KEYWORDS):
                ev.present = True
                ev.confidence = "high"
                rel = py.relative_to(repo_root).as_posix()
                ev.artifact_files.append(rel)
                if name.endswith("_dsl.py") or "dsl" in name.lower():
                    ev.storyline_dsl_file = rel
                if not ev.root_paths:
                    ev.root_paths.append(py.parent.relative_to(repo_root).as_posix())
                return ev
    return ev


def _detect_memory_layer_stub(repo_root: Path) -> LayerEvidence:
    """Light wrapper. Full v4.3 detect_memory is invoked separately in Phase 1
    of scan.py; this stub only flags presence based on import signals."""
    ev = LayerEvidence()
    for py in repo_root.rglob("*.py"):
        if any(part.startswith(".") or part == "__pycache__" for part in py.parts):
            continue
        try:
            text = py.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if "openai" in text or "anthropic" in text or "google.generativeai" in text:
            ev.llm_libs.append("openai/anthropic/google")
            ev.present = True
            ev.confidence = "medium"
            return ev
    return ev
