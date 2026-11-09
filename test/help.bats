#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

# Help metadata (lib/help_meta.sh), help search, and drift guards: each command's
# --help text, its parser and the three completion files must agree with the
# metadata. The completions are hand-written (decision D-R2-9 (a)).

# A failing [[ ]] on a non-final line doesn't fail a test on bash 3.2.
has() { case "$1" in *"$2"*) return 0 ;; esac; printf 'missing: %s\nin: %s\n' "$2" "$1"; return 1; }

COMMANDS="new launch merge status gc init doctor"
# Global options as completions spell them; root help lists these.
GLOBALS="--cwd --dry-run --help --no-color --version -h -v"

# meta_options <cmd> [all] — the metadata's option names (long and short), sorted.
# Deprecated ones only with "all".
meta_options() {
  awk -F'\t' -v c="$1" -v all="${2:-}" '
    $1 == "O" && $2 == c && (all == "all" || $10 == "false") {
      print $3; if ($4 != "-") print $4
    }' "$WH_ROOT/lib/help_meta.sh" | sort -u
}

# help_options <cmd> — the option names under "Options:" in `<cmd> --help`.
help_options() {
  "$WH" "$1" --help | awk '
    /^Options:/ { inside = 1; next }
    /^[^ ]/     { inside = 0 }
    inside && /^  -/ {
      line = $0; sub(/^  /, "", line); sub(/  .*/, "", line)
      n = split(line, w, /[ ,]+/)
      for (i = 1; i <= n; i++) if (w[i] ~ /^-/) print w[i]
    }' | sort -u
}

# same_set <label> <expected> <actual> — newline lists, compared as sets.
same_set() {
  if [ "$2" != "$3" ]; then
    printf '%s differ\nexpected:\n%s\nactual:\n%s\n' "$1" "$2" "$3"
    return 1
  fi
}

# subset <label> <small> <big> — every line of <small> is a word of <big>.
subset() {
  local x
  for x in $2; do
    case " $(echo $3) " in *" $x "*) ;; *) printf '%s: %s is not allowed (allowed: %s)\n' "$1" "$x" "$(echo $3)"; return 1 ;; esac
  done
}

# completion_options <file> <cmd|ROOT> — option names a completion file offers.
completion_options() {
  local file="$1" c="$2"
  case "$file" in
    *.bash)
      if [ "$c" = "ROOT" ]; then
        sed -n 's/.*compgen -W "\$cmds \([^"]*\)".*/\1/p' "$file"
      else
        awk -v c="$c" '
          /local opts="/ { s = $0; sub(/.*local opts="/, "", s); sub(/".*/, "", s); def = s }
          /^[[:space:]]*[a-z|]+\)[[:space:]]+opts="/ {
            s = $0; sub(/^[[:space:]]*/, "", s); pat = s; sub(/\).*/, "", pat)
            n = split(pat, a, "|")
            for (i = 1; i <= n; i++) if (a[i] == c) { o = s; sub(/.*opts="/, "", o); sub(/".*/, "", o); got = o; hit = 1 }
          }
          END { if (!hit) got = def; print got }' "$file"
      fi | tr ' ' '\n' ;;
    *.fish)
      awk -v c="$c" '
        /^set -l cmds / { cmds = $0; sub(/^set -l cmds /, "", cmds) }
        /^complete -c worktree-harness/ && / -[ls] / {
          line = $0; gsub(/\$cmds/, cmds, line)
          neg = 0; cond = ""; has = 0
          if (match(line, /-n "[^"]*"/)) {
            cond = substr(line, RSTART + 4, RLENGTH - 5); has = 1
            if (cond ~ /^not /) { neg = 1; sub(/^not /, "", cond) }
            sub(/^__fish_seen_subcommand_from /, "", cond)
          }
          inlist = 0; n = split(cond, a, " ")
          for (i = 1; i <= n; i++) if (a[i] == c) inlist = 1
          if (!has) ok = 1
          else if (c == "ROOT") ok = neg
          else if (neg) ok = !inlist
          else ok = inlist
          if (!ok) next
          n = split(line, w, " ")
          for (i = 1; i < n; i++) {
            if (w[i] == "-l") print "--" w[i + 1]
            if (w[i] == "-s") print "-" w[i + 1]
          }
        }' "$file" ;;
    *)
      # zsh: join continued lines, then read '--name[' specs and {-y,--yes} groups.
      awk '{ if (sub(/\\$/, "")) { buf = buf $0; next } print buf $0; buf = "" }' "$file" |
        awk -v c="$c" -v q="'" '
          function specs(s,   t, n, a, i) {
            while (match(s, q "--?[a-z][a-z-]*[[]")) {
              t = substr(s, RSTART + 1, RLENGTH - 2); print t; s = substr(s, RSTART + RLENGTH)
            }
          }
          function groups(s,   t, n, a, i) {
            while (match(s, /[{]-[^}]*[}]/)) {
              t = substr(s, RSTART + 1, RLENGTH - 2); n = split(t, a, ",")
              for (i = 1; i <= n; i++) print a[i]
              s = substr(s, RSTART + RLENGTH)
            }
          }
          c == "ROOT" && /_arguments -C/ { specs($0); groups($0) }
          c != "ROOT" && /^[[:space:]]*[a-z|]+\)[[:space:]]+_arguments/ {
            pat = $0; sub(/^[[:space:]]*/, "", pat); sub(/\).*/, "", pat)
            n = split(pat, a, "|")
            for (i = 1; i <= n; i++) if (a[i] == c) { specs($0); groups($0) }
          }' ;;
  esac | grep -v '^$' | sort -u
}

# completion_commands <file> — the command names a completion file offers.
completion_commands() {
  case "$1" in
    *.bash) sed -n 's/^ *cmds="\([^"]*\)".*/\1/p' "$1" | tr ' ' '\n' ;;
    *.fish) sed -n 's/^set -l cmds //p' "$1" | tr ' ' '\n' ;;
    *)      sed -n "s/^ *'\([a-z]*\):.*/\1/p" "$1" ;;
  esac | grep -v '^$' | sort -u
}

@test "help --all --json lists every command" {
  run --separate-stderr "$WH" help --all --json
  [ "$status" -eq 0 ]
  # Count command documents only: status's result schema has a "path" field too.
  [ "$(printf '%s' "$output" | grep -o '"path":"worktree-harness ' | wc -l | tr -d ' ')" -eq 7 ]
  for c in $COMMANDS; do has "$output" "\"path\":\"worktree-harness $c\""; done
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$output" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert list(doc) == ["commands"], list(doc)
for c in doc["commands"]:
    assert list(c) == ["path", "summary", "arguments", "options", "examples", "lifecycle", "resultSchema"], list(c)
    assert c["summary"] and c["examples"], c["path"]
    for o in c["options"]:
        assert o["type"] in ("boolean", "string"), o
        assert isinstance(o["deprecated"], bool) and isinstance(o["repeatable"], bool), o
'
  fi
}

@test "status --help --json declares a result schema" {
  run --separate-stderr "$WH" status --help --json
  [ "$status" -eq 0 ]
  has "$output" '"path":"worktree-harness status"'
  has "$output" '"resultSchema":{"type":"object"'
  has "$output" '"pagination"'
  run --separate-stderr "$WH" gc --help --json
  [ "$status" -eq 0 ]
  has "$output" '"resultSchema":null'
  has "$output" '"name":"--force"'
  has "$output" '"deprecated":true'
}

@test "help <COMMAND> --json matches <COMMAND> --help --json" {
  run --separate-stderr "$WH" merge --help --json
  [ "$status" -eq 0 ]
  local direct="$output"
  run --separate-stderr "$WH" help merge --json
  [ "$status" -eq 0 ]
  [ "$output" = "$direct" ]
}

@test "help search remove finds gc" {
  run --separate-stderr "$WH" help search remove
  [ "$status" -eq 0 ]
  has "$output" "worktree-harness gc  Preview the worktrees"
  run --separate-stderr "$WH" help search PORCELAIN
  [ "$status" -eq 0 ]
  [ "$output" = "worktree-harness status  List every worktree with its branch, ahead/behind, ports and path." ]
}

@test "help search with no match exits 0 with the message" {
  run --separate-stderr "$WH" help search 'no.such*thing'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = 'No commands match "no.such*thing".' ]
}

@test "help search --json shape" {
  run --separate-stderr "$WH" help search --json prune
  [ "$status" -eq 0 ]
  [ "$output" = '{"commands":[{"path":"worktree-harness gc","summary":"Preview the worktrees that are ready to remove, or remove them with --prune."}]}' ]
  run --separate-stderr "$WH" help search zzz-nothing --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"commands":[]}' ]
  [ -z "$stderr" ]
}

@test "help search without a query is a usage error" {
  run --separate-stderr "$WH" help search
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  has "$stderr" "help search needs a <QUERY>"
  run --separate-stderr "$WH" help search --json
  [ "$status" -eq 1 ]
  has "$stderr" '"reason":"invalid_arguments"'
}

@test "drift: each --help Options section matches the metadata" {
  local c
  for c in $COMMANDS; do
    same_set "$c options" "$(meta_options "$c")" "$(help_options "$c")"
  done
  # status --human stays accepted and unadvertised.
  case "$(meta_options status all)" in *--human*) echo "status --human is advertised"; false ;; esac
}

@test "drift: every metadata option parses" {
  make_repo
  local c o value
  for c in $COMMANDS; do
    for o in $(meta_options "$c" all); do
      value="$(awk -F'\t' -v c="$c" -v o="$o" '
        $1 == "O" && $2 == c && ($3 == o || $4 == o) && $5 == "string" {
          v = $8; sub(/,.*/, "", v); print (v == "-" ? "x" : v)
        }' "$WH_ROOT/lib/help_meta.sh")"
      set -- "$o"
      if [ -n "$value" ]; then set -- "$o" "$value"; fi
      if [ "$c" = "new" ]; then set -- r2-branch "$@"; fi
      run env __WH_PARSE_ONLY=1 "$WH" "$c" "$@"
      [ "$status" -eq 0 ] || { echo "$c $* failed: $output"; false; }
    done
  done
}

@test "every metadata example parses" {
  make_repo
  local dir example
  printf -v dir '%q' "$BATS_TEST_TMPDIR"
  while IFS= read -r example; do
    example="${example//<BRANCH>/r2-example}"
    example="${example//<DIR>/$dir}"
    example="${example//<COMMAND>/true}"
    example="${example//<FIELDS>/branch,path}"
    ( export __WH_PARSE_ONLY=1; eval "\"\$WH\" $example" ) >/dev/null 2>&1 </dev/null \
      || { echo "example failed to parse: $example"; false; }
  done < <(awk -F'\t' '$1 == "E" { print $3 }' "$WH_ROOT/lib/help_meta.sh")
}

@test "drift: completions list exactly the canonical commands and options" {
  local f c expected got
  expected="$(printf '%s\n' $COMMANDS help version | sort -u)"
  for f in worktree-harness.bash _worktree-harness worktree-harness.fish; do
    f="$WH_ROOT/share/completions/$f"
    same_set "$f commands" "$expected" "$(completion_commands "$f")"
    got="$(completion_options "$f" ROOT)"
    same_set "$f global options" "$(printf '%s\n' --cwd --dry-run --help --no-color --version)" \
      "$(printf '%s\n' "$got" | grep -- '^--' | sort -u)"
    subset "$f global options" "$got" "$GLOBALS"
    for c in $COMMANDS; do
      got="$(completion_options "$f" "$c")"
      # Every advertised option is offered…
      subset "$f $c (missing from the completion)" "$(meta_options "$c")" "$got"
      # …and nothing else but the global options: no -C, -V, gc --force or status --human.
      subset "$f $c" "$got" "$(meta_options "$c") $GLOBALS"
    done
  done
}

@test "status --cwd works after the command" {
  make_repo
  cd /
  run --separate-stderr "$WH" status --cwd "$APP"
  [ "$status" -eq 0 ]
  has "$output" "$APP"
}
