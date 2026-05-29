"""User flows signal collector + prompt + section renderer."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_FLOW_ALIASES = (
    "user flows", "user journeys", "使用路徑", "使用流程", "user flow",
)


@dataclass
class FlowSignal:
    has_explicit_section: bool
    raw_text: str


@dataclass
class Flow:
    slug: str
    title: str
    personas: list[str]
    steps_mermaid: str        # raw mermaid body (without ```mermaid fences)
    friction_assessment: list[str]
    maturity: str             # Alpha | Beta | GA
    related_modules: list[str]
    confidence: str = "medium"


def collect_flow_signal(repo_root: Path) -> FlowSignal:
    readme = repo_root / "README.md"
    if not readme.is_file():
        return FlowSignal(has_explicit_section=False, raw_text="")
    try:
        text = readme.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return FlowSignal(has_explicit_section=False, raw_text="")
    h2_re = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
    matches = list(h2_re.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        if title not in _FLOW_ALIASES:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        return FlowSignal(has_explicit_section=True, raw_text=text[body_start:body_end].strip())
    return FlowSignal(has_explicit_section=False, raw_text="")


def build_flows_prompt(
    *,
    project: str,
    personas_summary: str,
    api_surface_summary: str,
    readme_excerpt: str,
    agents_md_excerpt: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 title / friction_assessment 散文。"
            "Mermaid 圖內的 actor 名稱與 message 字串依實際情境選用 (zh 或 en)。"
        )
    else:
        lang_directive = (
            "Write title / friction_assessment in English. Mermaid actor names "
            "match real-world labels (English unless the system uses other languages)."
        )

    return "\n".join([
        f"You are documenting end-to-end user flows for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Rules",
        "- 2–5 flows. Each is a *user-visible* path through the product, not a "
        "  data-pipeline diagram for engineers.",
        "- Each flow MUST include a `steps_mermaid` value — a `sequenceDiagram` body "
        "  showing the persona crossing the system. Keep it under 15 messages.",
        "- Each flow MUST list 2–5 `friction_assessment` items — concrete spots that "
        "  feel rough today, with a hint of the underlying mechanism.",
        "- Each flow declares `maturity` as `Alpha | Beta | GA`.",
        "- `related_modules` are wikilinks like `[[modules/backend]]`.",
        "- `confidence` is `stated` only if README spells out this flow.",
        "",
        "Return strict JSON: a list of flows.",
        "",
        "## Personas available",
        personas_summary[:3000],
        "",
        "## API surface summary",
        api_surface_summary[:3000],
        "",
        "## README excerpt",
        readme_excerpt[:5000],
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
    ])


def render_flows_section(flows: list[Flow], lang: str = "en") -> str:
    out: list[str] = []
    for f in flows:
        out.append(f"### {f.title}")
        if f.personas:
            persona_label = "Personas" if lang == "en" else "使用者"
            out.append(f"- **{persona_label}:** {', '.join(f.personas)}")
        out.append("")
        out.append("```mermaid")
        out.append(f.steps_mermaid.strip())
        out.append("```")
        out.append("")
        if f.friction_assessment:
            fric_label = "Friction" if lang == "en" else "摩擦點"
            out.append(f"- **{fric_label}:**")
            for fa in f.friction_assessment:
                out.append(f"  - {fa}")
        out.append(f"- **Maturity:** {f.maturity}")
        if f.related_modules:
            rm_label = "Related modules" if lang == "en" else "相關模組"
            out.append(f"- **{rm_label}:** {', '.join(f.related_modules)}")
        out.append(f"- _confidence: {f.confidence}_")
        out.append("")
    return "\n".join(out).rstrip() + "\n"
