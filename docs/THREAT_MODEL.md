# Threat model

`worktree-harness` is a developer tool that runs in your own repositories on
your own machine. This documents what it trusts, what it protects, and what is
out of scope — so you can reason about running it and reading its code.

## Trust boundary

- **`.harnessrc` is sourced as bash.** Running `worktree-harness` in a repo
  executes that repo's `.harnessrc`, plus the install/setup commands it names.
  This is the same trust level as running `make`, an npm `postinstall`, `just`,
  or any tool with project-defined hooks — and the same model every comparable
  tool uses (worktrunk hooks, wtp `post_create`, uzi `devCommand`). **Only run
  worktree-harness in repositories you trust.** Don't run it in a freshly-cloned
  untrusted repo without reading its `.harnessrc` first.
- **No network beyond `git fetch`.** With `HARNESS_BASE_POLICY=origin` the tool
  runs a read-only `git fetch <remote> <branch>` to resolve the base. With
  `local` it does not touch the network at all. It never pushes.
- **No privilege escalation.** No sudo, no setuid. It writes only inside the
  repo, the configured worktree home, and `$PREFIX` at install time.

## What it protects

| Risk | Mitigation |
|---|---|
| One session's `git add -A` sweeping another's staged work | Per-worktree index — structurally impossible (see [DESIGN](DESIGN.md)) |
| Non-fast-forward clobber of the default branch | `merge` rebases, then checks ancestry; refuses anything but a true fast-forward |
| Accidental push to a stale/wrong remote | `merge` **never** pushes — landing is local-only |
| Semantically-broken code reaching the default branch | `HARNESS_MERGE_GATE` runs on the rebased tree before the fast-forward |
| Losing in-flight work to cleanup | `gc` keeps dirty/unmerged/busy/recent worktrees; **branches are always preserved** |
| Secrets world-readable in a copied env file | Copied `*.env*` files are `chmod 0600` |
| A failed isolation step running an agent un-isolated | `launch` fails **closed** — refuses to launch rather than silently fall back |

## Out of scope (non-threats)

- **Malicious repositories.** `.harnessrc` is trusted code, by design. This is a
  same-machine dev tool, not a sandbox.
- **Multi-user / server tenancy.** Worktrees share one object store and one set
  of refs; that is not a security boundary between users.
- **Secret management.** The tool *copies* the gitignored secret files you name;
  it does not vault or encrypt them. Keep them gitignored (they are, by
  definition).
- **Concurrent generation of shared derived state** (migration journals,
  lockfiles). Structural isolation does not cover semantic collisions there;
  they surface as a conflict or a failed gate, not silent corruption (see
  [DESIGN](DESIGN.md) → "The one edge").

## Reporting

Found a way to lose data or clobber a branch that the table above doesn't cover?
Open an issue with `worktree-harness doctor` output and a minimal repro. For
anything sensitive, contact the maintainer privately first.
