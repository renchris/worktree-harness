#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# A repo with no .harnessrc, cwd in it.
make_repo_without_rc() {
  make_repo
  git rm -q .harnessrc
  git commit -qm rm
}

@test "init writes .harnessrc and prints its path" {
  make_repo_without_rc
  run --separate-stderr "$WH" init
  [ "$status" -eq 0 ]
  # pwd -P: git reports the resolved path, and $APP can sit behind a symlink.
  [ "$output" = "$(pwd -P)/.harnessrc" ]
  [ -s .harnessrc ]
  bash -n .harnessrc
  [ -z "$(find . -maxdepth 1 -name '.harnessrc.*')" ]
}

@test "init never overwrites" {
  make_repo_without_rc
  run "$WH" init
  [ "$status" -eq 0 ]
  local before; before="$(cksum < .harnessrc)"
  run "$WH" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]] || false
  [ "$(cksum < .harnessrc)" = "$before" ]
}

@test "init refuses a dangling symlink, also in a dry run" {
  make_repo_without_rc
  ln -s "$BATS_TEST_TMPDIR/nowhere" .harnessrc
  run "$WH" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]] || false
  run "$WH" init --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/nowhere" ]
}

@test "init names a failed write on its own" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"
  make_repo_without_rc
  chmod a-w .
  run "$WH" init
  chmod u+w .
  [ "$status" -eq 1 ]
  [[ "$output" == *"Couldn't write"* ]] || false
  [[ "$output" != *"already exists"* ]] || false
  [ ! -e .harnessrc ]
}

@test "init --dry-run writes nothing and prints nothing on stdout" {
  make_repo_without_rc
  run --separate-stderr "$WH" init --dry-run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"would write"* ]] || false
  [ ! -e .harnessrc ]
}

@test "init --help prints usage on stdout" {
  run --separate-stderr "$WH" init --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"worktree-harness init"* ]]
}

@test "init rejects extra arguments" {
  make_repo_without_rc
  run "$WH" init junk
  [ "$status" -ne 0 ]
  [ ! -e .harnessrc ]
}

@test "every init --help example parses" {
  assert_help_examples_parse init
}
