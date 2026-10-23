---
date: 2026-10-23
type: brainstorm
id: R-003
status: complete
spec: docs/specs/R-003-add-security-review-gate.md
---

# R-003 brainstorm — a separate security gate in ship-next Phase 6, plus Pre-existing findings

## Trigger
The operator read Anthropic's "Solving code review at Anthropic" (2026-10-15,
https://claude.dev/blog/solving-code-review-at-anthropic/). In it, a security review is
**a separate pass**, next to the bug-hunting code review, and open findings from
either one block the merge. The post also introduces a **Pre-existing** finding tag.

## What the operator said
- First worry: "合了會不會系統 crash". That is deploy and runtime safety. The built-in
  `/security-review` explicitly excludes it (DoS, resource exhaustion, races).
  **Recorded as a separate future topic, not this item.**
- Then: "還是幫我加 security review 吧，我也怕被注入". Asked which kind of injection,
  the answer was **LINE users manipulating the AI bot** (prompt injection).

## Key fact that shaped the design
The upstream `/security-review` prompt (anthropics/claude-code-security-review, MIT,
commit 0c6a49f1fa56) hard-excludes the exact worry: exclusion 14, *"Including
user-controlled content in AI system prompts is not a vulnerability."* It also
diffs against `origin/HEAD` and emits `* Severity: High`, which ship-next's parser
cannot read. So the built-in command cannot be used as-is.

## Recon: langlive-line-oa (origin/main f25750e2, 2026-10-23), ranked
1. **Stored injection through the auto-published KB.** The hourly `qa_to_kb_sweeper`
   turns closed chats into QA. Candidates the LLM validator passes are uploaded
   (`question_center_kb.py:2337`) and synced into Weaviate, which every FAQ answer
   reads. One user's text can become content every other user sees.
   **Pre-existing; separate langlive item.**
2. LINE text is concatenated into one flat prompt (`prompts/lang_ai_customer.py:247`)
   with no role separation. Users can also type the internal markers
   (`[系統提醒]`, `[客服上一輪回覆]`).
3. LLM text goes to LINE with no output filter and no URL allowlist.
4. Form pre-fill can leak agent-written `profile_notes` to the same user
   (`process.py:476`).
5. LLM output drives handoff and form routing, which a user could use to flood the
   human queue.
6. The customer bot has no tools; refund and payment replies are fixed text. Ask AI
   is admin-only and read-only.

## Decisions
| # | Decision | Whose |
|---|---|---|
| 1 | Add the security gate, aimed at injection including prompt injection | operator |
| 2 | Crash / deploy-risk review is a non-goal here | operator |
| 3 | Vendor the upstream prompt (MIT) with changes, instead of calling the built-in command | Claude's call |
| 4 | The AI-input section is always on, conditioned inside the prompt on the diff touching prompt-building or LLM-output code. No per-repo flag. | Claude's call (changed from the per-repo switch shown in chat; simpler, and costs nothing in repos without LLM code) |
| 5 | Repo-specific notes come from an optional `docs/SECURITY_REVIEW.md` | Claude's call |
| 6 | HIGH → blocking, MEDIUM → important, LOW → nit. `[pre-existing]` never blocks and becomes a follow-up. | operator agreed to the playback |
| 7 | langlive's KB-poisoning fix and its `docs/SECURITY_REVIEW.md` are separate langlive work | operator agreed |
| 8 | The review's own config (`security_review: off`, `docs/SECURITY_REVIEW.md`) is read from `${ORIG_BRANCH}`, never from the branch under review | Claude's call, from the builder check (a ship must not be able to relax its own review) |
| 9 | The security pass never fails open: render failure halts; malformed output re-runs once, then halts | Claude's call, from the builder check |
| 10 | Pre-existing follow-ups are deduped across ships by a `pre-existing-key:` line in the IDEA | Claude's call, from the builder check |
| 11 | Only the new Phase 6 blocks guard `ORIG_BRANCH`; persisting it for older blocks is a follow-up | Claude's call, from the builder check |
