#!/usr/bin/env bats
load helpers
bats_require_minimum_version 1.5.0

setup() {
  B="$SHIP_SKILL_ROOT/skills/ship-refactor-brand"
  T="$SHIP_SKILL_ROOT/templates/refactor-report.html"
  S="$(make_scratch refactor-brand)"
}
teardown() { rm -rf "$S"; }

@test "SKILL.md: brand-direction step links directions.md and precedes the inventory (AC-1)" {
  f="$B/SKILL.md"
  d=$(grep -n '^## .*品牌方向' "$f" | head -1 | cut -d: -f1)
  i=$(grep -n '^## .*Inventory' "$f" | head -1 | cut -d: -f1)
  [ -n "$d" ] && [ -n "$i" ] && [ "$d" -lt "$i" ]
  sed -n "${d},${i}p" "$f" | grep -qF '(references/directions.md)'
}
@test "brand skill: the no-new-identity clause is gone (AC-2)" {
  ! grep -rqF 'does not justify inventing a new identity' "$B"
}
@test "directions.md: names every item of the direction procedure (AC-3)" {
  f="$B/references/directions.md"
  for s in '## app' '## page' 'draw.mjs' '--options 3' '--theme' 'neighbouring' 'TASTE_SKILL_HISTORY' \
           'Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html' '.panel.now' '.panel.optA' '.panel.optD' \
           '方案 A ·' 'Reports/refactor-brand-direction.md' '重選' '選 A、B、C，或混搭' 'fewer than three' \
           '~/.claude/skills/design-taste-frontend' '~/.agents/skills/design-taste-frontend' '~/.codex/skills/design-taste-frontend' \
           'mockup 未驗證' 'npx skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend -g'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
  grep -E -- '--keep' "$f" | grep -qi 'fixed'
}

@test "evidence.md: rendered after-pictures, unchanged appearance, no hand-drawn, unverified fallback (AC-4)" {
  f="$B/references/evidence.md"
  for s in '提案 · 方案' '外觀不變' 'mockup 未驗證' 'Hand-drawn schematic boxes are never a brand after-picture' '品牌方向'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
}
@test "evidence: images are PNG or JPEG, never SVG, never copied markup (review focus 1-2)" {
  f="$B/references/evidence.md"
  grep -qF 'PNG or JPEG data URIs, never SVG' "$f"
  grep -qF "never copy a build's markup or scripts into the report" "$f"
}
@test "roadmap.md: the c1 row carries the directions mockup and confirmed option (AC-5)" {
  f="$B/references/roadmap.md"
  grep -qF 'Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html' "$f"
  grep -qF 'mockup 定案 <X>' "$f"
}

@test "template: taste lint reports 0 FAIL (AC-7)" {
  L="${TASTE_SKILL_DIR:-$HOME/.claude/skills/design-taste-frontend}/scripts/lint.mjs"
  [ -f "$L" ] || skip "design-taste-frontend not installed"
  command -v node >/dev/null || skip "node missing"
  sed 's/{{STEM}}/refactor-brand-T/g' "$T" > "$S/report.html"
  run node "$L" "$S/report.html"
  [[ "$output" == *'RESULT: 0 FAIL'* ]] || { echo "$output"; return 1; }
}
@test "template: keeps anchors, zoom, AI link and a brand image example" {
  for s in 'id="top"' 'id="c1"' 'href="#c1"' 'id="z1"' 'href="#z1"' '{{STEM}}.ai.md' ':target' '<img'; do
    grep -qF -- "$s" "$T" || { echo "missing: $s"; return 1; }
  done
}
@test "template: no lint escapes (review focus 4)" {
  run ! grep -qF 'taste-skill-ignore' "$T"
}
@test "template: brand pictures sit on the light .fig surface, not in figcaptions" {
  run ! grep -qF '<figcaption' "$T"
}

@test "evidence: fallback install command displays verbatim and passes report validation" {
  snippet=$(sed -n '/^<p class="taste-fallback">/p' "$B/references/evidence.md")
  [ -n "$snippet" ]
  sed 's/{{STEM}}/fallback/g; /<\/body>/,$d' "$T" > "$S/fallback.html"
  printf '%s\n' "$snippet" '</body>' '</html>' >> "$S/fallback.html"
  printf '%s\n' '[human](fallback.html)' '## c1 · x' > "$S/fallback.ai.md"
  source "$SHIP_LIB/refactor-scan.sh"
  run --separate-stderr rs_report_check "$S/fallback"
  [ "$status" -eq 0 ] || { echo "$stderr"; return 1; }
  python3 - "$S/fallback.html" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)

parser = Text()
parser.feed(Path(sys.argv[1]).read_text())
assert 'npx skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend -g' in ''.join(parser.parts)
PY
}

@test "roadmap: mockup metadata belongs only to the direction-documentation candidate" {
  f="$B/references/roadmap.md"
  grep -qF "Only the direction-documentation candidate's row" "$f"
  grep -qF "Use the picked direction's recorded comparison mockup path and option" "$f"
  grep -qF 'do not add mockup metadata to an ordinary c1 or when no direction was picked' "$f"
}

@test "brand workflow: reused picks without a direction row retain the prerequisite" {
  f="$B/references/roadmap.md"
  grep -qF 'If the recorded direction is reused but its BRAND_GUIDE row is neither queued nor done' "$f"
  grep -qF 'propose this direction-documentation candidate as c1 again and keep visual-alignment candidates dependent on it' "$f"
}
@test "SKILL.md: the c1 rule lives once, in roadmap.md" {
  run ! grep -qF 'If the recorded direction is reused but its BRAND_GUIDE row is neither queued nor done' "$B/SKILL.md"
  grep -qF '(references/roadmap.md#selection-and-row-preparation)' "$B/SKILL.md"
}
@test "directions.md: every taste deal writes history to the evidence dir, one --out per option" {
  f="$B/references/directions.md"
  step5=$(awk '/^5\. /,/^6\. /' "$f")
  [[ "$step5" == *'TASTE_SKILL_HISTORY'* ]] || { echo "step 5 lacks TASTE_SKILL_HISTORY"; return 1; }
  [[ "$step5" == *'--out'* ]] || { echo "step 5 lacks --out"; return 1; }
  run ! grep -qF '$REPORT_DIR' "$f"
}
