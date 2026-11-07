#!/usr/bin/env bash
# cmd_new.sh — create a fully-runnable worktree for a parallel session.
# Generalizes reso's new-worktree.sh. The reusable primitive is
# wh_create_worktree (sets WH_WT_PATH); `launch` reuses it.

_wh_new_usage() {
  cat <<'EOF'
Usage:
  worktree-harness new <BRANCH> [options]

Create a runnable worktree for <BRANCH>, branched off the base branch.

Global Options:
  worktree-harness --help

Examples:
    worktree-harness new <BRANCH>
    worktree-harness new <BRANCH> --dry-run

Notes:
  Stdout carries only the worktree path, also with --dry-run, so
  path=$(worktree-harness new <BRANCH>) captures it.

  After branching, this copies the gitignored files in HARNESS_COPY, runs the
  install command, writes non-colliding ports to <worktree>/.harness.env and
  runs HARNESS_SETUP. HARNESS_* names are .harnessrc settings.

  An existing branch or the default branch is refused.

  WH_NO_FETCH=1 uses the last-known remote ref instead of fetching. Empty or
  unset means fetch.

  To create a worktree and start your agent in it in one step, use
  worktree-harness launch.
EOF
}

# wh_create_worktree <branch> — create + provision a worktree and set WH_WT_PATH.
# Run it as a statement, never inside $(...): errexit is off in a command
# substitution and the root signal trap doesn't reach it. Stdout stays clean, so
# progress and the output of git, install and setup all go to STDERR.
# WH_PARTIAL_* are read by the root signal trap in common.sh.
# shellcheck disable=SC2034
wh_create_worktree() {
  local branch="$1" def safe path base
  def="$(wh_default_branch)"
  case "$branch" in
    "$def"|main|master)
      wh_die "refusing to create a worktree on '$branch' — branch a NEW name for isolation." ;;
  esac
  safe="$(wh_safe_branch "$branch")"
  path="$(wh_worktree_path "$safe")"
  [ -e "$path" ] && wh_die "worktree path already exists: $path"
  git show-ref --verify --quiet "refs/heads/$branch" \
    && wh_die "branch '$branch' already exists — pick a new name (or: git branch -d $branch)."

  base="$(wh_base_ref)"            # may fetch (stderr); echoes the ref on stdout
  WH_WT_PATH="$path"
  if [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_step "would: git worktree add $path -b $branch $base"
    return 0
  fi
  # Braces matter: in a non-UTF-8 locale bash reads the ellipsis as part of the name.
  wh_step "Creating worktree $path on branch $branch from ${base}…"
  mkdir -p "$(dirname "$path")" \
    || wh_die "Couldn't create the directory for worktree $path.${WH_FAIL_HINT:+ $WH_FAIL_HINT}"
  git worktree add "$path" -b "$branch" "$base" >&2 \
    || wh_die "Couldn't create worktree $path for branch '$branch' (git's message is above).${WH_FAIL_HINT:+ $WH_FAIL_HINT}"
  WH_PARTIAL_PATH="$path"
  WH_PARTIAL_BRANCH="$branch"

  # The exclude keeps our generated env file out of merge/gc gates. errexit is off
  # throughout this list, so every step reports its own failure and returns 1.
  {
    wh_git_exclude ".harness.env" \
      && wh_copy_files "$path" \
      && wh_run_install "$path" \
      && wh_assign_ports "$path" \
      && wh_run_setup "$path"
  } || _wh_provision_failed "$path" "$branch"
  WH_PARTIAL_PATH=""
  WH_PARTIAL_BRANCH=""
}

# _wh_provision_failed <path> <branch> — the one error for a failed provisioning
# step: what was left behind and how to remove it. Exits 1.
_wh_provision_failed() {
  local quoted
  wh_err "Failed to provision worktree $1 (branch $2). The worktree and branch were left in place."
  wh_info "To remove them:"
  printf -v quoted '%q' "$1"
  wh_info "    git worktree remove --force $quoted"
  printf -v quoted '%q' "$2"
  wh_info "    git branch -D $quoted"
  if [ -n "${WH_FAIL_HINT:-}" ]; then wh_info "$WH_FAIL_HINT"; fi
  exit 1
}

# Copy gitignored runtime files (HARNESS_COPY) from the main checkout. Copy, not
# symlink — divergence between worktrees is intentional, and a symlinked local
# DB invites WAL corruption. Secrets are never readable by others, not even while
# they're being copied. Tries every file, then returns 1 if any failed.
wh_copy_files() {
  local path="$1" root f n=0 failed=0
  [ "${#HARNESS_COPY[@]}" -eq 0 ] && return 0
  root="$(wh_repo_root)"
  for f in "${HARNESS_COPY[@]}"; do
    if [ ! -e "$root/$f" ]; then
      wh_warn "copy: '$f' not found in repo root — skipped"
      continue
    fi
    if _wh_copy_one "$f" "$root/$f" "$path/$f"; then
      n=$((n + 1))
    else
      wh_info "copy failed: $f"
      failed=$((failed + 1))
    fi
  done
  if [ "$n" -gt 0 ]; then wh_ok "copied $(wh_plural "$n" file files)"; fi
  [ "$failed" -eq 0 ]
}

# _wh_copy_one <name> <src> <dst> — <name> decides whether this is a secret.
_wh_copy_one() {
  mkdir -p "$(dirname "$3")" || return 1
  case "$1" in
    .env|.env.*|*.env|*.env.*)
      ( umask 077; cp -R "$2" "$3" ) || return 1
      # On a directory, 0600 would remove the x bit that lets anyone enter it.
      if [ -f "$3" ]; then chmod 0600 "$3" || return 1; fi ;;
    *)
      cp -R "$2" "$3" || return 1 ;;
  esac
}

# Resolve + run the install command (HARNESS_INSTALL / detected PM) in the
# worktree, non-interactively (CI=true unless the caller already set CI).
wh_run_install() {
  local path="$1" root cmd
  root="$(wh_repo_root)"
  cmd="$(wh_resolve_install "$root")"
  [ -z "$cmd" ] && { wh_info "  (no install step)"; return 0; }
  wh_step "Installing dependencies: ${cmd}…"
  [ "${WH_DRY_RUN:-0}" = "1" ] && return 0
  if ! ( cd "$path" && export CI="${CI:-true}" && eval "$cmd" ) >&2; then
    wh_info "install failed: $cmd"
    return 1
  fi
}

# wh_worktree_offset <new-path> — the smallest offset >= 1 that no other linked
# worktree holds, so a removed worktree's ports are reused and live ones never are.
wh_worktree_offset() {
  local new_path list line wt off used="" first=1 k=1
  new_path="$(cd "$1" && pwd -P)" || return 1   # git lists resolved paths
  list="$(git worktree list --porcelain)" || return 1
  while IFS= read -r line; do
    case "$line" in "worktree "*) ;; *) continue ;; esac
    wt="${line#worktree }"
    if [ "$first" = "1" ]; then first=0; continue; fi   # the main checkout is listed first
    if [ "$wt" = "$new_path" ]; then continue; fi
    off="$(_wh_env_offset "$wt/.harness.env")"
    if [ -n "$off" ]; then used="$used $off"; fi
  done <<< "$list"
  while :; do
    case " $used " in
      *" $k "*) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$k"
}

# _wh_env_offset <env-file> — the offset a .harness.env holds, if any. A file from
# before the "# harness-offset=" marker gives its first export minus that name's
# base in HARNESS_PORTS.
_wh_env_offset() {
  local line name value spec
  [ -r "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "# harness-offset="*) printf '%s\n' "${line#"# harness-offset="}"; return 0 ;;
      "export "*=*)
        line="${line#export }"; name="${line%%=*}"; value="${line#*=}"
        case "$value" in ''|*[!0-9]*) return 0 ;; esac
        for spec in ${HARNESS_PORTS[@]+"${HARNESS_PORTS[@]}"}; do
          if [ "${spec%%=*}" = "$name" ]; then
            case "${spec#*=}" in ''|*[!0-9]*) return 0 ;; esac
            printf '%s\n' "$(( 10#$value - 10#${spec#*=} ))"
            return 0
          fi
        done
        return 0 ;;
    esac
  done < "$1"
}

# Ensure a pattern is git-ignored locally via info/exclude (never committed), so
# generated files like .harness.env don't trip merge's clean-tree gate or gc's
# dirty gate. info/exclude lives in the shared common dir — one entry covers
# every worktree.
wh_git_exclude() {
  local pat="$1" common exclude
  common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  common="$(cd "$common" 2>/dev/null && pwd)" || return 0
  exclude="$common/info/exclude"
  mkdir -p "$common/info"
  [ -f "$exclude" ] || : > "$exclude"
  grep -qxF "$pat" "$exclude" 2>/dev/null || printf '%s\n' "$pat" >> "$exclude"
}

# Write <worktree>/.harness.env with each HARNESS_PORTS entry offset, so the
# user (and HARNESS_SETUP) can `source .harness.env` before a dev server.
wh_assign_ports() {
  local path="$1" offset envf spec name base content mode newline=$'\n'
  [ "${#HARNESS_PORTS[@]}" -eq 0 ] && return 0
  offset="$(wh_worktree_offset "$path")" || { wh_info "Couldn't work out a port offset."; return 1; }
  envf="$path/.harness.env"
  content="# harness-offset=$offset"
  for spec in "${HARNESS_PORTS[@]}"; do
    name="${spec%%=*}"; base="${spec#*=}"
    case "$base" in ''|*[!0-9]*) wh_warn "ports: '$spec' base not numeric — skipped"; continue ;; esac
    content="$content${newline}export $name=$(( 10#$base + offset ))"
  done
  # Ports aren't secrets: the file keeps a plain file's mode, 0666 less the umask.
  mode="$(printf '%04o' "$(( 0666 & ~$(umask) ))")"
  if ! wh_atomic_write "$envf" "$mode" <<< "$content"; then
    wh_info "Couldn't write $envf."
    return 1
  fi
  wh_ok "ports offset by $offset → $envf (source it before your dev server)"
}

# Run each HARNESS_SETUP command in the worktree, with .harness.env sourced.
wh_run_setup() {
  local path="$1" cmd
  [ "${#HARNESS_SETUP[@]}" -eq 0 ] && return 0
  for cmd in "${HARNESS_SETUP[@]}"; do
    wh_step "Running setup: ${cmd}…"
    [ "${WH_DRY_RUN:-0}" = "1" ] && continue
    # shellcheck source=/dev/null
    if ! ( cd "$path" && { [ -f .harness.env ] && . ./.harness.env || :; } && eval "$cmd" ) >&2; then
      wh_info "setup step failed: $cmd"
      return 1
    fi
  done
  wh_ok "setup complete"
}

# Optional tips: WH_GUIDANCE_DISABLED hides them. The stdout path always prints.
_wh_new_next_steps() {
  local quoted def
  wh_guidance_enabled || return 0
  def="$(wh_default_branch)"
  printf -v quoted '%q' "$1"
  {
    printf '\nNext steps:\n'
    printf '  Go to the worktree:\n'
    printf '    cd %s\n' "$quoted"
    printf '  Start your agent:\n'
    printf '    %s\n' "$HARNESS_AGENT"
    printf '  Rebase, run the gate and fast-forward %s (never pushes):\n' "$def"
    printf '    worktree-harness merge\n'
    printf '  Remove merged, idle worktrees (branches are kept):\n'
    printf '    worktree-harness gc --prune\n'
  } >&2
}

wh_cmd_new() {
  wh_parse_opts new 1 "" -- "$@"
  local branch="${WH_ARGS[0]:-}"
  [ -n "$branch" ] || wh_usage_die new "Missing branch name."
  wh_load_config
  wh_require_repo new
  wh_create_worktree "$branch"
  printf '%s\n' "$WH_WT_PATH"                 # stdout: the path (capturable)
  if [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_info "dry-run: would create worktree $WH_WT_PATH (branch: $branch). Nothing changed."
    return 0
  fi
  wh_ok "worktree ready: $WH_WT_PATH  (branch: $branch)"
  _wh_new_next_steps "$WH_WT_PATH"
}
