# R-006 keep-only-learnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a shipped R-NNN leaves only its learning in the repo; spec (with Decisions) is mirrored to the vault and removed at compound; no separate brainstorm file.

**Architecture:** Extend R-005's pre-`ship_log` block in ship-compound step 9 (mirror spec, then one `git rm`). Text edits in ship-next Phase 3/7, templates, and docs. Tests execute the real step-9 block (`tests/test_command-blocks.bats`).

**Tech Stack:** bash, git, bats.

**Spec:** `docs/specs/R-006-keep-only-learnings.md`

## Global Constraints
- Removed at step 9: `docs/specs/${ID}-${slug}.md`, `docs/brainstorms/${ID}-${slug}.md`, `docs/plans/${ID}-${slug}.md`, `docs/plans/${ID}-${slug}-review-fix-*.md`. Nothing else.
- Vault mirror is best-effort: no binding → WARN, step continues.
- No new commit.

## Review Focus
- No vault config in HOME (every existing step-9 test) → step 9 must still exit 0 (AC-3, AC-5).
- Spec edited after Phase 3 → the vault copy reflects the edit (AC-2).
- Another ship's spec survives (AC-1).
- Mirror happens before the rm — after the rm the working-tree file is gone.

---

### Task 1: ship-compound step 9 mirrors and removes spec + legacy brainstorm

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md` (step 9 pre-`ship_log` block; step 3 prune sentence; the paragraph after step 9's block)
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats`

- [ ] **Step 1: Failing tests**
  - `ship-compound step 9 (mr) removes this ship's spec, brainstorm and plan, not another ship's spec` — AC-1: commit `docs/specs/R-1-x.md`, `docs/brainstorms/R-1-x.md`, `docs/plans/R-1-x.md`, `docs/specs/R-2-y.md` on `ship/R-1-x`; run; assert status 0 and `git ls-files docs/specs docs/brainstorms docs/plans` is exactly `docs/specs/R-2-y.md`.
  - `ship-compound step 9 mirrors the spec's latest text to the vault before removing it` — AC-2: write `$HOME/.claude/ship-workflow.yml` with `airos_vault: $SCRATCH/vault` and `airos_projects_dir: "10 Projects"`; commit spec `v1`, then commit an edit `v2-after-review`; run; `VP=$(cd <wt> && $HOME/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)`; assert `grep -q v2-after-review "$VP/Specs/R-1-x.md"`.
  - `ship-compound step 9 (squash) removes the spec with no vault configured` — AC-3.
- [ ] **Step 2:** `bats tests/test_command-blocks.bats -f 'step 9'` → the three new tests FAIL.
- [ ] **Step 3:** In the pre-`ship_log` block, before the existing `git rm`:
  ```bash
  if [ -f "docs/specs/${ID}-${slug}.md" ]; then
    VAULT_PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path 2>/dev/null) \
      && ~/.claude/skills/ship-workflow/lib/spec-mirror.sh "docs/specs/${ID}-${slug}.md" "$VAULT_PROJECT/Specs/${ID}-${slug}.md" \
      || echo "WARN: spec not mirrored to the vault — it stays in git history" >&2
  fi
  ```
  Add `"docs/specs/${ID}-${slug}.md" "docs/brainstorms/${ID}-${slug}.md"` to the `git rm` pathspecs. Reword the paragraph after the block (only the learning stays; R-005, R-006). Step 3 prune: "least recently cited by any file under `docs/learnings/`".
- [ ] **Step 4:** `bats tests/` → all pass except the known cwd-guard failure.
- [ ] **Step 5:** Commit `feat(R-006): ship-compound mirrors and removes this ship's spec — Task 1`.

### Task 2: no brainstorm file; Decisions in spec; Key Decisions in learning

**Files:**
- Modify: `commands/ship-next.md` Phase 3 steps 1–3, Phase 7 `Spec:` line; `templates/repo/SPEC.md`; `templates/repo/LEARNING.md`; `commands/ship-init.md:77`; `SKILL.md:26`; `README.md:12`; `references/flow-diagrams.md:55`
- Delete: `templates/repo/BRAINSTORM.md`
- Test: `tests/test_templates-seams.bats`

- [ ] **Step 1: Failing tests** (structural — these are prose contracts read by an agent)
  - `SPEC template has a Decisions section` — `grep -qF '## Decisions' templates/repo/SPEC.md`.
  - `LEARNING template has a Key Decisions section` — `grep -qF '## Key Decisions' templates/repo/LEARNING.md`.
  - `ship-next Phase 3 writes no brainstorm file` — the text between `^## Phase 3` and `^## Phase 4` contains no `docs/brainstorms/` and contains `## Decisions`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Edit as listed. Phase 3 step 1 adds: the spec must include `## Decisions` (what the operator decided in the dialogue and why; mark your own calls as yours) — there is no separate brainstorm file. Step 2 verifies only the spec. Step 3 stages only the spec, message `spec: ${ID} ${SLUG}`. Phase 7: `Spec:  docs/specs/${ID}-${SLUG}.md (removed by /ship-compound; full text in the vault Specs/)`. LEARNING.md: `## Key Decisions` after `## What Shipped`, with a one-line hint "carry the spec's Decisions forward — the spec leaves the repo at compound". Remove `brainstorms/` from the four doc lists.
- [ ] **Step 4:** `bats tests/` → all pass except the known failure.
- [ ] **Step 5:** Commit `feat(R-006): Phase 3 writes no brainstorm file; Decisions live in spec and learning — Task 2`.
