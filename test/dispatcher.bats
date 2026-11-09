#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# A failing [[ ]] on a non-final line doesn't fail a test on bash 3.2.
has() { case "$1" in *"$2"*) return 0 ;; esac; printf 'missing: %s\nin: %s\n' "$2" "$1"; return 1; }
lacks() { case "$1" in *"$2"*) printf 'unexpected: %s\nin: %s\n' "$2" "$1"; return 1 ;; esac; }

@test "version prints name and a version" {
  run "$WH" --version
  [ "$status" -eq 0 ]
  [[ "$output" == worktree-harness\ * ]]
}

@test "help lists the core commands" {
  run "$WH" help
  [ "$status" -eq 0 ]
  has "$output" "new"
  has "$output" "merge"
  has "$output" "gc"
  has "$output" "launch"
}

@test "unknown command exits 64" {
  run "$WH" definitely-not-a-command
  [ "$status" -eq 64 ]
  has "$output" "Unknown command definitely-not-a-command"
}

@test "unknown option uses the guide's wording" {
  run "$WH" --bogus-flag status
  [ "$status" -ne 0 ]
  has "$output" "Unknown option --bogus-flag for worktree-harness."
  has "$output" "See all options:"
}

@test "help prints to stdout" {
  run --separate-stderr "$WH" --help
  [ "$status" -eq 0 ]
  has "$output" "Usage:"
  [ -z "$stderr" ]
}

@test "a bare run prints help on stdout and exits 0" {
  run --separate-stderr "$WH"
  [ "$status" -eq 0 ]
  has "$output" "(default)"
  [ -z "$stderr" ]
}

@test "help <cmd> routes to that command's help" {
  run --separate-stderr "$WH" help new
  [ "$status" -eq 0 ]
  has "$output" "worktree-harness new <BRANCH>"
}

@test "help help and help version print help, not the version alone" {
  run --separate-stderr "$WH" help help
  [ "$status" -eq 0 ]
  has "$output" "Global Options:"
  run --separate-stderr "$WH" help version
  [ "$status" -eq 0 ]
  has "$output" "Usage:"
  has "$output" "worktree-harness version"
}

@test "help <unknown> takes the unknown-command path" {
  run "$WH" help nope
  [ "$status" -eq 64 ]
  has "$output" "Unknown command nope for worktree-harness."
}

# help's other forms (--all, --json, search) are lib/help_meta.sh's; test/help.bats covers them.

@test "root help works without lib/" {
  mkdir "$BATS_TEST_TMPDIR/b"
  cp "$WH" "$BATS_TEST_TMPDIR/b/worktree-harness"
  run "$BATS_TEST_TMPDIR/b/worktree-harness" --help
  [ "$status" -eq 0 ]
  has "$output" "Usage:"
  run "$BATS_TEST_TMPDIR/b/worktree-harness" help
  [ "$status" -eq 0 ]
  has "$output" "Usage:"
}

@test "root help fits 80 columns" {
  run bash -c '"$1" --help | LC_ALL=C awk "length>80"' _ "$WH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "root help follows the help layout" {
  run --separate-stderr "$WH" --help
  [ "$status" -eq 0 ]
  has "$output" "Usage:"
  has "$output" "Global Options:"
  has "$output" "Learn more: https://github.com/renchris/worktree-harness"
  has "$output" "--cwd <DIR>"
  has "$output" "64 unknown command"
  lacks "$output" "GLOBAL FLAGS"
  lacks "$output" "command-specific"
  lacks "$output" "-C "
  lacks "$output" "-V"
  lacks "$output" "--human"
  lacks "$output" "--force"
  lacks "$output" "    create"
  lacks "$output" "    run"
  lacks "$output" "    land"
  lacks "$output" "    prune"
  lacks "$output" "    ls"
  lacks "$output" "    list"
}

@test "-C without a directory is a usage error" {
  run "$WH" -C
  [ "$status" -eq 1 ]
  has "$output" "-C needs a directory"
  has "$output" "See all options:"
}

@test "--cwd without a value is a usage error" {
  run "$WH" --cwd
  [ "$status" -eq 1 ]
  has "$output" "Option --cwd needs a value."
  run "$WH" --cwd=
  [ "$status" -eq 1 ]
  has "$output" "Option --cwd needs a value."
}

@test "a directory that can't be entered is an error" {
  run "$WH" --cwd "$BATS_TEST_TMPDIR/absent" status
  [ "$status" -eq 1 ]
  has "$output" "Can't change to directory"
}

@test "unknown command prints one line, not the full usage" {
  run "$WH" nope
  [ "$status" -eq 64 ]
  has "$output" "See all options:"
  lacks "$output" "Commands:"
}

@test "unknown command suggests a close match and only a close match" {
  run "$WH" stat
  [ "$status" -eq 64 ]
  has "$output" "Unknown command stat for worktree-harness. Did you mean status?"
  run "$WH" mrege
  has "$output" "Did you mean merge?"
  run "$WH" docter
  has "$output" "Did you mean doctor?"
  run "$WH" definitely-not-a-command
  has "$output" "Unknown command"
  lacks "$output" "Did you mean"
}

@test "deprecated aliases warn; ls does not" {
  make_repo
  run "$WH" create x --dry-run
  [ "$status" -eq 0 ]
  has "$output" "deprecated"
  run "$WH" ls
  [ "$status" -eq 0 ]
  lacks "$output" "deprecated"
  run "$WH" list
  [ "$status" -eq 0 ]
  lacks "$output" "deprecated"
}

@test "a deprecated alias warns exactly once, on stderr" {
  make_repo
  run --separate-stderr "$WH" create x --dry-run
  [ "$status" -eq 0 ]
  lacks "$output" "deprecated"
  [ "$(printf '%s\n' "$stderr" | grep -c deprecated)" -eq 1 ]
}

@test "land and prune warn even before their commands parse options" {
  make_repo
  run "$WH" prune
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c deprecated)" -eq 1 ]
  has "$output" "This only previews; pass 'gc --prune' to remove."
  run "$WH" land --help
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c deprecated)" -eq 1 ]
}

@test "-v prints the same as --version" {
  [ "$("$WH" -v)" = "$("$WH" --version)" ]
  run "$WH" -v
  [ "$status" -eq 0 ]
}

@test "-V and -C stay accepted and silent" {
  make_repo
  run --separate-stderr "$WH" -V
  [ "$status" -eq 0 ]
  [ "$output" = "$("$WH" --version)" ]
  [ -z "$stderr" ]
  cd /
  run --separate-stderr "$WH" -C "$APP" status
  [ "$status" -eq 0 ]
  lacks "$stderr" "deprecated"
  run "$WH" "-C=$APP" status
  [ "$status" -eq 0 ]
}

@test "--cwd works before and after the command" {
  make_repo
  cd /
  run "$WH" --cwd "$APP" status
  [ "$status" -eq 0 ]
  run "$WH" "--cwd=$APP" status
  [ "$status" -eq 0 ]
  run --separate-stderr "$WH" new x --dry-run --cwd "$APP"
  [ "$status" -eq 0 ]
}

@test "global booleans parse =true and =false" {
  make_repo
  run "$WH" --dry-run=false status
  [ "$status" -eq 0 ]
  run "$WH" --dry-run=maybe status
  [ "$status" -ne 0 ]
  has "$output" "takes true or false"

  run --separate-stderr "$WH" --dry-run=true new a
  [ "$status" -eq 0 ]
  run git rev-parse --verify -q refs/heads/a
  [ "$status" -ne 0 ]

  run --separate-stderr "$WH" --dry-run --dry-run=false new b
  [ "$status" -eq 0 ]
  git rev-parse --verify -q refs/heads/b

  run --separate-stderr "$WH" --dry-run --no-dry-run new c
  [ "$status" -eq 0 ]
  git rev-parse --verify -q refs/heads/c
}

@test "--color undoes --no-color, and =true and =false set it" {
  FORCE_COLOR=1 run "$WH" --no-color --color definitely-not-a-command
  has "$output" $'\033['
  FORCE_COLOR=1 run "$WH" --no-color=false definitely-not-a-command
  has "$output" $'\033['
  FORCE_COLOR=1 run "$WH" --no-color=true definitely-not-a-command
  has "$output" "Unknown command"
  lacks "$output" $'\033'
}

@test "__WH_PARSE_ONLY stops a run with no command before printing help" {
  __WH_PARSE_ONLY=1 run --separate-stderr "$WH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  __WH_PARSE_ONLY=1 run --separate-stderr "$WH" --dry-run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every version --help example parses" {
  run --separate-stderr "$WH" version --help
  [ "$status" -eq 0 ]
  has "$output" "Usage:"
  assert_help_examples_parse version
}
