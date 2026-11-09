# bash completion for worktree-harness
_worktree_harness() {
  local cur prev cmds sub i
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  [ "$COMP_CWORD" -gt 0 ] && prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmds="new launch merge gc status init doctor help version"

  # A directory after --cwd; a field name after status --fields.
  case "$prev" in
    --cwd|-C)
      # shellcheck disable=SC2207
      COMPREPLY=( $(compgen -d -- "$cur") )
      return ;;
    --fields)
      # shellcheck disable=SC2207
      COMPREPLY=( $(compgen -W "kind branch dirty ahead behind ports path" -- "$cur") )
      return ;;
  esac

  # Find the command: the first word after the program that isn't an option
  # (skip --cwd <DIR>).
  sub=""
  i=1
  while [ "$i" -lt "$COMP_CWORD" ]; do
    case "${COMP_WORDS[i]}" in
      --cwd|-C) i=$((i + 2)); continue ;;
      -*) i=$((i + 1)); continue ;;
      *)  sub="${COMP_WORDS[i]}"; break ;;
    esac
  done

  if [ -z "$sub" ]; then
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "$cmds --cwd --dry-run --no-color --help --version" -- "$cur") )
    return
  fi

  local opts="--help"
  case "$sub" in
    new|launch|init) opts="--dry-run --help" ;;
    merge)           opts="--no-verify --dry-run --help" ;;
    gc)              opts="--prune --dry-run --yes -y --help" ;;
    status)          opts="--porcelain --json --fields --help" ;;
    doctor)          opts="--help" ;;
    help)            opts="$cmds" ;;
  esac
  # shellcheck disable=SC2207
  COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}
complete -F _worktree_harness worktree-harness
