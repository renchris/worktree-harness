#!/usr/bin/env bats
load helper

@test "version prints name and a version" {
  run "$WH" --version
  [ "$status" -eq 0 ]
  [[ "$output" == worktree-harness\ * ]]
}

@test "help lists the core commands" {
  run "$WH" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"new"* ]]
  [[ "$output" == *"merge"* ]]
  [[ "$output" == *"gc"* ]]
  [[ "$output" == *"launch"* ]]
}

@test "unknown command exits 64" {
  run "$WH" definitely-not-a-command
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "unknown global flag is rejected" {
  run "$WH" --bogus-flag status
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown global flag"* ]]
}
