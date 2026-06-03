from typer.testing import CliRunner

from devsync.cli import app

_SESSION = {
    "name": "ai-eden-service--dl02",
    "labels": {
        "managed-by": "devsync",
        "repo": "ai-eden-service",
        "server": "dl02",
    },
    "beta": {"url": {"host": "dl02", "path": "/home/leric/code/ai-eden-service"}},
}


def test_ssh_resolves_session_and_execs(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[_SESSION])
    execvp = mocker.patch("os.execvp")
    result = CliRunner().invoke(app, ["ssh", "ai-eden-service"])
    assert result.exit_code == 0, result.stdout
    execvp.assert_called_once()
    args, _ = execvp.call_args
    assert args[0] == "ssh"
    assert "dl02" in args[1]
    assert any("/home/leric/code/ai-eden-service" in a for a in args[1])


def test_ssh_no_session_exits_nonzero(mocker):
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[])
    result = CliRunner().invoke(app, ["ssh", "ai-eden-service"])
    assert result.exit_code != 0
    assert "no session" in result.stdout.lower() or "no session" in result.stderr.lower()
