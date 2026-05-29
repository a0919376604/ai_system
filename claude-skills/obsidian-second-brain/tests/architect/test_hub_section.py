from scripts.architect.refresh import render_hub_architecture_block


def test_hub_block_en():
    block = render_hub_architecture_block(
        commit="abc1234",
        last_scanned="2026-05-27",
        modules_active=4,
        modules_deprecated=1,
        repo_path="/path/to/repo",
        lang="en",
    )
    assert "## Architecture" in block
    assert "Overview: [[Architecture/overview]]" in block
    assert "(last scanned 2026-05-27 @ `abc1234`)" in block
    assert "Modules: 4 active, 1 deprecated" in block
    assert "/path/to/repo" in block


def test_hub_block_zh_tw():
    block = render_hub_architecture_block(
        commit="abc1234",
        last_scanned="2026-05-27",
        modules_active=4,
        modules_deprecated=1,
        repo_path="/path/to/repo",
        lang="zh-TW",
    )
    assert "## 架構" in block
    assert "總覽:" in block
    assert "(上次掃描 2026-05-27 @ `abc1234`)" in block
    assert "模組: 4 active, 1 deprecated" in block
