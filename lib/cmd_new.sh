#!/usr/bin/env bash
# cmd_new.sh — create a fully-runnable worktree for a parallel session.
# Generalizes reso's new-worktree.sh. The reusable primitive is
# wh_create_worktree (echoes the path on stdout); `launch` reuses it.

_wh_new_usage() {
  cat >&2 <<'EOF'
worktree-harness new <branch>

Create a git worktree for <branch>, branched off the base (origin/<default> or
local <default>, per HARNESS_BASE_POLICY), then make it runnable: copy the
gitignored files in HARNESS_COPY, run the install command, assign non-colliding
ports (written to <worktree>/.harness.env), and run HARNESS_SETUP.

Refuses to reuse an existing branch or the default branch. Honors --dry-run.
EOF
}

# wh_create_worktree <branch> — create + provision a worktree. Echoes the
# resulting path on STDOUT; all progress goes to STDERR so the path is cleanly
# capturable by callers (e.g. `launch`).
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
  mkdir -p "$(dirname "$path")"
  wh_step "git worktree add $path -b $branch $base"
  if [ "${WH_DRY_RUN:-0}" = "1" ]; then printf '%s\n' "$path"; return 0; fi
  # git's chatter goes to stderr so this function's stdout is ONLY the path
  # (callers like `launch` capture it).
  git worktree add "$path" -b "$branch" "$base" >&2 || wh_die "git worktree add failed"
  wh_git_exclude ".harness.env"    # keep our generated env file out of merge/gc gates

  wh_copy_files "$path"
  wh_run_install "$path"
  wh_assign_ports "$path"
  wh_run_setup "$path"
  printf '%s\n' "$path"
}

# Copy gitignored runtime files (HARNESS_COPY) from the main checkout. Copy, not
# symlink — divergence between worktrees is intentional, and a symlinked local
# DB invites WAL corruption. Secrets get tightened to 0600.
wh_copy_files() {
  local path="$1" root f n=0
  [ "${#HARNESS_COPY[@]}" -eq 0 ] && return 0
  root="$(wh_repo_root)"
  for f in "${HARNESS_COPY[@]}"; do
    if [ -e "$root/$f" ]; then
      mkdir -p "$(dirname "$path/$f")"
      cp -R "$root/$f" "$path/$f"
      case "$f" in .env|.env.*|*.env|*.env.*) chmod 0600 "$path/$f" 2>/dev/null || true ;; esac
      n=$((n + 1))
    else
      wh_warn "copy: '$f' not found in repo root — skipped"
    fi
  done
  [ "$n" -gt 0 ] && wh_ok "copied $n gitignored file(s)"
  return 0
}

# Resolve + run the install command (HARNESS_INSTALL / detected PM) in the
# worktree, non-interactively (CI=true unless the caller already set CI).
wh_run_install() {
  local path="$1" root cmd
  root="$(wh_repo_root)"
  cmd="$(wh_resolve_install "$root")"
  [ -z "$cmd" ] && { wh_info "  (no install step)"; return 0; }
  wh_step "install: $cmd"
  [ "${WH_DRY_RUN:-0}" = "1" ] && return 0
  ( cd "$path" && export CI="${CI:-true}" && eval "$cmd" ) >&2 || wh_die "install failed: $cmd"
}

# Offset = number of OTHER worktrees, so concurrent worktrees get distinct ports.
wh_worktree_offset() {
  local n; n="$(git worktree list --porcelain | grep -c '^worktree ' || true)"
  if [ "${n:-0}" -gt 0 ]; then echo $(( n - 1 )); else echo 0; fi
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
  local path="$1" offset envf spec name base
  [ "${#HARNESS_PORTS[@]}" -eq 0 ] && return 0
  offset="$(wh_worktree_offset)"
  envf="$path/.harness.env"
  : > "$envf"
  for spec in "${HARNESS_PORTS[@]}"; do
    name="${spec%%=*}"; base="${spec#*=}"
    case "$base" in ''|*[!0-9]*) wh_warn "ports: '$spec' base not numeric — skipped"; continue ;; esac
    printf 'export %s=%s\n' "$name" "$(( base + offset ))" >> "$envf"
  done
  wh_ok "ports offset by $offset → $envf (source it before your dev server)"
}

# Run each HARNESS_SETUP command in the worktree, with .harness.env sourced.
wh_run_setup() {
  local path="$1" cmd
  [ "${#HARNESS_SETUP[@]}" -eq 0 ] && return 0
  for cmd in "${HARNESS_SETUP[@]}"; do
    wh_step "setup: $cmd"
    [ "${WH_DRY_RUN:-0}" = "1" ] && continue
    # shellcheck source=/dev/null
    ( cd "$path" && { [ -f .harness.env ] && . ./.harness.env || :; } && eval "$cmd" ) >&2 \
      || wh_die "setup step failed: $cmd"
  done
  wh_ok "setup complete"
}

_wh_new_next_steps() {
  local path="$1" def; def="$(wh_default_branch)"
  {
    printf '\nNext:\n'
    printf '  cd %s\n' "$path"
    printf '  %s                  # launch your agent here\n' "$HARNESS_AGENT"
    printf '  worktree-harness merge       # rebase onto %s, gate, fast-forward %s (never pushes)\n' "$def" "$def"
    printf '  worktree-harness gc --prune  # reap merged + idle worktrees (branch kept)\n'
  } >&2
}

wh_cmd_new() {
  local branch=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) _wh_new_usage; return 0 ;;
      --dry-run) WH_DRY_RUN=1 ;;
      --) shift; break ;;
      -*) wh_die "new: unknown flag '$1'" ;;
      *)  if [ -z "$branch" ]; then branch="$1"; else wh_die "new: unexpected argument '$1'"; fi ;;
    esac
    shift
  done
  [ -n "$branch" ] || { _wh_new_usage; wh_die "new: a branch name is required"; }
  wh_load_config
  local path; path="$(wh_create_worktree "$branch")"
  printf '%s\n' "$path"                       # stdout: the path (capturable)
  wh_ok "worktree ready: $path  (branch: $branch)"
  _wh_new_next_steps "$path"
}
