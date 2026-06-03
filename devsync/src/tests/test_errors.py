from devsync.errors import (
    DevsyncError,
    MutagenDaemonError,
    NoSuchRepo,
    NoSuchServer,
    ServerUnreachable,
    SessionAlreadyExists,
)


def test_all_exceptions_inherit_from_devsync_error():
    for cls in [
        NoSuchRepo,
        NoSuchServer,
        ServerUnreachable,
        MutagenDaemonError,
        SessionAlreadyExists,
    ]:
        assert issubclass(cls, DevsyncError)


def test_no_such_repo_lists_candidates():
    err = NoSuchRepo("missing", ["alpha", "beta"])
    assert "missing" in str(err)
    assert "alpha" in str(err)


def test_server_unreachable_includes_host():
    err = ServerUnreachable("dl02", "192.168.90.32")
    assert "dl02" in str(err)
    assert "192.168.90.32" in str(err)
