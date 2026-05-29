"""Phase 2 — research linking helpers.

Provides:
- keyword_prefilter() — deterministic grep over project-scoped + recent vault-wide Research/
- build_relevance_prompt() — builds the LLM prompt for Phase 2c (agent runs the LLM)

The LLM relevance call itself happens in the slash command body (agent).
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from pathlib import Path

# Cap so a single candidate can't dominate the downstream LLM context window.
_DEFAULT_MAX_MATCHES = 10
_SUMMARY_EXCERPT_CHARS = 600
_TEXT_EXTENSIONS = {".md"}


@dataclass(frozen=True)
class ResearchMatch:
    candidate_id: str
    path: str               # vault-relative posix path
    summary_excerpt: str    # first ~600 chars of `## Summary` block or topic, for the LLM


def keyword_prefilter(
    *,
    candidate_id: str,
    keywords: list[str],
    vault_root: Path,
    project_research_dir: Path,
    vault_research_max_age_days: int = 30,
    max_matches: int = _DEFAULT_MAX_MATCHES,
) -> list[ResearchMatch]:
    """Return research notes whose topic / tags / body matches any keyword.

    Project-scoped Research/ is unfiltered by age; vault-wide Research/{Web,Deep}
    is restricted to recent files (mtime within the window).
    """
    vault_root = vault_root.resolve()
    project_research_dir = project_research_dir.resolve() if project_research_dir.exists() else None
    out: list[ResearchMatch] = []
    seen: set[Path] = set()
    cutoff = time.time() - vault_research_max_age_days * 24 * 3600

    # Project scope — no age filter.
    if project_research_dir and project_research_dir.is_dir():
        for f in project_research_dir.rglob("*.md"):
            if f in seen:
                continue
            match = _try_match(candidate_id, f, keywords, vault_root)
            if match:
                seen.add(f)
                out.append(match)
                if len(out) >= max_matches:
                    return out

    # Vault-wide scope — age-filtered.
    for sub in ("Research/Web", "Research/Deep"):
        d = vault_root / sub
        if not d.is_dir():
            continue
        for f in d.rglob("*.md"):
            if f in seen:
                continue
            try:
                if f.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            match = _try_match(candidate_id, f, keywords, vault_root)
            if match:
                seen.add(f)
                out.append(match)
                if len(out) >= max_matches:
                    return out
    return out


def _try_match(candidate_id: str, file: Path, keywords: list[str], vault_root: Path) -> ResearchMatch | None:
    if file.suffix not in _TEXT_EXTENSIONS:
        return None
    try:
        text = file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    haystack = text.lower()
    for kw in keywords:
        if kw.lower() in haystack:
            try:
                rel = file.relative_to(vault_root).as_posix()
            except ValueError:
                rel = str(file)
            return ResearchMatch(
                candidate_id=candidate_id,
                path=rel,
                summary_excerpt=_extract_summary_excerpt(text),
            )
    return None


_SUMMARY_RE = re.compile(r"^##\s+Summary\s*$([\s\S]*?)(?=^##\s|\Z)", re.MULTILINE)


def _extract_summary_excerpt(text: str) -> str:
    """Return the first ~600 chars of `## Summary` body, or topic frontmatter as fallback."""
    m = _SUMMARY_RE.search(text)
    if m:
        body = m.group(1).strip()
        return body[:_SUMMARY_EXCERPT_CHARS]
    # Fallback: pull `topic:` from frontmatter.
    fm_match = re.search(r"^topic:\s*[\"']?([^\"\'\n]+)", text, re.MULTILINE)
    return fm_match.group(1).strip() if fm_match else text[:_SUMMARY_EXCERPT_CHARS]


def build_relevance_prompt(
    matches_by_cand: dict[str, list[ResearchMatch]],
    candidates_text: dict[str, str],
    output_lang: str,
) -> str:
    """Build LLM prompt for Phase 2c (relevance check).

    The agent invokes the LLM with this prompt and expects JSON back:
    {candidate-id: [relevant-research-path, ...]}
    """
    lang_directive = (
        "輸出 JSON。判斷時思考用繁體中文 (zh-TW)。"
        if output_lang == "zh-TW"
        else "Output JSON. Reason in English."
    )
    lines = [
        "You are filtering research notes for relevance to roadmap candidates.",
        lang_directive,
        "",
        "For each candidate id below, return a JSON list of paths to research "
        "notes that are GENUINELY relevant (not just keyword-matching). Drop "
        "notes whose summary clearly addresses a different problem.",
        "",
        "Return strict JSON: {\"<candidate-id>\": [\"<path>\", ...], ...}",
        "",
        "Candidates:",
    ]
    for cid, text in candidates_text.items():
        lines.append(f"- {cid}: {text}")
    lines.append("")
    lines.append("Research matches per candidate:")
    for cid, matches in matches_by_cand.items():
        lines.append(f"### {cid}")
        for m in matches:
            lines.append(f"- path: {m.path}")
            lines.append(f"  summary: {m.summary_excerpt[:400]}")
    return "\n".join(lines)


def build_keyword_extraction_prompt(candidates: dict[str, str], output_lang: str) -> str:
    """Build LLM prompt for Phase 2a (keyword extraction).

    Agent invokes LLM with this prompt; expects JSON back: {cand-id: [kw, ...]}.
    """
    lang_directive = (
        "Output keywords in whatever language matches the candidate text "
        "(English code identifiers stay English; Chinese terms stay Chinese). "
        "Avoid stop words. Each keyword should be 1-3 tokens."
    )
    lines = [
        "Extract 3-5 short keywords per roadmap candidate, useful for searching "
        "across research notes.",
        lang_directive,
        "",
        "Return strict JSON: {\"<candidate-id>\": [\"<keyword>\", ...], ...}",
        "",
        "Candidates:",
    ]
    for cid, text in candidates.items():
        lines.append(f"- {cid}: {text}")
    return "\n".join(lines)
