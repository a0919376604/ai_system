"""API routes module."""
from src.auth.login import authenticate
from src.db.queries import get_user


def main() -> None:
    print("hello")
