#!/usr/bin/env bash
# ship-workflow/lib/learnings-lookup.sh
# Find the past learnings relevant to the feature being brainstormed.
#
# Why grep and not an index: measured on a 67-file corpus, reading every
# learning costs ~213k tokens, while a grep that returns only filenames costs
# ~31 — cheaper than CONTEXT.md's own ~892. An index file would be a fourth
# thing to keep in sync and would go stale silently; grep cannot.
#
# The caller decides what to do with the hits, because the right answer
# depends on how many there are. Measured on the same corpus: `solve_rate`
# matches 2 files, `bucket` matches 32. Opening 32 learnings costs ~100k
# tokens and buries the signal, so Phase 3 caps it and falls back to titles.
#
# Silent no-op when the repo keeps no learnings.

# learnings_match <term>... — learnings whose FILENAME contains any term.
#
# Filenames, not bodies. Measured on the real 67-file corpus: body grep for
# the slug words of `unify-ai-resolve-rate` returned 48 of 67 files, because
# words like "resolve" and "rate" appear in almost every 147-line narrative.
# The same terms against filenames return 4. Across five real slugs body grep
# gave 19-48 hits and filenames gave 2-13.
#
# Known gap: a learning whose slug shares no words with yours never surfaces,
# even when it is the relevant one — R-190.1-reverted-wrong-direction will not
# appear for a solve-rate change. Closing that needs `tags:` frontmatter on
# all 67 files; not worth the backfill until filename matching proves too
# narrow in practice.
learnings_match() {
  local dir="docs/learnings" t
  [ -d "$dir" ] || return 0
  [ $# -gt 0 ] || return 0
  for t in "$@"; do
    [ -n "$t" ] || continue
    # -F: literal. --: a term starting with `-` must not become an option;
    # this repo has already lost time to grep reading a term as a flag.
    ls -1 "$dir" 2>/dev/null | grep -F -- "$t" || true
  done | grep -v '^_log\.md$' | sort -u | sed "s|^|$dir/|"
}

# learnings_grep_body <term>... — body search, for identifier-like terms only.
# `solve_rate` matches 2 files where the word "rate" matches 48: an underscore
# or a dot means the term is a real symbol rather than English prose.
learnings_grep_body() {
  local dir="docs/learnings" t
  [ -d "$dir" ] || return 0
  for t in "$@"; do
    case "$t" in
      *_*|*.*) : ;;
      *) continue ;;
    esac
    grep -rlF -- "$t" "$dir" 2>/dev/null || true
  done | grep -v '/_log\.md$' | sort -u
}

# No learnings_title: measured on the real corpus, only 12 of 67 files have an
# H1 after the frontmatter (most open with `## For future Claude`) and none has
# a `title:` field. A title helper that works for 12 files is worse than none —
# the filename carries the slug (R-068-unify-ai-resolve-rate.md) and is the one
# label every file has. Callers print the path.
