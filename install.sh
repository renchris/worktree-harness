#!/usr/bin/env sh
# install.sh — install worktree-harness. POSIX sh (works under `curl ... | sh`).
#
#   curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh
#   ./install.sh                      # from a checkout
#
# Layout: copies bin/ lib/ share/ to $PREFIX/share/worktree-harness and symlinks
# the dispatcher into $PREFIX/bin. No sudo, no global state.
#
# Location: --prefix <DIR>, else WORKTREE_HARNESS_PREFIX, else ~/.local.
# Source: the checkout this file sits in, else a clone of WORKTREE_HARNESS_REPO
# (git URL; default https://github.com/renchris/worktree-harness.git).
# For both variables, empty or unset means the default. Each is read once per
# run and is not persisted.
set -eu

# Pinned to WH_VERSION in lib/common.sh by test/install.bats: under `curl | sh`
# there is no lib/ to read, and --version must not clone anything.
WH_INSTALLER_VERSION="0.2.0"
DEFAULT_REPO_URL="https://github.com/renchris/worktree-harness.git"

usage() {
  printf '%s\n' \
    'Usage:' \
    '    sh install.sh [options]' \
    '' \
    'Install worktree-harness under a prefix, with no sudo and no global state.' \
    '' \
    'Options:' \
    '    -h, --help        Print this help.' \
    '    --version         Print the version of this installer.' \
    "    --prefix <DIR>    Install under <DIR> (default: \$WORKTREE_HARNESS_PREFIX, else ~/.local)." \
    '' \
    'Examples:' \
    '    sh install.sh' \
    '    sh install.sh --prefix <DIR>' \
    '    curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh -s -- --prefix <DIR>' \
    '' \
    'Notes:' \
    '    WORKTREE_HARNESS_PREFIX is the install location when --prefix is not given.' \
    '    --prefix wins over it. Empty or unset uses ~/.local.' \
    "    WORKTREE_HARNESS_REPO is the git URL to clone when not run from a checkout" \
    "    (default $DEFAULT_REPO_URL)." \
    '    Empty or unset uses the default.' \
    '    Each variable is read once per run and is not persisted.' \
    '    Under curl | sh the script is on stdin, so pass options after sh -s --.' \
    '' \
    'Learn more:' \
    '    https://github.com/renchris/worktree-harness'
}

say() { printf '%s\n' "$*" >&2; }

fail() {
  say "$@"
  exit 1
}

usage_error() {
  say "$1"
  say ""
  say "See all options:"
  say "    sh install.sh --help"
  exit 2
}

path_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# Print the physical path of $1. A path that doesn't exist yet resolves through
# its nearest existing ancestor, because `cd -P` fails on it.
physical_path() {
  pp_dir=$1
  pp_tail=""
  while [ ! -d "$pp_dir" ]; do
    pp_tail="/$(basename "$pp_dir")$pp_tail"
    pp_dir=$(dirname "$pp_dir")
  done
  pp_real=$(CDPATH='' cd -P "$pp_dir" && pwd -P)
  printf '%s%s\n' "${pp_real%/}" "$pp_tail"
}

# Every file bin/worktree-harness sources unconditionally, plus share/. Lists all
# that are missing at once, before anything is written.
check_source() {
  missing=""
  for f in bin/worktree-harness lib/common.sh lib/compat.sh; do
    if [ ! -f "$SRC/$f" ]; then
      missing="$missing
    $f"
    fi
  done
  if [ ! -d "$SRC/share" ]; then
    missing="$missing
    share"
  fi
  if [ -n "$missing" ]; then
    fail "Can't install from $SRC_SHOWN. These paths are missing:$missing"
  fi
}

check_overlap() {
  src_real=$(physical_path "$SRC")
  share_real=$(physical_path "$SHARE_DIR")
  overlap=""
  case "$share_real/" in "${src_real%/}"/*) overlap=1 ;; esac
  case "$src_real/" in "${share_real%/}"/*) overlap=1 ;; esac
  if [ -e "$SHARE_DIR/.git" ]; then overlap=1; fi
  if [ -n "$overlap" ]; then
    say "Can't install into $SHARE_DIR. It's the source checkout."
    say ""
    say "Run the installer from another directory, or choose another prefix:"
    fail "    sh install.sh --prefix <DIR>"
  fi
}

remove_temp() {
  if [ -n "$1" ]; then
    rm -rf -- "$1" || say "Warning: couldn't remove $1."
  fi
}

# What the operator is told after a failed run, from the state on disk. A signal
# status is reported here, not in on_signal, because a child killed by SIGINT can
# trip `set -e` before the signal handler runs.
report_exit() {
  was_signal=""
  case "$1" in 129|130|143) was_signal=1 ;; esac
  case "$PHASE" in
    before)
      if [ -n "$was_signal" ]; then
        say "Canceled."
        say "Nothing was changed."
      fi
      ;;
    swapping)
      if [ -n "$was_signal" ]; then
        say "Canceled."
        if [ -n "$RESTORED" ]; then say "The previous install was restored."; fi
      elif [ -n "$RESTORED" ]; then
        say "Couldn't replace $SHARE_DIR. The previous install was restored."
      fi
      if [ -n "$KEPT" ]; then
        say "Couldn't restore $SHARE_DIR. The previous install is in $KEPT."
      fi
      ;;
    swapped)
      if [ -n "$was_signal" ]; then say "Stopped waiting."; fi
      say "$SHARE_DIR was replaced, but $BIN_DIR/worktree-harness wasn't updated."
      say ""
      say "Run the installer again:"
      say "    sh install.sh --prefix <DIR>"
      ;;
  esac
}

on_exit() {
  status=$?
  trap - EXIT
  set +e
  if [ "$PHASE" = swapping ]; then
    if path_exists "$SHARE_DIR"; then
      # SHARE_DIR is present, so either the first rename never ran (the stage is
      # still there) or the second one finished (it isn't).
      if path_exists "$STAGE"; then PHASE=before; else PHASE=swapped; fi
    elif [ -n "$OLD" ] && path_exists "$OLD/old"; then
      if mv "$OLD/old" "$SHARE_DIR"; then
        RESTORED=1
      else
        # This directory now holds the only copy of the previous install.
        KEPT="$OLD/old"
        OLD=""
      fi
    else
      PHASE=before
    fi
  fi
  if [ "$status" -ne 0 ]; then report_exit "$status"; fi
  remove_temp "$STAGE"
  remove_temp "$LINK_DIR"
  remove_temp "$CLEANUP"
  remove_temp "$OLD"
  exit "$status"
}

on_signal() {
  # Reset first, so a second Ctrl+C stops at once.
  trap - INT TERM HUP
  set +e
  # A background child ignores SIGINT in a non-job-control shell. The wait keeps
  # bash's "Terminated" notice for the child off the operator's stderr.
  if [ -n "$CHILD" ]; then
    kill "$CHILD" 2>/dev/null
    wait "$CHILD" 2>/dev/null
  fi
  exit "$1"
}

main() {
  # `-- --help` is a positional, so the scan stops at `--`. Help wins over any
  # other argument, and neither path does any work or needs a network.
  for a do
    case "$a" in
      --) break ;;
      -h|--help) usage; exit 0 ;;
    esac
  done
  if [ "${1:-}" = help ]; then usage; exit 0; fi

  OPT_PREFIX=""
  OPT_VERSION=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        if [ "$#" -gt 0 ]; then usage_error "Unexpected argument $1 for install.sh."; fi
        break
        ;;
      --version) OPT_VERSION=1 ;;
      --prefix)
        # An empty prefix must never reach the install paths: it would mean /share.
        if [ -z "${2:-}" ]; then usage_error "Option --prefix needs a value."; fi
        OPT_PREFIX=$2
        shift
        ;;
      --prefix=*)
        OPT_PREFIX=${1#--prefix=}
        if [ -z "$OPT_PREFIX" ]; then usage_error "Option --prefix needs a value."; fi
        ;;
      -*) usage_error "Unknown option $1 for install.sh." ;;
      *) usage_error "Unexpected argument $1 for install.sh." ;;
    esac
    shift
  done

  # Internal: lets test/install.bats check the --help examples without installing.
  if [ "${__WORKTREE_HARNESS_PARSE_ONLY:-}" = 1 ]; then exit 0; fi

  if [ -n "$OPT_VERSION" ]; then
    printf '%s\n' "$WH_INSTALLER_VERSION"
    exit 0
  fi

  if [ -n "$OPT_PREFIX" ]; then
    PREFIX=$OPT_PREFIX
  elif [ -n "${WORKTREE_HARNESS_PREFIX:-}" ]; then
    PREFIX=$WORKTREE_HARNESS_PREFIX
  elif [ -n "${HOME:-}" ]; then
    PREFIX="$HOME/.local"
  else
    say "Can't pick an install location. HOME isn't set."
    say ""
    say "Install to a named directory:"
    say "    sh install.sh --prefix <DIR>"
    exit 2
  fi
  case $PREFIX in /*) ;; *) PREFIX="$(pwd)/${PREFIX#./}" ;; esac
  SHARE_DIR="$PREFIX/share/worktree-harness"
  BIN_DIR="$PREFIX/bin"

  REPO_URL="${WORKTREE_HARNESS_REPO:-$DEFAULT_REPO_URL}"
  # Only git clone sees the raw URL; every printed line uses this one. With no sed
  # to redact it, print a name rather than a URL that may hold a password.
  REPO_URL_SHOWN=$(printf '%s' "$REPO_URL" | sed 's#://[^/]*@#://#' 2>/dev/null) || REPO_URL_SHOWN="worktree-harness"

  PHASE=before
  STAGE=""
  OLD=""
  LINK_DIR=""
  CLEANUP=""
  CHILD=""
  RESTORED=""
  KEPT=""
  trap on_exit EXIT
  trap 'on_signal 130' INT
  trap 'on_signal 143' TERM
  trap 'on_signal 129' HUP

  # Install from the checkout this file sits in; otherwise clone. Only $0 decides:
  # under `curl | sh` it is the shell's name, so a bin/ in the cwd is never used.
  SRC=""
  case "$0" in
    */install.sh|install.sh)
      if [ -f "$0" ]; then
        SELF_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
        if [ -f "$SELF_DIR/bin/worktree-harness" ]; then SRC="$SELF_DIR"; fi
      fi
      ;;
  esac
  if [ -n "$SRC" ]; then
    SRC_SHOWN="$SRC"
    say "Installing from $SRC (local checkout)…"
  else
    command -v git >/dev/null 2>&1 || fail "install: git is required to clone $REPO_URL_SHOWN"
    SRC_SHOWN="$REPO_URL_SHOWN"
    say "Installing from ${REPO_URL_SHOWN}…"
    # An explicit template, because a bare `mktemp -d` ignores TMPDIR on macOS.
    CLEANUP=$(mktemp -d "${TMPDIR:-/tmp}/worktree-harness.XXXXXX")
    TMP=$CLEANUP
    echo "→ cloning $REPO_URL_SHOWN"
    # In the background, so TERM to this shell doesn't wait for the clone to end.
    git clone --depth 1 -- "$REPO_URL" "$TMP/worktree-harness" >/dev/null 2>&1 &
    CHILD=$!
    rc=0
    wait "$CHILD" || rc=$?
    CHILD=""
    if [ "$rc" -ne 0 ]; then exit "$rc"; fi
    SRC="$TMP/worktree-harness"
  fi

  check_source
  check_overlap

  echo "→ installing to $SHARE_DIR"
  mkdir -p "$PREFIX/share" "$BIN_DIR"
  # A `..` through a directory that didn't exist before the mkdir resolves only now.
  check_overlap

  # Stage on the same filesystem, so the swap below is two renames. They aren't
  # atomic together: SHARE_DIR is absent for the moment between them.
  STAGE=$(mktemp -d "$PREFIX/share/.worktree-harness.XXXXXX")
  chmod "$(umask -S)" "$STAGE"
  cp -R "$SRC/bin" "$SRC/lib" "$SRC/share" "$STAGE/"
  chmod +x "$STAGE/bin/worktree-harness"

  PHASE=swapping
  if path_exists "$SHARE_DIR"; then
    OLD=$(mktemp -d "$PREFIX/share/.worktree-harness-old.XXXXXX")
    mv "$SHARE_DIR" "$OLD/old"
  fi
  mv "$STAGE" "$SHARE_DIR" || exit 1
  STAGE=""
  PHASE=swapped

  LINK_DIR=$(mktemp -d "$BIN_DIR/.worktree-harness.XXXXXX")
  ln -s "$SHARE_DIR/bin/worktree-harness" "$LINK_DIR/link"
  mv -f "$LINK_DIR/link" "$BIN_DIR/worktree-harness"
  PHASE="done"

  if [ ! -f "$BIN_DIR/worktree-harness" ] || [ ! -x "$BIN_DIR/worktree-harness" ]; then
    fail "Can't verify $BIN_DIR/worktree-harness. It doesn't resolve to $SHARE_DIR/bin/worktree-harness."
  fi

  echo "✓ installed: $BIN_DIR/worktree-harness"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  add it to your PATH:   export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
  echo
  echo "  optional: auto-isolate your agent (bash/zsh/fish) by sourcing one of:"
  echo "    $SHARE_DIR/share/shell/bash.sh"
  echo "    $SHARE_DIR/share/shell/zsh.sh"
  echo "    $SHARE_DIR/share/shell/fish.fish"
  echo
  echo "  optional: shell completions are under $SHARE_DIR/share/completions/"
  echo "    (bash: source worktree-harness.bash · zsh: add the dir to fpath · fish: copy *.fish)"
  echo
  echo "  get started:   worktree-harness init  &&  worktree-harness new my-feature"
}

# Called only here, so a truncated `curl | sh` body fails to parse or defines
# functions only, and installs nothing. No `||` or `if` around it: either would
# disable `set -e` inside main.
main "$@"
