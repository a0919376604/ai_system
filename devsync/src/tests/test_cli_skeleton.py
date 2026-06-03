from typer.testing import CliRunner

from devsync.cli import app


def test_version_flag_prints_version():
    runner = CliRunner()
    result = runner.invoke(app, ["--version"])
    assert result.exit_code == 0
    assert "0.2.0" in result.stdout


def test_help_lists_commands():
    runner = CliRunner()
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    # All commands should appear in help
    for cmd in ["start", "stop", "ls", "doctor", "ssh", "status", "flush", "logs"]:
        assert cmd in result.stdout
