"""Tests for /obsidian-brainstorm section registration + helpers."""
from __future__ import annotations

from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS


def test_brainstorm_section_type_present():
    assert SECTION_TYPES["brainstorm"] == "project-brainstorm"


def test_brainstorm_block_names_v1():
    expected = (
        "context",
        "opening-provocations",
        "drilled-explorations",
        "distilled-imps",
        "hypotheses",
        "parked",
        "open-questions",
        "meta-reflection",
        "dependencies",
    )
    assert _BLOCK_NAMES["brainstorm"] == expected


def test_brainstorm_block_headings_registered():
    """All v1 brainstorm block names must have entries in _BLOCK_HEADINGS."""
    new_blocks = [
        "context",
        "opening-provocations",
        "drilled-explorations",
        "distilled-imps",
        "hypotheses",
        "parked",
        "open-questions",
        "meta-reflection",
    ]
    for block in new_blocks:
        assert block in _BLOCK_HEADINGS, f"missing heading for {block}"
    # `dependencies` block reuses existing v3 mapping ("## Dependencies and consumers").
    assert "dependencies" in _BLOCK_HEADINGS


def test_parse_hypothesis_block_extracts_fields():
    """Hypothesis block has H3 entries with fields:
    假設 / 驗證方式 / kill criterion / owner / status."""
    from scripts.architect.sections import parse_hypothesis_block

    body = (
        "### H1: 客服自助 Rich Menu 能降 ticket 量 30%\n"
        "- **假設:** LINE Rich Menu 加 5 個自助 FAQ 入口後,客服 ticket 量在 4 週內降 ≥ 30%\n"
        "- **驗證方式:** 灰度部署到 20% 用戶,4 週後比較對照組 ticket 量\n"
        "- **kill criterion:** 降幅 < 10% 或客戶滿意度同步下降\n"
        "- **owner:** [[people/客服 lead]]\n"
        "- **status:** unvalidated\n"
        "\n"
        "### H2: 統一 embedding provider 後 recall 提升\n"
        "- **假設:** write+read 用同 embedding provider 後,golden-set recall@5 提升 ≥ 15%\n"
        "- **驗證方式:** 跑 evaluation/retrieval golden-set 對比\n"
        "- **kill criterion:** recall@5 變化 < 5%\n"
        "- **owner:** [[people/AI lead]]\n"
        "- **status:** unvalidated\n"
    )
    hyps = parse_hypothesis_block(body)
    assert len(hyps) == 2
    h1 = hyps[0]
    assert h1["title"] == "H1: 客服自助 Rich Menu 能降 ticket 量 30%"
    assert "LINE Rich Menu" in h1["assumption"]
    assert "灰度部署到 20%" in h1["validation"]
    assert "降幅 < 10%" in h1["kill_criterion"]
    assert "客服 lead" in h1["owner"]
    assert h1["status"] == "unvalidated"


def test_parse_hypothesis_block_ignores_entries_missing_required_fields():
    """An H3 missing assumption / validation / kill_criterion is dropped."""
    from scripts.architect.sections import parse_hypothesis_block

    body = (
        "### H1: incomplete (no fields)\n"
        "Just prose, no bullets.\n"
        "\n"
        "### H2: complete\n"
        "- **假設:** A\n"
        "- **驗證方式:** B\n"
        "- **kill criterion:** C\n"
        "- **owner:** D\n"
        "- **status:** unvalidated\n"
    )
    hyps = parse_hypothesis_block(body)
    assert len(hyps) == 1
    assert hyps[0]["title"] == "H2: complete"


def test_parse_hypothesis_block_returns_empty_when_no_h3():
    from scripts.architect.sections import parse_hypothesis_block
    assert parse_hypothesis_block("just paragraph text\nno h3 headings") == []


def test_compose_brainstorm_note_emits_extra_frontmatter():
    """compose_brainstorm_note merges session-specific frontmatter
    (mode / lens-mix / depth / status / counts) before ai-first: true."""
    from scripts.architect.sections import compose_brainstorm_note

    blocks = {n: f"body for {n}" for n in (
        "context", "opening-provocations", "drilled-explorations",
        "distilled-imps", "hypotheses", "parked", "open-questions",
        "meta-reflection", "dependencies",
    )}
    note = compose_brainstorm_note(
        project="P",
        repo_label="local: /tmp/p",
        commit="abc1234",
        signal_sources=["Architecture/*", "Research/*", "board.md"],
        confidence="medium",
        output_lang="zh-TW",
        generated_blocks=blocks,
        mode="generate",
        lens_mix=["gap", "persona", "premortem"],
        depth="medium",
        status="fresh",
        session_duration_min=28,
        provocations_opened=5,
        provocations_drilled=2,
        imps_distilled=3,
        hypotheses_raised=2,
    )
    assert "mode: generate" in note
    assert "depth: medium" in note
    assert "status: fresh" in note
    assert "session-duration-min: 28" in note
    assert "provocations-opened: 5" in note
    assert "provocations-drilled: 2" in note
    assert "imps-distilled: 3" in note
    assert "hypotheses-raised: 2" in note
    # lens-mix is a YAML list
    assert 'lens-mix: ["gap", "persona", "premortem"]' in note
    # Order: extras must come BEFORE `ai-first: true`.
    fm = note.split("---", 2)[1]
    assert fm.index("mode:") < fm.index("ai-first:")
    assert fm.index("hypotheses-raised:") < fm.index("ai-first:")
    # Body contains all 9 blocks via sentinels.
    for name in blocks:
        assert f"<!-- @generated:start {name} -->" in note
        assert f"<!-- @generated:end {name} -->" in note


def test_compose_brainstorm_note_zh_tw_renders_h2_in_zh():
    """When output_lang=zh-TW, the H2 headings for brainstorm blocks come out in zh-TW."""
    from scripts.architect.sections import compose_brainstorm_note

    blocks = {n: f"body" for n in (
        "context", "opening-provocations", "drilled-explorations",
        "distilled-imps", "hypotheses", "parked", "open-questions",
        "meta-reflection", "dependencies",
    )}
    note = compose_brainstorm_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["x"], confidence="medium", output_lang="zh-TW",
        generated_blocks=blocks, mode="generate", lens_mix=["gap"],
        depth="quick", status="fresh", session_duration_min=10,
        provocations_opened=4, provocations_drilled=0,
        imps_distilled=0, hypotheses_raised=0,
    )
    assert "## 對話脈絡" in note
    assert "## 開場 provocations" in note
    assert "## 深挖紀錄" in note
    assert "## 提煉的 Imps" in note
    assert "## 待驗證假設" in note
    assert "## 暫不討論" in note
    assert "## 仍不清楚" in note
    assert "## 自我覆盤" in note
