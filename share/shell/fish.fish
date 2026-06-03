# worktree-harness shell integration — fish.
#
# Makes your agent command(s) auto-isolate: when run from a project's MAIN
# checkout they launch inside a fresh git worktree; from a linked worktree or
# outside a repo they run in place.
#
# Install (in ~/.config/fish/config.fish, AFTER worktree-harness is on PATH):
#   set -gx WORKTREE_HARNESS_AGENTS claude        # e.g. claude aider
#   source /path/to/worktree-harness/share/shell/fish.fish
#
# Override per-invocation with WH_ISOLATION_SKIP=1 (run in place on the main checkout).
# Each agent must be a real executable on PATH (not itself a function/alias).

if not set -q WORKTREE_HARNESS_AGENTS
    set -g WORKTREE_HARNESS_AGENTS claude
end

for _wh_agent in $WORKTREE_HARNESS_AGENTS
    # --inherit-variable snapshots _wh_agent at definition time, so each
    # generated function keeps its own agent name.
    function $_wh_agent --inherit-variable _wh_agent --wraps $_wh_agent
        command worktree-harness launch -- $_wh_agent $argv
    end
end
set --erase _wh_agent
