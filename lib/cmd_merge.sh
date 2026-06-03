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
  cat >&2 <<'EOF'
worktree-harness merge [--no-verify]

From inside a worktree, land its branch onto the LOCAL default branch:
  1. rebase the branch onto the base (origin/<default> or local <default>),
  2. verify the default branch is an ancestor of the rebased branch,
  3. run HARNESS_MERGE_GATE (skip with --no-verify),
  4. fast-forward the default branch (ref-only when it isn't checked out).
Never pushes. Honors --dry-run.
EOF
}

wh_cmd_merge() {
  local skip_verify=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)   _wh_merge_usage; return 0 ;;
      --no-verify) skip_verify=1 ;;
      --dry-run)   WH_DRY_RUN=1 ;;
      *)           wh_die "merge: unknown argument '$1'" ;;
    esac
    shift
  done
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
    return 0
  fi

  local base; base="$(wh_base_ref)"          # may fetch (stderr); echoes ref on stdout
  wh_info "── $branch → $def  (base: $base) ──"
  git --no-pager log --oneline --reverse "$base..$branch" 2>/dev/null | sed 's/^/   + /' >&2 || true

  # Where is the default branch checked out (if anywhere)?
  local def_wt
  def_wt="$(git worktree list --porcelain | awk -v b="branch refs/heads/$def" '
    /^worktree /{w=$2} $0==b{print w}')"

  if [ "${WH_DRY_RUN:-0}" = "1" ]; then
    wh_info "dry-run: rebase onto $base → ancestry gate → $([ "$skip_verify" = 1 ] && echo 'skip gate' || echo "gate: ${HARNESS_MERGE_GATE}") → ff $def"
    if [ -n "$def_wt" ]; then wh_info "        (ff in-tree at $def_wt)"; else wh_info "        (ref-only ff; $def checked out nowhere)"; fi
    return 0
  fi

  wh_step "rebase $branch onto $base"
  if ! git rebase "$base"; then
    wh_err "rebase hit a conflict git/rerere could not auto-resolve — $def NOT touched."
    wh_info "  resolve here, then: git rebase --continue && worktree-harness merge"
    wh_info "  or bail entirely:   git rebase --abort"
    exit 2
  fi

  # Ancestry gate — never move the default branch unless it is strictly behind.
  git merge-base --is-ancestor "$def" "$branch" \
    || wh_die "post-rebase ancestry check failed — refusing to move $def ($def has commits not in $branch; the base diverged)."

  if [ "$skip_verify" = "1" ]; then
    wh_warn "--no-verify — skipping the merge gate."
  elif [ "$HARNESS_MERGE_GATE" = "none" ]; then
    : # no gate configured
  else
    wh_step "merge gate: $HARNESS_MERGE_GATE"
    eval "$HARNESS_MERGE_GATE" \
      || wh_die "merge gate failed on the rebased tree — $def NOT updated. Fix, commit, re-run."
  fi

  if [ -n "$def_wt" ]; then
    wh_step "$def is checked out at $def_wt — fast-forwarding there"
    git -C "$def_wt" merge --ff-only "$branch"
  else
    wh_step "$def is checked out nowhere — ref-only fast-forward (no working tree touched)"
    git fetch . "$branch:$def"
  fi
  wh_ok "$def now at $(git rev-parse --short "$def") — $branch landed. Local-only (never pushed)."
}
