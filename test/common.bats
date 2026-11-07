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

@test "boolean options parse =true, =false and --no-" {
  local prune=""
  wh_parse_opts gc 0 "--prune=prune" -- --prune=true
  [ "$prune" = "1" ]
  wh_parse_opts gc 0 "--prune=prune" -- --prune=false
  [ "$prune" = "0" ]
  prune=1
  wh_parse_opts gc 0 "--prune=prune" -- --no-prune
  [ "$prune" = "0" ]
  run --separate-stderr wh_parse_opts gc 0 "--prune=prune" -- --prune=maybe
  [ "$status" -eq 1 ]
  has "$stderr" "Option --prune takes true or false."
  run --separate-stderr wh_parse_opts gc 0 "" -- --dry-run=yes
  [ "$status" -eq 1 ]
  has "$stderr" "Option --dry-run takes true or false."
}

@test "an entry spelled --no-x takes --x as its negation" {
  local no_verify=""
  wh_parse_opts merge 0 "--no-verify=no_verify" -- --no-verify
  [ "$no_verify" = "1" ]
  wh_parse_opts merge 0 "--no-verify=no_verify" -- --verify
  [ "$no_verify" = "0" ]
  wh_parse_opts merge 0 "--no-verify=no_verify" -- --no-verify=false
  [ "$no_verify" = "0" ]
}

@test "negation applies to booleans only" {
  run --separate-stderr wh_parse_opts gc 0 "--base=base:" -- --no-base
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --no-base for worktree-harness gc."
  run --separate-stderr wh_parse_opts gc 0 "" -- --no-help
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --no-help for worktree-harness gc."
  run --separate-stderr wh_parse_opts gc 0 "--no-verify=v" -- --no-no-verify
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --no-no-verify for worktree-harness gc."
}

@test "built-in booleans parse the same forms" {
  wh_parse_opts gc 0 "" -- --dry-run --no-dry-run
  [ "$WH_DRY_RUN" = "0" ]
  export FORCE_COLOR=1
  wh_parse_opts gc 0 "" -- --no-color
  [ -z "$WH_C_RED" ]
  wh_parse_opts gc 0 "" -- --color
  [ -n "$WH_C_RED" ]
}

@test "a repeated boolean option is accepted once" {
  local prune=""
  run wh_parse_opts gc 0 "--prune=prune" -- --prune --prune
  [ "$status" -eq 0 ]
  wh_parse_opts gc 0 "--prune=prune" -- --prune --prune
  [ "$prune" = "1" ]
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

@test "--cwd and -C change directory identically" {
  local a="$BATS_TEST_TMPDIR/a" b="$BATS_TEST_TMPDIR/b" real_a real_b
  mkdir "$a" "$b"
  real_a="$(cd "$a" && pwd -P)"
  real_b="$(cd "$b" && pwd -P)"
  wh_parse_opts gc 0 "" -- --cwd "$a"
  [ "$(pwd -P)" = "$real_a" ]
  wh_parse_opts gc 0 "" -- -C "$b"
  [ "$(pwd -P)" = "$real_b" ]
  wh_parse_opts gc 0 "" -- --cwd="$a"
  [ "$(pwd -P)" = "$real_a" ]
  wh_parse_opts gc 0 "" -- --cwd "$a" --cwd "$b"
  [ "$(pwd -P)" = "$real_b" ]
}

@test "--cwd names the spelling used when its value is missing, and -C stays silent" {
  run --separate-stderr wh_parse_opts gc 0 "" -- --cwd
  [ "$status" -eq 1 ]
  has "$stderr" "Option --cwd needs a value."
  run --separate-stderr wh_parse_opts gc 0 "" -- --cwd=
  [ "$status" -eq 1 ]
  has "$stderr" "Option --cwd needs a value."
  run --separate-stderr wh_parse_opts gc 0 "" -- -C "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "--version works after the command and --help wins" {
  _wh_gc_usage() { echo "gc usage"; }
  run --separate-stderr wh_parse_opts gc 0 "" -- --version
  [ "$status" -eq 0 ]
  [ "$output" = "worktree-harness $WH_VERSION" ]
  [ -z "$stderr" ]
  run --separate-stderr wh_parse_opts gc 0 "" -- -v
  [ "$output" = "worktree-harness $WH_VERSION" ]
  run --separate-stderr wh_parse_opts gc 0 "" -- --version --help
  [ "$status" -eq 0 ]
  [ "$output" = "gc usage" ]
}

@test "--version prints JSON when --json is present, in either order" {
  run --separate-stderr wh_parse_opts gc 0 "" -- --version --json
  [ "$status" -eq 0 ]
  [ "$output" = "{\"version\":\"$WH_VERSION\"}" ]
  run --separate-stderr wh_parse_opts status 0 "--json=json" -- --json -v
  [ "$output" = "{\"version\":\"$WH_VERSION\"}" ]
}

@test "--version after a rest-mode command or after -- isn't ours" {
  wh_parse_opts launch rest "" -- claude --version
  [ "${WH_ARGS[1]}" = "--version" ]
  wh_parse_opts gc 1 "" -- -- --version
  [ "${WH_ARGS[0]}" = "--version" ]
}

@test "rest mode still lets --help beat --version after a value option" {
  _wh_launch_usage() { echo "launch usage"; }
  run --separate-stderr wh_parse_opts launch rest "--name=n:" -- --name x --version --help claude
  [ "$status" -eq 0 ]
  [ "$output" = "launch usage" ]
}

@test "--help --json uses the JSON help when it exists and human help before that" {
  _wh_gc_usage() { echo "gc usage"; }
  run --separate-stderr wh_parse_opts gc 0 "" -- --help --json
  [ "$status" -eq 0 ]
  [ "$output" = "gc usage" ]
  _wh_help_json() { printf '{"help":"%s"}\n' "$1"; }
  run --separate-stderr wh_parse_opts gc 0 "" -- --help --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"help":"gc"}' ]
}

@test "parse-only exits 0 before the command body" {
  run --separate-stderr env __WH_PARSE_ONLY=1 bash -c '
    . "$1"; wh_parse_opts gc 0 "--prune=prune" -- --prune; echo reached' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run --separate-stderr env __WH_PARSE_ONLY=1 bash -c '
    . "$1"; wh_parse_opts gc 0 "" -- --bogus; echo reached' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 1 ]
  has "$stderr" "Unknown option --bogus"
}

# A stand-in CLI: --help prints $HELP_TEXT; anything else passes when parse-only is
# set and its first argument isn't "bad". Records each run so a skipped example shows.
make_help_stub() {
  WH="$BATS_TEST_TMPDIR/stub"
  export HELP_TEXT="$1" STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  cat > "$WH" <<'EOF'
#!/usr/bin/env bash
if [ "$2" = "--help" ]; then printf '%s\n' "$HELP_TEXT"; exit 0; fi
printf '%s\n' "$*" >> "$STUB_LOG"
[ "${__WH_PARSE_ONLY:-}" = "1" ] && [ "$1" != "bad" ]
EOF
  chmod +x "$WH"
}

@test "assert_help_examples_parse fills placeholders and runs only the examples" {
  make_help_stub $'Usage:\n    worktree-harness new <BRANCH>\n\nExamples:\n    worktree-harness new <BRANCH> --cwd <DIR>\n    worktree-harness launch <COMMAND>\n    worktree-harness status --fields <FIELDS>\n\nOptions:\n    worktree-harness bad'
  run assert_help_examples_parse new
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "new r2-example --cwd $BATS_TEST_TMPDIR
launch true
status --fields branch,path" ]
}

@test "assert_help_examples_parse fails on a bad example and on an empty section" {
  make_help_stub $'Examples:\n    worktree-harness new x\n    worktree-harness bad x'
  run assert_help_examples_parse new
  [ "$status" -eq 1 ]
  has "$output" "example failed to parse:     worktree-harness bad x"
  make_help_stub $'Examples:\n\nOptions:\n    --all'
  run assert_help_examples_parse new
  [ "$status" -eq 1 ]
  has "$output" "Examples: section with no examples"
  make_help_stub $'Usage: no examples here'
  run assert_help_examples_parse new
  [ "$status" -eq 0 ]
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

@test "TERM=dumb on a TTY gives plain glyphs and no color" {
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
wh_err boom
wh_warn careful
: > "$BATS_TEST_TMPDIR/ran"
EOF
  TERM=dumb run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/ran" ] || skip "script didn't run the snippet under a pty here"
  has "$output" "Error: boom"
  has "$output" "Warning: careful"
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

# --- JSON mode ---------------------------------------------------------------

@test "JSON mode writes one error line and nothing on stdout" {
  run --separate-stderr bash -c '
    . "$1"; WH_JSON=1; wh_info hi; wh_step hi; wh_ok hi; wh_fail 1 invalid_config bad' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = '{"status":"error","reason":"invalid_config","message":"bad"}' ]
}

@test "wh_fail adds next in JSON mode and a Next: line in human mode" {
  run --separate-stderr bash -c '
    . "$1"; WH_JSON=1; wh_fail 3 conflict "a \"b\"" "worktree-harness merge --help"' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 3 ]
  [ "$stderr" = '{"status":"error","reason":"conflict","message":"a \"b\"","next":[{"command":"worktree-harness merge --help","argv":["worktree-harness","merge","--help"]}]}' ]
  run --separate-stderr wh_fail 3 conflict bad "worktree-harness merge --help"
  [ "$status" -eq 3 ]
  [ "$stderr" = $'Error: bad\n\nNext:\n    worktree-harness merge --help' ]
}

@test "wh_die keeps its human text and exit, and takes its JSON reason from WH_FAIL_REASON" {
  run --separate-stderr wh_die "Nope."
  [ "$status" -eq 1 ]
  [ "$stderr" = "Error: Nope." ]
  run --separate-stderr bash -c '. "$1"; WH_JSON=1; wh_die nope' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 1 ]
  [ "$stderr" = '{"status":"error","reason":"internal_error","message":"nope"}' ]
  run --separate-stderr bash -c '. "$1"; WH_JSON=1; WH_FAIL_REASON=invalid_config; wh_die nope' _ "$WH_ROOT/lib/common.sh"
  [ "$stderr" = '{"status":"error","reason":"invalid_config","message":"nope"}' ]
}

@test "usage errors are JSON as soon as the spec declares --json and argv has it" {
  run --separate-stderr wh_parse_opts status 0 "--json=json" -- --bogus --json
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = '{"status":"error","reason":"unknown_option","message":"Unknown option --bogus for worktree-harness status.","next":[{"command":"worktree-harness status --help","argv":["worktree-harness","status","--help"]}]}' ]
  run --separate-stderr wh_parse_opts status 0 "--json=json" -- junk --json
  [ "$status" -eq 1 ]
  has "$stderr" '"reason":"invalid_arguments"'
}

@test "--json stays out of the error form when undeclared, negated or after --" {
  run --separate-stderr wh_parse_opts gc 0 "" -- --json
  [ "$status" -eq 1 ]
  has "$stderr" "Error: Unknown option --json for worktree-harness gc."
  run --separate-stderr wh_parse_opts status 0 "--json=json" -- --bogus --json --no-json
  has "$stderr" "Error: Unknown option --bogus"
  run --separate-stderr wh_parse_opts status 0 "--json=json" -- --bogus --json=false
  has "$stderr" "Error: Unknown option --bogus"
  run --separate-stderr wh_parse_opts status 0 "--json=json" -- --bogus -- --json
  has "$stderr" "Error: Unknown option --bogus"
}

@test "every wh_fail reason is in the registry" {
  local reason
  # shellcheck disable=SC2013
  for reason in $(cd "$WH_ROOT" && grep -rhoE 'wh_fail [0-9]+ [a-z_]+' lib bin | awk '{print $3}'); do
    case " $WH_REASONS " in *" $reason "*) ;; *) printf 'unregistered: %s\n' "$reason"; false ;; esac
  done
}

@test "an unregistered reason reaches the JSON line as internal_error" {
  run --separate-stderr bash -c '. "$1"; WH_JSON=1; wh_fail 1 made_up bad' _ "$WH_ROOT/lib/common.sh"
  [ "$stderr" = '{"status":"error","reason":"internal_error","message":"bad"}' ]
}

@test "json_out compacts when piped" {
  run --separate-stderr wh_json_out '{"a":1,"b":[1,2]}'
  [ "$output" = '{"a":1,"b":[1,2]}' ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "json_out indents on a real TTY" {
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
wh_json_out '{"a":1}'
: > "$BATS_TEST_TMPDIR/ran"
EOF
  TERM=xterm run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/ran" ] || skip "script didn't run the snippet under a pty here"
  has "$output" '  "a": 1'
}

@test "indented JSON leaves string contents alone and keeps empty containers short" {
  WH_TTY_OUT=1
  run --separate-stderr wh_json_out '{"a,b":"x{y}:[\"z\\","l":[1,{"k":null}],"e":{},"n":[]}'
  [ "$output" = '{
  "a,b": "x{y}:[\"z\\",
  "l": [
    1,
    {
      "k": null
    }
  ],
  "e": {},
  "n": []
}' ]
}

@test "signal trap in JSON mode writes the canceled line and keeps the exit code" {
  run --separate-stderr bash -c '
    . "$1"; WH_JSON=1; WH_PARTIAL_PATH="$2"
    wh_install_signal_traps
    kill -TERM $$' _ "$WH_ROOT/lib/common.sh" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 143 ]
  [ -z "$output" ]
  [ "$stderr" = '{"status":"error","reason":"canceled","message":"Canceled.","data":{"remote":"none"}}' ]
}

# --- warnings ----------------------------------------------------------------

@test "a deprecation prints once per run" {
  run --separate-stderr bash -c '
    . "$1"; wh_deprecated x old new; wh_deprecated x old new; wh_deprecated y old2 new2' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = $'Warning: \'old\' is deprecated. Use \'new\'.\nWarning: \'old2\' is deprecated. Use \'new2\'.' ]
}

@test "warnings go in the JSON document" {
  run --separate-stderr bash -c '
    . "$1"; WH_JSON=1; wh_deprecated x old new; wh_warn "a \"b\""; wh_json_out "{\"a\":1}"' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = '{"a":1,"warnings":[{"reason":"deprecated","message":"'"'"'old'"'"' is deprecated. Use '"'"'new'"'"'."},{"reason":"general","message":"a \"b\""}]}' ]
}

@test "a warning joins an empty document, and an error line stays free of warnings" {
  run --separate-stderr bash -c '. "$1"; WH_JSON=1; wh_warn w; wh_json_out "{}"' _ "$WH_ROOT/lib/common.sh"
  [ "$output" = '{"warnings":[{"reason":"general","message":"w"}]}' ]
  run --separate-stderr bash -c '. "$1"; WH_JSON=1; wh_warn w; wh_fail 1 conflict bad' _ "$WH_ROOT/lib/common.sh"
  [ "$stderr" = '{"status":"error","reason":"conflict","message":"bad"}' ]
}

# Runs the bin-style sequence: open the queue, deprecate, then parse with $@.
queued_parse() {
  run --separate-stderr bash -c '
    . "$1"; shift
    _wh_gc_usage() { echo "gc usage"; }
    WH_QUEUE_WARNINGS=1
    wh_deprecated x old new
    printf "before-parse[%s]\n" "$WH_PENDING_WARNINGS" >&2
    wh_parse_opts gc 0 "--json=json" -- "$@"
    if [ "${json:-0}" = "1" ]; then wh_json_out "{\"a\":1}"; fi' _ "$WH_ROOT/lib/common.sh" "$@"
}

@test "a queued deprecation reaches stderr once the parser finds human mode" {
  queued_parse
  [ "$status" -eq 0 ]
  [ "$stderr" = $'before-parse[\'old\' is deprecated. Use \'new\'.]\nWarning: \'old\' is deprecated. Use \'new\'.' ]
}

@test "a queued deprecation joins the document once the parser finds JSON mode" {
  queued_parse --json
  [ "$status" -eq 0 ]
  has "$output" '"warnings":[{"reason":"deprecated"'
  [ "$stderr" = "before-parse['old' is deprecated. Use 'new'.]" ]
}

@test "a queued deprecation isn't lost when help or a failure ends the run" {
  queued_parse --help
  [ "$output" = "gc usage" ]
  has "$stderr" "Warning: 'old' is deprecated."
  run --separate-stderr bash -c '
    . "$1"; WH_QUEUE_WARNINGS=1; wh_deprecated x old new; wh_die boom' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 1 ]
  [ "$stderr" = $'Warning: \'old\' is deprecated. Use \'new\'.\nError: boom' ]
}

@test "wh_flush_pending_warnings prints for a command with no parser" {
  run --separate-stderr bash -c '
    . "$1"; WH_QUEUE_WARNINGS=1; wh_deprecated x old new; wh_flush_pending_warnings; wh_flush_pending_warnings
    wh_deprecated y old2 new2' _ "$WH_ROOT/lib/common.sh"
  [ "$status" -eq 0 ]
  [ "$stderr" = $'Warning: \'old\' is deprecated. Use \'new\'.\nWarning: \'old2\' is deprecated. Use \'new2\'.' ]
}

# --- guidance and interactivity ------------------------------------------------

@test "guidance helper honors the disable variable" {
  WH_GUIDANCE_DISABLED=1
  run wh_guidance_enabled
  [ "$status" -eq 1 ]
  WH_GUIDANCE_DISABLED=""
  run wh_guidance_enabled
  [ "$status" -eq 0 ]
  unset WH_GUIDANCE_DISABLED
  run wh_guidance_enabled
  [ "$status" -eq 0 ]
}

@test "offers need a stdin TTY and stay off for CI, JSON mode and disabled guidance" {
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
report() { if wh_offer_enabled; then echo "\$1=on"; else echo "\$1=off"; fi; }
report alone
( WH_GUIDANCE_DISABLED=1; report guidance )
( CI=1; report ci )
( WH_JSON=1; report json )
wh_init_style </dev/null
report no-stdin
: > "$BATS_TEST_TMPDIR/ran"
EOF
  TERM=xterm run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/ran" ] || skip "script didn't run the snippet under a pty here"
  has "$output" "alone=on"
  has "$output" "guidance=off"
  has "$output" "ci=off"
  has "$output" "json=off"
  has "$output" "no-stdin=off"
}

@test "print_id prints when piped and is quiet on an interactive TTY" {
  run --separate-stderr wh_print_id the-value
  [ "$status" -eq 0 ]
  [ "$output" = "the-value" ]
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
. "$WH_ROOT/lib/common.sh"
printf 'facts=%s%s%s\n' "\$WH_TTY_IN" "\$WH_TTY_OUT" "\$WH_TTY_ERR"
wh_print_id quiet-value
( CI=1; wh_print_id ci-value )
wh_init_style </dev/null
wh_print_id no-stdin-value
: > "$BATS_TEST_TMPDIR/ran"
EOF
  TERM=xterm run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/ran" ] || skip "script didn't run the snippet under a pty here"
  has "$output" "facts=111"
  has "$output" "ci-value"
  has "$output" "no-stdin-value"
  case "$output" in *quiet-value*) false ;; esac
}

@test "only common.sh checks TTYs and CI" {
  local found
  found="$(cd "$WH_ROOT" && grep -nE '\[ -t [012] \]|\$\{?CI\b' bin/worktree-harness lib/*.sh \
    | grep -v '^lib/common.sh:' | grep -v 'export CI=' || true)"
  [ -z "$found" ] || { printf '%s\n' "$found"; false; }
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

@test "INT exits 130 and names the partial worktree" {
  mkdir "$BATS_TEST_TMPDIR/partial"
  cat > "$BATS_TEST_TMPDIR/pty.sh" <<EOF
bash -c '. "$WH_ROOT/lib/common.sh"; WH_PARTIAL_PATH="$BATS_TEST_TMPDIR/partial"; wh_install_signal_traps; kill -INT \$\$; echo still-running'
echo "\$?" > "$BATS_TEST_TMPDIR/rc"
EOF
  TERM=xterm run_in_pty "$BATS_TEST_TMPDIR/pty.sh"
  [ -e "$BATS_TEST_TMPDIR/rc" ] || skip "script didn't run the snippet under a pty here"
  [ "$(cat "$BATS_TEST_TMPDIR/rc")" = "130" ]
  has "$output" "Stopped. Partial worktree left at $BATS_TEST_TMPDIR/partial"
  case "$output" in *still-running*) false ;; esac
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
