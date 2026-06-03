#!/usr/bin/env bats
load helper

# The tool must run on stock macOS /bin/bash (3.2). shellcheck has no "bash 3.2"
# dialect, so this guard greps the bash sources for 4.0+-only constructs.
@test "bash sources avoid bash 4+ only constructs" {
  result="$(find_bashisms)"
  [ -z "$result" ]
}

@test "completion scripts parse" {
  run bash -n "$WH_ROOT/share/completions/worktree-harness.bash"
  [ "$status" -eq 0 ]
  if command -v zsh >/dev/null 2>&1; then
    run zsh -n "$WH_ROOT/share/completions/_worktree-harness"
    [ "$status" -eq 0 ]
  fi
  if command -v fish >/dev/null 2>&1; then
    run fish --no-execute "$WH_ROOT/share/completions/worktree-harness.fish"
    [ "$status" -eq 0 ]
  fi
}

@test "every script passes bash -n (parse check) under bash" {
  run bash -c '
    set -e
    for f in "'"$WH_ROOT"'"/bin/worktree-harness "'"$WH_ROOT"'"/lib/*.sh "'"$WH_ROOT"'"/share/shell/bash.sh; do
      bash -n "$f"
    done'
  [ "$status" -eq 0 ]
}
