#!/usr/bin/env python3
"""Decide whether a test-pruning pass lost coverage.

Usage:  coverage-diff.py <before.json> <after.json>
Exit 0  no regression
Exit 1  regression; reasons on stdout
Exit 2  cannot decide (missing/malformed input, empty baseline) — callers MUST
        treat this as a regression. Never conflate "cannot tell" with "safe".

Why this exists rather than comparing `coverage report --format=total`:

  1. A percentage is a lossy measurement. 903/1004 (89.940%) and 902/1004
     (89.840%) both render as `90`, so a real statement loss reads as no change.
  2. A total can rise while an individual file falls.
  3. Coverage reports only the files it observed. Deleting the sole test that
     imports a module removes that module from the report entirely, and
     `--source` does not reliably prevent this for namespace packages (a
     directory with no __init__.py). The file simply vanishes and the remaining
     average may go UP.

So the invariants are membership and exact integers, per file:

  a. every file measured before is still measured after
  b. covered_lines never falls for any such file
  c. num_statements is unchanged for any such file — the prune touches tests,
     so a moving statement count means the comparison is not like-for-like
"""
import json
import sys


def load(path):
    with open(path) as fh:
        doc = json.load(fh)
    files = doc.get("files")
    if not isinstance(files, dict):
        raise ValueError(f"{path}: no 'files' object")
    out = {}
    for name, entry in files.items():
        summary = (entry or {}).get("summary") or {}
        out[name] = (int(summary["covered_lines"]), int(summary["num_statements"]))
    return out


def main(argv):
    if len(argv) != 3:
        print("usage: coverage-diff.py <before.json> <after.json>", file=sys.stderr)
        return 2
    try:
        before = load(argv[1])
        after = load(argv[2])
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"cannot decide: {exc}", file=sys.stderr)
        return 2

    if not before:
        print("cannot decide: baseline report measured no files", file=sys.stderr)
        return 2

    problems = []
    for name in sorted(before):
        cov_b, stmt_b = before[name]
        if name not in after:
            problems.append(
                f"{name}: no longer measured after pruning "
                f"(was {cov_b}/{stmt_b} covered statements)"
            )
            continue
        cov_a, stmt_a = after[name]
        if stmt_a != stmt_b:
            problems.append(
                f"{name}: statement count changed {stmt_b} -> {stmt_a}; "
                f"not a like-for-like comparison"
            )
        elif cov_a < cov_b:
            problems.append(
                f"{name}: covered statements fell {cov_b} -> {cov_a}"
            )

    if problems:
        print("coverage regression:")
        for p in problems:
            print(f"  - {p}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
