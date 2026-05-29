"""Personas signal collector + prompt builder + section renderer.

Source priority: explicit README '## Personas' / '## 使用者型態' section first;
otherwise LLM inference (handled by the agent via `build_personas_prompt`).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

# H2 aliases that count as a personas section.
_PERSONA_ALIASES = (
    "personas", "user types", "user roles", "使用者型態", "使用者角色",
)


@dataclass
class PersonaSignal:
    has_explicit_section: bool
    raw_text: str             # markdown body under the matched H2, stripped


@dataclass
class Persona:
    slug: str
    title: str
    who: str
    goals: list[str]
    touchpoints: list[str]
    frequency: str
    pain_points: list[str]
    confidence: str = "medium"   # stated | high | medium | speculation


def collect_persona_signal(repo_root: Path) -> PersonaSignal:
    readme = repo_root / "README.md"
    if not readme.is_file():
        return PersonaSignal(has_explicit_section=False, raw_text="")
    try:
        text = readme.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return PersonaSignal(has_explicit_section=False, raw_text="")
    h2_re = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
    matches = list(h2_re.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        if title not in _PERSONA_ALIASES:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end].strip()
        return PersonaSignal(has_explicit_section=True, raw_text=body)
    return PersonaSignal(has_explicit_section=False, raw_text="")


def build_personas_prompt(
    *,
    project: str,
    readme_excerpt: str,
    agents_md_excerpt: str,
    features_summary: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 title / who / goals / pain_points 等散文。"
            "Touchpoints (endpoint 路徑、CLI 命令) 保持英文。"
        )
        schema_fields = ("誰", "目標", "觸點", "頻率", "主要痛點")
    else:
        lang_directive = (
            "Write title / who / goals / pain_points in English. "
            "Touchpoints (endpoint paths, CLI commands) stay verbatim."
        )
        schema_fields = ("Who", "Goals", "Touchpoints", "Frequency", "Pain points")

    return "\n".join([
        f"You are documenting the personas for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Rules",
        "- Return 2–5 personas — the people who interact with this product.",
        "- For each persona, fill ALL the following fields: " + ", ".join(schema_fields) + ".",
        "- Touchpoints must be concrete (endpoint paths / pages / events), not vague labels.",
        "- Mark `confidence` as `stated` if you cite README/AGENTS.md, `medium` if you inferred.",
        "",
        "Return strict JSON: a list of personas, each with keys "
        "`slug, title, who, goals (list), touchpoints (list), frequency, pain_points (list), confidence`.",
        "",
        "## README excerpt",
        readme_excerpt[:5000],
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
        "",
        "## features.md summary",
        features_summary[:3000],
    ])


_FIELD_LABELS = {
    "en": {
        "who": "Who",
        "goals": "Goals",
        "touchpoints": "Touchpoints",
        "frequency": "Frequency",
        "pain": "Pain points",
    },
    "zh-TW": {
        "who": "誰",
        "goals": "目標",
        "touchpoints": "觸點",
        "frequency": "頻率",
        "pain": "主要痛點",
    },
}


def render_personas_section(personas: list[Persona], lang: str = "en") -> str:
    """Render personas as H3-per-persona markdown."""
    labels = _FIELD_LABELS.get(lang, _FIELD_LABELS["en"])
    out: list[str] = []
    for p in personas:
        out.append(f"### {p.title}")
        out.append(f"- **{labels['who']}:** {p.who}")
        if p.goals:
            out.append(f"- **{labels['goals']}:**")
            for g in p.goals:
                out.append(f"  - {g}")
        if p.touchpoints:
            out.append(f"- **{labels['touchpoints']}:** {', '.join(p.touchpoints)}")
        if p.frequency:
            out.append(f"- **{labels['frequency']}:** {p.frequency}")
        if p.pain_points:
            out.append(f"- **{labels['pain']}:**")
            for pp in p.pain_points:
                out.append(f"  - {pp}")
        out.append(f"- _confidence: {p.confidence}_")
        out.append("")
    return "\n".join(out).rstrip() + "\n"
