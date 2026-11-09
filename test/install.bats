#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper
load install_helper

setup() { install_setup; }

common_version() { sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$WH_ROOT/lib/common.sh"; }

# --- The current contract -----------------------------------------------------

@test "fresh install from the checkout" {
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$P/bin/worktree-harness")" = "$P/share/worktree-harness/bin/worktree-harness" ]
  [ -d "$P/share/worktree-harness/bin" ]
  [ -d "$P/share/worktree-harness/lib" ]
  [ -d "$P/share/worktree-harness/share" ]
  "$P/bin/worktree-harness" --version
  assert_share_clean
}

@test "reinstall replaces the tree" {
  install_once
  touch "$P/share/worktree-harness/stray"
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$P/share/worktree-harness/stray" ]
  "$P/bin/worktree-harness" --version
  assert_share_clean
}

@test "streams: the receipt is on stderr, stdout only the installed path" {
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Installed worktree-harness"
  assert_has "$stderr" "(local checkout)"
  assert_has "$stderr" "Next steps:"
  [ "$output" = "$P/bin/worktree-harness" ]
  run --separate-stderr sh "$WH_ROOT/install.sh" --bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_has "$stderr" "Unknown option --bogus"
}

@test "stdout is only the installed path" {
  make_full_fixture
  run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  [ "$output" = "$P/bin/worktree-harness" ]
  "$output" --version
}

@test "a failed install prints nothing on stdout" {
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_has "$stderr" "Couldn't clone"
}

@test "install.sh is POSIX" {
  sh -n "$WH_ROOT/install.sh"
  if command -v dash >/dev/null 2>&1; then dash -n "$WH_ROOT/install.sh"; fi
}

# --- Arguments do no work -----------------------------------------------------

@test "--help does no work and -h is the same" {
  run --separate-stderr sh "$WH_ROOT/install.sh" --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_has "$output" "Usage:"
  assert_has "$output" "--prefix <DIR>"
  [ ! -e "$P" ]
  help_text="$output"
  run --separate-stderr sh "$WH_ROOT/install.sh" -h
  [ "$status" -eq 0 ]
  [ "$output" = "$help_text" ]
  [ ! -e "$P" ]
}

@test "install.sh help prints the same help" {
  run sh "$WH_ROOT/install.sh" help
  [ "$status" -eq 0 ]
  [ "$output" = "$(sh "$WH_ROOT/install.sh" --help)" ]
  [ ! -e "$P" ]
}

@test "help wins over an earlier unknown option" {
  run --separate-stderr sh "$WH_ROOT/install.sh" --bogus --help
  [ "$status" -eq 0 ]
  assert_has "$output" "Usage:"
  [ -z "$stderr" ]
  [ ! -e "$P" ]
}

@test "-- ends help scanning" {
  run --separate-stderr sh "$WH_ROOT/install.sh" -- --help
  [ "$status" -eq 2 ]
  assert_has "$stderr" "Unexpected argument --help for install.sh."
  [ ! -e "$P" ]
}

@test "an unknown option exits 2 and names it" {
  run --separate-stderr sh "$WH_ROOT/install.sh" --bogus
  [ "$status" -eq 2 ]
  assert_has "$stderr" "Unknown option --bogus for install.sh."
  assert_has "$stderr" "See all options:"
  [ ! -e "$P" ]
}

@test "a positional argument exits 2 and names it" {
  run --separate-stderr sh "$WH_ROOT/install.sh" stray
  [ "$status" -eq 2 ]
  assert_has "$stderr" "Unexpected argument stray for install.sh."
  [ ! -e "$P" ]
}

@test "--dry-run, --force and --yes are refused, not ignored" {
  for opt in --dry-run --force --yes; do
    run --separate-stderr sh "$WH_ROOT/install.sh" "$opt"
    [ "$status" -eq 2 ]
    assert_has "$stderr" "Unknown option $opt for install.sh."
    [ ! -e "$P" ]
  done
}

@test "an empty --prefix is a usage error" {
  for form in --prefix= --prefix; do
    run --separate-stderr sh "$WH_ROOT/install.sh" "$form"
    [ "$status" -eq 2 ]
    assert_has "$stderr" "Option --prefix needs a value."
  done
  run --separate-stderr sh "$WH_ROOT/install.sh" --prefix ""
  [ "$status" -eq 2 ]
  assert_has "$stderr" "Option --prefix needs a value."
  [ ! -e "$P" ]
  [ ! -e /share/worktree-harness ]
}

@test "--version prints only the version in lib/common.sh" {
  run --separate-stderr sh "$WH_ROOT/install.sh" --version
  [ "$status" -eq 0 ]
  [ -n "$(common_version)" ]
  [ "$output" = "$(common_version)" ]
  [ -z "$stderr" ]
  [ ! -e "$P" ]
}

@test "--version under a piped run clones nothing" {
  make_shim git 'touch "$BATS_TEST_TMPDIR/git-ran"; exec "$REAL" "$@"'
  export BATS_TEST_TMPDIR
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install --version
  [ "$status" -eq 0 ]
  [ "$output" = "$(common_version)" ]
  [ ! -e "$BATS_TEST_TMPDIR/git-ran" ]
  [ -z "$(ls -A "$TMPDIR")" ]
  [ ! -e "$P" ]
}

@test "every --help example parses" {
  export __WORKTREE_HARNESS_PARSE_ONLY=1
  count=0
  while IFS= read -r line; do
    line="${line#    }"
    line="${line//<DIR>/$P}"
    case "$line" in
      curl*) args="${line#*sh -s -- }"; run piped_install $args ;;
      sh\ install.sh*) args="${line#sh install.sh}"; run sh "$WH_ROOT/install.sh" $args ;;
      *) printf 'an example with no rule in this test: %s\n' "$line"; false ;;
    esac
    [ "$status" -eq 0 ]
    [ ! -e "$P" ]
    count=$((count + 1))
  done < <(sh "$WH_ROOT/install.sh" --help | sed -n '/^Examples:$/,/^$/p' | sed '1d;$d')
  [ "$count" -eq 3 ]
}

@test "the piped --help example works without a checkout" {
  run piped_install --help
  [ "$status" -eq 0 ]
  assert_has "$output" "Usage:"
  [ ! -e "$P" ]
}

# --- Where it installs --------------------------------------------------------

@test "--prefix beats WORKTREE_HARNESS_PREFIX" {
  run sh "$WH_ROOT/install.sh" --prefix "$BATS_TEST_TMPDIR/p2"
  [ "$status" -eq 0 ]
  "$BATS_TEST_TMPDIR/p2/bin/worktree-harness" --version
  run sh "$WH_ROOT/install.sh" "--prefix=$BATS_TEST_TMPDIR/p3"
  [ "$status" -eq 0 ]
  "$BATS_TEST_TMPDIR/p3/bin/worktree-harness" --version
  [ ! -e "$P" ]
}

@test "an empty WORKTREE_HARNESS_PREFIX means the default" {
  WORKTREE_HARNESS_PREFIX="" run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  "$HOME/.local/bin/worktree-harness" --version
}

@test "unset HOME without a prefix names the fix" {
  run --separate-stderr env -u HOME -u WORKTREE_HARNESS_PREFIX sh "$WH_ROOT/install.sh"
  [ "$status" -eq 2 ]
  assert_has "$stderr" "HOME isn't set"
  assert_has "$stderr" "--prefix <DIR>"
}

@test "a relative prefix installs a working link" {
  cd "$BATS_TEST_TMPDIR"
  WORKTREE_HARNESS_PREFIX=rel run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  cd "$EMPTY"
  "$BATS_TEST_TMPDIR/rel/bin/worktree-harness" --version
}

@test "a prefix with a space and a quote installs a working link" {
  awkward="$BATS_TEST_TMPDIR/a b'c"
  run sh "$WH_ROOT/install.sh" --prefix "$awkward"
  [ "$status" -eq 0 ]
  "$awkward/bin/worktree-harness" --version
}

@test "a new install dir follows the umask" {
  umask 022
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  case "$(ls -ld "$P/share/worktree-harness")" in
    drwxr-xr-x*) ;;
    *) ls -ld "$P/share/worktree-harness"; false ;;
  esac
}

@test "something other than a link at the link path is reported" {
  mkdir -p "$P/bin/worktree-harness"
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Can't verify $P/bin/worktree-harness."
}

# --- Which source it installs from --------------------------------------------

@test "piped install clones the fixture" {
  make_full_fixture
  run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  [ -f "$P/share/worktree-harness/bin/fixture-marker" ]
  "$P/bin/worktree-harness" --version
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "piped install ignores a decoy bin/worktree-harness in the cwd" {
  make_full_fixture
  mkdir -p "$EMPTY/bin"
  printf '#!/bin/sh\necho decoy\n' > "$EMPTY/bin/worktree-harness"
  chmod +x "$EMPTY/bin/worktree-harness"
  run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Installing from $WORKTREE_HARNESS_REPO"
  assert_lacks "$("$P/bin/worktree-harness" --version)" "decoy"
  [ -f "$P/share/worktree-harness/bin/fixture-marker" ]
}

@test "a lone install.sh in an empty directory clones" {
  make_full_fixture
  cp "$WH_ROOT/install.sh" "$EMPTY/install.sh"
  run --separate-stderr sh "$EMPTY/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$P/share/worktree-harness/bin/fixture-marker" ]
}

@test "missing git fails before any write" {
  shim="$BATS_TEST_TMPDIR/nogit"
  mkdir -p "$shim"
  for tool in dirname mktemp sh; do ln -s "$(command -v "$tool")" "$shim/$tool"; done
  cd "$EMPTY"
  run --separate-stderr env PATH="$shim" "$shim/sh" -s < "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "git is required"
  [ ! -e "$P" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a source missing files lists them all and keeps the old install" {
  install_once
  old_version="$("$P/bin/worktree-harness" --version)"
  make_install_fixture "$BATS_TEST_TMPDIR/only-bin.git" bin
  export WORKTREE_HARNESS_REPO="file://$BATS_TEST_TMPDIR/only-bin.git"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "lib/common.sh"
  assert_has "$stderr" "lib/compat.sh"
  assert_has "$stderr" "share"
  [ "$("$P/bin/worktree-harness" --version)" = "$old_version" ]
  assert_share_clean
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "credentials in the repo URL are never printed" {
  run --separate-stderr env WORKTREE_HARNESS_REPO='https://user:s3cret@127.0.0.1:9/x.git' \
    sh -c 'cd "$1" && exec sh -s < "$2"' _ "$EMPTY" "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "https://127.0.0.1:9/x.git"
  assert_lacks "$output$stderr" "s3cret"
  run --separate-stderr env WORKTREE_HARNESS_REPO='https://user:p@ss@127.0.0.1:9/x.git' \
    sh -c 'cd "$1" && exec sh -s < "$2"' _ "$EMPTY" "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_lacks "$output$stderr" "ss@"
}

# --- Refusing to replace the source -------------------------------------------

@test "refuses to install over its own source checkout" {
  copy_checkout "$P/share/worktree-harness"
  git init -q "$P/share/worktree-harness"
  run --separate-stderr sh "$P/share/worktree-harness/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "It's the source checkout."
  [ -d "$P/share/worktree-harness/.git" ]
  [ -f "$P/share/worktree-harness/install.sh" ]
}

@test "a piped install refuses a checkout at the install dir" {
  make_full_fixture
  mkdir -p "$P/share"
  git init -q "$P/share/worktree-harness"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "It's the source checkout."
  [ -d "$P/share/worktree-harness/.git" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a prefix inside the source is refused" {
  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  WORKTREE_HARNESS_PREFIX="$src" run --separate-stderr sh "$src/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "It's the source checkout."
  [ ! -e "$src/share/worktree-harness" ]
}

@test "a symlinked prefix that resolves to the source is refused" {
  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  ln -s "$src" "$BATS_TEST_TMPDIR/link"
  WORKTREE_HARNESS_PREFIX="$BATS_TEST_TMPDIR/link" run --separate-stderr sh "$src/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "It's the source checkout."
  [ ! -e "$src/share/worktree-harness" ]
}

@test "piping from inside the install dir keeps a working install" {
  install_once
  make_full_fixture
  EMPTY="$P/share/worktree-harness" run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  [ -f "$P/share/worktree-harness/bin/fixture-marker" ]
  "$P/bin/worktree-harness" --version
}

# --- Keeping the previous install ---------------------------------------------

@test "a truncated download changes nothing" {
  install_once
  inode="$(ls -di "$P/share/worktree-harness")"
  version="$("$P/bin/worktree-harness" --version)"
  script="$WH_ROOT/install.sh"
  start="$(grep -n '^main() {$' "$script" | cut -d: -f1)"
  total="$(wc -l < "$script" | tr -d ' ')"
  [ "$(tail -n 1 "$script")" = 'main "$@"' ]
  cd "$EMPTY"
  count=0
  # Every 10th line inside main, then everything but the call on the last line.
  for n in $(seq "$((start + 1))" 10 "$((total - 1))") "$((total - 1))"; do
    head -n "$n" "$script" | sh >/dev/null 2>&1 || true
    [ "$(ls -di "$P/share/worktree-harness")" = "$inode" ]
    [ "$("$P/bin/worktree-harness" --version)" = "$version" ]
    assert_share_clean
    count=$((count + 1))
  done
  [ "$count" -ge 10 ]
}

@test "a failed copy keeps the previous install" {
  if [ "$(id -u)" = 0 ]; then skip "root reads a chmod 000 file"; fi
  install_once
  touch "$P/share/worktree-harness/previous"
  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  chmod 000 "$src/lib/pm.sh"
  run sh "$src/install.sh"
  [ "$status" -ne 0 ]
  [ -e "$P/share/worktree-harness/previous" ]
  "$P/bin/worktree-harness" --version
  assert_share_clean
}

@test "a failed clone over an existing install keeps it" {
  install_once
  touch "$P/share/worktree-harness/previous"
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  [ -e "$P/share/worktree-harness/previous" ]
  "$P/bin/worktree-harness" --version
  assert_share_clean
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a failed swap restores the previous install" {
  install_once
  touch "$P/share/worktree-harness/previous"
  make_shim mv 'case "$1" in */.worktree-harness.*) exit 1 ;; esac; exec "$REAL" "$@"'
  PATH="$SHIMS:$PATH" run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Couldn't replace $P/share/worktree-harness. The previous install was restored."
  [ -e "$P/share/worktree-harness/previous" ]
  "$P/bin/worktree-harness" --version
  assert_share_clean
}

@test "a failed restore keeps the only copy and names it" {
  install_once
  touch "$P/share/worktree-harness/previous"
  make_shim mv 'case "$1" in */.worktree-harness*) exit 1 ;; esac; exec "$REAL" "$@"'
  PATH="$SHIMS:$PATH" run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  kept="$(echo "$P"/share/.worktree-harness-old.*/old)"
  [ -e "$kept/previous" ]
  assert_has "$stderr" "The previous install is in $kept."
  assert_lacks "$stderr" "was restored"
}

@test "TERM between the renames restores the previous install" {
  install_once
  touch "$P/share/worktree-harness/previous"
  make_shim mv 'case "$1" in */.worktree-harness.*) kill -TERM "$PPID"; exit 0 ;; esac; exec "$REAL" "$@"'
  PATH="$SHIMS:$PATH" run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 143 ]
  assert_has "$stderr" "Canceled."
  assert_has "$stderr" "The previous install was restored."
  [ -e "$P/share/worktree-harness/previous" ]
  assert_share_clean
}

@test "TERM after the swap says the link wasn't updated" {
  install_once
  touch "$P/share/worktree-harness/previous"
  make_shim ln 'kill -TERM "$PPID"; exit 0'
  PATH="$SHIMS:$PATH" run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 143 ]
  assert_has "$stderr" "Stopped waiting."
  assert_has "$stderr" "$P/share/worktree-harness was replaced, but $P/bin/worktree-harness wasn't updated."
  assert_lacks "$stderr" "Nothing was changed"
}

# signal_during_clone <signal> <status> — the clone never ends, so only the signal
# can end the run: it must exit fast, say so, and leave no temp clone behind.
signal_during_clone() {
  local signal="$1" want="$2" pid started tries=0 rc=0
  make_shim git 'exec sleep 30'
  (
    cd "$EMPTY" || exit 1
    PATH="$SHIMS:$PATH" exec sh -s
  ) < "$WH_ROOT/install.sh" > "$BATS_TEST_TMPDIR/out" 2> "$BATS_TEST_TMPDIR/err" 3>&- &
  pid=$!
  until [ -n "$(ls -A "$TMPDIR")" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ]
    sleep 0.1
  done
  started="$(date +%s)"
  kill -"$signal" "$pid"
  wait "$pid" || rc=$?
  [ "$rc" -eq "$want" ]
  [ "$(($(date +%s) - started))" -lt 5 ]
  [ -z "$(ls -A "$TMPDIR")" ]
  assert_has "$(cat "$BATS_TEST_TMPDIR/err")" "Canceled."
  assert_has "$(cat "$BATS_TEST_TMPDIR/err")" "Nothing was changed."
  assert_lacks "$(cat "$BATS_TEST_TMPDIR/err")" "Terminated"
}

@test "TERM during the clone exits 143 fast and cleans up" {
  signal_during_clone TERM 143
}

@test "HUP during the clone exits 129 fast and cleans up" {
  signal_during_clone HUP 129
}

@test "a failed temp removal warns and keeps exit 0" {
  make_full_fixture
  make_shim rm 'for a do case "$a" in "$TMPDIR"/*) exit 1 ;; esac; done; exec "$REAL" "$@"'
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  "$P/bin/worktree-harness" --version
  assert_has "$stderr" "Warning: couldn't remove $TMPDIR/"
}
