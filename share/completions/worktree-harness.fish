# fish completions for worktree-harness
set -l cmds new launch merge gc status init doctor help version

# subcommands (only when none chosen yet)
complete -c worktree-harness -f
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a new     -d "create a runnable worktree"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a launch  -d "create a worktree and exec your agent"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a merge   -d "rebase + gate + fast-forward (never pushes)"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a gc      -d "remove merged + idle worktrees"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a status  -d "list worktrees"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a init    -d "scaffold a .harnessrc"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a doctor  -d "diagnose env + validate config"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a help    -d "show help"
complete -c worktree-harness -n "not __fish_seen_subcommand_from $cmds" -a version -d "show version"

# per-subcommand flags
complete -c worktree-harness -n "__fish_seen_subcommand_from merge"  -l no-verify -d "skip the merge gate"
complete -c worktree-harness -n "__fish_seen_subcommand_from gc"     -l prune     -d "actually remove (default is dry-run)"
complete -c worktree-harness -n "__fish_seen_subcommand_from status" -l porcelain -d "tab-separated machine output"
complete -c worktree-harness -n "__fish_seen_subcommand_from new launch merge gc init" -l dry-run -d "preview without changing anything"
complete -c worktree-harness -l help -d "show help"
