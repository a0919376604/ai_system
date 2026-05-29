"""Detect RAG architecture signals per AI flow.

Pure function. Walks each AIFlow.root_path, returns per-flow signals
(role read/write/both/none, vector stores, embedding libs/models,
retrieve params, rerank libs, chunking) + cross-flow summary
(read_flows, write_flows, vector_stores, embedding_aligned, mismatch).

embedding_aligned is the money-shot field: 3-state bool (true / false /
null) reflecting whether write-side and read-side embedding models match.
"""
from __future__ import annotations

import re
from pathlib import Path

# ---------- vector store detection ----------

_VECTOR_STORE_HINTS = {
    # Hints are substring-matched against source text. Keep them specific
    # enough to avoid matching bare config strings (e.g. `vector_provider ==
    # "qdrant"` should NOT mark a flow as using qdrant — only actual imports
    # of qdrant_client should).
    "weaviate": ("import weaviate", "from weaviate", "langchain_weaviate"),
    "chromadb": ("import chromadb", "from chromadb", "langchain_chroma"),
    "pinecone": ("import pinecone", "from pinecone"),
    "qdrant": ("qdrant_client",),
    "lancedb": ("import lancedb", "from lancedb"),
    "faiss": ("import faiss", "from faiss"),
    "pgvector": ("from pgvector", "import pgvector"),
}

# Subdirectories that are test/eval scaffolding — their .py files are excluded
# from the role classifier because production role shouldn't be determined by
# eval-only code that exercises both write + read paths.
_NON_PRODUCTION_DIRS = {"evaluation", "tests", "test", "examples", "__pycache__"}

# ---------- embedding detection ----------

_EMBEDDING_LIB_HINTS = {
    "openai": ("OpenAIEmbeddings", "langchain_openai"),
    "google_generativeai": ("GoogleGenerativeAIEmbeddings", "google_generativeai", "google.generativeai"),
    "cohere": ("CohereEmbeddings",),
    "sentence_transformers": ("sentence_transformers", "SentenceTransformer"),
}

_EMBEDDING_MODEL_RE = re.compile(
    r"['\"](?P<model>(?:models/)?(?:text-embedding-[0-9a-z\-]+|all-MiniLM-[0-9a-z\-]+|embedding-[a-z0-9\-]+))['\"]"
)

# ---------- chunking detection ----------

_CHUNKING_CLASS_HINTS = (
    "RecursiveCharacterTextSplitter",
    "CharacterTextSplitter",
    "SemanticSplitterNodeParser",
    "TokenTextSplitter",
)

# ---------- rerank detection ----------

_RERANK_LIB_HINTS = {
    "jina-reranker": ("JinaReranker", "jina_reranker"),
    "cohere-rerank": ("CohereRerank",),
    "sentence_transformers-cross-encoder": ("CrossEncoder",),
}

# ---------- role classifier ----------

_READ_CALL_RE = re.compile(
    r"\.(?:similarity_search|hybrid|search|query|retrieve)\b"
)
_WRITE_CALL_RE = re.compile(
    r"\.(?:add_documents|upsert|add\s*\()"
)
_EMBED_CALL_RE = re.compile(
    r"\.(?:embed_documents|embed_query|embed_texts)\s*\("
)

# ---------- retrieve params ----------

_PARAM_RE = re.compile(
    r"\b(?P<key>top_k|hybrid_alpha|alpha|fetch_k|rerank_num|k)\s*=\s*(?P<val>[0-9.]+)"
)


def detect_rag(repo_root: Path, ai_flows: list) -> dict:
    repo_root = repo_root.resolve()
    per_flow: dict[str, dict] = {}

    for flow in ai_flows:
        flow_dir = repo_root / flow.root_path
        if not flow_dir.is_dir():
            per_flow[flow.slug] = _empty_rag_record()
            continue
        per_flow[flow.slug] = _scan_flow(flow_dir, repo_root)

    summary = _build_summary(per_flow)
    return {"per_flow": per_flow, "summary": summary}


def _empty_rag_record() -> dict:
    return {
        "role": "none",
        "vector_stores": [],
        "vector_store_sources": [],
        "embedding_libs": [],
        "embedding_models": [],
        "embedding_dims": None,
        "retrieve_params": {},
        "rerank_libs": [],
        "chunking": None,
    }


def _scan_flow(flow_dir: Path, repo_root: Path) -> dict:
    vector_stores: set[str] = set()
    vector_store_sources: list[str] = []
    embedding_libs: set[str] = set()
    embedding_models: set[str] = set()
    rerank_libs: set[str] = set()
    has_read_calls = False
    has_write_calls = False
    has_embed_calls = False
    retrieve_params: dict[str, float | int] = {}
    chunking: dict | None = None

    for py_file in flow_dir.rglob("*.py"):
        try:
            text = py_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = py_file.relative_to(repo_root).as_posix()

        # Detect whether the file lives under a non-production directory.
        # These contribute to vector store / embedding / rerank inventory (still
        # useful evidence) but NOT to role classification — eval scaffolding
        # exercising both read+write paths would otherwise misclassify flows
        # as role=both when production behavior is read-only or write-only.
        is_non_production = any(
            part in _NON_PRODUCTION_DIRS for part in py_file.relative_to(flow_dir).parts
        )

        # Vector store libs.
        for label, hints in _VECTOR_STORE_HINTS.items():
            if any(h in text for h in hints):
                if label not in vector_stores:
                    vector_stores.add(label)
                    vector_store_sources.append(rel)
        # Embedding libs.
        for label, hints in _EMBEDDING_LIB_HINTS.items():
            if any(h in text for h in hints):
                embedding_libs.add(label)
        # Embedding models.
        for m in _EMBEDDING_MODEL_RE.finditer(text):
            embedding_models.add(m.group("model"))
        # Rerank libs.
        for label, hints in _RERANK_LIB_HINTS.items():
            if any(h in text for h in hints):
                rerank_libs.add(label)
        # Role-classifier hints — skip non-production dirs.
        if not is_non_production:
            if _READ_CALL_RE.search(text):
                has_read_calls = True
            if _WRITE_CALL_RE.search(text):
                has_write_calls = True
            if _EMBED_CALL_RE.search(text):
                has_embed_calls = True
        # Retrieve params.
        for m in _PARAM_RE.finditer(text):
            k = m.group("key")
            v = m.group("val")
            val: float | int = float(v) if "." in v else int(v)
            retrieve_params.setdefault(k, val)
        # Chunking.
        if chunking is None:
            for cls in _CHUNKING_CLASS_HINTS:
                if cls in text:
                    chunking = {"strategy": cls, "source": rel}
                    break

    role = _classify_role(has_read_calls, has_write_calls, has_embed_calls)

    return {
        "role": role,
        "vector_stores": sorted(vector_stores),
        "vector_store_sources": vector_store_sources,
        "embedding_libs": sorted(embedding_libs),
        "embedding_models": sorted(embedding_models),
        "embedding_dims": None,
        "retrieve_params": retrieve_params,
        "rerank_libs": sorted(rerank_libs),
        "chunking": chunking,
    }


def _classify_role(read: bool, write: bool, embed: bool) -> str:
    if write and read:
        return "both"
    if write or (embed and not read):
        return "write" if write or embed else "none"
    if read:
        return "read"
    return "none"


def _build_summary(per_flow: dict) -> dict:
    read_flows = sum(1 for v in per_flow.values() if v["role"] in ("read", "both"))
    write_flows = sum(1 for v in per_flow.values() if v["role"] in ("write", "both"))
    all_stores: set[str] = set()
    for v in per_flow.values():
        all_stores.update(v["vector_stores"])

    write_models: set[str] = set()
    read_models: set[str] = set()
    for v in per_flow.values():
        if v["role"] in ("write", "both"):
            write_models.update(v["embedding_models"])
        if v["role"] in ("read", "both"):
            read_models.update(v["embedding_models"])

    if not write_models or not read_models:
        embedding_aligned = None
        alignment_mismatch: list[dict] = []
    elif write_models == read_models:
        embedding_aligned = True
        alignment_mismatch = []
    else:
        embedding_aligned = False
        alignment_mismatch = []
        for slug_w, v_w in per_flow.items():
            if v_w["role"] not in ("write", "both"):
                continue
            for slug_r, v_r in per_flow.items():
                if v_r["role"] not in ("read", "both"):
                    continue
                if set(v_w["embedding_models"]) == set(v_r["embedding_models"]):
                    continue
                alignment_mismatch.append({
                    "write": {"flow": slug_w, "model": ",".join(v_w["embedding_models"]) or "?"},
                    "read": {"flow": slug_r, "model": ",".join(v_r["embedding_models"]) or "?"},
                })

    if not all_stores:
        primary_store = "none"
    elif len(all_stores) == 1:
        primary_store = next(iter(all_stores))
    else:
        primary_store = "mixed"

    return {
        "read_flows": read_flows,
        "write_flows": write_flows,
        "vector_stores": sorted(all_stores),
        "primary_vector_store": primary_store,
        "embedding_aligned": embedding_aligned,
        "alignment_mismatch": alignment_mismatch,
    }
