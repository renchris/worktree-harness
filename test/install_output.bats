#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper
load install_helper

# PATH without any worktree-harness the machine has installed, so each test decides
# whether the command resolves.
clean_path() {
  local IFS=: entry kept=""
  for entry in $PATH; do
    if [ ! -e "$entry/worktree-harness" ]; then kept="${kept:+$kept:}$entry"; fi
  done
  printf '%s' "$kept"
}

setup() {
  install_setup
  PATH="$(clean_path)"
  export PATH
  unset CI WH_GUIDANCE_DISABLED WORKTREE_HARNESS_REF
  # A shell with no offers, unless a test is about them.
  export SHELL=/bin/sh
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
}

common_version() { sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$WH_ROOT/lib/common.sh"; }

has_line() {
  if ! printf '%s\n' "$1" | grep -Fxq -- "$2"; then
    printf 'expected the line: %s\nin: %s\n' "$2" "$1"
    return 1
  fi
}

# The command under a failure's or a warning's instruction: the last line, unindented.
last_command() { printf '%s\n' "$1" | tail -n 1 | sed 's/^    //'; }

# The indented command on the line holding $2.
printed_command() { printf '%s\n' "$1" | grep -F -- "$2" | sed 's/^ *//'; }

# run_script_in_pty <script> — $output holds both streams, with the pty's \r removed.
run_script_in_pty() {
  command -v script >/dev/null 2>&1 || skip "script isn't installed, so no pty is available"
  case "$(uname -s)" in
    Linux) run script -qec "sh $(printf '%q' "$1")" /dev/null </dev/null ;;
    *) run script -q /dev/null sh "$1" </dev/null ;;
  esac
  output="$(printf '%s' "$output" | tr -d '\r')"
}

# --- A failed clone -----------------------------------------------------------

@test "a failed clone exits 1, says why, leaks nothing" {
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Couldn't clone"
  [ ! -e "$P/bin/worktree-harness" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "streams: a failed clone's progress and message are on stderr" {
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Error: Couldn't clone file:///nonexistent. Nothing was changed."
  assert_has "$stderr" "Cloning file:///nonexistent..."
  [ -z "$output" ]
}

@test "a failed clone shows a Detail row and one recovery command" {
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Couldn't clone"
  assert_has "$stderr" "  Detail          git: "
  has_line "$stderr" "    git ls-remote -- file:///nonexistent"
  assert_lacks "$output$stderr" "&&"
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a failed clone exits 1, not git's code, and says when git said nothing" {
  make_shim git 'exit 3'
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "git: no error text (exit 3)"
}

# record_prompt_setting — a git that records GIT_TERMINAL_PROMPT as the clone saw it,
# then fails the way git does, without contacting any host.
record_prompt_setting() {
  export BATS_TEST_TMPDIR
  make_shim git 'printf "%s\n" "${GIT_TERMINAL_PROMPT-unset}" > "$BATS_TEST_TMPDIR/prompt"; echo "fatal: no" >&2; exit 128'
}

@test "a prompt is never attempted" {
  record_prompt_setting
  unset GIT_TERMINAL_PROMPT
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/prompt")" = 0 ]
}

@test "GIT_TERMINAL_PROMPT=1 is honoured" {
  record_prompt_setting
  GIT_TERMINAL_PROMPT=1 PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/prompt")" = 1 ]
}

@test "a dash-leading repo URL is a usage error" {
  export BATS_TEST_TMPDIR
  make_shim git 'touch "$BATS_TEST_TMPDIR/git-ran"; exec "$REAL" "$@"'
  WORKTREE_HARNESS_REPO=--bogus PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_has "$stderr" "WORKTREE_HARNESS_REPO must be a repository URL, got: --bogus."
  [ ! -e "$BATS_TEST_TMPDIR/git-ran" ]
  [ ! -e "$P" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "the Detail row is git's first fatal line, not its last line" {
  make_shim git 'printf "Cloning into x...\nfatal: the cause\nfatal: the generic line\nhint: advice\n" >&2; exit 128'
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  has_line "$stderr" "  Detail          git: fatal: the cause"
  assert_lacks "$stderr" "the generic line"
  assert_lacks "$stderr" "advice"
}

@test "git's control characters don't reach the terminal" {
  make_shim git 'printf "fatal: a\033[31mb\n" >&2; exit 128'
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  has_line "$stderr" "  Detail          git: fatal: a[31mb"
}

@test "a URL credential never reaches the Detail row" {
  export WORKTREE_HARNESS_REPO='https://user:p@ss@127.0.0.1:9/x.git'
  run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_lacks "$output$stderr" "p@ss"
  assert_lacks "$output$stderr" "ss@"
  # The same, when git repeats the URL as it was given.
  make_shim git 'printf "fatal: unable to access '"'"'https://user:p@ss@127.0.0.1:9/x.git/'"'"'\n" >&2; exit 128'
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install
  [ "$status" -eq 1 ]
  assert_has "$stderr" "git: fatal: unable to access 'https://127.0.0.1:9/x.git/'"
  assert_lacks "$output$stderr" "p@ss"
  assert_lacks "$output$stderr" "ss@"
}

@test "missing git names the fix and the real prefix" {
  shim="$BATS_TEST_TMPDIR/nogit"
  mkdir -p "$shim"
  for tool in dirname mktemp sh; do ln -s "$(command -v "$tool")" "$shim/$tool"; done
  cd "$EMPTY"
  run --separate-stderr env PATH="$shim" "$shim/sh" -s < "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Can't clone worktree-harness. git isn't on PATH."
  assert_has "$stderr" "Install git, then rerun the installer:"
  assert_has "$stderr" "| sh -s -- --prefix $P"
  [ ! -e "$P" ]
}

# --- Failures before and during the install -----------------------------------

@test "a non-writable prefix is refused before any write" {
  if [ "$(id -u)" = 0 ]; then skip "root writes to a chmod 555 directory"; fi
  D="$BATS_TEST_TMPDIR/readonly"
  mkdir "$D"
  chmod 555 "$D"
  run --separate-stderr sh "$WH_ROOT/install.sh" --prefix "$D/p"
  chmod 755 "$D"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "isn't writable"
  assert_has "$stderr" "Nothing was changed."
  [ ! -e "$D/p" ]
  [ -z "$(ls -A "$TMPDIR")" ]
  recovery="$(last_command "$stderr")"
  assert_has "$recovery" "--prefix <DIR>"
  __WORKTREE_HARNESS_PARSE_ONLY=1 run sh -c "${recovery//<DIR>/$D/q}"
  [ "$status" -eq 0 ]
  [ ! -e "$D/q" ]
}

@test "the recovery command matches how the script started" {
  if [ "$(id -u)" = 0 ]; then skip "root writes to a chmod 555 directory"; fi
  D="$BATS_TEST_TMPDIR/readonly"
  mkdir "$D"
  chmod 555 "$D"
  run --separate-stderr piped_install --prefix "$D/p"
  piped="$stderr"
  run --separate-stderr sh "$WH_ROOT/install.sh" --prefix "$D/p"
  as_file="$stderr"
  chmod 755 "$D"
  assert_has "$piped" "| sh -s -- --prefix"
  assert_has "$as_file" "install.sh --prefix"
  assert_lacks "$as_file" "curl"
  assert_lacks "$piped$as_file" "WORKTREE_HARNESS_PREFIX="
}

@test "a failed copy says the previous install is unchanged" {
  if [ "$(id -u)" = 0 ]; then skip "root reads a chmod 000 file"; fi
  install_once
  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  chmod 000 "$src/lib/pm.sh"
  run --separate-stderr sh "$src/install.sh"
  [ "$status" -ne 0 ]
  assert_has "$stderr" "Couldn't copy files to $P/share/worktree-harness. The previous install is unchanged."
  "$P/bin/worktree-harness" --version
}

@test "a failed first copy claims no previous install" {
  if [ "$(id -u)" = 0 ]; then skip "root reads a chmod 000 file"; fi
  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  chmod 000 "$src/lib/pm.sh"
  run --separate-stderr sh "$src/install.sh"
  [ "$status" -ne 0 ]
  assert_has "$stderr" "Couldn't copy files to $P/share/worktree-harness."
  assert_lacks "$stderr" "previous install"
}

@test "a failed mktemp and a failed mkdir say so" {
  # Through env, because `run --separate-stderr` itself needs the real mktemp.
  make_shim mktemp 'exit 1'
  run --separate-stderr env PATH="$SHIMS:$PATH" sh -c 'cd "$1" && exec sh -s < "$2"' _ "$EMPTY" "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Failed to create a temporary directory."
  rm "$SHIMS/mktemp"
  make_shim mkdir 'exit 1'
  run --separate-stderr env PATH="$SHIMS:$PATH" sh "$WH_ROOT/install.sh"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Couldn't create the install directories under $P."
}

@test "a failed link names the files and reruns with the real prefix" {
  awkward="$BATS_TEST_TMPDIR/a b'c"
  make_shim ln 'exit 1'
  PATH="$SHIMS:$PATH" run --separate-stderr sh "$WH_ROOT/install.sh" --prefix "$awkward"
  [ "$status" -eq 1 ]
  assert_has "$stderr" "Couldn't link $awkward/bin/worktree-harness. Files are in $awkward/share/worktree-harness."
  assert_lacks "$stderr" "<DIR>"
  recovery="$(last_command "$stderr")"
  run sh -c "$recovery"
  [ "$status" -eq 0 ]
  "$awkward/bin/worktree-harness" --version
}

# --- PATH states --------------------------------------------------------------

@test "PATH states: on PATH, off PATH, shadowed" {
  PATH="$P/bin:$PATH" run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "Warning:"
  has_line "$output" "    worktree-harness new <BRANCH>"

  rm "$P/bin/worktree-harness"
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$output" "Warning: worktree-harness isn't on PATH, so the command won't resolve. Add it:"
  has_line "$output" "    $P/bin/worktree-harness new <BRANCH>"

  decoy="$BATS_TEST_TMPDIR/decoy"
  mkdir "$decoy"
  printf '#!/bin/sh\n' > "$decoy/worktree-harness"
  chmod +x "$decoy/worktree-harness"
  PATH="$decoy:$P/bin:$PATH" run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$output" "resolves to $decoy/worktree-harness, not this install"
  has_line "$output" "    $P/bin/worktree-harness new <BRANCH>"
}

@test "a trailing-slash PATH entry counts as on PATH" {
  PATH="$P/bin/:$PATH" run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "Warning:"
  has_line "$output" "    worktree-harness new <BRANCH>"
}

@test "a symlinked prefix counts as on PATH" {
  real="$BATS_TEST_TMPDIR/real"
  mkdir -p "$real"
  ln -s "$real" "$P"
  PATH="$real/bin:$PATH" run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "Warning:"
}

@test "the printed PATH command works for an awkward prefix" {
  awkward="$BATS_TEST_TMPDIR/a b'c"
  run sh "$WH_ROOT/install.sh" --prefix "$awkward"
  [ "$status" -eq 0 ]
  line="$(printed_command "$output" "export PATH=")"
  [ -n "$line" ]
  run sh -c "$line; command -v worktree-harness"
  [ "$status" -eq 0 ]
  [ "$output" = "$awkward/bin/worktree-harness" ]
}

@test "fish gets a PATH command fish can run" {
  SHELL=/usr/bin/fish run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  has_line "$output" "    fish_add_path $P/bin"
  assert_lacks "$output" "export PATH="
}

# --- Next steps ---------------------------------------------------------------

@test "next steps print one command per line" {
  for shell_name in bash zsh fish; do
    SHELL="/bin/$shell_name" run sh "$WH_ROOT/install.sh"
    [ "$status" -eq 0 ]
    assert_lacks "$output" "&&"
    assert_lacks "$output" '`'
    assert_lacks "$output" "·"
    if printf '%s\n' "$output" | grep -q '^ *\$ '; then
      printf 'a line starts with a prompt: %s\n' "$output"
      false
    fi
  done
}

@test "next steps follow the current directory" {
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  cd "$repo"
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  has_line "$output" "    $P/bin/worktree-harness init"
  assert_lacks "$output" "cd <REPO>"

  touch "$repo/.harnessrc"
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" " init"
  assert_has "$output" "new <BRANCH>"

  cd "$EMPTY"
  run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  before_init="${output%%worktree-harness init*}"
  assert_has "$before_init" "    cd <REPO>"
}

@test "a backslash in the prefix survives under dash" {
  command -v dash >/dev/null 2>&1 || skip "dash isn't installed"
  prefix="$BATS_TEST_TMPDIR/a\\tb"
  run dash "$WH_ROOT/install.sh" --prefix "$prefix"
  [ "$status" -eq 0 ]
  assert_has "$output" "Installed worktree-harness"
  assert_has "$output" "$prefix/bin/worktree-harness."
  "$prefix/bin/worktree-harness" --version
}

@test "the guidance variable hides optional steps and keeps the warning" {
  SHELL=/bin/zsh WH_GUIDANCE_DISABLED=1 run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "Next steps"
  assert_lacks "$output" "shell integration"
  assert_lacks "$output" "Uninstall"
  assert_has "$output" "isn't on PATH"
  assert_has "$output" "export PATH="
  WH_GUIDANCE_DISABLED="" run sh "$WH_ROOT/install.sh"
  assert_has "$output" "Next steps"
}

@test "optional offers are hidden in CI" {
  SHELL=/bin/zsh CI=1 run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "shell integration"
  assert_lacks "$output" "completions"
  assert_has "$output" "export PATH="
  assert_has "$output" "Create a worktree:"
}

@test "offers are real commands for the detected shell only, without a terminal" {
  shell_dir="$P/share/worktree-harness/share/shell"
  completions="$P/share/worktree-harness/share/completions"

  SHELL=/bin/bash run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  has_line "$output" "    source $shell_dir/bash.sh"
  has_line "$output" "    source $completions/worktree-harness.bash"
  assert_lacks "$output" "zsh.sh"
  assert_lacks "$output" "fish"

  SHELL=/usr/local/bin/zsh run sh "$WH_ROOT/install.sh"
  has_line "$output" "    source $shell_dir/zsh.sh"
  has_line "$output" "    fpath=($completions \$fpath)"
  assert_lacks "$output" "bash.sh"

  SHELL=/usr/bin/fish run sh "$WH_ROOT/install.sh"
  has_line "$output" "    source $shell_dir/fish.fish"
  has_line "$output" "    cp $completions/worktree-harness.fish ~/.config/fish/completions/"

  SHELL=/bin/ksh run sh "$WH_ROOT/install.sh"
  assert_lacks "$output" "shell integration"
  assert_lacks "$output" "completions"

  for file in "$shell_dir/bash.sh" "$shell_dir/zsh.sh" "$shell_dir/fish.fish" \
    "$completions/worktree-harness.bash" "$completions/_worktree-harness" "$completions/worktree-harness.fish"; do
    [ -f "$file" ]
  done
}

@test "the printed uninstall command removes both paths" {
  awkward="$BATS_TEST_TMPDIR/a b'c"
  run sh "$WH_ROOT/install.sh" --prefix "$awkward"
  [ "$status" -eq 0 ]
  line="$(printed_command "$output" "rm -rf -- ")"
  [ -n "$line" ]
  sh -c "$line"
  [ ! -e "$awkward/share/worktree-harness" ]
  [ ! -L "$awkward/bin/worktree-harness" ]
  [ -d "$awkward/bin" ]
}

# --- Receipts -----------------------------------------------------------------

@test "the receipt names the version and commit" {
  make_full_fixture
  run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Installed worktree-harness $(common_version)"
  assert_has "$stderr" "commit $(git -C "$FIXTURE" rev-parse --short HEAD), from "
  assert_has "$stderr" " to $P/bin/worktree-harness."
}

@test "WORKTREE_HARNESS_REF pins the clone and the receipt names it" {
  make_full_fixture
  git -C "$FIXTURE" tag v9
  commit="$(git -C "$FIXTURE" rev-parse --short HEAD)"
  printf 'later\n' > "$FIXTURE/bin/later"
  git -C "$FIXTURE" add bin/later
  git -C "$FIXTURE" commit -qm later
  WORKTREE_HARNESS_REF=v9 run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  [ ! -e "$P/share/worktree-harness/bin/later" ]
  assert_has "$stderr" "(commit $commit, from v9)"
  WORKTREE_HARNESS_REF="" run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  [ -e "$P/share/worktree-harness/bin/later" ]
}

@test "a copy inside another repository doesn't claim its commit" {
  outer="$BATS_TEST_TMPDIR/outer"
  git init -q "$outer"
  git -C "$outer" -c user.email=t@e.st -c user.name=T commit -q --allow-empty -m outer
  copy_checkout "$outer/copy"
  run --separate-stderr sh "$outer/copy/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$stderr" "commit "
  assert_has "$stderr" "Installed worktree-harness $(common_version) to $P/bin/worktree-harness."
}

@test "fresh, replaced, and unchanged receipts" {
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Installed worktree-harness"
  assert_lacks "$output$stderr" "Replaced"
  inode="$(ls -di "$P/share/worktree-harness")"

  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$stderr" "worktree-harness $(common_version) is already installed."
  assert_lacks "$stderr" "Installed"
  assert_has "$stderr" "isn't on PATH"
  [ "$(ls -di "$P/share/worktree-harness")" = "$inode" ]

  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  printf '# changed\n' >> "$src/lib/pm.sh"
  run --separate-stderr sh "$src/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Replaced $(common_version) (different content)."
  assert_has "$stderr" "Installed worktree-harness"

  installed="$P/share/worktree-harness/lib/common.sh"
  sed 's/^WH_VERSION=.*/WH_VERSION="0.1.0"/' "$installed" > "$installed.new"
  mv "$installed.new" "$installed"
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Replaced 0.1.0."

  sed '/^WH_VERSION=/d' "$installed" > "$installed.new"
  mv "$installed.new" "$installed"
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$stderr" "Replaced unknown version."
}

@test "an unchanged piped install leaks no temp clone" {
  make_full_fixture
  run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  run --separate-stderr piped_install
  [ "$status" -eq 0 ]
  assert_has "$stderr" "is already installed."
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a lost link isn't reported as already installed" {
  install_once
  rm "$P/bin/worktree-harness"
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output$stderr" "already installed"
  "$P/bin/worktree-harness" --version
}

@test "a dispatcher that lost its mode isn't reported as already installed" {
  install_once
  chmod -x "$P/share/worktree-harness/bin/worktree-harness"
  run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output$stderr" "already installed"
  "$P/bin/worktree-harness" --version
}

@test "a missing diff takes the safe path" {
  install_once
  shim="$BATS_TEST_TMPDIR/nodiff"
  mkdir -p "$shim"
  for tool in sh dirname mktemp sed git mkdir chmod cp mv ln rm ls readlink; do
    ln -s "$(command -v "$tool")" "$shim/$tool"
  done
  run --separate-stderr env PATH="$shim" "$shim/sh" "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output$stderr" "already installed"
  assert_has "$stderr" "Replaced"
}

# --- Closed streams -----------------------------------------------------------

@test "closed streams still install and exit 0" {
  run sh -c 'sh "$1" --prefix "$2" >&-' _ "$WH_ROOT/install.sh" "$BATS_TEST_TMPDIR/p1"
  [ "$status" -eq 0 ]
  "$BATS_TEST_TMPDIR/p1/bin/worktree-harness" --version

  run sh -c 'sh "$1" --prefix "$2" 2>&-' _ "$WH_ROOT/install.sh" "$BATS_TEST_TMPDIR/p2"
  [ "$status" -eq 0 ]
  "$BATS_TEST_TMPDIR/p2/bin/worktree-harness" --version

  # `true` closes the pipe at once on every OS; BSD head refuses `-n 0`.
  run bash -c 'sh "$1" --prefix "$2" | true; echo "${PIPESTATUS[0]}"' _ "$WH_ROOT/install.sh" "$BATS_TEST_TMPDIR/p3"
  [ "${lines[${#lines[@]} - 1]}" = "0" ]
  "$BATS_TEST_TMPDIR/p3/bin/worktree-harness" --version

  run sh -c 'sh "$1" --prefix "$2" >&- 2>&-' _ "$WH_ROOT/install.sh" "$BATS_TEST_TMPDIR/p4"
  [ "$status" -eq 0 ]
  "$BATS_TEST_TMPDIR/p4/bin/worktree-harness" --version
}

@test "a closed stderr doesn't abort a piped install, and stdout is the path" {
  make_full_fixture
  run bash -c 'cd "$1" && sh -s < "$2" 2>&- | head -n 1; echo "${PIPESTATUS[0]}"' _ "$EMPTY" "$WH_ROOT/install.sh"
  [ "${lines[0]}" = "$P/bin/worktree-harness" ]
  [ "${lines[${#lines[@]} - 1]}" = "0" ]
  "$P/bin/worktree-harness" --version
}

# --- Stdout contract ----------------------------------------------------------

@test "stdout is a bare path when captured" {
  p="$(sh "$WH_ROOT/install.sh" </dev/null 2>/dev/null)"
  [ "$p" = "$P/bin/worktree-harness" ]
  "$p" --version
}

@test "an interactive TTY gets the receipt and no bare path line" {
  TERM=dumb run_script_in_pty "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$output" "Installed worktree-harness"
  if printf '%s\n' "$output" | grep -Fxq -- "$P/bin/worktree-harness"; then
    printf 'a bare path line on an interactive terminal: %s\n' "$output"
    false
  fi
}

@test "CI=1 on a TTY prints the bare path" {
  CI=1 TERM=dumb run_script_in_pty "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  has_line "$output" "$P/bin/worktree-harness"
}

# --- Glyph modes --------------------------------------------------------------

@test "plain output is ASCII from column 0" {
  SHELL=/bin/zsh run sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | LC_ALL=C tr -d '\011\012\040-\176' | wc -c | tr -d ' ')" = 0 ]
  printf '%s\n' "$output" | grep -q '^Installed worktree-harness'
  printf '%s\n' "$output" | grep -q '^Warning: worktree-harness'
  assert_has "$output" "(local checkout)..."
  assert_has "$output" "Installing to $P/share/worktree-harness..."
}

@test "plain failures start with Error:" {
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run piped_install
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | LC_ALL=C tr -d '\011\012\040-\176' | wc -c | tr -d ' ')" = 0 ]
  printf '%s\n' "$output" | grep -q "^Error: Couldn't clone"
}

@test "rich rows use the 16-character label column" {
  commit="$(git -C "$WH_ROOT" rev-parse --short HEAD)"
  TERM=xterm run_script_in_pty "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  has_line "$output" "✓ Installed worktree-harness $(common_version)"
  has_line "$output" "  Path            $P/bin/worktree-harness"
  has_line "$output" "  Version         $(common_version) (commit $commit)"
  has_line "$output" "→ Installing to $P/share/worktree-harness…"
  assert_has "$output" "! worktree-harness isn't on PATH"
}

@test "rich failures use the cross, and the Replaced row uses the column" {
  install_once
  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  printf '# changed\n' >> "$src/lib/pm.sh"
  TERM=xterm run_script_in_pty "$src/install.sh"
  [ "$status" -eq 0 ]
  has_line "$output" "  Replaced        $(common_version) (different content)"

  cp "$WH_ROOT/install.sh" "$EMPTY/install.sh"
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  TERM=xterm run_script_in_pty "$EMPTY/install.sh"
  assert_has "$output" "✗ Couldn't clone file:///nonexistent. Nothing was changed."
  assert_has "$output" "→ Cloning file:///nonexistent…"
}

@test "a dumb or missing TERM is plain on a terminal" {
  TERM=dumb run_script_in_pty "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "✓"
  assert_has "$output" "Installed worktree-harness"

  # Under `script`, whose own TERM handling differs by OS, the empty value stands in
  # for unset: the installer reads both through ${TERM:-dumb}.
  TERM="" run_script_in_pty "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_lacks "$output" "✓"
}
