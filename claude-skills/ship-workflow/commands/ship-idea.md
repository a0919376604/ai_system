---
name: ship-idea
description: Capture a product idea as IDEA-NNN with AIR-OS frontmatter (fast mobile-friendly capture)
argument-hint: "<description> [--during-build --severity <level> --source <hint> --related-roadmap-item <R-NNN>]"
discord-visible: true
---

# /ship-idea

You are capturing a new idea into `docs/ideas/IDEA-NNN-<slug>.md`.

## Arguments

- **`<description>`** (required) — one-line natural description (Claude generates the slug from it)

### Optional flags (used by /ship-next --auto:yes; not normally typed by hand)

- `--during-build` — non-interactive capture mode. Skips the interactive fill-in (existing step 6). Combine with the 3 flags below to provide context.
- `--severity <level>` — `major | minor | nit`. Stored in frontmatter `severity:`. Used when the idea is captured from a code-review finding that was deferred to follow-up.
- `--source <hint>` — short string like `code-review-skill auto-run during R-001.3`. Stored in frontmatter `source:`.
- `--related-roadmap-item <R-NNN>` — explicit cross-link to the R-NNN this idea was discovered while shipping. Stored in frontmatter `related-roadmap-item:`.

## Steps

1. **Sync product brain** (cheap if fresh):
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Allocate ID:**
   ```bash
   ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh idea)
   ```

3. **Generate slug.** Take `<description>`, lowercase, kebab-case, strip stopwords, cap 6 words. Example: "Multimodal feedback loop for support agents" → `multimodal-feedback-loop-agents`.

4. **(Optional, on user request)** Invoke `compound-engineering:ce-ideate` with `<description>` to deepen the Problem / Evidence / Impact sections before writing the file.

5. **Render template.** Read `~/.claude/skills/ship-workflow/templates/repo/IDEA.md` and substitute `{{date}}` (today), `{{id}}` ($ID), `{{project}}` ($(./lib/airos-binding.sh project_name)). Write the result to `docs/ideas/${ID}-${slug}.md`.

6. **Fill the For future Claude preamble + Summary + Problem.** Two paths:

   - **Interactive mode (default)**: Use `<description>` and any extra context the user provided. Leave Target User / Evidence / Impact / Confidence / Dependencies / Risks / Possible Roadmap Item as section headers with `_to-fill_` placeholders only if the user is explicit that they want a quick capture; otherwise drive a short interactive fill-in.

   - **`--during-build` mode**: Skip interactive fill entirely. Write only the `<description>` into Summary + Problem. Other sections stay as `_to-fill_` placeholders. Add three extra frontmatter keys at the top (after existing keys, before the closing `---`):
     ```yaml
     severity: <severity-arg-value>           # major | minor | nit
     source: <source-arg-value>               # free-form
     related-roadmap-item: <R-NNN-arg-value>  # cross-link to parent
     ```
     These are emitted only when the corresponding flag was provided. Missing flag → omit the key entirely (do not write `null`).

7. **Append log line:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-idea | $ID | $description | n |" >> docs/learnings/_log.md
   ```

8. **Commit:**
   ```bash
   git add docs/ideas/${ID}-${slug}.md docs/learnings/_log.md
   git commit -m "idea: $ID $description"
   ```

9. **Report:** Tell the user the ID + file path + 1-line summary, and offer "Want to graduate this into a Roadmap item via /ship-roadmap?" if confidence is medium+ or impact is high.

## Failure modes

- Global config missing → run `/ship-init` first
- `docs/ideas/` doesn't exist → run `/ship-init` first
