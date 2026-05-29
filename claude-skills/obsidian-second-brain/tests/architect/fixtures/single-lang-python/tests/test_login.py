from src.auth.login import authenticate


def test_authenticate():
    assert authenticate("u", "p")
