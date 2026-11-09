---
name: worktree-harness
description: >
  Run parallel coding-agent sessions in isolated git worktrees and land them
  back safely. Use when the user wants to work on multiple branches/tasks at
  once without sessions clobbering each other, make a fresh worktree actually
  runnable (env files, deps, ports), or fast-forward a branch onto the default
  branch safely. Triggers: "parallel sessions", "git worktree", "isolate this
  work", "spin up a worktree", "land/merge my branch safely", "clean up worktrees".
---

# worktree-harness

A zero-dependency CLI (`git` + `bash` only) that gives each parallel agent
session its own git worktree — separate index, so sessions can't sweep each
other's staged files — and lands branches back with fast-forward-only,
never-push discipline.

## When to use it

- The user is (or wants to be) running **more than one agent/session at once** on
  the same project.
- They ask to **isolate** a piece of work, or a fresh worktree needs to be
  **runnable** (copy `.env`, install deps, assign non-colliding ports).
- They want to **land a branch safely** onto the default branch without a
  non-fast-forward clobber or an accidental push.
- They want to **tidy up** finished worktrees.

If the task is a single linear session on one branch, you don't need this.

## Commands

```sh
worktree-harness init                          # scaffold .harnessrc (detects the package manager)
worktree-harness new <BRANCH>                  # runnable worktree at ~/.worktrees/<repo>/<BRANCH>
worktree-harness launch [-- <COMMAND> [<ARG>]...]  # make a worktree and exec an agent in it
worktree-harness merge                         # rebase onto base + gate + fast-forward local default. never pushes.
worktree-harness status [--porcelain|--json]   # list worktrees: branch, ahead/behind, dirty, ports
worktree-harness gc [--prune] [--dry-run]      # preview, or remove merged+clean+idle worktrees (branches kept)
worktree-harness doctor                        # diagnose env + validate .harnessrc
worktree-harness help [<COMMAND>]              # overview, or one command's options and examples
```

Add `--dry-run` to `new`, `launch`, `merge`, `gc` or `init` to preview without
changing anything. `--cwd <DIR>` runs any command as if started in `<DIR>`.

## How to drive it

1. Once per repo: `worktree-harness init`, then review `.harnessrc` (which files
   to copy, ports, and `HARNESS_MERGE_GATE` = the typecheck/test command).
2. Per task: `worktree-harness new <branch>`; it prints the worktree path on
   stdout. `cd` there, `source .harness.env` if ports are configured, and work.
3. To land: from inside the worktree, `worktree-harness merge`. It rebases onto
   the base, runs the gate, and fast-forwards the **local** default branch. It
   does **not** push — run `git push` yourself when you mean to.
4. Cleanup: `worktree-harness gc --prune`.

## Gotchas worth knowing

- **`new` prints the worktree path on stdout** (everything else is stderr), so
  you can capture it: `wt="$(worktree-harness new feat)"`. Likewise `merge`
  prints the landed commit's SHA, `init` the `.harnessrc` path, and
  `gc --prune` the removed paths.
- **Read state with `status --json`** (or `--porcelain`), not the table: piped
  `status` output is tab-separated with a header and its summary on stderr.
- **A failed `new` names what it left behind.** If a copy, install or setup step
  fails, it exits 1 and prints the worktree and branch to remove, with the
  commands.
- **`merge` refuses a diverged base** and refuses on the default branch — that's
  correct, not a bug; resolve as instructed and re-run.
- **`gc` won't reap recent/dirty/unmerged worktrees.** To force-reap a just-made
  one in a test, set `HARNESS_GC_IDLE_MIN=0`.
- **Base policy.** Default `origin` (fetch, branch off `origin/<default>`). If
  the user's local default branch is canonical and origin is a stale fork, set
  `HARNESS_BASE_POLICY=local`. A failed fetch warns and continues from the
  last-known remote ref; `WH_NO_FETCH=1` skips the fetch on purpose (offline,
  or to keep the base fixed).
- **`launch` fails closed:** if it can't create the worktree on the main
  checkout, it refuses to launch rather than run un-isolated.
- **Exit codes:** 0 success; 1 error or usage error; 2 `merge` rebase conflict
  (resolve it, or run `git rebase --abort`); 64 unknown command; `doctor`
  exits with the number of blocking issues.
