"""Tests for scripts.architect.ai_rag_detect.detect_rag."""
from __future__ import annotations

from pathlib import Path

from scripts.architect.ai_rag_detect import detect_rag


def test_detects_weaviate_retrieve_role_read(tmp_path: Path):
    """Flow calling `.similarity_search` + `.hybrid` → role='read', vector_store=weaviate."""
    flow_root = tmp_path / "engines"
    flow_root.mkdir()
    (flow_root / "retrieve.py").write_text(
        "import weaviate\n"
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "vs = WeaviateVectorStore(client=weaviate.Client('http://x'))\n"
        "def retrieve(query):\n"
        "    return vs.similarity_search(query, k=12)\n",
        encoding="utf-8",
    )
    (flow_root / "embed.py").write_text(
        "from langchain_google_genai import GoogleGenerativeAIEmbeddings\n"
        "embedding = GoogleGenerativeAIEmbeddings(model='models/text-embedding-004')\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engines"
        root_path = "engines"

    result = detect_rag(tmp_path, [_Flow()])
    fr = result["per_flow"]["engines"]
    assert fr["role"] == "read"
    assert "weaviate" in fr["vector_stores"]
    assert "google_generativeai" in fr["embedding_libs"]
    assert "models/text-embedding-004" in fr["embedding_models"]


def test_detects_top_k_and_alpha_params(tmp_path: Path):
    """Regex extracts top_k= and hybrid_alpha= from retrieve calls."""
    flow_root = tmp_path / "engines"
    flow_root.mkdir()
    (flow_root / "retrieve.py").write_text(
        "import weaviate\n"
        "def retrieve(query):\n"
        "    return search(query, top_k=12, hybrid_alpha=0.8, rerank_num=6)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engines"
        root_path = "engines"

    result = detect_rag(tmp_path, [_Flow()])
    params = result["per_flow"]["engines"]["retrieve_params"]
    assert params.get("top_k") == 12
    assert params.get("hybrid_alpha") == 0.8
    assert params.get("rerank_num") == 6


def test_detects_write_role_via_add_documents(tmp_path: Path):
    flow_root = tmp_path / "ingest"
    flow_root.mkdir()
    (flow_root / "writer.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs = WeaviateVectorStore(embedding=embed)\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "ingest"
        root_path = "ingest"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["per_flow"]["ingest"]["role"] == "write"


def test_summary_embedding_aligned_false_when_models_differ(tmp_path: Path):
    """Write flow uses text-embedding-3-small; read flow uses text-embedding-004.
    Summary must flag embedding_aligned=false + populate alignment_mismatch."""
    writer = tmp_path / "writer"
    writer.mkdir()
    (writer / "w.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )
    reader = tmp_path / "reader"
    reader.mkdir()
    (reader / "r.py").write_text(
        "from langchain_google_genai import GoogleGenerativeAIEmbeddings\n"
        "embed = GoogleGenerativeAIEmbeddings(model='models/text-embedding-004')\n"
        "vs.similarity_search(q, k=5)\n",
        encoding="utf-8",
    )

    class _Flow:
        def __init__(self, slug):
            self.slug = slug
            self.root_path = slug

    result = detect_rag(tmp_path, [_Flow("writer"), _Flow("reader")])
    s = result["summary"]
    assert s["embedding_aligned"] is False
    assert len(s["alignment_mismatch"]) == 1
    mismatch = s["alignment_mismatch"][0]
    assert mismatch["write"]["flow"] == "writer"
    assert mismatch["read"]["flow"] == "reader"
    assert "text-embedding-3-small" in mismatch["write"]["model"]
    assert "text-embedding-004" in mismatch["read"]["model"]


def test_summary_embedding_aligned_true_when_both_use_same_model(tmp_path: Path):
    for slug in ("writer", "reader"):
        d = tmp_path / slug
        d.mkdir()
        suffix = "vs.add_documents(docs)" if slug == "writer" else "vs.similarity_search(q)"
        (d / "x.py").write_text(
            "from langchain_openai import OpenAIEmbeddings\n"
            "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
            f"{suffix}\n",
            encoding="utf-8",
        )

    class _Flow:
        def __init__(self, slug):
            self.slug = slug
            self.root_path = slug

    result = detect_rag(tmp_path, [_Flow("writer"), _Flow("reader")])
    assert result["summary"]["embedding_aligned"] is True
    assert result["summary"]["alignment_mismatch"] == []


def test_summary_embedding_aligned_null_when_only_one_side(tmp_path: Path):
    """Only a write flow exists → alignment is N/A (null), not false."""
    writer = tmp_path / "writer"
    writer.mkdir()
    (writer / "w.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "writer"
        root_path = "writer"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["summary"]["embedding_aligned"] is None


def test_returns_role_none_when_no_rag_calls(tmp_path: Path):
    flow_root = tmp_path / "plain"
    flow_root.mkdir()
    (flow_root / "x.py").write_text(
        "def hello(): pass\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "plain"
        root_path = "plain"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["per_flow"]["plain"]["role"] == "none"


def test_empty_ai_flows_list_returns_empty(tmp_path: Path):
    result = detect_rag(tmp_path, [])
    assert result["per_flow"] == {}
    assert result["summary"]["read_flows"] == 0
    assert result["summary"]["write_flows"] == 0
    assert result["summary"]["embedding_aligned"] is None


def test_qdrant_string_in_config_does_not_trigger_qdrant_store(tmp_path: Path):
    """Repro: langlive mem0_memory.py has `vector_provider == 'qdrant'` config string.
    That's runtime-conditional, not an actual qdrant import. Must NOT mark store
    as qdrant unless `qdrant_client` is imported."""
    flow_root = tmp_path / "mem0"
    flow_root.mkdir()
    (flow_root / "memory.py").write_text(
        "import os\n"
        "def setup(vector_provider: str):\n"
        '    if vector_provider == "qdrant":\n'
        '        host = os.getenv("QDRANT_HOST", "localhost")\n'
        '    elif vector_provider == "weaviate":\n'
        "        import weaviate\n"
        "        client = weaviate.Client()\n"
        "        return client\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "mem0"
        root_path = "mem0"

    result = detect_rag(tmp_path, [_Flow()])
    stores = result["per_flow"]["mem0"]["vector_stores"]
    assert "qdrant" not in stores, f"qdrant config string should not trigger; got {stores}"
    assert "weaviate" in stores


def test_evaluation_subdir_does_not_drive_role_to_both(tmp_path: Path):
    """Repro: qa_to_kb has evaluation/ subdir with similarity_search + add_documents
    calls (eval-only). Production pipeline is write-only. Role must be 'write',
    not 'both'."""
    flow_root = tmp_path / "qa_to_kb"
    (flow_root / "evaluation" / "retrieval").mkdir(parents=True)
    # Eval-only file: BOTH read and write calls.
    (flow_root / "evaluation" / "retrieval" / "eval.py").write_text(
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "vs = WeaviateVectorStore()\n"
        "vs.add_documents(docs)\n"
        "vs.similarity_search(q, k=5)\n",
        encoding="utf-8",
    )
    # Production pipeline: write-only.
    (flow_root / "pipeline.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs = WeaviateVectorStore(embedding=embed)\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "qa_to_kb"
        root_path = "qa_to_kb"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["per_flow"]["qa_to_kb"]["role"] == "write", (
        f"evaluation/ subdir should not drive role to both; "
        f"got {result['per_flow']['qa_to_kb']['role']}"
    )
