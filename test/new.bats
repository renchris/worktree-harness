#!/usr/bin/env bats
load helper

@test "new creates a worktree off origin, copies files, offsets ports" {
  make_repo
  run "$WH" new feat
  [ "$status" -eq 0 ]
  [ -d "$WT_HOME/app/feat" ]
  [ -f "$WT_HOME/app/feat/.env.local" ]
  grep -q "PORT=3001" "$WT_HOME/app/feat/.harness.env"
}

@test "new emits ONLY the worktree path on stdout" {
  make_repo
  path="$("$WH" new feat 2>/dev/null)"
  [ "$path" = "$WT_HOME/app/feat" ]
}

@test "the generated .harness.env does not make the worktree dirty" {
  make_repo
  "$WH" new feat
  run git -C "$WT_HOME/app/feat" status --porcelain
  [ -z "$output" ]
}

@test "new refuses the default branch" {
  make_repo
  run "$WH" new main
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to create a worktree on 'main'"* ]]
}

@test "new refuses an existing branch" {
  make_repo
  "$WH" new feat
  run "$WH" new feat
  [ "$status" -ne 0 ]
}

@test "new --dry-run creates nothing" {
  make_repo
  run "$WH" new feat --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$WT_HOME/app/feat" ]
}

@test "second worktree gets a distinct port offset" {
  make_repo
  "$WH" new feat
  "$WH" new feat2
  ! grep -q "PORT=3001" "$WT_HOME/app/feat2/.harness.env"
}
