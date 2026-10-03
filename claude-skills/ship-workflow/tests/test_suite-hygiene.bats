#!/usr/bin/env bats
# Guards on the test suite itself.
load helpers

@test "no [[ ]] assertion is silently ignored" {
  # In this bats/bash combination a failing `[[ ]]` that is NOT the final
  # command of its test does not fail the test — the ERR trap does not fire
  # for the `[[` keyword. `[ ]` and a final `[[ ]]` both behave correctly.
  #
  # Demonstrated: a deliberately impossible assertion passed, and an audit
  # found 72 of them across 14 files. They happened to all be true, so nothing
  # was hiding behind them — but the net had 72 holes in it.
  #
  # Fix is `|| return 1` on any non-final `[[ ]]`. This test keeps it that way.
  bad=$(python3 - "$SHIP_SKILL_ROOT/tests" <<'PY'
import re, sys, glob, os
hits=[]
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.bats'))):
    lines=open(f, encoding='utf-8').read().split('\n')
    start=None
    for i,l in enumerate(lines):
        if l.startswith('@test'): start=i
        if l.rstrip()=='}' and start is not None:
            body=range(start+1,i)
            idxs=[j for j in body if lines[j].strip() and not lines[j].strip().startswith('#')]
            last=idxs[-1] if idxs else -1
            for j in body:
                b=lines[j]
                if not re.match(r'\s*!?\s*\[\[ ', b): continue
                if j==last or b.rstrip().endswith('\\') or '||' in b: continue
                hits.append(f"{os.path.basename(f)}:{j+1}: {b.strip()[:60]}")
            start=None
print('\n'.join(hits))
PY
)
  if [ -n "$bad" ]; then
    echo "These [[ ]] assertions cannot fail — add '|| return 1':"
    echo "$bad"
    return 1
  fi
}
