# bash completion for worktree-harness
_worktree_harness() {
  local cur cmds sub i
  cur="${COMP_WORDS[COMP_CWORD]}"
  cmds="new launch merge gc status init doctor help version"

  # Find the subcommand: first non-flag word after the program (skip -C <dir>).
  sub=""
  i=1
  while [ "$i" -lt "$COMP_CWORD" ]; do
    case "${COMP_WORDS[i]}" in
      -C) i=$((i + 2)); continue ;;
      -*) i=$((i + 1)); continue ;;
      *)  sub="${COMP_WORDS[i]}"; break ;;
    esac
  done

  if [ -z "$sub" ]; then
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "$cmds -C --dry-run --no-color --help --version" -- "$cur") )
    return
  fi

  local flags="--help"
  case "$sub" in
    new|launch|init) flags="--dry-run --help" ;;
    merge)           flags="--no-verify --dry-run --help" ;;
    gc)              flags="--prune --dry-run --help" ;;
    status)          flags="--porcelain --help" ;;
    doctor)          flags="--help" ;;
  esac
  # shellcheck disable=SC2207
  COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
}
complete -F _worktree_harness worktree-harness
