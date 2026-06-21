---
date: 2026-06-21
updated: 2026-06-21
type: spec
status: draft
tags: [ship-workflow, ship-next, worktree, code-review, mega-command]
ai-first: true
related-specs:
  - 2026-06-14-ship-workflow-skill-design.md
  - 2026-06-17-roadmap-explainer-notes-design.md
supersedes:
  - "commands/ship-build.md (retired)"
---

## For future Claude
> 把 `/ship-next` 從「brainstorm + spec 半段」升級成 mega-command:從挑 R-NNN
> 一路跑到 squash-merged-到-原 branch。中間自動在 sibling worktree 隔離、用
> `awesome-skills/code-review-skill` strict gate 擋 blocking findings、自動 loop
> fix。`/ship-build` 隨之退役。所有 escape-hatch ship-* commands 自動繼承
> worktree cwd,無需改動。

## §1 Problem

### 1.1 觀察到的症狀
- 今天 `/ship-next` 跟 `/ship-build` 分成兩段。直覺命名暗示「next = 拿下一個 R-NNN」 應該是端到端動作,但實際只到 spec 就結束。
- 實作 (`/ship-build`) 跟 brainstorm 在同一個 working tree;沒有 worktree 隔離 → 任一階段失敗都會弄髒 main。
- 沒有 review gate;executor 寫完就 commit,沒人擋低品質 PR 進 main。
- `awesome-skills/code-review-skill` 已存在但沒 wired-in 任何 ship-workflow 動作。

### 1.2 從 brainstorm session 收到的 4 個 hard signals (2026-06-21)
1. **Worktree 包 ship-next + ship-build**(scope:整個 brainstorm → spec → plan → execute 都在 worktree)
2. **Strict review gate**:任何 `blocking` finding 就擋 merge,使用者改完 re-review 才放行
3. **Squash merge**:一個 R-NNN = 一個 commit on main,完整 metadata 在 commit body
4. **重新命名**:`/ship-next` 變 mega-command;`/ship-build` 退役。命名跟「Next」直覺對齊

### 1.3 既有 artifact 為何不夠
| Artifact | 為何不夠 |
|---|---|
| **`/ship-next` 現狀** | 只到 spec;沒 worktree;沒 review |
| **`/ship-build` 現狀** | spec → plan → execute → commit,但 commit 直接落 main;無 review;與 ship-next 切割 |
| **`superpowers:using-git-worktrees`** | 工具有了,但 ship-workflow 沒呼叫 |
| **`awesome-skills/code-review-skill`** | 工具有了,但沒 strict-gate wiring |

---

## §2 Goal + Success Criterion

### 2.1 Goal
使用者只打**一個指令** `/ship-next [R-NNN]`,即可從 ROADMAP 挑 row 一路執行到 main 上多一個 squashed commit + ROADMAP row 標 ✅。中間自動隔離、code review 強 gate、failure 可恢復。

### 2.2 Success Criterion (observable)
- **使用面**:在 `ai-eden-service` repo 跑一次 `/ship-next R-001.X`,end-to-end 完成不需要使用者切換命令、不需要手動 worktree 操作
- **品質面**:main branch 上每個 R-NNN squashed commit 過了 strict review gate (`blocking=0`)
- **隔離面**:整個 cycle 中 main branch index 沒被修改(diff 為空)
- **可恢復面**:中斷後 re-invoke `/ship-next R-NNN` 能從 worktree 接續,不從頭開始
- **可中止面**:使用者可以用 `--discard` 完全放棄,worktree + branch 都清乾淨

### 2.3 Non-goals
- **不取代 `/ship-roadmap`、`/ship-propose`、`/ship-arch`、`/ship-research`**:這些獨立流程
- **不取代 escape-hatch commands** (`/ship-idea`、`/ship-decision`、`/ship-explain`):這些在 worktree 內也能正常用,artifacts 隨 squash 帶過去
- **不改 `awesome-skills/code-review-skill` 本身**:skill 已存在,我們只負責 invocation + parsing
- **不支援多 R-NNN 並行**(雖然 worktree 本身允許):一次只能 1 個 active worktree

---

## §3 Architecture

### 3.1 Lifecycle (9 phases)

```
state: 使用者在 main branch (cwd = <repo>)
            │
            │ /ship-next R-NNN  (或無參數 → 自動挑)
            ↓
┌─────────────────────────────────────────────────────────┐
│ P1. Pre-flight                                           │
│  - Sync product brain (sync.sh)                          │
│  - Resolve R-NNN: arg 給就用,沒給就跑既有 ranking 邏輯  │
│  - Detect existing worktree at deterministic path        │
│    若存在 → prompt: continue / discard / abort           │
│                                                          │
│ P2. Open worktree                                        │
│  Path: <parent>/<repo>-worktrees/R-NNN-<slug>            │
│  Branch: ship/R-NNN-<slug>                               │
│  Driver: superpowers:using-git-worktrees                 │
│  cd 進 worktree (Claude 自動,使用者見告)                │
│                                                          │
│ P3. Brainstorm                                           │
│  Driver: superpowers:brainstorming                       │
│  Output:                                                 │
│   - docs/brainstorms/R-NNN-<slug>.md                     │
│   - docs/specs/R-NNN-<slug>.md                           │
│  Commit: "brainstorm+spec: R-NNN <slug>"                 │
│                                                          │
│ P4. Writing-plans                                        │
│  Driver: superpowers:writing-plans                       │
│  Output: docs/plans/R-NNN-<slug>.md                      │
│  Commit: "plan: R-NNN <slug>"                            │
│                                                          │
│ P5. Choose executor                                      │
│  Ask user:                                               │
│   1. subagent-driven (recommended)                       │
│   2. inline executing-plans                              │
│   3. codex /run-plan                                     │
│  Executor commits N task commits in worktree branch      │
│                                                          │
│ P6. Code review loop (strict gate)                       │
│  Driver: awesome-skills/code-review-skill                │
│  Input: git diff <main>..HEAD                            │
│  Output: severity-tagged findings                        │
│  while blocking_count > 0:                               │
│    - Print blockers                                      │
│    - if attempt > 3: pause, ask user                     │
│    - else: build fix-plan + re-invoke executor           │
│    - re-invoke review                                    │
│                                                          │
│ P7. Squash merge → original branch                       │
│  cd <original repo>                                      │
│  git merge --squash ship/R-NNN-<slug>                    │
│  git commit -m "<formatted message>"                     │
│                                                          │
│ P8. /ship-compound — wrap up                             │
│  Driver: /ship-compound (existing)                       │
│  Log learning, promote to vault, mark ROADMAP ✅          │
│                                                          │
│ P9. Cleanup worktree                                     │
│  git worktree remove <path>                              │
│  git branch -d ship/R-NNN-<slug>                         │
│  失敗時 keep + 印 hint                                   │
└─────────────────────────────────────────────────────────┘
            │
            ↓
state: 使用者回到 main + R-NNN row 已 ✅
```

### 3.2 Worktree path convention (deterministic)

```bash
REPO_PATH=$(pwd)                          # /Users/leric/Desktop/code/ai-eden-service
REPO_NAME=$(basename "$REPO_PATH")        # ai-eden-service
PARENT=$(dirname "$REPO_PATH")            # /Users/leric/Desktop/code
WORKTREE_PATH="$PARENT/${REPO_NAME}-worktrees/R-NNN-<slug>"
BRANCH_NAME="ship/R-NNN-<slug>"
```

**Slug derivation**:從 ROADMAP row description 機械式取出 — 同 `/ship-explain` 的 slug derivation 規則 (kebab-case 3-5 字)。**首字優先 imperative verb** (Land, Wire, Author, Migrate, Implement, Extend, Build, Roll-out)。

**No state file**:R-NNN+slug 已 uniquely identify worktree。`/ship-next R-001.3` 不論在 main / 在已存在 worktree / 在別人的 worktree,都能算出正確 path。

### 3.3 Code review gate policy

**Strict**:任何 `blocking` severity → 不 merge。

**Loop policy (capped)**:
```
attempt = 1
while attempt ≤ 3:
  output = invoke awesome-skills/code-review-skill on git diff <main>..HEAD
  blockers = parse blocking findings from output
  if len(blockers) == 0:
    break  # ready to merge
  print blockers to terminal
  # Build inline fix plan from blockers (each = 1 task)
  fix_plan = [
    {task: i, file: b.file, line: b.line, code: b.code, suggestion: b.suggestion}
    for i, b in enumerate(blockers)
  ]
  invoke previously-chosen executor (subagent / inline / codex) with fix_plan
  attempt += 1
else:  # attempt > 3 ran out
  pause:
    "3 review attempts didn't clear blockers. Continue auto-fix? [Y/n/abort]"
```

`major` findings 不擋 merge,但列出來給使用者選:
- `[F] fix now` (新 fix-plan iteration)
- `[I] log as IDEA-NNN follow-up` (`/ship-idea` 自動帶 `related-roadmap-item: R-NNN`)
- `[S] skip`

### 3.4 Squash merge commit format

```
feat: R-NNN <one-line description from ROADMAP row>

↳ done when: <criterion from ROADMAP ↳ done when:>

Tasks (from docs/plans/R-NNN-<slug>.md):
1. <task 1 title>
2. <task 2 title>
N. <task N title>

Code review (awesome-skills/code-review-skill):
- blocking: 0 ✓
- major:    M (see plan §Execution log for resolutions)
- minor:    K
- praise:   P

Spec:  docs/specs/R-NNN-<slug>.md
Plan:  docs/plans/R-NNN-<slug>.md
Notes: docs/roadmap-notes/R-NNN-<slug>.md (if exists)

🤖 ship/R-NNN-<slug>
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

### 3.5 Escape hatches in worktree

`/ship-idea`、`/ship-decision`、`/ship-explain`、`/ship-research` 都會在 worktree cwd 內被 invoke (因為 Claude cd 進 worktree 後就在裡面)。它們的 artifact 自然 commit 到 worktree branch,squash 時被吸進 main 上的單一 commit。

**Exception (hard-blocked)**:`/ship-roadmap`、`/ship-arch`、`/ship-init`、`/ship-propose` 是 main branch 的 cross-cutting workflows — 它們會動 ROADMAP、Architecture、Proposals 這些跨 R-NNN 的 artifacts。在 worktree 內 invoke 會造成這些改動被 squash 進單一 R-NNN 的 commit,弄亂 main 的 history boundary。

**實作**:這 4 個命令的 .md 文件**開頭加 cwd 偵測**:
```bash
# Refuse if cwd is inside a ship-workflow worktree
if git rev-parse --git-common-dir 2>/dev/null | grep -q "/worktrees/"; then
  echo "ERROR: /ship-{roadmap,arch,init,propose} cannot run inside a ship/* worktree."
  echo "       cd back to the main repo (or another non-worktree) first."
  exit 1
fi
```

新 `/ship-next` 開頭不額外 detect — 受影響命令各自 self-guard。

---

## §4 Components

### 4.1 Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/commands/ship-next.md` | **完全重寫** — 9-phase mega flow,worktree open + brainstorm + spec + plan + execute + review + merge + compound + cleanup |
| `claude-skills/ship-workflow/commands/ship-init.md` | Next-suggested commands list:`/ship-build` → `/ship-next`;**加 §3.5 worktree-guard 開頭 block** |
| `claude-skills/ship-workflow/commands/ship-compound.md` | 偵測 worktree → 自動在 main 上 mark ROADMAP ✅;`next suggested` 也指 `/ship-next`(不需 guard — compound 在 worktree 內就是預期用法) |
| `claude-skills/ship-workflow/commands/ship-roadmap.md` | **加 §3.5 worktree-guard 開頭 block** |
| `claude-skills/ship-workflow/commands/ship-arch.md` | **加 §3.5 worktree-guard 開頭 block** |
| `claude-skills/ship-workflow/commands/ship-propose.md` | **加 §3.5 worktree-guard 開頭 block** |
| `claude-skills/ship-workflow/templates/repo/BRAINSTORM.md` | 移除 `/ship-build` 引用 (若有) |
| `claude-skills/ship-workflow/templates/repo/PLAN.md` | 移除 `/ship-build` 引用 (若有) |
| `claude-skills/ship-workflow/SKILL.md` | command count 10 → 9;flow 圖更新 |

### 4.2 Deleted files
| Path | 原因 |
|---|---|
| `claude-skills/ship-workflow/commands/ship-build.md` | 功能融進 `/ship-next` |

### 4.3 New helper script (optional, defer to plan)
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/lib/code-review-parse.sh` | 解析 code-review-skill output,emit `BLOCKING_COUNT` `MAJOR_COUNT` etc. 給 ship-next 命令文件用 |

**設計考量**:也可以讓 ship-next.md 命令文件直接用 grep,不寫 helper。看 plan 階段決定。

### 4.4 Out-of-tree
| Path | Change |
|---|---|
| `~/.claude/commands/ship-build.md` (symlink) | **刪除** |
| `~/.claude/skills/code-review-skill/` | 必須存在(由使用者預先 install)。`/ship-next` 開頭驗證,缺則 ERROR + 給 install hint |

### 4.5 Worktree-aware logic in ship-next.md (pseudocode)

```bash
# P1 Pre-flight
ROADMAP_PATH="$(lib/airos-binding.sh project_path)/ROADMAP.md"
sync.sh

ID="$1"
[ -z "$ID" ] && ID=$(rank_now_section "$ROADMAP_PATH" | head -1)
SLUG=$(derive_slug "$ROADMAP_PATH" "$ID")

REPO=$(pwd)
WORKTREE="$(dirname $REPO)/$(basename $REPO)-worktrees/${ID}-${SLUG}"
BRANCH="ship/${ID}-${SLUG}"
ORIG_BRANCH=$(git branch --show-current)

if [ -d "$WORKTREE" ]; then
  ask user: continue / discard / abort
else
  # P2 Open worktree
  invoke superpowers:using-git-worktrees with path=$WORKTREE branch=$BRANCH from=$ORIG_BRANCH
fi
cd "$WORKTREE"

# P3-P4: brainstorm + writing-plans skills run here
# P5: executor choice (existing 3-way menu)
# P6: review loop
# P7-P9: squash merge + compound + cleanup
```

---

## §5 Data flow

### 5.1 Happy path — first time R-NNN
```
1. main repo, cwd=<repo>, branch=main
2. /ship-next R-001.3 → resolves slug=wire-scene-engine
3. mkdir worktree at <parent>/<repo>-worktrees/R-001.3-wire-scene-engine
   branch=ship/R-001.3-wire-scene-engine off main
4. cd worktree
5. brainstorm → spec → commit "brainstorm+spec: R-001.3 wire-scene-engine"
6. writing-plans → plan → commit "plan: R-001.3 wire-scene-engine"
7. user picks "1. subagent" → 10 task commits in worktree
8. code-review-skill on diff main..HEAD → blocking=0, major=2 (logged)
9. cd back to original repo
10. git merge --squash ship/R-001.3-wire-scene-engine
11. git commit -m "feat: R-001.3 Wire SceneEngine into dialogue.py ..." (full template)
12. /ship-compound → ROADMAP row → ✅, learning written
13. git worktree remove ../<repo>-worktrees/R-001.3-wire-scene-engine
14. git branch -d ship/R-001.3-wire-scene-engine
```

### 5.2 Recovery — R-NNN started yesterday, resumed today
```
1. main repo, /ship-next R-001.3
2. P1 detects existing worktree → prompt
3. user: Y (continue)
4. cd worktree, detect state by checking commits on branch:
   - 0 commits beyond fork = restart from P3 brainstorm
   - 1 commit = spec done, resume from P4 plan
   - 2 commits = plan done, resume from P5 executor
   - N commits + plan file = check ## Execution log in plan, resume from there
5. Continue normal flow
```

### 5.3 Code review blocks merge
```
1. After P5 executor commits, P6 invokes review
2. Review returns: blocking=2 ("SQL injection in handler.py:45", "unhandled None in cache.py:12")
3. Print blockers
4. fix_plan = build inline plan from 2 blockers
5. Re-invoke executor (same kind as P5 choice) on fix_plan
6. Executor commits 2 fix commits
7. Re-invoke review → blocking=0, proceed to P7
```

### 5.4 Edge case — code-review-skill missing
```
1. P6 step: check ~/.claude/skills/code-review-skill/SKILL.md exists
2. If missing:
   ERROR: awesome-skills/code-review-skill not installed.
   Install: git clone https://github.com/awesome-skills/code-review-skill \
            ~/.claude/skills/code-review-skill
   Then re-invoke /ship-next ${ID} to resume.
3. Worktree stays alive — easy resume
```

### 5.5 Edge case — user discards mid-flow
```
1. P3 brainstorm, user realises wrong R-NNN
2. user: Ctrl-C and run /ship-next --discard
3. cd back to original repo
4. git worktree remove --force <path>
5. git branch -D ship/<branch>
6. Print: "Discarded R-NNN worktree. main branch untouched."
```

---

## §6 Acceptance Criteria

| ID | Criterion |
|---|---|
| AC-001 | `/ship-next R-NNN` 在 cwd=main repo 跑時,自動建 worktree at deterministic path 並 cd 進去 |
| AC-002 | `/ship-next` 不帶參數時,從 ROADMAP "Now" 區依既有 rank 邏輯選 R-NNN(epic skip,children .M 升序) |
| AC-003 | Worktree 內 brainstorm + spec + plan + N 個 executor task commits 全部成功 commit 到 `ship/R-NNN-<slug>` branch |
| AC-004 | P6 code review loop 偵測 `blocking` count;`blocking=0` 才放行 |
| AC-005 | P6 loop attempt > 3 時自動 pause,提示使用者選 [Y/n/abort] |
| AC-006 | P7 squash merge 後 main branch 多 1 個 commit,commit message 完全照 §3.4 template |
| AC-007 | `/ship-next R-NNN` 在 worktree 已存在時 prompt continue/discard/abort,3 選項都 work |
| AC-008 | `/ship-next --discard R-NNN` 強制刪除 worktree + branch,exit 0 |
| AC-009 | `~/.claude/skills/code-review-skill/` 不存在時,P6 直接 ERROR 並給 install hint |
| AC-010 | `commands/ship-build.md` 已刪;`~/.claude/commands/ship-build.md` symlink 已刪 |
| AC-011 | `/ship-init` 提示的 "next suggested" 不再含 `/ship-build` |
| AC-012 | `/ship-compound` 在 P8 自動 detect cwd 是 worktree,將 ROADMAP row 標 ✅ 寫在 main repo 的 ROADMAP |
| AC-013 | `/ship-roadmap`、`/ship-arch`、`/ship-init`、`/ship-propose` 在 worktree cwd 內 invoke 時 **hard-block** with ERROR + hint;exit 非 0 |

---

## §7 Open Questions

### 7.1 Closed (此 session 已決定)
- ✅ Worktree scope: 包 ship-next + ship-build
- ✅ Review gate: strict (blocking=0 才放行)
- ✅ Merge strategy: squash
- ✅ Command name: `/ship-next` 變 mega;`/ship-build` 退役

### 7.2 Open (plan 階段再定)
1. **Review loop cap 真的 3 嗎?**:可能 2 太少,5 太多。Plan 階段先用 3,P5 跑 production usage 觀察後調。
2. **`/ship-next` resume detection 怎麼判斷 "to which P"**:目前用「branch commit count + 文件存在性」判斷。Edge case:使用者手動加了一個 unrelated commit,count 不準。要不要 worktree 內存 `.ship-state` 文件?Plan 階段決定。
3. **Major findings 預設動作**:`/ship-idea` 自動帶 `related-roadmap-item: R-NNN` 但這需要 `/ship-idea` 支援該 flag。Plan 階段確認 ship-idea.md 是否已支援。
4. **Test runner integration**:今天 ship-build 沒跑 test。新 `/ship-next` 是否在 P6 之前 run test suite?若 fail 也算 blocking?Plan 階段 user 拍板。
5. **Worktree base branch**:今天假設從 `main` 開。若使用者在 feature branch 跑 `/ship-next`,worktree 應該從 current branch fork(讓 stacked branches 也支援)。Plan 階段確認。

---

## §8 Out of scope

- **多 R-NNN 並行 worktree**:技術上 git worktree 允許,但 ship-workflow UX 暫不支援(複雜化 cleanup + state 偵測)
- **Web UI / Dashboard 看 worktree 狀態**:純 CLI/Discord workflow
- **跨 repo 同 R-NNN** (例:R-001.3 跨 backend + frontend repo):各自 worktree,不嘗試協調
- **取代 `superpowers:finishing-a-development-branch`**:該 skill 處理 merge / PR / cleanup 一般 case。`/ship-next` 是專為 R-NNN cycle 的 narrow case
- **改 awesome-skills/code-review-skill 本身**:外部 skill,我們只 wire-in
- **支援 main / master 之外的 base branch 自動偵測**:plan 階段可能 close 這個 (見 §7.2-Q5)

---

## §9 Implementation phases

| Phase | 內容 | 退場條件 |
|---|---|---|
| **0. Spec lock** | 此 spec + 使用者 review pass | spec committed |
| **1. ship-next.md rewrite** | 完整重寫 9-phase mega flow,含 worktree open/cd 邏輯 | AC-001/002 手動驗 |
| **2. Code review loop integration** | P6 邏輯,parse skill output + fix-plan re-invoke + cap=3 | AC-004/005 |
| **3. Squash merge + cleanup** | P7-P9,含 commit template + worktree remove | AC-006/012 |
| **4. Recovery + discard paths** | 既存 worktree detect + continue/discard/abort prompt + `--discard` flag | AC-007/008 |
| **5. ship-build retirement** | Delete file + symlink + update SKILL.md / ship-init / ship-compound references | AC-010/011 |
| **5b. Worktree guards** | 加 §3.5 cwd-detect block 到 ship-roadmap / ship-arch / ship-init / ship-propose | AC-013 |
| **6. End-to-end smoke test** | 在 ai-eden-service 跑一次 `/ship-next R-001.X` (挑 effort=S 的 child) | success criterion §2.2 |
| **7. Polish** | Test runner integration (§7.2-Q4)、base branch detect (§7.2-Q5) — deferred,觀察後決定 | post-Phase-6 |

### Estimate
- Phase 1-5:~3-4 小時(主要是 markdown / shell logic;沒新增 lib)
- Phase 6:~1 小時(真實 R-NNN exec,token cost 是大宗)
- **總計:4-5 小時** (單 session 或拆 2 個 chunks)

---

## §10 Migration / Rollout

### 10.1 既有 worktree state
無 — 沒人之前用 worktree。乾淨遷移。

### 10.2 `/ship-build` 殺得乾淨
1. 刪 commands/ship-build.md
2. 刪 `~/.claude/commands/ship-build.md` symlink
3. Update ship-init.md 的 next-suggested
4. Update SKILL.md 的 command count + flow diagram
5. Update ship-compound.md 的 next-suggested
6. Search-and-replace `ship-build` in templates/

### 10.3 Documentation
- README in SKILL.md:把 "10 commands" 改成 "9 commands" (ship-build out, no new in)
- Discord bot 啟動時 rescan commands;ship-build 的 frontmatter 不再存在 → bot restart 後 commands 變 9 個。**需要手動 kill/restart bot 才生效** — 不是自動。

### 10.4 Backward compat
- 使用者打 `/ship-build` → "invalid command" error from Claude Code's resolution。Acceptable;一次性 break。
- 既有 docs/specs/R-*.md 完全沿用;新 `/ship-next` 在 P3 step 偵測「spec 已存在」會跳過 brainstorm,直接走 P4 plan(支援使用者已手動寫 spec 的情境)

---

## §11 References

- Spec ancestor:`docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
- Existing /ship-build code:`claude-skills/ship-workflow/commands/ship-build.md`
- Existing /ship-next code:`claude-skills/ship-workflow/commands/ship-next.md`
- External skill (must be installed):`awesome-skills/code-review-skill` — https://github.com/awesome-skills/code-review-skill
- Superpowers driver: `superpowers:using-git-worktrees`、`superpowers:brainstorming`、`superpowers:writing-plans`、`superpowers:subagent-driven-development`、`superpowers:executing-plans`
- Codex driver: `/run-plan` (gstack)
- Brainstorm session log: 本 file `## For future Claude` block (2026-06-21 session,4 user signals at §1.2)
