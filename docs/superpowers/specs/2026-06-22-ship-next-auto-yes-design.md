---
date: 2026-06-22
updated: 2026-06-22
type: spec
status: draft
tags: [ship-workflow, ship-next, auto, fire-and-forget]
ai-first: true
related-specs:
  - 2026-06-21-ship-next-mega-command-design.md
  - 2026-06-17-roadmap-explainer-notes-design.md
supersedes: null
---

## For future Claude
> `/ship-next --auto:yes` 把 9-phase mega flow 全程自動跑 — 給「出門/睡覺」場景用。
> 所有 clarifying question 都選第一個(brainstorming skill 慣例:lead with
> recommended);所有 review checkpoint 都自動 approve;executor 自動選 subagent;
> review loop cap=3 失敗時 **abort + Discord push + worktree 保留**;major findings
> **不 skip**,自動轉 IDEA-NNN follow-up,避免 silent quality debt。Pre-flight 強制
> ROADMAP row 有 `↳ done when:` annotation,沒有就 refuse。每個 auto 決策都寫到
> worktree 內的 `.ship-auto-decisions.md` log,使用者回來 5 秒看完。

## §1 Problem

### 1.1 觀察到的症狀
- `/ship-next` mega flow 有 9 個 phase,中間 ≥ 7 個地方等使用者按 Y / 選選項。
- Fire-and-forget 場景(出門、睡覺、上廁所)無法用 — 任一停在 prompt 就卡住整個 cycle。
- Codex `/run-plan` 內若要 invoke `/ship-next` 也不能,codex 不能互動。

### 1.2 從 brainstorm session 收到的 2 個 hard signals(2026-06-22)
1. **使用場景 = fire-and-forget**(出門 / 睡覺)。需要 robust failure modes — 任何卡關都不能 silently 把 main 弄髒。
2. **cap=3 review loop 失敗 → abort + Discord push + worktree 保留**。不續跑、不安全降級;讓使用者回家 resume 手動。

### 1.3 設計約束
- **Strict gate principle inherited**:`blocking=0` 仍然才能 merge。auto 模式不放鬆這個。
- **No silent quality debt**:major findings 不能默默 skip;每個 major 轉 IDEA-NNN follow-up。
- **Auditable**:回家要能看到 auto 跑了什麼決策。

---

## §2 Goal + Success Criterion

### 2.1 Goal
使用者打一次 `/ship-next R-NNN --auto:yes` 然後關電腦走人。回來看到:
- **成功路徑**:main 多 1 個 squashed commit,ROADMAP row ✅,Discord 一條成功訊息,worktree 已 cleanup
- **失敗路徑**:main **不動**,worktree 保留,Discord 一條 abort 訊息附 cap=3 失敗原因 + resume 指令

### 2.2 Success Criterion(observable)
- **使用面**:`/ship-next --adhoc "test" --auto:yes` 在 ai-eden-service 跑完整 9 phases 不需要任何 keypress
- **品質面**:auto 模式 squashed 的 commit,blocking=0(跟 interactive 模式一樣的 gate)
- **可審計面**:`docs/.ship-auto-decisions.md` 含**每個** auto 決策一行,使用者回家 5 秒掃完知道發生了什麼
- **失敗面**:強制觸發 cap=3 失敗(例:塞 unfixable security bug)後,main 完全沒動 + Discord 通知收到

### 2.3 Non-goals
- **不取代 interactive 模式**:`/ship-next R-NNN`(無 `--auto:yes`)行為完全不變。auto 是純加層。
- **不改 strict-gate**:`blocking=0` 仍硬性要求。auto 是「auto-fix until blocking=0」,不是「auto-ship even with blockers」。
- **不支援 multi-R-NNN batch**:一次 1 個 R-NNN;不做 `/ship-next --auto:yes --batch R-001,R-002,R-003`。
- **不取代 codex `/run-plan`**:run-plan 跑 plan 文件,ship-next 跑 R-NNN 整個 cycle。Orthogonal。

---

## §3 Architecture

### 3.1 Flag 形式

**主名:** `--auto:yes`
**短別名:** `--auto`(語意相同;`--auto=no` 不接受,缺 flag 就是 interactive)

**位置:**任意,跟現有 args 並列:
```
/ship-next --auto:yes
/ship-next R-002 --auto:yes
/ship-next --adhoc "Smoke test" --auto:yes
/ship-next --resume R-001.3 --auto:yes
```

**互斥:**
- `--discard R-NNN --auto:yes` → ERROR(刪除是破壞性,不准 auto)
- `--force-refresh` 跟 `--auto:yes` 可以共存,但會被當 `--resume` 處理

### 3.2 Pre-flight gate

`/ship-next --auto:yes` 開頭(Phase 1)先驗:

```bash
# Required: ROADMAP row 必須有 ↳ done when: 註解
DONE_WHEN=$(grep -A1 "\*\*${ID}\*\*" "$ROADMAP_PATH" | grep "↳ done when:" || true)
if [ -z "$DONE_WHEN" ]; then
  echo "ERROR: --auto:yes refused — R-NNN $ID has no ↳ done when: annotation."
  echo "       fire-and-forget mode requires an explicit success criterion."
  echo "       Run /ship-roadmap to add one, then re-invoke."
  exit 2
fi

# Recommended (only warn): explainer note + proposal
EXPLAIN=$(grep -A1 "\*\*${ID}\*\*" "$ROADMAP_PATH" | grep "↳ explain:" || true)
[ -z "$EXPLAIN" ] && echo "WARN: no explainer note for $ID; brainstorm may pick defaults that don't match intent" >&2

PROPOSAL=$(ls "$PROJECT_PATH/Proposals/"*"${ID}"*"-proposal.md" 2>/dev/null | head -1)
[ -z "$PROPOSAL" ] && echo "WARN: no proposal for $ID; brainstorm has less constrained design space" >&2
```

**Rationale:** done-when 是「auto 知道自己有沒有做完」的唯一信號。沒有 done-when 等於沒有 acceptance test,auto 無法判斷 success vs failure。

### 3.3 Phase-by-phase auto 行為

| Phase | Interactive | Auto:yes |
|---|---|---|
| **P1 Pre-flight** | 偵測 worktree → 問 continue/discard/abort | 偵測 → **auto continue**(resume 邏輯 detect 進度) |
| **P2 Open worktree** | 直接做 | 一樣 |
| **P3 Brainstorm** | 每個 clarifying question 等使用者 | **每題 auto 選第一個選項**(brainstorming skill 慣例:options 是 leading with recommendation → option 1 = 推薦) |
| **P3 spec review gate** | "Review spec first?" | **auto approve** |
| **P4 Plan review gate** | "Review plan first?" | **auto approve** |
| **P5 Executor choice** | 1/2/3 menu | **auto pick 1**(subagent-driven) |
| **P6 review attempt** | 印 blockers + 等使用者看 | **直接 build fix-plan + re-invoke executor**;每次嘗試寫 log |
| **P6 cap=3 失敗** | pause + 3 選項 | **abort + Discord push + worktree 保留**(見 §3.5) |
| **P6 major findings** | 每個問 [F]/[I]/[S] | **每個 auto 轉 IDEA-NNN**(透過 `/ship-idea --during-build`,自動帶 `related-roadmap-item`)|
| **P7 Squash merge** | 自動 | 一樣 |
| **P8 /ship-compound** | 自動 | 一樣 |
| **P9 Cleanup** | 自動 | 一樣 |

### 3.4 Decision log

Worktree 內加一個 audit log:`docs/.ship-auto-decisions.md`

**重要:** 加進 `.gitignore`,**不** commit。純本地審計用。

Format(每決策一行,append-only):
```
2026-06-22T23:15:00 P3 brainstorm Q1 "Worktree scope?" → auto-picked: 包 ship-next 跟 ship-build
2026-06-22T23:18:00 P3 spec review → auto-approved
2026-06-22T23:25:00 P4 plan review → auto-approved
2026-06-22T23:26:00 P5 executor → auto-picked: 1 (subagent-driven)
2026-06-22T23:50:00 P6 review attempt 1 → blocking=2 (handler.py:45, cache.py:12); building fix-plan
2026-06-22T23:55:00 P6 review attempt 2 → blocking=0, major=3 (service.py:88, dialogue.py:104, cache.py:42)
2026-06-22T23:55:30 P6 majors → 3 IDEAs created (IDEA-042, 043, 044)
2026-06-22T23:55:45 P7 squash merge → main + 1 commit (sha=4c49b25)
2026-06-22T23:56:00 P8 /ship-compound → ROADMAP row R-NNN ✅
2026-06-22T23:56:30 P9 cleanup → worktree removed, branch deleted
```

### 3.5 Cap=3 failure handling

```
attempt = 1
while attempt ≤ 3:
  invoke code-review-skill
  parse counts
  if BLOCKING == 0: break
  log P6 attempt + blocker list to decision log
  build fix-plan from blockers
  invoke subagent on fix-plan
  attempt += 1

if BLOCKING > 0 after attempt=3:
  # ABORT path
  - log "P6 cap=3 exhausted, aborting" to decision log
  - leave worktree intact (do NOT cd back to main, do NOT cleanup)
  - Discord push:
    🛑 R-NNN aborted at P6 — 3 attempts didn't clear blockers.
    blockers (last attempt): <list>
    worktree retained at /path/to/worktree
    Resume manually:
      cd /path/to/worktree
      /ship-next --resume R-NNN
  - exit 1
```

### 3.6 Major findings auto-handling

**Interactive 模式:**每個 major 問 [F]ix-now / [I]dea-NNN / [S]kip
**Auto:yes 模式:****全部 auto 轉 IDEA-NNN**(不 skip)

Mechanic:
```bash
for finding in $major_findings:
  # /ship-idea --during-build wraps id-gen + log + commit
  /ship-idea --during-build \
    "P6 major from R-NNN ${ID}: $finding.title" \
    --related-roadmap-item "$ID" \
    --severity major \
    --source "code-review-skill auto-run"
  # captures into docs/ideas/IDEA-NNN.md
```

**Rationale:** Skip 會 silently 累積 quality debt。轉 IDEA 讓 debt 變 explicit、可見、回家後可以 prioritize。

### 3.7 Notification

**Success path(squash merge 完):**
1. Discord push(若 session 來自 Discord):
   ```
   ✅ R-NNN <description> shipped (squash <sha>)
   • blocking: 0 ✓
   • major: M → IDEA-042..044 (auto-logged as follow-ups)
   • minor: K
   • praise: P
   • decisions log: /path/to/.ship-auto-decisions.md
   ```
2. `PushNotification`(若是 terminal session):同樣 3 行 summary
3. `osascript -e display notification` + bell:本地立即聽到

**Abort path(cap=3 失敗):**
1. Discord / PushNotification:見 §3.5 abort log
2. worktree 不 cleanup,branch 不 delete

### 3.8 Codex /run-plan 互動

當 codex `/run-plan` 跑某 plan 而 plan 內提到 `/ship-next`,plan 必須叫 codex 帶 `--auto:yes`(因為 codex 不能互動)。

**實作:**`/run-plan` skill 的 prompt template 加一條約束:
```
EXECUTION NOTES:
- If you invoke `/ship-next` from within a plan task, ALWAYS include `--auto:yes`.
  Codex cannot answer interactive prompts; `/ship-next` without --auto:yes will hang.
```

(此條 constraint 寫在 `/run-plan` skill 的 prompt template,不寫在 `/ship-next` 本身。)

---

## §4 Components

### 4.1 Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/commands/ship-next.md` | 加 `--auto:yes` arg parsing + 每個 phase 條件分支(interactive vs auto)+ decision log writer + Discord push 整合 |
| `claude-skills/ship-workflow/commands/ship-idea.md` | 加 `--during-build` + `--severity` + `--source` flags(若還沒支援) |
| `~/.claude/skills/run-plan/SKILL.md`(out-of-tree) | Prompt template 加「always include `--auto:yes`」約束 |

### 4.2 New helper files
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/lib/auto-decision-log.sh` | Append-only writer:`auto-decision-log.sh <worktree> <phase> <decision> <detail>` |
| `claude-skills/ship-workflow/tests/test_auto-decision-log.bats` | TDD coverage for above |

### 4.3 Frontmatter update
`commands/ship-next.md` frontmatter `argument-hint`:
```yaml
argument-hint: "[R-NNN] | --adhoc <desc> | --discard R-NNN | --resume R-NNN | --auto:yes"
```

### 4.4 No-touch files
- `lib/cwd-guard.sh`、`lib/code-review-parse.sh`:不動,本身就 stateless
- 其他 ship-* commands:不動

---

## §5 Data flow

### 5.1 Happy path — auto run completes
```
1. /ship-next R-001.3 --auto:yes 從 main repo
2. P1: pre-flight check
   - done-when annotation ✓
   - explain ✓
   - proposal ✓
   - no existing worktree
3. P2: open worktree, cd
4. P3: brainstorm runs
   - Q1 "approach?" → auto-picked option 1
   - Q2 "scope?" → auto-picked option 1
   - spec written → auto-approved
   → docs/.ship-auto-decisions.md gets 3 entries
5. P4: writing-plans runs → plan written → auto-approved
6. P5: executor auto = 1 (subagent)
7. Subagent runs all tasks, commits N task commits
8. P6 attempt 1: code-review → blocking=0, major=2
   - 2 IDEAs created automatically (IDEA-045, 046)
9. P7: cd main, squash merge, commit with full template
10. P8: /ship-compound → ROADMAP ✅
11. P9: worktree cleanup
12. Discord push: "✅ R-001.3 shipped..."
13. Terminal bell + osascript notification
```

### 5.2 Abort path — cap=3 fails
```
1-7. Same as 5.1 through executor
8. P6 attempt 1 → blocking=2 (security hole + null deref). build fix-plan.
9. P6 attempt 2 → blocking=2 (executor's fix introduced new issue). build fix-plan.
10. P6 attempt 3 → blocking=1 (still a SQL injection). build fix-plan.
11. attempt > 3: ABORT
    - decision log: "P6 cap=3 exhausted; main untouched"
    - worktree intact at /path
    - Discord push: "🛑 R-001.3 aborted..."
    - exit 1
12. User comes home, sees Discord, cd's into worktree, runs /ship-next --resume R-001.3 (interactive mode this time)
```

### 5.3 Edge case — missing done-when
```
1. /ship-next R-009 --auto:yes
2. P1 pre-flight: R-009 row has no ↳ done when: annotation
3. ERROR + exit 2; main untouched
4. Discord push: "🛑 R-009 auto refused — needs done-when. Run /ship-roadmap first."
```

### 5.4 Edge case — codex /run-plan calls /ship-next
```
1. codex reads plan
2. plan says "invoke /ship-next R-NNN"
3. codex follows /run-plan skill's prompt template constraint → invokes "/ship-next R-NNN --auto:yes"
4. /ship-next runs in auto mode, no interactive prompts
5. completes or aborts per §5.1/5.2
```

---

## §6 Acceptance Criteria

| ID | Criterion |
|---|---|
| AC-001 | `/ship-next R-NNN --auto:yes` runs end-to-end with zero keypresses on happy path |
| AC-002 | `--auto:yes` synonym `--auto` works identically |
| AC-003 | `--auto:yes` + `--discard` combination ERRORs out (mutually exclusive) |
| AC-004 | Pre-flight refuses if ROADMAP row lacks `↳ done when:` annotation; exit 2 |
| AC-005 | Pre-flight WARNs (but proceeds) if explainer or proposal missing |
| AC-006 | Brainstorm clarifying questions auto-pick option 1; spec/plan review gates auto-approve |
| AC-007 | Executor in auto mode = 1 (subagent-driven), never prompts |
| AC-008 | P6 review loop in auto mode silently iterates fix-plan up to cap=3 |
| AC-009 | P6 cap=3 failure: worktree NOT cleaned up, branch NOT deleted, main NOT touched, exit 1 |
| AC-010 | P6 major findings in auto mode each become an IDEA-NNN via `/ship-idea --during-build` |
| AC-011 | Decision log at `docs/.ship-auto-decisions.md` has one line per auto decision (P1 through P9) |
| AC-012 | Decision log file is `.gitignore`d (not committed) |
| AC-013 | Discord push (when in Discord session) on success contains: sha, major count + IDEA links, minor count, decision log path |
| AC-014 | Discord push on abort contains: failure phase, blocker count, worktree path, `/ship-next --resume` resume hint |
| AC-015 | `/run-plan` skill's prompt template includes the "always include --auto:yes" constraint when invoking /ship-next |

---

## §7 Open Questions

### 7.1 Closed (此 session 已決定)
- ✅ Use case: fire-and-forget(出門/睡覺)
- ✅ Cap=3 failure: abort + Discord push + worktree 保留
- ✅ Brainstorm behavior: auto-pick option 1 per question(沿用 brainstorming skill 「lead with recommended」慣例)
- ✅ Major findings: 不 skip,轉 IDEA-NNN follow-up
- ✅ Flag form: `--auto:yes`(主)、`--auto`(短別名)

### 7.2 Open(plan 階段再定)
1. **`/ship-idea --during-build` 的 flag 集合**:`--related-roadmap-item`、`--severity`、`--source` 三個 flag 是否已支援?Plan 階段 grep ship-idea.md 確認。若缺,plan 加 task 補。
2. **Decision log 跟 brainstorm 內部 todo list 的關係**:brainstorming skill 自己有 TodoWrite 追蹤 progress;ship-next 的 auto decision log 是上一層的 summary。兩者不衝突但 plan 階段確認 log 別 duplicate brainstorm 內部追蹤。
3. **Terminal session 沒 Discord 怎麼 notify**:已有 `PushNotification` tool + osascript;確認 fallback 順序(Discord → PushNotification → osascript only)。
4. **Resume 偵測 progress 的方法**:Phase 4 `--resume` 邏輯用 commit count + 文件存在性。auto 模式 resume(中斷後再跑)會不會跟 interactive resume 行為一致?Plan 階段細看 §3.3 P1。

---

## §8 Out of scope

- **`--auto:yes --dry-run` 預覽**:不做。Auto + dry-run 概念衝突(auto = 直接做)
- **多 R-NNN batch auto**:`/ship-next --auto:yes --batch R-001,R-002` 不支援
- **Auto mode 內手動 escape**:沒有「auto 中途按 Esc 退到 interactive」 — 一旦 `--auto:yes`,整個 cycle 都是 auto
- **不同 fail behavior modes**:不做 `--auto:yes-strict` / `--auto:yes-lax`,只一個 strict 模式
- **Timer-based auto-approval**(例:5 秒 timeout 自動 Y):不做。要做就純 auto

---

## §9 Implementation phases

| Phase | 內容 | 退場條件 |
|---|---|---|
| **0. Spec lock** | 此 spec + 使用者 review pass | spec committed |
| **1. lib/auto-decision-log.sh + bats** | Append-only log writer with bats coverage | TDD tests green |
| **2. ship-idea --during-build flags** | If `/ship-idea` doesn't yet support the 3 flags, add them (per §7.2-Q1) | Manual smoke or unit test |
| **3. ship-next.md auto branches** | Add `--auto:yes` arg parsing + per-phase conditional branches + decision log calls | Read-through verify each phase has explicit auto vs interactive branch |
| **4. Pre-flight gate** | done-when required check; explain/proposal warn-only | AC-004, AC-005 |
| **5. P6 auto loop** | Auto fix-plan rebuilding, cap=3 abort logic | AC-008, AC-009 |
| **6. P6 major → IDEA** | Auto-create IDEA-NNN follow-ups per major finding | AC-010 |
| **7. Notification integration** | Discord push / PushNotification / osascript at success + abort paths | AC-013, AC-014 |
| **8. /run-plan template update** | Append "always --auto:yes" constraint to skill prompt template | AC-015 |
| **9. End-to-end smoke (happy + abort)** | In ai-eden-service, `/ship-next --adhoc "smoke auto" --auto:yes` then intentionally trigger cap=3 failure | AC-001 through AC-015 |

### Estimate
- Phase 1-2: ~30 min(bash + bats + ship-idea flag additions)
- Phase 3-7: ~1.5-2 hours(ship-next.md edits — biggest chunk)
- Phase 8: ~10 min
- Phase 9: ~30 min(real smoke, token-heavy)
- **總計:3-4 小時**

---

## §10 Migration / Rollout

### 10.1 Backward compat
- `/ship-next R-NNN`(無 `--auto:yes`):**完全不變**,所有 prompt 跟今天一樣
- `--auto:yes` 是新加層,不影響任何既有 invocation

### 10.2 `.gitignore` 更新
Repo 端的 `.claude/.gitignore`(由 `/ship-init` 寫的)加一行:
```
.ship-auto-decisions.md
```

對既有 repo:`/ship-next --auto:yes` 第一次跑時自動 append 這行(if not present)。新 repo:`/ship-init` 寫進去。

### 10.3 Discord bot
不需要重啟 — `/ship-next` 的 frontmatter 沒變(`argument-hint` 改 string,description ≤ 100 char 仍然符合),只是 args 多接幾個 flag。bot 下次 rescan 會撈到新 hint。

---

## §11 References

- Parent spec:`docs/superpowers/specs/2026-06-21-ship-next-mega-command-design.md`
- Existing /ship-next code:`claude-skills/ship-workflow/commands/ship-next.md`(after Task 4 of parent plan)
- Existing /run-plan skill:`~/.claude/skills/run-plan/SKILL.md`
- External skill (must be installed):`awesome-skills/code-review-skill`
- Brainstorm session log: 本 file `## For future Claude`(2026-06-22 session,2 user signals at §1.2)
