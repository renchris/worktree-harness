#!/usr/bin/env bats
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
