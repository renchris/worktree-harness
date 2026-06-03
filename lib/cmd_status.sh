#!/usr/bin/env bash
# cmd_status.sh — list worktrees with branch, ahead/behind vs the default
# branch, dirty flag, and the ports assigned in each worktree's .harness.env.
#
# Zero-dependency: pure git + awk (no jq). The result is the command's output,
# so it goes to STDOUT (pipeable); only warnings go to stderr. --porcelain emits
# tab-separated rows for scripts/CI.

_wh_status_usage() {
  cat >&2 <<'EOF'
worktree-harness status [--porcelain]

List every worktree: branch (+'*' if dirty), ahead/behind the default branch,
assigned ports (from <worktree>/.harness.env), and path.
--porcelain prints tab-separated rows: kind<TAB>branch<TAB>+ahead/-behind<TAB>ports<TAB>path
EOF
}

wh_cmd_status() {
  local porcelain=0
  case "${1:-}" in
    --porcelain) porcelain=1 ;;
    ""|--human)  ;;
    -h|--help)   _wh_status_usage; return 0 ;;
    *)           wh_die "status: unknown argument '$1'" ;;
  esac
  wh_load_config

  local main def wts count=0
  main="$(wh_repo_root)"
  def="$(wh_default_branch)"
  wts="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')"

  [ "$porcelain" = "0" ] && printf '%s%-24s %-11s %-15s %s%s\n' \
    "$WH_C_DIM" "BRANCH" "AHEAD/BEH" "PORTS" "PATH" "$WH_C_RESET"

  while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    br="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
    [ -z "$br" ] && br="detached"
    dirty=""
    [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] && dirty="*"

    kind="linked"; [ "$wt" = "$main" ] && kind="main"

    ab="-"
    if [ "$br" != "detached" ] && [ "$br" != "$def" ]; then
      a="$(git -C "$main" rev-list --count "$def..$br" 2>/dev/null || echo 0)"
      b="$(git -C "$main" rev-list --count "$br..$def" 2>/dev/null || echo 0)"
      ab="+$a/-$b"
    fi

    ports="-"
    if [ -f "$wt/.harness.env" ]; then
      ports="$(awk -F= '/^export /{sub(/^export /,""); printf "%s%s", sep, $2; sep=","}' "$wt/.harness.env" 2>/dev/null || true)"
      [ -z "$ports" ] && ports="-"
    fi

    if [ "$porcelain" = "1" ]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$br$dirty" "$ab" "$ports" "$wt"
    else
      printf '%-24s %-11s %-15s %s\n' "$br$dirty" "$ab" "$ports" "$wt"
    fi
    count=$((count + 1))
  done <<EOF
$wts
EOF

  if [ "$porcelain" = "0" ]; then
    printf '%s(%d worktrees · base: %s · '\''*'\'' = uncommitted)%s\n' "$WH_C_DIM" "$count" "$def" "$WH_C_RESET"
  fi
}
