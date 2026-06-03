# worktree-harness

Run many parallel coding-agent sessions — Claude Code, Aider, Codex, whatever —
each in its own isolated **git worktree**, and fast-forward them back to your
default branch **safely**. Zero runtime dependencies beyond `git` and `bash`.

[![ci](https://github.com/renchris/worktree-harness/actions/workflows/ci.yml/badge.svg)](https://github.com/renchris/worktree-harness/actions/workflows/ci.yml)

![worktree-harness demo: new → status → merge → gc](docs/demo.gif)

```console
$ worktree-harness new add-auth
→ fetch origin main
→ git worktree add ~/.worktrees/myapp/add-auth -b add-auth origin/main
✓ copied 1 gitignored file(s)
→ install: pnpm install --frozen-lockfile
✓ ports offset by 1 → ~/.worktrees/myapp/add-auth/.harness.env
✓ worktree ready: ~/.worktrees/myapp/add-auth  (branch: add-auth)

# ...work in the worktree, commit, then:
$ worktree-harness merge        # rebase onto main, run your gate, fast-forward main. never pushes.
$ worktree-harness gc --prune   # reap merged + idle worktrees (your branches are kept)
```

---

## Why

Running several agents at once on one checkout is a footgun: they share one git
index, so one session's `git add -A` quietly sweeps another's staged files, and
they collide on dev/inspector ports. The fix is one idea:

> **Give each session its own git worktree.** Each worktree has its own index,
> HEAD, and working tree, so the staged-file collision is *physically
> impossible* — there's no shared staging area to clobber. No lock file, no
> daemon, no coordination. The isolation is structural.

`git` already gives you that. What it *doesn't* give you is the boring glue that
makes a fresh worktree actually runnable and a finished one safe to land:

- A fresh worktree has none of your gitignored runtime state — no `.env`, no
  `node_modules`, no local DB — and it'll fight other worktrees for ports.
- Landing a branch back is where people get hurt: a stray `git add -A`, a
  non-fast-forward clobber, an accidental push to a stale remote.

`worktree-harness` is that glue, and nothing more:

- **`new` / `launch`** — create a worktree off your base branch and make it
  runnable: copy declared gitignored files, run the right install command,
  assign non-colliding ports, run your setup.
- **`merge`** — rebase the branch onto the base, run a verify gate, and
  **fast-forward your local default branch**. It refuses anything that isn't a
  clean fast-forward, and it **never pushes**.
- **`gc`** — remove worktrees that are merged, clean, and idle. Your branches
  are always kept.

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full argument, including why
there is no lock and why a failed isolation step *refuses to launch* rather
than silently falling back.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh
```

Or from a checkout:

```sh
git clone https://github.com/renchris/worktree-harness && ./worktree-harness/install.sh
```

It installs to `~/.local` by default (override with `WORKTREE_HARNESS_PREFIX`):
files go under `~/.local/share/worktree-harness`, and the `worktree-harness`
command is symlinked into `~/.local/bin`. No sudo, no global state. To uninstall,
delete those two paths.

**Requirements:** `git` and `bash` ≥ 3.2 (i.e. stock macOS `/bin/bash`) — that's it.

## Quickstart

```sh
cd your-project
worktree-harness init          # scaffold a .harnessrc (detects your package manager)
$EDITOR .harnessrc             # tweak: which files to copy, ports, merge gate

worktree-harness new fix-123   # runnable worktree at ~/.worktrees/your-project/fix-123
cd ~/.worktrees/your-project/fix-123
source .harness.env            # if you configured ports
# ...run your agent, commit...

worktree-harness merge         # land it on local main (rebase + gate + ff; never pushes)
worktree-harness gc --prune    # tidy up
```

### Auto-isolating launcher (optional)

Make your agent command launch inside a fresh worktree automatically — from the
main checkout it isolates; from a linked worktree or outside a repo it runs in
place:

```sh
# in ~/.zshrc (or ~/.bashrc; fish supported too)
export WORKTREE_HARNESS_AGENTS="claude"   # space-separated; e.g. "claude aider"
source ~/.local/share/worktree-harness/share/shell/zsh.sh
```

Now typing `claude` in a project root spins up an isolated worktree and launches
the agent there. Override once with `WH_ISOLATION_SKIP=1 claude`.

## Configuration — `.harnessrc`

A `.harnessrc` in your repo root, committed so every worktree inherits it. It's
**sourced as bash** (zero parsing dependencies; arrays and comments for free).
Treat it like a `Makefile`: only run `worktree-harness` in repos you trust.
Scaffold one with `worktree-harness init`. Every key is optional.

| Key | Default | Meaning |
|---|---|---|
| `HARNESS_BASE_POLICY` | `origin` | `origin` = fetch and branch off `<remote>/<default>`; `local` = branch off the local default, never touch the network |
| `HARNESS_REMOTE` | `origin` | Remote used when policy is `origin` |
| `HARNESS_DEFAULT_BRANCH` | *(auto)* | Blank → auto-detect (`origin/HEAD`, then `main`/`master`) |
| `HARNESS_WORKTREE_HOME` | `$HOME/.worktrees` | Worktrees live at `<home>/<repo>/<branch>` |
| `HARNESS_COPY` | `()` | Gitignored files copied (not symlinked) into each worktree, e.g. `( ".env" ".env.local" )` |
| `HARNESS_PACKAGE_MANAGER` | `auto` | `auto` detects from the lockfile; or pin `pnpm`/`npm`/`yarn`/`bun`/`pip`/`poetry`/`uv`/`cargo`/`go`/`none` |
| `HARNESS_INSTALL` | `auto` | `auto` derives the frozen-lockfile command from the PM; `none`; or a literal command |
| `HARNESS_SETUP` | `()` | Commands run inside the worktree after install, e.g. `( "pnpm db:setup" )` |
| `HARNESS_PORTS` | `()` | `"NAME=BASE"` → `NAME=BASE+offset`, written to `<worktree>/.harness.env` |
| `HARNESS_MERGE_GATE` | `none` | Command that must pass before `merge` fast-forwards, e.g. `"pnpm typecheck"` |
| `HARNESS_AGENT` | `claude` | What `launch` execs inside the worktree |
| `HARNESS_GC_KEEP` | `()` | Worktree basenames `gc` must never reap |
| `HARNESS_GC_IDLE_MIN` | `30` | `gc` keeps worktrees touched more recently than this (minutes; `0` disables) |

> **origin vs. local.** The default (`origin`) is right for the common case: a
> team repo where `origin/main` is canonical. If your `origin` is a diverged
> fork and your **local** default branch is the source of truth (a solo,
> rarely-push workflow), set `HARNESS_BASE_POLICY="local"` and the tool branches
> and rebases off your local tip, never fetching. This is the case native
> `claude -w` silently mishandles.

See [`examples/`](examples/) for ready-to-copy configs (Node/pnpm, Python/uv,
and a multi-service setup).

## Commands

| Command | What it does |
|---|---|
| `new <branch>` | Create + provision a worktree off the base branch. `--dry-run` to preview. |
| `launch [-- <cmd…>]` | Create an auto-named worktree and exec your agent in it; in a linked worktree or outside a repo, exec in place. |
| `merge [--no-verify]` | Rebase the current worktree's branch onto the base, run the gate, fast-forward the local default branch. Never pushes. |
| `status [--porcelain]` | List worktrees: branch, ahead/behind, dirty, assigned ports. |
| `gc [--prune]` | Preview (default) or remove merged + clean + idle worktrees. Branches always preserved. |
| `init` | Scaffold a `.harnessrc` with your detected package manager. |
| `doctor` | Diagnose the environment and validate `.harnessrc`. |

Global flags: `-C <dir>` (run as if in `<dir>`), `--dry-run`, `--no-color`.

## How it compares

There's a healthy ecosystem here; `worktree-harness` deliberately owns the
*lifecycle-safety* corner the others leave open. (Comparison reflects public
behavior as of mid-2026; details change — corrections welcome.)

| | worktree-harness | [claude-squad] | [worktrunk] | native `claude -w` |
|---|:---:|:---:|:---:|:---:|
| Isolation via git worktrees | ✓ | ✓ (+tmux) | ✓ | ✓ |
| Provision: copy env, install, **ports** | ✓ | ✗ ([#260]) | ✓ | partial¹ |
| **Frozen-lockfile** install auto-detected | ✓ | ✗ | ✗ | ✗ |
| Safe merge-back: **ff-only + verify gate** | ✓ | ✗ (manual) | partial² | ✗ |
| **Never pushes** on merge | ✓ | ✗ (auto-push, [#122]) | n/a | n/a |
| **Diverged-origin / local-main** first-class | ✓ | ✗ | ✗ | ✗ ([#27947]³) |
| Runtime dependencies | git + bash | Go binary | Rust binary | Claude Code |
| Agent-agnostic | ✓ | ✓ | ✓ | Claude only |
| Headless / SSH / CI friendly | ✓ | ✓ | ✓ | partial |

¹ `.worktreeinclude` copies files (desktop; CLI parity tracked upstream) — no
ports/DB. ² `worktrunk merge` runs hooks but doesn't enforce fast-forward-only
or a typecheck gate. ³ native `--worktree` silently no-ops on non-GitHub remotes
and assumes origin is canonical.

If you want a polished TUI/GUI to *watch* many agents, reach for
[claude-squad]/[Conductor]. If you want a heavier config-driven Rust tool, see
[worktrunk]. `worktree-harness` is the small, dependency-free shell tool for the
safe-lifecycle path — especially if your local branch is canonical.

[claude-squad]: https://github.com/smtg-ai/claude-squad
[worktrunk]: https://github.com/max-sixty/worktrunk
[Conductor]: https://www.conductor.build/
[#260]: https://github.com/smtg-ai/claude-squad/issues/260
[#122]: https://github.com/smtg-ai/claude-squad/issues/122
[#27947]: https://github.com/anthropics/claude-code/issues/27947

## FAQ

**Does `merge` ever push?** No. It lands on your *local* default branch by
fast-forward and stops. Pushing stays an explicit `git push` you run when you
mean it.

**What if rebasing onto the base would conflict?** `merge` stops and tells you
exactly how to resolve and re-run, or abort. Your default branch is never
touched until a clean fast-forward is proven.

**Why is config bash and not YAML?** Zero dependencies — no `yq`, no fragile
pure-bash YAML parser. A sourced `.harnessrc` gives arrays and comments for
free. The trust model is identical to a `Makefile` or any tool that runs
project-defined hooks.

**Does it work with Aider / Codex / others?** Yes — set `HARNESS_AGENT` (or pass
`launch -- <cmd>`), and list multiple in `WORKTREE_HARNESS_AGENTS` for the shell
integration. Worktrees are agent-agnostic.

**Claude Code already has `--worktree` — why this?** Native `-w` creates the
worktree, but leaves provisioning (env, deps, ports, DB), merge-back, and the
diverged-origin case to you, and silently no-ops on non-GitHub remotes. This
fills exactly those gaps. See [`SKILL.md`](SKILL.md) for Claude Code integration.

## Contributing

Small, focused, dependency-free. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
`shellcheck` clean + `bats test/` green + bash-3.2-safe are the gates.

## License

[MIT](LICENSE) © Chris Ren
