from pathlib import Path

from scripts.roadmap.candidates import Candidate, detect_candidates

FIXTURE = Path(__file__).parent / "fixtures" / "project-a"


def test_detects_decisions_known_limitations():
    cands = detect_candidates(FIXTURE)
    kinds = {c.kind for c in cands}
    assert "limitation" in kinds


def test_detects_promote_to_adr():
    cands = detect_candidates(FIXTURE)
    promotes = [c for c in cands if c.kind == "promote-to-adr"]
    assert len(promotes) == 3
    assert any("Redis Cluster" in c.raw_text for c in promotes)


def test_skips_legacy_roadmap_todo_clusters():
    cands = detect_candidates(FIXTURE)
    clusters = [c for c in cands if c.kind == "todo-cluster"]
    assert clusters == []


def test_candidate_carries_source_wikilink():
    cands = detect_candidates(FIXTURE)
    for c in cands:
        if c.kind == "limitation":
            assert c.source_wikilink.startswith("[[Architecture/decisions")
            return
    raise AssertionError("no limitation candidate found")


def test_dedup_by_normalized_title():
    # Two candidates with same text after lowercasing + stripping punct should dedup
    from scripts.roadmap.candidates import Candidate, _dedup
    cands = [
        Candidate(id="gap-a", title="加 SSO 整合", source_wikilink="[[a]]", source_line=1,
                  kind="gap", raw_text="加 SSO 整合"),
        Candidate(id="asp-b", title="加 sso 整合", source_wikilink="[[b]]", source_line=2,
                  kind="aspiration", raw_text="加 sso 整合"),
    ]
    result = _dedup(cands)
    assert len(result) == 1


def test_missing_architecture_dir_returns_empty(tmp_path: Path):
    assert detect_candidates(tmp_path) == []


def test_candidate_has_stable_id():
    """Candidate id should be deterministic from kind + normalized title."""
    cands = detect_candidates(FIXTURE)
    ids = [c.id for c in cands]
    assert len(ids) == len(set(ids))  # all unique
    # Re-run yields same IDs
    cands2 = detect_candidates(FIXTURE)
    assert [c.id for c in cands2] == ids


def test_candidate_supports_v3_improvement_fields():
    from scripts.roadmap.candidates import Candidate
    c = Candidate(
        id="imp-x",
        title="Extract worker",
        source_wikilink="[[modules/backend#改進機會]]",
        source_line=0,
        kind="improvement",
        raw_text="full body",
        why="Because.",
        evidence=["[[a]]"],
        effort="M",
        risk_if_not_done="Bad.",
        confidence="medium",
    )
    assert c.why == "Because."
    assert c.effort == "M"
    assert c.confidence == "medium"


def test_candidate_v2_fields_still_work():
    """Existing v2 candidates without Imp metadata still construct fine."""
    from scripts.roadmap.candidates import Candidate
    c = Candidate(
        id="gap-x",
        title="A gap",
        source_wikilink="[[Architecture/future#落差分析]]",
        source_line=10,
        kind="gap",
        raw_text="...",
    )
    assert c.why is None
    assert c.effort is None


def test_detect_candidates_reads_improvement_blocks_from_modules(tmp_path):
    """v3 — `## 改進機會` / `## Improvement opportunities` blocks in modules/*.md become candidates."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    # A v3 module note with an improvement block.
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 拆 EventConsumer 為獨立 worker\n"
        "- **為什麼:** API process 與 event loop 共用\n"
        "- **證據:** [[Architecture/decisions#Event routing principle]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 流量峰值 API 延遲飆\n"
        "- **Confidence:** medium\n"
        "\n"
        "### Imp 2: 加 webhook signature verification\n"
        "- **為什麼:** 目前未驗證 LINE 來源\n"
        "- **證據:** `backend/main.py:80`\n"
        "- **Effort:** S\n"
        "- **未做的風險:** webhook 可被偽造\n"
        "- **Confidence:** stated\n"
    )
    # decisions.md now contributes known-limitations (migrated from v3 future.md).
    (arch / "decisions.md").write_text(
        "## 已知限制\n"
        "- 沒有 SSO 整合 (stated)\n"
    )
    cands = detect_candidates(tmp_path)
    # 2 improvements from backend module + 1 limitation from future.md
    by_kind = {c.kind: [x for x in cands if x.kind == c.kind] for c in cands}
    imp_titles = [c.title for c in cands if c.kind == "improvement"]
    assert any("EventConsumer" in t for t in imp_titles)
    assert any("webhook signature" in t for t in imp_titles)
    # Improvement candidate carries Imp metadata.
    ec_cand = next(c for c in cands if c.kind == "improvement" and "EventConsumer" in c.title)
    assert ec_cand.effort == "M"
    assert ec_cand.confidence == "medium"
    assert any("Event routing" in e for e in ec_cand.evidence)
    # Limitation still picked up.
    assert any(c.kind == "limitation" for c in cands)


def test_detect_candidates_reads_improvements_from_overview(tmp_path):
    """Overview-level Imps also become candidates."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    arch.mkdir(parents=True)
    (arch / "overview.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 升級 LangGraph 為 pluggable adapter\n"
        "- **為什麼:** 目前只能跑 LangGraph,鎖死供應商\n"
        "- **證據:** [[Architecture/decisions]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 換模型成本高\n"
        "- **Confidence:** stated\n"
    )
    cands = detect_candidates(tmp_path)
    imp = [c for c in cands if c.kind == "improvement"]
    assert len(imp) == 1
    assert "LangGraph" in imp[0].title
    assert imp[0].effort == "L"


def test_detect_candidates_skips_legacy_future_when_no_v4_sources(tmp_path):
    """v4 ignores legacy future.md; migration moves durable signal to decisions.md first."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    arch.mkdir(parents=True)
    (arch / "future.md").write_text(
        "## 落差分析\n\n- README mentions streaming, not implemented\n"
        "## 期望中的想法\n\n- migrate to pluggable engines\n"
    )
    cands = detect_candidates(tmp_path)
    assert cands == []


def test_v4_detect_candidates_skips_deleted_files(tmp_path):
    """v4: detect_candidates does NOT read future/roadmap/jobs/api-surface/features/flows files,
    even if they exist (legacy vault). It only reads overview + modules + decisions."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    # Overview with cross-cutting improvements
    (arch / "overview.md").write_text(
        "## 跨模組改進機會\n\n"
        "### Imp 1: 拆 EventConsumer 為獨立 worker\n"
        "- **為什麼:** 共用 process\n"
        "- **證據:** [[modules/backend#改進機會]] Imp 1\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 流量峰值\n"
        "- **Confidence:** medium\n"
    )
    # Module with improvements
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 抽 sweeper\n"
        "- **為什麼:** main.py 過大\n"
        "- **證據:** `backend/main.py:58-388`\n"
        "- **Effort:** M\n"
        "- **未做的風險:** test scope 擴大\n"
        "- **Confidence:** high\n"
    )
    # Decisions with promote-to-ADR
    (arch / "decisions.md").write_text(
        "## 建議升級為 ADR\n\n"
        "1. **Redis vs PostgreSQL 角色釐清** — AGENTS.md 暗示未詳述\n"
    )
    # Legacy v3 file SHOULD BE IGNORED even if present.
    (arch / "features.md").write_text(
        "## 改進機會\n\n"
        "### Imp 99: 不該被撿到\n"
        "- **為什麼:** ...\n"
        "- **證據:** [[fake]]\n"
        "- **Effort:** S\n"
        "- **未做的風險:** ...\n"
        "- **Confidence:** speculation\n"
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("EventConsumer" in t for t in titles)
    assert any("抽 sweeper" in t for t in titles)
    # The deleted-file Imp must NOT be picked up.
    assert not any("Imp 99" in t or "不該被撿到" in t for t in titles), \
        f"v4 detect_candidates should skip features.md; got titles={titles}"


def test_v4_detect_candidates_reads_known_limitations_in_decisions(tmp_path):
    """The known-limitations content (migrated from future.md) becomes 'limitation' kind candidates."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    arch.mkdir(parents=True)
    (arch / "decisions.md").write_text(
        "## 已知限制\n\n"
        "- backend/.env deprecated\n"
        "- plain-text password fallback\n"
    )
    cands = detect_candidates(tmp_path)
    kinds = {c.kind for c in cands}
    assert "limitation" in kinds
    titles = [c.title for c in cands if c.kind == "limitation"]
    assert any("env deprecated" in t for t in titles)


def test_v4_1_detect_candidates_reads_ai_flows_dir(tmp_path):
    """v4.1: detect_candidates also walks Architecture/ai-flows/*.md."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "lang-ai-customer.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 加 prompt eval framework\n"
        "- **為什麼:** 完全靠人工\n"
        "- **證據:** `backend/engines/langgraph/`\n"
        "- **Effort:** L\n"
        "- **未做的風險:** prompt regression 無法 catch\n"
        "- **Confidence:** stated\n"
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("prompt eval framework" in t for t in titles), \
        f"ai-flow Imp not picked up by detect_candidates; got: {titles}"
    imp = next(c for c in cands if "prompt eval" in c.title)
    assert imp.effort == "L"
    assert imp.confidence == "stated"


def test_v4_1_detect_candidates_no_ai_flows_dir_still_works(tmp_path):
    """If ai-flows/ doesn't exist, detect_candidates falls through cleanly."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: backend Imp\n"
        "- **為什麼:** ...\n- **證據:** [[x]]\n- **Effort:** S\n"
        "- **未做的風險:** ...\n- **Confidence:** high\n"
    )
    cands = detect_candidates(tmp_path)
    assert any("backend Imp" in c.title for c in cands)


def test_detect_candidates_walks_features_md_missing_features_block(tmp_path):
    """detect_candidates picks up missing-features H3 entries from features.md."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    arch.mkdir()
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 可加 features\n"
        "<!-- @generated:start missing-features -->\n"
        "### Multi-channel inbox\n"
        "- **為什麼:** 客戶開始要求 WhatsApp 整合\n"
        "- **證據:** [[Research/line-bot-trends]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 客戶轉投競品\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end missing-features -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    multichannel = next(
        (c for c in cands if "Multi-channel" in c.title), None
    )
    assert multichannel is not None, f"missing-features entry not picked up; got {[c.title for c in cands]}"
    # Research wikilink in Evidence → priority high.
    assert multichannel.priority == "high"


def test_detect_candidates_features_imp_without_research_is_normal_priority(tmp_path):
    """missing-features Evidence with persona / code-pattern but no [[Research/]] → normal."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    arch.mkdir()
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 可加 features\n"
        "<!-- @generated:start missing-features -->\n"
        "### Shift handoff\n"
        "- **為什麼:** Persona Mary 跨班沒工具\n"
        "- **證據:** [[Architecture/personas#Mary]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 客服漏接\n"
        "- **Confidence:** high\n"
        "<!-- @generated:end missing-features -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    shift = next((c for c in cands if "Shift handoff" in c.title), None)
    assert shift is not None
    assert shift.priority == "normal"


def test_detect_candidates_dedup_features_vs_module(tmp_path):
    """When features.md Imp and module Imp cite same Evidence wikilink,
    features.md wins; module Imp is dropped or marked child."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Streaming reply\n"
        "- **為什麼:** UX 體感落後\n"
        "- **證據:** [[Architecture/modules/backend#改進機會]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 競品先上\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    (arch / "modules" / "backend.md").write_text(
        "---\ntype: architecture-module\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Streaming reply tech impl\n"
        "- **為什麼:** llm.invoke 改 stream\n"
        "- **證據:** [[Architecture/modules/backend#改進機會]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 無\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    # Features.md Imp wins; module Imp deduped.
    titles = [c.title for c in cands]
    assert "Streaming reply" in titles
    assert "Streaming reply tech impl" not in titles, (
        f"expected module Imp deduped against features Imp; got {titles}"
    )


def test_detect_candidates_dedup_features_vs_module_when_module_imp_is_structured(tmp_path):
    """Features.md wins when a parsed module Imp cites the same Evidence wikilink."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Streaming reply\n"
        "- **為什麼:** UX 體感落後\n"
        "- **證據:** [[Architecture/modules/backend#改進機會]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 競品先上\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    (arch / "modules" / "backend.md").write_text(
        "---\ntype: architecture-module\n---\n\n"
        "## 改進機會\n"
        "### Imp 1: Streaming reply tech impl\n"
        "- **為什麼:** llm.invoke 改 stream\n"
        "- **證據:** [[Architecture/modules/backend#改進機會]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 無\n"
        "- **Confidence:** stated\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert "Streaming reply" in titles
    assert "Streaming reply tech impl" not in titles, (
        f"expected module Imp deduped against features Imp; got {titles}"
    )


def test_detect_candidates_walks_ai_memory_md(tmp_path):
    """detect_candidates picks up improvements block from ai-flows/memory.md."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "memory.md").write_text(
        "---\ntype: architecture-ai-memory\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Add TTL to SimpleRedisSaver keys\n"
        "- **為什麼:** 無 TTL → 無限長 session state\n"
        "- **證據:** [[Architecture/ai-flows/memory#Scope & lifecycle]]\n"
        "- **Effort:** S\n"
        "- **未做的風險:** Redis 容量爆\n"
        "- **Confidence:** high\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("TTL" in t for t in titles), f"memory Imp not picked up; got {titles}"


def test_detect_candidates_rag_md_embedding_aligned_evidence_raises_priority(tmp_path):
    """When an Imp from rag.md cites embedding-aligned: false evidence, priority becomes high."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "rag.md").write_text(
        "---\ntype: architecture-ai-rag\nembedding-aligned: false\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Align write+read embedding providers\n"
        "- **為什麼:** embedding-aligned: false → vector space 不一致\n"
        "- **證據:** [[Architecture/ai-flows/rag#Embedding providers]] (embedding-aligned: false)\n"
        "- **Effort:** M\n"
        "- **未做的風險:** retrieve recall 受損\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    align = next((c for c in cands if "Align" in c.title), None)
    assert align is not None, f"rag Imp not picked up; cands={[c.title for c in cands]}"
    assert align.priority == "high", (
        f"expected priority=high due to embedding-aligned evidence; got {align.priority}"
    )
