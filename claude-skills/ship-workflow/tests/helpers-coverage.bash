#!/usr/bin/env bash
# Emit a coverage-json-shaped document.
# Args: <out> then triples of <path> <executed_lines_csv> <num_statements>.
# e.g. make_cov_json out.json src/a.py 1,3,4,5 5
make_cov_json() {
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, rest = sys.argv[1], sys.argv[2:]
files = {}
for i in range(0, len(rest), 3):
    path, csv, stmts = rest[i], rest[i+1], int(rest[i+2])
    lines = [int(x) for x in csv.split(",") if x != ""]
    files[path] = {"executed_lines": lines,
                   "summary": {"covered_lines": len(lines), "num_statements": stmts}}
json.dump({"files": files}, open(out, "w"))
PY
}

# Write a coverage json with a raw summary value, to test validation.
# Args: <out> <path> <executed_lines_csv> <num_statements_literal_json>
make_cov_json_raw() {
  python3 - "$@" <<'PY'
import json, sys
out, path, csv, stmts = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = [int(x) for x in csv.split(",") if x != ""]
json.dump({"files": {path: {"executed_lines": lines,
                            "summary": {"covered_lines": len(lines),
                                        "num_statements": json.loads(stmts)}}}},
          open(out, "w"))
PY
}
