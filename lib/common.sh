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

# --- JSON mode ---------------------------------------------------------------
# wh_parse_opts sets WH_JSON=1 when the command declares --json and argv has it.
# Stdout then carries one document and stderr at most one error line.
WH_JSON=0
WH_JSON_WARNINGS=""                     # comma-joined warning objects for wh_json_out
WH_REASONS="invalid_arguments unknown_option unknown_command repository_not_found invalid_config conflict network_error partial_failure confirmation_required canceled internal_error"
WH_WARNING_REASONS="deprecated general"

# Deprecations. bin sets WH_QUEUE_WARNINGS=1 before its global loop, because the
# output mode isn't known until the command's parser has run; wh_parse_opts and
# wh_flush_pending_warnings close the queue. Left at 0, they print at once.
WH_DEPRECATED_SEEN=""
WH_QUEUE_WARNINGS=0
WH_PENDING_WARNINGS=""                  # newline-joined messages

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
  WH_TTY_IN=0; WH_TTY_OUT=0; WH_TTY_ERR=0; WH_RICH_ERR=0
  if [ -t 0 ]; then WH_TTY_IN=1; fi
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

# _wh_json_quiet — true when progress output must stay off stderr.
_wh_json_quiet() { [ "$WH_JSON" = "1" ]; }

wh_info() { _wh_json_quiet || printf '%s\n' "$*" >&2; }
wh_step() { _wh_json_quiet || _wh_line "$WH_C_BLUE"  '→' '' "$*"; }
wh_ok()   { _wh_json_quiet || _wh_line "$WH_C_GREEN" '✓' '' "$*"; }
wh_warn() { _wh_warning general "$*"; }
wh_err()  { _wh_line "$WH_C_RED" '✗' 'Error:' "$*"; }
wh_die()  { wh_fail 1 "${WH_FAIL_REASON:-internal_error}" "$*"; }

# _wh_warning <reason> <message> — on stderr, or kept for the JSON document.
_wh_warning() {
  local reason="$1"
  case " $WH_WARNING_REASONS " in *" $reason "*) ;; *) reason="general" ;; esac
  if [ "$WH_JSON" = "1" ]; then
    WH_JSON_WARNINGS="${WH_JSON_WARNINGS:+$WH_JSON_WARNINGS,}{\"reason\":$(wh_json_str "$reason"),\"message\":$(wh_json_str "$2")}"
  else
    _wh_line "$WH_C_YELLOW" '!' 'Warning:' "$2"
  fi
}

# wh_deprecated <id> <old> <new> — warn at most once per <id> per run.
wh_deprecated() {
  local msg="'$2' is deprecated. Use '$3'." newline=$'\n'
  case " $WH_DEPRECATED_SEEN " in *" $1 "*) return 0 ;; esac
  WH_DEPRECATED_SEEN="$WH_DEPRECATED_SEEN $1"
  if [ "$WH_QUEUE_WARNINGS" = "1" ]; then
    WH_PENDING_WARNINGS="${WH_PENDING_WARNINGS:+$WH_PENDING_WARNINGS$newline}$msg"
  else
    _wh_warning deprecated "$msg"
  fi
}

# wh_flush_pending_warnings — the output mode is now known: close the queue and
# send what it holds to stderr or the JSON document.
wh_flush_pending_warnings() {
  local msg pending="$WH_PENDING_WARNINGS"
  WH_QUEUE_WARNINGS=0; WH_PENDING_WARNINGS=""
  if [ -z "$pending" ]; then return 0; fi
  while IFS= read -r msg; do
    _wh_warning deprecated "$msg"
  done <<< "$pending"
}

# _wh_json_next <command> — one "next" entry. argv is the command split on spaces,
# so pass a command whose values contain none.
_wh_json_next() {
  local word argv="" words
  IFS=' ' read -r -a words <<< "$1"
  for word in ${words[@]+"${words[@]}"}; do
    argv="${argv:+$argv,}$(wh_json_str "$word")"
  done
  printf '{"command":%s,"argv":[%s]}' "$(wh_json_str "$1")" "$argv"
}

# wh_fail <exit> <reason> <message> [<next-command>] — the one way to fail. Human
# text, or in JSON mode exactly one line on stderr. Reasons come from WH_REASONS.
wh_fail() {
  local code="$1" reason="$2" msg="$3" next="${4:-}" line
  wh_flush_pending_warnings
  case " $WH_REASONS " in *" $reason "*) ;; *) reason="internal_error" ;; esac
  if [ "$WH_JSON" = "1" ]; then
    line="{\"status\":\"error\",\"reason\":$(wh_json_str "$reason"),\"message\":$(wh_json_str "$msg")"
    if [ -n "$next" ]; then line="$line,\"next\":[$(_wh_json_next "$next")]"; fi
    printf '%s}\n' "$line" >&2
  else
    wh_err "$msg"
    if [ -n "$next" ]; then
      wh_info ""
      wh_info "Next:"
      wh_info "    $next"
    fi
  fi
  exit "$code"
}

# wh_usage_die <cmd-or-""> <message> [<reason>] — report a usage error, name the
# help command, exit WH_EXIT_USAGE. <reason> defaults to invalid_arguments.
wh_usage_die() {
  local cmd="${1:-}" help_cmd
  help_cmd="worktree-harness ${1:+$cmd }--help"
  if [ "$WH_JSON" = "1" ]; then
    wh_fail "$WH_EXIT_USAGE" "${3:-invalid_arguments}" "${2:-}" "$help_cmd"
  fi
  wh_flush_pending_warnings
  wh_err "${2:-}"
  wh_info ""
  wh_info "See all options:"
  wh_info "    $help_cmd"
  exit "$WH_EXIT_USAGE"
}

# wh_json_out <compact-json-object> — the result document, plus any warnings. As
# is when piped; indented with 2 spaces on a TTY.
wh_json_out() {
  local doc="$1"
  if [ -n "$WH_JSON_WARNINGS" ]; then
    if [ "$doc" = "{}" ]; then
      doc="{\"warnings\":[$WH_JSON_WARNINGS]}"
    else
      doc="${doc%?},\"warnings\":[$WH_JSON_WARNINGS]}"
    fi
  fi
  if [ "$WH_TTY_OUT" = "1" ]; then
    printf '%s\n' "$doc" | _wh_json_pretty
  else
    printf '%s\n' "$doc"
  fi
}

# _wh_json_pretty — indent compact JSON from stdin; string contents stay untouched.
_wh_json_pretty() {
  LC_ALL=C awk '
    function newline(level, i) { printf "\n"; for (i = 0; i < level; i++) printf "  " }
    {
      n = length($0)
      for (p = 1; p <= n; p++) {
        c = substr($0, p, 1)
        if (in_string) {
          printf "%s", c
          if (c == "\\") { p++; printf "%s", substr($0, p, 1) }
          else if (c == "\"") in_string = 0
        } else if (c == "\"") {
          in_string = 1; printf "%s", c
        } else if (c == "{" || c == "[") {
          after = substr($0, p + 1, 1)
          if (after == "}" || after == "]") { printf "%s%s", c, after; p++ }
          else { printf "%s", c; depth++; newline(depth) }
        } else if (c == "}" || c == "]") {
          depth--; newline(depth); printf "%s", c
        } else if (c == ",") {
          printf "%s", c; newline(depth)
        } else if (c == ":") {
          printf ": "
        } else {
          printf "%s", c
        }
      }
    }
    END { printf "\n" }'
}

# --- guidance ----------------------------------------------------------------
# _wh_interactive — someone at a terminal can see and answer us.
_wh_interactive() { [ "$WH_TTY_IN" = "1" ] && [ "$WH_TTY_ERR" = "1" ] && [ -z "${CI+x}" ]; }

# wh_guidance_enabled — optional tips print. Required recovery never checks this.
wh_guidance_enabled() { [ -z "${WH_GUIDANCE_DISABLED:-}" ]; }

# wh_offer_enabled — tips that invite the next action print.
wh_offer_enabled() { wh_guidance_enabled && [ "$WH_JSON" = "0" ] && _wh_interactive; }

# wh_print_id <value> — the value on stdout so x=$(…) works; nothing on an
# interactive TTY, where the receipt already shows it.
wh_print_id() {
  if [ "$WH_TTY_OUT" = "1" ] && _wh_interactive; then return 0; fi
  printf '%s\n' "$1"
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

# _wh_show_version — print the version on stdout and exit 0.
_wh_show_version() {
  if [ "$WH_JSON" = "1" ]; then
    wh_json_out "{\"version\":$(wh_json_str "$WH_VERSION")}"
  else
    printf 'worktree-harness %s\n' "$WH_VERSION"
  fi
  exit 0
}

# _wh_prescan_help <cmd> <max|rest> <spec> <arg...> — settle the output mode, then
# help wins over any other error and version over the rest, so look before parsing.
# Stops at "--"; in rest mode also at the first positional, because everything from
# there on belongs to the wrapped command.
_wh_prescan_help() {
  local cmd="$1" max="$2" spec="$3" a help=0 version=0 json=0
  shift 3
  for a in "$@"; do
    case "$a" in
      --)                      break ;;
      -h|--help)               help=1 ;;
      -v|--version)            version=1 ;;
      --json|--json=true)      json=1 ;;
      --no-json|--json=false)  json=0 ;;
      -?*)                     ;;
      *)                       if [ "$max" = "rest" ]; then break; fi ;;
    esac
  done
  if [ "$json" = "1" ] && _wh_opt_classify --json "$spec" && [ "$_WH_OPT_TAKES" = "0" ]; then
    WH_JSON=1
  fi
  if [ "$help" = "1" ]; then
    if [ "$json" = "1" ] && declare -F _wh_help_json >/dev/null; then
      WH_JSON=1
      wh_flush_pending_warnings
      _wh_help_json "$cmd"
      exit 0
    fi
    wh_flush_pending_warnings
    _wh_show_help "$cmd"
  fi
  if [ "$version" = "1" ]; then
    if [ "$json" = "1" ]; then WH_JSON=1; fi
    wh_flush_pending_warnings
    _wh_show_version
  fi
  wh_flush_pending_warnings
}

# _wh_opt_classify <name> <spec> — find an option. On success sets _WH_OPT_TAKES
# (1 if it takes a value), _WH_OPT_VAR (empty for a built-in, which _wh_opt_builtin
# applies) and _WH_OPT_NEG (1 if <name> is the negation of a boolean: --no-x for
# --x, or --x for --no-x). Add a built-in in _wh_opt_lookup and _wh_opt_builtin.
_wh_opt_classify() {
  _WH_OPT_NEG=0
  if _wh_opt_lookup "$1" "$2"; then return 0; fi
  case "$1" in
    --no-help|--no-version|--no-no-*) return 1 ;;
    --no-*) _wh_opt_lookup "--${1#--no-}" "$2" || return 1 ;;
    --*)    _wh_opt_lookup "--no-${1#--}" "$2" || return 1 ;;
    *)      return 1 ;;
  esac
  if [ "$_WH_OPT_TAKES" = "1" ]; then return 1; fi
  _WH_OPT_NEG=1
}

# _wh_opt_lookup <name> <spec> — the exact-name half of _wh_opt_classify.
_wh_opt_lookup() {
  local IFS=' ' _wh_entry _wh_names
  _WH_OPT_TAKES=0; _WH_OPT_VAR=""
  case "$1" in
    *'|'*) return 1 ;;   # would match across the alternatives of a spec entry
    -h|--help|-v|--version|--dry-run|--no-color) return 0 ;;
    -C|--cwd) _WH_OPT_TAKES=1; return 0 ;;
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

# _wh_opt_builtin <cmd> <name> <value> — apply a built-in option. A boolean's
# <value> is 1 or 0 for the spelling in the first pattern of its case.
_wh_opt_builtin() {
  case "$2" in
    -h|--help)    if [ "$3" = "1" ]; then _wh_show_help "$1"; fi ;;
    -v|--version) if [ "$3" = "1" ]; then _wh_show_version; fi ;;
    --dry-run|--no-dry-run) WH_DRY_RUN="$3"; export WH_DRY_RUN ;;
    --no-color|--color)     WH_NO_COLOR="$3"; export WH_NO_COLOR; wh_init_style ;;
    -C|--cwd)
      if [ -z "$3" ]; then wh_usage_die "$1" "Option $2 needs a value."; fi
      CDPATH='' cd -- "$3" >/dev/null 2>&1 || wh_die "Can't change to directory $3." ;;
  esac
}

# wh_parse_opts <cmd> <max-positionals|rest> "<spec>" -- "$@"
#   spec: space-separated "a|b=VAR" (boolean) or "a|b=VAR:" (takes a value: --a v or
#   --a=v), with the dashes in the names: "--all|-a=all --base=base:"
#   A boolean sets VAR=1; --a=true and --a=false set 1 and 0, --no-a sets 0. An entry
#   spelled --no-x takes --x as its negation.
#   Built-ins, in every command: -h|--help, -v|--version, -C|--cwd <DIR>, --dry-run,
#   --no-color. A declared --json turns on WH_JSON. __WH_PARSE_ONLY=1 exits 0 here.
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
  _wh_prescan_help "$_wh_cmd" "$_wh_max" "$_wh_spec" "$@"

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
      wh_usage_die "$_wh_cmd" "Unknown option $_wh_name for worktree-harness $_wh_cmd." unknown_option
    fi

    if [ "$_WH_OPT_TAKES" = "1" ]; then
      if [ "$_wh_has_value" = "0" ]; then
        if [ $# -eq 0 ]; then wh_usage_die "$_wh_cmd" "Option $_wh_name needs a value."; fi
        _wh_value="$1"; shift
        # In rest mode the first prescan stopped at this value, seen as a positional.
        if [ "$_wh_max" = "rest" ]; then
          _wh_prescan_help "$_wh_cmd" "$_wh_max" "$_wh_spec" "$@"
          _wh_opt_classify "$_wh_name" "$_wh_spec"
        fi
      fi
    else
      if [ "$_wh_has_value" = "0" ]; then _wh_value=true; fi
      case "$_wh_value" in
        true)  _wh_value=1 ;;
        false) _wh_value=0 ;;
        *)     wh_usage_die "$_wh_cmd" "Option $_wh_name takes true or false." ;;
      esac
      if [ "$_WH_OPT_NEG" = "1" ]; then _wh_value=$((1 - _wh_value)); fi
    fi

    if [ -n "$_WH_OPT_VAR" ]; then
      printf -v "$_WH_OPT_VAR" '%s' "$_wh_value"
    else
      _wh_opt_builtin "$_wh_cmd" "$_wh_name" "$_wh_value"
    fi
  done
  if [ "${__WH_PARSE_ONLY:-}" = "1" ]; then exit 0; fi
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
  if [ "$WH_JSON" = "1" ]; then
    printf '%s\n' '{"status":"error","reason":"canceled","message":"Canceled.","data":{"remote":"none"}}' >&2
    exit "$2"
  fi
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
