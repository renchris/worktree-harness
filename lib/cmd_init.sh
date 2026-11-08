#!/usr/bin/env bash
# cmd_init.sh — scaffold a starter .harnessrc in the repo root, pre-filled with
# the detected package manager and documented defaults. Never overwrites.

_wh_init_usage() {
  cat <<'EOF'
Usage:
  worktree-harness init [options]

Write a starter .harnessrc in the repository root.

Options:
  --dry-run   Show what would be written and change nothing.

Global Options:
  worktree-harness --help

Examples:
    worktree-harness init
    worktree-harness init --dry-run

Notes:
  An existing .harnessrc is never overwritten: init stops with exit 1. The new
  file names the package manager detected from your lockfile.

  Stdout carries only the new file's path, so rc=$(worktree-harness init)
  captures it. At an interactive terminal the receipt shows the path instead.
  --dry-run prints nothing on stdout.
EOF
}

wh_cmd_init() {
  wh_parse_opts init 0 "" -- "$@"
  local root; root="$(wh_repo_root)" || wh_die "not inside a git repository."
  [ -n "$root" ] || wh_die "not inside a git repository."
  local rc="$root/.harnessrc"
  local exists_msg=".harnessrc already exists at $rc — edit it directly."
  # A dry run stops here too, so it never promises a write the real run refuses.
  if [ -e "$rc" ] || [ -h "$rc" ]; then wh_die "$exists_msg"; fi
  local pm; pm="$(wh_detect_pm "$root")"

  if [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_info "dry-run: would write $rc (detected package manager: $pm)"; return 0
  fi

  local write_status=0
  wh_write_new "$rc" <<EOF || write_status=$?
# .harnessrc — worktree-harness project config. Sourced as bash; treat it like a
# Makefile (only run worktree-harness in repos you trust). Every key is optional;
# the values shown are the defaults unless noted.

# Base-branch policy. "origin": fetch and branch off <remote>/<default>.
# "local": branch off the local <default> and never touch the network (use this
# when origin is a diverged fork and your local default branch is canonical).
HARNESS_BASE_POLICY="origin"
HARNESS_REMOTE="origin"
# HARNESS_DEFAULT_BRANCH=""           # blank = auto-detect (origin/HEAD, then main/master)

# Where worktrees are created: <home>/<repo>/<branch>.
HARNESS_WORKTREE_HOME="\$HOME/.worktrees"

# Gitignored runtime files copied (not symlinked) into each new worktree.
HARNESS_COPY=( ".env" ".env.local" )

# Package manager: "auto" detects from the lockfile. Detected here: ${pm}.
HARNESS_PACKAGE_MANAGER="auto"
# HARNESS_INSTALL="auto"              # "auto" = derive from PM; "none"; or a literal command

# Commands run inside the new worktree after install. Any HARNESS_PORTS
# (below) are exported into their environment via .harness.env.
HARNESS_SETUP=( )

# Per-worktree ports: "NAME=BASE" → NAME=BASE+offset, written to
# <worktree>/.harness.env so you can 'source .harness.env' before a dev server.
HARNESS_PORTS=( )                     # e.g. ( "PORT=3000" "INSPECT_PORT=9229" )

# Command that must pass before 'merge' fast-forwards the default branch.
HARNESS_MERGE_GATE="none"             # e.g. "npm run typecheck"

# Default agent that 'launch' execs inside the worktree.
HARNESS_AGENT="claude"

# Worktrees 'gc' must never reap (by basename), and the idle threshold (minutes).
HARNESS_GC_KEEP=( )
HARNESS_GC_IDLE_MIN="30"
EOF
  case "$write_status" in
    0) ;;
    1) wh_die "$exists_msg" ;;
    *) wh_die "Couldn't write $rc. Check that the repository root is writable, then re-run." ;;
  esac
  wh_print_id "$rc"
  wh_ok "wrote $rc (detected package manager: $pm)"
  wh_info "Review it, then create your first worktree: worktree-harness new my-feature"
}
