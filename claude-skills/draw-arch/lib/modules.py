"""Build a deterministic module import matrix using only Python's AST (Python 3.9)."""
import argparse
import ast
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path


def skipped(path: Path) -> bool:
    return (any(p.startswith(".") or p in ("__pycache__", "tests", "test") for p in path.parts)
            or path.name.startswith("test_") or path.name.endswith("_test.py"))


def scan(repo: str, roots: list) -> dict:
    directory = Path(repo).resolve()
    entries = []
    for root in roots:
        base = (directory / root).resolve()
        if not base.is_dir():
            raise ValueError("root not found: " + root)
        relative = base.relative_to(directory)
        # The bare "" prefix treats the root as a sys.path entry (src layout); a child named
        # like a stdlib module would also catch that import — rename the root if that bites.
        prefixes = [".".join(relative.parts[i:]) for i in range(len(relative.parts) + 1)]
        packages = {c.name for c in base.iterdir() if c.is_dir()}
        for child in sorted(base.iterdir()):
            if skipped(child.relative_to(base)) or child.name == "__init__.py":
                continue
            if child.is_file() and child.stem in packages:
                continue  # Python imports the package, not the file beside it.
            if child.is_dir():
                files = sorted(p for p in child.rglob("*.py") if not skipped(p.relative_to(base)))
            else:
                files = [child] if child.suffix == ".py" else []
            if files:
                stem = child.name if child.is_dir() else child.stem
                entries.append({"id": stem, "stem": stem, "root": root, "base": base,
                                "path": child, "files": files, "prefixes": prefixes})
    stems = Counter(e["stem"] for e in entries)
    for entry in entries:
        if stems[entry["stem"]] > 1:
            entry["id"] = entry["base"].relative_to(directory).as_posix() + "/" + entry["stem"]
    entries.sort(key=lambda e: e["id"])
    matrix = [[0 for _ in entries] for _ in entries]
    modules = []

    def absolute(name):
        targets = set()
        for j, entry in enumerate(entries):
            for prefix in entry["prefixes"]:
                module = (prefix + "." if prefix else "") + entry["stem"]
                if name == module or name.startswith(module + "."):
                    targets.add(j)
        return targets

    def relative(path):
        if not path.is_relative_to(directory):
            return set()
        targets = set()
        for j, entry in enumerate(entries):
            module = entry["path"]
            if path == module or (module.is_dir() and module in path.parents) or (module.is_file() and path == module.with_suffix("")):
                targets.add(j)
        return targets

    for i, entry in enumerate(entries):
        lines = 0
        for path in entry["files"]:
            source = path.read_text(encoding="utf-8")
            lines += len(source.splitlines())
            tree = ast.parse(source, filename=str(path))
            for node in ast.walk(tree):
                targets = set()
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        targets.update(absolute(alias.name))
                elif isinstance(node, ast.ImportFrom):
                    if node.level:
                        base = path.parent
                        for _ in range(node.level - 1):
                            base = base.parent
                        if not base.is_relative_to(directory):
                            continue
                        if node.module:
                            base = base.joinpath(*node.module.split("."))
                        targets.update(relative(base))
                        for alias in node.names:
                            targets.update(relative(base / alias.name))
                    else:
                        name = node.module or ""
                        targets.update(absolute(name))
                        for alias in node.names:
                            targets.update(absolute(name + "." + alias.name))
                for j in targets - {i}:
                    matrix[i][j] += 1
        modules.append({"id": entry["id"], "root": entry["root"], "files": len(entry["files"]), "lines": lines})

    # Tarjan: one strongly connected set per module-level cycle, in stable id order.
    indices, low, stack, active, cycles = {}, {}, [], set(), []

    def visit(v):
        indices[v] = low[v] = len(indices)
        stack.append(v)
        active.add(v)
        for w, count in enumerate(matrix[v]):
            if not count:
                continue
            if w not in indices:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in active:
                low[v] = min(low[v], indices[w])
        if low[v] == indices[v]:
            component = []
            while True:
                w = stack.pop()
                active.remove(w)
                component.append(entries[w]["id"])
                if w == v:
                    break
            if len(component) >= 2:
                cycles.append(sorted(component))

    for v in range(len(entries)):
        if v not in indices:
            visit(v)
    return {"modules": modules, "matrix": matrix, "cycles": sorted(cycles)}


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo")
    parser.add_argument("out")
    parser.add_argument("--root", action="append", required=True)
    parser.add_argument("--name")
    args = parser.parse_args(argv)
    try:
        result = scan(args.repo, args.root)
        commit = subprocess.check_output(["git", "-C", args.repo, "rev-parse", "HEAD"], text=True).strip()
        out = Path(args.out)
        previous = json.loads(out.read_text(encoding="utf-8")) if out.is_file() else {}
        descriptions = {m["id"]: m["does"] for m in previous.get("modules", []) if "does" in m}
        for module in result["modules"]:
            if module["id"] in descriptions:
                module["does"] = descriptions[module["id"]]
        spec = {"topic": "modules", "page": "matrix", "title": previous.get("title", "模組耦合")}
        if "subtitle" in previous:
            spec["subtitle"] = previous["subtitle"]
        spec.update({"repo": {"name": args.name or Path(args.repo).resolve().name, "commit": commit},
                     "roots": args.root, **result})
        out.write_text(json.dumps(spec, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    except (OSError, UnicodeError, ValueError, SyntaxError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
