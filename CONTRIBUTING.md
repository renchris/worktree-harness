# Contributing

Thanks for your interest! `worktree-harness` stays small, focused, and
dependency-free on purpose — that constraint is the product.

## Principles

- **`git` + `bash` only.** No new runtime dependency. If a feature needs one, it
  almost certainly belongs in a `HARNESS_SETUP` hook in the user's project, not
  in the tool. See [`docs/DESIGN.md`](docs/DESIGN.md) → Non-goals.
- **bash 3.2-safe.** It must run on stock macOS `/bin/bash` (3.2.57). Avoid
  `declare -A`, `mapfile`/`readarray`, `[[ -v ]]`, and `${var^^}`/`${var,,}`.
  The suite's `bashism.bats` enforces this.
- **Fail closed, never silently.** A guard that can't do its job should refuse
  loudly, not pretend to succeed.

## Dev setup

```sh
# shellcheck:  brew install shellcheck   |   apt-get install shellcheck
shellcheck bin/worktree-harness lib/*.sh share/shell/bash.sh

# bats (vendored on demand — no install needed):
git clone --depth 1 https://github.com/bats-core/bats-core /tmp/bats
/tmp/bats/bin/bats test/
```

## Before opening a PR

- [ ] `shellcheck` is clean on the bash sources
- [ ] `bats test/` is green, with a test covering your change
- [ ] bash 3.2-safe (the `bashism.bats` guard passes)
- [ ] Docs updated (README / `docs/` / the `init` template) if behavior or
      config changed
- [ ] No new runtime dependency

## Layout

| Path | Responsibility |
|---|---|
| `bin/worktree-harness` | Dispatcher: global-flag parsing, sourcing, routing |
| `lib/common.sh` | Version, color, logging, prompts |
| `lib/compat.sh` | OS portability shims (macOS/BSD vs Linux/GNU) |
| `lib/config.sh` | `.harnessrc` loading, defaults, validation, base resolution |
| `lib/pm.sh` | Package-manager detection + frozen-lockfile install command |
| `lib/cmd_*.sh` | One file per command (`new`, `merge`, `gc`, `status`, `launch`, `init`, `doctor`) |
| `share/shell/*` | bash / zsh / fish integration snippets |
| `test/*.bats` | Test suite (`test/helper.bash` holds fixtures) |

## Commit messages

Conventional Commits, lowercase, no redundant verbs
(`feat: per-worktree ports`, not `feat: add per-worktree ports`).
