#!/usr/bin/env bash
# config.sh — locate the repo, load .harnessrc, apply defaults, validate, and
# derive runtime values. After wh_load_config, the HARNESS_* variables are
# populated in the calling shell.
#
# Config is a SHELL-SOURCED file (.harnessrc), not YAML. That is a deliberate
# choice: it needs zero parsing dependency (no `yq`), gets arrays and comments
# for free, and is the most portable option for a bash tool. The trust model is
# a Makefile's: only run worktree-harness in repos you trust. Every comparable
# tool runs repo-controlled shell the same way (worktrunk hooks, wtp
# post_create, uzi devCommand).

# Defaults are set BEFORE sourcing .harnessrc so a user file overrides cleanly
# and any absent key is still safe to read. Arrays start empty.
#
# These HARNESS_* vars are the tool's config surface — assigned here, consumed
# by command files that source this. shellcheck can't see that cross-file usage.
# shellcheck disable=SC2034
wh_set_defaults() {
  HARNESS_BASE_POLICY="origin"          # origin | local
  HARNESS_REMOTE="origin"
  HARNESS_DEFAULT_BRANCH=""             # "" → auto-detect (origin/HEAD, then main/master)
  HARNESS_WORKTREE_HOME="$HOME/.worktrees"
  HARNESS_BRANCH_PREFIX="wt"            # auto-named branches: <prefix>-<HHMMSS>-<pid>
  HARNESS_PACKAGE_MANAGER="auto"        # auto | pnpm|npm|yarn|bun|pip|pipenv|poetry|uv|cargo|go | none
  HARNESS_INSTALL="auto"                # auto (derive from PM) | none | "<command>"
  HARNESS_MERGE_GATE="none"             # none | "<command>" (e.g. "pnpm typecheck")
  HARNESS_AGENT="claude"                # what `launch` execs inside the worktree
  HARNESS_GC_IDLE_MIN="30"             # worktrees touched more recently than this are kept
  HARNESS_COPY=()                       # gitignored files copied into each new worktree
  HARNESS_SETUP=()                      # commands run inside the new worktree (post-install)
  HARNESS_PORTS=()                      # "NAME=BASE" → NAME exported as BASE+offset
  HARNESS_GC_KEEP=()                    # worktree basenames never reaped
}

# Repo root of the current directory (the main checkout / common-dir owner).
wh_repo_root() { git rev-parse --show-toplevel 2>/dev/null; }
wh_repo_name() { basename "$(wh_repo_root)"; }

# Path a worktree for safe-branch $1 should live at: <home>/<repo>/<branch>.
wh_worktree_path() {
  printf '%s/%s/%s\n' "$HARNESS_WORKTREE_HOME" "$(wh_repo_name)" "$1"
}

# Replace "/" with "-" so a slashed branch name maps to one path segment.
wh_safe_branch() { printf '%s\n' "${1//\//-}"; }

wh_load_config() {
  wh_set_defaults
  local root; root="$(wh_repo_root)" || true
  if [ -n "$root" ] && [ -f "$root/.harnessrc" ]; then
    local _pwd _status; _pwd="$(pwd)"
    # Source with `set +e` so a benign non-zero command mid-file (e.g. a
    # `command -v` probe) does not abort the whole run; a real failure still
    # surfaces via the final status.
    set +e
    # shellcheck source=/dev/null
    . "$root/.harnessrc"
    _status=$?
    set -e
    cd "$_pwd" 2>/dev/null || true
    [ "$_status" -eq 0 ] || wh_fail 1 invalid_config ".harnessrc failed to load (exit $_status). Run: worktree-harness doctor"
  fi
  wh_validate_config
}

# _wh_one_line <s> — <s> with newlines as spaces, so a value can't add a line.
_wh_one_line() { printf '%s' "${1//$'\n'/ }"; }

# wh_config_problems — one line per invalid key; these stop every command that
# loads the config. Never exits, so doctor can report them all.
wh_config_problems() {
  case "$HARNESS_BASE_POLICY" in
    origin|local) ;;
    *) printf "HARNESS_BASE_POLICY must be 'origin' or 'local' (got '%s')\n" "$(_wh_one_line "$HARNESS_BASE_POLICY")" ;;
  esac
  case "$HARNESS_GC_IDLE_MIN" in
    ''|*[!0-9]*) printf "HARNESS_GC_IDLE_MIN must be a whole number (got '%s')\n" "$(_wh_one_line "$HARNESS_GC_IDLE_MIN")" ;;
  esac
}

# wh_config_warnings — one line per suspect value that doesn't stop a command.
# Needs pm.sh for the list of package managers.
wh_config_warnings() {
  local spec
  if ! wh_pm_is_known "$HARNESS_PACKAGE_MANAGER"; then
    printf "HARNESS_PACKAGE_MANAGER '%s' is not a known package manager (known: %s)\n" \
      "$(_wh_one_line "$HARNESS_PACKAGE_MANAGER")" "$WH_PM_KNOWN"
  fi
  for spec in ${HARNESS_PORTS[@]+"${HARNESS_PORTS[@]}"}; do
    if ! [[ "$spec" =~ ^[A-Za-z_][A-Za-z0-9_]*=[0-9]+$ ]]; then
      printf "HARNESS_PORTS entry '%s' must look like NAME=BASE (for example PORT=3000)\n" "$(_wh_one_line "$spec")"
    fi
  done
}

wh_validate_config() {
  local p; p="$(wh_config_problems)"
  [ -z "$p" ] || wh_fail 1 invalid_config "${p%%$'\n'*}"
}

# Echo the default branch name. Explicit config wins; else origin/HEAD's target;
# else a local main/master; else the current branch.
wh_default_branch() {
  if [ -n "$HARNESS_DEFAULT_BRANCH" ]; then printf '%s\n' "$HARNESS_DEFAULT_BRANCH"; return; fi
  local ref b
  ref="$(git symbolic-ref --quiet "refs/remotes/$HARNESS_REMOTE/HEAD" 2>/dev/null || true)"
  if [ -n "$ref" ]; then printf '%s\n' "${ref#refs/remotes/"$HARNESS_REMOTE"/}"; return; fi
  for b in main master; do
    if git show-ref --verify --quiet "refs/heads/$b"; then printf '%s\n' "$b"; return; fi
  done
  git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# _wh_fetch_bounded <remote> <branch> — fetch without prompting, and give up on a
# stalled connection. Prints only git's stderr. Call it inside $(...), which keeps
# the exports out of the caller. A user's own ssh setup is left alone.
_wh_fetch_bounded() {
  export GIT_TERMINAL_PROMPT=0
  if [ -z "${GIT_SSH_COMMAND+x}" ] && [ -z "${GIT_SSH+x}" ] \
    && [ -z "$(git config core.sshCommand 2>/dev/null || true)" ]; then
    export GIT_SSH_COMMAND="ssh -o ConnectTimeout=10 -o BatchMode=yes"
  fi
  { git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 fetch --quiet "$1" "$2" >/dev/null; } 2>&1
}

# _wh_safe_url_text — stdin to stdout, without credentials in URLs or control bytes.
_wh_safe_url_text() { wh_sanitize_stream | sed 's#://[^/]*@#://#g'; }

# _wh_fetch_base <branch> — a failed fetch warns and the run continues on the
# last-known remote ref.
_wh_fetch_base() {
  local def="$1" err url first
  err="$(_wh_fetch_bounded "$HARNESS_REMOTE" "$def")" && return 0
  url="$(git remote get-url "$HARNESS_REMOTE" 2>/dev/null | _wh_safe_url_text || true)"
  first="$(printf '%s\n' "${err%%$'\n'*}" | _wh_safe_url_text)"
  wh_warn "Couldn't fetch $def from $HARNESS_REMOTE ($url): ${first:-git gave no error text}. Using last-known $HARNESS_REMOTE/$def."
}

# Echo the git ref to branch/rebase from, honoring base policy. For policy
# "origin" it fetches first (unless WH_NO_FETCH=1 or a dry run, since a fetch moves
# remote-tracking refs) and returns "<remote>/<branch>"; for "local" it returns the
# local branch and never touches the network. Falls back to local if policy=origin
# but the remote is absent. Progress goes to stderr so the captured stdout is only
# the ref.
wh_base_ref() {
  local def; def="$(wh_default_branch)"
  if [ "$HARNESS_BASE_POLICY" = "origin" ]; then
    if ! git remote get-url "$HARNESS_REMOTE" >/dev/null 2>&1; then
      wh_warn "base policy 'origin' but no '$HARNESS_REMOTE' remote — using local $def"
      printf '%s\n' "$def"; return
    fi
    if [ "${WH_NO_FETCH:-0}" != "1" ]; then
      if [ "${WH_DRY_RUN:-0}" = "1" ]; then
        wh_step "would fetch $HARNESS_REMOTE $def (skipped: dry run)"
      else
        wh_step "Fetching $HARNESS_REMOTE ${def}…"
        _wh_fetch_base "$def"
      fi
    fi
    printf '%s/%s\n' "$HARNESS_REMOTE" "$def"
  else
    printf '%s\n' "$def"
  fi
}
