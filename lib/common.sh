#!/usr/bin/env bash
# common.sh — shared version, color, logging, and prompt helpers.
# Sourced by the dispatcher and every command. bash 3.2-safe.
#
# All diagnostics go to STDERR so stdout stays clean for machine-readable
# output (`status --porcelain`, a captured worktree path, etc.).

# The values below are this tool's shared surface: assigned here, consumed by
# the dispatcher and command files that source this. shellcheck can't see that
# cross-file usage when linting this file in isolation, hence the disable.
# shellcheck disable=SC2034
WH_VERSION="0.2.0"

# Color only for an interactive stderr, unless disabled. Honors NO_COLOR
# (https://no-color.org) and an explicit WH_NO_COLOR=1.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${WH_NO_COLOR:-0}" != "1" ]; then
  WH_C_RED=$'\033[31m';   WH_C_GREEN=$'\033[32m'; WH_C_YELLOW=$'\033[33m'
  WH_C_BLUE=$'\033[34m';  WH_C_DIM=$'\033[2m';    WH_C_BOLD=$'\033[1m'
  WH_C_RESET=$'\033[0m'
else
  WH_C_RED=''; WH_C_GREEN=''; WH_C_YELLOW=''; WH_C_BLUE=''
  WH_C_DIM=''; WH_C_BOLD=''; WH_C_RESET=''
fi

wh_info() { printf '%s\n' "$*" >&2; }
wh_step() { printf '%s→%s %s\n'  "$WH_C_BLUE"   "$WH_C_RESET" "$*" >&2; }
wh_ok()   { printf '%s✓%s %s\n'  "$WH_C_GREEN"  "$WH_C_RESET" "$*" >&2; }
wh_warn() { printf '%s⚠%s %s\n'  "$WH_C_YELLOW" "$WH_C_RESET" "$*" >&2; }
wh_err()  { printf '%s✗%s %s\n'  "$WH_C_RED"    "$WH_C_RESET" "$*" >&2; }
wh_die()  { wh_err "$*"; exit 1; }

# wh_confirm <prompt> [default y|n] — TTY only; non-interactive uses the default.
wh_confirm() {
  local prompt="$1" def="${2:-n}" reply hint
  if [ ! -t 0 ]; then [ "$def" = "y" ]; return; fi
  if [ "$def" = "y" ]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s] ' "$prompt" "$hint" >&2
  read -r reply || reply=""
  [ -z "$reply" ] && reply="$def"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# wh_run <cmd...> — echo the command, then run it unless WH_DRY_RUN=1.
wh_run() {
  wh_step "$*"
  [ "${WH_DRY_RUN:-0}" = "1" ] && return 0
  "$@"
}
