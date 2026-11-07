#!/usr/bin/env bash
# cmd_gc.sh — safely sweep merged + clean + idle worktrees out of the filesystem.
# Generalizes reso's worktree-gc.sh.
#
# Removes ONLY worktrees that pass EVERY gate: clean tree, fully merged into the
# default branch, no busy marker, not open by a live process, and idle
# (> HARNESS_GC_IDLE_MIN). Everything else is kept with a printed reason, and a
# gate that can't be evaluated keeps the worktree.
# BRANCHES ARE ALWAYS PRESERVED — delete merged ones yourself with
# `git branch -d <branch>`. Default is dry-run; pass --prune to remove. --dry-run
# beats --prune. --force is a deprecated spelling of --prune.

_wh_gc_usage() {
  cat <<'EOF'
Usage:
  worktree-harness gc [options]

Preview the worktrees that are ready to remove, or remove them with --prune.

Options:
  --dry-run    Preview only, even with --prune.
  --prune      Remove the worktrees that pass every check, without a prompt.
  -y, --yes    Accepted for scripts. gc doesn't prompt; --yes alone doesn't
               remove.

Global Options:
  worktree-harness --help

Examples:
    worktree-harness gc
    worktree-harness gc --prune
    worktree-harness gc --prune --yes

Notes:
  A worktree is removed only when it has no uncommitted changes, is fully
  merged into the default branch, has no .worktree-harness-busy marker, isn't
  open by a live process, and has been idle for HARNESS_GC_IDLE_MIN minutes.
  Any other worktree is kept and the reason printed. A check that can't run
  keeps the worktree.

  The main checkout and worktrees named in HARNESS_GC_KEEP are never removed.
  HARNESS_* names are .harnessrc settings.

  Branches are always preserved. Removing a worktree deletes its ignored files
  such as .env.

  With --prune, stdout carries the removed paths, one per line, only when every
  removal succeeded. A preview prints nothing on stdout.

  Exit codes: 0 when everything requested succeeded; 1 when a removal failed or
  gc can't run.
EOF
}

# True if basename $1 is in HARNESS_GC_KEEP.
wh_gc_kept() {
  local b="$1" k
  [ "${#HARNESS_GC_KEEP[@]}" -eq 0 ] && return 1
  for k in "${HARNESS_GC_KEEP[@]}"; do [ "$k" = "$b" ] && return 0; done
  return 1
}

# _wh_gc_remove_failed <worktree> <branch> <git's message> — the Failed row and how
# to recover.
_wh_gc_remove_failed() {
  local quoted
  printf -v quoted '%q' "$1"
  wh_err "Failed  $1 [$2]: ${3%%$'\n'*}"
  wh_info "  inspect: git -C $quoted status --ignored"
  case "$3" in
    *locked*) wh_info "  unlock: git worktree unlock $quoted" ;;
    *) wh_info "  force: git worktree remove --force $quoted (deletes ignored files such as .env, and uncommitted changes)" ;;
  esac
}

wh_cmd_gc() {
  local prune=0 force_alias=0
  # shellcheck disable=SC2034 # --yes is accepted and does nothing: gc doesn't prompt.
  local yes=0
  wh_parse_opts gc 0 "--force=force_alias --prune=prune --yes|-y=yes" -- "$@"
  if [ "$force_alias" = "1" ]; then
    wh_deprecated gc-force "gc --force" "gc --prune"
    prune=1
  fi
  wh_load_config
  wh_require_repo gc

  local main def idle wts wt base br st n err
  local find_err recent find_msg
  local cands=0 removed=0 failed=0 removed_paths=""
  main="$(wh_repo_root)"
  def="$(wh_default_branch)"
  idle="$HARNESS_GC_IDLE_MIN"
  if [ "$prune" = "1" ] && [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_info "--dry-run overrides --prune: nothing will be removed."
    prune=0
  elif [ "$prune" = "0" ]; then
    wh_info "DRY-RUN — pass --prune to remove. Branches are always preserved."
  fi
  wts="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')"

  # Here-string (not a pipe) keeps the loop in the current shell: predictable
  # under set -e, and no subshell scoping surprises.
  while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    [ "$wt" = "$main" ] && continue
    base="$(basename "$wt")"
    if wh_gc_kept "$base"; then wh_info "Keep    $wt — in HARNESS_GC_KEEP"; continue; fi
    br="$(git -C "$wt" branch --show-current 2>/dev/null || true)"

    if ! st="$(git -C "$wt" status --porcelain 2>&1)"; then
      wh_info "Keep    $wt [${br:-detached}] — couldn't check dirty state: ${st%%$'\n'*}"; continue
    fi
    if [ -n "$st" ]; then
      wh_info "Keep    $wt [${br:-detached}] — dirty (uncommitted work)"; continue
    fi
    if [ -f "$wt/.worktree-harness-busy" ]; then
      wh_info "Keep    $wt [${br:-detached}] — .worktree-harness-busy marker"; continue
    fi
    # No pipe into grep -q: it can exit first, and under pipefail lsof's SIGPIPE
    # would read as "not open".
    if wh_has lsof && [ -n "$(lsof -- "$wt" 2>/dev/null || true)" ]; then
      wh_info "Keep    $wt [${br:-detached}] — open by a live process"; continue
    fi
    # idle=0 disables the recency gate. Skip the find entirely rather than rely
    # on `find -mmin -0`, whose meaning differs across BSD find builds.
    if [ "$idle" -gt 0 ]; then
      if ! find_err="$(mktemp)"; then
        wh_info "Keep    $wt [${br:-detached}] — couldn't check recency: no temporary file"; continue
      fi
      # head may close the pipe on find under pipefail, hence || true. find's errors
      # go to a file, so one that reports no recent file can't pass as idle.
      recent="$(find "$wt" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -mmin "-$idle" 2>"$find_err" | head -1 || true)"
      find_msg="$(head -1 "$find_err" || true)"
      rm -f "$find_err"
      if [ -n "$find_msg" ]; then
        wh_info "Keep    $wt [${br:-detached}] — couldn't check recency: $find_msg"; continue
      fi
      if [ -n "$recent" ]; then
        wh_info "Keep    $wt [${br:-detached}] — modified <${idle} min ago"; continue
      fi
    fi
    if [ -z "$br" ]; then
      wh_info "Keep    $wt — detached HEAD (manual review)"; continue
    fi
    if ! git -C "$main" merge-base --is-ancestor "$br" "$def" 2>/dev/null; then
      n="$(git -C "$main" rev-list --count "$def..$br" 2>/dev/null || echo '?')"
      wh_info "Keep    $wt [$br] — $(wh_plural "$n" commit commits) not in $def (merge first)"; continue
    fi

    cands=$((cands + 1))
    if [ "$prune" = "1" ]; then
      if err="$(git worktree remove "$wt" 2>&1)"; then
        removed=$((removed + 1))
        removed_paths="${removed_paths:+$removed_paths$'\n'}$wt"
        wh_ok "Removed $wt [$br] — branch '$br' preserved"
      else
        failed=$((failed + 1))
        _wh_gc_remove_failed "$wt" "$br" "$err"
      fi
    else
      wh_info "Remove  $wt [$br] — clean + merged + idle"
    fi
  done <<EOF
$wts
EOF

  if [ "$prune" = "1" ]; then
    if ! git worktree prune; then
      wh_warn "Couldn't clear stale worktree records. Run git worktree prune to retry."
    fi
  fi
  if [ "$cands" -eq 0 ]; then
    wh_info "No worktrees are ready to remove."
  elif [ "$prune" = "1" ]; then
    wh_info "Removed $removed of $(wh_plural "$cands" worktree worktrees). $failed failed."
    if [ "$failed" -gt 0 ]; then
      wh_info "Removals are per worktree, not atomic; re-running gc --prune is safe."
    fi
  fi
  wh_info ""
  wh_info "Remaining worktrees"
  git worktree list >&2

  if [ "$failed" -eq 0 ] && [ -n "$removed_paths" ]; then
    wh_print_id "$removed_paths"
  fi
  [ "$failed" -eq 0 ]
}
