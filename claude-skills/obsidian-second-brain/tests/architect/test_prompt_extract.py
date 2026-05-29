import hashlib
from pathlib import Path

from scripts.architect.prompt_extract import ExtractedPrompt, extract_prompts


def test_extracts_toml_config_prompts(tmp_path: Path):
    (tmp_path / "config").mkdir()
    (tmp_path / "config" / "prompts.toml").write_text(
        '[summarize]\n'
        'template = """Summarize this:\n{conversation}\n\nReturn 3 bullets."""\n'
        '\n'
        '[classify]\n'
        'template = "Classify: {text}"\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "summarize" in names
    assert "classify" in names
    summ = next(p for p in prompts if p.name == "summarize")
    assert "Summarize this" in summ.body
    assert "{conversation}" in summ.body
    assert summ.is_dynamic is False
    assert summ.source.startswith("config/prompts.toml")
    assert summ.source_hash.startswith("sha256:")
    # Reproducible hash
    expected = "sha256:" + hashlib.sha256(summ.body.encode("utf-8")).hexdigest()
    assert summ.source_hash == expected
    assert summ.extraction_method == "toml-config"


def test_extracts_python_module_constant(tmp_path: Path):
    (tmp_path / "prompts").mkdir()
    (tmp_path / "prompts" / "intent.py").write_text(
        '"""Intent classifier prompts."""\n'
        '\n'
        'INTENT_PROMPT = """You are an intent classifier.\n'
        'Given: {user_message}\n'
        'Return: PRODUCT | COMPLAINT | OTHER.\n'
        '"""\n'
        '\n'
        '# Helper not exported\n'
        'def build(): pass\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "INTENT_PROMPT" in names
    intent = next(p for p in prompts if p.name == "INTENT_PROMPT")
    assert "intent classifier" in intent.body.lower()
    assert "{user_message}" in intent.body
    assert intent.is_dynamic is False
    assert intent.extraction_method == "module-constant"
    assert "prompts/intent.py" in intent.source


def test_extracts_system_prompt_pattern(tmp_path: Path):
    (tmp_path / "agent.py").write_text(
        '\n'
        'SYSTEM_PROMPT = """You are a helpful assistant focused on customer service."""\n'
        'USER_PROMPT_TEMPLATE = "Question: {q}"\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "SYSTEM_PROMPT" in names
    assert "USER_PROMPT_TEMPLATE" in names


def test_extracts_langchain_chat_prompt_template(tmp_path: Path):
    (tmp_path / "chain.py").write_text(
        'from langchain_core.prompts import ChatPromptTemplate\n'
        'from langchain_core.messages import SystemMessage, HumanMessage\n'
        '\n'
        'CHAT_PROMPT = ChatPromptTemplate.from_messages([\n'
        '    SystemMessage(content="You are an expert at categorization."),\n'
        '    HumanMessage(content="Categorize: {input}"),\n'
        '])\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "CHAT_PROMPT" in names
    cp = next(p for p in prompts if p.name == "CHAT_PROMPT")
    assert "expert at categorization" in cp.body
    assert "Categorize" in cp.body
    assert cp.is_dynamic is False
    assert cp.extraction_method == "langchain-chat-prompt-template"


def test_skips_non_prompt_string_constants(tmp_path: Path):
    """Random string constants (not prompt-like) should NOT be extracted."""
    (tmp_path / "config.py").write_text(
        'DATABASE_URL = "postgresql://localhost/db"\n'
        'API_VERSION = "v1"\n'
        'SIMPLE_NAME = "Hello"\n'
    )
    prompts = extract_prompts(tmp_path)
    # No PROMPT-suffix or PROMPT-prefix names → nothing extracted from Python constants.
    # But config.py has no .toml so 0 prompts.
    assert prompts == []


def test_source_hash_changes_when_body_changes(tmp_path: Path):
    (tmp_path / "config").mkdir()
    (tmp_path / "config" / "prompts.toml").write_text('[p]\ntemplate = "v1"\n')
    h1 = extract_prompts(tmp_path)[0].source_hash
    (tmp_path / "config" / "prompts.toml").write_text('[p]\ntemplate = "v2"\n')
    h2 = extract_prompts(tmp_path)[0].source_hash
    assert h1 != h2


def test_dynamic_prompt_concat_detected(tmp_path: Path):
    """A prompt assembled via string concat across multiple sources should be marked dynamic."""
    (tmp_path / "agent.py").write_text(
        '\n'
        '_BASE = "You are an assistant."\n'
        '_TONE = "Be concise."\n'
        '\n'
        'def make_prompt(user_input: str) -> str:\n'
        '    return _BASE + " " + _TONE + " Question: " + user_input\n'
        '\n'
        '# Note: no SYSTEM_PROMPT module constant exists.\n'
    )
    prompts = extract_prompts(tmp_path)
    # Two constants are short individually (don't look like prompts on their own).
    # The concat function isn't a static prompt — should NOT extract a stitched-together fake.
    # Either: nothing is extracted, OR if anything is extracted it's marked is_dynamic=True.
    for p in prompts:
        if "Question" in p.body and "assistant" in p.body:
            # If something looking like the concat IS produced, it MUST be marked dynamic.
            assert p.is_dynamic is True, "stitched-together prompt must be marked dynamic"


def test_dynamic_marker_for_format_string_calls(tmp_path: Path):
    """If a make_prompt() / build_prompt() function is detected with multiple inputs, mark dynamic."""
    (tmp_path / "agent.py").write_text(
        '\n'
        'def build_system_prompt(persona: str, tools: list[str]) -> str:\n'
        '    return f"You are {persona}. Available tools: {tools}. Be helpful."\n'
    )
    # No module-level constant; function with dynamic params doesn't produce a static extract.
    # This is a "skip cleanly" case — extract_prompts returns empty.
    prompts = extract_prompts(tmp_path)
    assert prompts == [] or all(p.is_dynamic for p in prompts)
