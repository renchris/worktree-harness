#!/usr/bin/env bash
# help_meta.sh — one machine-readable index of the commands: summary, usage,
# arguments, options, examples and the result schema. It feeds
# `<COMMAND> --help --json`, `help --all --json` and `help search`, and
# test/help.bats checks every `--help` text and completion file against it.
#
# Records are tab-separated; an empty field is "-". Columns after the kind and
# the command:
#   C  summary, usage
#   A  name, required, variadic, description                 (a positional)
#   O  long, short, type, value hint, default (JSON), accepted (comma list),
#      repeatable, deprecated, description                   (an option)
#   E  example (the words after "worktree-harness ")
#   S  result schema (compact JSON)
# Options are the ones each command's help lists under "Options:"; global
# options belong to root help. Deprecated options stay here, marked, so the
# completions can be checked against what's advertised.

# _wh_meta_rows — every record, one per line.
_wh_meta_rows() {
  cat <<'EOF'
C	new	Create a runnable worktree for <BRANCH>, branched off the base branch.	worktree-harness new <BRANCH> [options]
A	new	BRANCH	true	false	The new branch; it must not exist yet.
E	new	new <BRANCH>
E	new	new <BRANCH> --dry-run
C	launch	Create an auto-named worktree off the base branch and start your agent in it.	worktree-harness launch [options] [-- <COMMAND> [<ARG>]...]
A	launch	COMMAND	false	false	The command to run, after --. Default: the HARNESS_AGENT setting.
A	launch	ARG	false	true	Arguments for the command.
E	launch	launch
E	launch	launch -- <COMMAND>
C	merge	Land this worktree's branch on the LOCAL default branch. Never pushes.	worktree-harness merge [options]
O	merge	--dry-run	-	boolean	-	false	-	false	false	Show the steps and change nothing.
O	merge	--no-verify	-	boolean	-	false	-	false	false	Skip the merge gate.
E	merge	merge
E	merge	merge --no-verify
C	status	List every worktree with its branch, ahead/behind, ports and path.	worktree-harness status [options]
O	status	--fields	-	string	<FIELDS>	null	kind,branch,dirty,ahead,behind,ports,path	false	false	With --json, keep only these comma-separated keys.
O	status	--json	-	boolean	-	false	-	false	false	Print one JSON document.
O	status	--porcelain	-	boolean	-	false	-	false	false	Print tab-separated rows for scripts.
E	status	status
E	status	status --json --fields branch,path
E	status	status --porcelain
S	status	{"type":"object","properties":{"worktrees":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["main","linked"]},"branch":{"type":"string","description":"The branch, or detached when there is none."},"dirty":{"type":["boolean","null"],"description":"Uncommitted changes; null when git couldn't answer."},"ahead":{"type":["integer","null"],"description":"Commits ahead of the default branch; null when there is nothing to compare."},"behind":{"type":["integer","null"],"description":"Commits behind the default branch; null when there is nothing to compare."},"ports":{"type":"object","additionalProperties":{"type":["integer","string"]},"description":"Each name in <worktree>/.harness.env; a string when the value isn't an integer."},"path":{"type":"string"}}}},"pagination":{"type":"object","properties":{"next":{"type":"null"}}}}}
C	gc	Preview the worktrees that are ready to remove, or remove them with --prune.	worktree-harness gc [options]
O	gc	--dry-run	-	boolean	-	false	-	false	false	Preview only, even with --prune.
O	gc	--prune	-	boolean	-	false	-	false	false	Remove the worktrees that pass every check, without a prompt.
O	gc	--yes	-y	boolean	-	false	-	false	false	Accepted for scripts. gc doesn't prompt; --yes alone doesn't remove.
O	gc	--force	-	boolean	-	false	-	false	true	Use --prune.
E	gc	gc
E	gc	gc --prune
E	gc	gc --prune --yes
C	init	Write a starter .harnessrc in the repository root.	worktree-harness init [options]
O	init	--dry-run	-	boolean	-	false	-	false	false	Show what would be written and change nothing.
E	init	init
E	init	init --dry-run
C	doctor	Diagnose the environment and validate .harnessrc.	worktree-harness doctor [options]
E	doctor	doctor
C	version	Print the version.	worktree-harness version [options]
E	version	version
EOF
}

# _wh_meta_commands — the indexed commands, in help order. `version` has a
# record for `version --help --json` but isn't part of the index.
_wh_meta_commands() {
  local kind cmd rest
  while IFS="$(printf '\t')" read -r kind cmd rest; do
    if [ "$kind" = "C" ] && [ "$cmd" != "version" ]; then printf '%s\n' "$cmd"; fi
  done <<EOF
$(_wh_meta_rows)
EOF
}

# _wh_meta_json_or_null <field> — a JSON string, or null for "-".
_wh_meta_json_or_null() {
  if [ "$1" = "-" ]; then printf 'null'; else wh_json_str "$1"; fi
}

# _wh_meta_doc <cmd> — the command's help document, compact, no newline.
# Returns 1 when <cmd> has no record.
_wh_meta_doc() {
  local want="$1" kind cmd f1 f2 f3 f4 f5 f6 f7 f8 f9 found=0
  local summary="" args="" opts="" examples="" schema="null" accepted item
  while IFS="$(printf '\t')" read -r kind cmd f1 f2 f3 f4 f5 f6 f7 f8 f9; do
    if [ "$cmd" != "$want" ]; then continue; fi
    case "$kind" in
      C) found=1; summary="$f1" ;;
      A)
        args="${args:+$args,}{\"name\":$(wh_json_str "$f1"),\"required\":$f2,\"variadic\":$f3,\"description\":$(wh_json_str "$f4")}" ;;
      O)
        accepted=null
        if [ "$f6" != "-" ]; then
          accepted=""
          for item in $(printf '%s' "$f6" | tr ',' ' '); do
            accepted="${accepted:+$accepted,}$(wh_json_str "$item")"
          done
          accepted="[$accepted]"
        fi
        opts="${opts:+$opts,}{\"name\":$(wh_json_str "$f1"),\"short\":$(_wh_meta_json_or_null "$f2"),\"type\":$(wh_json_str "$f3"),\"valueHint\":$(_wh_meta_json_or_null "$f4"),\"default\":$f5,\"accepted\":$accepted,\"repeatable\":$f7,\"deprecated\":$f8,\"description\":$(wh_json_str "$f9")}" ;;
      E) examples="${examples:+$examples,}$(wh_json_str "worktree-harness $f1")" ;;
      S) schema="$f1" ;;
    esac
  done <<EOF
$(_wh_meta_rows)
EOF
  if [ "$found" = "0" ]; then return 1; fi
  printf '{"path":%s,"summary":%s,"arguments":[%s],"options":[%s],"examples":[%s],"lifecycle":null,"resultSchema":%s}' \
    "$(wh_json_str "worktree-harness $want")" "$(wh_json_str "$summary")" "$args" "$opts" "$examples" "$schema"
}

# _wh_help_json <cmd> — `<cmd> --help --json`: the command's help document.
_wh_help_json() {
  local doc
  if ! doc="$(_wh_meta_doc "$1")"; then
    wh_fail 1 internal_error "No help metadata is defined for worktree-harness $1."
  fi
  wh_json_out "$doc"
}

# _wh_help_all_json — `help --all --json`: one document per indexed command.
_wh_help_all_json() {
  local cmd docs=""
  for cmd in $(_wh_meta_commands); do
    docs="${docs:+$docs,}$(_wh_meta_doc "$cmd")"
  done
  wh_json_out "{\"commands\":[$docs]}"
}

# _wh_help_all_text — `help --all`: every indexed command's help, in order.
_wh_help_all_text() {
  local cmd first=1
  for cmd in $(_wh_meta_commands); do
    if [ "$first" = "0" ]; then printf '\n'; fi
    first=0
    ( _wh_dispatch "$cmd" --help )
  done
}

# _wh_meta_haystack <cmd> — one line to search: path, summary, option names and
# examples.
_wh_meta_haystack() {
  local want="$1" kind cmd f1 f2 rest line="worktree-harness $1"
  while IFS="$(printf '\t')" read -r kind cmd f1 f2 rest; do
    if [ "$cmd" != "$want" ]; then continue; fi
    case "$kind" in
      C) line="$line $f1" ;;
      O) line="$line $f1"; if [ "$f2" != "-" ]; then line="$line $f2"; fi ;;
      E) line="$line worktree-harness $f1" ;;
    esac
  done <<EOF
$(_wh_meta_rows)
EOF
  printf '%s\n' "$line"
}

# _wh_meta_summary <cmd> — the command's one-line summary.
_wh_meta_summary() {
  local kind cmd f1 rest
  while IFS="$(printf '\t')" read -r kind cmd f1 rest; do
    if [ "$kind" = "C" ] && [ "$cmd" = "$1" ]; then printf '%s' "$f1"; return 0; fi
  done <<EOF
$(_wh_meta_rows)
EOF
}

# _wh_help_search <arg...> — `help search <QUERY> [--json]`. The query is a
# fixed string matched without case; it is never written anywhere.
_wh_help_search() {
  local json=0 query="" have=0 a cmd summary n=0 items="" shown
  for a in "$@"; do
    case "$a" in --json|--json=true) json=1 ;; --no-json|--json=false) json=0 ;; esac
  done
  if [ "$json" = "1" ]; then WH_JSON=1; fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --json|--json=true|--no-json|--json=false) ;;
      --)
        shift
        if [ $# -gt 0 ]; then
          if [ "$have" = "1" ] || [ $# -gt 1 ]; then
            wh_usage_die "" "help search takes one <QUERY>; quote a query with spaces."
          fi
          query="$1"; have=1
        fi
        break ;;
      -h|--help) _wh_usage; return 0 ;;
      -?*) wh_usage_die "" "Unknown option $1 for worktree-harness help search." unknown_option ;;
      *)
        if [ "$have" = "1" ]; then
          wh_usage_die "" "help search takes one <QUERY>; quote a query with spaces."
        fi
        query="$1"; have=1 ;;
    esac
    shift
  done
  if [ -z "$query" ]; then
    wh_usage_die "" "help search needs a <QUERY>: worktree-harness help search <QUERY>."
  fi
  for cmd in $(_wh_meta_commands); do
    if [ "$n" -ge 10 ]; then break; fi
    if _wh_meta_haystack "$cmd" | grep -iqF -e "$query"; then
      n=$((n + 1))
      summary="$(_wh_meta_summary "$cmd")"
      if [ "$json" = "1" ]; then
        items="${items:+$items,}{\"path\":$(wh_json_str "worktree-harness $cmd"),\"summary\":$(wh_json_str "$summary")}"
      else
        printf 'worktree-harness %s  %s\n' "$cmd" "$summary"
      fi
    fi
  done
  if [ "$json" = "1" ]; then
    wh_json_out "{\"commands\":[$items]}"
  elif [ "$n" -eq 0 ]; then
    shown="$(printf '%s' "$query" | wh_sanitize_stream)"
    wh_info "No commands match \"${shown}\"."
  fi
}

# _wh_help_ext <arg...> — the `help` forms bin's _wh_help doesn't handle itself:
# `help --all [--json]`, `help --json`, `help <COMMAND> --json`, `help search …`.
_wh_help_ext() {
  local json=0 all=0 cmd="" a
  if [ "${1:-}" = "search" ]; then
    shift
    _wh_help_search "$@"
    return 0
  fi
  for a in "$@"; do
    case "$a" in --json|--json=true) json=1 ;; --no-json|--json=false) json=0 ;; esac
  done
  # shellcheck disable=SC2034 # read by wh_fail and wh_json_out in common.sh
  if [ "$json" = "1" ]; then WH_JSON=1; fi
  for a in "$@"; do
    case "$a" in
      --json|--json=true|--no-json|--json=false) ;;
      --all) all=1 ;;
      -h|--help) _wh_usage; return 0 ;;
      -?*) wh_usage_die "" "Unknown option $a for worktree-harness help." unknown_option ;;
      *)
        if [ -n "$cmd" ]; then
          wh_usage_die "" "Unexpected argument $a for worktree-harness help."
        fi
        cmd="$a" ;;
    esac
  done
  if [ -n "$cmd" ] && [ "$all" = "1" ]; then
    wh_usage_die "" "Can't use --all with a command."
  fi
  if [ -n "$cmd" ]; then
    case "$cmd" in
      create) cmd=new ;; run) cmd=launch ;; land) cmd=merge ;; prune) cmd=gc ;;
      ls|list) cmd=status ;;
    esac
    if ! _wh_is_command "$cmd"; then
      if [ "$json" = "1" ]; then
        wh_fail 64 unknown_command "Unknown command $cmd for worktree-harness." "worktree-harness --help"
      fi
      _wh_unknown_command "$cmd"
    fi
    if [ "$cmd" = "help" ]; then
      # help's own document is the index.
      if [ "$json" = "1" ]; then _wh_help_all_json; else _wh_usage; fi
    elif [ "$json" = "1" ]; then
      _wh_help_json "$cmd"
    else
      _wh_dispatch "$cmd" --help
    fi
    return 0
  fi
  if [ "$json" = "1" ]; then
    _wh_help_all_json
  elif [ "$all" = "1" ]; then
    _wh_help_all_text
  else
    _wh_usage
  fi
}
