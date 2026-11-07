#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

@test "doctor reports the configured base policy and detected branch" {
  make_repo
  run "$WH" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"base policy   : origin"* ]]
  [[ "$output" == *"default branch: main"* ]]
}

@test "invalid HARNESS_BASE_POLICY is rejected" {
  make_repo
  printf 'HARNESS_BASE_POLICY="bogus"\n' >> .harnessrc
  run "$WH" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARNESS_BASE_POLICY"* ]]
}

@test "non-numeric HARNESS_GC_IDLE_MIN is rejected" {
  make_repo
  printf 'HARNESS_GC_IDLE_MIN="soon"\n' >> .harnessrc
  run "$WH" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARNESS_GC_IDLE_MIN"* ]]
}

@test "local base policy validates with no remote dependency" {
  make_repo
  printf 'HARNESS_BASE_POLICY="local"\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"base policy   : local"* ]]
}

@test "doctor reports detected package manager + install command" {
  make_repo
  touch pnpm-lock.yaml
  run "$WH" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"pnpm install --frozen-lockfile"* ]]
}

@test "new warns when the package manager is unknown" {
  make_repo
  printf 'HARNESS_PACKAGE_MANAGER="pnmp"\n' >> .harnessrc
  run --separate-stderr "$WH" new feat
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"not a known package manager"* ]]
  [ "$output" = "$WT_HOME/app/feat" ]
}

@test "a failed fetch names the remote and continues" {
  make_repo
  git -C "$APP" remote set-url origin "$BATS_TEST_TMPDIR/missing.git"
  run "$WH" new feat
  [ "$status" -eq 0 ]
  [[ "$output" == *"Couldn't fetch"* ]]
  [[ "$output" == *"missing.git"* ]]
  [[ "$output" == *"Using last-known origin/main."* ]]
}

@test "a failed fetch doesn't print credentials from the remote URL" {
  make_repo
  git -C "$APP" remote set-url origin "file://user:s3cret@$BATS_TEST_TMPDIR/missing.git"
  run "$WH" new feat
  [ "$status" -eq 0 ]
  [[ "$output" == *"Couldn't fetch"* ]]
  [[ "$output" != *"s3cret"* ]]
}

@test "new --dry-run does not fetch" {
  make_repo
  local before; before="$(git -C "$APP" rev-parse origin/main)"
  local second="$BATS_TEST_TMPDIR/second"
  git clone -q -b main "$ORIGIN" "$second"
  git -C "$second" config user.email t@e.st
  git -C "$second" config user.name Tester
  commit_in "$second"
  git -C "$second" push -q origin main
  [ "$(git -C "$ORIGIN" rev-parse main)" != "$before" ]
  "$WH" new feat --dry-run
  [ "$(git -C "$APP" rev-parse origin/main)" = "$before" ]
}
