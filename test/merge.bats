#!/usr/bin/env bats
load helper

@test "merge fast-forwards the local default branch and never pushes" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  ( cd "$WT_HOME/app/feat" && "$WH" merge )
  run git -C "$APP" log --oneline
  [[ "$output" == *"feat: feat.txt"* ]]
  # origin must NOT have received it — merge is local-only
  run git -C "$APP" log origin/main --oneline
  [[ "$output" != *"feat: feat.txt"* ]]
}

@test "merge refuses to run on the default branch" {
  make_repo
  run "$WH" merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"you are ON 'main'"* ]]
}

@test "merge refuses with uncommitted changes" {
  make_repo
  "$WH" new feat
  ( cd "$WT_HOME/app/feat" && printf 'more\n' >> README.md )
  run bash -c "cd '$WT_HOME/app/feat' && '$WH' merge"
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "merge refuses a diverged base (ff-only safety)" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  # a local-only commit on main → main diverges from origin/main (the base)
  ( cd "$APP" && printf 'local\n' >> README.md && git commit -qam "local-only main commit" )
  run bash -c "cd '$WT_HOME/app/feat' && '$WH' merge"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ancestry"* ]]
  # main was NOT moved to the feature commit
  run git -C "$APP" log -1 --oneline
  [[ "$output" == *"local-only main commit"* ]]
}

@test "merge --dry-run changes nothing" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  ( cd "$WT_HOME/app/feat" && "$WH" merge --dry-run )
  run git -C "$APP" log --oneline
  [[ "$output" != *"feat: feat.txt"* ]]
}
