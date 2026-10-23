---
name: ship-brief
description: Render a plain-language HTML overview (roadmap brief + architecture metaphor) for humans
argument-hint: "[--refresh-arch]"
discord-visible: true
---

# /ship-brief

You are producing the **human-facing** view of this project: two self-contained HTML pages a manager or teammate can open on a phone and understand in two minutes. ROADMAP.md and the specs stay the AI-facing source of truth; this command never edits them.

Division of labour: `lib/brief.py` owns numbers, dates, IDs and markup. You own the words. You write two small JSON files; the script renders them and refuses any R-id that is not in the ROADMAP.

## Arguments

- *(none)* — refresh the roadmap brief; write the architecture page only if it is missing or the knowledge graph changed since it was written.
- `--refresh-arch` — rewrite the architecture page too.

## Steps

0. **Refuse if inside a worktree** (the KG and ROADMAP belong to main):
   ```bash
   ~/.claude/skills/ship-workflow/lib/cwd-guard.sh || exit $?
   ```

1. **Resolve paths and extract facts:**
   ```bash
   BRIEF=~/.claude/skills/ship-workflow/lib/brief.py
   PROJECT_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
   ROADMAP="$PROJECT_PATH/ROADMAP.md"
   OUT="$PROJECT_PATH/Overview"; mkdir -p "$OUT"
   ROOT="$(git rev-parse --show-toplevel)"
   KG="$ROOT/.ua/knowledge-graph.json"; [ -f "$KG" ] || KG="$ROOT/.understand-anything/knowledge-graph.json"
   python3 "$BRIEF" extract "$ROADMAP" --repo "$ROOT" --kg "$KG" > "$OUT/facts.json"   # missing KG is fine
   ```
   **Read `$OUT/facts.json`. Do not read ROADMAP.md itself** — it can be hundreds of KB; the facts file is the slice you need (`active` = open Now/Next rows with tags, explain, done-when; `later` = titles only; `recent_done`; `checked_in_now` / `tags_say_done_unchecked` = rows whose status looks stale; `kg` = layers + tour when a knowledge graph exists).

2. **Architecture JSON (only when needed).** Write `$OUT/architecture.json` if it does not exist, if `--refresh-arch` was passed, or if its `kg_commit` differs from `facts.kg.commit`. Otherwise keep it as-is: the metaphor must stay stable week to week.

   Sources, in order: `$PROJECT_PATH/Architecture/POCKET.md` and `JOURNEY.md` if present (hand-written, trust them); `facts.kg.layers` and `facts.kg.tour`; `facts.kg.description`. If the project already has an ELI5 doc (`grep -rl "style: eli5" "$PROJECT_PATH"`), **reuse its metaphor**. If there is no KG and no POCKET/JOURNEY, skip this step; the brief renders alone.

   ```json
   {
     "kg_commit": "<facts.kg.commit or empty>",
     "title": "這個系統像一間 24 小時便利商店",
     "basis": "比喻沿用 main-dashboard-metrics-eli5.md · 原料是 UA 的 layer 和 tour＋JOURNEY.md",
     "stalls": [
       {"name": "門口", "role": "LINE 收訊息，先收下、排隊", "real": "webhook"}
     ],
     "side": {"text": "隔壁倉庫：公司的會員資料，提供 VIP 等級給 3 號櫃。", "ids": []},
     "steps_title": "跟一則訊息走一遍",
     "steps": [{"text": "小明在 LINE 問：「訂單什麼時候到？」", "tour": ""}]
   }
   ```
   - One everyday metaphor for the whole system. 4–6 `stalls` in flow order; each groups several KG layers. `role` is what it does in metaphor words; `real` is the short technical name (a reader who knows the code can map it).
   - 4–7 `steps` following one concrete request end to end; `tour` = the KG tour step it came from (traceability).
   - `side` is optional (an external system the stalls depend on).

3. **Brief JSON.** Write `$OUT/brief.json`:
   ```json
   {
     "headline": "這兩週主力在兩件事……有一件事卡住，需要你決定：……",
     "done": [{"text": "客服在聊天清單上就看得出誰是 VIP。", "status": "已 merge", "ids": ["R-217"]}],
     "themes": [{"name": "問題洞察改版：從「數問題的寫法」改成「數工單」",
                 "why": "以前同一個問題換個說法就被當成兩個，數字沒有參考價值。",
                 "hill": "downhill", "ids": ["R-197", "R-234"], "stuck": [], "stall": 5}],
     "asks": [{"text": "會員主檔同步停在 2019 年，四種修法要選一個。", "ids": ["R-195"]}],
     "later": ["精準推播", "客戶自動標籤"]
   }
   ```
   **Voice — the reader is a manager with no domain knowledge, reading zh-TW on a phone:**
   - No file paths, table names, MR numbers, commit hashes or code identifiers. If a term is unavoidable, gloss it in the same sentence.
   - `done` (max 5): rows from `recent_done`, plus `active` rows whose tags say merged/shipped. Write the change someone **can see** (客人、客服、主管), not what the code does. `status` is honest: unchecked + "merged" = `已 merge · 待部署`, in review = `做完 · 等 review`, never `已上線` unless the row says deployed.
   - `themes` (2–4): group `active` rows by **outcome**, not by ID. `why` is one sentence on why it matters, preferably rewritten from the rows' `explain`. `hill`: `uphill` = still figuring out how (needs-brainstorm, debug, recon, root cause unknown); `crest` = approach known, building; `downhill` = mostly in review / merged / finishing. `stuck` = IDs blocked on a decision. `stall` = 1-based index into `architecture.json` stalls when the theme clearly lives there (marks it 整修中); omit otherwise.
   - `asks` (0–3): only real decisions waiting on the user: tags like `DECISION` or `needs-brainstorm` with options, done-when text like 擇一 / 拍板 / 書面答覆. Empty list is fine.
   - `later` (2–4): direction phrases distilled from `later` titles, no IDs.
   - **Every sentence cites the rows it came from in `ids`.** Numbers must be copied from the facts text, never computed by you. If unsure, leave it out.

4. **Render:**
   ```bash
   python3 "$BRIEF" render --roadmap "$ROADMAP" --facts "$OUT/facts.json" --brief "$OUT/brief.json" \
     --arch "$OUT/architecture.json" --out "$OUT"   # missing architecture.json = brief only
   ```
   Exit 1 with `cited IDs not found in ROADMAP` means you cited an ID that does not exist: fix the JSON and re-run. Do not work around the check.

5. **Report** (no commit: everything lives in the vault):
   ```
   📰 Brief: <OUT>/brief.html
   🏪 Architecture: <OUT>/architecture.html   (or: skipped, no KG / POCKET / JOURNEY)

   一句話：<headline>
   狀態有疑問：<len(checked_in_now)> 列已打勾還在 Now · <len(tags_say_done_unchecked)> 列寫 merged 沒打勾 → /ship-roadmap
   ```
   If `facts.kg.commits_behind` > 50, add: `KG 落後 N 個 commit，架構頁可能漏掉新功能。跑 /understand 後再 /ship-brief --refresh-arch。`

## Failure modes

- No ROADMAP.md at the project path → ERROR, point at `/ship-init`.
- ROADMAP has no open rows → still render; the page says nothing is in progress.
- No KG and no POCKET/JOURNEY → brief only, no architecture page.
