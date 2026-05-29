"""v4.3 AI memory + RAG cross-flow tests."""
from __future__ import annotations

from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS


def test_ai_memory_section_type_present():
    assert SECTION_TYPES["ai-memory"] == "architecture-ai-memory"


def test_ai_rag_section_type_present():
    assert SECTION_TYPES["ai-rag"] == "architecture-ai-rag"


def test_ai_memory_block_names_v4_3():
    expected = (
        "summary",
        "flow-memory-map",
        "backend-and-storage",
        "scope-and-lifecycle",
        "context-window-management",
        "compaction-strategy",
        "long-term-vs-short",
        "strengths",
        "weaknesses",
        "improvements",
        "dependencies",
    )
    assert _BLOCK_NAMES["ai-memory"] == expected


def test_ai_rag_block_names_v4_3():
    expected = (
        "summary",
        "rag-data-flow",
        "ingest-pipeline",
        "vector-store-config",
        "retrieve-strategy",
        "embedding-providers",
        "evaluation",
        "strengths",
        "weaknesses",
        "improvements",
        "dependencies",
    )
    assert _BLOCK_NAMES["ai-rag"] == expected


def test_v4_3_new_block_headings_registered():
    """All v4.3-specific block names must have entries in _BLOCK_HEADINGS."""
    new_blocks = [
        "flow-memory-map", "backend-and-storage", "scope-and-lifecycle",
        "context-window-management", "compaction-strategy", "long-term-vs-short",
        "rag-data-flow", "ingest-pipeline", "vector-store-config",
        "retrieve-strategy", "embedding-providers",
    ]
    for block in new_blocks:
        assert block in _BLOCK_HEADINGS, f"missing heading for {block}"


def test_build_ai_memory_prompt_requires_11_block_keys():
    from scripts.architect.sections import build_ai_memory_prompt

    prompt = build_ai_memory_prompt(
        project="P",
        ai_memory_signals={
            "per_flow": {
                "engines": {
                    "has_memory": True,
                    "backends": ["redis"],
                    "checkpointer_classes": ["SimpleRedisSaver"],
                    "checkpointer_sources": ["backend/.../saver.py"],
                    "key_patterns": ["simple_ckpt_v2"],
                    "reducer_funcs": ["add_messages_limited"],
                    "reducer_caps": [{"name": "add_messages_limited", "limit": 100, "source": "..."}],
                    "compaction_funcs": ["session_summary"],
                    "compaction_sources": ["..."],
                }
            },
            "summary": {"memory_flows": 1, "stateless_flows": 0,
                        "primary_backend": "redis", "uniform_backend": True},
        },
        ai_flows_summary=[{"slug": "engines", "framework": "langgraph",
                           "root_path": "backend/engines/langgraph"}],
        output_lang="zh-TW",
    )
    for key in (
        "summary", "flow-memory-map", "backend-and-storage",
        "scope-and-lifecycle", "context-window-management",
        "compaction-strategy", "long-term-vs-short", "strengths",
        "weaknesses", "improvements", "dependencies",
    ):
        assert key in prompt, f"prompt must reference block key {key!r}"


def test_build_ai_memory_prompt_no_invention_rule():
    """When a signal field is empty/null, prompt must instruct LLM to acknowledge absence."""
    from scripts.architect.sections import build_ai_memory_prompt

    prompt = build_ai_memory_prompt(
        project="P",
        ai_memory_signals={"per_flow": {}, "summary": {"memory_flows": 0,
                                                         "stateless_flows": 1,
                                                         "primary_backend": "none",
                                                         "uniform_backend": True}},
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    assert "未偵測到" in prompt or "acknowledge absence" in prompt.lower() or "no invention" in prompt.lower()


def test_build_ai_memory_prompt_wikilink_out_directive():
    """Prompt MUST instruct LLM to wikilink-out per-flow state-schema rather than rewrite."""
    from scripts.architect.sections import build_ai_memory_prompt

    prompt = build_ai_memory_prompt(
        project="P",
        ai_memory_signals={"per_flow": {}, "summary": {"memory_flows": 0,
                                                         "stateless_flows": 0,
                                                         "primary_backend": "none",
                                                         "uniform_backend": True}},
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    assert "[[ai-flows/" in prompt
    assert "State schema" in prompt or "state-schema" in prompt


def test_build_ai_rag_prompt_requires_11_block_keys():
    from scripts.architect.sections import build_ai_rag_prompt

    prompt = build_ai_rag_prompt(
        project="P",
        ai_rag_signals={
            "per_flow": {
                "writer": {"role": "write", "vector_stores": ["weaviate"],
                           "embedding_libs": ["openai"],
                           "embedding_models": ["text-embedding-3-small"],
                           "retrieve_params": {}, "rerank_libs": [], "chunking": None,
                           "vector_store_sources": [], "embedding_dims": None},
                "reader": {"role": "read", "vector_stores": ["weaviate"],
                           "embedding_libs": ["google_generativeai"],
                           "embedding_models": ["models/text-embedding-004"],
                           "retrieve_params": {"hybrid_alpha": 0.8, "top_k": 12},
                           "rerank_libs": [], "chunking": None,
                           "vector_store_sources": [], "embedding_dims": None},
            },
            "summary": {"read_flows": 1, "write_flows": 1,
                        "vector_stores": ["weaviate"], "primary_vector_store": "weaviate",
                        "embedding_aligned": False,
                        "alignment_mismatch": [{"write": {"flow": "writer",
                                                          "model": "text-embedding-3-small"},
                                                 "read": {"flow": "reader",
                                                          "model": "models/text-embedding-004"}}]},
        },
        ai_flows_summary=[
            {"slug": "writer", "framework": "custom-pipeline", "root_path": "modules/writer"},
            {"slug": "reader", "framework": "langgraph", "root_path": "backend/reader"},
        ],
        output_lang="zh-TW",
    )
    for key in (
        "summary", "rag-data-flow", "ingest-pipeline", "vector-store-config",
        "retrieve-strategy", "embedding-providers", "evaluation",
        "strengths", "weaknesses", "improvements", "dependencies",
    ):
        assert key in prompt, f"prompt must reference {key!r}"


def test_build_ai_rag_prompt_embedding_aligned_false_warning():
    """When embedding_aligned=false, prompt MUST instruct LLM to flag mismatch in
    weaknesses + improvements blocks."""
    from scripts.architect.sections import build_ai_rag_prompt

    prompt = build_ai_rag_prompt(
        project="P",
        ai_rag_signals={
            "per_flow": {},
            "summary": {"read_flows": 1, "write_flows": 1,
                        "vector_stores": ["weaviate"], "primary_vector_store": "weaviate",
                        "embedding_aligned": False, "alignment_mismatch": []},
        },
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    assert "embedding_aligned" in prompt or "embedding-aligned" in prompt
    assert "false" in prompt.lower()
    assert "weakness" in prompt.lower() or "缺點" in prompt
    assert "improvement" in prompt.lower() or "改進" in prompt


def test_build_ai_rag_prompt_aligned_true_no_warning():
    """When embedding_aligned=true, prompt should NOT push a misalignment warning."""
    from scripts.architect.sections import build_ai_rag_prompt

    prompt = build_ai_rag_prompt(
        project="P",
        ai_rag_signals={
            "per_flow": {},
            "summary": {"read_flows": 1, "write_flows": 1,
                        "vector_stores": ["weaviate"], "primary_vector_store": "weaviate",
                        "embedding_aligned": True, "alignment_mismatch": []},
        },
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    # The prompt MUST NOT insist on a misalignment Imp.
    assert "MUST flag the mismatch" not in prompt


def test_compose_ai_memory_note_emits_extra_frontmatter():
    from scripts.architect.sections import compose_ai_memory_note

    blocks = {n: f"body for {n}" for n in (
        "summary", "flow-memory-map", "backend-and-storage", "scope-and-lifecycle",
        "context-window-management", "compaction-strategy", "long-term-vs-short",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    note = compose_ai_memory_note(
        project="P",
        repo_label="local: /tmp/p",
        commit="abc1234",
        signal_sources=["scan: ai_memory"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks=blocks,
        memory_flows=1,
        stateless_flows=1,
        backend="redis",
    )
    assert "memory-flows: 1" in note
    assert "stateless-flows: 1" in note
    assert 'backend: "redis"' in note
    # Order: extra fields before ai-first: true.
    fm = note.split("---", 2)[1]
    assert fm.index("memory-flows") < fm.index("ai-first")


def test_compose_ai_rag_note_emits_embedding_aligned_bool_or_null():
    from scripts.architect.sections import compose_ai_rag_note

    blocks = {n: f"body for {n}" for n in (
        "summary", "rag-data-flow", "ingest-pipeline", "vector-store-config",
        "retrieve-strategy", "embedding-providers", "evaluation",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    # Case 1: aligned is false.
    note_false = compose_ai_rag_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_rag"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        rag_flows_read=1, rag_flows_write=1, vector_store="weaviate",
        embedding_aligned=False,
    )
    assert "embedding-aligned: false" in note_false
    # Case 2: aligned is None.
    note_null = compose_ai_rag_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_rag"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        rag_flows_read=1, rag_flows_write=0, vector_store="weaviate",
        embedding_aligned=None,
    )
    assert "embedding-aligned: null" in note_null
    # Case 3: aligned is True.
    note_true = compose_ai_rag_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_rag"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        rag_flows_read=1, rag_flows_write=1, vector_store="weaviate",
        embedding_aligned=True,
    )
    assert "embedding-aligned: true" in note_true


def test_scan_report_includes_ai_memory_and_ai_rag(tmp_path):
    """build_scan_report exposes ai_memory + ai_rag dicts when ai_flows detected."""
    import subprocess
    import os
    from scripts.architect.scan import build_scan_report

    # Set up a minimal repo + LangGraph flow with checkpointer.
    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)

    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname="m"\ndependencies=["langgraph"]\n',
        encoding="utf-8",
    )
    flow = tmp_path / "app"
    (flow / "nodes").mkdir(parents=True)
    for n in ("intent", "retrieve", "generate"):
        (flow / "nodes" / f"{n}.py").write_text(
            f"def {n}(s): return s\n",
            encoding="utf-8",
        )
    (flow / "prompts").mkdir()
    (flow / "prompts" / "system.py").write_text('SYSTEM = "x"\n', encoding="utf-8")
    (flow / "core").mkdir()
    (flow / "core" / "state.py").write_text("class S: pass\n", encoding="utf-8")
    (flow / "graph.py").write_text(
        "from langgraph.checkpoint.memory import MemorySaver\n"
        "from langgraph.graph import StateGraph\n"
        "checkpointer = MemorySaver()\n"
        "g = StateGraph(dict)\n"
        "g.add_node('intent', None)\n"
        "g.add_node('retrieve', None)\n"
        "g.add_node('generate', None)\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        env={**os.environ, "GIT_AUTHOR_DATE": "2026-05-28T00:00:00",
             "GIT_COMMITTER_DATE": "2026-05-28T00:00:00"},
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "ai_memory" in report
    assert "ai_rag" in report
    # The flow was detected; pick whichever slug landed.
    fm_slugs = list(report["ai_memory"]["per_flow"].keys())
    assert fm_slugs, f"expected at least one per-flow record; got {fm_slugs}"
    fr_slugs = list(report["ai_rag"]["per_flow"].keys())
    assert fr_slugs == fm_slugs, "memory + rag must cover same set of flows"
    # in-memory backend detected via MemorySaver.
    sole = report["ai_memory"]["per_flow"][fm_slugs[0]]
    assert sole["has_memory"] is True
    assert "in-memory" in sole["backends"]


def test_scan_report_ai_memory_ai_rag_empty_when_no_ai_flows(tmp_path):
    """No AI flows → both keys present with empty per_flow + zero counts."""
    import subprocess
    import os
    from scripts.architect.scan import build_scan_report

    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "main.py").write_text("def hello(): pass\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init"],
        cwd=tmp_path, check=True, capture_output=True,
        env={**os.environ, "GIT_AUTHOR_DATE": "2026-05-28T00:00:00",
             "GIT_COMMITTER_DATE": "2026-05-28T00:00:00"},
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert report["ai_memory"]["per_flow"] == {}
    assert report["ai_memory"]["summary"]["memory_flows"] == 0
    assert report["ai_rag"]["per_flow"] == {}
    assert report["ai_rag"]["summary"]["read_flows"] == 0
    assert report["ai_rag"]["summary"]["embedding_aligned"] is None
