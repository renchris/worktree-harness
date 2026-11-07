#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# The failed-copy test leaves an unreadable directory that bats couldn't clean up.
teardown() {
  if [ -d "$BATS_TEST_TMPDIR/app/sec/x" ]; then chmod 755 "$BATS_TEST_TMPDIR/app/sec/x"; fi
}

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

@test "new --dry-run creates no parent dir and prints the planned path" {
  make_repo
  run --separate-stderr "$WH" new feat --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$WT_HOME/app/feat" ]
  [ ! -d "$WT_HOME/app" ]
  [[ "$stderr" == *"would create"* ]]
}

@test "globals work after the command" {
  make_repo
  run "$WH" new feat --no-color --dry-run
  [ "$status" -eq 0 ]
}

@test "new without a branch points at help" {
  make_repo
  run "$WH" new
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing branch name."* ]]
  [[ "$output" == *"See all options:"* ]]
  [[ "$output" == *"worktree-harness new --help"* ]]
  [[ "$output" != *"Create a runnable worktree"* ]]
}

@test "new outside a repository says so" {
  make_norepo
  run "$WH" new feat
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside a git repository"* ]]
}

@test "a mistyped option creates nothing" {
  make_repo
  run "$WH" new feat --dyr-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option --dyr-run for worktree-harness new."* ]]
  [ ! -d "$WT_HOME/app/feat" ]
  [ -z "$(git -C "$APP" branch --list feat)" ]
}

@test "a failed copy fails new and names the cleanup" {
  [ "$(id -u)" = 0 ] && skip "root can read a mode 000 directory"
  make_repo
  mkdir -p "$APP/sec/x"
  chmod 000 "$APP/sec/x"
  printf 'HARNESS_COPY+=("sec")\n' >> .harnessrc
  run --separate-stderr "$WH" new feat
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"copy failed: sec"* ]]
  [[ "$stderr" == *"Failed to provision worktree $WT_HOME/app/feat"* ]]
  [[ "$stderr" == *"git worktree remove --force"* ]]
  [[ "$stderr" == *"git branch -D feat"* ]]
  [[ "$stderr" != *"Next steps"* ]]
}

@test "a failing setup prints exactly one error" {
  make_repo
  printf 'HARNESS_SETUP=( "false" )\n' >> .harnessrc
  run --separate-stderr "$WH" new feat
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(printf '%s\n' "$stderr" | grep -c '^Error:')" -eq 1 ]
  [[ "$stderr" == *"setup step failed: false"* ]]
}

@test "a failed git worktree add names the worktree and git's message" {
  make_repo
  git update-ref -d refs/remotes/origin/main
  WH_NO_FETCH=1 run --separate-stderr "$WH" new feat
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(printf '%s\n' "$stderr" | grep -c '^Error:')" -eq 1 ]
  [[ "$stderr" == *"Couldn't create worktree $WT_HOME/app/feat for branch 'feat'"* ]]
  [[ "$stderr" == *"fatal:"* ]]
}

@test "port offsets are reused after a worktree is removed" {
  make_repo
  "$WH" new feat
  "$WH" new feat2
  git -C "$APP" worktree remove "$WT_HOME/app/feat"
  "$WH" new feat3
  grep -q "PORT=3001" "$WT_HOME/app/feat3/.harness.env"
}

@test "a .harness.env from before the offset marker still holds its offset" {
  make_repo
  "$WH" new feat
  printf 'export PORT=3001\n' > "$WT_HOME/app/feat/.harness.env"
  "$WH" new feat2
  grep -q "PORT=3002" "$WT_HOME/app/feat2/.harness.env"
}

@test ".harness.env starts with its offset and status still shows only ports" {
  make_repo
  umask 022
  "$WH" new feat
  [ "$(head -n 1 "$WT_HOME/app/feat/.harness.env")" = "# harness-offset=1" ]
  [[ "$(ls -l "$WT_HOME/app/feat/.harness.env")" == "-rw-r--r--"* ]]
  run "$WH" status --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t3001\t'* ]]
}

@test "copied secret files are owner-only" {
  make_repo
  chmod 644 .env.local
  "$WH" new feat
  [[ "$(ls -l "$WT_HOME/app/feat/.env.local")" == "-rw-------"* ]]
}

@test "a secret-named directory stays enterable after the copy" {
  make_repo
  mkdir config.env
  printf 'SECRET=1\n' > config.env/a
  printf 'HARNESS_COPY+=("config.env")\n' >> .harnessrc
  "$WH" new feat
  [[ "$(ls -ld "$WT_HOME/app/feat/config.env")" == "drwx------"* ]]
  [ "$(cat "$WT_HOME/app/feat/config.env/a")" = "SECRET=1" ]
}

@test "TERM during setup names the partial worktree" {
  make_repo
  local started="$BATS_TEST_TMPDIR/started" release="$BATS_TEST_TMPDIR/release"
  local out="$BATS_TEST_TMPDIR/out" err="$BATS_TEST_TMPDIR/err" pid rc=0 i=0
  # Setup holds until released, so the signal always lands while it runs. The loop
  # is bounded so a failing test can't leave it spinning. The trap fires when this
  # child returns, because bash defers it until a foreground command finishes.
  printf 'HARNESS_SETUP=( "touch %s; i=0; while [ ! -e %s ] && [ \\$i -lt 1200 ]; do sleep 0.1; i=\\$((i + 1)); done" )\n' \
    "$started" "$release" >> .harnessrc
  "$WH" new feat >"$out" 2>"$err" &
  pid=$!
  while [ ! -e "$started" ] && [ "$i" -lt 1200 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e "$started" ]
  kill -TERM "$pid"
  touch "$release"
  wait "$pid" || rc=$?
  [ "$rc" -eq 143 ]
  [ ! -s "$out" ]
  grep -q "Partial worktree left at $WT_HOME/app/feat" "$err"
  grep -q "git worktree remove --force" "$err"
  grep -q "git branch -D feat" "$err"
}

@test "the guidance variable hides next steps but keeps the path" {
  make_repo
  WH_GUIDANCE_DISABLED=1 run --separate-stderr "$WH" new feat
  [ "$status" -eq 0 ]
  [ "$output" = "$WT_HOME/app/feat" ]
  [[ "$stderr" != *"Next steps"* ]]
}

@test "next steps print by default, with no trailing comments" {
  make_repo
  run --separate-stderr "$WH" new feat
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Next steps:"* ]]
  [[ "$stderr" == *"worktree-harness gc --prune"* ]]
  [[ "$stderr" != *"  # "* ]]
}

@test "new and launch help name each other" {
  run "$WH" new --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree-harness launch"* ]]
  run "$WH" launch --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree-harness new <BRANCH>"* ]]
}

@test "every new/launch --help example parses" {
  assert_help_examples_parse new
  assert_help_examples_parse launch
}

@test "new and launch help go to stdout and stay within 80 columns" {
  local cmd
  for cmd in new launch; do
    run --separate-stderr "$WH" "$cmd" --help
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
    [[ "$output" == "Usage:"* ]]
    [[ "$output" == *"WH_NO_FETCH=1"* ]]
    [ -z "$(printf '%s\n' "$output" | awk 'length > 80')" ]
  done
}
