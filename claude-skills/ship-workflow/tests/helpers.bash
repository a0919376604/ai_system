#!/usr/bin/env bash
# Test helpers shared across all .bats files.

# Absolute path to the skill root (one level above tests/)
SHIP_SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIP_LIB="$SHIP_SKILL_ROOT/lib"

# Create per-test scratch directory under tests/.tmp/<test-name>/
make_scratch() {
  local test_name="${1:-default}"
  local d="$SHIP_SKILL_ROOT/tests/.tmp/$test_name-$$"
  rm -rf "$d"
  mkdir -p "$d"
  echo "$d"
}

# Build a fake AIR-OS vault under <scratch>/airos with a 10 Projects/<name>/ project folder
make_fake_airos() {
  local scratch="$1"
  local project_name="${2:-test-project}"
  local airos="$scratch/airos"
  local proj="$airos/10 Projects/$project_name"
  mkdir -p "$proj"
  cat > "$proj/VISION.md" <<EOF
---
type: vision
project: "[[$project_name]]"
---
Test vision.
EOF
  cat > "$proj/STRATEGY.md" <<EOF
---
type: strategy
project: "[[$project_name]]"
---
Test strategy.
EOF
  cat > "$proj/ROADMAP.md" <<EOF
---
type: roadmap
project: "[[$project_name]]"
---

## 🔥 Now (3-5 items)

## 🔜 Next

## 🕐 Later

## ✅ Done
EOF
  cat > "$proj/QUARTERLY_GOALS.md" <<EOF
---
type: quarterly-goal
project: "[[$project_name]]"
---
Test goals.
EOF
  echo "$airos"
}

# Build a fake repo under <scratch>/repo
make_fake_repo() {
  local scratch="$1"
  local repo="$scratch/repo"
  mkdir -p "$repo/.claude" "$repo/docs/product" "$repo/docs/ideas" \
           "$repo/docs/decisions" "$repo/docs/brainstorms" \
           "$repo/docs/specs" "$repo/docs/plans" "$repo/docs/learnings"
  echo "$repo"
}

# Write a global config file at $HOME-override (caller sets HOME to scratch)
write_global_config() {
  local home="$1"
  local airos_vault="$2"
  mkdir -p "$home/.claude"
  cat > "$home/.claude/ship-workflow.yml" <<EOF
airos_vault: $airos_vault
airos_projects_dir: "10 Projects"
default_roadmap_mode: soft
default_id_pad: 3
auto_pull_freshness_window: 60
EOF
}

# Build a fake .ua/knowledge-graph.json under <scratch> with an optional commit hash.
make_fake_ua_kg() {
  local scratch="$1"
  local commit="${2:-abc123def456}"
  mkdir -p "$scratch/.ua"
  cat > "$scratch/.ua/knowledge-graph.json" <<EOF
{
  "project": {
    "name": "fake",
    "description": "fake project for tests",
    "languages": ["Python"],
    "frameworks": [],
    "analyzedAt": "2026-08-30T00:00:00Z",
    "gitCommitHash": "$commit"
  },
  "nodes": [
    {"id": "file:foo.py", "type": "file", "name": "foo.py", "filePath": "foo.py", "summary": "foo module", "tags": ["python"], "complexity": 10},
    {"id": "file:bar.py", "type": "file", "name": "bar.py", "filePath": "bar.py", "summary": "bar module", "tags": ["python"], "complexity": 5},
    {"id": "function:foo.py:do_foo", "type": "function", "name": "do_foo", "filePath": "foo.py", "summary": "does foo", "tags": [], "complexity": 3}
  ],
  "edges": [
    {"source": "file:bar.py", "target": "file:foo.py", "type": "imports", "direction": "outgoing", "weight": 5},
    {"source": "function:foo.py:do_foo", "target": "file:foo.py", "type": "contains", "direction": "outgoing", "weight": 1}
  ],
  "layers": [
    {"id": "layer:core", "name": "core", "description": "core modules", "nodeIds": ["file:foo.py"]}
  ],
  "tour": []
}
EOF
}

# Touch a directory that mimics UA plugin cache install path so ua_check_installed sees it.
# Uses a HOME override; caller must export HOME="$scratch/home" before running lib calls.
make_fake_ua_plugin_cache() {
  local scratch="$1"
  mkdir -p "$scratch/home/.claude/plugins/cache/understand-anything"
}
