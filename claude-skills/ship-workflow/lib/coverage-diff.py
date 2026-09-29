#!/usr/bin/env python3
"""Decide whether a test-pruning pass lost coverage.

Usage:  coverage-diff.py <before.json> <after.json>
Exit 0  no regression
Exit 1  regression; reasons on stdout
Exit 2  cannot decide — missing/malformed input, empty baseline, or a value that
        is not a plain non-negative int. Callers MUST treat 2 as a regression.
        "Cannot tell" is never "safe".

Three earlier gates failed here, each in the same way: they compared a SUMMARY of
coverage rather than coverage itself.

  1. `coverage report --format=total` is a rounded percentage. 903/1004 (89.940%)
     and 902/1004 (89.840%) both render as `90`, so a real statement loss reads as
     no change at all.
  2. Exact per-file COUNTS fixed the rounding but preserve cardinality, not
     membership. Executed lines going from [1,3,4,5] to [1,3,4,6] keeps the count
     at 4 while line 5 silently lost its only test.
  3. A file that drops out of the report entirely cannot be compared at all.
     Deleting the sole test importing a module removes it, and `--source` does not
     prevent this for namespace packages (a directory with no __init__.py).

So the comparison is over the executed-line SETS, which is the ground truth coverage
actually records. Per file present in the baseline:

  a. the file is still measured after            — membership
  b. every line executed before is executed after — identity, not cardinality
  c. num_statements is unchanged                  — otherwise not like-for-like

Values are validated strictly. `int(x)` silently truncates 1.9 to 1 and accepts
True as 1, so a malformed report could pass; each value must be a plain
non-negative int.
"""
import json
import sys


def _int(value, where):
    # bool is a subclass of int; a JSON `true` must not read as 1.
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{where}: expected a plain integer, got {value!r}")
    if value < 0:
        raise ValueError(f"{where}: expected a non-negative integer, got {value}")
    return value


def load(path):
    with open(path) as fh:
        doc = json.load(fh)
    # A bare list or scalar has no .get; that raises AttributeError, which escapes
    # as an uncaught traceback and exit 1 — the fail-closed direction, but the wrong
    # signal. "Cannot decide" must be 2, and it must say why.
    if not isinstance(doc, dict):
        raise ValueError(f"{path}: top level is {type(doc).__name__}, expected an object")
    files = doc.get("files")
    if not isinstance(files, dict):
        raise ValueError(f"{path}: no 'files' object")
    out = {}
    for name, entry in files.items():
        entry = entry or {}
        if "executed_lines" not in entry:
            raise ValueError(
                f"{path}: {name} has no 'executed_lines'; this report cannot "
                f"establish which lines were covered"
            )
        raw = entry["executed_lines"]
        if not isinstance(raw, list):
            raise ValueError(f"{path}: {name}: 'executed_lines' is not a list")
        lines = {_int(n, f"{path}:{name}:executed_lines") for n in raw}
        summary = entry.get("summary") or {}
        stmts = _int(summary.get("num_statements"), f"{path}:{name}:num_statements")
        out[name] = (lines, stmts)
    return out


def main(argv):
    if len(argv) != 3:
        print("usage: coverage-diff.py <before.json> <after.json>", file=sys.stderr)
        return 2
    try:
        before = load(argv[1])
        after = load(argv[2])
    except (OSError, ValueError, KeyError, TypeError, AttributeError,
            json.JSONDecodeError) as exc:
        print(f"cannot decide: {exc}", file=sys.stderr)
        return 2

    if not before:
        print("cannot decide: baseline report measured no files", file=sys.stderr)
        return 2

    problems = []
    for name in sorted(before):
        lines_b, stmt_b = before[name]
        if name not in after:
            problems.append(
                f"{name}: no longer measured after pruning "
                f"(was {len(lines_b)}/{stmt_b} covered statements)"
            )
            continue
        lines_a, stmt_a = after[name]
        if stmt_a != stmt_b:
            problems.append(
                f"{name}: statement count changed {stmt_b} -> {stmt_a}; "
                f"not a like-for-like comparison"
            )
            continue
        lost = sorted(lines_b - lines_a)
        if lost:
            shown = ", ".join(str(n) for n in lost[:10])
            more = f" (+{len(lost) - 10} more)" if len(lost) > 10 else ""
            problems.append(f"{name}: lines no longer covered: {shown}{more}")

    if problems:
        print("coverage regression:")
        for p in problems:
            print(f"  - {p}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
