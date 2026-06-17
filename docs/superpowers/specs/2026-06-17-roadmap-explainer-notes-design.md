---
date: 2026-06-17
updated: 2026-06-17
type: spec
status: draft
tags: [ship-workflow, roadmap, explainer, plan-precursor]
ai-first: true
related-specs:
  - 2026-06-14-ship-workflow-skill-design.md
  - 2026-06-14-obsidian-air-os-vault-design.md
supersedes: null
---

## For future Claude
> ROADMAP row 仍讓 product owner 看不懂在做什麼,即使套了 α(action verb +
> done-when)。Root cause 是 domain 知識斷層 — 看到「SceneEngine」「stable-prefix
> cache」「D-004」等名詞無從理解。修法:加一個新 artifact「Roadmap Explainer
> Note」,per-row 的 10-20 行白話文 + 用語小辭典 + 與前後 R-NNN 的關係,Claude
> 用 proposal + Architecture overview 自動 draft,product owner review 即可。

## §1 Problem

### 1.1 觀察到的症狀
- α 套件 (`↳ done when:`) 上線後,product owner 仍反映 ROADMAP row「看不懂在做什麼」
- 不是 *what done looks like* 的問題,是 *what this step is doing* 的問題
- Root cause:product owner 不熟 codebase 的 domain 詞彙與架構
- Confirmed via brainstorm session 2026-06-17 — 「不太懂為什麼做這個,domain知識不夠 所以看不懂」

### 1.2 既有 artifact 為何不夠
| Artifact | 為何不夠 |
|---|---|
| **Proposal** (935 行/§式) | 戰略+技術深;非工程人員讀不完;且寫在 epic 級 (R-001),沒切到 child (R-001.3) |
| **Brainstorm** | `/ship-next` 才產生;進 brainstorm 前已經要懂 row 才能討論;且寫給「進入工作模式的人」看,非入門 |
| **Spec / Plan** | 更下游;假設讀者已知道 row 在做什麼 |
| **ROADMAP row 本身** | 受限於一行篇幅;塞 action verb + done-when + effort + confidence 已經滿 |

**結論:**proposal 與 brainstorm 之間有個 「row-level 入門口袋書」 的空位 — 這個 spec 補上。

### 1.3 出處
此 spec 由 2026-06-17 brainstorm session 產生。Key user signals:
- 「不太懂為什麼做這個,domain知識不夠 所以看不懂」(diagnosis: WHY/domain gap)
- 「可以打開別的檔案 但要讓我懂這個 roadmap 這步要做什麼」(constraint: cross-ref OK,comprehension priority)
- 「Mid — 拆成一個 note 檔」(format choice)

---

## §2 Goal + Success Criterion

### 2.1 Goal
Product owner 打開 ROADMAP 看任一 R-NNN[.M] row,**1 個 click(打開 explainer note)** 之內理解:
1. 這步在做什麼(plain language)
2. 為什麼要做這步(在 epic 中的角色 + 沒做的後果)
3. 用到的 domain 名詞是什麼意思(or 至少知道去哪查)
4. 前後 R-NNN 關係(已 unblock 什麼、被誰 blocked)

### 2.2 Success Criterion
**Backfill 完 ai-eden-service R-001 epic + R-001.1–.7 (8 個 note) 後,product owner 不需要打開 proposal §3 就能對「下一個要做哪個 child」做出有依據的決定。**

驗收方式:user explicit acknowledgement(主觀 — 但這是 UX 問題,沒有客觀 metric 是合理的)。

### 2.3 Non-goals
- **不取代 proposal**。Proposal 仍是 technical canonical(§3 設計、§5 phased plan)。Explainer 是入門卡。
- **不取代 brainstorm**。Brainstorm 仍負責設計選項探索。Explainer 是入門口袋書,不討論 trade-offs。
- **不強制每個 R-NNN 都要有 explainer**。優先補 "Now" 區 + 有 proposal 的 row;其他自然 accumulate。

---

## §3 Architecture

### 3.1 Artifact 位置

```
<airos_vault>/10 Projects/<project>/Roadmap-Notes/R-NNN[.M]-<slug>.md   ← canonical
                  │
                  ↓ sync.sh (one-way mirror, 同 Proposals/ 模式)
                  │
<repo>/docs/roadmap-notes/R-NNN[.M]-<slug>.md                            ← read-only mirror
```

- Vault 是 source of truth;repo 是 mirror
- Filename:`R-NNN[.M]-<slug>.md`,沒有 date prefix(explainer 是 single-revision artifact,不像 proposal 會有 v1/v2)
- 多個 explainer per project:flat directory,no nested folders

### 3.2 ROADMAP row 引用

新 annotation `↳ explain:` 跟 `↳ done when:` 同級:

```markdown
- [ ] **R-001.3** Wire SceneEngine into dialogue.py + 驗 stable-prefix cache 穩定 (Phase 3) — 保留 D-004 順序 + 新增 cache hit metric (proposal §3.x Q6) · effort=S · confidence=high
    ↳ explain: [[Roadmap-Notes/R-001.3-wire-scene-engine]]
    ↳ done when: TTFB 不 regress + stable-prefix cache hit rate 不掉 + uncached input token 增量 < 30% (§5 Phase 3 退場條件)
```

子 row(`R-NNN.M`)annotation 用 6 空格縮排(沿用 `↳ done when:` 規則)。

### 3.3 與既有 artifact 的分工

```
┌─────────────┐  Where am I going?      ┌───────────────┐
│ STRATEGY    ├────────────────────────▶│ ROADMAP       │
│ + VISION    │                         │ (row level)   │
└─────────────┘                         └──────┬────────┘
                                               │ row 看不懂?
                                               ↓
┌─────────────────────┐                 ┌──────────────────┐
│ Architecture/       │                 │ Roadmap-Notes/    │  ← 新 artifact
│ overview, modules,  │  source for ←───┤ R-NNN-<slug>.md  │
│ ai-flows            │                 │ (10-20 lines,     │
└─────────────────────┘                 │  plain language)  │
                                        └────────┬─────────┘
┌─────────────────────┐                          │ 想深入?
│ Proposals/          │ source for ──────────────┘
│ R-NNN-...-proposal  │
│ (technical depth)   │
└─────────────────────┘
                                               ┌──────────────────┐
ROADMAP row picked by /ship-next ─────────────▶│ Brainstorm       │
                                               │ (design choices) │
                                               └──────┬───────────┘
                                                      ↓
                                               ┌──────────────────┐
                                               │ Spec / Plan      │
                                               └──────────────────┘
```

### 3.4 Lifecycle

1. **產生 trigger** — 3 條路徑(見 §4.2)
2. **存放** — vault canonical
3. **更新(loose coupling)** — explainer 跟 row 不自動同步。Row 改 description 不會自動 invalidate explainer。User 手動 `/ship-explain --force-refresh R-NNN` 才重寫。Stale detection 是 best-effort warning(`/ship-roadmap` step 11 用 git blame 比 row vs explainer mtime;見 §8.2-Q4)
4. **歸檔** — row 進 Done 時,explainer **保留**(歷史記錄,類似 brainstorm note);不刪不移動

---

## §4 Components

### 4.1 Explainer Note Template (`templates/obsidian/ROADMAP-NOTE.md`)

```markdown
---
date: {{date}}
updated: {{date}}
type: roadmap-note
id: {{id}}
parent: {{parent}}                       # 沒有就 null
tags: [roadmap-note, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-row: {{id}}
proposal-ref: {{proposal_ref}}           # 沒有就 null
---

## For future Claude
> {{id}} 的入門口袋書 — plain language 解釋這步在做什麼、為什麼做、
> domain 名詞代表什麼。讀者:domain 不熟的 product owner / 新加入的工程師。

## 一句話總結
> {{one_liner}}

## 這步在做什麼
{{plain_what}}

## 為什麼要做這步
- **在 epic 的角色**:{{role_in_epic}}
- **沒做會怎樣**:{{cost_if_skipped}}
- **做完後玩家/系統會感覺到什麼**:{{user_visible_change}}

## 前後關係
- **依賴 (blocked-by)**: {{blocked_by}}
- **解鎖 (unblocks)**: {{unblocks}}
- **同 epic 兄弟**: {{siblings}}

## 用到的 domain 名詞
| 詞 | 是什麼 | 完整定義 |
|---|---|---|
{{glossary_rows}}

## 深入閱讀
{{deeper_reading_links}}
```

#### 4.1.1 Section scaling

| Row effort | 必填 sections | 可省 sections |
|---|---|---|
| S | 一句話總結、這步在做什麼、深入閱讀 | 其他可省 |
| M | + 為什麼要做這步、前後關係 | domain 名詞可省(若無新詞) |
| L | 全部 | — |

Frontmatter `proposal-ref` 有值 → 必填 domain 名詞 section(L 大多帶 proposal)。

#### 4.1.2 Voice 規則
- **Plain language**:第一次出現的 domain 名詞 inline 定義(例:「SceneEngine(規則層,決定下一個 scene 演什麼)」)
- **zh-TW prose**:跟 vault `_CLAUDE.md` 的 `output-lang: zh-TW` rule 對齊
- **避免**:「整合」「重構」這種抽象動詞;優先具象描述「把 X 接到 Y」「在 Z 路徑加 W」

### 4.2 `/ship-explain` 新指令

```
~/.claude/skills/ship-workflow/commands/ship-explain.md
```

Frontmatter:
```yaml
---
name: ship-explain
description: Generate (or refresh) plain-language explainer note for a ROADMAP row
argument-hint: "<R-NNN> | --all-now"
discord-visible: true
---
```

#### 4.2.1 模式

| 模式 | 行為 |
|---|---|
| `ship-explain R-NNN` | 寫(或覆寫,with diff)單一 R-NNN 的 explainer |
| `ship-explain --all-now` | 把 "Now" 區所有 row 沒有 explainer 的補齊;有的跳過(除非 `--force-refresh`) |
| `ship-explain --force-refresh R-NNN` | 強制覆寫既有 explainer(會先 print diff 給 user confirm) |

#### 4.2.2 必讀來源 (Claude 在 draft 前讀)

1. ROADMAP row 本身(action verb description + done-when + effort + proposal-ref)
2. `Proposals/*-R-NNN-*-proposal.md`(若存在)— extract §1 為什麼 + §3 設計概要 + §5 phase 角色
3. `Architecture/overview.md` + 引用的 `Architecture/modules/*.md` / `Architecture/ai-flows/*.md`
4. 相鄰 R-NNN 既有 explainer(維持 voice + glossary 一致;若 R-001.2 已有 explainer,R-001.3 explainer 中 cross-link 它)

#### 4.2.3 選讀來源

- `docs/learnings/R-*.md`:若 epic 已有先前 child shipped(例:R-001.1 done → R-001.2 explainer 引用該 learning)
- `docs/decisions/D-*.md`:若 row 提到 D-NNN(例:「保留 D-004 順序」→ explainer 必須說明 D-004 是什麼)

#### 4.2.4 Output 流程

1. Claude draft `<vault>/<project>/Roadmap-Notes/R-NNN-<slug>.md`(atomic write — `.tmp` then `mv`)
2. `sync.sh --force` 鏡像到 repo
3. **`roadmap-insert.sh --inject-explain R-NNN "<slug>"` 將 `↳ explain:` annotation 加到 row**:
   - Row 沒 `↳ explain:` → 在 `↳ done when:` 前面 insert
   - Row 已有 `↳ explain:` **指向同一 slug** → no-op (idempotent)
   - Row 已有 `↳ explain:` **指向不同 slug**(typically 因 row description 改了 slug 變了)→ replace,並 print warning「舊 slug `<old>` explainer 仍存在於 disk,可手動歸檔或 delete」
4. Print 一句話總結 + 為什麼要做這步 到 terminal,讓 user 立即 sanity-check
5. Ask:「Read full note? [Y/n/edit]」 — `Y` 印全文、`edit` 開 `$EDITOR`、`n` 結束

### 4.3 `roadmap-insert.sh` 擴充

新 flag `--explain "<path-or-slug>"`:

```bash
roadmap-insert.sh "$ROADMAP" R-001.3 "Wire SceneEngine into dialogue.py" \
  --child R-001 \
  --explain "Roadmap-Notes/R-001.3-wire-scene-engine" \
  --done-when "TTFB 不 regress + ..."
```

行為:
- 跟 `--done-when` 一樣寫一行 indented annotation
- Annotation 排序:`↳ explain:` 在 `↳ done when:` **前**(讀 row 時順序合理:先理解 → 再看驗收)
- 縮排規則沿用既有:top-level 4 空格、child 6 空格

### 4.4 `/ship-next` 整合

`commands/ship-next.md` Branch A step 4(picking R-NNN)後,新增 step **4b. Explainer pre-flight**:

```
4b. **Explainer pre-flight.** 選定 R-NNN 後:
    1. 在 ROADMAP row 找 `↳ explain:` annotation
    2a. 若有:讀 explainer file,印「一句話總結」+「為什麼要做這步」到 terminal
    2b. 若無:offer `Run /ship-explain $ID now? [Y/n]`
        - Y:跑 explain,完成後印 summary
        - n:直接進 brainstorm(允許,但提示「explainer 缺,可能影響 brainstorm 品質」)
    3. 進 brainstorm 時,把 explainer 內容當 context 注入(success criterion + 為什麼 + glossary)
```

### 4.5 `/ship-roadmap` 整合

`commands/ship-roadmap.md` step 7(decompose)中,每個 child 寫進 ROADMAP 後:

```
For each newly-inserted child:
  - Auto-run /ship-explain $CHILD_ID    # in same session
  - explainer draft 完成後,user 跟其他 children 一起 review
```

step 11(report)加一條:
- **Count of items in "Now" missing `↳ explain:` annotation** + 「To backfill: `/ship-explain --all-now`」suggestion

### 4.6 `BRAINSTORM.md` template 微調

既有 frontmatter 已有 `success-criteria`、`estimated-effort`。加 `roadmap-note-ref`:

```yaml
roadmap-note-ref: "[[Roadmap-Notes/{{id}}-{{slug}}]]"   # null if not yet generated
```

讓 brainstorm 跟 explainer 有雙向 wikilink。

---

## §5 Data Flow

### 5.1 Happy path — 新 epic decompose

```
1. /ship-roadmap detects R-001 too big → marks ⚠️
2. user: 'y' → decompose brainstorm
   - For each child: gather desc + done_when + est
   - roadmap-insert.sh ... --child R-001 --done-when ... --est ...
3. /ship-roadmap auto-runs /ship-explain $CHILD_ID for each newly-inserted child
   - explain.sh reads proposal §1/§3/§5 + Architecture overview
   - drafts <vault>/<project>/Roadmap-Notes/R-001.M-<slug>.md
   - injects `↳ explain:` annotation into ROADMAP row (idempotent)
4. user reviews diff (covers ROADMAP + 5 new Roadmap-Notes files)
5. confirm → vault write + sync to repo
6. /ship-roadmap step 11 report: "5 children decomposed; 5 explainer notes drafted; 0 still missing"
```

### 5.2 Happy path — 從未有 explainer 的 row 接續工作

```
1. /ship-next default branch → ranks Now items
2. user picks R-001.3
3. step 4b: no `↳ explain:` in row → offer to generate
4. user: Y → /ship-explain R-001.3 runs
5. Claude reads proposal §3.x Q6 + Architecture/ai-flows/storyline + R-001.1/R-001.2 explainers
6. drafts Roadmap-Notes/R-001.3-wire-scene-engine.md
7. prints 一句話總結 + 為什麼要做這步
8. user "啊 我懂了" → proceeds to brainstorm with explainer as context
```

### 5.3 Edge case — R-NNN 沒 proposal

```
1. /ship-explain R-005 invoked (R-005 是 Later 區的小項目,無 proposal)
2. Claude only has:
   - ROADMAP row text
   - Architecture/overview.md (high level)
3. drafts minimal explainer:
   - 一句話總結 (from row + Architecture context)
   - 這步在做什麼 (best-effort plain rewrite of row)
   - 深入閱讀 (Architecture refs only)
   - SKIP: 為什麼要做這步 (no proposal source) → leave section empty with note: "為什麼:proposal 尚未寫;建議 `/ship-propose R-005` 後再 refresh explainer"
   - SKIP: domain 名詞 (only if row has unfamiliar terms; otherwise empty)
```

### 5.4 Edge case — explainer 已存在但 row 描述被改

```
1. user edits ROADMAP row 改 description
2. (No automatic detection — explainer 不會自動失效)
3. Optional: `/ship-roadmap` step 11 report 偵測 (mtime(row) > mtime(explainer)?
   actually row 沒有 per-line mtime — use git blame instead) →
   warn "R-001.3 row updated after explainer last touched; consider /ship-explain --force-refresh R-001.3"
4. User手動 refresh
```

---

## §6 Backfill plan

### 6.1 範圍
**只動 ai-eden-service "Now" 區:**

| R-NNN | Title (current) | Phase |
|---|---|---|
| R-001 (epic) | Build 韓劇式戀愛劇情 + 人設自動生成 pipeline | — |
| R-001.1 | Land Phase 1 schema | 1 |
| R-001.2 | Implement ArcEngine + StorylineSelector + SceneEngine | 2 |
| R-001.3 | Wire SceneEngine into dialogue.py | 3 |
| R-001.4 | Extend StateInference + ship 4 區 dashboard | 4 |
| R-001.5 | Migrate runway_atelier 為 canary world | 5a |
| R-001.6 | Roll out remaining 6 worlds | 5b |
| R-001.7 | Author 第二 character 從 0 on new arch | 5c |

**共 8 個 explainer note。**

### 6.2 不動範圍
- ai-eden-service R-002–R-010(Next/Later)— 等對應 /ship-next 自然 trigger
- claudecode-discord、langlive-line-oa — 等自然 trigger
- ai-eden-service Done 區 — 歷史,不補

### 6.3 執行方式
單一指令完成:
```bash
/ship-explain --all-now    # 在 ai-eden-service repo cwd 下
```

執行 sequencing(由 `--all-now` 邏輯保證):
1. **依 ROADMAP 出現順序**處理(parent epic R-001 先,然後 R-001.1 → R-001.7)
2. **每個 R-NNN draft 完成才進下一個** — 後寫的 explainer 可在 §4.2.2 「相鄰 R-NNN 既有 explainer」步驟讀到前面剛 draft 的,維持 voice + glossary 一致
3. **逐個 print 一句話總結** 到 terminal(progress feedback)
4. **8 個全部 draft 完才一次 prompt** review/commit;不逐個 ask(避免打斷)
5. Atomic rollback safety:若任一 draft 失敗,**所有先前 draft 留在 disk 但不 commit**;user 可保留 partial progress 或 `rm -rf` 重來

---

## §7 Acceptance Criteria

| ID | Criterion |
|---|---|
| AC-001 | `roadmap-insert.sh --explain "<slug>"` 寫出正確縮排的 `↳ explain:` annotation,並且 `--explain` 出現在 `--done-when` 註解**之前** |
| AC-002 | `/ship-explain R-NNN` 在 ai-eden-service R-001.3 上跑,產生 `<vault>/10 Projects/ai-eden-service/Roadmap-Notes/R-001.3-wire-scene-engine.md`,內含至少 「一句話總結」「這步在做什麼」「深入閱讀」三 section,且檔案 sync 到 `<repo>/docs/roadmap-notes/` |
| AC-003 | `/ship-explain R-001.3` 跑完後,ROADMAP row R-001.3 多了一行 `    ↳ explain: [[Roadmap-Notes/R-001.3-wire-scene-engine]]`,且在 `↳ done when:` **之前** |
| AC-004 | `/ship-explain --all-now` 在 ai-eden-service 上一次補齊 8 個 note (R-001 + R-001.1-.7) |
| AC-005 | `/ship-next` Branch A 選到一個無 explainer 的 row 時,offer 「Run /ship-explain now?」prompt |
| AC-006 | `/ship-next` Branch A 選到有 explainer 的 row 時,自動印「一句話總結 + 為什麼要做這步」到 terminal,進 brainstorm 時把 explainer 內容當 context |
| AC-007 | `/ship-roadmap` step 11 report 含「count of Now items missing `↳ explain:`」 |
| AC-008 | New bats tests for `roadmap-insert.sh --explain`(3 個:基本插入、跟 `--done-when` 同存、child mode);現有 61/61 仍綠 |
| AC-009 | User subjective acknowledgement:「現在打開 ai-eden-service ROADMAP + 點任一 R-001.x explainer,我懂這步在做什麼」 |

---

## §8 Open Questions

### 8.1 Closed (此 session 已決定)
- ✅ Inline 還是拆檔?**拆檔(Mid 尺寸)**
- ✅ 誰寫?**Claude 用 proposal + Architecture overview 自動 draft;user review**
- ✅ Backfill 範圍?**僅 ai-eden-service Now 區 (R-001 + R-001.1-.7) = 8 個 note**

### 8.2 Open(plan 階段再定)
1. **`↳ explain:` annotation 形式** — 用 `[[wikilink]]` (Obsidian) 還是 `path/to/file.md` (markdown standard)?
   - Lean towards Obsidian wikilink — vault 端是 canonical,wikilink 在 Obsidian app 內可 click
   - repo mirror 端的 wikilink 不 clickable,但 user 在 repo 主要看 diff/commit,真實閱讀都在 vault
2. **explainer voice 是否要 enforce 「不能直接抄 proposal 句子」**?
   - 風險:不 enforce 的話 Claude 可能就 copy-paste proposal §1,沒做 plain-language translation
   - Mitigation:在 ship-explain.md command 中明確 prompt 「你必須 *rewrite*,不能直接抄」
3. **`--all-now` 一次 draft 多個 note 時,要不要逐個 ask user confirm,還是 batch + 最後一次 diff**?
   - 8 個 note 逐個 ask 體驗會打斷;batch + 最後一次 diff 比較順暢
   - 但 batch 模式單一 draft 出錯時 rollback 麻煩 → 用 git branch 保護?或寫進 tmp 路徑後再 atomic mv?
4. **explainer 有沒有 `status: stale` marker** — 當對應 row 改了 description 卻沒 refresh explainer 時?
   - Yes,加 `status: live | stale` frontmatter;mtime / git blame 比較邏輯放在 /ship-roadmap step 11

---

## §9 Out of scope

- **Explainer 的 UI 渲染最佳化** — 例如 callout / Obsidian Templater 動態渲染。先用 plain markdown,有需要再升級。
- **跨 project explainer 共用 glossary** — claudecode-discord 跟 langlive-line-oa 各自有自己的 domain 詞;不嘗試做跨 project glossary。
- **`/ship-explain --diff R-NNN`** 顯示 explainer 跟 row 差異 — 留待 Phase 2 觀察是否需要。
- **Notion / Linear / Jira 整合** — 不做。Explainer 是 vault-native artifact。

---

## §10 Implementation phases

| Phase | 內容 | 退場條件 |
|---|---|---|
| **0. Template + flag** | `templates/obsidian/ROADMAP-NOTE.md` 新建;`roadmap-insert.sh --explain` flag;bats tests | AC-001 + AC-008 部分(`roadmap-insert.sh` 測試)綠 |
| **1. /ship-explain core** | `commands/ship-explain.md` 落地;單 R-NNN 模式 | AC-002 + AC-003 在 R-001.3 上手動驗證 |
| **2. /ship-explain bulk** | `--all-now` + `--force-refresh` | AC-004 |
| **3. /ship-next integration** | step 4b 邏輯 | AC-005 + AC-006 |
| **4. /ship-roadmap integration** | step 7 auto-explain;step 11 report 加 missing count | AC-007 |
| **5. Backfill** | 跑 `/ship-explain --all-now` 在 ai-eden-service;commit | AC-009 |
| **6. Polish** | Stale detection (open Q4)、voice enforcement prompt (open Q2) | post-Phase-5 觀察後決定 |

### Estimate
- Phase 0–4:~2-3 小時(機械改動)
- Phase 5:~1 小時(8 個 note 的 draft + review;dependent on proposal 內容)
- Phase 6:defer
- **總計:3-4 小時**(單 session,可 ship)

---

## §11 Migration / Rollout

### 11.1 既有 ROADMAP 行為相容
- `↳ explain:` annotation 是新加的;不影響既有 `↳ done when:` 或 row 解析
- 沒 explainer 的 row 仍合法 — 工具不會強制 reject(只在 report 提示)
- 既有 `/ship-next`、`/ship-roadmap` 在 explainer-less ROADMAP 上仍 work

### 11.2 Sync sequence
- 沿用既有 `sync.sh` 模式 — 加一條 mirror `Roadmap-Notes/` → `docs/roadmap-notes/`
- Atomic write rule:write to `.tmp` then `mv`(同 Proposals 模式)
- launchd auto-push (6h interval) 自動帶到 SecondBrain GitHub

### 11.3 失敗模式
- `/ship-explain` 在 proposal-less + Architecture-less 的 row 上跑 → 產出 minimal note + 在 「為什麼要做這步」section 留 「需要 /ship-propose 後 refresh」 hint
- 跨 session 中 explainer file 被 user 手動編輯後,`--force-refresh` 會覆蓋 → 用 `--diff` 先看再決定(open Q3)

---

## §12 References

- α 套件 commit:`c5b66bd feat(ship-workflow): enforce Action + done-when format in ROADMAP entries`
- Ship Workflow spec:`docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
- AIR-OS Vault spec:`docs/superpowers/specs/2026-06-14-obsidian-air-os-vault-design.md`
- Brainstorm session log:此 file 本身的 ## For future Claude
- Live example target:`/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/ROADMAP.md`(R-001.1-.7)
- Proposal that explainer will reference:`/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Proposals/2026-06-15-R-001-story-generation-pipeline-proposal.md`
