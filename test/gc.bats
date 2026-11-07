#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# [[ ]] on a non-final line doesn't fail a test under bash 3.2, so these return
# non-zero and say what they looked for.
has() {
  case "$1" in *"$2"*) return 0 ;; esac
  printf 'expected %s in:\n%s\n' "$2" "$1"
  return 1
}
lacks() {
  case "$1" in *"$2"*) printf 'unexpected %s in:\n%s\n' "$2" "$1"; return 1 ;; esac
}

# A merged, clean, idle worktree on branch feat. FEAT is its path as git reports it
# (symlinks resolved), which is what gc prints.
reapable_fixture() {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  ( cd "$WT_HOME/app/feat" && "$WH" merge )
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"        # disable recency
  FEAT="$(cd "$WT_HOME/app/feat" && pwd -P)"
}

# A second worktree, feat2: reapable, because it adds nothing to main. Call after
# reapable_fixture. FEAT2 is its path as git reports it.
add_second_worktree() {
  "$WH" new feat2
  FEAT2="$(cd "$WT_HOME/app/feat2" && pwd -P)"
}

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

@test "global --dry-run beats gc --prune" {
  reapable_fixture
  run "$WH" -C "$APP" --dry-run gc --prune
  [ "$status" -eq 0 ]
  [ -d "$WT_HOME/app/feat" ]
  has "$output" "Remove  $FEAT"
  has "$output" "--dry-run overrides --prune"
  lacks "$output" "pass --prune"
}

@test "gc --prune --dry-run removes nothing" {
  reapable_fixture
  run "$WH" -C "$APP" gc --prune --dry-run
  [ "$status" -eq 0 ]
  [ -d "$WT_HOME/app/feat" ]
  has "$output" "Remove  $FEAT"
  run "$WH" -C "$APP" gc --dry-run --prune
  [ "$status" -eq 0 ]
  [ -d "$WT_HOME/app/feat" ]
  has "$output" "Remove  $FEAT"
}

@test "gc --prune rejects extra arguments" {
  reapable_fixture
  run "$WH" -C "$APP" gc --prune junk
  [ "$status" -ne 0 ]
  has "$output" "Unexpected argument junk"
  [ -d "$WT_HOME/app/feat" ]
}

@test "gc --force warns and still prunes" {
  reapable_fixture
  run "$WH" -C "$APP" gc --force
  [ "$status" -eq 0 ]
  has "$output" "deprecated"
  has "$output" "gc --prune"
  [ ! -d "$WT_HOME/app/feat" ]
}

@test "gc --yes alone only previews" {
  reapable_fixture
  run --separate-stderr "$WH" -C "$APP" gc --yes
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -d "$WT_HOME/app/feat" ]
  has "$stderr" "Remove  $FEAT"
  run "$WH" -C "$APP" gc -y
  [ "$status" -eq 0 ]
  [ -d "$WT_HOME/app/feat" ]
}

@test "gc --prune --yes removes" {
  reapable_fixture
  run "$WH" -C "$APP" gc --prune --yes
  [ "$status" -eq 0 ]
  [ ! -d "$WT_HOME/app/feat" ]
}

@test "gc --prune removes non-interactively without a prompt" {
  reapable_fixture
  run "$WH" -C "$APP" gc --prune </dev/null
  [ "$status" -eq 0 ]
  [ ! -d "$WT_HOME/app/feat" ]
}

@test "gc --prune prints removed paths on stdout" {
  reapable_fixture
  run --separate-stderr "$WH" -C "$APP" gc --prune
  [ "$status" -eq 0 ]
  [ "$output" = "$FEAT" ]
  has "$stderr" "Removed $FEAT"
  has "$stderr" "Removed 1 of 1 worktree. 0 failed."
}

@test "gc --prune exits 1 when a removal fails" {
  reapable_fixture
  git -C "$APP" worktree lock "$WT_HOME/app/feat"
  run "$WH" -C "$APP" gc --prune
  [ "$status" -eq 1 ]
  has "$output" "locked"
  has "$output" "Failed  $FEAT"
  has "$output" "1 failed"
  has "$output" "git worktree unlock"
  has "$output" "not atomic"
  [ -d "$WT_HOME/app/feat" ]
}

@test "gc --prune prints nothing on stdout when any removal fails" {
  reapable_fixture
  add_second_worktree
  git -C "$APP" worktree lock "$WT_HOME/app/feat2"
  run --separate-stderr "$WH" -C "$APP" gc --prune
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  has "$stderr" "Removed $FEAT"
  has "$stderr" "Removed 1 of 2 worktrees. 1 failed."
  [ ! -d "$WT_HOME/app/feat" ]
  [ -d "$WT_HOME/app/feat2" ]
}

@test "gc keeps a worktree whose dirty check fails" {
  reapable_fixture
  printf 'gitdir: /nonexistent\n' > "$WT_HOME/app/feat/.git"
  run "$WH" -C "$APP" gc --prune
  [ -d "$WT_HOME/app/feat" ]
  has "$output" "couldn't check"
}

@test "gc keeps a worktree whose recency check fails" {
  reapable_fixture
  printf 'HARNESS_GC_IDLE_MIN=5\n' >> "$APP/.harnessrc"
  mkdir "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/sh\necho "find: stubbed failure" >&2\nexit 1\n' > "$BATS_TEST_TMPDIR/stub/find"
  chmod +x "$BATS_TEST_TMPDIR/stub/find"
  PATH="$BATS_TEST_TMPDIR/stub:$PATH" run "$WH" -C "$APP" gc --prune
  [ "$status" -eq 0 ]
  [ -d "$WT_HOME/app/feat" ]
  has "$output" "couldn't check recency: find: stubbed failure"
}

@test "gc outside a repo fails with a message" {
  make_norepo
  run "$WH" gc
  [ "$status" -eq 1 ]
  has "$output" "outside a git repository"
}

@test "gc rows print full worktree paths and one label set" {
  reapable_fixture
  add_second_worktree
  printf 'wip\n' > "$WT_HOME/app/feat2/scratch.txt"
  run "$WH" -C "$APP" gc
  [ "$status" -eq 0 ]
  has "$output" "Remove  $FEAT [feat]"
  has "$output" "Keep    $FEAT2 [feat2] — dirty"
  local old_labels
  old_labels="$(printf '%s\n' "$output" | grep -cE '^(KEEP|WOULD|skip) ' || true)"
  [ "$old_labels" = "0" ]
  printf '%s\n' "$output" | grep -qx 'Remaining worktrees'
}

@test "gc says 1 commit and 2 commits for unmerged work" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  printf 'HARNESS_GC_IDLE_MIN=0\n' >> "$APP/.harnessrc"
  run "$WH" -C "$APP" gc
  has "$output" "1 commit not in main"
  commit_in "$WT_HOME/app/feat" second.txt
  run "$WH" -C "$APP" gc
  has "$output" "2 commits not in main"
}

@test "gc with nothing to remove says so" {
  make_repo
  run "$WH" -C "$APP" gc
  [ "$status" -eq 0 ]
  has "$output" "No worktrees are ready to remove."
  run "$WH" -C "$APP" gc --prune
  [ "$status" -eq 0 ]
  has "$output" "No worktrees are ready to remove."
  lacks "$output" "Removed 0"
}

@test "gc --help prints to stdout, fits 80 columns and hides --force" {
  run --separate-stderr "$WH" gc --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  has "$output" "-y, --yes"
  has "$output" "Exit codes: 0"
  lacks "$output" "--force"
  [ -z "$(printf '%s\n' "$output" | awk 'length($0) > 80')" ]
}

@test "every gc --help example parses" {
  assert_help_examples_parse gc
}
