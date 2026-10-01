#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ua-integration)"
  mkdir -p "$SCRATCH/.ua"
  ( cd "$SCRATCH" && git init -q . )
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "ua_check_installed: exit 1 when plugin dir missing" {
  cd "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_installed
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "ua_check_installed: exit 2 when plugin present but KG missing" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_installed
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "ua_check_installed: exit 0 when both present" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_installed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ua_check_drift: empty output when UA absent" {
  cd "$SCRATCH"
  git init -q
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ua_check_drift: empty output when KG commit matches HEAD" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local head; head=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$head"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ua_check_drift: mild warning when 1-50 files diverge" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local base; base=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$base"
  # Create 3 new files + commit → 3-file diff vs KG's base
  for i in 1 2 3; do echo "x" > "file$i.txt"; done
  git add . && git -c user.email=t@t -c user.name=t commit -q -m "3 files"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [[ "$output" =~ "UA KG is stale" ]]
  [[ "$output" =~ "3 file(s)" ]]
}

@test "ua_check_drift: severe warning when >50 files diverge" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local base; base=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$base"
  for i in $(seq 1 60); do echo "x" > "file$i.txt"; done
  git add . && git -c user.email=t@t -c user.name=t commit -q -m "60 files"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [[ "$output" =~ "severely stale" ]]
  [[ "$output" =~ "60 file(s)" ]]
}

@test "_ua_extract_file_summary: returns summary when file node exists in KG" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run _ua_extract_file_summary "foo.py"
  [ "$status" -eq 0 ]
  [ "$output" = "foo module" ]
}

@test "_ua_extract_file_summary: empty when file not in KG" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run _ua_extract_file_summary "nonexistent.py"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_ua_extract_callers: lists 1-hop upstream via imports edge" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run _ua_extract_callers "foo.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "file:bar.py" ]]
  [[ "$output" =~ "imports" ]]
  [[ "$output" =~ "weight 5" ]]
}


@test "ua_get_pre_brainstorm_context: emits section per target file" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  mkdir -p docs/specs
  cat > docs/specs/R-999-example.md <<EOF
---
target-files:
  - foo.py
  - bar.py
---
Fake spec.
EOF
  source "$SHIP_LIB/ua-integration.sh"
  run ua_get_pre_brainstorm_context "R-999"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "UA pre-brainstorm context" ]]
  [[ "$output" =~ "foo.py" ]]
  [[ "$output" =~ "foo module" ]]
  [[ "$output" =~ "bar.py" ]]
}

@test "ua_get_pre_brainstorm_context: empty when spec missing" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_get_pre_brainstorm_context "R-999"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}





@test "_ua_extract_callers: never lists the file as its own caller" {
  cd "$SCRATCH"
  python3 - <<'PY'
import json
json.dump({"project":{"name":"x","gitCommitHash":"abc"},
 "nodes":[
   {"id":"file:a.py","type":"file","filePath":"a.py","summary":"A"},
   {"id":"function:a.py:foo","type":"function","filePath":"a.py","summary":"foo"},
   {"id":"function:a.py:bar","type":"function","filePath":"a.py","summary":"bar"},
   {"id":"file:b.py","type":"file","filePath":"b.py","summary":"B"}],
 "edges":[
   {"source":"file:a.py","target":"function:a.py:foo","type":"contains","weight":1},
   {"source":"file:a.py","target":"function:a.py:bar","type":"contains","weight":1},
   {"source":"file:b.py","target":"file:a.py","type":"imports","weight":5}],
 "layers":[]}, open(".ua/knowledge-graph.json","w"))
PY
  source "$SHIP_LIB/ua-integration.sh"
  out=$(_ua_extract_callers "a.py")
  if echo "$out" | grep -q 'file:a.py'; then
    echo "a.py is listed as its own caller:"; echo "$out"
    return 1
  fi
  echo "$out" | grep -q 'file:b.py' || { echo "the real caller b.py is missing"; return 1; }
}

@test "_ua_extract_callers: deduplicates and drops containment edges" {
  # bats runs setup() per test, so this builds its own graph rather than reusing
  # the previous test's scratch — which it silently did not inherit.
  cd "$SCRATCH"
  python3 - <<'PY2'
import json
json.dump({"project":{"name":"x","gitCommitHash":"abc"},
 "nodes":[
   {"id":"file:a.py","type":"file","filePath":"a.py","summary":"A"},
   {"id":"function:a.py:foo","type":"function","filePath":"a.py","summary":"foo"},
   {"id":"file:b.py","type":"file","filePath":"b.py","summary":"B"}],
 "edges":[
   {"source":"file:a.py","target":"function:a.py:foo","type":"contains","weight":1},
   {"source":"file:b.py","target":"file:a.py","type":"imports","weight":5},
   {"source":"file:b.py","target":"function:a.py:foo","type":"imports","weight":5}],
 "layers":[]}, open(".ua/knowledge-graph.json","w"))
PY2
  source "$SHIP_LIB/ua-integration.sh"
  out=$(_ua_extract_callers "a.py")
  n=$(echo "$out" | grep -c . )
  [ "$n" -eq 1 ] || { echo "expected 1 caller, got $n:"; echo "$out"; return 1; }
}
