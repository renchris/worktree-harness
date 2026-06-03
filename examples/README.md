# Example `.harnessrc` files

Copy one to your repo root as `.harnessrc` and adjust. Commit it so every
worktree inherits the same setup. (Generate a fresh one for your project with
`worktree-harness init`.)

| File | For |
|---|---|
| [`node-pnpm.harnessrc`](node-pnpm.harnessrc) | A Node/pnpm app on a team repo where `origin/main` is canonical |
| [`python-uv.harnessrc`](python-uv.harnessrc) | A Python service managed by `uv`, origin-canonical |
| [`local-canonical.harnessrc`](local-canonical.harnessrc) | Solo / diverged-fork workflow where your **local** default branch is canonical and origin is stale |

Remember: `.harnessrc` is **sourced as bash** — treat it like a `Makefile` and
only run `worktree-harness` in repos you trust.
