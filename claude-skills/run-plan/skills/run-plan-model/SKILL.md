---
name: run-plan-model
description: Use when the user wants to view, set, or reset the global model used by run-plan independently of the outer conversation model.
argument-hint: "[model]"
discord-visible: true
---

# /run-plan-model

Manage the model for future `/run-plan` executions across projects. This is
an alias for `/run-plan model`; it does not launch a plan.

| Input | Action |
|---|---|
| `/run-plan-model` | Show the current override, or inherit if unset |
| `/run-plan-model sol` | Set `gpt-6.1-sol` |
| `/run-plan-model astra` | Set `gpt-6-astra` |
| `/run-plan-model <MODEL_ID>` | Set an exact model ID |
| `/run-plan-model reset` | Resume inheriting Codex configuration |

Run `bash ~/.claude/skills/run-plan/scripts/model.sh` with no argument to
query, or pass the user's one model/reset argument as a safely quoted argv
element. If that installation path is absent, resolve `../../scripts/model.sh`
relative to this skill's actual directory (follow symlinks). Do not execute
argument text as shell code or silently discard extra arguments.

The helper stores `${XDG_CONFIG_HOME:-$HOME/.config}/run-plan/model` atomically.
It leaves Codex configuration and reasoning effort unchanged. Settings apply
only to newly launched runs; existing runs retain their model. `sol` and
`astra` are shortcuts; other inputs must be exact model IDs. Validation checks
syntax only; Codex checks account availability when a plan actually runs.

Report the helper result. On failure, surface the error without editing
Codex config or starting a plan. No argument is a query, not an interactive
model picker. Do not run an inference call merely to test a setting.
