"""Phase 3 — LLM prompt builder for theme synthesis.

Output of the LLM (parsed by the agent) is a JSON list of themes with
fully-specified tasks (description + slug + module-wikilink + acceptance-criteria).
Phase 5 then writes files without further LLM calls.
"""

from __future__ import annotations

import json


def build_synthesis_prompt(
    *,
    candidates: list[dict],
    modules_summary: str,
    project: str,
    output_lang: str,
    max_themes: int = 12,
) -> str:
    """Build the LLM prompt for Phase 3 theme synthesis."""
    if output_lang == "zh-TW":
        lang_directive = (
            "輸出的 title / why / task description / acceptance-criteria 用繁體中文。"
            "Code identifier (檔名、function/class、env var、CLI 字串、URL、wikilink 內檔名段) "
            "保持英文。`slug` 必須 ascii-lowercase-hyphen,≤ 50 字元,動詞起頭。"
        )
    else:
        lang_directive = (
            "Output title / why / task description / acceptance-criteria in English. "
            "Slug must be ascii-lowercase-hyphen, <= 50 chars, verb-first."
        )

    lines = [
        f"You are synthesizing the Roadmap themes for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        f"Group {len(candidates)} candidate signals into {max_themes} or fewer themes. "
        "Each theme bundles related candidates and produces fully-specified tasks.",
        "",
        "Return STRICT JSON (no prose around it) — a list of themes:",
        json.dumps([{
            "slug": "<ascii-lowercase-hyphen, verb-first, ≤50 chars>",
            "title": "<short prose title>",
            "why": "<2-3 sentence rationale; cite candidates>",
            "priority": "<🔴 | 🟡 | 🟢>",
            "effort": "<S | M | L | XL>",
            "evidence": ["<wikilink>", "<wikilink>"],
            "candidate-ids": ["<id>", "<id>"],
            "tasks": [{
                "description": "<short, verb-first, ≤80 chars>",
                "slug": "<ascii-lowercase-hyphen>",
                "module-wikilink": "[[modules/<slug>]]",
                "acceptance-criteria": ["<bullet>", "<bullet>"],
            }],
        }], indent=2, ensure_ascii=False),
        "",
        f"Available modules: {modules_summary}",
        "",
        "Candidates:",
    ]
    for c in candidates:
        lines.append(f"- id={c['id']} kind={c['kind']}")
        lines.append(f"  title: {c['title']}")
        if c.get("evidence"):
            lines.append(f"  evidence: {c['evidence']}")
    return "\n".join(lines)
