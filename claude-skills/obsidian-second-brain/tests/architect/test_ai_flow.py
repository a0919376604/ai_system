from pathlib import Path

from scripts.architect.ai_flow import AIFlow, detect_ai_flows

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_detects_langgraph_project():
    flows = detect_ai_flows(FIXTURE_DIR / "langgraph_proj")
    assert len(flows) == 1
    f = flows[0]
    assert f.framework == "langgraph"
    assert f.node_count >= 3
    assert "app" in f.root_path or "graph" in f.root_path
    assert any("prompts" in p for p in f.prompt_files)


def test_detects_custom_pipeline_project():
    flows = detect_ai_flows(FIXTURE_DIR / "custom_pipeline_proj")
    assert len(flows) == 1
    f = flows[0]
    assert f.framework == "custom-pipeline"
    assert "pipeline" in f.root_path
    assert any("prompts.toml" in p for p in f.prompt_files)


def test_detects_no_ai_in_flask_project():
    flows = detect_ai_flows(FIXTURE_DIR / "no_ai_proj")
    assert flows == []


def test_node_count_threshold_enforced(tmp_path: Path):
    """Project with langgraph dep but only 1 node should NOT count as AI flow."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "tiny"\ndependencies = ["langgraph"]\n'
    )
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "graph.py").write_text(
        'from langgraph.graph import StateGraph\n'
        'g = StateGraph(dict)\n'
        'g.add_node("only", lambda s: s)\n'  # ONLY 1 node
    )
    flows = detect_ai_flows(tmp_path)
    assert flows == []


def test_ai_flow_slug_is_filename_safe():
    """AIFlow.slug must be ascii lowercase hyphen - usable as filename."""
    import re
    flows = detect_ai_flows(FIXTURE_DIR / "langgraph_proj")
    for f in flows:
        assert re.match(r"^[a-z0-9-]+$", f.slug), f"bad slug: {f.slug!r}"


def test_parent_candidate_dropped_when_nested_flow_exists(tmp_path: Path):
    """Repro: langlive-line-oa had `backend/engines/` AND `backend/engines/langgraph/`
    both detected because `engines` is in _AI_DIR_NAMES. Only the nested specific
    flow should survive."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["langgraph", "openai"]\n'
    )
    # Parent: backend/engines/ has stray .py files (matches _AI_DIR_NAMES dir scan)
    eng = tmp_path / "backend" / "engines"
    eng.mkdir(parents=True)
    (eng / "__init__.py").write_text("")
    (eng / "helper.py").write_text("def f(): pass\n")
    # Nested LangGraph subsystem under backend/engines/langgraph/
    lg = eng / "langgraph"
    (lg / "core").mkdir(parents=True)
    (lg / "core" / "state.py").write_text("class S: pass\n")
    (lg / "nodes").mkdir()
    for n in ("intent", "retrieve", "generate"):
        (lg / "nodes" / f"{n}.py").write_text(f"def {n}(s): return s\n")
    (lg / "prompts").mkdir()
    (lg / "prompts" / "system.py").write_text('SYSTEM = "x"\n')
    (lg / "graph.py").write_text(
        "from langgraph.graph import StateGraph\n"
        "g = StateGraph(dict)\n"
        "g.add_node('intent', None)\n"
        "g.add_node('retrieve', None)\n"
        "g.add_node('generate', None)\n"
    )
    flows = detect_ai_flows(tmp_path)
    roots = [f.root_path for f in flows]
    assert len(flows) == 1, f"expected only the nested flow; got {roots}"
    assert flows[0].root_path == "backend/engines/langgraph", \
        f"expected backend/engines/langgraph survives; got {flows[0].root_path}"


def test_langchain_utility_imports_do_not_force_langchain_framework(tmp_path: Path):
    """Repro: modules/qa_to_kb uses `from langchain_core.documents import Document`
    and `from langchain_weaviate.vectorstores import WeaviateVectorStore` as utility
    libs for a vector store integration. The module's primary architecture is
    a custom pipeline (pipeline.py + nodes/ + prompts.toml). It must classify
    as custom-pipeline, not langchain."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["langchain-core", "openai"]\n'
    )
    qa = tmp_path / "modules" / "qa_to_kb"
    (qa / "config").mkdir(parents=True)
    (qa / "config" / "prompts.toml").write_text(
        '[summarize]\nbody = "summarize this"\n'
    )
    (qa / "nodes").mkdir()
    for n in ("ingest", "clean", "summarize"):
        (qa / "nodes" / f"{n}.py").write_text(
            "from langchain_core.documents import Document\n"
            "import openai\n"
            "def run(x: Document): return x\n"
        )
    (qa / "pipeline.py").write_text(
        "import openai\n"
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "from modules.qa_to_kb.nodes import ingest, clean, summarize\n"
        "def run_pipeline(x): return summarize(clean(ingest(x)))\n"
    )
    flows = detect_ai_flows(tmp_path)
    assert len(flows) == 1, f"expected 1 flow; got {len(flows)}"
    f = flows[0]
    assert f.framework == "custom-pipeline", \
        f"langchain_core/langchain_weaviate are utility libs - " \
        f"structural pipeline.py+nodes/+prompts pattern must win; got {f.framework}"


def test_local_evidence_wins_over_repo_dep(tmp_path: Path):
    """Repro: langlive-line-oa's `modules/qa_to_kb/` was misclassified as `langgraph`
    because the repo-level pyproject.toml lists langgraph (used elsewhere). But
    the candidate's local code only imports openai + has pipeline.py + nodes/ +
    prompts.toml. Classification should be custom-pipeline, not langgraph."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["langgraph", "openai"]\n'
    )
    qa = tmp_path / "modules" / "qa_to_kb"
    (qa / "config").mkdir(parents=True)
    (qa / "config" / "prompts.toml").write_text(
        '[summarize]\nbody = "summarize this"\n'
    )
    (qa / "nodes").mkdir()
    for n in ("ingest", "clean", "summarize"):
        (qa / "nodes" / f"{n}.py").write_text(
            "import openai\ndef run(x): return x\n"
        )
    (qa / "pipeline.py").write_text(
        "import openai\n"
        "from modules.qa_to_kb.nodes import ingest, clean, summarize\n"
        "def run_pipeline(x): return summarize(clean(ingest(x)))\n"
    )
    flows = detect_ai_flows(tmp_path)
    assert len(flows) == 1, f"expected 1 flow; got {len(flows)}"
    f = flows[0]
    assert f.framework == "custom-pipeline", \
        f"expected custom-pipeline (local code imports openai, not langgraph); got {f.framework}"
    assert f.root_path == "modules/qa_to_kb"
    assert any("prompts.toml" in p for p in f.prompt_files)


def test_custom_pipeline_detected_without_nodes_dir_when_llm_imports(tmp_path: Path):
    """Repro: ai-eden-service has app/pipeline.py + LLM provider imports but
    no nodes/ dir. Should still detect as custom-pipeline."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["openai"]\n', encoding="utf-8"
    )
    app = tmp_path / "app"
    (app / "providers").mkdir(parents=True)
    (app / "providers" / "openai_provider.py").write_text(
        "from openai import OpenAI\nclient = OpenAI()\n", encoding="utf-8"
    )
    (app / "pipeline.py").write_text(
        "from app.providers.openai_provider import client\n"
        "def run(): return client.chat.completions.create(messages=[])\n",
        encoding="utf-8",
    )
    (app / "prompts.toml").write_text(
        '[system]\nbody = "You are an assistant"\n', encoding="utf-8"
    )
    from scripts.architect.ai_flow import detect_ai_flows
    flows = detect_ai_flows(tmp_path)
    assert len(flows) == 1
    assert flows[0].framework == "custom-pipeline"


def test_custom_pipeline_still_requires_pipeline_file(tmp_path: Path):
    """Sanity: openai imports + no pipeline.py → not a flow."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["openai"]\n', encoding="utf-8"
    )
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "main.py").write_text(
        "from openai import OpenAI\ndef hello(): pass\n", encoding="utf-8"
    )
    from scripts.architect.ai_flow import detect_ai_flows
    flows = detect_ai_flows(tmp_path)
    assert flows == []


def test_custom_pipeline_with_companion_archetype_waives_prompts_file(tmp_path: Path):
    """v4.6 follow-up to Task 4: when companion_archetype=True is passed,
    the custom-pipeline branch's prompts-file requirement is waived.

    Mirrors ai-eden-service's real layout: app/pipeline.py + app/providers/*
    with `openai` imports + NO prompts.toml/.yaml/.md. Without the companion
    signal these stacks fall off the detector; with it they classify as
    custom-pipeline.
    """
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["openai"]\n', encoding="utf-8"
    )
    app = tmp_path / "app"
    (app / "providers").mkdir(parents=True)
    (app / "providers" / "openai_provider.py").write_text(
        'from openai import OpenAI\n'
        'SYSTEM_PROMPT = "You are an AI companion."\n'
        'client = OpenAI()\n',
        encoding="utf-8",
    )
    (app / "pipeline.py").write_text(
        "from app.providers.openai_provider import client\n"
        "def run(): return client.chat.completions.create(messages=[])\n",
        encoding="utf-8",
    )
    # No prompts.toml / prompts.yaml / prompts.md anywhere.
    from scripts.architect.ai_flow import detect_ai_flows

    # Without companion signal: detector misses (the pre-v4.6 behavior).
    assert detect_ai_flows(tmp_path) == []

    # With companion signal: detector picks it up.
    flows = detect_ai_flows(tmp_path, companion_archetype=True)
    assert len(flows) == 1, f"expected 1 flow, got {len(flows)}"
    assert flows[0].framework == "custom-pipeline"


def test_companion_archetype_does_not_force_unrelated_repos(tmp_path: Path):
    """Sanity: passing companion_archetype=True doesn't magically create a
    flow when pipeline.py / LLM signals are absent — the other clauses still
    gate detection."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = []\n', encoding="utf-8"
    )
    (tmp_path / "main.py").write_text("def hello(): pass\n", encoding="utf-8")
    from scripts.architect.ai_flow import detect_ai_flows
    assert detect_ai_flows(tmp_path, companion_archetype=True) == []
