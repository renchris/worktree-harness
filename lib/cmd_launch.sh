#!/usr/bin/env bash
# cmd_launch.sh — the always-isolate launcher. Generalizes reso's
# _cc_route_check + claude() wrapper.
#
# From the MAIN checkout (.git is a directory): create a fresh auto-named
# worktree off the base and exec the agent there. From a linked worktree (.git
# is a file) or outside a repo: exec in place — never nest. If worktree creation
# fails on the main checkout, REFUSE to launch un-isolated (set WH_ISOLATION_SKIP=1
# to override). The isolation is structural: each worktree has its own git index,
# so parallel sessions can't sweep each other's staged files.

_wh_launch_usage() {
  cat <<'EOF'
Usage:
  worktree-harness launch [options] [-- <COMMAND> [<ARG>]...]

Create an auto-named worktree off the base branch and start your agent in it.

Global Options:
  worktree-harness --help

Examples:
    worktree-harness launch
    worktree-harness launch -- <COMMAND>

Notes:
  With no command, this runs the HARNESS_AGENT setting from .harnessrc
  (default: claude). From a linked worktree (already isolated) or outside a git
  repository, the command runs in place.

  WH_ISOLATION_SKIP=1 runs in place on the main checkout too, with no worktree.
  Empty or unset means isolate, and a failed isolation refuses to launch.

  WH_NO_FETCH=1 uses the last-known remote ref instead of fetching. Empty or
  unset means fetch.

  To create a named worktree without starting an agent, use
  worktree-harness new <BRANCH>.
EOF
}

# Auto branch name: <prefix>-<HHMMSS>-<pid> — unique per shell/pane.
wh_autobranch() { printf '%s-%s-%s\n' "$HARNESS_BRANCH_PREFIX" "$(date +%H%M%S)" "$$"; }

# Replace this process with the agent (so TTY/signals behave). Dry-run prints.
wh_exec_agent() {
  [ "$#" -gt 0 ] || wh_die "launch: no command to run (HARNESS_AGENT is empty)."
  if [ "${WH_DRY_RUN:-0}" = "1" ]; then wh_info "dry-run: would exec: $*"; return 0; fi
  exec "$@"
}

wh_cmd_launch() {
  local agent_cmd=()
  wh_parse_opts launch rest "" -- "$@"
  agent_cmd=(${WH_ARGS[@]+"${WH_ARGS[@]}"})

  wh_load_config
  if [ "${#agent_cmd[@]}" -eq 0 ]; then
    # HARNESS_AGENT may be multi-word; word-split it intentionally, without letting
    # glob characters expand against the current directory.
    set -f
    # shellcheck disable=SC2206
    agent_cmd=($HARNESS_AGENT)
    set +f
  fi
  [ "${#agent_cmd[@]}" -gt 0 ] || wh_die "launch: no agent command (HARNESS_AGENT is empty and none was given)."

  local top; top="$(git rev-parse --show-toplevel 2>/dev/null || true)"

  # Outside a repo → exec in place.
  if [ -z "$top" ]; then wh_exec_agent "${agent_cmd[@]}"; return; fi
  # Linked worktree (.git is a FILE) → already isolated, exec in place.
  if [ -f "$top/.git" ]; then
    wh_step "Launching in place, since this is already a linked worktree…"
    wh_exec_agent "${agent_cmd[@]}"; return
  fi
  # Explicit override → exec un-isolated on the main checkout.
  if [ "${WH_ISOLATION_SKIP:-0}" = "1" ]; then
    wh_warn "WH_ISOLATION_SKIP=1 — launching un-isolated on the main checkout"
    wh_exec_agent "${agent_cmd[@]}"; return
  fi

  # Main checkout → isolate first, then exec inside the new worktree.
  local branch path
  branch="$(wh_autobranch)"
  # shellcheck disable=SC2034  # read by wh_create_worktree in cmd_new.sh
  WH_FAIL_HINT="Refusing to launch un-isolated (WH_ISOLATION_SKIP=1 to override)."
  wh_create_worktree "$branch"
  path="$WH_WT_PATH"
  if [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_info "dry-run: would isolate in $path (branch: $branch)"
    wh_exec_agent "${agent_cmd[@]}"; return
  fi
  [ -d "$path" ] || wh_die "worktree isolation failed — path not created. Refusing to launch un-isolated."
  wh_ok "isolated session: $path  (branch: $branch)"
  cd "$path" || wh_die "cannot cd to $path"
  wh_exec_agent "${agent_cmd[@]}"
}
