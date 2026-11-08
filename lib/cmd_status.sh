#!/usr/bin/env bash
# cmd_status.sh — list worktrees with branch, ahead/behind vs the default
# branch, dirty flag, and the ports assigned in each worktree's .harness.env.
#
# Zero-dependency: pure git + awk (no jq). The rows go to STDOUT: an aligned
# table on a terminal or with --human, tab-separated with a header when piped.
# Warnings and the summary line go to stderr. --porcelain emits headerless
# tab-separated rows for scripts/CI; --json emits one document.

_WH_STATUS_FIELDS="kind branch dirty ahead behind ports path"

_wh_status_usage() {
  cat <<'EOF'
Usage:
  worktree-harness status [options]

List every worktree with its branch, ahead/behind, ports and path.

Options:
  --fields <FIELDS>  With --json, keep only these comma-separated keys: kind,
                     branch, dirty, ahead, behind, ports, path
  --json             Print one JSON document
  --porcelain        Print tab-separated rows for scripts

Global Options:
  worktree-harness --help

Examples:
    worktree-harness status
    worktree-harness status --json --fields branch,path
    worktree-harness status --porcelain

Notes:
  A * after the branch means uncommitted changes. Ahead/behind compares with
  the default branch, and - means there is nothing to compare. A ? means git
  couldn't answer; --json reports that as null.

  --porcelain columns, separated by tabs: kind, branch, +ahead/-behind, ports,
  path.

  Piped output is tab-separated with a header row, and the summary line goes
  to stderr. Scripts should use --porcelain or --json.

  Ports come from <worktree>/.harness.env.
EOF
}

# _wh_status_check_fields <list> — refuse anything but names from the fixed set.
# Tokens are compared whole, so no value ever reaches a shell or awk program.
_wh_status_check_fields() {
  local rest="$1," field valid="Valid fields: kind, branch, dirty, ahead, behind, ports, path."
  while [ -n "$rest" ]; do
    field="${rest%%,*}"; rest="${rest#*,}"
    if [ -z "$field" ]; then wh_usage_die status "Empty field in --fields. $valid"; fi
    case "$field" in
      *[!a-z]*) wh_usage_die status "Unknown field $field for worktree-harness status --fields. $valid" ;;
    esac
    case " $_WH_STATUS_FIELDS " in
      *" $field "*) ;;
      *) wh_usage_die status "Unknown field $field for worktree-harness status --fields. $valid" ;;
    esac
  done
}

# _wh_status_json_pairs <keep> — one worktree's "key":value pairs, in schema order,
# from wh_cmd_status's loop variables (dynamic scope). <keep> is space-separated, and
# only --fields ever shortens it: a null or empty value keeps its key.
_wh_status_json_pairs() {
  local name value out=""
  for name in $_WH_STATUS_FIELDS; do
    case " $1 " in *" $name "*) ;; *) continue ;; esac
    case "$name" in
      kind)   value="$(wh_json_str "$kind")" ;;
      branch) value="$(wh_json_str "$br")" ;;
      dirty)  value="$dirty_json" ;;
      ahead)  value="$ahead" ;;
      behind) value="$behind" ;;
      ports)  value="$ports" ;;
      path)   value="$(wh_json_str "$wt")" ;;
    esac
    out="${out:+$out,}\"$name\":$value"
  done
  printf '%s' "$out"
}

# _wh_status_ports_json <env-file> — the file's exports as a JSON object keyed by
# name. As when sourced, the last export of a name wins. Never fails: an absent or
# unreadable file is {}. A value that isn't a plain integer stays a string.
_wh_status_ports_json() {
  local name value out=""
  if [ -f "$1" ]; then
    while IFS=$'\t' read -r name value; do
      case "$value" in
        0) ;;
        ""|0*|*[!0-9]*) value="$(wh_json_str "$value")" ;;
      esac
      out="${out:+$out,}$(wh_json_str "$name"):$value"
    done < <(awk '/^export /{
        sub(/^export /, ""); i = index($0, "=")
        if (i < 2) next
        n = substr($0, 1, i - 1)
        if (!(n in val)) order[++count] = n
        val[n] = substr($0, i + 1)
      }
      END { for (k = 1; k <= count; k++) printf "%s\t%s\n", order[k], val[order[k]] }' "$1" 2>/dev/null || true)
  fi
  printf '{%s}' "$out"
}

wh_cmd_status() {
  # \001 marks "not given": --fields "" must fail, and bash 3.2 can't tell a
  # declared local from an empty one.
  local human=0 json=0 porcelain=0 not_given=$'\001' fields keep="$_WH_STATUS_FIELDS"
  fields="$not_given"
  wh_parse_opts status 0 "--fields=fields: --human=human --json=json --porcelain=porcelain" -- "$@"

  if [ "$json" = "1" ] && [ "$porcelain" = "1" ]; then
    wh_usage_die status "Can't use --json with --porcelain."
  fi
  if [ "$json" = "1" ] && [ "$human" = "1" ]; then
    wh_usage_die status "Can't use --json with --human."
  fi
  if [ "$fields" != "$not_given" ]; then
    if [ "$json" != "1" ]; then wh_usage_die status "Can't use --fields without --json."; fi
    _wh_status_check_fields "$fields"
    keep="${fields//,/ }"
  fi

  # Read by wh_die in common.sh, which shellcheck can't see from this file.
  # shellcheck disable=SC2034
  WH_FAIL_REASON=invalid_config
  wh_load_config
  # shellcheck disable=SC2034
  WH_FAIL_REASON=repository_not_found
  wh_require_repo status
  # shellcheck disable=SC2034
  WH_FAIL_REASON=""

  # table: aligned, for a terminal or --human. tsv: tab-separated with a header,
  # when stdout isn't a terminal. Both are the human modes: they warn, and their
  # summary line goes to stderr.
  local mode=tsv
  if [ "${WH_TTY_OUT:-0}" = "1" ] || [ "$human" = "1" ]; then mode=table; fi
  if [ "$porcelain" = "1" ]; then mode=porcelain; fi
  if [ "$json" = "1" ]; then mode=json; fi

  local main def wts count=0 items=""
  local wt br changes dirty dirty_json kind ab a b ahead behind ports
  main="$(wh_repo_root)"
  def="$(wh_default_branch)" \
    || wh_fail 128 internal_error "Can't find the default branch. Make a first commit or set HARNESS_DEFAULT_BRANCH in .harnessrc."
  wts="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')"

  case "$mode" in
    table)
      printf '%s%-24s %-11s %-15s %s%s\n' \
        "$WH_O_DIM" "BRANCH" "AHEAD/BEH" "PORTS" "PATH" "$WH_O_RESET" ;;
    tsv)
      printf 'KIND\tBRANCH\tDIRTY\tAHEAD\tBEHIND\tPORTS\tPATH\n' ;;
  esac

  while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    br="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
    [ -z "$br" ] && br="detached"

    dirty=""; dirty_json=false
    if changes="$(git -C "$wt" status --porcelain 2>/dev/null)"; then
      if [ -n "$changes" ]; then dirty="*"; dirty_json=true; fi
    else
      dirty_json=null
      # Porcelain leaves the column empty. kept: decision packet ad226c7513ea
      if [ "$mode" = "table" ] || [ "$mode" = "tsv" ]; then
        dirty="?"
        wh_warn "can't check $wt for uncommitted changes"
      fi
    fi

    kind="linked"; [ "$wt" = "$main" ] && kind="main"

    ab="-"; ahead=null; behind=null
    if [ "$br" != "detached" ] && [ "$br" != "$def" ]; then
      a="$(git -C "$main" rev-list --count "$def..$br" 2>/dev/null)" || a='?'
      b="$(git -C "$main" rev-list --count "$br..$def" 2>/dev/null)" || b='?'
      if [ "$a" != "?" ]; then ahead="$a"; fi
      if [ "$b" != "?" ]; then behind="$b"; fi
      if [ "$a" = "?" ] || [ "$b" = "?" ]; then
        case "$mode" in
          table|tsv)
            if git -C "$main" show-ref --verify --quiet "refs/heads/$def"; then
              wh_warn "can't compare $br with $def"
            else
              wh_warn "can't compare $br with $def: no local '$def' branch"
            fi ;;
          porcelain)
            # Stays byte-identical for scripts. kept: decision packet ad226c7513ea
            if [ "$a" = "?" ]; then a=0; fi
            if [ "$b" = "?" ]; then b=0; fi ;;
        esac
      fi
      ab="+$a/-$b"
    fi

    case "$mode" in
      json)
        ports="$(_wh_status_ports_json "$wt/.harness.env")"
        items="${items:+$items,}{$(_wh_status_json_pairs "$keep")}" ;;
      *)
        ports="-"
        if [ -f "$wt/.harness.env" ]; then
          ports="$(awk -F= '/^export /{sub(/^export /,""); printf "%s%s", sep, $2; sep=","}' "$wt/.harness.env" 2>/dev/null || true)"
          [ -z "$ports" ] && ports="-"
        fi
        case "$mode" in
          porcelain)
            printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$br$dirty" "$ab" "$ports" "$wt" ;;
          tsv)
            # DIRTY is yes|no|?; AHEAD and BEHIND are a count, - or ?.
            case "$dirty_json" in
              true) dirty=yes ;; false) dirty=no ;; *) dirty="?" ;;
            esac
            a="$ahead"; b="$behind"
            if [ "$a" = "null" ]; then a="?"; fi
            if [ "$b" = "null" ]; then b="?"; fi
            if [ "$ab" = "-" ]; then a="-"; b="-"; fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
              "$kind" "$br" "$dirty" "$a" "$b" "$ports" "$wt" ;;
          *)
            printf '%-24s %-11s %-15s %s\n' "$br$dirty" "$ab" "$ports" "$wt" ;;
        esac ;;
    esac
    count=$((count + 1))
  done <<EOF
$wts
EOF

  case "$mode" in
    json)
      wh_json_out "{\"worktrees\":[$items],\"pagination\":{\"next\":null}}" ;;
    table|tsv)
      # The summary is commentary, not data, so it stays out of stdout.
      printf '%s(%s · base: %s · '\''*'\'' = uncommitted)%s\n' \
        "$WH_C_DIM" "$(wh_plural "$count" worktree worktrees)" "$def" "$WH_C_RESET" >&2 ;;
  esac
}
