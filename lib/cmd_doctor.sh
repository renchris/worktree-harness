#!/usr/bin/env bash
# cmd_doctor.sh — diagnose the environment and validate .harnessrc. Designed to
# keep going and REPORT a broken .harnessrc rather than die on it.

_wh_doctor_usage() {
  cat <<'EOF'
Usage: worktree-harness doctor [options]
Diagnose the environment and validate .harnessrc.

Global Options: worktree-harness --help

Examples:
    worktree-harness doctor

Notes:
  Exits with the number of blocking issues; 0 means none.

Learn more: https://github.com/renchris/worktree-harness#readme
EOF
}

# _wh_doctor_verdict <issues> — the closing line.
_wh_doctor_verdict() {
  if [ "$1" -eq 0 ]; then wh_ok "doctor: no blocking issues"
  else wh_err "doctor: $(wh_plural "$1" issue issues) above"; fi
}

wh_cmd_doctor() {
  wh_parse_opts doctor 0 "" -- "$@"

  local issues=0 line
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
    _wh_doctor_verdict "$issues"
    return "$issues"
  fi
  wh_ok "repo: $root"

  wh_set_defaults
  local rc="$root/.harnessrc" load_err
  if [ -f "$rc" ]; then
    # Only the file's stderr is relayed, never the values it assigns.
    # shellcheck source=/dev/null
    if load_err="$( ( set +e; . "$rc" ) 2>&1 >/dev/null )"; then
      wh_ok ".harnessrc loads cleanly"
      # shellcheck source=/dev/null
      set +e; . "$rc" >/dev/null 2>&1; set -e
    else
      wh_err ".harnessrc fails to load:"
      if [ -n "$load_err" ]; then
        while IFS= read -r line; do
          wh_info "    $line"
        done <<< "$(printf '%s\n' "$load_err" | wh_sanitize_stream)"
      fi
      wh_info "  Fix the error (try: bash -n $rc)"
      issues=$((issues + 1))
    fi
  else
    wh_info "  no .harnessrc — using defaults (scaffold one with: worktree-harness init)"
  fi

  while IFS= read -r line; do
    if [ -n "$line" ]; then wh_err "$line"; issues=$((issues + 1)); fi
  done <<< "$(wh_config_problems)"
  while IFS= read -r line; do
    if [ -n "$line" ]; then wh_warn "$line"; fi
  done <<< "$(wh_config_warnings)"

  local def pm install
  def="$(wh_default_branch 2>/dev/null || true)"
  if [ "$HARNESS_PACKAGE_MANAGER" = "auto" ]; then pm="$(wh_detect_pm "$root")"; else pm="$HARNESS_PACKAGE_MANAGER"; fi
  # An unknown package manager was already reported by wh_config_warnings above.
  install="$(wh_resolve_install "$root" 2>/dev/null)"
  wh_info "  base policy   : $HARNESS_BASE_POLICY"
  wh_info "  default branch: ${def:-unknown}"
  wh_info "  remote        : $HARNESS_REMOTE"
  wh_info "  worktree home : $HARNESS_WORKTREE_HOME"
  wh_info "  package mgr   : $pm  →  ${install:-(no install step)}"
  wh_info "  merge gate    : $HARNESS_MERGE_GATE"
  wh_info "  gc idle (min) : $HARNESS_GC_IDLE_MIN"

  if [ "$HARNESS_BASE_POLICY" = "origin" ] && ! git remote get-url "$HARNESS_REMOTE" >/dev/null 2>&1; then
    wh_warn "base policy is 'origin' but no '$HARNESS_REMOTE' remote — new/merge will fall back to local $def"
  fi

  _wh_doctor_verdict "$issues"
  return "$issues"
}
