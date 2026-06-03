# Changelog

All notable changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0]

Initial release.

### Added
- `new` — create and provision a worktree off the base branch: copy declared
  gitignored files (`chmod 0600` on secrets), install with the detected
  frozen-lockfile command, assign non-colliding ports (`.harness.env`), run
  `HARNESS_SETUP`.
- `launch` — always-isolate launcher for any agent; from the main checkout it
  creates a worktree and execs there, from a linked worktree or outside a repo
  it execs in place, and it **fails closed** if isolation can't be set up.
- `merge` — rebase the branch onto the base, verify ancestry, run
  `HARNESS_MERGE_GATE`, then fast-forward the local default branch.
  **Never pushes.**
- `gc` — remove merged + clean + idle worktrees behind six safety gates;
  branches are always preserved. Dry-run by default.
- `status` (human + `--porcelain`), `init` (scaffold `.harnessrc`), `doctor`.
- `.harnessrc` configuration, sourced as bash, with `origin` and `local` base
  policies (the diverged-origin / local-canonical case is first-class).
- Package-manager detection with frozen-lockfile commands: pnpm, npm,
  yarn (classic + berry), bun, uv, poetry, pipenv, pip, cargo, go.
- Shell integration for bash, zsh, and fish; POSIX `install.sh`.
- bats test suite (41 cases) and GitHub Actions CI: shellcheck, the suite on
  Linux and macOS, an explicit run under system bash 3.2, and an install smoke
  test.

[Unreleased]: https://github.com/chrisren/worktree-harness/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/chrisren/worktree-harness/releases/tag/v0.1.0
