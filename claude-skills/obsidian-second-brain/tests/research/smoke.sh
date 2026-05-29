#!/usr/bin/env bash
# tests/research/smoke.sh - full toolkit end-to-end against live APIs.
# Run manually before merging. Not in CI.

set -euo pipefail

cd "$(dirname "$0")/../.."

echo "=== /research smoke ==="
out=$(uv run -m scripts.research.research "retrieval augmented generation")
echo "$out" | python3 -c "import json,sys; p=json.load(sys.stdin); assert p['stats']['sources_succeeded'] >= 3, f'only {p[\"stats\"][\"sources_succeeded\"]} sources succeeded'"
echo "ok"

echo "=== /research --academic smoke ==="
out=$(uv run -m scripts.research.research "transformer attention" --academic)
echo "$out" | python3 -c "import json,sys; p=json.load(sys.stdin); assert p['academic_mode'] is True; assert p['stats']['sources_succeeded'] >= 2"
echo "ok"

echo "=== /research-deep smoke ==="
out=$(uv run -m scripts.research.research_deep "rag latency" "rag eval benchmarks")
echo "$out" | python3 -c "import json,sys; p=json.load(sys.stdin); assert len(p['per_query']) == 2"
echo "ok"

echo "=== /discourse-pulse smoke ==="
out=$(uv run -m scripts.research.discourse_pulse "rust async")
echo "$out" | python3 -c "import json,sys; p=json.load(sys.stdin); assert p['stats']['sources_succeeded'] >= 2"
echo "ok"

echo "=== /youtube smoke ==="
out=$(uv run -m scripts.research.youtube_extract "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
echo "$out" | python3 -c "import json,sys; p=json.load(sys.stdin); assert p['video_id']"
echo "ok"

echo ""
echo "ALL SMOKE TESTS PASSED"
