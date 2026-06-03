#!/usr/bin/env bash
# cmd_gc.sh — safely sweep merged + clean + idle worktrees out of the filesystem.
# Generalizes reso's worktree-gc.sh.
#
# Removes ONLY worktrees that pass EVERY gate: clean tree, fully merged into the
# default branch, no busy marker, not open by a live process, and idle
# (> HARNESS_GC_IDLE_MIN). Everything else is KEPT with a printed reason.
# BRANCHES ARE ALWAYS PRESERVED — delete merged ones yourself with
# `git branch -d <branch>`. Default is dry-run; pass --prune to remove.

_wh_gc_usage() {
  cat >&2 <<'EOF'
worktree-harness gc [--prune]

Preview (default) or remove (--prune) worktrees that are clean + fully merged
into the default branch + idle. Branches are always preserved. Worktrees listed
in HARNESS_GC_KEEP, dirty/unmerged/busy/recently-touched ones, and the main
checkout are never removed.
EOF
}

# True if basename $1 is in HARNESS_GC_KEEP.
wh_gc_kept() {
  local b="$1" k
  [ "${#HARNESS_GC_KEEP[@]}" -eq 0 ] && return 1
  for k in "${HARNESS_GC_KEEP[@]}"; do [ "$k" = "$b" ] && return 0; done
  return 1
}

wh_cmd_gc() {
  local prune=0
  case "${1:-}" in
    --prune|--force) prune=1 ;;
    ""|--dry-run)    ;;
    -h|--help)       _wh_gc_usage; return 0 ;;
    *)               wh_die "gc: unknown argument '$1'" ;;
  esac
  wh_load_config

  local main def idle wts
  main="$(wh_repo_root)"
  def="$(wh_default_branch)"
  idle="$HARNESS_GC_IDLE_MIN"
  [ "$prune" = "0" ] && wh_info "DRY-RUN — pass --prune to remove. Branches are always preserved."
  wts="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')"

  # Here-string (not a pipe) keeps the loop in the current shell: predictable
  # under set -e, and no subshell scoping surprises.
  while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    [ "$wt" = "$main" ] && continue
    base="$(basename "$wt")"
    if wh_gc_kept "$base"; then wh_info "skip   $base — in HARNESS_GC_KEEP"; continue; fi
    br="$(git -C "$wt" branch --show-current 2>/dev/null || true)"

    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
      wh_info "KEEP   $base [${br:-detached}] — dirty (uncommitted work)"; continue
    fi
    if [ -f "$wt/.worktree-harness-busy" ]; then
      wh_info "KEEP   $base [${br:-detached}] — .worktree-harness-busy marker"; continue
    fi
    if wh_has lsof && lsof -- "$wt" 2>/dev/null | grep -q .; then
      wh_info "KEEP   $base [${br:-detached}] — open by a live process"; continue
    fi
    # idle=0 disables the recency gate. Skip the find entirely rather than rely
    # on `find -mmin -0`, whose meaning differs across BSD find builds.
    if [ "$idle" -gt 0 ] && [ -n "$(find "$wt" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -mmin "-$idle" 2>/dev/null | head -1)" ]; then
      wh_info "KEEP   $base [${br:-detached}] — modified <${idle} min ago"; continue
    fi
    if [ -z "$br" ]; then
      wh_info "KEEP   $base — detached HEAD (manual review)"; continue
    fi
    if ! git -C "$main" merge-base --is-ancestor "$br" "$def" 2>/dev/null; then
      n="$(git -C "$main" rev-list --count "$def..$br" 2>/dev/null || echo '?')"
      wh_info "KEEP   $base [$br] — $n commit(s) not in $def (merge first)"; continue
    fi

    if [ "$prune" = "1" ]; then
      if git worktree remove "$wt" 2>/dev/null; then
        wh_ok "removed $base [$br] — branch '$br' preserved"
      else
        wh_err "failed  $base — try manually: git worktree remove --force $wt"
      fi
    else
      wh_info "WOULD remove $base [$br] — clean + merged + idle"
    fi
  done <<EOF
$wts
EOF

  [ "$prune" = "1" ] && git worktree prune
  wh_info ""
  wh_info "Remaining worktrees:"
  git worktree list >&2
}
