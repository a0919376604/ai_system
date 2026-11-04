"""Find external-system touchpoints in tracked Python files without running source."""
import argparse
import ast
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path

from render import SpecError, load_spec


def git_output(repo: str, *args: str) -> str:
    result = subprocess.run(["git", "-C", repo, *args], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(result.stderr.strip())
    return result.stdout


def scan(repo: str, systems: list, exclude: list) -> dict:
    if not Path(repo).is_dir():
        raise ValueError("not a repository: " + repo)
    found = {system["id"]: [] for system in systems}
    files = sorted(filter(None, git_output(repo, "ls-files", "-z", "*.py").split("\0")))
    for file in files:
        path = Path(file)
        if (any(part in ("tests", "test") for part in path.parts) or
                fnmatch.fnmatch(path.name, "test_*.py") or fnmatch.fnmatch(path.name, "*_test.py") or
                any(fnmatch.fnmatch(file, pattern) for pattern in exclude)):
            continue
        try:
            source = (Path(repo) / file).read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            print("seams: cannot read " + file, file=sys.stderr)
            continue
        imports = []
        try:
            tree = ast.parse(source, filename=file)
        except (SyntaxError, ValueError):
            print("seams: cannot parse " + file, file=sys.stderr)
        else:
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.extend((alias.name, node.lineno) for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.level == 0:
                    imports.append((node.module, node.lineno))
        for system in systems:
            lines = set()
            for probe in system["probes"]:
                pattern = probe["pattern"]
                if probe["kind"] == "import":
                    lines.update(line for name, line in imports
                                 if name == pattern or name.startswith(pattern + "."))
                else:
                    lines.update(line for line, text in enumerate(source.split("\n"), 1)
                                 if re.search(pattern, text))
            if lines:
                found[system["id"]].append({
                    "file": file, "lines": sorted(lines),
                    "adapter": any(fnmatch.fnmatch(file, pattern) for pattern in system["adapters"]),
                })
    return found


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo")
    parser.add_argument("spec")
    args = parser.parse_args(argv)
    try:
        spec = load_spec(args.spec)
        from check import check_spec
        findings = check_spec(spec)
        if findings:
            raise ValueError("\n".join(findings))
        if spec.get("page") != "seams":
            raise ValueError("spec.page must be seams")
        actual = scan(args.repo, spec["systems"], spec.get("exclude", []))
        commit = git_output(args.repo, "rev-parse", "HEAD").strip()
        notes = {(system["id"], point["file"]): point["note"]
                 for system in spec["systems"] for point in system["touchpoints"] if "note" in point}
        for system in spec["systems"]:
            for point in actual[system["id"]]:
                key = (system["id"], point["file"])
                if key in notes:
                    point["note"] = notes[key]
            system["touchpoints"] = actual[system["id"]]
        spec["repo"]["commit"] = commit
        Path(args.spec).write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (SpecError, OSError, UnicodeError, ValueError) as exc:
        print("seams: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
