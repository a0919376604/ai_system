"""Phase 1 — gap candidate detection from Architecture/ files."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Candidate:
    id: str
    title: str
    source_wikilink: str
    source_line: int
    kind: str
    raw_text: str
    # v3 additions (optional, populated when source is a structured Improvement).
    why: str | None = None
    evidence: list[str] = field(default_factory=list)
    effort: str | None = None
    risk_if_not_done: str | None = None
    confidence: str | None = None
    candidate_type: str | None = None
    priority: str = "normal"
    source: str | None = None


# Section heading -> (kind, source-file)
_FUTURE_SECTIONS = {
    "## 已知限制": "limitation",
    "## Known limitations": "limitation",
    "## 落差分析": "gap",
    "## Gap analysis": "gap",
    "## 期望中的想法": "aspiration",
    "## Aspirational ideas": "aspiration",
}

_DECISIONS_SECTIONS = {
    "## 建議升級為 ADR": "promote-to-adr",
    "## Promote to ADR": "promote-to-adr",
}

_ROADMAP_SECTIONS = {
    "## TODO 群組": "todo-cluster",
    "## TODO clusters": "todo-cluster",
}

_BULLET_RE = re.compile(r"^[-*]\s+(.+)$", re.MULTILINE)
_NUMBERED_RE = re.compile(r"^\d+\.\s+(.+)$", re.MULTILINE)


def detect_candidates(project_root: Path) -> list[Candidate]:
    """Walk Architecture/ files, extract candidates.

    v4: reads overview.md, modules/*.md, and decisions.md `## 改進機會`
    or `## Improvement opportunities` blocks. Legacy v3 files (future.md,
    roadmap.md, jobs.md, api-surface.md, flows.md) are NOT walked even if
    they exist. v4.2 re-introduces features.md, but only via generated
    missing-features / improvements / doc-sync-actions sentinel blocks.

    Also extracts `## 已知限制` from decisions.md as kind=limitation candidates.
    """
    arch = project_root / "Architecture"
    if not arch.is_dir():
        return []
    out: list[Candidate] = []

    # v4 signal sources — only overview + modules/*.md + decisions.md.
    candidate_files = []
    if (arch / "overview.md").is_file():
        candidate_files.append(arch / "overview.md")
    if (arch / "decisions.md").is_file():
        candidate_files.append(arch / "decisions.md")
    if (arch / "modules").is_dir():
        candidate_files.extend(sorted((arch / "modules").glob("*.md")))
    # v4.1: AI flow improvements feed roadmap signal.
    if (arch / "ai-flows").is_dir():
        candidate_files.extend(sorted((arch / "ai-flows").glob("*.md")))

    for f in candidate_files:
        out.extend(_extract_improvements_from_file(f, arch))

    # Decisions.md gets two extra extraction paths beyond `## 改進機會`:
    # 1. `## 建議升級為 ADR` (promote-to-ADR list) — kept from v3
    # 2. `## 已知限制` (known limitations, post-v4 migration) — new in v4
    if (arch / "decisions.md").is_file():
        out.extend(_extract_from_file(arch / "decisions.md", _DECISIONS_SECTIONS))
        out.extend(_extract_known_limitations(arch / "decisions.md", arch))

    # v4.2: product-PM features lens feeds roadmap signal via generated blocks.
    if (arch / "features.md").is_file():
        out.extend(_extract_features_candidates(arch / "features.md", arch))

    # v4.3: AI memory + RAG cross-flow notes feed roadmap signal via generated blocks.
    out.extend(_extract_ai_cross_flow_candidates(arch))

    return _dedup(_dedup_candidates(out))


_KNOWN_LIM_SECTIONS = {
    "## 已知限制": "limitation",
    "## Known limitations": "limitation",
}


def _extract_improvements_from_file(path: Path, arch_root: Path) -> list[Candidate]:
    """Pull `## 改進機會` / `## Improvement opportunities` blocks via sections.parse_improvements_block."""
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    # Locate the H2 block body.
    pattern = re.compile(
        r"^##\s+(?:改進機會|Improvement opportunities|跨模組改進機會|Cross-cutting improvements)\s*$([\s\S]*?)(?=^##\s|\Z)",
        re.MULTILINE,
    )
    m = pattern.search(text)
    if not m:
        return []
    body = m.group(1)
    rel_path = path.relative_to(arch_root.parent).as_posix()
    # Use the same parser sections.py exposes.
    from scripts.architect.sections import parse_improvements_block
    imps = parse_improvements_block(body)
    out: list[Candidate] = []
    arch_rel = rel_path.replace(".md", "")
    if "跨模組改進機會" in text:
        anchor = "跨模組改進機會"
    elif "Cross-cutting improvements" in text:
        anchor = "Cross-cutting improvements"
    else:
        anchor = "改進機會" if "改進機會" in text else "Improvement opportunities"
    for imp in imps:
        cand_id = _make_id("imp", _normalize_title(imp.title))
        out.append(Candidate(
            id=cand_id,
            title=imp.title,
            source_wikilink=f"[[{arch_rel}#{anchor}]]",
            source_line=0,
            kind="improvement",
            raw_text=imp.why,
            why=imp.why,
            evidence=imp.evidence,
            effort=imp.effort,
            risk_if_not_done=imp.risk_if_not_done,
            confidence=imp.confidence,
        ))
    return out


def _extract_known_limitations(path: Path, arch_root: Path) -> list[Candidate]:
    """Extract known-limitations bullets from decisions.md as `limitation` candidates."""
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    out: list[Candidate] = []
    for heading_str, kind in _KNOWN_LIM_SECTIONS.items():
        body, body_line = _section_body(text, heading_str)
        if body is None:
            continue
        anchor = heading_str.lstrip("# ").strip()
        bullets = _BULLET_RE.findall(body)
        rel = path.relative_to(arch_root.parent).as_posix().replace(".md", "")
        for raw in bullets:
            title = _normalize_title(raw)
            cand_id = _make_id(kind, title)
            out.append(Candidate(
                id=cand_id,
                title=title or raw,
                source_wikilink=f"[[{rel}#{anchor}]]",
                source_line=body_line,
                kind=kind,
                raw_text=raw.strip(),
            ))
    return out


def _extract_features_candidates(path: Path, arch_root: Path) -> list[Candidate]:
    """Extract v4.2 candidates from generated blocks in Architecture/features.md."""
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []

    out: list[Candidate] = []
    rel = path.relative_to(arch_root.parent).as_posix().replace(".md", "")

    missing_body = _extract_generated_block(text, "missing-features")
    if missing_body:
        for entry in _parse_feature_imp_entries(missing_body):
            priority = "high" if _has_research_wikilink(entry["evidence"]) else "normal"
            out.append(_candidate_from_feature_imp(
                entry,
                rel=rel,
                block="missing-features",
                kind="missing-feature",
                priority=priority,
            ))

    improvements_body = _extract_generated_block(text, "improvements")
    if improvements_body:
        for entry in _parse_feature_imp_entries(improvements_body):
            out.append(_candidate_from_feature_imp(
                entry,
                rel=rel,
                block="improvements",
                kind="feature-improvement",
                priority="normal",
            ))

    doc_actions_body = _extract_generated_block(text, "doc-sync-actions")
    if doc_actions_body:
        from scripts.architect.sections import parse_doc_actions_block

        for action in parse_doc_actions_block(doc_actions_body):
            title = action["text"][:80]
            out.append(Candidate(
                id=_make_id("doc-action", _normalize_title(title)),
                title=title,
                source_wikilink=f"[[{rel}#Doc sync actions]]",
                source_line=0,
                kind="doc-action",
                raw_text=action["text"],
                why=f"Doc sync: {action['group']}",
                evidence=[],
                effort="S",
                risk_if_not_done="文件持續漂移降低 onboarding 速度",
                confidence="stated",
                candidate_type="doc-action",
                priority="low",
                source="features.md#doc-sync-actions",
            ))

    return out


def _extract_ai_cross_flow_candidates(arch_root: Path) -> list[Candidate]:
    """Extract v4.3 candidates from generated blocks in ai-flows/memory.md and rag.md."""
    out: list[Candidate] = []
    for fname, candidate_type, default_priority in (
        ("ai-flows/memory.md", "ai-memory-improvement", "normal"),
        ("ai-flows/rag.md", "ai-rag-improvement", "normal"),
    ):
        note_path = arch_root / fname
        if not note_path.exists():
            continue
        try:
            text = note_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        imp_body = _extract_generated_block(text, "improvements")
        if not imp_body:
            continue
        rel = note_path.relative_to(arch_root.parent).as_posix().replace(".md", "")
        for entry in _parse_feature_imp_entries(imp_body):
            priority = default_priority
            if fname.endswith("rag.md") and any(
                "embedding-aligned" in evidence.lower() for evidence in entry["evidence"]
            ):
                priority = "high"
            cand = _candidate_from_feature_imp(
                entry,
                rel=rel,
                block="improvements",
                kind=candidate_type,
                priority=priority,
            )
            cand.source = f"{fname}#improvements"
            out.append(cand)
    return out


def _extract_generated_block(text: str, name: str) -> str | None:
    """Extract content between <!-- @generated:start <name> --> and end markers."""
    start = f"<!-- @generated:start {name} -->"
    end = f"<!-- @generated:end {name} -->"
    s = text.find(start)
    if s == -1:
        return None
    s += len(start)
    e = text.find(end, s)
    if e == -1:
        return None
    return text[s:e].strip()


_FEATURE_ENTRY_TITLE_RE = re.compile(r"^###\s+(?:Imp\s+\d+:\s+)?(.+?)\s*$", re.MULTILINE)
_FEATURE_FIELD_RE = re.compile(r"^-\s+\*\*(.+?):\*\*\s*(.+)$", re.MULTILINE)
_FEATURE_FIELD_ALIASES = {
    "why": "why",
    "為什麼": "why",
    "evidence": "evidence",
    "證據": "evidence",
    "effort": "effort",
    "risk if not done": "risk_if_not_done",
    "未做的風險": "risk_if_not_done",
    "risk": "risk_if_not_done",
    "confidence": "confidence",
}


def _parse_feature_imp_entries(body: str) -> list[dict]:
    """Parse features.md H3 ImprovementItem-like entries."""
    parts = _FEATURE_ENTRY_TITLE_RE.split(body)
    if len(parts) < 3:
        return []
    entries: list[dict] = []
    for i in range(1, len(parts), 2):
        title = parts[i].strip()
        entry_body = parts[i + 1] if i + 1 < len(parts) else ""
        fields: dict[str, str] = {}
        for m in _FEATURE_FIELD_RE.finditer(entry_body):
            key = _FEATURE_FIELD_ALIASES.get(m.group(1).strip().lower())
            if key:
                fields[key] = m.group(2).strip()
        required = {"why", "evidence", "effort", "risk_if_not_done", "confidence"}
        if not required.issubset(fields):
            continue
        entries.append({
            "title": title,
            "why": fields["why"],
            "evidence": [e.strip() for e in fields["evidence"].split("|") if e.strip()],
            "effort": fields["effort"],
            "risk_if_not_done": fields["risk_if_not_done"],
            "confidence": fields["confidence"],
        })
    return entries


def _has_research_wikilink(evidence: list[str]) -> bool:
    return any("[[Research/" in e or "[[research/" in e for e in evidence)


def _candidate_from_feature_imp(
    entry: dict,
    *,
    rel: str,
    block: str,
    kind: str,
    priority: str,
) -> Candidate:
    return Candidate(
        id=_make_id(kind, _normalize_title(entry["title"])),
        title=entry["title"],
        source_wikilink=f"[[{rel}#{block}]]",
        source_line=0,
        kind=kind,
        raw_text=entry["why"],
        why=entry["why"],
        evidence=entry["evidence"],
        effort=entry["effort"],
        risk_if_not_done=entry["risk_if_not_done"],
        confidence=entry["confidence"],
        candidate_type=kind,
        priority=priority,
        source=f"features.md#{block}",
    )


def _extract_from_file(path: Path, section_to_kind: dict[str, str], freq_dedup: bool = False) -> list[Candidate]:
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    out: list[Candidate] = []
    file_stem = path.stem  # e.g. "future"
    arch_rel = f"Architecture/{file_stem}"
    for heading_str, kind in section_to_kind.items():
        body, body_start_line = _section_body(text, heading_str)
        if body is None:
            continue
        anchor = heading_str.lstrip("# ").strip()
        # For todo-cluster, count frequency by normalized TODO body.
        bullets = _BULLET_RE.findall(body) + _NUMBERED_RE.findall(body)
        freq: dict[str, int] = {}
        first_raw: dict[str, str] = {}
        for b in bullets:
            key = _todo_cluster_key(b) if freq_dedup else b
            freq[key] = freq.get(key, 0) + 1
            first_raw.setdefault(key, b)
        for key, count in freq.items():
            if freq_dedup and count < 2:
                continue
            raw = first_raw[key]
            title = _normalize_title(raw)
            cand_id = _make_id(kind, title)
            # Approximate source_line as body_start_line; precise per-bullet line tracking is overkill.
            out.append(Candidate(
                id=cand_id,
                title=title or raw,
                source_wikilink=f"[[{arch_rel}#{anchor}]]",
                source_line=body_start_line,
                kind=kind,
                raw_text=raw.strip(),
            ))
    return out


def _section_body(text: str, heading: str) -> tuple[str | None, int]:
    """Return (body, 1-indexed start line) for the section whose H2 matches `heading`."""
    pattern = re.compile(rf"^{re.escape(heading)}\s*$", re.MULTILINE)
    m = pattern.search(text)
    if not m:
        return None, 0
    start = m.end()
    start_line = text[: m.start()].count("\n") + 1
    # Body until next H2 or EOF.
    rest = text[start:]
    next_h2 = re.search(r"\n##\s+", rest)
    end = start + (next_h2.start() if next_h2 else len(rest))
    return text[start:end].strip(), start_line


_PUNCT_RE = re.compile(r"[「」、,。!?:;]+")
_EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\U00002600-\U000027BF]+")


def _normalize_title(raw: str) -> str:
    s = raw.strip()
    s = _EMOJI_RE.sub("", s)
    s = _PUNCT_RE.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    # Strip leading inline-markdown like **bold** wrapper.
    s = re.sub(r"^\**\s*", "", s).rstrip("*").strip()
    # Cap length to keep IDs short.
    return s[:120]


_TODO_PREFIX_RE = re.compile(r"^`[^`]+`\s+\(TODO\)\s+", re.IGNORECASE)


def _todo_cluster_key(raw: str) -> str:
    return _normalize_title(_TODO_PREFIX_RE.sub("", raw))


def _make_id(kind: str, normalized_title: str) -> str:
    h = hashlib.sha1(f"{kind}::{normalized_title}".encode("utf-8")).hexdigest()[:10]
    return f"{kind[:3]}-{h}"


def _dedup(cands: list[Candidate]) -> list[Candidate]:
    """Drop later occurrences of candidates with the same normalized title."""
    seen: set[str] = set()
    out: list[Candidate] = []
    for c in cands:
        key = c.title.strip().lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(c)
    return out


def _dedup_candidates(candidates: list[Candidate]) -> list[Candidate]:
    """Dedup module Imps against features.md Imps when they share Evidence wikilinks.

    Features.md (PM lens) wins. Module Imps with overlapping Evidence are dropped.
    """
    features_evidence_set: set[str] = set()
    for c in candidates:
        if _is_features_candidate(c):
            for wl in _extract_wikilinks(" | ".join(c.evidence)):
                features_evidence_set.add(wl)

    deduped: list[Candidate] = []
    for c in candidates:
        if _is_features_candidate(c):
            deduped.append(c)
            continue
        # Module / overview / decisions candidates: drop if any evidence wikilink
        # is in features_evidence_set.
        if any(wl in features_evidence_set for wl in _extract_wikilinks(" | ".join(c.evidence))):
            continue
        deduped.append(c)
    return deduped


def _is_features_candidate(candidate: Candidate) -> bool:
    return (
        (candidate.source is not None and "features.md" in candidate.source)
        or "Architecture/features" in candidate.source_wikilink
    )


_WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]")


def _extract_wikilinks(text: str) -> list[str]:
    return _WIKILINK_RE.findall(text)
