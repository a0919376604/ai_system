"""Tests for scripts.architect.ai_memory_detect.detect_memory."""
from __future__ import annotations

from pathlib import Path

from scripts.architect.ai_memory_detect import detect_memory


def test_detects_langgraph_custom_redis_saver(tmp_path: Path):
    """Custom RedisSaver subclass + thread_id-keyed checkpointer construction."""
    flow_root = tmp_path / "backend" / "engines" / "langgraph"
    flow_root.mkdir(parents=True)
    (flow_root / "graphs").mkdir()
    (flow_root / "graphs" / "main.py").write_text(
        "from engines.langgraph.utils.simple_redis_saver import SimpleRedisSaver\n"
        "from redis import Redis\n"
        "def get_checkpointer():\n"
        "    return SimpleRedisSaver(redis_client=Redis(), key_prefix='simple_ckpt_v2')\n"
        "workflow = StateGraph(AgentState)\n"
        "app = workflow.compile(checkpointer=get_checkpointer())\n",
        encoding="utf-8",
    )
    (flow_root / "utils").mkdir()
    (flow_root / "utils" / "simple_redis_saver.py").write_text(
        "from redis import Redis\n"
        "class SimpleRedisSaver:\n"
        "    def put(self, x): pass\n"
        "    def get(self, x): pass\n"
        "    def list(self, x): pass\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engines-langgraph"
        root_path = "backend/engines/langgraph"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["engines-langgraph"]
    assert fm["has_memory"] is True
    assert "redis" in fm["backends"]
    assert "SimpleRedisSaver" in fm["checkpointer_classes"]
    assert any("simple_ckpt_v2" in k for k in fm["key_patterns"])


def test_returns_has_memory_false_when_no_checkpointer(tmp_path: Path):
    """A flow with no checkpointer / saver / memory import reports has_memory=false."""
    flow_root = tmp_path / "modules" / "qa_to_kb"
    flow_root.mkdir(parents=True)
    (flow_root / "pipeline.py").write_text(
        "def run_pipeline(input):\n"
        "    return process(input)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "modules-qa-to-kb"
        root_path = "modules/qa_to_kb"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["modules-qa-to-kb"]
    assert fm["has_memory"] is False
    assert fm["backends"] == []
    assert fm["checkpointer_classes"] == []


def test_detects_langgraph_in_memory_checkpointer(tmp_path: Path):
    """`from langgraph.checkpoint.memory import MemorySaver` → in-memory backend."""
    flow_root = tmp_path / "agents" / "small"
    flow_root.mkdir(parents=True)
    (flow_root / "graph.py").write_text(
        "from langgraph.checkpoint.memory import MemorySaver\n"
        "from langgraph.graph import StateGraph\n"
        "checkpointer = MemorySaver()\n"
        "g = StateGraph(dict)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "agents-small"
        root_path = "agents/small"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["agents-small"]
    assert fm["has_memory"] is True
    assert "in-memory" in fm["backends"]


def test_detects_langchain_memory(tmp_path: Path):
    """`from langchain.memory import ConversationBufferMemory` → langchain backend."""
    flow_root = tmp_path / "agents" / "chat"
    flow_root.mkdir(parents=True)
    (flow_root / "agent.py").write_text(
        "from langchain.memory import ConversationBufferMemory\n"
        "memory = ConversationBufferMemory()\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "agents-chat"
        root_path = "agents/chat"

    result = detect_memory(tmp_path, [_Flow()])
    assert "langchain" in result["per_flow"]["agents-chat"]["backends"]


def test_extracts_reducer_cap_from_slice(tmp_path: Path):
    """`def add_messages_limited(...) -> List: ... return result[-100:]` → cap=100."""
    flow_root = tmp_path / "engine"
    flow_root.mkdir(parents=True)
    (flow_root / "state.py").write_text(
        "from typing import List\n"
        "def add_messages_limited(left: List, right: List) -> List[str]:\n"
        "    if not isinstance(left, list): left = []\n"
        "    if not isinstance(right, list): right = []\n"
        "    result = left + right\n"
        "    return result[-100:]\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engine"
        root_path = "engine"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["engine"]
    assert "add_messages_limited" in fm["reducer_funcs"]
    caps = {c["name"]: c["limit"] for c in fm["reducer_caps"]}
    assert caps.get("add_messages_limited") == 100


def test_langgraph_checkpoint_base_not_treated_as_backend(tmp_path: Path):
    """Repro: SimpleRedisSaver imports `from langgraph.checkpoint.base import (...)`.
    `base` is an abstract module, NOT a backend. Must not pollute backends list."""
    flow_root = tmp_path / "engine"
    flow_root.mkdir()
    (flow_root / "saver.py").write_text(
        "from langgraph.checkpoint.base import BaseCheckpointSaver\n"
        "from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer\n"
        "from langgraph.checkpoint.redis import RedisSaver\n"
        "class MySaver(BaseCheckpointSaver):\n"
        "    def put(self, x): pass\n"
        "    def get(self, x): pass\n"
        "    def list(self, x): pass\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engine"
        root_path = "engine"

    result = detect_memory(tmp_path, [_Flow()])
    backends = result["per_flow"]["engine"]["backends"]
    assert "base" not in backends, f"`base` is abstract, not a backend; got {backends}"
    assert "serde" not in backends, f"`serde` is serializer, not a backend; got {backends}"
    assert "redis" in backends, f"real redis import should be detected; got {backends}"


def test_summary_primary_backend_uniform(tmp_path: Path):
    """When 2 flows both have memory + same backend, summary reports uniform."""
    for slug in ("a", "b"):
        d = tmp_path / slug
        d.mkdir()
        (d / "saver.py").write_text(
            "class FooRedisSaver:\n"
            "    def put(self, x): pass\n"
            "    def get(self, x): pass\n"
            "    def list(self, x): pass\n",
            encoding="utf-8",
        )

    class _Flow:
        def __init__(self, slug):
            self.slug = slug
            self.root_path = slug

    result = detect_memory(tmp_path, [_Flow("a"), _Flow("b")])
    s = result["summary"]
    assert s["memory_flows"] == 2
    assert s["stateless_flows"] == 0
    assert s["primary_backend"] == "redis"
    assert s["uniform_backend"] is True
