"""Jobs-to-be-done signal collector + prompt + section renderer."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_JOB_ALIASES = (
    "jobs to be done", "jtbd", "user jobs", "使用者工作", "工作清單",
)


@dataclass
class JobSignal:
    has_explicit_section: bool
    raw_text: str


@dataclass
class Job:
    slug: str
    persona: str              # persona title (free-text)
    jtbd: str                 # "When X, the user wants Y so that Z"
    maturity: str             # Alpha | Beta | GA
    friction_points: list[str]
    related_features: list[str]
    related_flows: list[str]
    confidence: str = "medium"


def collect_job_signal(repo_root: Path) -> JobSignal:
    readme = repo_root / "README.md"
    if not readme.is_file():
        return JobSignal(has_explicit_section=False, raw_text="")
    try:
        text = readme.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return JobSignal(has_explicit_section=False, raw_text="")
    h2_re = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
    matches = list(h2_re.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        if title not in _JOB_ALIASES:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        return JobSignal(has_explicit_section=True, raw_text=text[body_start:body_end].strip())
    return JobSignal(has_explicit_section=False, raw_text="")


def build_jobs_prompt(
    *,
    project: str,
    personas_summary: str,
    features_summary: str,
    readme_excerpt: str,
    agents_md_excerpt: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 JTBD 與 friction_points 散文。"
            "Slug、related_features 中的 anchor、persona 標題保持英文或既有命名。"
        )
    else:
        lang_directive = (
            "Write JTBD and friction_points in English. Slugs stay ascii-lowercase-hyphen."
        )

    return "\n".join([
        f"You are documenting Jobs-to-be-done (JTBD) for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Rules",
        "- 3–6 jobs covering the main user journeys.",
        "- Each job belongs to one of the personas listed below.",
        "- JTBD format: 'When <context>, the user wants <outcome> so that <reason>'.",
        "- Each job MUST declare `maturity` as one of: `Alpha` (partial / behind flag), "
        "`Beta` (works but rough), `GA` (fully delivered).",
        "- Each job lists 1–4 concrete `friction_points` (specific things that suck today).",
        "- `related_features` / `related_flows` are wikilinks like `[[features#Section]]`.",
        "- `confidence`: `stated` if README/AGENTS.md spells out, else `medium` or `speculation`.",
        "",
        "Return strict JSON: a list of jobs.",
        "",
        "## Personas available",
        personas_summary[:3000],
        "",
        "## Features summary",
        features_summary[:3000],
        "",
        "## README excerpt",
        readme_excerpt[:5000],
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
    ])


def render_jobs_section(jobs: list[Job], lang: str = "en") -> str:
    out: list[str] = []
    for j in jobs:
        out.append(f"### {j.jtbd}" if lang == "en" else f"### {j.jtbd}")
        out.append(f"- **Persona:** {j.persona}")
        out.append(f"- **JTBD:** {j.jtbd}")
        out.append(f"- **Maturity:** {j.maturity}")
        if j.friction_points:
            fp_label = "Friction" if lang == "en" else "摩擦點"
            out.append(f"- **{fp_label}:**")
            for fp in j.friction_points:
                out.append(f"  - {fp}")
        if j.related_features:
            out.append(f"- **Related features:** {', '.join(j.related_features)}")
        if j.related_flows:
            out.append(f"- **Related flows:** {', '.join(j.related_flows)}")
        out.append(f"- _confidence: {j.confidence}_")
        out.append("")
    return "\n".join(out).rstrip() + "\n"
