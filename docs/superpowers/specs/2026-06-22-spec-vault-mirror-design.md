---
date: 2026-06-22
updated: 2026-06-22
type: spec
status: draft
tags: [ship-workflow, ship-next, vault, mirror, specs]
ai-first: true
related-specs:
  - 2026-06-21-ship-next-mega-command-design.md
  - 2026-06-22-ship-next-auto-yes-design.md
  - 2026-06-14-obsidian-air-os-vault-design.md
supersedes: null
---

## For future Claude
> Let specs land in Obsidian for easy mobile/cross-device viewing. Repo stays
> canonical (engineers edit + code-review in repo); vault gets a read-only mirror
> at `<vault>/<project>/Specs/R-NNN-<slug>.md`. Trigger = dual-write at /ship-next
> Phase 3 (spec creation), with `mirror-source: docs/specs/...` injected into
> vault frontmatter so readers see "don't edit here". Discard cleans vault too.

## §1 Problem

### 1.1 Symptom
- Specs live in `docs/specs/R-NNN-<slug>.md` (repo, Execution Brain).
- Vault (Product Brain) already has VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS / Architecture / Proposals / Research / Roadmap-Notes.
- **No specs in vault** — so a product owner reading in Obsidian (mobile / cross-device) can't see the formal spec for an R-NNN. Has to clone the repo or browse GitHub.

### 1.2 Hard signals from brainstorm (2026-06-22)
1. **Repo is canonical, vault is mirror.** Engineers edit specs in repo (with code review); vault is read-only.
2. **Scope = spec only.** Brainstorm note / plan / learning / idea / decision stay repo-only.
3. **Trigger = dual-write at /ship-next P3.** Simplest path. Accept stale-window if spec is hand-edited in repo afterwards.

### 1.3 Why not the other shapes
| Rejected option | Why |
|---|---|
| Vault canonical, repo mirror | Breaks engineering workflow (engineers can't easily edit spec in repo with code-review trail) |
| Repo→vault reverse sync via sync.sh | sync.sh is purely vault→repo; adding the reverse direction conceptually mixes; YAGNI |
| Symlink | macOS-only; CI / fresh clone breaks |
| Dual canonical | "Which side is authoritative after a divergence?" ambiguity |

---

## §2 Goal + Success Criterion

### 2.1 Goal
A product owner opening Obsidian and navigating to `<vault>/10 Projects/<project>/Specs/` sees one `R-NNN-<slug>.md` per spec, viewable + wikilink-connected to ROADMAP rows / Proposals / Roadmap-Notes.

### 2.2 Success Criterion (observable)
- **Visibility**: after `/ship-next R-NNN`, the spec file exists at both `docs/specs/R-NNN-<slug>.md` (repo) and `<vault>/10 Projects/<project>/Specs/R-NNN-<slug>.md` (vault) with identical body content.
- **Authority signal**: vault file frontmatter contains `mirror-source: docs/specs/R-NNN-<slug>.md` so anyone opening it sees "this is a mirror".
- **Cleanup integrity**: `/ship-next --discard R-NNN` removes both repo and vault entries (no orphan).

### 2.3 Non-goals
- **Bi-directional sync** — repo always wins.
- **Brainstorm / plan / learning / idea / decision mirror** — repo-only. (Maybe later, separate spec.)
- **Vault Specs index / MOC** — Obsidian's directory view is sufficient. No `Specs/_index.md`.
- **Detect manual edits in vault** — if user edits vault file, it gets silently overwritten on next `/ship-next` write. By design.
- **Stale-window detection / warning** — if user edits spec in repo without re-running /ship-next, vault stays stale. By design. (User can run a one-off `cp` to re-sync, or re-invoke /ship-next.)

---

## §3 Architecture

### 3.1 Vault path convention

```
<vault>/10 Projects/<project>/Specs/R-NNN-<slug>.md
```

- Flat structure (no epic nesting). `R-001.3-wire-scene-engine.md` lives alongside `R-002-prompt-injection-defense.md`.
- Filename identical to repo side: `R-NNN-<slug>.md`.
- Directory `Specs/` is auto-created on first write (`mkdir -p`); no separate scaffold step.

### 3.2 Dual-write at /ship-next P3

After the existing P3 spec-write step in `commands/ship-next.md`, append:

```bash
# After repo-side spec write:
#   write to docs/specs/${ID}-${SLUG}.md (existing, unchanged)

# New: also write to vault (atomic via .tmp + mv, same pattern as sync.sh)
VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
mkdir -p "$VAULT_SPECS_DIR"
VAULT_SPEC="$VAULT_SPECS_DIR/${ID}-${SLUG}.md"

# Copy body but inject mirror-source key into frontmatter
~/.claude/skills/ship-workflow/lib/spec-mirror.sh \
  docs/specs/${ID}-${SLUG}.md "$VAULT_SPEC"
```

Where `lib/spec-mirror.sh` is a small new helper that:
1. Reads repo-side spec
2. Inserts `mirror-source: docs/specs/${ID}-${SLUG}.md` into frontmatter (if not already present)
3. Writes to `<dst>.tmp`
4. `mv <dst>.tmp <dst>` (atomic)

### 3.3 `--discard` cleanup

Existing `--discard` block removes worktree + branch. Add one line:

```bash
# Phase 1, --discard handler
rm -f "$VAULT_SPECS_DIR/${ID}-"*.md
```

Glob match by ID prefix because slug may have been derived differently in failed sessions — safe sweep.

### 3.4 Frontmatter convention (vault-side)

Repo spec frontmatter (unchanged):
```yaml
---
date: 2026-06-22
type: spec
status: draft
id: R-001.3
tags: [...]
ai-first: true
---
```

Vault mirror gets ONE extra key injected by `spec-mirror.sh`:
```yaml
---
date: 2026-06-22
type: spec
status: draft
id: R-001.3
tags: [...]
ai-first: true
mirror-source: docs/specs/R-001.3-wire-scene-engine.md   # ← NEW
---
```

That key is the one-line signal "edit upstream, not here".

### 3.5 Edge cases

| Situation | Handling |
|---|---|
| /ship-next P3 re-runs (resume) | Vault spec overwritten via atomic write. No intermediate state. |
| /ship-next --discard R-NNN | Vault Specs/R-NNN-*.md glob-removed alongside worktree + branch cleanup. No orphan. |
| /ship-next P6 cap=3 abort | Vault spec **retained** (worktree + branch are retained — vault state matches). Resume picks up from the same point. |
| User hand-edits repo spec after /ship-next | Vault stale until next /ship-next. Accepted. User may manually `cp` to re-sync. |
| User hand-edits vault spec | Silently overwritten on next /ship-next write. `mirror-source:` key serves as the "don't edit here" warning. |
| First /ship-next in a fresh repo (vault `Specs/` doesn't exist) | `mkdir -p` creates the dir. No-op if it exists. |
| `/ship-init` on a new repo | Doesn't pre-create `<vault>/<project>/Specs/`. P3 creates it on first use. |

---

## §4 Components

### 4.1 New files
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/lib/spec-mirror.sh` | Copy repo spec → vault Specs/ + inject `mirror-source:` frontmatter key; atomic write via `.tmp + mv` |
| `claude-skills/ship-workflow/tests/test_spec-mirror.bats` | TDD coverage for above |

### 4.2 Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/commands/ship-next.md` | P3 (after spec write + before commit): invoke `spec-mirror.sh`. P1 `--discard` block: glob-remove vault spec. |

### 4.3 Unchanged
- `lib/sync.sh` — no reverse sync direction added. Vault Specs/ is a one-way write target from /ship-next, not part of sync.sh's vault→repo mirror pattern.
- `lib/airos-binding.sh` — `project_path` resolver already gives the project root; Specs/ subpath is computed inline.
- `commands/ship-init.md` — no pre-create Specs/ dir; P3 handles it lazily.
- All other ship-* commands — orthogonal.

### 4.4 `spec-mirror.sh` interface (pseudocode)

```bash
#!/usr/bin/env bash
# spec-mirror.sh <src-spec-path> <dst-vault-path>
#
# Copies <src> to <dst> with one frontmatter modification:
#   inject `mirror-source: <src>` into the frontmatter block, after `type:` line.
# Atomic write via <dst>.tmp + mv. mkdir -p the parent dir.

set -euo pipefail
SRC="$1"
DST="$2"

[ -f "$SRC" ] || { echo "ERROR: source spec not found: $SRC" >&2; exit 2; }

mkdir -p "$(dirname "$DST")"
TMP="${DST}.tmp"

awk -v src="$SRC" '
  BEGIN { in_fm = 0; injected = 0 }
  /^---$/ {
    if (in_fm == 0) { in_fm = 1; print; next }
    if (in_fm == 1 && !injected) {
      print "mirror-source: " src
      injected = 1
    }
    in_fm = 0
    print; next
  }
  in_fm && /^mirror-source:/ { injected = 1 }   # already has it; do not duplicate
  { print }
' "$SRC" > "$TMP"

mv "$TMP" "$DST"
```

(Implementation will be refined in Plan stage.)

---

## §5 Data flow

### 5.1 Happy path — first /ship-next on a new R-NNN

```
1. User in main repo on dev branch
2. /ship-next R-001.3 --auto:yes (or interactive)
3. P1 pre-flight + worktree open (existing)
4. P3 brainstorming produces docs/specs/R-001.3-wire-scene-engine.md (existing)
5. NEW: spec-mirror.sh docs/specs/R-001.3-wire-scene-engine.md \
        $VAULT_SPECS_DIR/R-001.3-wire-scene-engine.md
   - mkdir -p $VAULT_SPECS_DIR (if absent)
   - atomic .tmp → mv
   - vault file has `mirror-source: docs/specs/...` in frontmatter
6. P3 git commit "brainstorm+spec: R-001.3 ..." (existing — vault file is NOT in git)
7. ... rest of mega flow continues unchanged
```

### 5.2 Resume — /ship-next R-NNN where worktree exists

```
1. P1 detects worktree, prompts continue (or auto-continues in --auto:yes)
2. P3 resume detection sees spec exists → skip to P4
3. Vault spec also stays put (no rewrite needed; content already mirrored)
4. ... continues
```

### 5.3 --discard cleanup

```
1. /ship-next --discard R-001.3
2. P1 --discard handler:
   - git worktree remove --force <wt>
   - git branch -D ship/R-001.3-<slug>
   - rm -f $VAULT_SPECS_DIR/R-001.3-*.md      # NEW
3. Exit 0
```

### 5.4 Edge: hand-edit divergence

```
1. /ship-next R-001.3 completes — both repo + vault have spec
2. Engineer edits docs/specs/R-001.3-wire-scene-engine.md (e.g. typo fix)
3. Vault is now stale.
4. Acceptable per §2.3 non-goals. Mitigation:
   - User can manually `cp docs/specs/R-001.3-*.md <vault>/.../Specs/`
   - OR re-invoke /ship-next R-001.3 (P3 resume sees spec exists, but vault dual-write happens regardless? — actually P3 resume SKIPS spec-write, so vault stays stale)
5. Pragmatic fix: re-run `lib/spec-mirror.sh docs/specs/R-001.3-*.md $VAULT_SPECS_DIR/R-001.3-*.md` manually
```

(Plan §7.2 open question: should P3 resume detection re-mirror spec to vault even when spec already exists?)

---

## §6 Acceptance Criteria

| ID | Criterion |
|---|---|
| AC-001 | `lib/spec-mirror.sh <src> <dst>` writes `<dst>` with `mirror-source: <src>` injected into frontmatter, atomically (no `<dst>.tmp` leftover). |
| AC-002 | spec-mirror.sh is idempotent: running it twice with same src/dst produces the same file (no duplicate `mirror-source` keys). |
| AC-003 | spec-mirror.sh exits 2 if `<src>` doesn't exist. |
| AC-004 | spec-mirror.sh creates `<dst>` parent dir via `mkdir -p` if absent. |
| AC-005 | After `/ship-next R-NNN`, file exists at `<vault>/10 Projects/<project>/Specs/R-NNN-<slug>.md` with identical body to `docs/specs/R-NNN-<slug>.md`. |
| AC-006 | The vault file's frontmatter contains `mirror-source: docs/specs/R-NNN-<slug>.md`. |
| AC-007 | After `/ship-next --discard R-NNN`, vault `Specs/R-NNN-*.md` is removed. |
| AC-008 | `/ship-next R-NNN` on a project where vault `<project>/Specs/` doesn't exist auto-creates the dir. |
| AC-009 | Existing 89 bats tests stay green. New bats tests for spec-mirror.sh added inline. |
| AC-010 | Existing /ship-init behavior unchanged (no new Specs/ pre-create step). |

---

## §7 Open Questions

### 7.1 Closed (this session)
- ✅ Repo canonical, vault is mirror
- ✅ Scope: only spec (not brainstorm / plan / learning / idea / decision)
- ✅ Trigger: /ship-next P3 dual-write
- ✅ Vault path: `<vault>/10 Projects/<project>/Specs/R-NNN-<slug>.md` (flat)
- ✅ `mirror-source:` frontmatter key as authority signal

### 7.2 Open (plan stage will close)
1. **P3 resume re-mirror?** When /ship-next resumes and detects spec already exists, should it skip vault dual-write (current design) or RE-mirror to catch any post-write edits? Plan-stage decision; lean towards re-mirror for safety.
2. **`spec-mirror.sh` invocation in `--auto:yes` decision log?** auto-decision-log.sh entry: "P3 spec mirrored to vault: <path>"? Optional, low value, plan decides.
3. **`/ship-compound` re-mirror?** Should P8 re-mirror spec to catch executor-time edits? Lean no (spec shouldn't change during executor); plan confirms.
4. **Other artifacts later?** brainstorm/plan/learning mirror — explicitly out-of-scope here. Future spec if user revisits.

---

## §8 Out of scope

- **Brainstorm / plan / learning / idea / decision** mirroring to vault
- **Vault Specs MOC** (`Specs/_index.md`)
- **Bi-directional sync** (any vault → repo direction)
- **Stale-window detection** UI / warning
- **Cross-project Specs aggregation** (vault has `<project>/Specs/`; no global `Specs/` index)
- **`/ship-init` Specs/ pre-creation** — lazy auto-create at P3 first use

---

## §9 Implementation phases

| Phase | Content | Exit condition |
|---|---|---|
| **0. Spec lock** | This spec + user review pass | spec committed |
| **1. lib/spec-mirror.sh + bats** | TDD: 4 ACs (basic, idempotent, source-missing, mkdir-p) | tests green |
| **2. ship-next.md P3 integration** | Insert dual-write call after spec write, before commit | AC-005, AC-006 manual verify |
| **3. ship-next.md --discard cleanup** | Glob-remove vault Specs/R-NNN-* | AC-007 manual verify |
| **4. End-to-end smoke** | `/ship-next --adhoc "smoke vault spec mirror" --auto:yes` in ai-eden-service | AC-001..010 |

### Estimate
- Phase 1: ~30 min (small bash + 4-6 bats tests)
- Phase 2-3: ~20 min (markdown edits)
- Phase 4: ~30 min (manual smoke, token-heavy)
- **Total: ~1.5 hours**

---

## §10 Migration / Rollout

### 10.1 Backward compat
- `/ship-next` invocations WITHOUT this feature behave identically (P3 still writes repo spec).
- After this feature ships, new `/ship-next` invocations dual-write.
- Existing repo specs that were created before this feature: **vault Specs/ stays empty**. No backfill (out-of-scope; user can run `lib/spec-mirror.sh` manually for each).

### 10.2 Backfill (optional, manual)
If user wants existing R-001.x specs in vault:
```bash
for f in docs/specs/R-*.md; do
  ~/.claude/skills/ship-workflow/lib/spec-mirror.sh "$f" \
    "$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs/$(basename $f)"
done
```
One-liner; no automation needed.

### 10.3 Vault structure note
The new `Specs/` directory becomes a new top-level item under each project. Adds parallelism to existing `Architecture/`, `Proposals/`, `Research/`, `Roadmap-Notes/`. No naming collision.

---

## §11 References

- Parent spec (mega flow): `docs/superpowers/specs/2026-06-21-ship-next-mega-command-design.md`
- Sibling spec (auto:yes): `docs/superpowers/specs/2026-06-22-ship-next-auto-yes-design.md`
- AIR-OS vault design: `docs/superpowers/specs/2026-06-14-obsidian-air-os-vault-design.md`
- Existing similar pattern (vault-canonical artifacts): `lib/sync.sh` Proposals/ + Roadmap-Notes/ mirror blocks
- Current /ship-next P3 spec write site: `claude-skills/ship-workflow/commands/ship-next.md` Phase 3
- Brainstorm session log: this file `## For future Claude` block (2026-06-22 session, 3 user signals at §1.2)
