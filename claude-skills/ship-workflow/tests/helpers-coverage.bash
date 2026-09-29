#!/usr/bin/env bash
# Emit a coverage-json-shaped document. Args: <out> then triples of
# <path> <covered_lines> <num_statements>.
make_cov_json() {
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out = sys.argv[1]
rest = sys.argv[2:]
files = {}
for i in range(0, len(rest), 3):
    files[rest[i]] = {"summary": {"covered_lines": int(rest[i+1]),
                                  "num_statements": int(rest[i+2])}}
tc = sum(f["summary"]["covered_lines"] for f in files.values())
tn = sum(f["summary"]["num_statements"] for f in files.values())
json.dump({"files": files, "totals": {"covered_lines": tc, "num_statements": tn}},
          open(out, "w"))
PY
}
