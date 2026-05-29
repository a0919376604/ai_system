from datetime import date

from scripts.roadmap.render import (
    Theme,
    Task,
    compose_roadmap,
    compose_task_note,
    format_board_card,
)


def _sample_themes() -> list[Theme]:
    return [
        Theme(
            slug="ai-engine-pluggability",
            title="AI 引擎可插拔化",
            why="目前只支援 LangGraph (見 [[modules/backend]]);AGENTS.md 提 pluggable engine 但未落實。",
            priority="🔴",
            effort="M",
            evidence=["[[Architecture/future#期望中的想法]] 第 1 點",
                      "[[Projects/p/Research/2026-05-15-engine-comparison]]"],
            tasks=[
                Task(id="T-001", slug="add-engine-adapter-base",
                     description="在 backend/engines/ 加 EngineAdapter base class",
                     module_wikilink="[[modules/backend]]",
                     acceptance_criteria=["`backend/engines/adapter.py` 有 EngineAdapter ABC"]),
                Task(id="T-002", slug="port-langgraph-as-adapter",
                     description="把 LangGraph 實作改寫為 LangGraphAdapter",
                     module_wikilink="[[modules/backend]]",
                     acceptance_criteria=["adapter 通過整合測試"]),
            ],
        ),
    ]


def test_compose_roadmap_emits_frontmatter_and_themes_section_zh():
    note = compose_roadmap(
        project="myproj",
        themes=_sample_themes(),
        stale_themes=[],
        synthesis_summary={"themes": 1, "tasks": 2, "research_cited": 1, "architect_signals": 2},
        output_lang="zh-TW",
    )
    assert note.startswith("---\n")
    assert "type: roadmap" in note
    assert 'project: "[[myproj]]"' in note
    assert "lang: zh-TW" in note
    assert "themes-count: 1" in note
    assert "tasks-count: 2" in note
    assert "## 給未來 Claude" in note
    assert "## 本次合成摘要" in note
    assert "## 主題" in note
    # Theme heading appears as H3
    assert "### 🔴 AI 引擎可插拔化" in note
    # Tasks are wiki-linked
    assert "[[Tasks/T-001-add-engine-adapter-base|T-001 在 backend/engines/ 加 EngineAdapter base class]]" in note
    # Evidence rendered as bullets
    assert "[[Architecture/future#期望中的想法]]" in note


def test_compose_roadmap_en_translates_headings():
    note = compose_roadmap(
        project="myproj",
        themes=_sample_themes(),
        stale_themes=[],
        synthesis_summary={"themes": 1, "tasks": 2, "research_cited": 0, "architect_signals": 1},
        output_lang="en",
    )
    assert "## For future Claude" in note
    assert "## Synthesis summary" in note
    assert "## Themes" in note
    assert "## 給未來 Claude" not in note


def test_compose_roadmap_renders_stale_section():
    note = compose_roadmap(
        project="myproj",
        themes=_sample_themes(),
        stale_themes=[
            Theme(slug="dropped-thing", title="放棄的東西", why="signal disappeared",
                  priority="🟢", effort="S", evidence=[], tasks=[]),
        ],
        synthesis_summary={"themes": 1, "tasks": 2, "research_cited": 0, "architect_signals": 1},
        output_lang="zh-TW",
    )
    assert "## 過時主題" in note
    assert "放棄的東西" in note


def test_compose_task_note_zh():
    t = Task(id="T-001", slug="add-engine-adapter-base",
             description="在 backend/engines/ 加 EngineAdapter base class",
             module_wikilink="[[modules/backend]]",
             acceptance_criteria=["`backend/engines/adapter.py` 有 EngineAdapter ABC",
                                  "既有 LangGraph 可以 instantiate 為 adapter"])
    note = compose_task_note(
        task=t,
        theme_slug="ai-engine-pluggability",
        theme_title="AI 引擎可插拔化",
        project="myproj",
        output_lang="zh-TW",
    )
    assert "type: task" in note
    assert "roadmap-theme: ai-engine-pluggability" in note
    assert 'created-by: "obsidian-roadmap"' in note
    assert "status: backlog" in note
    assert "## 給未來 Claude" in note
    assert "## 接受條件" in note
    assert "EngineAdapter ABC" in note
    assert "[[Roadmap]]" in note
    assert "[[modules/backend]]" in note


def test_format_board_card_carries_theme_label():
    t = Task(id="T-007", slug="add-rate-limit",
             description="加 rate limit middleware",
             module_wikilink="[[modules/backend]]",
             acceptance_criteria=[])
    card = format_board_card(t, theme_slug="observability", priority="🔴")
    assert card.startswith("- [ ]")
    assert "[[Tasks/T-007-add-rate-limit|加 rate limit middleware]]" in card
    assert "🔴" in card
    assert "[theme: observability]" in card


def test_normalize_slug_keeps_valid():
    from scripts.roadmap.render import normalize_slug
    assert normalize_slug("add-engine-adapter-base") == "add-engine-adapter-base"
    assert normalize_slug("refresh-token-rotation") == "refresh-token-rotation"


def test_normalize_slug_falls_back_when_invalid():
    from scripts.roadmap.render import normalize_slug
    # Capitalised / spaces / Chinese -> fallback uses description
    assert normalize_slug("Add Adapter Base") == "add-adapter-base"
    assert normalize_slug("在 backend 加 EngineAdapter") == "backend-engineadapter"


def test_normalize_slug_caps_length():
    from scripts.roadmap.render import normalize_slug
    s = normalize_slug("a-" * 50)  # 100 chars
    assert len(s) <= 50


def test_normalize_slug_handles_empty():
    from scripts.roadmap.render import normalize_slug
    # All-non-ascii input falls back to hash-based slug
    s = normalize_slug("一個全中文的任務")
    assert s.startswith("task-")  # fallback prefix
    assert len(s) > 5


def test_append_board_card_to_existing_backlog(tmp_path):
    from scripts.roadmap.render import append_to_board
    board = tmp_path / "board.md"
    board.write_text(
        "---\n"
        "type: board\n"
        "---\n"
        "\n"
        "## 待辦\n"
        "\n"
        "- [ ] existing card\n"
        "\n"
        "## 進行中\n"
    )
    appended = append_to_board(board, ["- [ ] new card 1", "- [ ] new card 2"], heading_zh="## 待辦", heading_en="## Backlog")
    text = board.read_text()
    assert "- [ ] existing card" in text
    assert "- [ ] new card 1" in text
    assert "- [ ] new card 2" in text
    assert appended == 2
    # Cards land BEFORE ## 進行中, not after
    backlog_idx = text.index("## 待辦")
    inprogress_idx = text.index("## 進行中")
    new_card_idx = text.index("new card 1")
    assert backlog_idx < new_card_idx < inprogress_idx


def test_append_board_card_creates_backlog_section_if_missing(tmp_path):
    from scripts.roadmap.render import append_to_board
    board = tmp_path / "board.md"
    board.write_text("## 進行中\n\n## 已完成\n")
    appended = append_to_board(board, ["- [ ] one"], heading_zh="## 待辦", heading_en="## Backlog")
    text = board.read_text()
    assert "## 待辦" in text
    assert "- [ ] one" in text
    assert appended == 1
