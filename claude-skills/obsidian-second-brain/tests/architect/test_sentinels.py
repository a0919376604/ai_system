from scripts.architect.sentinels import parse_blocks, render_block, GeneratedBlock, UserBlock


SAMPLE = """\
## For future Claude

Top preamble. Not in a sentinel.

<!-- @generated:start what-it-does -->
LLM paragraph here.
<!-- @generated:end what-it-does -->

<!-- @user:start notes -->
## Notes
User wrote this.
<!-- @user:end notes -->
"""


def test_parses_generated_block():
    blocks = parse_blocks(SAMPLE)
    gen = [b for b in blocks if isinstance(b, GeneratedBlock)]
    assert len(gen) == 1
    assert gen[0].name == "what-it-does"
    assert "LLM paragraph" in gen[0].body


def test_parses_user_block():
    blocks = parse_blocks(SAMPLE)
    user = [b for b in blocks if isinstance(b, UserBlock)]
    assert len(user) == 1
    assert user[0].name == "notes"
    assert "User wrote this" in user[0].body


def test_render_generated_block_round_trips():
    blocks = parse_blocks(SAMPLE)
    gen = [b for b in blocks if isinstance(b, GeneratedBlock)][0]
    rendered = render_block(gen)
    assert "@generated:start what-it-does" in rendered
    assert "@generated:end what-it-does" in rendered
    assert "LLM paragraph" in rendered
