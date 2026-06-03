#!/usr/bin/env bats
load helper

@test "gc keeps a dirty worktree" {
  make_repo
  "$WH" new feat
  ( cd "$WT_HOME/app/feat" && printf 'wip\n' > scratch.txt )   # untracked → dirty
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"        # isolate the dirty gate
  run "$WH" -C "$APP" gc --prune
  [ -d "$WT_HOME/app/feat" ]
  [[ "$output" == *"dirty"* ]]
}

@test "gc keeps an unmerged worktree" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"
  run "$WH" -C "$APP" gc --prune
  [ -d "$WT_HOME/app/feat" ]
  [[ "$output" == *"not in main"* ]]
}

@test "gc keeps a recently-touched worktree (idle gate)" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  ( cd "$WT_HOME/app/feat" && "$WH" merge )   # merged, but just touched
  run "$WH" -C "$APP" gc --prune
  [ -d "$WT_HOME/app/feat" ]
  [[ "$output" == *"modified <"* ]]
}

@test "gc reaps a merged + idle worktree but preserves its branch" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  ( cd "$WT_HOME/app/feat" && "$WH" merge )
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"        # disable recency
  "$WH" -C "$APP" gc --prune
  [ ! -d "$WT_HOME/app/feat" ]
  git -C "$APP" show-ref --verify --quiet refs/heads/feat
}

@test "gc dry-run (default) removes nothing" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  ( cd "$WT_HOME/app/feat" && "$WH" merge )
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"
  "$WH" -C "$APP" gc          # no --prune
  [ -d "$WT_HOME/app/feat" ]  # still there
}

@test "gc never reaps the main checkout" {
  make_repo
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"
  "$WH" -C "$APP" gc --prune
  [ -d "$APP" ]
}
