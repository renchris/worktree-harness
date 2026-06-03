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
  cat >&2 <<'EOF'
worktree-harness launch [-- <command> [args...]]

Create an auto-named worktree off the base branch and exec your agent inside it.
With no command, runs HARNESS_AGENT (default: claude). From inside a linked
worktree (already isolated) or outside a git repo, execs in place.

  WH_ISOLATION_SKIP=1   exec in place even on the main checkout (no worktree)
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
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) _wh_launch_usage; return 0 ;;
      --dry-run) WH_DRY_RUN=1 ;;
      --) shift; break ;;
      -*) wh_die "launch: unknown flag '$1'" ;;
      *)  break ;;
    esac
    shift
  done
  [ $# -gt 0 ] && agent_cmd=("$@")

  wh_load_config
  if [ "${#agent_cmd[@]}" -eq 0 ]; then
    # HARNESS_AGENT may be multi-word; word-split it intentionally.
    # shellcheck disable=SC2206
    agent_cmd=($HARNESS_AGENT)
  fi
  [ "${#agent_cmd[@]}" -gt 0 ] || wh_die "launch: no agent command (HARNESS_AGENT is empty and none was given)."

  local top; top="$(git rev-parse --show-toplevel 2>/dev/null || true)"

  # Outside a repo → exec in place.
  if [ -z "$top" ]; then wh_exec_agent "${agent_cmd[@]}"; return; fi
  # Linked worktree (.git is a FILE) → already isolated, exec in place.
  if [ -f "$top/.git" ]; then
    wh_info "→ already in a linked worktree — launching in place"
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
  path="$(wh_create_worktree "$branch")" \
    || wh_die "worktree isolation failed — refusing to launch un-isolated (WH_ISOLATION_SKIP=1 to override)."
  [ -d "$path" ] || wh_die "worktree isolation failed — path not created. Refusing to launch un-isolated."
  wh_ok "isolated session: $path  (branch: $branch)"
  if [ "${WH_DRY_RUN:-0}" = "1" ]; then wh_exec_agent "${agent_cmd[@]}"; return; fi
  cd "$path" || wh_die "cannot cd to $path"
  wh_exec_agent "${agent_cmd[@]}"
}
