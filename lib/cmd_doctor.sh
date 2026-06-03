#!/usr/bin/env bash
# cmd_doctor.sh — diagnose the environment and validate .harnessrc. Designed to
# keep going and REPORT a broken .harnessrc rather than die on it.

wh_cmd_doctor() {
  case "${1:-}" in
    -h|--help) wh_info "worktree-harness doctor — diagnose the environment and validate .harnessrc."; return 0 ;;
    "") ;;
    *) wh_die "doctor: unexpected argument '$1'" ;;
  esac

  local issues=0
  wh_info "${WH_C_BOLD}worktree-harness $WH_VERSION${WH_C_RESET}  ($(wh_os))"

  if wh_has git; then wh_ok "git $(git --version 2>/dev/null | awk '{print $3}')"
  else wh_err "git not found — required"; issues=$((issues + 1)); fi
  wh_ok "bash ${BASH_VERSION:-unknown}"

  if wh_has lsof; then wh_ok "lsof present — gc can detect worktrees open by a live process"
  else wh_warn "lsof not found — gc keeps worktrees it can't prove are unused"; fi
  if wh_has tmux; then wh_ok "tmux present (optional)"; else wh_info "  tmux not found (optional)"; fi

  local root; root="$(wh_repo_root 2>/dev/null || true)"
  if [ -z "$root" ]; then
    wh_warn "not inside a git repository — cd into your project to validate its config"
    if [ "$issues" -eq 0 ]; then wh_ok "doctor: no blocking issues"; else wh_err "doctor: $issues issue(s) above"; fi
    return "$issues"
  fi
  wh_ok "repo: $root"

  wh_set_defaults
  local rc="$root/.harnessrc"
  if [ -f "$rc" ]; then
    # shellcheck source=/dev/null
    if ( set +e; . "$rc" ) >/dev/null 2>&1; then
      wh_ok ".harnessrc loads cleanly"
      # shellcheck source=/dev/null
      set +e; . "$rc" >/dev/null 2>&1; set -e
    else
      wh_err ".harnessrc fails to load — fix the syntax error (try: bash -n $rc)"
      issues=$((issues + 1))
    fi
  else
    wh_info "  no .harnessrc — using defaults (scaffold one with: worktree-harness init)"
  fi

  case "$HARNESS_BASE_POLICY" in
    origin|local) ;;
    *) wh_err "HARNESS_BASE_POLICY invalid: '$HARNESS_BASE_POLICY' (want origin|local)"; issues=$((issues + 1)) ;;
  esac

  local def pm install
  def="$(wh_default_branch 2>/dev/null || true)"
  if [ "$HARNESS_PACKAGE_MANAGER" = "auto" ]; then pm="$(wh_detect_pm "$root")"; else pm="$HARNESS_PACKAGE_MANAGER"; fi
  install="$(wh_resolve_install "$root")"
  wh_info "  base policy   : $HARNESS_BASE_POLICY"
  wh_info "  default branch: ${def:-unknown}"
  wh_info "  remote        : $HARNESS_REMOTE"
  wh_info "  worktree home : $HARNESS_WORKTREE_HOME"
  wh_info "  package mgr   : $pm  →  ${install:-(no install step)}"
  wh_info "  merge gate    : $HARNESS_MERGE_GATE"

  if [ "$HARNESS_BASE_POLICY" = "origin" ] && ! git remote get-url "$HARNESS_REMOTE" >/dev/null 2>&1; then
    wh_warn "base policy is 'origin' but no '$HARNESS_REMOTE' remote — new/merge will fall back to local $def"
  fi

  if [ "$issues" -eq 0 ]; then wh_ok "doctor: no blocking issues"; else wh_err "doctor: $issues issue(s) above"; fi
  return "$issues"
}
