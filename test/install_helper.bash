#!/usr/bin/env bash
# test/install_helper.bash — fixtures for the install.sh suites. Load after helper.bash.
# Nothing here reaches the network or the real $HOME.

# Point HOME, TMPDIR, the prefix and the repo URL at this test's temp directory.
# TMPDIR is its own directory so that a leaked temp clone is observable.
# Sets P (the prefix), EMPTY (an empty cwd) and FIXTURE (the path behind the repo URL).
install_setup() {
  P="$BATS_TEST_TMPDIR/prefix"
  EMPTY="$BATS_TEST_TMPDIR/empty"
  FIXTURE="$BATS_TEST_TMPDIR/fixture.git"
  mkdir -p "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/tmp" "$EMPTY"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export WORKTREE_HARNESS_PREFIX="$P"
  export WORKTREE_HARNESS_REPO="file://$FIXTURE"
}

# make_install_fixture <dest> <dir>... — a git repo holding copies of the named
# top-level directories, plus the marker bin/fixture-marker.
make_install_fixture() {
  local dest="$1" d
  shift
  mkdir -p "$dest"
  for d in "$@"; do cp -R "$WH_ROOT/$d" "$dest/"; done
  printf 'fixture\n' > "$dest/bin/fixture-marker"
  (
    cd "$dest" || exit 1
    git init -q
    git config user.email t@e.st
    git config user.name Tester
    git add -A
    git commit -qm fixture
  )
}

# The default repo behind WORKTREE_HARNESS_REPO, with everything the installer needs.
make_full_fixture() { make_install_fixture "$FIXTURE" bin lib share; }

# copy_checkout <dest> — a checkout's files, from the working tree, so a test always
# runs the install.sh under test.
copy_checkout() {
  mkdir -p "$1"
  cp -R "$WH_ROOT/bin" "$WH_ROOT/lib" "$WH_ROOT/share" "$WH_ROOT/install.sh" "$1/"
}

# piped_install [arg]... — run install.sh the way `curl | sh` does: the script on
# stdin, from a directory with no checkout in it.
piped_install() {
  (cd "$EMPTY" && exec sh -s -- "$@" < "$WH_ROOT/install.sh")
}

# install_once — a quiet install from the checkout into $P.
install_once() {
  sh "$WH_ROOT/install.sh" >/dev/null 2>&1
}

# make_shim <tool> <sh body> — put a stand-in for <tool> in $BATS_TEST_TMPDIR/bin.
# The body can run the real tool as "$REAL". Sets SHIMS to the directory.
make_shim() {
  local real
  real="$(command -v "$1" || true)"
  SHIMS="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$SHIMS"
  printf '#!/bin/sh\nREAL=%s\n%s\n' "'$real'" "$2" > "$SHIMS/$1"
  chmod +x "$SHIMS/$1"
}

# `[[ ]]` and `!` don't fail a bats test on bash 3.2 unless they come last.
assert_has() {
  case "$1" in *"$2"*) return 0 ;; esac
  printf 'expected to find: %s\nin: %s\n' "$2" "$1"
  return 1
}

assert_lacks() {
  case "$1" in
    *"$2"*)
      printf 'expected not to find: %s\nin: %s\n' "$2" "$1"
      return 1
      ;;
  esac
}

# The share dir holds only the install: no stage or old tree was left behind.
assert_share_clean() {
  [ "$(ls -A "$P/share")" = "worktree-harness" ]
}
