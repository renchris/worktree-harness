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
# WORKTREE_HARNESS_REF pins that clone to a branch or tag; by default it tracks main.
# For all three variables, empty or unset means the default. Each is read once per
# run and is not persisted. WH_GUIDANCE_DISABLED hides the next steps.
set -eu

# Pinned to WH_VERSION in lib/common.sh by test/install.bats: under `curl | sh`
# there is no lib/ to read, and --version must not clone anything.
WH_INSTALLER_VERSION="0.2.0"
DEFAULT_REPO_URL="https://github.com/renchris/worktree-harness.git"
INSTALL_URL="https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh"

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
    '    WORKTREE_HARNESS_REF is the branch or tag to clone. Empty or unset tracks' \
    '    main.' \
    '    Each variable is read once per run and is not persisted.' \
    '    WH_GUIDANCE_DISABLED, when not empty, hides the next steps. PATH warnings' \
    '    still print. CI, when not empty, hides the shell integration and' \
    '    completion offers.' \
    '    Under curl | sh the script is on stdin, so pass options after sh -s --.' \
    '' \
    'Learn more:' \
    '    https://github.com/renchris/worktree-harness'
}

# The subshells keep a closed stream from aborting an install that has started:
# `set -e` kills a bare printf on a closed pipe even with SIGPIPE ignored.
# say prints on stderr, out on stdout. C6 moves the out lines to stderr.
say() { ( printf '%s\n' "$*" >&2 ) || :; }
out() { ( printf '%s\n' "$*" ) 2>/dev/null || :; }

# Rich output needs a terminal that can show it. Chosen once, on stdout's terminal.
pick_glyphs() {
  RICH=""
  if [ -t 1 ]; then
    case "${TERM:-dumb}" in
      dumb) ;;
      *) RICH=1 ;;
    esac
  fi
  if [ -n "$RICH" ]; then
    ELLIPSIS='…'
    PROGRESS='→ '
    SUCCESS='✓ '
    ERROR='✗ '
    WARNING='! '
  else
    ELLIPSIS='...'
    PROGRESS=''
    SUCCESS=''
    ERROR='Error: '
    WARNING='Warning: '
  fi
}

# row <label> <value> — one line of the 16-character label column.
row() { printf '  %-16s%s' "$1" "$2"; }

say_error() {
  say ""
  say "$ERROR$1"
}

# fail <exit> <headline> [<detail>] [<instruction> <command>]
fail() {
  say_error "$2"
  if [ -n "${3:-}" ]; then say "$(row Detail "$3")"; fi
  if [ -n "${4:-}" ]; then
    say ""
    say "$4:"
    say "    ${5:-}"
  fi
  exit "$1"
}

# tool_failed <status> <headline> — the tool's own stderr is already above, so the
# headline invents no cause. 128+n is a signal, which report_exit reports.
tool_failed() {
  if [ "$1" -gt 128 ]; then exit "$1"; fi
  fail "$1" "$2"
}

# Print $1 so that a shell reads it back as one word. Uses no external tool, because
# the failure it may be reporting can be a missing one.
shq() {
  case "$1" in
    ''|*[!A-Za-z0-9_./:@%+,-]*) ;;
    *)
      printf '%s' "$1"
      return 0
      ;;
  esac
  shq_quote="'"
  shq_rest=$1
  shq_done=""
  while :; do
    case "$shq_rest" in
      *"$shq_quote"*) ;;
      *) break ;;
    esac
    shq_done=$shq_done${shq_rest%%"$shq_quote"*}$shq_quote\\$shq_quote$shq_quote
    shq_rest=${shq_rest#*"$shq_quote"}
  done
  printf "'%s%s'" "$shq_done" "$shq_rest"
}

# recovery_command <prefix text> — the installer, started the way this run started.
# The text is already quoted, or is the placeholder <DIR>.
recovery_command() {
  if [ -n "$SELF_DIR" ]; then
    printf 'sh %s/install.sh --prefix %s' "$(shq "$SELF_DIR")" "$1"
  else
    printf 'curl -fsSL %s | sh -s -- --prefix %s' "$INSTALL_URL" "$1"
  fi
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
    fail 1 "Can't install from $SRC_SHOWN. These paths are missing:$missing"
  fi
}

# Print the nearest existing directory at or above $1.
nearest_directory() {
  nd_dir=$1
  while [ ! -d "$nd_dir" ]; do
    nd_dir=$(dirname "$nd_dir")
  done
  printf '%s' "$nd_dir"
}

# Before the first write, so a prefix nobody can write to changes nothing.
check_writable() {
  for cw_path in "$(dirname "$SHARE_DIR")" "$BIN_DIR"; do
    cw_base=$(nearest_directory "$cw_path")
    if [ ! -w "$cw_base" ]; then
      fail 1 "Can't install to $PREFIX. $cw_base isn't writable." "Nothing was changed." \
        "Choose a directory you can write to" "$(recovery_command '<DIR>')"
    fi
  done
}

check_overlap() {
  src_real=$(physical_path "$SRC")
  share_real=$(physical_path "$SHARE_DIR")
  overlap=""
  case "$share_real/" in "${src_real%/}"/*) overlap=1 ;; esac
  case "$src_real/" in "${share_real%/}"/*) overlap=1 ;; esac
  if [ -e "$SHARE_DIR/.git" ]; then overlap=1; fi
  if [ -n "$overlap" ]; then
    fail 1 "Can't install into $SHARE_DIR. It's the source checkout." "" \
      "Run the installer from another directory, or choose another prefix" \
      "$(recovery_command '<DIR>')"
  fi
}

# Read, never source: lib/common.sh is bash and this is sh. Matches the assignment,
# and a missing file must not kill `X=$(read_version …)` under `set -e`.
read_version() { sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$1" 2>/dev/null || true; }

# True only when installing would change nothing: same version, same files, nothing
# extra at the top of the tree, and a dispatcher and link that still work. A missing
# diff or readlink reads as "different", which takes the safe path.
installed_matches() {
  if [ -z "$NEW_VERSION" ] || [ "$NEW_VERSION" != "$OLD_VERSION" ]; then return 1; fi
  if [ ! -x "$SHARE_DIR/bin/worktree-harness" ]; then return 1; fi
  if [ "$(readlink "$BIN_DIR/worktree-harness" 2>/dev/null)" != "$SHARE_DIR/bin/worktree-harness" ]; then
    return 1
  fi
  if [ "$(ls -A "$SHARE_DIR" 2>/dev/null)" != "bin
lib
share" ]; then
    return 1
  fi
  for im_dir in bin lib share; do
    if ! diff -r "$SRC/$im_dir" "$SHARE_DIR/$im_dir" >/dev/null 2>&1; then return 1; fi
  done
}

# fresh, replaced or unchanged, from the disk, before anything is replaced.
pick_state() {
  NEW_VERSION=$(read_version "$SRC/lib/common.sh")
  OLD_VERSION=""
  if ! path_exists "$SHARE_DIR"; then
    STATE=fresh
    return 0
  fi
  OLD_VERSION=$(read_version "$SHARE_DIR/lib/common.sh")
  if installed_matches; then STATE=unchanged; else STATE=replaced; fi
}

# The commit names what was installed; the ref is a pointer that moves. A copy with
# no .git of its own may sit inside another repository, whose commit isn't its own.
read_source_commit() {
  COMMIT=""
  SOURCE_REF=""
  if [ ! -e "$SRC/.git" ] || ! command -v git >/dev/null 2>&1; then return 0; fi
  COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) || COMMIT=""
  if [ -n "$SELF_DIR" ]; then return 0; fi
  SOURCE_REF=${WORKTREE_HARNESS_REF:-}
  if [ -z "$SOURCE_REF" ]; then
    SOURCE_REF=$(git -C "$SRC" symbolic-ref --short -q HEAD 2>/dev/null) || SOURCE_REF=""
  fi
}

# Clone into $TMP. Git's stderr stays out of the headline: the first fatal: or error:
# line is the one that names the cause, and its last line is often only advice.
# Stdin is closed so the clone can't read the rest of a piped script. The low-speed
# settings cover HTTP(S) stalls only.
clone_source() {
  set -- clone --depth 1
  if [ -n "${WORKTREE_HARNESS_REF:-}" ]; then
    set -- "$@" --branch "$WORKTREE_HARNESS_REF"
  fi
  # In the background, so TERM to this shell doesn't wait for the clone to end.
  git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@" -- "$REPO_URL" "$TMP/worktree-harness" \
    </dev/null >/dev/null 2>"$TMP/clone.err" &
  CHILD=$!
  rc=0
  wait "$CHILD" || rc=$?
  CHILD=""
  if [ "$rc" -eq 0 ]; then return 0; fi
  if [ "$rc" -gt 128 ]; then exit "$rc"; fi
  # With no way to redact git's text, none of it is shown.
  clone_err=$(sed 's#://[^/ ]*@#://#g' "$TMP/clone.err" 2>/dev/null | LC_ALL=C tr -d '\000-\010\013-\037\177' 2>/dev/null) || clone_err=""
  detail=$(printf '%s\n' "$clone_err" | grep -E '^(fatal|error):' | head -n 1) || detail=""
  if [ -z "$detail" ]; then
    detail=$(printf '%s\n' "$clone_err" | grep . | tail -n 1) || detail=""
  fi
  # A failed clone keeps git's own code until C8.
  fail "$rc" "Couldn't clone $REPO_URL_SHOWN. Nothing was changed." \
    "git: ${detail:-no error text (exit $rc)}" \
    "Check access to the repository" "git ls-remote -- $(shq "$REPO_URL_SHOWN")"
}

# Stage on the same filesystem, so the swap is two renames. They aren't atomic
# together: SHARE_DIR is absent for the moment between them.
install_files() {
  out "${PROGRESS}Installing to $SHARE_DIR$ELLIPSIS"
  mkdir -p "$PREFIX/share" "$BIN_DIR" || tool_failed "$?" "Couldn't create the install directories under $PREFIX."
  # A `..` through a directory that didn't exist before the mkdir resolves only now.
  check_overlap

  STAGE=$(mktemp -d "$PREFIX/share/.worktree-harness.XXXXXX") || tool_failed "$?" "Failed to create a temporary directory."
  copy_failed="Couldn't copy files to $SHARE_DIR."
  if [ "$STATE" = replaced ]; then copy_failed="$copy_failed The previous install is unchanged."; fi
  {
    chmod "$(umask -S)" "$STAGE" &&
      cp -R "$SRC/bin" "$SRC/lib" "$SRC/share" "$STAGE/" &&
      chmod +x "$STAGE/bin/worktree-harness"
  } || tool_failed "$?" "$copy_failed"

  PHASE=swapping
  if path_exists "$SHARE_DIR"; then
    OLD=$(mktemp -d "$PREFIX/share/.worktree-harness-old.XXXXXX") || tool_failed "$?" "Failed to create a temporary directory."
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
    fail 1 "Can't verify $BIN_DIR/worktree-harness. It doesn't resolve to $SHARE_DIR/bin/worktree-harness."
  fi
}

report_receipt() {
  if [ "$STATE" = unchanged ]; then
    say "${SUCCESS}worktree-harness $NEW_VERSION is already installed."
    return 0
  fi
  installed_name="worktree-harness${NEW_VERSION:+ $NEW_VERSION}"
  version_text=${NEW_VERSION:-unknown}
  commit_text=""
  if [ -n "$COMMIT" ]; then
    commit_text="commit $COMMIT"
    if [ -n "$SOURCE_REF" ]; then commit_text="$commit_text, from $SOURCE_REF"; fi
    version_text="$version_text ($commit_text)"
  fi
  if [ -n "$RICH" ]; then
    out "${SUCCESS}Installed $installed_name"
    out "$(row Path "$BIN_DIR/worktree-harness")"
    out "$(row Version "$version_text")"
  elif [ -n "$commit_text" ]; then
    out "Installed $installed_name ($commit_text) to $BIN_DIR/worktree-harness."
  else
    out "Installed $installed_name to $BIN_DIR/worktree-harness."
  fi
  if [ "$STATE" != replaced ]; then return 0; fi
  if [ -z "$OLD_VERSION" ]; then
    replaced_text="unknown version"
  elif [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    replaced_text="$OLD_VERSION (different content)"
  else
    replaced_text=$OLD_VERSION
  fi
  if [ -n "$RICH" ]; then
    say "$(row Replaced "$replaced_text")"
  else
    say "Replaced $replaced_text."
  fi
}

# Print the physical path of the existing directory $1, or fail.
physical_dir() { ( CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P ); }

# The warnings are required recovery, so they ignore the guidance variable. Sets WH
# to the command the next steps can use: the bare name only if it runs this install.
report_path() {
  WH=$(shq "$BIN_DIR/worktree-harness")
  found=$(command -v worktree-harness 2>/dev/null) || found=""
  if [ -z "$found" ]; then
    out ""
    out "${WARNING}worktree-harness isn't on PATH, so the command won't resolve. Add it:"
    case "${SHELL:-}" in
      */fish|fish) out "    fish_add_path $(shq "$BIN_DIR")" ;;
      *) out "    export PATH=$(shq "$BIN_DIR"):\"\$PATH\"" ;;
    esac
    return 0
  fi
  found_dir=$(physical_dir "$(dirname "$found")") || found_dir=""
  bin_real=$(physical_dir "$BIN_DIR") || bin_real=""
  if [ -n "$found_dir" ] && [ "$found_dir" = "$bin_real" ]; then
    WH=worktree-harness
    return 0
  fi
  out ""
  out "${WARNING}worktree-harness resolves to $found, not this install, so the bare command runs that copy."
}

# next_step <instruction> <command>...
next_step() {
  out ""
  out "$1:"
  shift
  for ns_command do out "    $ns_command"; done
}

# Real commands for the detected shell only. They come after any PATH fix, because
# the shell integration needs the command on PATH when it is sourced.
report_offers() {
  if [ -n "${CI:-}" ]; then return 0; fi
  shell_dir="$SHARE_DIR/share/shell"
  completions_dir="$SHARE_DIR/share/completions"
  case "${SHELL:-}" in
    */bash|bash)
      next_step "Turn on shell integration to auto-isolate your agent (add to ~/.bashrc)" \
        "source $(shq "$shell_dir/bash.sh")"
      next_step "Turn on completions (add to ~/.bashrc)" \
        "source $(shq "$completions_dir/worktree-harness.bash")"
      ;;
    */zsh|zsh)
      next_step "Turn on shell integration to auto-isolate your agent (add to ~/.zshrc)" \
        "source $(shq "$shell_dir/zsh.sh")"
      next_step "Turn on completions (add to ~/.zshrc, before compinit)" \
        "fpath=($(shq "$completions_dir") \$fpath)"
      ;;
    */fish|fish)
      next_step "Turn on shell integration to auto-isolate your agent (add to ~/.config/fish/config.fish)" \
        "source $(shq "$shell_dir/fish.fish")"
      next_step "Turn on completions" \
        "cp $(shq "$completions_dir/worktree-harness.fish") ~/.config/fish/completions/"
      ;;
  esac
}

report_next_steps() {
  if [ -n "${WH_GUIDANCE_DISABLED:-}" ]; then return 0; fi
  out ""
  out "Next steps:"
  # `worktree-harness init` refuses outside a repository, and when .harnessrc exists.
  repo_root=""
  if command -v git >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root=""
  fi
  if [ -z "$repo_root" ]; then
    next_step "Set up a repository" "cd <REPO>" "$WH init"
  elif [ ! -e "$repo_root/.harnessrc" ]; then
    next_step "Set up a repository" "$WH init"
  fi
  next_step "Create a worktree" "$WH new <BRANCH>"
  report_offers
  # rm on the symlink removes the link, not its target.
  next_step "Uninstall later by removing both paths" \
    "rm -rf -- $(shq "$SHARE_DIR") $(shq "$BIN_DIR/worktree-harness")"
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
        say_error "Couldn't replace $SHARE_DIR. The previous install was restored."
      fi
      if [ -n "$KEPT" ]; then
        say_error "Couldn't restore $SHARE_DIR. The previous install is in $KEPT."
      fi
      ;;
    swapped)
      if [ -n "$was_signal" ]; then
        say "Stopped waiting."
        say "$SHARE_DIR was replaced, but $BIN_DIR/worktree-harness wasn't updated."
      else
        say_error "Couldn't link $BIN_DIR/worktree-harness. Files are in $SHARE_DIR."
      fi
      say ""
      say "Run the installer again:"
      say "    $(recovery_command "$(shq "$PREFIX")")"
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
  trap '' PIPE
  pick_glyphs

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

  # Install from the checkout this file sits in; otherwise clone. Only $0 decides:
  # under `curl | sh` it is the shell's name, so a bin/ in the cwd is never used.
  SELF_DIR=""
  case "$0" in
    */install.sh|install.sh)
      if [ -f "$0" ]; then
        script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd)
        if [ -f "$script_dir/bin/worktree-harness" ]; then SELF_DIR="$script_dir"; fi
      fi
      ;;
  esac

  if [ -n "$OPT_PREFIX" ]; then
    PREFIX=$OPT_PREFIX
  elif [ -n "${WORKTREE_HARNESS_PREFIX:-}" ]; then
    PREFIX=$WORKTREE_HARNESS_PREFIX
  elif [ -n "${HOME:-}" ]; then
    PREFIX="$HOME/.local"
  else
    fail 2 "Can't pick an install location. HOME isn't set." "" \
      "Install to a named directory" "$(recovery_command '<DIR>')"
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

  check_writable

  if [ -n "$SELF_DIR" ]; then
    SRC="$SELF_DIR"
    SRC_SHOWN="$SRC"
    say "${PROGRESS}Installing from $SRC (local checkout)$ELLIPSIS"
  else
    command -v git >/dev/null 2>&1 || fail 1 "Can't clone $REPO_URL_SHOWN. git isn't on PATH." \
      "git is required to install without a checkout." \
      "Install git, then rerun the installer" "$(recovery_command "$(shq "$PREFIX")")"
    SRC_SHOWN="$REPO_URL_SHOWN"
    say "${PROGRESS}Installing from $REPO_URL_SHOWN$ELLIPSIS"
    # An explicit template, because a bare `mktemp -d` ignores TMPDIR on macOS.
    CLEANUP=$(mktemp -d "${TMPDIR:-/tmp}/worktree-harness.XXXXXX") || tool_failed "$?" "Failed to create a temporary directory."
    TMP=$CLEANUP
    out "${PROGRESS}Cloning $REPO_URL_SHOWN$ELLIPSIS"
    clone_source
    SRC="$TMP/worktree-harness"
  fi

  check_source
  check_overlap
  read_source_commit
  pick_state

  if [ "$STATE" != unchanged ]; then install_files; fi

  report_receipt
  report_path
  report_next_steps
}

# Called only here, so a truncated `curl | sh` body fails to parse or defines
# functions only, and installs nothing. No `||` or `if` around it: either would
# disable `set -e` inside main.
main "$@"
