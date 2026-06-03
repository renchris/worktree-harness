# worktree-harness shell integration — bash.
#
# Makes your agent command(s) auto-isolate: when run from a project's MAIN
# checkout they launch inside a fresh git worktree; from a linked worktree or
# outside a repo they run in place. Mirrors the reso `claude()` wrapper, but for
# any agent and any project.
#
# Install (in ~/.bashrc, AFTER worktree-harness is on PATH):
#   export WORKTREE_HARNESS_AGENTS="claude"     # space-separated; e.g. "claude aider"
#   source /path/to/worktree-harness/share/shell/bash.sh
#
# Override per-invocation with WH_ISOLATION_SKIP=1 (run in place on the main checkout).
# Each agent must be a real executable on PATH (not itself a shell function/alias).

: "${WORKTREE_HARNESS_AGENTS:=claude}"
for _wh_agent in $WORKTREE_HARNESS_AGENTS; do
  eval "${_wh_agent}() { command worktree-harness launch -- ${_wh_agent} \"\$@\"; }"
done
unset _wh_agent
