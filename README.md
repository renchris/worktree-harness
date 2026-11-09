# worktree-harness

**Run many coding agents in parallel — each in its own git worktree, each fast-forwarded back to your default branch safely — with nothing on your machine but `git` and `bash`.** Claude Code, Aider, Codex, whatever; the worktrees don't care.

[![ci](https://github.com/renchris/worktree-harness/actions/workflows/ci.yml/badge.svg)](https://github.com/renchris/worktree-harness/actions/workflows/ci.yml)

![worktree-harness demo: new → status → merge → gc](docs/demo.gif)

▶ **[Watch the interactive player](https://renchris.github.io/worktree-harness/)** — crisp, selectable-text playback (asciinema).

```console
$ worktree-harness new add-auth
→ Fetching origin main…
→ Creating worktree ~/.worktrees/myapp/add-auth on branch add-auth from origin/main…
✓ copied 1 file
→ Installing dependencies: pnpm install --frozen-lockfile…
✓ ports offset by 1 → ~/.worktrees/myapp/add-auth/.harness.env
✓ worktree ready: ~/.worktrees/myapp/add-auth  (branch: add-auth)

# ...work in the worktree, commit, then:
$ worktree-harness merge        # rebase onto main, run your gate, fast-forward main. never pushes.
$ worktree-harness gc --prune   # reap merged + idle worktrees (your branches are kept)
```

Three agents, three branches, three clean fast-forwards onto your local `main` — and nothing pushed until you say so:

```
 time ──────────────────────────────────────────────────────►
 add-auth:   new·edit·commit──merge───────────────────────gc
 fix-123:        new·edit·commit────────merge─────────────gc
 refactor:           new·edit·commit──────────────merge───gc

 main:              A───────────B───────────────────C────►
                    ▲           ▲                    ▲
               ff-only      ff-only              ff-only      (never pushes)
```

---

## Running parallel agents on one checkout breaks in five specific ways

You're running more than one coding agent at once — Claude Code in one pane, Aider in another — against the same repo. On a single shared checkout, five concrete things go wrong:

- **One git index, shared.** One session's `git add -A` (or an agent committing "all changes") sweeps another session's half-staged work into the wrong commit.
- **Ports collide.** Two dev servers want `:3000`; two inspectors want `:9229`.
- **A fresh worktree won't run.** `git worktree add` gives you a tree with no `.env`, no `node_modules`, no local DB — it won't start without hand-wiring.
- **Landing the branch back is where the damage happens.** A non-fast-forward clobber of `main`, a "looked merged but never typechecked" regression, or an accidental push to a stale remote.
- **Existing tooling assumes `origin` is canonical** and silently no-ops on non-GitHub remotes — wrong for the solo / diverged-fork workflow where your *local* branch is the truth.

The fix is one idea — **give each session its own git worktree** — and four disciplines that follow from it. Each worktree has its own index, HEAD, and reflog, so the collision isn't *coordinated away*, it's *impossible*. `worktree-harness` is the small, dependency-free glue that makes that worktree runnable and safe to land — and nothing more.

## Isolation is structural, not cooperative

Each session gets its own worktree at `~/.worktrees/<repo>/<branch>`, with its own index, HEAD, and reflog, all backed by the one shared object store. The staged-file collision isn't prevented by a lock — there is no shared staging area to collide on, so it cannot happen.

```
 you, in N panes        (type `claude`, or `worktree-harness launch claude`)
 ┌───────────┬───────────┬───────────┐
 │  pane 1   │  pane 2   │  pane 3   │
 └─────┬─────┴─────┬─────┴─────┬─────┘
       │           │           │   from the MAIN checkout (.git is a dir) → isolate
       ▼           ▼           ▼
 ┌───────────┬───────────┬───────────┐
 │  wt: A    │  wt: B    │  wt: C    │  separate working tree
 │ branch A  │ branch B  │ branch C  │  separate index · HEAD · reflog
 │ base:main │ base:main │ base:main │  branched off the base at creation
 │ own ports │ own ports │ own ports │  .env copied · deps installed · .harness.env
 └─────┬─────┴─────┬─────┴─────┬─────┘
       └───────────┼───────────┘
                   ▼
        one shared  <repo>/.git    (objects + refs; content-addressed, atomic)
        refs/heads/{ main, A, B, C }
```

That is why there is **no lock and no daemon**. The only shared mutable thing left is `refs/heads/*`, and git already serializes ref updates with a per-ref lock held for microseconds. (An earlier version of this idea carried a session-long writer lock; it blocked other sessions for zero safety benefit — the worktrees had already removed the collision it guarded — so it was deleted.)

The launcher follows the same principle: from your main checkout it isolates *before* running your agent, and if it can't, it **refuses to launch** rather than run un-isolated.

```mermaid
flowchart TD
    A[type claude / worktree-harness launch] --> B{in a git repo?}
    B -- no --> P[exec in place — nothing to isolate]
    B -- linked worktree --> P2[exec in place — already isolated, never nest]
    B -- MAIN checkout --> C[create a worktree off the base, provision, exec there]
    C -- success --> D[cd worktree → exec the agent]
    C -- FAILURE --> R[REFUSE to launch, exit ≠ 0 — never runs un-isolated]
```

A guard that silently does nothing when it fails is worse than no guard, because you *think* you're protected. Isolation here fails closed: no worktree, no launch (`WH_ISOLATION_SKIP=1` opts out explicitly).

## A fresh worktree arrives runnable

`git worktree add` hands you an empty tree; `new` makes it actually work, in the order you'd do it by hand:

- **Copies your gitignored state** — the files you declare in `HARNESS_COPY` (`.env`, `.env.local`, …), with `chmod 0600` on anything matching `*.env*` so secrets aren't world-readable.
- **Runs the frozen-lockfile install** for your package manager, auto-detected from the lockfile: pnpm, npm, yarn (classic + berry), bun, uv, poetry, pipenv, pip, cargo, go.
- **Assigns non-colliding ports** by offset and writes them to `<worktree>/.harness.env` — `source` it and your dev server and inspector won't fight the other worktrees. Each worktree gets the smallest free offset, so a removed worktree's ports are reused.
- **Runs your setup** — whatever you put in `HARNESS_SETUP` (e.g. `pnpm db:setup`).

`new` prints the worktree path on **stdout** (everything else is stderr), so you can capture it: `wt="$(worktree-harness new feat)"`. If a copy, install or setup step fails, `new` exits 1, prints nothing on stdout, and names the worktree and branch it left behind with the commands to remove them.

## Landing back is fast-forward-only, gated, and never pushed

`merge`, run from inside the worktree, makes the one boring, safe move:

```mermaid
flowchart TD
    M[worktree-harness merge — from inside the worktree] --> A{working tree clean?}
    A -- no --> A1[stop: commit explicit paths first]
    A -- yes --> B{already landed?}
    B -- yes --> B1[done — nothing to do]
    B -- no --> C[rebase the branch onto the base]
    C -- conflict git cannot auto-resolve --> C1[stop: how to resolve / abort — base untouched]
    C -- clean --> D{is default branch an ancestor of the rebased branch?}
    D -- no --> D1[REFUSE — base diverged; the move would not be a fast-forward]
    D -- yes --> E[run HARNESS_MERGE_GATE on the rebased tree]
    E -- fails --> E1[stop — base NOT updated]
    E -- passes --> F[fast-forward the LOCAL default branch to the branch tip]
    F --> G[done — NEVER pushes]
```

Three properties are deliberate:

1. **Fast-forward only.** The branch is rebased onto the base, then an ancestry check confirms the move is a true fast-forward before anything is touched. A diverged base is refused loudly, not forced.
2. **Gated.** A clean *textual* rebase can still be *semantically* broken, so `HARNESS_MERGE_GATE` (your typecheck/test command) runs on the rebased tree *before* the default branch moves — catching breakage a plain merge would hide.
3. **Never pushes.** Landing is local; pushing stays a separate, explicit `git push` you run when you mean it. (This is a direct answer to a real footgun in a popular alternative, whose "checkout" auto-pushes to the remote.)

Concurrent merge-backs serialize naturally — each is a fast-forward of one ref, ordered by git's per-ref lock in microseconds; a non-fast-forward is rejected, so the loser of a race just re-rebases and retries. Cleanup is conservative by construction: `gc` removes a worktree only if it's merged **and** clean **and** idle **and** not open by a live process — anything else is kept with a printed reason, and **your branches are always preserved.**

## The only thing it adds to your machine is git and bash

- **Zero runtime dependencies.** No daemon, no Go or Rust binary, no YAML parser. `.harnessrc` is sourced as bash — arrays and comments for free — and the trust model is identical to a `Makefile`: run it only in repos you trust.
- **Agent-agnostic.** Claude Code, Aider, Codex, anything else — set `HARNESS_AGENT` or pass `launch -- <cmd>`, and list several in `WORKTREE_HARNESS_AGENTS` for the shell integration.
- **First-class for the local-canonical workflow.** When `origin` is a stale fork and your *local* default branch is the truth, set `HARNESS_BASE_POLICY=local`: the tool branches and rebases off your local tip and never touches the network — exactly the case native `claude -w` silently mishandles ([#27947](https://github.com/anthropics/claude-code/issues/27947)).

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full argument and [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) for what it trusts and protects.

## Install

**Homebrew** (macOS / Linux):

```sh
brew install renchris/tap/worktree-harness
```

**Or** the zero-dependency installer:

```sh
curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh
```

Or download it first and run it only if the download succeeded (a lone `install.sh` clones the repository, like the piped form):

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh && sh install.sh
```

Or from a checkout:

```sh
git clone https://github.com/renchris/worktree-harness && ./worktree-harness/install.sh
```

It installs to `~/.local` by default: files go under `~/.local/share/worktree-harness`, and the `worktree-harness` command is symlinked into `~/.local/bin`. No sudo, no global state. Run as a file from a checkout, it installs that checkout; otherwise it clones the repository into a temporary directory and removes it when done. A failed or cancelled install keeps the previous one.

**Requirements:** `git` and `bash` ≥ 3.2 (i.e. stock macOS `/bin/bash`) — that's it.

#### Installer options and variables

`sh install.sh --help` prints these and does nothing else. Under `curl | sh`, pass options after `sh -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh -s -- --prefix <DIR>
```

| Option or variable | Meaning |
|---|---|
| `-h`, `--help` | Print usage and do nothing else (so does `help` as the first argument). |
| `--version` | Print the installer's version without cloning anything. With `--json`, prints `{"version":"<v>"}`. |
| `--json` | Print one JSON document on stdout and nothing on stderr (also `--json=true\|false`, `--no-json`). See below. |
| `--prefix <DIR>`, `--prefix=<DIR>` | Install under `<DIR>`. A relative `<DIR>` is taken from the current directory. An empty value exits 2. |
| `WORKTREE_HARNESS_PREFIX` | Install location when `--prefix` isn't given. |
| `WORKTREE_HARNESS_REPO` | Git URL to clone when not run from a checkout (default `https://github.com/renchris/worktree-harness.git`). Point it only at a source you trust: the cloned code is what gets installed. |
| `WORKTREE_HARNESS_REF` | Branch or tag to clone. Unset, the installer tracks `main`. |
| `WH_GUIDANCE_DISABLED` | When not empty, hides the next steps and offers. PATH warnings still print. |
| `CI` | When not empty, hides the shell-integration and completion offers. |

The location is `--prefix`, then `WORKTREE_HARNESS_PREFIX`, then `~/.local`; with `HOME` unset and no prefix, the installer exits 2 and names `--prefix`. For every variable, empty means unset. Each is read once per run and never saved, so re-running without your custom prefix installs a second copy under `~/.local`; the uninstall, shell-integration and completion paths below also use your prefix in place of `~/.local`. Unknown options and stray arguments exit 2 and change nothing.

`WORKTREE_HARNESS_*` names are environment variables read by `install.sh` and the shell integration. `HARNESS_*` names are `.harnessrc` settings; exporting one in your shell has no effect.

`install.sh` writes its progress, receipt and next steps to stderr. When captured or piped, or when `CI` is set, stdout is one line, the installed command's path, so `p=$(sh install.sh)` gives you the command to run. An interactive terminal shows only the receipt.

For scripts, `sh install.sh --json` (piped: `curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh -s -- --json`) prints one document, indented on a terminal and on one line when piped:

```json
{"install":{"path":"<prefix>/bin/worktree-harness","version":"0.2.0"},"outcome":"installed","next":[{"command":"worktree-harness doctor","argv":["worktree-harness","doctor"]}]}
```

`outcome` is `installed`, `replaced` or `unchanged`; `version` is `null` when unknown; `next` uses the absolute path when the bin directory isn't on `PATH`; a `warnings` array (`reason` `not_on_path` or `shadowed`, plus a `message`) appears only when there are warnings. A failure prints nothing on stdout and exactly one line on stderr, `{"status":"error","reason":"<reason>","message":"…"}`, with the same exit code as without `--json`; the reason is one of `invalid_arguments`, `unknown_option`, `conflict`, `clone_failed`, `internal_error` or `canceled`. Under `--json`, git never prompts for credentials, and a prefix containing a control character is refused before anything is written.

#### Upgrade

Re-run the installer with the same prefix. It installs the tip of `main` unless `WORKTREE_HARNESS_REF` pins a tag, and its receipt names the version and commit (or says `already installed`). Only the latest released tag receives fixes ([`SECURITY.md`](SECURITY.md)); to stay on a release, pin it:

```sh
curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | WORKTREE_HARNESS_REF=v0.2.0 sh
```

Homebrew users run `brew upgrade worktree-harness`.

#### Uninstall

```sh
rm -rf -- ~/.local/share/worktree-harness ~/.local/bin/worktree-harness
```

That removes only the installer's two paths, not the rest of `~/.local/bin`; with a custom prefix, use `<DIR>/share/worktree-harness` and `<DIR>/bin/worktree-harness`. Then delete any shell-integration or completion lines you added. For a Homebrew install, run `brew uninstall worktree-harness`.

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
# in ~/.zshrc
export WORKTREE_HARNESS_AGENTS="claude"   # space-separated; e.g. "claude aider"
source ~/.local/share/worktree-harness/share/shell/zsh.sh
```

For bash, put the same `export` in `~/.bashrc` and source `share/shell/bash.sh`
instead. For fish, in `~/.config/fish/config.fish`:

```fish
set -gx WORKTREE_HARNESS_AGENTS claude        # e.g. claude aider
source ~/.local/share/worktree-harness/share/shell/fish.fish
```

Source it after `worktree-harness` is on your `PATH`, and with a custom prefix
use `<DIR>/share/worktree-harness/...` in place of
`~/.local/share/worktree-harness/...`. The installer prints the line for your
shell with the real path.

Now typing `claude` in a project root spins up an isolated worktree and launches
the agent there. Override once with `WH_ISOLATION_SKIP=1 claude`.

### Shell completions

The Homebrew formula installs bash, zsh, and fish completions automatically. With
the `curl` installer they ship under
`~/.local/share/worktree-harness/share/completions/`; the installer prints the
step for your shell:

```sh
# bash, in ~/.bashrc
source ~/.local/share/worktree-harness/share/completions/worktree-harness.bash
# zsh, in ~/.zshrc, before compinit
fpath=(~/.local/share/worktree-harness/share/completions $fpath)
# fish, once
cp ~/.local/share/worktree-harness/share/completions/worktree-harness.fish ~/.config/fish/completions/
```

## Configure once in `.harnessrc`

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
| `HARNESS_PACKAGE_MANAGER` | `auto` | `auto` detects from the lockfile; or pin `pnpm`/`npm`/`yarn`/`bun`/`pip`/`pipenv`/`poetry`/`uv`/`cargo`/`go`/`none`. Any other value is a warning, and `new` skips the install |
| `HARNESS_INSTALL` | `auto` | `auto` derives the frozen-lockfile command from the PM; `none`; or a literal command |
| `HARNESS_SETUP` | `()` | Commands run inside the worktree after install, e.g. `( "pnpm db:setup" )` |
| `HARNESS_PORTS` | `()` | `"NAME=BASE"` → `NAME=BASE+offset`, written to `<worktree>/.harness.env`. `NAME` is a shell identifier and `BASE` is digits |
| `HARNESS_MERGE_GATE` | `none` | Command that must pass before `merge` fast-forwards, e.g. `"pnpm typecheck"` |
| `HARNESS_AGENT` | `claude` | What `launch` execs inside the worktree |
| `HARNESS_BRANCH_PREFIX` | `wt` | Prefix of the branches `launch` names for you: `<prefix>-<HHMMSS>-<pid>` |
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

`worktree-harness doctor` checks these settings and exits with the number of
blocking issues it found (0 means none).

### Environment variables

These apply to one run and are not `.harnessrc` settings (exporting a
`HARNESS_*` name in your shell has no effect).

| Variable | Effect |
|---|---|
| `WH_NO_FETCH=1` | `new`, `launch` and `merge` use the last-known remote ref instead of fetching. `--dry-run` never fetches |
| `WH_ISOLATION_SKIP=1` | `launch` (and the shell integration) runs in place on the main checkout, with no worktree |
| `WH_DRY_RUN=1` | Same as `--dry-run` |
| `WH_NO_COLOR=1`, `NO_COLOR` | Turn off color. `FORCE_COLOR` turns it on when output isn't a terminal; `--no-color` beats `NO_COLOR`, which beats `FORCE_COLOR` |
| `WH_GUIDANCE_DISABLED=1` | Hides optional next steps and offers, in the CLI and `install.sh`. Required warnings still print |

The `WH_*` switches are on at `1` (`WH_GUIDANCE_DISABLED` at any value that
isn't empty); empty or unset means off.

## Commands

| Command | What it does |
|---|---|
| `new <BRANCH>` | Create + provision a worktree off the base branch. `--dry-run` to preview. |
| `launch [-- <COMMAND> [<ARG>]...]` | Create an auto-named worktree and exec your agent in it; in a linked worktree or outside a repo, exec in place. |
| `merge [--no-verify]` | Rebase the current worktree's branch onto the base, run the gate, fast-forward the local default branch. Never pushes. |
| `status [--porcelain\|--json]` | List worktrees: branch, ahead/behind, dirty, assigned ports. `--json --fields <FIELDS>` keeps only the keys you name. |
| `gc [--prune] [--dry-run]` | Preview (default) or remove merged + clean + idle worktrees. Branches always preserved; removing a worktree deletes its ignored files such as `.env`. |
| `init` | Scaffold a `.harnessrc` with your detected package manager. Never overwrites one. |
| `doctor` | Diagnose the environment and validate `.harnessrc`. |
| `help [<COMMAND>] [--json]` | Print the overview, or one command's help (same as `<COMMAND> --help`). `--json` prints it as a document. |
| `help --all [--json]` | Print every command's help; `--json` prints one document per command. |
| `help search <QUERY> [--json]` | Find commands whose name, summary, options or examples contain `<QUERY>`. |

Global options: `--cwd <DIR>` (run as if started in `<DIR>`), `--dry-run`, `--no-color`, `-v`/`--version`. They work before or after the command.

Exit codes: 0 success; 1 error or usage error; 2 `merge` rebase conflict; 64 unknown command; `doctor` exits with the number of blocking issues; `launch` passes through its command's exit code.

### Scripting

Each command keeps stdout for its result and sends progress, warnings and errors to stderr:

| Command | Stdout |
|---|---|
| `new` | The worktree path (also with `--dry-run`) |
| `merge` | The landed commit's full SHA, also when the branch had already landed; nothing with `--dry-run` |
| `init` | The new `.harnessrc` path |
| `gc --prune` | The removed paths, one per line, only when every removal succeeded |
| `status --porcelain` | Tab-separated rows: kind, branch, `+ahead/-behind`, ports, path |
| `status --json` | One document: `worktrees[]` of `{kind, branch, dirty, ahead, behind, ports, path}` (`kind` is `main` or `linked`; `ahead` and `behind` are `null` for the main checkout, and any of `dirty`, `ahead` and `behind` is `null` when git couldn't answer; `ports` is keyed by name) and `pagination: {next: null}` |

At an interactive terminal, `merge` and `init` show a readable receipt in place of the bare value, and `gc --prune` keeps its paths off stdout. Piped `status` with neither option prints tab-separated rows with a header (`KIND`, `BRANCH`, `DIRTY`, `AHEAD`, `BEHIND`, `PORTS`, `PATH`) and puts the summary line on stderr; scripts should use `--porcelain` or `--json`. A `--json` failure is one JSON line on stderr.

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
