#!/usr/bin/env bash
# cmd_merge.sh — land the current worktree's branch onto the LOCAL default
# branch, safely, in one command. Generalizes reso's merge-to-main.sh.
#
# The discipline (and the tool's differentiator): rebase onto the base so the
# landing is a true fast-forward, verify ancestry before moving anything, run a
# merge gate (HARNESS_MERGE_GATE) to catch semantic breakage a clean textual
# rebase hides, then fast-forward the LOCAL default branch. It NEVER pushes —
# pushing stays an explicit `git push` (avoids claude-squad's auto-push footgun,
# issue #122). Fails closed on any real conflict: stop, report, let a human decide.

_wh_merge_usage() {
  cat <<'EOF'
Usage:
  worktree-harness merge [options]

Land this worktree's branch on the LOCAL default branch. Never pushes.

Options:
  --dry-run     Show the steps and change nothing.
  --no-verify   Skip the merge gate.

Global Options:
  worktree-harness --help

Examples:
    worktree-harness merge
    worktree-harness merge --no-verify

Notes:
  Run it from inside a worktree. It rebases the branch onto the base (the
  remote's or the local default branch), checks that the default branch is an
  ancestor of the result, runs the merge gate, then fast-forwards the default
  branch. Only the ref moves when that branch isn't checked out anywhere.
  HARNESS_MERGE_GATE, a .harnessrc setting, names the gate.

  Stdout carries only the landed commit's full SHA, also when the branch had
  already landed, so sha=$(worktree-harness merge) captures it. At an
  interactive terminal the receipt shows a short SHA instead. --dry-run prints
  nothing on stdout.

  Exit codes: 0 landed or already landed; 1 error; 2 rebase conflict (resolve
  it, or run git rebase --abort).

  WH_NO_FETCH=1 uses the last-known remote ref instead of fetching. Empty or
  unset means fetch.
EOF
}

wh_cmd_merge() {
  local skip_verify=0 nl=$'\n'
  wh_parse_opts merge 0 "--no-verify=skip_verify" -- "$@"
  wh_require_repo merge
  wh_load_config

  local branch def
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  def="$(wh_default_branch)"
  case "$branch" in
    "$def"|main|master) wh_die "you are ON '$branch' — run merge from your session branch." ;;
    HEAD)               wh_die "detached HEAD — 'git switch <your-branch>' first." ;;
  esac

  if [ -n "$(git status --porcelain)" ]; then
    wh_err "uncommitted changes — commit them (explicit paths) before landing:"
    git status -s >&2
    exit 1
  fi
  git rev-parse --verify --quiet "$def" >/dev/null || wh_die "no local '$def' branch in this repo."

  if git merge-base --is-ancestor "$branch" "$def"; then
    wh_ok "$def already contains $branch ($(git rev-parse --short "$def")) — nothing to do."
    if [ "${WH_DRY_RUN:-0}" != "1" ]; then wh_print_id "$(git rev-parse "$def")"; fi
    return 0
  fi

  local base; base="$(wh_base_ref)"          # may fetch (stderr); echoes ref on stdout
  wh_info "── $branch → $def  (base: $base) ──"
  git --no-pager log --no-decorate --format='%h %s' --reverse "$base..$branch" 2>/dev/null \
    | wh_sanitize_stream | sed 's/^/   + /' >&2 || true

  # Where is the default branch checked out (if anywhere)? substr, because a
  # worktree path can hold spaces.
  local def_wt
  def_wt="$(git worktree list --porcelain | awk -v b="branch refs/heads/$def" '
    /^worktree /{w=substr($0,10)} $0==b{print w}')"

  if [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_info "dry-run: rebase onto $base → ancestry gate → $([ "$skip_verify" = 1 ] && echo 'skip gate' || echo "gate: ${HARNESS_MERGE_GATE}") → ff $def"
    if [ -n "$def_wt" ]; then wh_info "        (ff in-tree at $def_wt)"; else wh_info "        (ref-only ff; $def checked out nowhere)"; fi
    return 0
  fi

  wh_step "Rebasing $branch onto ${base}…"
  if ! git rebase "$base" >&2; then
    wh_err "rebase hit a conflict git/rerere could not auto-resolve — $def NOT touched."
    wh_info "  resolve here, then: git rebase --continue && worktree-harness merge"
    wh_info "  or bail entirely:   git rebase --abort"
    exit 2
  fi

  # Ancestry gate — never move the default branch unless it is strictly behind.
  git merge-base --is-ancestor "$def" "$branch" \
    || wh_die "post-rebase ancestry check failed — refusing to move $def ($def has commits not in $branch; the base diverged)."

  local prepared="rebased"
  if [ "$skip_verify" = "1" ]; then
    wh_warn "--no-verify — skipping the merge gate."
  elif [ "$HARNESS_MERGE_GATE" = "none" ]; then
    : # no gate configured
  else
    wh_step "Running the merge gate: ${HARNESS_MERGE_GATE}…"
    if ! eval "$HARNESS_MERGE_GATE" >&2; then
      wh_err "merge gate failed on the rebased tree: $HARNESS_MERGE_GATE. $def was not updated."
      wh_info "Fix the failure, commit, then re-run:"
      wh_info "  worktree-harness merge"
      exit 1
    fi
    prepared="rebased and gated"
  fi

  if [ -n "$def_wt" ]; then
    wh_step "Fast-forwarding $def, checked out at ${def_wt}…"
    git -C "$def_wt" merge --ff-only "$branch" >&2 \
      || wh_die "Couldn't fast-forward $def at $def_wt to $branch (git's message is above). $branch is $prepared; $def is unchanged.${nl}Fix $def_wt, then finish the landing without repeating the rebase or the gate:${nl}    git -C $(printf %q "$def_wt") merge --ff-only $(printf %q "$branch")"
  else
    wh_step "Moving $def to $branch without touching a working tree…"
    git fetch . "$branch:$def" \
      || wh_die "Couldn't move $def to $branch (git's message is above). $branch is $prepared; $def is unchanged.${nl}Finish the landing without repeating the rebase or the gate:${nl}    git fetch . $(printf %q "$branch:$def")"
  fi
  wh_ok "$def now at $(git rev-parse --short "$def") — $branch landed. Local-only (never pushed)."
  wh_print_id "$(git rev-parse "$def")"
}
