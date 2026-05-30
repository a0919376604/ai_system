---
description: Interview-style brainstorm: Claude reads vault, opens with 4-6 bold next-direction provocations, drills via follow-ups, distills into a session file feeding /obsidian-roadmap
argument-hint: <repo>
category: thinking
triggers_en: ["brainstorm project", "obsidian brainstorm", "what should I work on", "stuck on next step"]
param-autocomplete:
  - name: repo
    source: vault-projects
---

Use the obsidian-second-brain skill. Execute `/obsidian-brainstorm $ARGUMENTS`:

The first argument is `<repo>` (project name or absolute path bound by hub `local-path`). Optional flags:
- `--topic="<seed>"`: narrow the provocation focus (e.g. `--topic="客戶流失"`)
- `--lens=gap|persona|trend|premortem|mix`: provocation flavor; default `mix` (1-2 each, 4-6 total)
- `--depth=quick|medium|deep`: `quick` = open + react only; `medium` = drill 1-2 (default); `deep` = drill all
- `--lang=zh-TW|en`: override vault `_CLAUDE.md output-lang`
- `--research-window-days=N`: read Research/ window, default 30

## Phase 0: Pre-flight + resolve <repo>

- Confirm vault root has `_CLAUDE.md`. If no, abort with "Run /obsidian-init first."
- Parse the first whitespace-delimited token from `$ARGUMENTS` as the `<repo>` argument. Anything after is treated as flags.
- Resolve via shared helper:

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument. Usage: /obsidian-brainstorm <repo> [--topic=...] [--lens=...] [--depth=...]")
repo_token = tokens[0]
remaining_flags = tokens[1:]

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=False,   # brainstorm requires a real project
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state == "unknown" or resolution.state == "global":
    abort(resolution.message)  # 'global' is rejected for brainstorm
```

- Confirm `Projects/<project_slug>/` exists. If no, abort with "Run /obsidian-project <P> first."
- Ensure `Projects/<project_slug>/Brainstorms/` exists (mkdir if needed).
- Resolve `output_lang`:
  ```bash
  uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
  ```

## Phase 1: Vault scan (deterministic, no LLM)

Read the following files and build a `BrainstormContext` dict (see spec for the exact JSON shape):

1. `Projects/<P>/Architecture/overview.md`: extract `## 跨模組改進機會` block via `_extract_generated_block(text, "cross-cutting-improvements")`. Parse via `parse_improvements_block`. Lens-hint = `gap`.
2. `Projects/<P>/Architecture/features.md`: extract `## 改進機會` AND `## 可加 features` blocks. Lens-hint = `gap` (improvements) + `persona` (missing-features).
3. `Projects/<P>/Architecture/ai-flows/*.md` (each file): extract `## 改進機會` block.
4. `Projects/<P>/Architecture/personas.md`: read first 4 KB; extract each persona's `**主要痛點:**` bullets. Lens-hint = `persona`.
5. `Projects/<P>/Architecture/decisions.md`: extract `## 已知限制` block.
6. `Projects/<P>/Research/*.md`: files with `mtime` within `--research-window-days`. Per file: frontmatter `title` + first non-blank paragraph + `tags` + `date`. Lens-hint = `trend`.
7. `Projects/<P>/board.md`: `## 待辦` block titles (these are already in flight, avoid recommending them).
8. `Logs/YYYY-MM-DD.md` last 7 days: entries containing `[[<P>]]` wikilink (recent owner focus).
9. `Projects/<P>/Brainstorms/*.md` past sessions: `## 仍不清楚` + `## 暫不討論` blocks. **Count repeat parked titles**. If same title (fuzzy match) appears >=3 times across past sessions, flag `repeat_count: N` in context.

If any of the Architecture/* files is missing, log a warning (e.g. "no Architecture/personas.md: persona-lens provocations may be weaker") but continue.

## Phase 2: Opening provocations (LLM, single message)

Using `BrainstormContext` + `--lens` recipe + `--topic` seed (if provided), produce **4-6 provocations** in a single chat message. Each provocation MUST include:

- **Title** (<=30 chars)
- **為什麼 / Why** (1-2 sentences)
- **證據 / Evidence**: wikilink to vault file, OR `(speculation, no vault evidence)` literal when Lens = `premortem` and pure reasoning
- **Lens**: one of `gap` / `persona` / `trend` / `premortem`
- **Confidence**: one of `stated` (vault explicit) / `hypothesis` (vault + reasoning jump) / `speculation` (pure reasoning)

**Lens recipe defaults (`--lens=mix`):** 1-2 gap + 1-2 persona + 1-2 trend + 1 premortem, total 4-6. If Research/ is empty, replace trend with extra gap.

**Repeat-parked rule:** if `BrainstormContext.past_brainstorms` shows a topic with `repeat_count >= 3`, prepend `第 N 次出現` to that provocation's title and bring it up as one of the slots (signals owner "this keeps being deferred").

**Voice constraints:**
- **Bold**: speculate user-novel directions, not just restate existing Imps
- **No filler**: banned phrases: "這個值得思考", "我覺得很有趣", "可能不錯"
- **No invented wikilinks**: only cite vault files that actually exist (Phase 1 saw them)

Format the message with P1-P6 labels so the user can reference by number.

## Phase 3: User reaction (chat)

Wait for user response. Parse one of:

- `drill P2, P5`: mark P2 + P5 for deep dive (Phase 4)
- `kill P1`: record killed
- `park P3 P4`: record parked (will accumulate for future repeat detection)
- `P6 改成 X`: rewrite a provocation; treat the rewritten one as drilled
- `none`: user has no appetite; skip Phase 4, write a minimal note with all provocations recorded

Collect into `drilled[]`, `killed[]`, `parked[]`, `rewritten{}` lists for Phase 5 writeback.

## Phase 4: Drill (LLM, multi-turn)

For each drilled provocation, ask **2-4 follow-up questions, ONE AT A TIME** from the pool below (or improvise based on the conversation):

- "If this shipped, what would success look like in 1 month? 6 months?"
- "What's the riskiest assumption?"
- "Who do you steal time/budget from to do this?"
- "What's the smallest test that would disprove it?" (drives hypothesis output)
- "Who would push back? What's their valid concern?"
- "3 months out, customer hasn't reacted. Can you still hold?"
- "Conflicts with X on the board. How do you sequence?"

**Quote capture rule:** When the user answers, identify which sentence is a **verbatim quote** worth preserving (use `> ` in the writeup) and which content can be paraphrased.

Apply `--depth` rule:
- `quick`: skip Phase 4 entirely
- `medium` (default): drill 1-2 provocations (those the user marked)
- `deep`: drill all marked, take as long as needed

## Phase 5: Distill + write file (LLM)

For each drilled provocation, distill into:

- **0-2 ImprovementItems** for `distilled-imps` block (`為什麼 / 證據 / Effort / 未做的風險 / Confidence`)
- **0-2 hypotheses** for `hypotheses` block (`假設 / 驗證方式 / kill criterion / owner / status`)
- **Open questions** the user couldn't answer: `open-questions` block

Compose via `scripts.architect.sections.compose_brainstorm_note`. Slug for filename comes from session theme: ascii-lowercase-hyphen of the session's central topic (e.g. `vision-q3`, `customer-churn`, `embedding-alignment`).

Write to `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`.

Frontmatter `confidence` field is `high` when `provocations_drilled >= 2`, otherwise `medium`.

## Phase 6: Hub + activity log

- Idempotent update of `Projects/<P>/<P>.md` `## Brainstorms` block (create sentinel `<!-- @generated:start brainstorms-section -->` if absent). Content:
  ```markdown
  - 最近 session: [[Brainstorms/YYYY-MM-DD-<slug>]] (N imps + M hypotheses)
  - 全部 sessions: [[Brainstorms/]] folder
  - 新 session: `/obsidian-brainstorm <P>`
  - 餵 Roadmap: `/obsidian-roadmap <P>` (自動拾取 status!=actioned 的 brainstorms)
  ```
- Append to today's `Logs/YYYY-MM-DD.md ## Activity`:
  ```
  **HH:MM** - brainstorm | <P> - <slug> - N imps + M hypotheses drilled
  ```

If `Logs/YYYY-MM-DD.md` doesn't exist, create with the standard daily frontmatter (`type: daily`, `date: YYYY-MM-DD`, `ai-first: true`, `tags: [daily]`, `## 給未來 Claude`, `## Activity` headings).

---

**AI-first rule:** Every note created by this command MUST follow `references/ai-first-rules.md`: `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus the brainstorm-specific fields documented in the schema), recency markers per external claim, mandatory `[[wikilinks]]` for every persona/module/research note referenced, sources preserved verbatim, confidence levels mandatory.

**Language:** Respect `_CLAUDE.md`'s `- output-lang: zh-TW` line by default; honor `--lang=` flag as a single-run override. All prose in chosen language; code identifiers, paths, function names, env vars, and wikilink filename segments remain English regardless.
