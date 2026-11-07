#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

@test "launch --dry-run on the main checkout exits 0 and creates nothing" {
  make_repo
  run "$WH" launch --dry-run -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"would exec: true"* ]]
  [[ "$output" != *"isolated session"* ]]
  [ -z "$(ls "$WT_HOME/app" 2>/dev/null)" ]
  [ -z "$(git -C "$APP" branch --list 'wt-*')" ]
}

@test "launch still runs outside a repo" {
  make_norepo
  run "$WH" launch -- sh -c 'printf "ran in %s" "$PWD"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran in "*"/norepo"* ]]
}

@test "a failed isolation prints one error and doesn't launch" {
  make_repo
  printf 'HARNESS_SETUP=("false")\n' >> .harnessrc
  run --separate-stderr "$WH" launch -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | grep -c '^Error:')" -eq 1 ]
  [[ "$stderr" == *"Refusing to launch un-isolated"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "a failed git worktree add still refuses to launch un-isolated" {
  make_repo
  git update-ref -d refs/remotes/origin/main
  WH_NO_FETCH=1 run --separate-stderr "$WH" launch -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | grep -c '^Error:')" -eq 1 ]
  [[ "$stderr" == *"Refusing to launch un-isolated"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "launch isolates on the main checkout and runs the command in the new worktree" {
  make_repo
  run --separate-stderr "$WH" launch -- sh -c 'pwd -P; git rev-parse --abbrev-ref HEAD'
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"/wt/app/"* ]]
  [ "${lines[1]}" != "main" ]
}

@test "launch passes the child's exit code through" {
  make_repo
  "$WH" new feat
  cd "$WT_HOME/app/feat"
  run "$WH" launch -- sh -c 'exit 42'
  [ "$status" -eq 42 ]
}

@test "launch passes argv with spaces and metacharacters unchanged" {
  make_repo
  "$WH" new feat
  cd "$WT_HOME/app/feat"
  # shellcheck disable=SC2016
  run --separate-stderr "$WH" launch -- printf '%s|' 'a b' '$HOME' '*'
  [ "$status" -eq 0 ]
  [ "$output" = 'a b|$HOME|*|' ]
}

@test "launch leaves options after the command to that command" {
  make_repo
  "$WH" new feat
  cd "$WT_HOME/app/feat"
  run --separate-stderr "$WH" launch printf '%s|' --help --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = '--help|--dry-run|' ]
}

@test "glob characters in HARNESS_AGENT don't expand against the cwd" {
  make_repo
  "$WH" new feat
  cd "$WT_HOME/app/feat"
  printf 'HARNESS_AGENT="printf %%s| *"\n' >> .harnessrc
  run --separate-stderr "$WH" launch
  [ "$status" -eq 0 ]
  [ "$output" = '*|' ]
}
