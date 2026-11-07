#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

@test "doctor flags a non-numeric HARNESS_GC_IDLE_MIN" {
  make_repo
  printf 'HARNESS_GC_IDLE_MIN="soon"\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARNESS_GC_IDLE_MIN"* ]]
  [[ "$output" == *"doctor: 1 issue above"* ]]
}

@test "doctor counts each invalid key" {
  make_repo
  printf 'HARNESS_BASE_POLICY="bogus"\nHARNESS_GC_IDLE_MIN="soon"\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -eq 2 ]
  [[ "$output" == *"HARNESS_BASE_POLICY"* ]]
  [[ "$output" == *"HARNESS_GC_IDLE_MIN"* ]]
  [[ "$output" == *"doctor: 2 issues above"* ]]
}

@test "doctor shows where .harnessrc breaks" {
  make_repo
  printf 'if then\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *".harnessrc fails to load:"* ]]
  [[ "$output" == *".harnessrc: line"* ]]
  [[ "$output" == *"bash -n"* ]]
}

@test "doctor relays a failing .harnessrc's stderr but not its values" {
  make_repo
  printf 'HARNESS_AGENT="s3cret-value"\nprintf "%%s\\n" "$HARNESS_AGENT"\nfalse\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *".harnessrc fails to load:"* ]]
  [[ "$output" != *"s3cret-value"* ]]
}

@test "doctor warns about an unknown package manager" {
  make_repo
  printf 'HARNESS_PACKAGE_MANAGER="pnmp"\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"pnmp"* ]]
  [[ "$output" == *"not a known package manager"* ]]
  [[ "$output" != *"skipping install"* ]]
}

@test "doctor warns about a malformed HARNESS_PORTS entry" {
  make_repo
  printf 'HARNESS_PORTS=( "PORT=3000" "1BAD=70" "API=soon" )\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"'1BAD=70'"* ]]
  [[ "$output" == *"'API=soon'"* ]]
  [[ "$output" != *"'PORT=3000'"* ]]
}

@test "doctor shows the gc idle setting" {
  make_repo
  printf 'HARNESS_GC_IDLE_MIN="45"\n' >> .harnessrc
  run "$WH" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"gc idle (min) : 45"* ]]
}

@test "doctor --help prints to stdout and lists its exit code" {
  run --separate-stderr "$WH" doctor --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"Usage: worktree-harness doctor [options]"* ]]
  [[ "$output" == *"Exits with the number of blocking issues; 0 means none."* ]]
}

@test "doctor rejects an unexpected argument" {
  make_repo
  run "$WH" doctor extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unexpected argument extra"* ]]
}

@test "every doctor --help example parses" {
  assert_help_examples_parse doctor
}
