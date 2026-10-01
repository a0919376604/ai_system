#!/usr/bin/env bats
# ua-integration.sh is sourced by command files that Claude executes, and the
# operator's shell is zsh. `local x` on an already-local variable PRINTS it in zsh
# and is silent in bash, so a bash-clean function can emit `summary=$'...'` garbage
# into a report under zsh. Every public helper must produce identical output in both.
load helpers

setup() {
  export SCRATCH="$(make_scratch ua-zsh)"
  mkdir -p "$SCRATCH/repo/src"
  cd "$SCRATCH/repo"
  git init -q .
  git config user.email t@t
  git config user.name t
  printf 'def f():\n    return 1\n' > src/a.py
  git add -A
  git commit -q -m base
  make_fake_ua_kg "$SCRATCH/repo" "$(git rev-parse HEAD)"
  export HOME="$SCRATCH/home"
  make_fake_ua_plugin_cache "$SCRATCH"
  mkdir -p docs/specs
  printf -- '---\ntarget-files:\n  - foo.py\n  - bar.py\n---\n' > docs/specs/R-001-demo.md
}

teardown() { rm -rf "$SCRATCH"; }

@test "zsh: ua_get_pre_brainstorm_context emits no 'summary=' debris" {
  command -v zsh >/dev/null || skip "zsh not installed"
  out=$(zsh -c "source '$SHIP_LIB/ua-integration.sh'; ua_get_pre_brainstorm_context R-001" 2>&1)
  if echo "$out" | grep -q "summary="; then
    echo "zsh leaked a local declaration into the output:"
    echo "$out" | grep "summary=" | head -3
    return 1
  fi
}

@test "bash and zsh produce identical pre-brainstorm context" {
  command -v zsh >/dev/null || skip "zsh not installed"
  b=$(bash -c "source '$SHIP_LIB/ua-integration.sh'; ua_get_pre_brainstorm_context R-001" 2>&1)
  z=$(zsh  -c "source '$SHIP_LIB/ua-integration.sh'; ua_get_pre_brainstorm_context R-001" 2>&1)
  [ "$b" = "$z" ]
}

@test "no helper declares a local inside a loop body" {
  # The root cause, pinned structurally: a `local` re-declared on each iteration is
  # what zsh echoes. Declare locals once at function top instead.
  awk '
    /^[a-z_]+\(\)/            { fn=$1; depth=0 }
    /(^|[[:space:];])(while|for)[[:space:]].*[[:space:];]do[[:space:]]*$/ { if (fn) depth++ }
    /^[[:space:]]*done/       { if (fn && depth>0) depth-- }
    /^[[:space:]]*local /     { if (fn && depth>0) print FILENAME": "FNR": "$0 }
  ' "$SHIP_LIB/ua-integration.sh" > /tmp/ua-loop-locals.txt
  if [ -s /tmp/ua-loop-locals.txt ]; then
    cat /tmp/ua-loop-locals.txt
    return 1
  fi
}
