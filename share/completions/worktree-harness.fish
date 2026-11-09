# fish completions for worktree-harness
set -l cmds new launch merge gc status init doctor help version

# commands (only when none chosen yet)
complete -c worktree-harness -f
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a new     -d "create a runnable worktree"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a launch  -d "create a worktree and run your agent"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a merge   -d "rebase + gate + fast-forward (never pushes)"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a gc      -d "preview or remove merged + idle worktrees"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a status  -d "list worktrees"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a init    -d "scaffold a .harnessrc"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a doctor  -d "diagnose env + validate config"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a help    -d "print help"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a version -d "print the version"

# global options
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -l cwd -x -a "(__fish_complete_directories)" -d "run as if started in DIR"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -l no-color -d "turn off color"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -l version  -d "print the version"

# per-command options
complete -c worktree-harness -n "__fish_seen_subcommand_from merge"  -l no-verify -d "skip the merge gate"
complete -c worktree-harness -n "__fish_seen_subcommand_from gc"     -l prune     -d "remove the worktrees that pass every check"
complete -c worktree-harness -n "__fish_seen_subcommand_from gc"     -s y -l yes  -d "accepted for scripts; never removes on its own"
complete -c worktree-harness -n "__fish_seen_subcommand_from status" -l porcelain -d "print tab-separated rows for scripts"
complete -c worktree-harness -n "__fish_seen_subcommand_from status" -l json      -d "print one JSON document"
complete -c worktree-harness -n "__fish_seen_subcommand_from status" -l fields -x -a "kind branch dirty ahead behind ports path" -d "with --json, keep only these keys"
complete -c worktree-harness -n "__fish_seen_subcommand_from help"   -a "$cmds"
complete -c worktree-harness -n "not __fish_seen_subcommand_from status doctor help version" -l dry-run -d "preview without changing anything"
complete -c worktree-harness -l help -d "show help"
