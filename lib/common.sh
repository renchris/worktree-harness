#!/usr/bin/env bash
# common.sh — shared version, exit codes, style, logging, option parsing,
# consent, atomic writes and signal traps.
# Sourced by the dispatcher and every command, never run. bash 3.2-safe.
#
# All diagnostics go to STDERR so stdout stays clean for machine-readable
# output (`status --porcelain`, a captured worktree path, etc.).

# The values below are this tool's shared surface: assigned here, consumed by
# the dispatcher and command files that source this. shellcheck can't see that
# cross-file usage when linting this file in isolation, hence the disable.
# shellcheck disable=SC2034
WH_VERSION="0.2.0"

# --- exit codes --------------------------------------------------------------
WH_EXIT_USAGE=1
WH_EXIT_MISSING_INPUT=2   # a required confirmation can't be asked for (wh_require_consent)

# --- style -------------------------------------------------------------------
# _wh_color_on <fd> — colour decision for one stream. Precedence: WH_NO_COLOR=1
# (--no-color) > non-empty NO_COLOR (https://no-color.org) > FORCE_COLOR (set and
# not 0: on; 0: off) > the stream is a TTY and TERM isn't dumb.
_wh_color_on() {
  if [ "${WH_NO_COLOR:-0}" = "1" ]; then return 1; fi
  if [ -n "${NO_COLOR:-}" ]; then return 1; fi
  if [ -n "${FORCE_COLOR+x}" ]; then [ "$FORCE_COLOR" != "0" ]; return; fi
  [ -t "$1" ] && [ "${TERM:-}" != "dumb" ]
}

# wh_init_style — set the stream facts and colour roles. WH_C_* are for stderr,
# WH_O_* for stdout. Runs at source time, and again once global flags are known.
wh_init_style() {
  WH_TTY_OUT=0; WH_TTY_ERR=0; WH_RICH_ERR=0
  if [ -t 1 ]; then WH_TTY_OUT=1; fi
  if [ -t 2 ]; then
    WH_TTY_ERR=1
    if [ "${TERM:-}" != "dumb" ]; then WH_RICH_ERR=1; fi
  fi

  if _wh_color_on 2; then
    WH_C_RED=$'\033[31m';   WH_C_GREEN=$'\033[32m'; WH_C_YELLOW=$'\033[33m'
    WH_C_BLUE=$'\033[34m';  WH_C_DIM=$'\033[2m';    WH_C_BOLD=$'\033[1m'
    WH_C_RESET=$'\033[0m'
  else
    WH_C_RED=''; WH_C_GREEN=''; WH_C_YELLOW=''; WH_C_BLUE=''
    WH_C_DIM=''; WH_C_BOLD=''; WH_C_RESET=''
  fi

  if _wh_color_on 1; then
    WH_O_DIM=$'\033[2m'; WH_O_RESET=$'\033[0m'
  else
    WH_O_DIM=''; WH_O_RESET=''
  fi
}
wh_init_style

# --- logging (all to stderr) -------------------------------------------------
# _wh_line <color> <rich-glyph> <plain-prefix> <message>
_wh_line() {
  local color="$1" mark="$3"
  if [ "$WH_RICH_ERR" = "1" ]; then mark="$2"; fi
  if [ -n "$mark" ]; then
    printf '%s%s%s %s\n' "$color" "$mark" "$WH_C_RESET" "$4" >&2
  else
    printf '%s\n' "$4" >&2
  fi
}

wh_info() { printf '%s\n' "$*" >&2; }
wh_step() { _wh_line "$WH_C_BLUE"   '→' ''         "$*"; }
wh_ok()   { _wh_line "$WH_C_GREEN"  '✓' ''         "$*"; }
wh_warn() { _wh_line "$WH_C_YELLOW" '!' 'Warning:' "$*"; }
wh_err()  { _wh_line "$WH_C_RED"    '✗' 'Error:'   "$*"; }
wh_die()  { wh_err "$*"; exit 1; }

# wh_usage_die <cmd-or-""> <message> [<reason>] — report a usage error, name the
# help command, exit WH_EXIT_USAGE. <reason> is accepted for callers; nothing
# reads it yet.
wh_usage_die() {
  local cmd="${1:-}"
  wh_err "${2:-}"
  wh_info ""
  wh_info "See all options:"
  wh_info "    worktree-harness ${cmd:+$cmd }--help"
  exit "$WH_EXIT_USAGE"
}

# wh_run <cmd...> — echo the command, then run it unless WH_DRY_RUN=1.
wh_run() {
  wh_step "$*"
  [ "${WH_DRY_RUN:-0}" = "1" ] && return 0
  "$@"
}

# --- small value helpers (no trailing newline, for use in "$(...)") ------------
# wh_plural <n> <one> <many> — "1 worktree" / "3 worktrees".
wh_plural() {
  if [ "$1" = "1" ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi
}

# wh_json_str <s> — <s> as a JSON string literal, quotes included.
wh_json_str() {
  local s="$1" out='"' c n i=0
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"; i=$((i + 1))
    case "$c" in
      '"')   out+='\"' ;;
      \\)    out+="\\\\" ;;
      $'\t') out+='\t' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      [[:cntrl:]])
        printf -v n '%d' "'$c"
        if [ "$n" -lt 32 ]; then printf -v c '\\u%04x' "$n"; fi
        out+="$c" ;;
      *)     out+="$c" ;;
    esac
  done
  printf '%s"' "$out"
}

# wh_sanitize_stream — stdin to stdout without C0 (except tab and newline), DEL
# or UTF-8 C1 controls. C1 is matched as its two-byte UTF-8 form, never as lone
# bytes, because \200-\237 also occur inside valid multibyte characters.
wh_sanitize_stream() {
  LC_ALL=C tr -d '\000-\010\013-\037\177' | LC_ALL=C sed $'s/\xc2[\x80-\x9f]//g'
}

# --- option parsing ----------------------------------------------------------
# _wh_show_help <cmd> — print the command's usage on stdout and exit 0.
_wh_show_help() {
  local fn="_wh_${1}_usage"
  declare -F "$fn" >/dev/null || wh_die "No help is defined for worktree-harness $1."
  "$fn"
  exit 0
}

# _wh_prescan_help <cmd> <max|rest> <arg...> — help wins over any other error, so
# look for it before parsing. Stops at "--"; in rest mode also at the first
# positional, because everything from there on belongs to the wrapped command.
_wh_prescan_help() {
  local cmd="$1" max="$2" a
  shift 2
  for a in "$@"; do
    case "$a" in
      --)        return 0 ;;
      -h|--help) _wh_show_help "$cmd" ;;
      -?*)       ;;
      *)         if [ "$max" = "rest" ]; then return 0; fi ;;
    esac
  done
  return 0
}

# _wh_opt_classify <name> <spec> — find an option. On success sets _WH_OPT_TAKES
# (1 if it takes a value) and _WH_OPT_VAR (empty for a built-in, which
# _wh_opt_builtin applies). Add a built-in here and in _wh_opt_builtin.
_wh_opt_classify() {
  local IFS=' ' _wh_entry _wh_names
  _WH_OPT_TAKES=0; _WH_OPT_VAR=""
  case "$1" in
    *'|'*) return 1 ;;   # would match across the alternatives of a spec entry
    -h|--help|--dry-run|--no-color) return 0 ;;
    -C) _WH_OPT_TAKES=1; return 0 ;;
  esac
  for _wh_entry in $2; do
    _wh_names="${_wh_entry%%=*}"
    case "|$_wh_names|" in
      *"|$1|"*)
        _WH_OPT_VAR="${_wh_entry#*=}"
        case "$_WH_OPT_VAR" in
          *:) _WH_OPT_TAKES=1; _WH_OPT_VAR="${_WH_OPT_VAR%:}" ;;
        esac
        return 0 ;;
    esac
  done
  return 1
}

# _wh_opt_builtin <cmd> <name> <value> — apply a built-in option.
_wh_opt_builtin() {
  case "$2" in
    -h|--help)  _wh_show_help "$1" ;;
    --dry-run)  WH_DRY_RUN=1; export WH_DRY_RUN ;;
    --no-color) WH_NO_COLOR=1; export WH_NO_COLOR; wh_init_style ;;
    -C)
      if [ -z "$3" ]; then wh_usage_die "$1" "Option $2 needs a value."; fi
      CDPATH='' cd -- "$3" >/dev/null 2>&1 || wh_die "Can't change to directory $3." ;;
  esac
}

# wh_parse_opts <cmd> <max-positionals|rest> "<spec>" -- "$@"
#   spec: space-separated "a|b=VAR" (boolean, sets VAR=1) or "a|b=VAR:" (takes a
#   value: --a v or --a=v), with the dashes in the names: "--all|-a=all --base=base:"
#   Result: WH_ARGS holds the positionals; read it as ${WH_ARGS[@]+"${WH_ARGS[@]}"}.
#   "--" ends options. In rest mode the first positional, or anything after "--",
#   goes to WH_ARGS verbatim, along with everything after it.
# Locals carry a prefix because printf -v assigns through dynamic scope: a spec
# naming VAR "name" must set the caller's variable, not one of ours.
wh_parse_opts() {
  if [ "${4:-}" != "--" ]; then wh_die "wh_parse_opts: the -- separator is missing."; fi
  local _wh_cmd="$1" _wh_max="$2" _wh_spec="$3" _wh_n=0
  local _wh_arg _wh_name _wh_value _wh_has_value
  shift 4
  WH_ARGS=()
  _wh_prescan_help "$_wh_cmd" "$_wh_max" "$@"

  while [ $# -gt 0 ]; do
    _wh_arg="$1"; shift

    case "$_wh_arg" in
      --)
        while [ $# -gt 0 ]; do
          if [ "$_wh_max" != "rest" ] && [ "$_wh_n" -ge "$_wh_max" ]; then
            wh_usage_die "$_wh_cmd" "Unexpected argument $1 for worktree-harness $_wh_cmd."
          fi
          WH_ARGS+=("$1"); _wh_n=$((_wh_n + 1)); shift
        done
        break ;;
      -?*) ;;
      *)
        if [ "$_wh_max" = "rest" ]; then
          WH_ARGS+=("$_wh_arg")
          if [ $# -gt 0 ]; then WH_ARGS+=("$@"); fi
          break
        fi
        if [ "$_wh_n" -ge "$_wh_max" ]; then
          wh_usage_die "$_wh_cmd" "Unexpected argument $_wh_arg for worktree-harness $_wh_cmd."
        fi
        WH_ARGS+=("$_wh_arg"); _wh_n=$((_wh_n + 1))
        continue ;;
    esac

    case "$_wh_arg" in
      *=*) _wh_name="${_wh_arg%%=*}"; _wh_value="${_wh_arg#*=}"; _wh_has_value=1 ;;
      *)   _wh_name="$_wh_arg"; _wh_value=""; _wh_has_value=0 ;;
    esac

    if ! _wh_opt_classify "$_wh_name" "$_wh_spec"; then
      wh_usage_die "$_wh_cmd" "Unknown option $_wh_name for worktree-harness $_wh_cmd."
    fi

    if [ "$_WH_OPT_TAKES" = "1" ]; then
      if [ "$_wh_has_value" = "0" ]; then
        if [ $# -eq 0 ]; then wh_usage_die "$_wh_cmd" "Option $_wh_name needs a value."; fi
        _wh_value="$1"; shift
      fi
    elif [ "$_wh_has_value" = "1" ]; then
      wh_usage_die "$_wh_cmd" "Option $_wh_name doesn't take a value."
    else
      _wh_value=1
    fi

    if [ -n "$_WH_OPT_VAR" ]; then
      printf -v "$_WH_OPT_VAR" '%s' "$_wh_value"
    else
      _wh_opt_builtin "$_wh_cmd" "$_wh_name" "$_wh_value"
    fi
  done
  return 0
}

# --- preconditions -----------------------------------------------------------
# wh_require_repo <cmd> — deliberately not part of wh_load_config: launch must
# keep working outside a repository.
wh_require_repo() {
  git rev-parse --show-toplevel >/dev/null 2>&1 \
    || wh_die "Can't run worktree-harness $1 outside a git repository. cd into your repo (or pass --cwd <DIR>) and re-run."
}

# wh_require_consent <question> <missing-headline> <rerun-cmd> <assume_yes:0|1>
# Returns 0 on consent. Asks only when stdin and stderr are TTYs and CI is unset;
# otherwise it refuses and exits WH_EXIT_MISSING_INPUT rather than assuming.
wh_require_consent() {
  local reply=""
  if [ "${4:-0}" = "1" ]; then return 0; fi
  if [ -t 0 ] && [ -t 2 ] && [ -z "${CI+x}" ]; then
    printf '? %s (y/N) ' "$1" >&2
    read -r reply || reply=""
    case "$reply" in [Yy]|[Yy][Ee][Ss]) return 0 ;; esac
    wh_info "Canceled."
    exit 130
  fi
  wh_err "$2"
  wh_info "  $3"
  exit "$WH_EXIT_MISSING_INPUT"
}

# --- atomic writes -----------------------------------------------------------
# _wh_tmp_from_stdin <target> [mode] — copy stdin to a temp file beside <target>
# and print its path. The default mode is 0666 & ~umask, because mktemp makes 0600.
_wh_tmp_from_stdin() {
  local target="$1" mode="${2:-}" tmp
  case "$target" in */*) ;; *) target="./$target" ;; esac
  case "$target" in -*) target="./$target" ;; esac
  if [ -z "$mode" ]; then mode="$(printf '%04o' "$(( 0666 & ~$(umask) ))")"; fi
  tmp="$(mktemp "${target%/*}/.${target##*/}.XXXXXX")" || return 1
  if cat > "$tmp" && chmod "$mode" "$tmp"; then
    printf '%s\n' "$tmp"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

# wh_atomic_write <target> [mode] — stdin replaces <target> in one step.
wh_atomic_write() {
  local target="$1" tmp
  # mv onto a directory would move the file inside it and still report success.
  if [ -d "$target" ]; then wh_err "Can't write $target: it's a directory."; return 1; fi
  tmp="$(_wh_tmp_from_stdin "$target" "${2:-}")" || return 1
  if mv -f -- "$tmp" "$target"; then return 0; fi
  rm -f -- "$tmp"
  return 1
}

# wh_write_new <target> [mode] — stdin becomes <target> only if nothing is there.
# `ln` is the atomic publish: it fails on an existing target, so there's no clobber
# race. Returns 1 if the target exists, 2 on any other failure.
wh_write_new() {
  local target="$1" tmp
  if [ -e "$target" ] || [ -h "$target" ]; then return 1; fi
  tmp="$(_wh_tmp_from_stdin "$target" "${2:-}")" || return 2
  if ln -- "$tmp" "$target" 2>/dev/null; then
    rm -f -- "$tmp"
    return 0
  fi
  rm -f -- "$tmp"
  if [ -e "$target" ] || [ -h "$target" ]; then return 1; fi
  wh_err "Can't create $target."
  return 2
}

# --- signals -----------------------------------------------------------------
# A command sets these while it holds partial state.
WH_PARTIAL_PATH=""
WH_PARTIAL_BRANCH=""

# _wh_on_signal <SIG> <code> — say what was left behind, then exit <code>.
_wh_on_signal() {
  local quoted
  trap - "$1"
  if [ -n "$WH_PARTIAL_PATH" ] && [ -e "$WH_PARTIAL_PATH" ]; then
    wh_info "Stopped. Partial worktree left at $WH_PARTIAL_PATH${WH_PARTIAL_BRANCH:+ (branch $WH_PARTIAL_BRANCH)}. To remove it:"
    printf -v quoted '%q' "$WH_PARTIAL_PATH"
    wh_info "  git worktree remove --force $quoted"
    if [ -n "$WH_PARTIAL_BRANCH" ]; then
      printf -v quoted '%q' "$WH_PARTIAL_BRANCH"
      wh_info "  git branch -D $quoted"
    fi
  fi
  exit "$2"
}

# wh_install_signal_traps — the one root trap. Doesn't reach $(...) subshells.
wh_install_signal_traps() {
  trap '_wh_on_signal INT 130' INT
  trap '_wh_on_signal TERM 143' TERM
  trap '_wh_on_signal HUP 129' HUP
}
