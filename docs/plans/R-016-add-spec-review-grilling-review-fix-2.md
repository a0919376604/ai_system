# R-016 review fix 2

Blocking (spec review, attempt 1): `code-review-parse.sh` drops only the first line of an
indented `Spec:` quote; continuation lines of a multi-line quote (which
`sn_spec_review_check` accepts) still reach the unanchored counters, so a quote holding
`**Severity:** blocking` adds a phantom blocker no fix can clear.

- [ ] Test: a multi-line `Spec:` quote holding `[ponytail:delete]` and `**Severity:** blocking`
      adds to no counter; the next finding still counts.
- [ ] Fix: drop the `Spec:` line and the indented lines that continue it (reset per file).
- [ ] Nit: the prompt's 🟡 [important] form keeps the `[spec:extra] [ponytail:yagni]` tags.
