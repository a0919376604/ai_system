import time
from pathlib import Path

from scripts.roadmap.research_match import (
    ResearchMatch,
    keyword_prefilter,
    build_relevance_prompt,
)


def _make_research(path: Path, topic: str, tags: list[str], body: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    fm = "---\n" + f"topic: {topic}\n" + f"tags: {tags}\n" + "type: research-deep\n" + "---\n"
    path.write_text(fm + "\n## Summary\n\n" + body)


def test_finds_match_in_project_research(tmp_path: Path):
    proj_research = tmp_path / "Projects" / "p" / "Research"
    _make_research(proj_research / "2026-05-15-oauth.md", "OAuth flow", ["oauth"], "OAuth 是 ...")
    matches = keyword_prefilter(
        candidate_id="gap-1",
        keywords=["OAuth", "SSO"],
        vault_root=tmp_path,
        project_research_dir=proj_research,
        vault_research_max_age_days=30,
    )
    assert any(m.path.endswith("2026-05-15-oauth.md") for m in matches)


def test_finds_match_in_vault_research_within_window(tmp_path: Path):
    vault_research = tmp_path / "Research" / "Deep"
    _make_research(vault_research / "2026-05-20-ai-engines.md", "AI Engines", ["ai", "engine"], "比較 LangGraph vs ...")
    matches = keyword_prefilter(
        candidate_id="gap-2",
        keywords=["LangGraph", "engine"],
        vault_root=tmp_path,
        project_research_dir=tmp_path / "Projects" / "p" / "Research",
        vault_research_max_age_days=30,
    )
    assert any(m.path.endswith("2026-05-20-ai-engines.md") for m in matches)


def test_skips_vault_research_older_than_window(tmp_path: Path):
    vault_research = tmp_path / "Research" / "Deep"
    _make_research(vault_research / "2025-01-01-old.md", "Old", ["old"], "older than window")
    # Forcibly age the file
    old = (vault_research / "2025-01-01-old.md")
    old_ts = time.time() - 60 * 24 * 3600  # 60 days ago
    import os
    os.utime(old, (old_ts, old_ts))
    matches = keyword_prefilter(
        candidate_id="gap-3",
        keywords=["old"],
        vault_root=tmp_path,
        project_research_dir=tmp_path / "Projects" / "p" / "Research",
        vault_research_max_age_days=30,
    )
    assert not any(m.path.endswith("old.md") for m in matches)


def test_caps_matches_per_candidate(tmp_path: Path):
    proj_research = tmp_path / "Projects" / "p" / "Research"
    for i in range(20):
        _make_research(proj_research / f"2026-05-{i:02d}-streaming.md", "streaming",
                       ["streaming"], "streaming body")
    matches = keyword_prefilter(
        candidate_id="gap-4",
        keywords=["streaming"],
        vault_root=tmp_path,
        project_research_dir=proj_research,
        vault_research_max_age_days=30,
        max_matches=10,
    )
    assert len(matches) <= 10


def test_build_relevance_prompt_lists_candidates_and_matches():
    matches_by_cand = {
        "gap-1": [
            ResearchMatch(candidate_id="gap-1", path="Research/Deep/2026-05-15-oauth.md",
                          summary_excerpt="OAuth is a delegated authorization protocol..."),
        ],
    }
    candidates_text = {"gap-1": "Add SSO integration"}
    prompt = build_relevance_prompt(matches_by_cand, candidates_text, output_lang="zh-TW")
    assert "gap-1" in prompt
    assert "Add SSO integration" in prompt
    assert "OAuth is a delegated" in prompt
    # zh-TW prompt should mention 繁體中文 OR be explicit about output language
    assert "繁體中文" in prompt or "zh-TW" in prompt or "Traditional Chinese" in prompt


def test_build_keyword_extraction_prompt_lists_candidates_with_text():
    from scripts.roadmap.research_match import build_keyword_extraction_prompt
    candidates = {
        "gap-1": "加 SSO 整合 (stated: AGENTS.md)",
        "asp-2": "把 AI 引擎抽象成 pluggable adapter",
    }
    prompt = build_keyword_extraction_prompt(candidates, output_lang="zh-TW")
    assert "gap-1" in prompt
    assert "加 SSO 整合" in prompt
    assert "asp-2" in prompt
    # Prompt must explicitly ask for JSON output
    assert "JSON" in prompt
    # Must ask for 3-5 keywords per candidate
    assert "3" in prompt and "5" in prompt
