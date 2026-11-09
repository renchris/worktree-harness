# Changelog

All notable changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `--cwd <DIR>` runs a command as if started in `<DIR>`, and `-v` prints the
  version. Both work before or after the command.
- `help <COMMAND>` prints that command's help.
- `status --json` prints one document (ports keyed by name), and
  `--fields <FIELDS>` keeps only the named keys: kind, branch, dirty, ahead,
  behind, ports, path.
- Stdout carries each command's result: `merge` prints the landed commit's full
  SHA (also when the branch had already landed; nothing on a dry run), `init`
  prints the new `.harnessrc` path, and `gc --prune` prints the removed paths
  when every removal succeeded and stdout isn't an interactive terminal.
- `gc -y, --yes`, accepted for scripts. `gc` doesn't prompt, and `--yes` alone
  doesn't remove.
- Every command's `--help` has examples, and root help plus the `merge`, `gc`
  and `doctor` help list their exit codes.
- `WH_GUIDANCE_DISABLED=1` hides optional next steps and offers, in the CLI and
  `install.sh`. Required warnings always print.
- `doctor` warns about an unknown `HARNESS_PACKAGE_MANAGER` and a malformed
  `HARNESS_PORTS` entry, shows `gc idle (min) :`, has a full `--help`, and ends
  with `doctor: 1 issue above` or `doctor: 2 issues above`.
- `install.sh --help` (also `-h` and `help`) prints usage and does no work;
  `--version` prints the installer's version without cloning.
- `install.sh --prefix <DIR>` (or `--prefix=<DIR>`) picks the install location
  and beats `WORKTREE_HARNESS_PREFIX`.
- `WORKTREE_HARNESS_REF` pins the installer's clone to a branch or tag; by
  default it tracks `main`.
- The installer's receipt names the version and commit, and says whether it
  installed, replaced or found the same version `already installed`.
- `docs/DESIGN.md` gains a glossary and a list of the CLI conventions the tool
  knowingly keeps out of, with the reason for each.
- `install.sh --json` (also `--json=true|false` and `--no-json`) prints one
  document on stdout with the install path and version, the outcome
  (`installed`, `replaced` or `unchanged`), the next command and any PATH
  warnings, and nothing on stderr. A failure is one JSON line on stderr with an
  unchanged exit code. Under `--json` git never prompts for credentials, and a
  prefix containing a control character is refused before any write.
  `--version --json` prints `{"version":"<v>"}`.

### Changed
- Help goes to stdout. Root help is grouped by task, with `Usage:`,
  `Commands:`, `Global Options:` and `Learn more:` headings and a Notes block
  of exit codes.
- A usage error prints one line plus `See all options:` instead of the full
  usage. An unknown option reads `Unknown option <x> for worktree-harness.` and
  an unknown command `Unknown command <x> for worktree-harness.` (still exit 64).
- Global options that take no value accept `=true` or `=false`, and
  `--no-dry-run` and `--color` exist.
- Messages on a stderr that isn't a terminal start with `Warning:` or
  `Error:`; on a terminal the warning glyph is `!`.
- Progress lines read as what is happening, ending in `…`
  (`→ Fetching origin main…`).
- Piped `status` output is tab-separated with a header (`KIND`, `BRANCH`,
  `DIRTY`, `AHEAD`, `BEHIND`, `PORTS`, `PATH`), and the summary line moved to
  stderr. Scripts should use `--porcelain` or `--json`.
- `status --human` is still accepted but no longer documented.
- `gc` rows print full worktree paths with the labels Keep, Remove, Removed and
  Failed, under the heading `Remaining worktrees`, and say
  `No worktrees are ready to remove.` when nothing qualifies.
- `new` and `launch` accept options after their arguments, and their help pages
  point to each other. `new` with no branch prints one error and a pointer to
  its help.
- Port offsets are the smallest free one, so a removed worktree's ports are
  reused. `.harness.env` starts with `# harness-offset=N`; older files still
  read.
- `new`'s `Next steps:` are reworded without trailing comments, quote the `cd`
  path for the shell, and are hidden by `WH_GUIDANCE_DISABLED=1`.
- A failed fetch names the branch, the remote, its URL with credentials removed
  and git's first error line. It still warns and continues.
- `new` warns when `HARNESS_PACKAGE_MANAGER` is unknown, then skips the install
  as before.
- `merge` sends git's rebase, gate and fast-forward output to stderr.
- `install.sh` prints the source it installs from, with credentials removed from
  every printed URL. A failure shows a Detail row and one recovery command.
  PATH warnings (off `PATH`, or shadowed by another copy) always print, next
  steps are checked against the current directory, and the shell-integration
  and completion offers are real commands for your shell.

### Fixed
- `--no-color` works (it did nothing). `FORCE_COLOR` and `TERM=dumb` apply per
  stream, so piped output no longer takes its color from stderr's terminal.
- `gc --prune` honors `--dry-run`, in any order and as a global option.
- `gc --prune` exits 1 when a removal fails, reports
  `Removed X of Y worktrees. F failed.`, and gives the commands to inspect and
  unlock or force-remove the worktree (it exited 0).
- `gc`, `status`, `new` and `merge` outside a git repository print a message
  and exit 1 (`gc` exited 128 silently).
- A `gc` dirty or recency check that can't run keeps the worktree and says so.
- `gc` and `init` reject extra arguments.
- The `status` footer says "1 worktree". A failed compare or dirty check shows
  `?` and a warning; `--porcelain` is unchanged.
- A mistyped option to `new` or `launch` creates nothing.
- A failed copy, install or setup fails `new` with one error naming the
  worktree and branch left behind and the commands to remove them (a failed
  copy used to be ignored). It exits 1 with nothing on stdout.
- Ctrl+C, `TERM` or `HUP` while a worktree is being provisioned names the
  partial worktree and the commands to clean it up.
- `new --dry-run` no longer creates the parent directory.
- `launch --dry-run` on the main checkout reports the planned worktree and
  command and creates nothing (it used to fail).
- `new --dry-run` and `merge --dry-run` no longer fetch; they use the
  last-known remote ref.
- Fetches can't prompt for credentials or hang on a stalled connection. For
  ssh, `ConnectTimeout=10` and `BatchMode=yes` apply only when
  `GIT_SSH_COMMAND`, `GIT_SSH` and `core.sshCommand` are unset.
- `.harness.env` is written atomically, files matching a secret pattern are
  copied under umask 077, and a directory with a secret-like name keeps its
  execute bit.
- Glob characters in `HARNESS_AGENT` no longer expand.
- `merge` strips control characters from commit subjects, and a blocked
  fast-forward names the partial state with a quoted recovery command.
- `init` never overwrites an existing `.harnessrc`, even in a race.
- `doctor` flags a non-numeric `HARNESS_GC_IDLE_MIN` and shows bash's own error
  lines when `.harnessrc` fails to load.
- `install.sh` exits 2 on an unknown option or a stray argument instead of
  ignoring it and reinstalling.
- Under `curl | sh`, a `bin/worktree-harness` in the current directory is no
  longer installed.
- `install.sh` checks its source first and lists every missing path, and
  refuses to install over its own source checkout.
- `install.sh` stages the new tree and swaps it in by rename, so a failed copy,
  a failed swap or a cancel keeps the previous install, and a truncated
  download installs nothing.
- A relative `--prefix` or `WORKTREE_HARNESS_PREFIX` installs a working
  absolute link.
- A closed stdout or stderr no longer aborts an install.
- `docs/THREAT_MODEL.md` now covers the installer's clone and its temporary
  directory, and the network use of the install and setup commands you
  configure.
- The README sample output, the demo recording's text and the shell
  completions match the current commands and options.

### Deprecated
- The `create`, `run`, `land` and `prune` aliases warn once per run. Use `new`,
  `launch`, `merge` and `gc` (`gc --prune` to remove).
- `gc --force` warns and points to `gc --prune`. It still prunes, and help
  doesn't list it.

## [0.2.0]

### Added
- Shell completions for bash, zsh, and fish (installed by the Homebrew formula;
  shipped under `share/completions/` for the installer).
- Homebrew install: `brew install renchris/tap/worktree-harness`
  (tap: [renchris/homebrew-tap](https://github.com/renchris/homebrew-tap)), with
  a **bottled** formula so install pours a prebuilt package instead of building
  from source on supported platforms.
- Animated demo GIF in the README, plus a hosted
  [asciinema player](https://renchris.github.io/worktree-harness/) for crisp,
  selectable-text playback.
- `SECURITY.md` documenting the trust model and reporting process.

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

[Unreleased]: https://github.com/renchris/worktree-harness/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/renchris/worktree-harness/releases/tag/v0.2.0
[0.1.0]: https://github.com/renchris/worktree-harness/releases/tag/v0.1.0
