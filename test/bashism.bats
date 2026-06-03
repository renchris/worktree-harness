#!/usr/bin/env bats
load helper

# The tool must run on stock macOS /bin/bash (3.2). shellcheck has no "bash 3.2"
# dialect, so this guard greps the bash sources for 4.0+-only constructs.
@test "bash sources avoid bash 4+ only constructs" {
  result="$(find_bashisms)"
  [ -z "$result" ]
}

@test "every script passes bash -n (parse check) under bash" {
  run bash -c '
    set -e
    for f in "'"$WH_ROOT"'"/bin/worktree-harness "'"$WH_ROOT"'"/lib/*.sh "'"$WH_ROOT"'"/share/shell/bash.sh; do
      bash -n "$f"
    done'
  [ "$status" -eq 0 ]
}
