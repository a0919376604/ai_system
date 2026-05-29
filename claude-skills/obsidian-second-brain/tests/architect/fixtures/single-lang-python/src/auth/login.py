"""Auth login module."""

def authenticate(username: str, password: str) -> bool:
    return bool(username and password)
