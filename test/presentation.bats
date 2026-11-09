#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# Presentation: the CLI never reads the terminal width, colour follows
# --no-color > NO_COLOR > FORCE_COLOR and the TTY, and machine output
# (--porcelain, --json, new's stdout path) is never styled.

ESC="$(printf '\033')"

# strip_ansi — stdin without SGR sequences.
strip_ansi() { sed "s/${ESC}\[[0-9;]*m//g"; }

# no_esc <label> <text> — fail when <text> holds an escape byte.
no_esc() {
  case "$2" in *"$ESC"*) printf '%s carries ESC:\n%s\n' "$1" "$2" | cat -v; return 1 ;; esac
}

# capture <env...> -- <args...> — stdout and stderr of one run, merged.
capture() {
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -u FORCE_COLOR -u NO_COLOR -u WH_NO_COLOR ${envs[@]+"${envs[@]}"} "$WH" "$@" 2>&1 </dev/null || true
}

# The cases from the plan: help, status, gc's preview and new's dry run.
CASES=("--help" "status --help" "status" "gc" "new feat-x --dry-run")

@test "output doesn't change with COLUMNS and keeps paths whole" {
  make_repo
  local args narrow mid wide
  for args in "${CASES[@]}"; do
    # shellcheck disable=SC2086
    narrow="$(capture COLUMNS=40 -- $args)"
    # shellcheck disable=SC2086
    mid="$(capture COLUMNS=80 -- $args)"
    # shellcheck disable=SC2086
    wide="$(capture COLUMNS=120 -- $args)"
    [ "$narrow" = "$mid" ] || { printf '%s differs at 40 and 80:\n%s\n---\n%s\n' "$args" "$narrow" "$mid"; false; }
    [ "$mid" = "$wide" ] || { printf '%s differs at 80 and 120:\n%s\n---\n%s\n' "$args" "$mid" "$wide"; false; }
    if printf '%s\n' "$narrow" | grep "$BATS_TEST_TMPDIR" | grep -q '…'; then
      echo "$args shortens a path: $narrow"; false
    fi
  done
  narrow="$(capture COLUMNS=40 -- status)"
  case "$narrow" in *"$APP"*|*"/private$APP"*) ;; *) echo "status lost the path: $narrow"; false ;; esac
}

@test "FORCE_COLOR output, stripped, equals NO_COLOR output" {
  make_repo
  local args forced plain
  for args in "${CASES[@]}"; do
    # shellcheck disable=SC2086
    forced="$(capture FORCE_COLOR=1 -- $args | strip_ansi)"
    # shellcheck disable=SC2086
    plain="$(capture NO_COLOR=1 -- $args)"
    [ "$forced" = "$plain" ] || { printf '%s:\n%s\n---\n%s\n' "$args" "$forced" "$plain"; false; }
    no_esc "$args under NO_COLOR" "$plain"
  done
}

@test "--no-color beats FORCE_COLOR" {
  make_repo
  local args
  for args in "${CASES[@]}"; do
    # shellcheck disable=SC2086
    no_esc "--no-color $args" "$(capture FORCE_COLOR=1 -- --no-color $args)"
  done
}

@test "TERM=dumb on a terminal emits no ESC" {
  command -v script >/dev/null 2>&1 || skip "script isn't installed"
  make_repo
  local args out
  for args in "${CASES[@]}"; do
    if script -q /dev/null true </dev/null >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      out="$(env -u FORCE_COLOR -u NO_COLOR TERM=dumb script -q /dev/null "$WH" $args </dev/null 2>&1)" || true
    else
      out="$(env -u FORCE_COLOR -u NO_COLOR TERM=dumb script -qec "\"$WH\" $args" /dev/null </dev/null 2>&1)" || true
    fi
    case "$out" in *Usage:*|*worktree*|*feat-x*) ;; *) skip "script gave no output here: $out" ;; esac
    no_esc "TERM=dumb $args" "$out"
  done
}

@test "machine output stays unstyled under FORCE_COLOR" {
  make_repo
  run --separate-stderr env FORCE_COLOR=1 "$WH" status --porcelain
  [ "$status" -eq 0 ]
  no_esc "status --porcelain" "$output"
  run --separate-stderr env FORCE_COLOR=1 "$WH" status --json
  [ "$status" -eq 0 ]
  no_esc "status --json" "$output"
  no_esc "status --json stderr" "$stderr"
  run --separate-stderr env FORCE_COLOR=1 "$WH" new feat-y --dry-run
  [ "$status" -eq 0 ]
  no_esc "new's stdout" "$output"
  case "$output" in */app/feat-y) ;; *) echo "new's stdout isn't the path: $output"; false ;; esac
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  run --separate-stderr env FORCE_COLOR=1 "$WH" help --all --json
  [ "$status" -eq 0 ]
  no_esc "help --all --json" "$output"
}
