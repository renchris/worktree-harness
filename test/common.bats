#!/usr/bin/env bats
# Shared helpers in lib/common.sh, exercised directly. The last test goes through
# the CLI to prove the dispatcher re-reads the style after global flags.
bats_require_minimum_version 1.5.0
load helper

setup() {
  unset NO_COLOR WH_NO_COLOR FORCE_COLOR CI
  # shellcheck source=../lib/common.sh
  . "$WH_ROOT/lib/common.sh"
}

# [[ ]] doesn't trip errexit mid-test on bash 3.2, so substring checks use this.
has() { case "$1" in *"$2"*) return 0 ;; esac; printf 'missing: %s\nin: %s\n' "$2" "$1"; return 1; }

# Runs a script file under a pseudo-terminal; its stdout and stderr land in $output.
run_in_pty() {
  command -v script >/dev/null 2>&1 || skip "script isn't installed, so no pty is available"
  case "$(uname -s)" in
    Linux) run script -qec "bash $(printf '%q' "$1")" /dev/null </dev/null ;;
    *)     run script -q /dev/null bash "$1" </dev/null ;;
  esac
}

# --- wh_usage_die ------------------------------------------------------------

@test "usage die exits WH_EXIT_USAGE and names the help command" {
  run --separate-stderr wh_usage_die gc "Unknown option --x for worktree-harness gc."
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = $'Error: Unknown option --x for worktree-harness gc.\n\nSee all options:\n    worktree-harness gc --help' ]
}

@test "usage die without a command names the root help" {
  run --separate-stderr wh_usage_die "" "Nope."
  [ "$status" -eq 1 ]
  [ "$stderr" = $'Error: Nope.\n\nSee all options:\n    worktree-harness --help' ]
}

# --- wh_parse_opts -----------------------------------------------------------

@test "parse_opts rejects an unknown option" {
  run --separate-stderr wh_parse_opts gc 0 "" -- --bogus
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --bogus for worktree-harness gc."
  has "$stderr" "    worktree-harness gc --help"
}

@test "parse_opts names an unknown option without its value" {
  run --separate-stderr wh_parse_opts gc 0 "" -- --token=hunter2
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --token for worktree-harness gc."
  case "$stderr" in *hunter2*) false ;; esac
}

@test "parse_opts doesn't let a literal pipe match across spec alternatives" {
  run --separate-stderr wh_parse_opts gc 0 "--a|--b=v" -- "--a|--b"
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --a|--b for worktree-harness gc."
}

@test "parse_opts rejects an extra positional" {
  run --separate-stderr wh_parse_opts gc 0 "" -- junk
  [ "$status" -eq 1 ]
  has "$stderr" "Unexpected argument junk for worktree-harness gc."
}

@test "parse_opts counts positionals after -- toward the limit" {
  run --separate-stderr wh_parse_opts new 1 "" -- one -- two
  [ "$status" -eq 1 ]
  has "$stderr" "Unexpected argument two for worktree-harness new."
}

@test "parse_opts reports a value option with no value" {
  run --separate-stderr wh_parse_opts gc 0 "--name=v:" -- --name
  [ "$status" -eq 1 ]
  has "$stderr" "Option --name needs a value."
}

@test "parse_opts reports a value given to a boolean" {
  run --separate-stderr wh_parse_opts gc 0 "--all=a" -- --all=yes
  [ "$status" -eq 1 ]
  has "$stderr" "Option --all doesn't take a value."
  run --separate-stderr wh_parse_opts gc 0 "" -- --dry-run=yes
  [ "$status" -eq 1 ]
  has "$stderr" "Option --dry-run doesn't take a value."
}

@test "parse_opts accepts --opt=value and stops at --" {
  local v="" all=""
  wh_parse_opts gc 1 "--name=v: --all|-a=all" -- --name=x -a -- --name
  [ "$v" = "x" ]
  [ "$all" = "1" ]
  [ "${#WH_ARGS[@]}" -eq 1 ]
  [ "${WH_ARGS[0]}" = "--name" ]
}

@test "parse_opts accepts a separate value, an empty =value and an equals sign in a value" {
  local v=""
  wh_parse_opts gc 0 "--name=v:" -- --name "a b"
  [ "$v" = "a b" ]
  wh_parse_opts gc 0 "--name=v:" -- --name=
  [ -z "$v" ]
  wh_parse_opts gc 0 "--name=v:" -- --name=a=b
  [ "$v" = "a=b" ]
}

@test "parse_opts sets the caller's variable even when it shares a name with a parser local" {
  local name="" value="" cmd="" spec=""
  wh_parse_opts gc 0 "--a=name: --b=value: --c=cmd: --d=spec:" -- --a=1 --b=2 --c=3 --d=4
  [ "$name$value$cmd$spec" = "1234" ]
}

@test "parse_opts mixes options and positionals and treats a lone dash as a positional" {
  local all=""
  wh_parse_opts gc 2 "--all=all" -- one --all -
  [ "$all" = "1" ]
  [ "${WH_ARGS[*]}" = "one -" ]
}

@test "parse_opts rest mode passes the command through untouched" {
  wh_parse_opts launch rest "" -- claude --resume
  [ "${#WH_ARGS[@]}" -eq 2 ]
  [ "${WH_ARGS[0]}" = "claude" ]
  [ "${WH_ARGS[1]}" = "--resume" ]
}

@test "parse_opts rest mode leaves --help after the first positional to the wrapped command" {
  run --separate-stderr bash -c '
    . "$1"; _wh_launch_usage() { echo "launch usage"; }
    wh_parse_opts launch rest "--name=n:" -- --name x claude --help --bogus
    printf "[%s]" "$n" "${WH_ARGS[@]}"' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "[x][claude][--help][--bogus]" ]
}

@test "parse_opts rest mode still honors --help after a value option" {
  _wh_launch_usage() { echo "launch usage"; }
  run --separate-stderr wh_parse_opts launch rest "--name=n:" -- --name x --help claude
  [ "$status" -eq 0 ]
  [ "$output" = "launch usage" ]
}

@test "parse_opts help wins over a bad option and prints to stdout" {
  _wh_gc_usage() { echo "gc usage"; }
  run --separate-stderr wh_parse_opts gc 0 "" -- --bogus --help
  [ "$status" -eq 0 ]
  [ "$output" = "gc usage" ]
  [ -z "$stderr" ]
  run --separate-stderr wh_parse_opts gc 0 "" -- junk -h
  [ "$status" -eq 0 ]
  [ "$output" = "gc usage" ]
}

@test "parse_opts doesn't read --help after --" {
  _wh_gc_usage() { echo "gc usage"; }
  wh_parse_opts gc 1 "" -- -- --help
  [ "${WH_ARGS[0]}" = "--help" ]
}

@test "parse_opts fails closed when a command has no usage function" {
  run --separate-stderr wh_parse_opts gc 0 "" -- --help
  [ "$status" -eq 1 ]
  has "$stderr" "No help is defined for worktree-harness gc."
}

@test "parse_opts -C after the command changes directory" {
  mkdir "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
  wh_parse_opts gc 0 "" -- -C "$BATS_TEST_TMPDIR/a"
  [ "$(pwd -P)" = "$(cd "$BATS_TEST_TMPDIR/a" && pwd -P)" ]
  wh_parse_opts gc 0 "" -- -C="$BATS_TEST_TMPDIR/b"
  [ "$(pwd -P)" = "$(cd "$BATS_TEST_TMPDIR/b" && pwd -P)" ]
}

@test "parse_opts -C reports a missing value and a missing directory" {
  run --separate-stderr wh_parse_opts gc 0 "" -- -C
  [ "$status" -eq 1 ]
  has "$stderr" "Option -C needs a value."
  run --separate-stderr wh_parse_opts gc 0 "" -- -C=
  [ "$status" -eq 1 ]
  has "$stderr" "Option -C needs a value."
  run --separate-stderr wh_parse_opts gc 0 "" -- -C "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 1 ]
  has "$stderr" "Can't change to directory $BATS_TEST_TMPDIR/nope."
}

@test "parse_opts --dry-run and --no-color take effect and are exported" {
  export FORCE_COLOR=1
  wh_init_style
  [ -n "$WH_C_RED" ]
  wh_parse_opts gc 0 "" -- --dry-run --no-color
  [ -z "$WH_C_RED" ]
  [ "$(bash -c 'echo "$WH_DRY_RUN$WH_NO_COLOR"')" = "11" ]
}

@test "parse_opts is safe under the dispatcher's strict mode with no arguments" {
  run --separate-stderr bash -c '
    set -euo pipefail
    . "$1"
    wh_parse_opts gc 2 "--all=all" --
    printf "count=%s" "${#WH_ARGS[@]}"' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "count=0" ]
}

# --- wh_init_style -----------------------------------------------------------

@test "init_style precedence" {
  FORCE_COLOR=1 wh_init_style
  [ -n "$WH_C_RED" ]
  [ -n "$WH_O_DIM" ]

  WH_NO_COLOR=1 FORCE_COLOR=1 wh_init_style
  [ -z "$WH_C_RED" ]
  [ -z "$WH_O_DIM" ]

  NO_COLOR=1 FORCE_COLOR=1 wh_init_style
  [ -z "$WH_C_RED" ]

  FORCE_COLOR=0 wh_init_style
  [ -z "$WH_C_RED" ]
}

@test "plain stderr uses Warning:/Error: prefixes and no glyph on ok or step" {
  run wh_warn x
  [ "$output" = "Warning: x" ]
  run wh_err y
  [ "$output" = "Error: y" ]
  run wh_ok z
  [ "$output" = "z" ]
  run wh_step w
  [ "$output" = "w" ]
}

@test "a TTY stderr gets glyphs and colour while a piped stdout stays plain" {
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
exec 1>"$BATS_TEST_TMPDIR/stdout"
wh_init_style
printf 'out=%s err=%s rich=%s dim=[%s]\n' "\$WH_TTY_OUT" "\$WH_TTY_ERR" "\$WH_RICH_ERR" "\$WH_O_DIM"
wh_err boom; wh_warn careful; wh_ok done; wh_step going
EOF
  TERM=xterm run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -s "$BATS_TEST_TMPDIR/stdout" ] || skip "script didn't run the snippet under a pty here"
  [ "$(cat "$BATS_TEST_TMPDIR/stdout")" = "out=0 err=1 rich=1 dim=[]" ]
  has "$output" $'\033[31m✗\033[0m boom'
  has "$output" $'\033[33m!\033[0m careful'
  has "$output" $'\033[32m✓\033[0m done'
  has "$output" $'\033[34m→\033[0m going'
}

@test "TERM=dumb on a TTY stays plain" {
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
wh_err boom
: > "$BATS_TEST_TMPDIR/ran"
EOF
  TERM=dumb run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/ran" ] || skip "script didn't run the snippet under a pty here"
  has "$output" "Error: boom"
  case "$output" in *$'\033['*) false ;; esac
}

# --- small helpers -----------------------------------------------------------

@test "plural picks singular for 1" {
  [ "$(wh_plural 1 worktree worktrees)" = "1 worktree" ]
  [ "$(wh_plural 2 worktree worktrees)" = "2 worktrees" ]
  [ "$(wh_plural 0 worktree worktrees)" = "0 worktrees" ]
}

@test "sanitize strips ESC and C1 but keeps UTF-8" {
  result="$(printf 'caf\xc3\xa9 \033[31mred\xc2\x9b\ta\rb\177\n' | wh_sanitize_stream)"
  [ "$result" = $'caf\xc3\xa9 [31mred\tab' ]
}

@test "json_str escapes quotes, backslashes, tabs, newlines and other C0" {
  [ "$(wh_json_str $'a"b\\c\td\ne\rf')" = '"a\"b\\c\td\ne\rf"' ]
  [ "$(wh_json_str $'x\001y\033z\037')" = '"x\u0001y\u001bz\u001f"' ]
  [ "$(wh_json_str $'caf\xc3\xa9')" = $'"caf\xc3\xa9"' ]
  [ "$(wh_json_str '')" = '""' ]
}

# --- preconditions -----------------------------------------------------------

@test "require_repo names the command and the way out, outside a repo" {
  make_norepo
  run --separate-stderr wh_require_repo gc
  [ "$status" -eq 1 ]
  [ "$stderr" = "Error: Can't run worktree-harness gc outside a git repository. cd into your repo (or pass --cwd <DIR>) and re-run." ]
  git init -q .
  run --separate-stderr wh_require_repo gc
  [ "$status" -eq 0 ]
}

@test "require_consent fails with exit 2 and names --yes when stdin is not a TTY" {
  run --separate-stderr wh_require_consent "Remove?" "Can't remove worktrees without --yes in non-interactive mode." "worktree-harness gc --prune --yes" 0 </dev/null
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = $'Error: Can\'t remove worktrees without --yes in non-interactive mode.\n  worktree-harness gc --prune --yes' ]
}

@test "require_consent returns 0 without asking when assume_yes is 1" {
  run --separate-stderr wh_require_consent "Remove?" "headline" "rerun" 1 </dev/null
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "require_consent refuses on a TTY when CI is set" {
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
( wh_require_consent "Remove?" "headline" "rerun" 0 ); echo "\$?" > "$BATS_TEST_TMPDIR/rc"
EOF
  CI=1 run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/rc" ] || skip "script didn't run the snippet under a pty here"
  [ "$(cat "$BATS_TEST_TMPDIR/rc")" = "2" ]
}

# --- atomic writes -----------------------------------------------------------

@test "atomic_write leaves no temp file and keeps umask mode" {
  cd "$BATS_TEST_TMPDIR"
  umask 022
  printf 'one\n' | wh_atomic_write x
  [ "$(cat x)" = "one" ]
  [ "$(ls -l x | cut -c1-10)" = "-rw-r--r--" ]
  printf 'two\n' | wh_atomic_write x 600
  [ "$(cat x)" = "two" ]
  [ "$(ls -l x | cut -c1-10)" = "-rw-------" ]
  [ -z "$(find . -name '.x.*')" ]
}

@test "atomic_write handles a dash-leading name and refuses a directory" {
  cd "$BATS_TEST_TMPDIR"
  printf 'one\n' | wh_atomic_write -x
  [ "$(cat ./-x)" = "one" ]
  mkdir d
  rc=0
  printf 'one\n' | wh_atomic_write d 2>/dev/null || rc=$?
  [ "$rc" -eq 1 ]
  [ -z "$(ls -A d)" ]
}

@test "write_new refuses an existing file" {
  cd "$BATS_TEST_TMPDIR"
  umask 022
  printf 'one\n' | wh_write_new x
  [ "$(cat x)" = "one" ]
  [ "$(ls -l x | cut -c1-10)" = "-rw-r--r--" ]
  rc=0
  printf 'two\n' | wh_write_new x || rc=$?
  [ "$rc" -eq 1 ]
  [ "$(cat x)" = "one" ]
  [ -z "$(find . -name '.x.*')" ]
}

@test "write_new refuses a dangling symlink and a directory" {
  cd "$BATS_TEST_TMPDIR"
  ln -s nowhere link
  mkdir d
  rc=0
  printf 'one\n' | wh_write_new link || rc=$?
  [ "$rc" -eq 1 ]
  [ ! -e nowhere ]
  rc=0
  printf 'one\n' | wh_write_new d || rc=$?
  [ "$rc" -eq 1 ]
  [ -z "$(ls -A d)" ]
}

# --- signals -----------------------------------------------------------------

@test "signal trap names the partial worktree and exits 143 on TERM" {
  mkdir "$BATS_TEST_TMPDIR/par tial"
  run --separate-stderr bash -c '
    . "$1"
    WH_PARTIAL_PATH="$2"; WH_PARTIAL_BRANCH=feat
    wh_install_signal_traps
    kill -TERM $$
    echo "still running"' _ "$WH_ROOT/lib/common.sh" "$BATS_TEST_TMPDIR/par tial"
  [ "$status" -eq 143 ]
  [ -z "$output" ]
  has "$stderr" "Stopped. Partial worktree left at $BATS_TEST_TMPDIR/par tial (branch feat). To remove it:"
  has "$stderr" "  git worktree remove --force $(printf '%q' "$BATS_TEST_TMPDIR/par tial")"
  has "$stderr" "  git branch -D feat"
}

@test "signal trap says nothing when no partial worktree exists" {
  run --separate-stderr bash -c '
    . "$1"
    WH_PARTIAL_PATH="$2"
    wh_install_signal_traps
    kill -TERM $$' _ "$WH_ROOT/lib/common.sh" "$BATS_TEST_TMPDIR/gone"
  [ "$status" -eq 143 ]
  [ -z "$stderr" ]
}

# --- CLI ---------------------------------------------------------------------

@test "--no-color disables color (CLI)" {
  FORCE_COLOR=1 run "$WH" definitely-not-a-command
  has "$output" $'\033['
  FORCE_COLOR=1 run "$WH" --no-color definitely-not-a-command
  has "$output" "unknown command: definitely-not-a-command"
  case "$output" in *$'\033'*) false ;; esac
}
