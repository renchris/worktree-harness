#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# Run merge from worktree $1 with any further arguments; quoting survives any path.
run_merge() {
  local wt="$1"; shift
  run --separate-stderr bash -c 'cd "$1" && shift && "$@"' _ "$wt" "$WH" merge "$@"
}

# Commit a merge gate into worktree $1's .harnessrc, which is the copy merge loads.
commit_gate() {
  ( cd "$1" && printf 'HARNESS_MERGE_GATE=%q\n' "$2" >> .harnessrc \
    && git add .harnessrc && git commit -qm "gate" )
}

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

@test "merge prints the landed commit on stdout" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$APP" rev-parse main)" ]
  [ "$output" = "$(git -C "$WT_HOME/app/feat" rev-parse HEAD)" ]
}

@test "merge on an already-landed branch prints the same SHA" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 0 ]
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$APP" rev-parse main)" ]
}

@test "merge --dry-run prints nothing on stdout" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  run_merge "$WT_HOME/app/feat" --dry-run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Already landed takes an earlier return, which must stay quiet too.
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 0 ]
  run_merge "$WT_HOME/app/feat" --dry-run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "merge strips control characters from commit subjects" {
  make_repo
  "$WH" new feat
  ( cd "$WT_HOME/app/feat" && printf 'x\n' > evil.txt && git add evil.txt \
    && git commit -qm $'evil \033[31m red' )
  [[ "$(git -C "$WT_HOME/app/feat" log -1 --format=%s)" == *$'\033'* ]] || false
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *$'\033'* ]] || false
  [[ "$stderr" == *"evil"* ]]
}

@test "merge outside a repo fails with a message" {
  make_norepo
  run "$WH" merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside a git repository"* ]]
}

@test "a merge gate's output stays off stdout" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  commit_gate "$WT_HOME/app/feat" "echo gate-output"
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$APP" rev-parse main)" ]
  [[ "$stderr" == *"gate-output"* ]]
}

@test "a failed merge gate names the gate and the way back" {
  make_repo
  local before; before="$(git -C "$APP" rev-parse main)"
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  commit_gate "$WT_HOME/app/feat" "false"
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"merge gate failed on the rebased tree: false. main was not updated."* ]] || false
  [[ "$stderr" == *"  worktree-harness merge"* ]] || false
  [ "$(git -C "$APP" rev-parse main)" = "$before" ]
}

@test "merge --no-verify lands past a failing gate" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  commit_gate "$WT_HOME/app/feat" "false"
  run_merge "$WT_HOME/app/feat" --no-verify
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$APP" rev-parse main)" ]
}

@test "a rebase conflict exits 2 and leaves main alone" {
  make_repo
  "$WH" new feat
  ( cd "$WT_HOME/app/feat" && printf 'feat\n' >> README.md && git commit -qam "feat readme" )
  ( cd "$APP" && printf 'main\n' >> README.md && git commit -qam "main readme" && git push -q origin main )
  local before; before="$(git -C "$APP" rev-parse main)"
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"git rebase --abort"* ]] || false
  [ "$(git -C "$APP" rev-parse main)" = "$before" ]
}

@test "a blocked fast-forward names the partial state" {
  make_repo
  local before; before="$(git -C "$APP" rev-parse main)"
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  printf x > "$APP/feat.txt"
  run_merge "$WT_HOME/app/feat"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Couldn't fast-forward main"* ]] || false
  [ "$(git -C "$APP" rev-parse main)" = "$before" ]
}

@test "a blocked fast-forward quotes the branch in its recovery command" {
  make_repo
  local wt; wt="$("$WH" new 'feat$(x)')"
  commit_in "$wt"
  printf x > "$APP/feat.txt"
  run_merge "$wt"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'merge --ff-only feat\$\(x\)'* ]] || false
  [[ "$stderr" != *'merge --ff-only feat$(x)'* ]]
}

@test "a failed ref-only fast-forward names the state and quotes its recovery command" {
  make_repo
  local before wt; before="$(git -C "$APP" rev-parse main)"
  wt="$("$WH" new 'feat$(x)')"
  commit_in "$wt"
  git -C "$APP" switch -q -c elsewhere
  : > "$APP/.git/refs/heads/main.lock"
  run_merge "$wt"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Couldn't move main"* ]] || false
  [[ "$stderr" == *'git fetch . feat\$\(x\):main'* ]] || false
  [ "$(git -C "$APP" rev-parse main)" = "$before" ]
}

@test "merge lands on a default branch checked out under a path with a space" {
  make_repo
  mv "$APP" "$BATS_TEST_TMPDIR/my app"
  cd "$BATS_TEST_TMPDIR/my app"
  "$WH" new feat
  commit_in "$WT_HOME/my app/feat"
  run_merge "$WT_HOME/my app/feat"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse main)" ]
  [ "$(git status --porcelain)" = "" ]
  [ -f feat.txt ]
}

@test "merge --help prints usage on stdout" {
  run --separate-stderr "$WH" merge --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"worktree-harness merge"* ]] || false
  [[ "$output" == *"WH_NO_FETCH=1"* ]]
}

@test "merge rejects extra arguments" {
  make_repo
  run "$WH" merge junk
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected argument junk"* ]]
}

@test "every merge --help example parses" {
  assert_help_examples_parse merge
}
