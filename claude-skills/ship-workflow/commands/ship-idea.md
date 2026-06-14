---
name: ship-idea
description: Capture a new product idea as IDEA-NNN with AIR-OS-conformant frontmatter. Optionally delegates depth-of-thought to compound-engineering:ce-ideate. Use when an idea worth recording arises during conversation, slack scroll, user feedback, or competitor scan.
---

# /ship-idea

You are capturing a new idea into `docs/ideas/IDEA-NNN-<slug>.md`.

## Argument

`<description>` — one-line natural description (Claude generates the slug from it)

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

6. **Fill the For future Claude preamble + Summary + Problem.** Use `<description>` and any extra context the user provided. Leave Target User / Evidence / Impact / Confidence / Dependencies / Risks / Possible Roadmap Item as section headers with `_to-fill_` placeholders only if the user is explicit that they want a quick capture; otherwise drive a short interactive fill-in.

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
