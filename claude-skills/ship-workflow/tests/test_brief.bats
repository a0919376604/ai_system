#!/usr/bin/env bats
# /ship-brief: lib/brief.py extract + render.
load helpers

setup() {
  export SCRATCH="$(make_scratch brief)"
  export BRIEF="$SHIP_LIB/brief.py"
  export ROADMAP="$SCRATCH/demo/ROADMAP.md"
  mkdir -p "$SCRATCH/demo"
  cat > "$ROADMAP" <<'EOF'
---
updated: 2026-10-12-r232-in-review
type: roadmap
---

## 🔥 Now (3-5 items)

- [ ] **R-010** [EPIC · P1 · in-progress · 2a shipped-in-branch 未 push] 把 `buckets` 拿掉 —— long AI-only detail that must not leak into the title
    ↳ explain: 一張工單本來就代表一個問題。
    ↳ done when: 表已 DROP
- [x] **R-011** [FIX] 改 label —— shipped 2026-09-03

## 🔜 Next

- [ ] **R-020** [FEATURE · merged to main 2026-10-09 (!261) · 部署清單見 [[wave-2026-10]]] 換成 7 類 —— detail
- [ ] **R-021** [DECISION] NER 開工前三件事
    ↳ done when: 個資範圍有書面答覆

## 🕐 Later

- [ ] **R-030** [P3] 精準推播 —— detail

## ✅ Done

- [x] **R-040** [SHIPPED · merged 2026-10-07] 聊天頁 VIP 標章 —— detail
- [x] **R-041** ~~重複的列~~ —— 撤銷 2026-10-08
- [x] **R-042** 很舊的功能 —— 2026-06-01
EOF
  python3 "$BRIEF" extract "$ROADMAP" --today 2026-10-12 > "$SCRATCH/facts.json"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "extract: open Now/Next rows carry tags, explain and done-when; titles stop at ——" {
  python3 - "$SCRATCH/facts.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))
a = {r["id"]: r for r in f["active"]}
assert sorted(a) == ["R-010", "R-020", "R-021"], sorted(a)
assert a["R-010"]["title"] == "把 `buckets` 拿掉", a["R-010"]["title"]
assert a["R-010"]["explain"] == "一張工單本來就代表一個問題。"
assert a["R-021"]["done_when"] == "個資範圍有書面答覆"
assert a["R-020"]["title"] == "換成 7 類", a["R-020"]["title"]          # nested [[link]] in tags
assert [r["id"] for r in f["later"]] == ["R-030"] and "tags" not in f["later"][0]
assert f["roadmap"]["updated"] == "2026-10-12"
PY
}

@test "extract: stale-status hints and the recent-done window" {
  python3 - "$SCRATCH/facts.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))
assert f["checked_in_now"] == ["R-011"], f["checked_in_now"]
# merged-but-unchecked is flagged; shipped-in-branch is not "done"
assert f["tags_say_done_unchecked"] == ["R-020"], f["tags_say_done_unchecked"]
# within 14 days, withdrawn (~~) and old rows excluded
assert [r["id"] for r in f["recent_done"]] == ["R-040"], f["recent_done"]
PY
}

write_brief() {
  cat > "$SCRATCH/brief.json" <<EOF
{"headline": "主力在 <script>alert(1)</script> 問題洞察",
 "done": [{"text": "VIP 標章上線", "status": "已 merge", "ids": ["R-040"]}],
 "themes": [{"name": "問題洞察改版", "why": "數字不準", "hill": "downhill", "ids": ["$1"], "stall": 2}],
 "asks": [{"text": "個資範圍要書面答覆", "ids": ["R-021"]}],
 "later": ["精準推播"]}
EOF
  cat > "$SCRATCH/arch.json" <<'EOF'
{"title": "像一間便利商店", "stalls": [{"name": "門口", "role": "收訊息"}, {"name": "店長的帳本", "role": "報表"}],
 "steps": [{"text": "小明問問題", "tour": "3"}]}
EOF
}

@test "render: escapes text, chips carry ROADMAP titles, hot stall marked" {
  write_brief R-010
  run python3 "$BRIEF" render --roadmap "$ROADMAP" --facts "$SCRATCH/facts.json" \
    --brief "$SCRATCH/brief.json" --arch "$SCRATCH/arch.json" --out "$SCRATCH/out"
  [ "$status" -eq 0 ]
  grep -q '&lt;script&gt;' "$SCRATCH/out/brief.html"
  [ "$(grep -c '<script>' "$SCRATCH/out/brief.html")" -eq 0 ]
  grep -q 'title="把 `buckets` 拿掉 · done when: 表已 DROP">R-010<' "$SCRATCH/out/brief.html"
  grep -q '1 列已打勾卻還在 Now（R-011）' "$SCRATCH/out/brief.html"
  grep -q 'class="stall hot"><span class="no">2<' "$SCRATCH/out/architecture.html"
}

@test "render: missing --arch file renders the brief alone" {
  write_brief R-010
  run python3 "$BRIEF" render --roadmap "$ROADMAP" --facts "$SCRATCH/facts.json" \
    --brief "$SCRATCH/brief.json" --arch "$SCRATCH/nope.json" --out "$SCRATCH/out"
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH/out/brief.html" ]
  [ ! -f "$SCRATCH/out/architecture.html" ]
  [ "$(grep -c 'architecture.html' "$SCRATCH/out/brief.html")" -eq 0 ]
}

@test "render: an R-id not in the ROADMAP writes nothing and fails" {
  write_brief R-999
  run python3 "$BRIEF" render --roadmap "$ROADMAP" --facts "$SCRATCH/facts.json" \
    --brief "$SCRATCH/brief.json" --arch "$SCRATCH/arch.json" --out "$SCRATCH/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-999"* ]] || return 1
  [ ! -e "$SCRATCH/out" ]
}

@test "/ship-roadmap ends by running /ship-brief" {
  grep -q 'commands/ship-brief.md' "$SHIP_SKILL_ROOT/commands/ship-roadmap.md"
}
