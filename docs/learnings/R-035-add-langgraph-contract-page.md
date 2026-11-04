---
date: 2026-11-04
updated: 2026-11-04
type: learning
id: R-035
tags: [learning, ai_system, draw-arch, langgraph, state-contract, seams]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-035
shipped: true
shipped-date: 2026-11-04
---

## For future Claude
> R-035 added a `contract` page to `/draw-arch`: the internal seams of a LangGraph graph.
> Its nodes never import each other; they talk through the shared state. `lib/contract.py`
> resolves every `add_node` and every conditional-edge router through `ast`, then lists the
> state fields each one reads and writes. It follows state into same-repo helpers up to 3
> levels deep. Anything it cannot read becomes a named partial reason.
>
> **Headline lesson:** a static scan that only reads the node function itself is not a
> partial answer, it is a wrong one. The first scan of line-oa marked 16 of 19 nodes
> partial, and the findings lied: `query` showed up as "read, never written" because its
> writer works through a helper. Following helpers and scanning routers fixed the facts.
> After that, every remaining gap had to say what was unread, not `return Name`.

## What Shipped
- `lib/contract.py <repo> <spec>` scans the graph through `ast`.
  - Graph entries:
    - `add_node("x", fn)`, `action=`, `add_node(fn)` (named after the function), plus
      `line-<n>` for an `add_node` call whose name it cannot read;
    - conditional-edge routers as `kind: router`.
  - Resolution:
    - follows re-exports up to 5 hops, factories down to the inner def, and `async def`;
    - an import that resolves outside the repo leaves that name unresolved; it does not
      abort the scan.
  - Reads and writes:
    - reads `state["k"]` and `state.get("k")`;
    - writes the returned dict keys, keys of a returned dict variable, and `state["k"] = …`;
    - follows same-repo helpers that receive the state (bare names or `module.func`),
      including awaited returns, with a cycle guard.
  - Partial reasons: `return <expr>`, `return {**expr}`, `<var>.update(<expr>)`,
    `state passed to <callee>`, `state used in nested function <name>`, `state rebound`
    and `no state parameter`. A router's return is never a reason.
- `check.py`:
  - checks the contract schema (`kind`, `verdict`, scenario ids, duplicate ids);
  - reports `check: contract: stale` on fact changes only, never on a new HEAD.
- `render.py`, in order:
  - a node table with verdict tones and `（路由）` on routers;
  - field findings — 熱點欄位, 只讀沒人寫 (may be graph inputs), 只寫沒人讀 (may be graph
    outputs), 宣告了但沒用;
  - scenarios, whose 必須讀 / 必須寫 are derived from their nodes;
  - one section per node.
- The index order is overview, features, seams, contract, jobs.
- `test_draw-arch.bats` has 81 tests.
- The langlive-line-oa `lang_ai_customer` page has 19 nodes and 6 routers, with a verdict
  and note on each, and 4 scenarios:
  - `retrieve`/`rerank` have the cleanest seam;
  - `reply` reads 21 fields, including `channel_id` and `mode`;
  - `route_human_check` reads `line_loading_indicator_enabled`;
  - `first_session` writes 38 fields;
  - 6 nodes remain partial, each with a specific reason.

## Key Decisions
- The operator asked for 「langraph 內部模組之間的 seams」 after R-034. I checked that the
  nodes import nothing from each other, so the seam is the state contract. Proposal
  accepted: 「好」 (operator).
- The contract is per `add_node`, not per file (my call).
- Resolution goes through `ast` only (my call).
- The read and write rules are explicit, and partial reasons are honest (my call).
  The operator was told about this limit before saying 「好」.
- Declared fields come from the state class annotations (my call).
- The script supplies the facts; Claude writes verdicts, notes and scenarios (my call).
- A field is hot when 3 or more nodes read it (my call).
- Door: two-way.

## What Changed From Plan
- Codex ran Tasks 1–2 in one round, DONE_WITH_CONCERNS. It made one deviation I reverted:
  staleness compared `repo.commit` with HEAD, so any unrelated line-oa commit would have
  flagged the page. Fixed in 3be836c, with an "unrelated commit" test.
- Task 3 (Claude) found that the plan's analysis was too shallow for the real graph. I added
  helper-following, routers, and dropping return reasons for helpers whose result is not
  returned and for routers (b1f94e5, d6fa891). I also added finding hints and bare names for
  unused fields (4dbf7e3). The spec's Seams were updated with each change.
- Review attempt 1 found one spec blocker (`return <expr>` showed the AST class name) and
  8 important findings. All were reproduced in one regression test and fixed in bfe9849.
  Attempt 2 was clean.

## Bugs
- Node-only analysis produced false findings, because helpers held most state access.
- A helper's own non-dict return and a router's name return were reported as partial.
- A shadowed or rebound state name (comprehension, `for state in`, `s = dict(s)`) produced
  fields that do not exist.
- `**other` spreads, `out.update(call)` and closures dropped facts silently.
- `return await helper(state)` was not followed.
- An import resolving outside the repo aborted the whole scan.
- The `add_node(fn)` and `action=`/`path=` forms were dropped silently.

## Lessons → checks
- Report every case the scanner cannot read as a named partial reason, never a silent gap or a type name — enforced by `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats -f 'instead of pretending'` · proof: red at 4dbf7e3 (exit 1) · green at 7d05340
- Before trusting a static analysis, run it on the real target and look at how much it marks incomplete; a high partial rate means the model of the code is wrong, not that the code is unusual — judgment

## Reusable Patterns
- **In a LangGraph app, the seam is the state contract.** Per-node reads and writes, plus
  hot, read-only, write-only and unused fields, answer "can I swap this node?" better than
  an import graph.
- **Derive a scenario's interface.** Must-read is the union of its nodes' reads minus their
  writes; must-write is the union of their writes.
- **Compare facts in the stale check, not commits.** Otherwise every unrelated commit raises
  an alarm.

## Technical Debt
- Review nits not taken:
  - a nested-function false positive and duplicate (no line-oa impact);
  - `except … as state` and `match` captures are not treated as a rebind;
  - a sibling `pkg.py` is preferred over `pkg/__init__.py` for `from . import f`;
  - a resolvable helper at depth 3 still yields `state passed to`;
  - `f(*xs, state)` maps the state by its raw index;
  - colliding computed ids;
  - several tests pin CSS or bundle many asserts;
  - an unknown scenario node gives a bare error in render;
  - the relative-import parent walk is duplicated.
- The line-oa partials left: `extract_memory` (imported inside a function), `post_process`,
  `reset_state` returns, and `continuity.reset_after_topic_switch` merged through `.update`.

## Future Follow-ups
- In line-oa:
  - move the loading indicator out of `route_human_check`;
  - the platform reads in `reply`;
  - confirm what `post_process` writes before replacing FAQ generation.
- Optional: one contract page per StateGraph (the `load_lang_ai_customer_data` graph).
