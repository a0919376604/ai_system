#!/usr/bin/env bats
# R-017 lesson (promotes R-004's judgment rule): a command block that ends with
# `[ … ] && cmd` exits 1 whenever the test is false, so the block reports failure
# on its normal path. End a block with an if-block, or add `|| true`.
load helpers

@test "no command-file bash block ends with a bare test && list" {
  bad=$(awk '
    /^[[:space:]]*```bash[[:space:]]*$/ { inb=1; last=""; next }
    inb && /^[[:space:]]*```[[:space:]]*$/ {
      inb=0
      if (last ~ /^[[:space:]]*(\[|\(\(|test )/ && last ~ /&&/ && last !~ /\|\|/)
        print FILENAME ":" lastn ": " last
      next
    }
    inb && $0 !~ /^[[:space:]]*(#|$)/ { last=$0; lastn=FNR }
  ' "$SHIP_SKILL_ROOT"/commands/*.md)
  [ -z "$bad" ] || { echo "end these blocks with an if-block instead:"; echo "$bad"; return 1; }
}
