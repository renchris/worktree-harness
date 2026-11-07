#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# Fail the test unless $1 is valid JSON that satisfies the Python expression $2 on d.
assert_json() {
  command -v python3 >/dev/null 2>&1 || skip "python3 isn't installed"
  printf '%s' "$1" | python3 -c 'import json,sys;d=json.load(sys.stdin);sys.exit(0 if eval(sys.argv[1]) else 1)' "$2"
}

# The path git reports: on macOS the temp dir sits behind a symlink.
real_path() { ( cd "$1" && pwd -P ); }

# Point status at a default branch that doesn't exist, so every compare fails.
break_default_branch() {
  printf 'HARNESS_DEFAULT_BRANCH="nope"\n' >> .harnessrc
}

@test "--porcelain output is unchanged (golden)" {
  make_repo
  "$WH" new feat
  run "$WH" status --porcelain
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "$(printf 'linked\tfeat\t+0/-0\t3001\t%s' "$(real_path "$WT_HOME/app/feat")")" ]
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "$(printf 'main\tmain\t-\t-\t%s' "$(real_path "$APP")")" ]
}

@test "--json is one valid document with ports by name" {
  make_repo
  "$WH" new feat
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_json "$output" 'd["worktrees"][1]["ports"]=={"PORT":3001}'
  assert_json "$output" 'd["pagination"]=={"next":None}'
}

@test "--json keeps every key, with null and empty values, for the main checkout" {
  make_repo
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 0 ]
  assert_json "$output" 'list(d["worktrees"][0])==["kind","branch","dirty","ahead","behind","ports","path"]'
  assert_json "$output" 'd["worktrees"][0]["kind"]=="main" and d["worktrees"][0]["dirty"] is False'
  assert_json "$output" 'd["worktrees"][0]["ahead"] is None and d["worktrees"][0]["behind"] is None'
  assert_json "$output" 'd["worktrees"][0]["ports"]=={}'
}

@test "--json reports real counts and dirty state for a linked worktree" {
  make_repo
  "$WH" new feat
  commit_in "$WT_HOME/app/feat"
  printf 'x\n' > "$WT_HOME/app/feat/untracked.txt"
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 0 ]
  assert_json "$output" 'd["worktrees"][1]["ahead"]==1 and d["worktrees"][1]["behind"]==0'
  assert_json "$output" 'd["worktrees"][1]["dirty"] is True and d["worktrees"][1]["kind"]=="linked"'
}

@test "--json stays valid with a hand-edited .harness.env" {
  make_repo
  "$WH" new feat
  printf 'export PORT=1\nexport PORT=2\nexport NAME="a b"\nexport ZIP=01234\nexport BARE\n# export NOT=1\n' > "$WT_HOME/app/feat/.harness.env"
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 0 ]
  assert_json "$output" 'd["worktrees"][1]["ports"]=={"PORT":2,"NAME":"\"a b\"","ZIP":"01234"}'
}

@test "--json with --porcelain is a usage error" {
  make_repo
  run "$WH" status --json --porcelain
  [ "$status" -ne 0 ]
  [[ "$output" == *"Can't use --json with --porcelain"* ]]
}

@test "--human stays accepted, isn't advertised, and can't combine with --json" {
  make_repo
  run "$WH" status --human
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH"* ]]
  run "$WH" status --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"--human"* ]]
  run "$WH" status --human --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"Can't use --json with --human"* ]]
}

@test "--help goes to stdout, teaches the porcelain columns and fits 80 columns" {
  make_repo
  run --separate-stderr "$WH" status --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"kind, branch, +ahead/-behind, ports,"* ]]
  [ -z "$(printf '%s\n' "$output" | awk 'length > 80')" ]
}

@test "footer uses a correct plural" {
  make_repo
  run "$WH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1 worktree "* ]]
  "$WH" new feat
  run "$WH" status
  [[ "$output" == *"(2 worktrees "* ]]
}

@test "piped stdout carries no ANSI even when stderr is a terminal" {
  command -v script >/dev/null 2>&1 || skip "script isn't installed, so no pty is available"
  make_repo
  cat > "$BATS_TEST_TMPDIR/piped.sh" <<SCRIPT
unset FORCE_COLOR NO_COLOR
"$WH" status | od -c
SCRIPT
  case "$(uname -s)" in
    Linux) run script -qec "bash $(printf '%q' "$BATS_TEST_TMPDIR/piped.sh")" /dev/null </dev/null ;;
    *)     run script -q /dev/null bash "$BATS_TEST_TMPDIR/piped.sh" </dev/null ;;
  esac
  [[ "$output" == *"B   R   A   N   C   H"* ]]
  [[ "$output" != *"033"* ]]
}

@test "--porcelain and --json stay unstyled under FORCE_COLOR" {
  make_repo
  FORCE_COLOR=1 run "$WH" status --porcelain
  [[ "$output" != *$'\033'* ]]
  FORCE_COLOR=1 run "$WH" status --json
  [[ "$output" != *$'\033'* ]]
}

@test "status outside a repo fails with a message" {
  make_norepo
  run "$WH" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside a git repository"* ]]
}

@test "a failed compare shows ? with one warning per worktree" {
  make_repo
  "$WH" new feat
  break_default_branch
  run --separate-stderr "$WH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"+?/-?"* ]]
  [[ "$stderr" == *"can't compare feat with nope: no local 'nope' branch"* ]]
  [ "$(printf '%s\n' "$stderr" | grep -c "can't compare feat")" -eq 1 ]
}

@test "a failed compare stays silent +0/-0 under --porcelain" {
  make_repo
  "$WH" new feat
  break_default_branch
  run --separate-stderr "$WH" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *$'\tfeat\t+0/-0\t'* ]]
}

@test "a failed compare is null in --json, with empty stderr and no warnings key" {
  make_repo
  "$WH" new feat
  break_default_branch
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_json "$output" 'd["worktrees"][1]["ahead"] is None and d["worktrees"][1]["behind"] is None'
  assert_json "$output" '"warnings" not in d'
}

@test "a failed dirty check is ? for people, empty for --porcelain, null for --json" {
  make_repo
  "$WH" new feat
  mv "$WT_HOME/app/feat" "$WT_HOME/app/gone"
  run --separate-stderr "$WH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"detached?"* ]]
  [[ "$stderr" == *"for uncommitted changes"* ]]
  run --separate-stderr "$WH" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *$'\tdetached\t-\t'* ]]
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_json "$output" 'd["worktrees"][1]["dirty"] is None'
}

@test "--fields keeps only the named keys" {
  make_repo
  "$WH" new feat
  run --separate-stderr "$WH" status --json --fields branch,path
  [ "$status" -eq 0 ]
  assert_json "$output" 'all(set(w)=={"branch","path"} for w in d["worktrees"])'
  assert_json "$output" 'd["pagination"]=={"next":None}'
}

@test "--fields takes a repeated name once, in schema order" {
  make_repo
  run --separate-stderr "$WH" status --json --fields path,kind,path
  [ "$status" -eq 0 ]
  [[ "$output" == '{"worktrees":[{"kind":"main","path":'* ]]
  [ "$(printf '%s' "$output" | grep -o '"path"' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "--fields rejects an unknown field and lists the valid ones" {
  make_repo
  run "$WH" status --json --fields nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"Valid fields: kind, branch, dirty"* ]]
}

@test "--fields refuses anything but whole field names" {
  make_repo
  local bad
  for bad in "" "branch," ",branch" "branch,,path" "kind branch" 'branch;id' 'BRANCH' '$(id)'; do
    run --separate-stderr "$WH" status --json --fields "$bad"
    [ "$status" -eq 1 ] || { echo "accepted: [$bad]"; false; }
    [ -z "$output" ] || { echo "stdout for: [$bad]"; false; }
    [[ "$stderr" == *'"reason":"invalid_arguments"'* ]] || { echo "reason for: [$bad]"; false; }
  done
}

@test "--fields without --json is a usage error" {
  make_repo
  run "$WH" status --fields branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"Can't use --fields without --json."* ]]
}

@test "--json failure is one JSON line on stderr" {
  make_norepo
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(printf '%s\n' "$stderr" | wc -l)" -eq 1 ]
  [[ "$stderr" == *'"reason":"repository_not_found"'* ]]
}

@test "--json config failure is one invalid_config line" {
  make_repo
  printf 'HARNESS_BASE_POLICY="bogus"\n' >> .harnessrc
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(printf '%s\n' "$stderr" | wc -l)" -eq 1 ]
  [[ "$stderr" == *'"reason":"invalid_config"'* ]]
}

@test "--json usage failures are one line with the right reason" {
  make_repo
  run --separate-stderr "$WH" status --json --bogus
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'"reason":"unknown_option"'* ]]
  run --separate-stderr "$WH" status --json --porcelain
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'"reason":"invalid_arguments"'* ]]
}

@test "a repository with no commits fails with a message and keeps its exit code" {
  git init -q "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty"
  run --separate-stderr "$WH" status
  [ "$status" -eq 128 ]
  [[ "$stderr" == *"default branch"* ]]
  run --separate-stderr "$WH" status --json
  [ "$status" -eq 128 ]
  [ -z "$output" ]
  [ "$(printf '%s\n' "$stderr" | wc -l)" -eq 1 ]
  [[ "$stderr" == *'"status":"error"'* ]]
}

@test "piped --json is compact" {
  make_repo
  "$WH" new feat
  run "$WH" status --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

@test "every status --help example parses" {
  make_repo
  assert_help_examples_parse status
}
