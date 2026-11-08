#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper
load install_helper

# install.sh --json (plan B11). No assertion depends on key order.

# PATH without any worktree-harness the machine has installed, so each test decides
# whether the command resolves.
clean_path() {
  local IFS=: entry kept=""
  for entry in $PATH; do
    if [ ! -e "$entry/worktree-harness" ]; then kept="${kept:+$kept:}$entry"; fi
  done
  printf '%s' "$kept"
}

setup() {
  install_setup
  PATH="$(clean_path)"
  export PATH
  unset CI WH_GUIDANCE_DISABLED WORKTREE_HARNESS_REF
  export SHELL=/bin/sh
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
}

common_version() { sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$WH_ROOT/lib/common.sh"; }

need_python() { command -v python3 >/dev/null 2>&1 || skip "python3 isn't installed"; }

# jq_ <json> <python expression over d> — prints the value. json.load refuses
# anything after the first document.
jq_() {
  printf '%s' "$1" | python3 -I -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1]))' "$2"
}

line_count() { printf '%s\n' "$1" | grep -c .; }

@test "--json prints one document and nothing on stderr" {
  need_python
  run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(line_count "$output")" -eq 1 ]
  [ "$(jq_ "$output" 'd["install"]["path"]')" = "$P/bin/worktree-harness" ]
  [ "$(jq_ "$output" 'd["install"]["version"]')" = "$(common_version)" ]

  # Piped, through the clone, the same holds and no temp file is left.
  make_full_fixture
  run --separate-stderr piped_install --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_ "$output" 'd["install"]["path"]')" = "$P/bin/worktree-harness" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "--json outcome is installed, replaced, unchanged" {
  need_python
  run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ "$(jq_ "$output" 'd["outcome"]')" = installed ]

  run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_ "$output" 'd["outcome"]')" = unchanged ]

  src="$BATS_TEST_TMPDIR/src"
  copy_checkout "$src"
  printf '# changed\n' >> "$src/lib/pm.sh"
  run --separate-stderr sh "$src/install.sh" --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_ "$output" 'd["outcome"]')" = replaced ]
}

@test "--json next names the inspect command" {
  need_python
  PATH="$P/bin:$PATH" WH_GUIDANCE_DISABLED=1 run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ "$(jq_ "$output" 'd["next"][0]["argv"][-1]')" = doctor ]
  [ "$(jq_ "$output" 'd["next"][0]["argv"][0]')" = worktree-harness ]
  [ "$(jq_ "$output" 'd["next"][0]["command"]')" = "worktree-harness doctor" ]
  [ "$(jq_ "$output" '"warnings" in d')" = False ]

  run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ "$(jq_ "$output" 'd["next"][0]["argv"][0]')" = "$P/bin/worktree-harness" ]
}

@test "--json carries the PATH warning in the document" {
  need_python
  run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_ "$output" 'd["warnings"][0]["reason"]')" = not_on_path ]
  assert_has "$(jq_ "$output" 'd["warnings"][0]["message"]')" "export PATH="

  decoy="$BATS_TEST_TMPDIR/decoy"
  mkdir "$decoy"
  printf '#!/bin/sh\n' > "$decoy/worktree-harness"
  chmod +x "$decoy/worktree-harness"
  PATH="$decoy:$P/bin:$PATH" run --separate-stderr sh "$WH_ROOT/install.sh" --json
  [ "$status" -eq 0 ]
  [ "$(jq_ "$output" 'd["warnings"][0]["reason"]')" = shadowed ]
  [ "$(jq_ "$output" 'd["next"][0]["argv"][0]')" = "$P/bin/worktree-harness" ]
}

@test "--json failure is one line on stderr" {
  need_python
  export WORKTREE_HARNESS_REPO="file:///nonexistent"
  run --separate-stderr piped_install --json
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [ "$(line_count "$stderr")" -eq 1 ]
  assert_has "$stderr" '"reason":"clone_failed"'
  [ "$(jq_ "$stderr" 'd["status"]')" = error ]
  [ -z "$(ls -A "$TMPDIR")" ]

  # A failed clone keeps git's exit code.
  make_shim git 'exit 3'
  PATH="$SHIMS:$PATH" run --separate-stderr piped_install --json
  [ "$status" -eq 3 ]
  [ "$(line_count "$stderr")" -eq 1 ]
}

@test "--json usage error is one line, exit 2" {
  run --separate-stderr sh "$WH_ROOT/install.sh" --json --bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$(line_count "$stderr")" -eq 1 ]
  assert_has "$stderr" '"reason":"unknown_option"'

  run --separate-stderr sh "$WH_ROOT/install.sh" --bogus --json
  [ "$status" -eq 2 ]
  assert_has "$stderr" '"reason":"unknown_option"'

  run --separate-stderr sh "$WH_ROOT/install.sh" --json --prefix
  [ "$status" -eq 2 ]
  assert_has "$stderr" '"reason":"invalid_arguments"'
  [ ! -e "$P" ]
}

@test "--json escapes a quote and a backslash in the prefix" {
  need_python
  prefix="$BATS_TEST_TMPDIR/a\"b\\c"
  run --separate-stderr sh "$WH_ROOT/install.sh" --json --prefix "$prefix"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_ "$output" 'd["install"]["path"]')" = "$prefix/bin/worktree-harness" ]
}

@test "--json refuses a control character in the prefix" {
  prefix="$BATS_TEST_TMPDIR/a$(printf '\t')b"
  run --separate-stderr sh "$WH_ROOT/install.sh" --json --prefix "$prefix"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  assert_has "$stderr" '"reason":"invalid_arguments"'
  [ ! -e "$prefix" ]
}

@test "--json example parses" {
  sh "$WH_ROOT/install.sh" --help | grep -Fxq '    sh install.sh --json'
  export __WORKTREE_HARNESS_PARSE_ONLY=1
  for arg in --json --json=true --json=false --no-json; do
    run --separate-stderr sh "$WH_ROOT/install.sh" "$arg"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  run --separate-stderr sh "$WH_ROOT/install.sh" --json=maybe
  [ "$status" -eq 2 ]
  [ ! -e "$P" ]
}

@test "--version --json prints the version document" {
  need_python
  run --separate-stderr piped_install --version --json
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_ "$output" 'd["version"]')" = "$(common_version)" ]
  [ ! -e "$P" ]
}

@test "--json is indented on a terminal" {
  need_python
  command -v script >/dev/null 2>&1 || skip "script isn't installed, so no pty is available"
  case "$(uname -s)" in
    Linux) run script -qec "sh $(printf '%q' "$WH_ROOT/install.sh") --json" /dev/null </dev/null ;;
    *) run script -q /dev/null sh "$WH_ROOT/install.sh" --json </dev/null ;;
  esac
  [ "$status" -eq 0 ]
  # macOS script echoes the closed stdin as ^D before the document.
  doc="$(printf '%s' "$output" | tr -d '\r')"
  doc="{${doc#*\{}"
  printf '%s\n' "$doc" | grep -q '^  "install": {$'
  [ "$(jq_ "$doc" 'd["outcome"]')" = installed ]
}

@test "zero-argument output is unchanged by this unit" {
  p1="$BATS_TEST_TMPDIR/p1"
  p2="$BATS_TEST_TMPDIR/p2"
  WORKTREE_HARNESS_PREFIX="$p1" run --separate-stderr sh "$WH_ROOT/install.sh"
  [ "$status" -eq 0 ]
  assert_has "$output" "Installed worktree-harness $(common_version)"
  assert_has "$output" " to $p1/bin/worktree-harness."
  assert_has "$output" "Next steps:"
  assert_has "$output" "    $p1/bin/worktree-harness new <BRANCH>"
  assert_lacks "$output$stderr" '"outcome"'
  plain_out="${output//$p1/PREFIX}"
  plain_err="${stderr//$p1/PREFIX}"

  WORKTREE_HARNESS_PREFIX="$p2" run --separate-stderr sh "$WH_ROOT/install.sh" --no-json
  [ "$status" -eq 0 ]
  [ "${output//$p2/PREFIX}" = "$plain_out" ]
  [ "${stderr//$p2/PREFIX}" = "$plain_err" ]
}
